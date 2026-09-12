import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../api/chat_tools_api.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/media.dart';
import '../../core/media/pick_image.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../ui/widgets.dart';
import 'overlay_canvas.dart';
import 'post_media.dart';

/// الحد الأقصى للفيديو والتسجيل الصوتي في منشور الخريطة.
const int kPostVideoMaxBytes = 25 * 1024 * 1024;
const Duration kPostVoiceMax = Duration(seconds: 60);

/// ألوان النص والخلفيات المتاحة في المحرّر.
const _textColors = ['#FFFFFF', '#111111', '#FFD54F', '#FF5252', '#69F0AE', '#40C4FF', '#FF80AB', '#0A6E78'];
const _bgColors = ['#0A6E78', '#BF3A1E', '#5A4200', '#1F1F2B', '#2E7D32', '#6A1B9A', '#0D47A1', '#37474F'];
const _stickers = ['🔥', '❤️', '😍', '😂', '👏', '🎉', '✨', '⭐', '💯', '📍', '🛒', '🏷️', '💰', '🎁', '☕', '🍔', '🍕', '🍰', '🚗', '🏨', '🎬', '🎵', '📸', '🏖️', '🕌', '🌙', '☀️', '🌴', '⚡', '🚀', '💼', '📈', '🤝', '📞', '💬', '✅', '🆕', '🆓', '🔖', '👀'];

/// محرّر منشور الخريطة على طريقة سناب شات: اختر صورة أو فيديو قصير أو تسجيل صوتي أو نص، ثم أضف نصوصاً وملصقات
/// تُسحب وتُكبَّر بالإصبع، وحقولاً احترافية اختيارية (نوع المنشور، عنوان، سعر، زر إجراء، مدة الظهور)، ثم انشر.
class PostComposerPage extends ConsumerStatefulWidget {
  final double lat, lng;
  final String? placeName;
  final MapPost? edit;
  const PostComposerPage({super.key, required this.lat, required this.lng, this.placeName, this.edit});

  static Future<MapPost?> open(BuildContext context, {required double lat, required double lng, String? placeName, MapPost? edit}) =>
      Navigator.of(context).push<MapPost>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PostComposerPage(lat: lat, lng: lng, placeName: placeName, edit: edit)));

  @override
  ConsumerState<PostComposerPage> createState() => _PostComposerPageState();
}

class _PostComposerPageState extends ConsumerState<PostComposerPage> {
  late String? kind = widget.edit?.kind;
  Uint8List? bytes;
  String? mime, fileName;
  late String? mediaUrl = widget.edit?.mediaUrl;
  late int? durationSec = widget.edit?.durationSec;
  late String bg = widget.edit?.bg ?? '#0A6E78';
  late List<PostOverlay> overlays = List.of(widget.edit?.overlays ?? const <PostOverlay>[]);
  int? selected;
  /// الطبقة النصية قيد الكتابة المباشرة على اللوحة (بلا نافذة منفصلة)
  int? editing;
  final _inlineCtl = TextEditingController();
  final _inlineFocus = FocusNode();
  late final caption = TextEditingController(text: widget.edit?.caption ?? '');
  late final title = TextEditingController(text: widget.edit?.title ?? '');
  late final price = TextEditingController(text: widget.edit?.price == null ? '' : _priceText(widget.edit!.price!));
  late final ctaValue = TextEditingController(text: widget.edit?.cta?.value ?? '');
  late final ctaLabel = TextEditingController(text: widget.edit?.cta?.label ?? '');
  late final place = TextEditingController(text: widget.edit?.placeName ?? widget.placeName ?? '');
  late String tag = widget.edit?.tag ?? 'moment';
  late String? ctaType = widget.edit?.cta?.type;
  int ttl = 24;
  late bool pro = widget.edit != null && (widget.edit!.tag != 'moment' || widget.edit!.cta != null || widget.edit!.price != null);
  bool busy = false;
  // التسجيل الصوتي
  VoiceRecorder? _webRec;
  final _nativeRec = AudioRecorder();
  Timer? _recTimer;
  int _recSec = 0;
  bool recording = false;

