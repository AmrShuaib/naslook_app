import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/client.dart' show mediaUrl;
import '../../../api/posts_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/filters.dart';
import '../overlay_canvas.dart';
import '../post_media.dart';
import 'composer_draft.dart';
import 'text_board.dart' show contrastTextColor;
import 'voice_layer.dart';

const _textColors = ['#FFFFFF', '#111111', '#FFD66B', '#0A6E78', '#BF3A1E', '#1FA35A'];
const _stickers = ['🔥', '❤️', '😍', '😂', '👏', '🎉', '✨', '⭐', '💯', '📍', '🛒', '🏷️', '💰', '🎁', '☕', '🍔', '🍕', '🍰', '🚗', '🏨', '🎬', '🎵', '📸', '🏖️', '🕌', '🌙', '☀️', '🌴', '⚡', '🚀', '💼', '📈', '🤝', '📞', '💬', '✅', '🆕', '🆓', '🔖', '👀'];

/// أنماط النص الأربعة: عادي (بلا خلفية)، بخلفية، توهّج (خلفية بلون النص شفافة)، عنوان (أكبر بخلفية)
const _textStyles = <(String, String)>[('plain', 'عادي'), ('boxed', 'بخلفية'), ('glow', 'توهّج'), ('title', 'عنوان')];

/// شاشة «راجع وعدّل»: أربع أدوات فقط في عمود واحد (نص، ملصق، قصّ، فلاتر) وأداة الصوت، وكل أداة تفتح درجاً سفلياً.
/// لا نوع ولا مدة ولا مكان هنا. تعيد 1 عند «التالي» و0 عند الرجوع.
class EditPage extends StatefulWidget {
  final ComposerDraft draft;
  const EditPage({super.key, required this.draft});
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  ComposerDraft get d => widget.draft;
  late List<PostOverlay> overlays = List.of(d.overlays);
  int? selected, editing;
  String? tool;
  late String filter = d.filter;
  late PhotoAdjust adjust = d.adjust;
  late PhotoFrame frame = d.frame;
  late VoiceLayer? voice = d.voice;
  bool manual = false;
  final _inline = TextEditingController();
  final _inlineFocus = FocusNode();

  bool get isImage => d.kind == 'image';
  bool get isVideo => d.kind == 'video';
  bool get existing => d.editing != null && d.shots.isEmpty && d.video == null;