  static String _priceText(int h) => h % 100 == 0 ? '${h ~/ 100}' : (h / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _recTimer?.cancel();
    _webRec?.cancel();
    _nativeRec.dispose();
    caption.dispose();
    title.dispose();
    price.dispose();
    ctaValue.dispose();
    ctaLabel.dispose();
    place.dispose();
    _inlineCtl.dispose();
    _inlineFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- اختيار الوسائط
  Future<void> _pickImage({bool camera = false}) async {
    final img = await pickImage(camera: camera);
    if (img == null || !mounted) return;
    setState(() {
      kind = 'image';
      bytes = img.bytes;
      mime = img.mime;
      fileName = img.name;
    });
  }

  Future<void> _pickVideo() async {
    try {
      Uint8List? b;
      String? m, n;
      if (kIsWeb && WebMedia.available) {
        final v = await WebMedia.pick('video');
        if (v == null) return;
        b = v.bytes;
        m = v.mime;
        n = v.name;
      } else {
        final x = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
        if (x == null) return;
        b = await x.readAsBytes();
        m = x.mimeType ?? 'video/mp4';
        n = x.name;
      }
      if (b.length > kPostVideoMaxBytes) {
        if (mounted) toast(context, 'الفيديو أكبر من 25 م.ب؛ اختر مقطعاً أقصر (حتى 30 ثانية)', error: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        kind = 'video';
        bytes = b;
        mime = m;
        fileName = n;
      });
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (kIsWeb && WebMedia.available) {
        _webRec = VoiceRecorder();
        await _webRec!.start();
      } else {
        if (!await _nativeRec.hasPermission()) {
          if (mounted) toast(context, 'اسمح بالوصول إلى الميكروفون أولاً', error: true);
          return;
        }
        await _nativeRec.start(const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 48000, numChannels: 1), path: '');
      }
      setState(() {
        recording = true;
        _recSec = 0;
      });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSec++);
        if (_recSec >= kPostVoiceMax.inSeconds) _stopRecording(keep: true);
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر بدء التسجيل: $e', error: true);
    }
  }

  Future<void> _stopRecording({required bool keep}) async {
    _recTimer?.cancel();
    if (!recording) return;
    setState(() => recording = false);
    try {
      Uint8List? b;
      String? m;
      if (kIsWeb && _webRec != null) {
        final rec = _webRec!;
        _webRec = null;
        if (!keep) {
          await rec.cancel();
          return;
        }
        final r = await rec.stop();
        if (r != null) {
          b = r.bytes;
          m = r.mime;
        }
      } else {
        if (!keep) {
          await _nativeRec.cancel();
          return;
        }
        final path = await _nativeRec.stop();
        if (path != null) {
          b = await XFile(path).readAsBytes();
          m = path.endsWith('.m4a') ? 'audio/mp4' : 'audio/ogg';
        }
      }
      if (b == null || _recSec < 1) {
        if (mounted) toast(context, 'التسجيل قصير جداً');
        return;
      }
      if (!mounted) return;
      setState(() {
        kind = 'audio';
        bytes = b;
        mime = m;
        fileName = 'voice.${m == 'audio/mp4' ? 'm4a' : m == 'audio/ogg' ? 'ogg' : 'weba'}';
        durationSec = _recSec;
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر حفظ التسجيل: $e', error: true);
    }
  }

  // ---------------------------------------------------------------- الطبقات
  void _addOverlay(PostOverlay o) => setState(() {
        overlays = [...overlays, o];
        selected = overlays.length - 1;
      });

  /// يبدأ كتابة نص مباشرة على اللوحة: طبقة جديدة في الوسط أو تعديل طبقة قائمة.
  void _startText({int? index}) {
    if (editing != null) _commitText();
    setState(() {
      var i = index;
      if (i == null) {
        overlays = [
          ...overlays,
          PostOverlay(type: 'text', text: '', x: .5, y: overlays.isEmpty ? .5 : (.35 + overlays.length * .08).clamp(.2, .85), scale: kind == 'text' && overlays.isEmpty ? 1.5 : 1.0),
        ];
        i = overlays.length - 1;
      }
      editing = i;
      selected = i;
      _inlineCtl.text = overlays[i].text;
      _inlineCtl.selection = TextSelection.collapsed(offset: _inlineCtl.text.length);
    });
    _inlineFocus.requestFocus();
  }

  /// ينهي الكتابة المباشرة: يحفظ النص أو يزيل الطبقة إن بقيت فارغة.
  void _commitText() {
    final i = editing;
    if (i == null) return;
    final text = _inlineCtl.text.trim();
    setState(() {
      if (text.isEmpty) {
        overlays = [...overlays]..removeAt(i);
        selected = null;
      } else {
        overlays[i] = overlays[i].copyWith(text: text);
        selected = i;
      }
      editing = null;
    });
    _inlineFocus.unfocus();
  }

  void _setEditing({String? color, String? bg, bool clearBg = false, double? scale, String? align}) {
    final i = editing;
    if (i == null) return;
    setState(() => overlays[i] = overlays[i].copyWith(color: color, bg: bg, clearBg: clearBg, scale: scale, align: align));
  }

  /// حقل الكتابة فوق اللوحة بنفس مظهر الطبقة النهائية (الحجم واللون والخلفية الاختيارية).
  Widget _inlineEditor(double w, double h) {
    final i = editing!;
    final o = overlays[i];
    final size = w * 0.065 * o.scale;
    final color = colorFromHex(o.color);
    final bgc = o.bg == null ? null : colorFromHex(o.bg);
    final style = TextStyle(
      color: color, fontSize: size, height: 1.25, fontWeight: FontWeight.w800,
      shadows: bgc == null ? [const Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))] : null,
    );
    Widget field = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w * .85, minWidth: size * 3),
      child: IntrinsicWidth(
        child: TextField(
          key: const ValueKey('inline-text'),
          controller: _inlineCtl,
          focusNode: _inlineFocus,
          autofocus: true,
          maxLines: null,
          maxLength: 140,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          textInputAction: TextInputAction.done,
          textAlign: switch (o.align) { 'start' => TextAlign.start, 'end' => TextAlign.end, _ => TextAlign.center },
          style: style,
          cursorColor: color,
          decoration: InputDecoration.collapsed(hintText: 'اكتب هنا…', hintStyle: style.copyWith(color: color.withValues(alpha: .45))),
          onChanged: (v) => setState(() => overlays[i] = overlays[i].copyWith(text: v)),
          onSubmitted: (_) => _commitText(),
        ),
      ),
    );
    if (bgc != null) {
      field = Container(padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: size * .25), decoration: BoxDecoration(color: bgc, borderRadius: BorderRadius.circular(size * .5)), child: field);
    }
    return Positioned(
      left: o.x * w, top: o.y * h,
      child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.rotate(angle: o.rot, child: field)),
    );
  }

  /// شريط أدوات النص أثناء الكتابة: اللون، خلفية اختيارية، الحجم، المحاذاة، وإنهاء.
  Widget _inlineToolbar() {
    final o = overlays[editing!];
    final light = colorFromHex(o.color).computeLuminance() > .5;
    final nextAlign = switch (o.align) { 'center' => 'start', 'start' => 'end', _ => 'center' };
    final alignIcon = switch (o.align) { 'start' => Icons.format_align_right_rounded, 'end' => Icons.format_align_left_rounded, _ => Icons.format_align_center_rounded };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final c in _textColors) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _swatch(c, o.color == c, () => _setEditing(color: c)))]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _mini(o.bg == null ? Icons.format_color_fill_outlined : Icons.format_color_reset_outlined, o.bg == null ? 'خلفية' : 'بلا خلفية',
              () => o.bg == null ? _setEditing(bg: light ? '#000000AA' : '#FFFFFFDD') : _setEditing(clearBg: true)),
          _mini(Icons.text_decrease_rounded, 'أصغر', () => _setEditing(scale: (o.scale - .2).clamp(.5, 4.0))),
          _mini(Icons.text_increase_rounded, 'أكبر', () => _setEditing(scale: (o.scale + .2).clamp(.5, 4.0))),
          _mini(alignIcon, 'محاذاة', () => _setEditing(align: nextAlign)),
          const Spacer(),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(56, 36), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: _commitText, child: const Text('تم')),
        ]),
      ]),
    );
  }

  Widget _mini(IconData icon, String label, VoidCallback onTap) => Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Icon(icon, color: Colors.white, size: 22)),
        ),
      );

  /// منتقي لون الخلفية العامة للمنشور النصي: ألوان جاهزة أو درجة وتشبّع وإضاءة.
  Future<void> _bgPicker() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1C1F24),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (_) => _ColorPickerSheet(initial: bg, onPick: (hex) => setState(() => bg = hex)),
      );

  Widget _swatch(String? hex, bool on, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: hex == null ? Colors.transparent : colorFromHex(hex), shape: BoxShape.circle, border: Border.all(color: on ? Joy.sun : Colors.white30, width: on ? 3 : 1.5)),
          child: hex == null ? const Icon(Icons.block_rounded, size: 16, color: Colors.white54) : null,
        ),
      );

  Future<void> _stickerSheet() async {
    final s = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1F24),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ملصقات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _stickers)
                InkWell(onTap: () => Navigator.pop(ctx, e), borderRadius: BorderRadius.circular(12), child: SizedBox(width: 48, height: 48, child: Center(child: Text(e, style: const TextStyle(fontSize: 30))))),
            ]),
          ]),
        ),
      ),
    );
    if (s == null || !mounted) return;
    _addOverlay(PostOverlay(type: 'sticker', text: s, x: .5 + (overlays.length % 3 - 1) * .15, y: .55, scale: 1.2));
  }

  // ---------------------------------------------------------------- النشر
  Map<String, dynamic> _fields() {
    final p = price.text.trim().replaceAll('،', '.');
    final cta = ctaType == null || (ctaType != 'chat' && ctaValue.text.trim().isEmpty) ? null : {'type': ctaType, 'value': ctaValue.text.trim(), 'label': ctaLabel.text.trim()};
    return {
      'caption': caption.text.trim(), 'overlays': [for (final o in overlays) o.toJson()], 'bg': bg, 'placeName': place.text.trim(),
      'tag': pro ? tag : 'moment', 'title': pro ? title.text.trim() : '', 'price': pro && p.isNotEmpty ? ((double.tryParse(p) ?? 0) * 100).round() : null, 'cta': pro ? cta : null, 'ttlHours': ttl,
    };
  }

  Future<void> _publish() async {
    if (kind == null) return;
    if (kind == 'text' && caption.text.trim().isEmpty && !overlays.any((o) => !o.isSticker)) {
      toast(context, 'أضف نصاً أولاً (زر Aa) أو تعليقاً', error: true);
      return;
    }
    if (pro && ctaType == 'link' && ctaValue.text.trim().isNotEmpty && !ctaValue.text.trim().startsWith('http')) {
      toast(context, 'الرابط يجب أن يبدأ بـ https://', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final api = ref.read(apiClientProvider);
      var url = mediaUrl;
      if (bytes != null) url = (await api.uploadMedia(bytes!, contentType: mime ?? 'application/octet-stream', fileName: fileName)).url;
      final MapPost post;
      if (widget.edit != null) {
        post = await api.updatePost(widget.edit!.id, {..._fields(), if (bytes != null) 'mediaUrl': url});
      } else {
        post = await api.createPost({'kind': kind, 'mediaUrl': url, 'lat': widget.lat, 'lng': widget.lng, 'durationSec': durationSec, ..._fields()});
      }
      invalidatePosts(ref);
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, e.toString().contains('suspended') ? 'حسابك موقوف ولا يمكنه النشر' : e.toString(), error: true);
      }
    }
  }

  // ---------------------------------------------------------------- البناء
  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: const Color(0xFF0E1013),
          body: SafeArea(child: kind == null ? _pickStage() : _editStage()),
        ),
      );

  Widget _pickStage() {
    final me = ref.read(appStateProvider).user;
    return Column(children: [
      Row(children: [
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        Expanded(child: Text(widget.edit == null ? 'منشور جديد على الخريطة' : 'تعديل المنشور', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text('${me?.nickname ?? ''} · ${place.text.isNotEmpty ? place.text : 'عند هذه النقطة'}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
      ),
      if (recording) ...[
        const Spacer(),
        const Icon(Icons.mic_rounded, size: 72, color: Joy.sun),
        const SizedBox(height: 10),
        Text('${_recSec ~/ 60}:${(_recSec % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
        const Text('يُسجَّل الآن… حتى دقيقة واحدة', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(onPressed: () => _stopRecording(keep: false), icon: const Icon(Icons.delete_outline_rounded), label: const Text('إلغاء')),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: () => _stopRecording(keep: true), icon: const Icon(Icons.stop_rounded), label: const Text('إيقاف واستخدام')),
        ]),
        const Spacer(),
      ] else
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            _kindTile(Icons.photo_camera_rounded, 'التقط صورة', 'من الكاميرا مباشرة', () => _pickImage(camera: true)),
            _kindTile(Icons.photo_library_rounded, 'صورة من المعرض', 'ثم أضف نصوصاً وملصقات', _pickImage),
            _kindTile(Icons.videocam_rounded, 'فيديو قصير', 'حتى 30 ثانية أو 25 م.ب', _pickVideo),
            _kindTile(Icons.mic_rounded, 'تسجيل صوتي', 'حتى دقيقة واحدة', _startRecording),
            _kindTile(Icons.text_fields_rounded, 'نص على خلفية ملونة', 'اكتب مباشرة على اللوحة', () { setState(() => kind = 'text'); _startText(); }),
            const SizedBox(height: 12),
            const Text('بعد الاختيار تستطيع إضافة نصوص وملصقات، وتحديد نوع المنشور (لحظة، عرض، إعلان، فرصة استثمار…) وزر إجراء مثل واتساب أو رابط، ومدة ظهوره على الخريطة.', style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.5)),
          ]),
        ),
    ]);
  }

  Widget _kindTile(IconData icon, String t, String s, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: const Color(0xFF1C1F24),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: Joy.primary.withValues(alpha: .25), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(s, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                ])),
                const Icon(Icons.chevron_left_rounded, color: Colors.white38),
              ]),
            ),
          ),
        ),
      );

  Widget _editStage() => Column(children: [
        Row(children: [
          IconButton(tooltip: 'رجوع', onPressed: () => widget.edit != null ? Navigator.pop(context) : setState(() { kind = null; bytes = null; overlays = []; selected = null; }), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          Expanded(child: Text(switch (kind) { 'image' => 'صورة', 'video' => 'فيديو قصير', 'audio' => 'تسجيل صوتي', _ => 'نص' }, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
          TextButton.icon(onPressed: () => setState(() => pro = !pro), icon: Icon(pro ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined, color: Joy.sun, size: 18), label: Text(pro ? 'احترافي ✓' : 'خيارات احترافية', style: const TextStyle(color: Colors.white))),
        ]),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth - 72);
            return Stack(children: [
              Center(
                child: SizedBox(
                  width: w,
                  height: box.maxHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(fit: StackFit.expand, children: [
                      PostMedia(kind: kind!, bytes: bytes, mime: mime, url: mediaUrl, bg: bg, durationSec: durationSec),
                      GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => editing != null ? _commitText() : setState(() => selected = null)),
                      OverlayCanvas(
                        overlays: overlays, editable: true, selected: selected,
                        onSelect: (i) => setState(() => selected = i),
                        onChanged: (i, o) => setState(() => overlays[i] = o),
                        onEdit: (i) => overlays[i].isSticker ? null : _startText(index: i),
                        hiddenIndex: editing,
                      ),
                      if (editing != null) _inlineEditor(w, box.maxHeight),
                    ]),
                  ),
                ),
              ),
              // أدوات التحرير على جانب البداية
              PositionedDirectional(
                start: 8, top: 8,
                child: Column(children: [
                  _tool(Icons.title_rounded, 'نص', () => _startText()),
                  _tool(Icons.emoji_emotions_outlined, 'ملصق', _stickerSheet),
                  if (kind == 'text') _tool(Icons.palette_outlined, 'الخلفية', _bgPicker),
                  if (selected != null) _tool(Icons.delete_outline_rounded, 'حذف', () => setState(() { overlays.removeAt(selected!); selected = null; })),
                  if (selected != null && !overlays[selected!].isSticker && editing == null) _tool(Icons.edit_outlined, 'تعديل', () => _startText(index: selected)),
                ]),
              ),
              if (editing != null) Positioned(left: 8, right: 8, bottom: 8, child: _inlineToolbar()),
            ]);
          }),
        ),
        _bottomPanel(),
      ]);

  Widget _tool(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22))),
          ),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
        ]),
      );

  Widget _bottomPanel() => Container(
        decoration: const BoxDecoration(color: Color(0xFF15181D), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (pro ? .5 : .3)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: caption, maxLines: 2, maxLength: 500, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: const InputDecoration(hintText: 'تعليق (اختياري)…', hintStyle: TextStyle(color: Colors.white38), counterText: '', filled: true, fillColor: Color(0xFF22262C), isDense: true)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: place, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(prefixIcon: Icon(Icons.place_outlined, color: Colors.white54, size: 18), hintText: 'اسم المكان (اختياري)', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Color(0xFF22262C), isDense: true))),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: ttl, dropdownColor: const Color(0xFF22262C), underline: const SizedBox.shrink(), style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: [for (final (h, l) in postTtlOptions) DropdownMenuItem(value: h, child: Text(l))], onChanged: (v) => setState(() => ttl = v ?? 24),
                ),
              ]),
              if (pro) ...[
                const SizedBox(height: 10),
                const Text('نوع المنشور', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in postTags.entries)
                    ChoiceChip(label: Text(e.value, style: TextStyle(color: tag == e.key ? Joy.primaryOn : Colors.white, fontSize: 12)), selected: tag == e.key, showCheckmark: false, selectedColor: Joy.primary, backgroundColor: const Color(0xFF22262C), onSelected: (_) => setState(() => tag = e.key)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(flex: 3, child: TextField(controller: title, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(hintText: 'عنوان (مثال: خصم 30٪ على القهوة)', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Color(0xFF22262C), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(hintText: 'السعر (ر.س)', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Color(0xFF22262C), isDense: true))),
                ]),
                const SizedBox(height: 8),
                const Text('زر الإجراء', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ChoiceChip(label: Text('بدون', style: TextStyle(color: ctaType == null ? Joy.primaryOn : Colors.white, fontSize: 12)), selected: ctaType == null, showCheckmark: false, selectedColor: Joy.primary, backgroundColor: const Color(0xFF22262C), onSelected: (_) => setState(() => ctaType = null)),
                  for (final e in postCtaTypes.entries)
                    ChoiceChip(label: Text(e.value, style: TextStyle(color: ctaType == e.key ? Joy.primaryOn : Colors.white, fontSize: 12)), selected: ctaType == e.key, showCheckmark: false, selectedColor: Joy.primary, backgroundColor: const Color(0xFF22262C), onSelected: (_) => setState(() => ctaType = e.key)),
                ]),
                if (ctaType != null && ctaType != 'chat') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctaValue,
                    keyboardType: ctaType == 'link' ? TextInputType.url : (ctaType == 'whatsapp' || ctaType == 'call') ? TextInputType.phone : TextInputType.text,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(hintText: switch (ctaType) { 'link' => 'https://…', 'whatsapp' => 'رقم واتساب مثل 05xxxxxxxx', 'call' => 'رقم الهاتف', 'biz' => 'معرّف الدائرة التجارية (مثل biz-ikea)', _ => 'معرّف العرض في السوق' }, hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: const Color(0xFF22262C), isDense: true),
                  ),
                ],
                if (ctaType != null) ...[
                  const SizedBox(height: 8),
                  TextField(controller: ctaLabel, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(hintText: 'نص الزر (اختياري)', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Color(0xFF22262C), isDense: true)),
                ],
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _publish,
                  icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                  label: Text(busy ? 'جارٍ النشر…' : widget.edit != null ? 'حفظ التعديلات' : 'نشر على الخريطة'),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// ورقة اختيار لون: ألوان جاهزة + درجة اللون والتشبّع والإضاءة مع معاينة حية.