  @override
  void dispose() {
    _inline.dispose();
    _inlineFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- النص
  void _startText({int? index}) {
    if (editing != null) _commitText();
    setState(() {
      var i = index;
      if (i == null) {
        overlays = [...overlays, PostOverlay(type: 'text', text: '', x: .5, y: overlays.isEmpty ? .5 : (.35 + overlays.length * .08).clamp(.2, .85), scale: 1.2, color: d.isText ? contrastTextColor(d.board) : '#FFFFFF')];
        i = overlays.length - 1;
      }
      editing = i;
      selected = i;
      tool = 'text';
      _inline.text = overlays[i].text;
      _inline.selection = TextSelection.collapsed(offset: _inline.text.length);
    });
    _inlineFocus.requestFocus();
  }

  void _commitText() {
    final i = editing;
    if (i == null) return;
    final text = _inline.text.trim();
    setState(() {
      if (text.isEmpty) {
        overlays = [...overlays]..removeAt(i);
        selected = null;
      } else {
        overlays[i] = overlays[i].copyWith(text: text);
        selected = i;
      }
      editing = null;
      tool = null;
    });
    _inlineFocus.unfocus();
  }

  String _styleOf(PostOverlay o) => o.scale >= 1.7 && o.bg != null ? 'title' : o.bg == null ? 'plain' : (o.bg!.length == 9 ? 'glow' : 'boxed');

  void _applyStyle(String s) {
    final i = editing ?? selected;
    if (i == null) return;
    final o = overlays[i];
    final dark = colorFromHex(o.color).computeLuminance() < .5;
    setState(() => overlays[i] = switch (s) {
          'boxed' => o.copyWith(bg: dark ? '#FFFFFF' : '#111111', scale: o.scale >= 1.7 ? 1.2 : o.scale),
          'glow' => o.copyWith(bg: '${o.color.length == 7 ? o.color : '#FFFFFF'}55', scale: o.scale >= 1.7 ? 1.2 : o.scale),
          'title' => o.copyWith(bg: dark ? '#FFFFFF' : '#111111', scale: 1.8),
          _ => o.copyWith(clearBg: true, scale: o.scale >= 1.7 ? 1.2 : o.scale),
        });
  }

  void _setColor(String c) {
    final i = editing ?? selected;
    if (i == null) return;
    setState(() {
      final o = overlays[i];
      final dark = colorFromHex(c).computeLuminance() < .5;
      overlays[i] = o.copyWith(color: c, bg: o.bg == null ? null : (o.bg!.length == 9 ? '${c}55' : (dark ? '#FFFFFF' : '#111111')));
    });
  }

  void _cycleSize() {
    final i = editing ?? selected;
    if (i == null) return;
    const sizes = [1.0, 1.2, 1.5, 1.8];
    final cur = overlays[i].scale;
    final next = sizes[(sizes.indexWhere((v) => (v - cur).abs() < .05) + 1) % sizes.length];
    setState(() => overlays[i] = overlays[i].copyWith(scale: next));
  }

  // ---------------------------------------------------------------- الملصقات والصوت
  void _addSticker(String e) => setState(() {
        overlays = [...overlays, PostOverlay(type: 'sticker', text: e, x: .5 + (overlays.length % 3 - 1) * .15, y: .55, scale: 1.2)];
        selected = overlays.length - 1;
        tool = null;
      });

  Future<void> _voiceTool() async {
    final v = await showVoiceLayerSheet(context, current: voice);
    if (!mounted) return;
    setState(() { voice = v; tool = null; });
  }

  /// سحب الطبقة إلى أسفل اللوحة يحذفها
  void _onOverlayChanged(int i, PostOverlay o) {
    if (o.y > .96) {
      HapticFeedback.mediumImpact();
      setState(() { overlays = [...overlays]..removeAt(i); selected = null; });
      return;
    }
    setState(() => overlays[i] = o);
  }

  void _next() {
    if (editing != null) _commitText();
    d.overlays = overlays;
    d.filter = filter;
    d.adjust = adjust;
    d.frame = frame;
    d.voice = voice;
    Navigator.pop(context, 1);
  }

  // ---------------------------------------------------------------- البناء
  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F1114),
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  TextButton.icon(key: const Key('edit-back'), style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black38, shape: const StadiumBorder()), onPressed: () => Navigator.pop(context, 0), icon: const Icon(Icons.arrow_back_rounded, size: 18), label: Text(existing ? 'إلغاء' : d.isText ? 'رجوع' : 'إعادة التصوير')),
                  const Spacer(),
                  FilledButton(key: const Key('edit-next'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: _next, child: const Text('التالي')),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth - 88);
                  return Stack(children: [
                    Center(
                      child: SizedBox(
                        width: w, height: box.maxHeight - 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(fit: StackFit.expand, children: [
                            _media(),
                            GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => editing != null ? _commitText() : setState(() { selected = null; if (tool == 'text') tool = null; })),
                            OverlayCanvas(
                              overlays: overlays, editable: true, selected: selected, hiddenIndex: editing, shadow: !d.isText,
                              onSelect: (i) => setState(() { selected = i; if (!overlays[i].isSticker) tool = 'text'; }),
                              onChanged: _onOverlayChanged,
                              onEdit: (i) => overlays[i].isSticker ? null : _startText(index: i),
                            ),
                            if (editing != null) _inlineEditor(w, box.maxHeight - 12),
                            if (voice != null) Positioned(bottom: 14, left: 0, right: 0, child: Center(child: VoiceChip(layer: voice, light: d.isText && contrastTextColor(d.board) == '#111111'))),
                            if (selected != null && editing == null)
                              Positioned(bottom: 6, left: 0, right: 0, child: IgnorePointer(child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white), SizedBox(width: 4), Text('اسحب إلى هنا للحذف', style: TextStyle(color: Colors.white, fontSize: 11))]))))),
                          ]),
                        ),
                      ),
                    ),
                    // عمود الأدوات
                    if (editing == null)
                      PositionedDirectional(
                        start: 10, top: 10,
                        child: Column(children: [
                          _tool('text', Icons.title_rounded, 'نص', () => _startText()),
                          _tool('sticker', Icons.emoji_emotions_outlined, 'ملصق', () => setState(() => tool = tool == 'sticker' ? null : 'sticker')),
                          if (isImage && !existing) _tool('crop', Icons.crop_rotate_rounded, 'قصّ', () => setState(() => tool = tool == 'crop' ? null : 'crop')),
                          if (isImage && !existing) _tool('filter', Icons.auto_fix_high_rounded, 'فلاتر', () => setState(() => tool = tool == 'filter' ? null : 'filter')),
                          if (!isVideo) _tool('voice', Icons.mic_rounded, 'صوت', _voiceTool, on: voice != null),
                        ]),
                      ),
                  ]);
                }),
              ),
              _tray(),
            ]),
          ),
        ),
      );

  Widget _media() {
    if (d.isText) return Container(color: colorFromHex(d.board, Colors.white));
    if (isVideo) return PostMedia(kind: 'video', bytes: d.video?.bytes, mime: d.video?.mime, url: d.editing?.mediaUrl, durationSec: d.videoSec ?? d.editing?.durationSec);
    final shot = d.coverShot;
    Widget img;
    if (shot != null) {
      img = Image.memory(shot.bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF14181C), child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48)));
    } else if (d.editing?.mediaUrl != null) {
      img = Image.network(mediaUrl(d.editing!.mediaUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF14181C)));
    } else {
      return const ColoredBox(color: Color(0xFF14181C));
    }
    final cf = colorFilterFor(filterById(filter), adjust);
    if (cf != null) img = ColorFiltered(colorFilter: cf, child: img);
    if (frame.quarterTurns % 4 != 0) img = RotatedBox(quarterTurns: frame.quarterTurns, child: img);
    if (frame.aspect != null) img = Center(child: AspectRatio(aspectRatio: frame.aspect!, child: img));
    return ColoredBox(color: const Color(0xFF14181C), child: img);
  }

  Widget _tool(String id, IconData icon, String label, VoidCallback onTap, {bool on = false}) {
    final active = on || tool == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(color: active ? Joy.sun : Colors.black54, shape: const CircleBorder(), child: InkWell(key: Key('tool-$id'), customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 46, height: 46, child: Icon(icon, color: active ? Joy.sunText : Colors.white, size: 22)))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, shadows: [Shadow(color: Colors.black54, blurRadius: 3)])),
      ]),
    );
  }

  Widget _inlineEditor(double w, double h) {
    final o = overlays[editing!];
    final size = w * 0.065 * o.scale;
    final color = colorFromHex(o.color);
    final bgc = o.bg == null ? null : colorFromHex(o.bg);
    final style = TextStyle(color: color, fontSize: size, height: 1.25, fontWeight: FontWeight.w800, fontFamily: o.font == 'serif' ? 'serif' : null, shadows: bgc == null && !d.isText ? [const Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))] : null);
    Widget field = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w * .85, minWidth: size * 3),
      child: IntrinsicWidth(
        child: TextField(
          key: const Key('inline-text'), controller: _inline, focusNode: _inlineFocus, autofocus: true, maxLines: null, maxLength: 140,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, textInputAction: TextInputAction.done, textAlign: TextAlign.center, style: style, cursorColor: color,
          decoration: InputDecoration.collapsed(hintText: 'اكتب هنا…', hintStyle: style.copyWith(color: color.withValues(alpha: .45))),
          onChanged: (v) => setState(() => overlays[editing!] = overlays[editing!].copyWith(text: v)),
          onSubmitted: (_) => _commitText(),
        ),
      ),
    );
    if (bgc != null) field = Container(padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: size * .25), decoration: BoxDecoration(color: bgc, borderRadius: BorderRadius.circular(size * .5)), child: field);
    return Positioned(left: o.x * w, top: o.y * h, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.rotate(angle: o.rot, child: field)));
  }

  // ---------------------------------------------------------------- الأدراج
  Widget _tray() {
    Widget? body;
    String title = '';
    switch (tool) {
      case 'text':
        final i = editing ?? selected;
        if (i == null || overlays[i].isSticker) break;
        final o = overlays[i];
        title = 'النص';
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (k, l) in _textStyles)
              ChoiceChip(key: Key('style-$k'), label: Text(l, style: TextStyle(color: _styleOf(o) == k ? Colors.black : Colors.white, fontSize: 12.5)), selected: _styleOf(o) == k, showCheckmark: false, selectedColor: Colors.white, backgroundColor: Colors.white12, side: BorderSide.none, visualDensity: VisualDensity.compact, onSelected: (_) => _applyStyle(k)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final c in _textColors) InkWell(key: Key('color-$c'), onTap: () => _setColor(c), borderRadius: BorderRadius.circular(999), child: Container(width: 30, height: 30, decoration: BoxDecoration(color: colorFromHex(c), shape: BoxShape.circle, border: Border.all(color: o.color == c ? Joy.sun : Colors.white38, width: o.color == c ? 3 : 1.5)))),
            InkWell(key: const Key('text-size'), onTap: _cycleSize, borderRadius: BorderRadius.circular(10), child: Container(width: 44, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)), child: Text('Aa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: o.scale < 1.1 ? 12 : o.scale < 1.4 ? 14 : o.scale < 1.7 ? 17 : 20)))),
          ]),
        ]);
      case 'sticker':
        title = 'ملصق';
        body = SizedBox(height: 112, child: GridView.count(crossAxisCount: 8, physics: const NeverScrollableScrollPhysics(), children: [for (final e in _stickers.take(16)) InkWell(key: Key('sticker-$e'), onTap: () => _addSticker(e), child: Center(child: Text(e, style: const TextStyle(fontSize: 26))))]));
      case 'crop':
        title = 'قصّ ودوران';
        body = Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (l, a) in photoAspects)
            ChoiceChip(key: Key('aspect-$l'), label: Text(l, style: TextStyle(color: frame.aspect == a ? Colors.black : Colors.white, fontSize: 12.5)), selected: frame.aspect == a, showCheckmark: false, selectedColor: Colors.white, backgroundColor: Colors.white12, side: BorderSide.none, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => frame = a == null ? frame.copyWith(clearAspect: true) : frame.copyWith(aspect: a))),
          IconButton(key: const Key('rotate'), tooltip: 'تدوير', onPressed: () => setState(() => frame = frame.copyWith(quarterTurns: (frame.quarterTurns + 1) % 4)), icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: Colors.white)),
        ]);
      case 'filter':
        title = 'الفلاتر';
        final shot = d.coverShot;
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 92,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in photoFilters)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: InkWell(
                    key: Key('filter-${f.id}'), onTap: () => setState(() => filter = f.id), borderRadius: BorderRadius.circular(14),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 56, height: 66, clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: filter == f.id ? Joy.sun : Colors.transparent, width: 2), color: Colors.white12),
                        child: shot == null ? null : (colorFilterFor(f, const PhotoAdjust()) == null ? Image.memory(shot.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()) : ColorFiltered(colorFilter: colorFilterFor(f, const PhotoAdjust())!, child: Image.memory(shot.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))),
                      ),
                      const SizedBox(height: 4),
                      Text(f.label, style: TextStyle(color: filter == f.id ? Joy.sun : Colors.white70, fontSize: 11, fontWeight: filter == f.id ? FontWeight.w700 : FontWeight.w500)),
                    ]),
                  ),
                ),
            ]),
          ),
          InkWell(
            key: const Key('manual-toggle'),
            onTap: () => setState(() => manual = !manual),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [const Text('ضبط يدوي: سطوع · تباين · دفء', style: TextStyle(color: Colors.white70, fontSize: 12.5)), const Spacer(), Icon(manual ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white54, size: 20)])),
          ),
          if (manual) ...[
            _slider('السطوع', adjust.brightness, (v) => setState(() => adjust = adjust.copyWith(brightness: v)), key: const Key('adj-brightness')),
            _slider('التباين', adjust.contrast, (v) => setState(() => adjust = adjust.copyWith(contrast: v))),
            _slider('الدفء', adjust.warmth, (v) => setState(() => adjust = adjust.copyWith(warmth: v))),
          ],
        ]);
    }
    if (body == null) return const SizedBox(height: 12);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF1C1F24), borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.viewInsetsOf(context).bottom * (editing != null ? 1 : 0)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const Spacer(),
          FilledButton(key: const Key('tray-done'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, visualDensity: VisualDensity.compact), onPressed: () => editing != null ? _commitText() : setState(() => tool = null), child: const Text('تم')),
        ]),
        const SizedBox(height: 8),
        body,
      ]),
    );
  }

  Widget _slider(String label, double v, ValueChanged<double> onChanged, {Key? key}) => Row(children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(child: Slider(key: key, value: v, min: -1, max: 1, activeColor: Joy.sun, inactiveColor: Colors.white24, onChanged: onChanged)),
        SizedBox(width: 30, child: Text(v == 0 ? '0' : (v * 100).round().toString(), style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.end)),
      ]);
}