class _ColorPickerSheet extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onPick;
  const _ColorPickerSheet({required this.initial, required this.onPick});
  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  static const _presets = [..._bgColors, '#C62828', '#EF6C00', '#F9A825', '#00897B', '#1565C0', '#4527A0', '#AD1457', '#212121'];
  late HSVColor hsv = HSVColor.fromColor(colorFromHex(widget.initial, Joy.primary));

  void _set(HSVColor c) {
    setState(() => hsv = c);
    widget.onPick(hexFromColor(c.toColor()));
  }

  @override
  Widget build(BuildContext context) {
    final c = hsv.toColor();
    const label = TextStyle(color: Colors.white70, fontSize: 12);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('لون الخلفية', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Container(
            height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [c, Color.lerp(c, Colors.black, .45)!])),
            alignment: Alignment.center,
            child: const Text('معاينة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final hex in _presets)
              InkWell(
                key: ValueKey('bg-$hex'),
                onTap: () => _set(HSVColor.fromColor(colorFromHex(hex))),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: colorFromHex(hex), shape: BoxShape.circle, border: Border.all(color: hexFromColor(c) == hex ? Joy.sun : Colors.white24, width: hexFromColor(c) == hex ? 3 : 1.5)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 64, child: Text('الدرجة', style: label)), Expanded(child: Slider(value: hsv.hue, min: 0, max: 360, activeColor: c, onChanged: (v) => _set(hsv.withHue(v))))]),
          Row(children: [const SizedBox(width: 64, child: Text('التشبّع', style: label)), Expanded(child: Slider(value: hsv.saturation, min: 0, max: 1, activeColor: c, onChanged: (v) => _set(hsv.withSaturation(v))))]),
          Row(children: [const SizedBox(width: 64, child: Text('الإضاءة', style: label)), Expanded(child: Slider(value: hsv.value.clamp(.12, 1.0), min: .12, max: 1, activeColor: c, onChanged: (v) => _set(hsv.withValue(v))))]),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم'))),
        ]),
      ),
    );
  }
}
