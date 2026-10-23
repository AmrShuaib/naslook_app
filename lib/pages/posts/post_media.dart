import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../core/media/video_view.dart';
import '../../core/media/voice_player.dart';
import 'overlay_canvas.dart';

/// وسائط المنشور خلف الطبقات: صورة (رابط أو بايتات)، فيديو (مشغّل أصلي عند العرض أو معاينة عند التحرير)،
/// تسجيل صوتي (بطاقة تشغيل بموجات)، أو خلفية ملونة للنص.
/// الفيديو المعروض داخل [MomentPlayback] (عارض اللحظات) يعمل كسناب: فوراً بالصوت وبلا أزرار، يقوده متحكم العارض، وغلافه تحته حتى أول إطار.
class PostMedia extends StatelessWidget {
  final String kind;
  final String? url;
  final Uint8List? bytes;
  final String? mime;
  final String? bg;
  final int? durationSec;
  final bool play;
  const PostMedia({super.key, required this.kind, this.url, this.bytes, this.mime, this.bg, this.durationSec, this.play = false});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'image':
        if (bytes != null) return Image.memory(bytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined));
        if (url != null && url!.isNotEmpty) return Image.network(mediaUrl(url!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined));
        return _fallback(Icons.image_outlined);
      case 'video':
        final hasUrl = url != null && url!.isNotEmpty;
        if (play && hasUrl) {
          final c = MomentPlayback.maybeOf(context);
          if (c != null) return _MomentVideo(media: url!, controller: c);
          return Container(color: Colors.black, child: VideoView(url: mediaUrl(url!), autoplay: true));
        }
        final label = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white),
          const SizedBox(height: 8),
          Text('فيديو قصير${durationSec != null ? ' · $durationSec ث' : ''}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        ]);
        // مقطع مرفوع لا يعمل الآن (لحظة مجاورة أثناء السحب): إطاره الثابت بدل لوحة داكنة
        if (hasUrl && bytes == null) {
          return Stack(fit: StackFit.expand, children: [
            Image.network(thumbUrl(url!), key: const Key('post-video-poster'), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF14181C))),
            label,
          ]);
        }
        return Container(color: const Color(0xFF14181C), child: label);
      case 'audio':
        return _AudioCard(url: url, bytes: bytes, mime: mime, durationSec: durationSec, play: play);
      default:
        // لوحة المنشور النصي: لون مسطّح (الافتراضي أبيض) حتى يبقى النص الأسود واضحاً بلا تدرّج يعكّر الخلفية
        return Container(color: colorFromHex(bg, Colors.white));
    }
  }

  Widget _fallback(IconData icon) => Container(color: const Color(0xFF14181C), child: Icon(icon, size: 64, color: Colors.white38));
}

/// متحكم فيديو اللحظة المعروضة في العارض: يضعه العارض فوق صفحاته فيأخذه [PostMedia] و[MomentVideoGestures] للحظة النشطة.
/// null حين لا تكون اللحظة النشطة فيديو.
class MomentPlayback extends InheritedWidget {
  final VideoViewController? controller;
  const MomentPlayback({super.key, required this.controller, required super.child});

  static VideoViewController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MomentPlayback>()?.controller;

  @override
  bool updateShouldNotify(MomentPlayback oldWidget) => !identical(controller, oldWidget.controller);
}

/// فيديو اللحظة في العارض: الغلاف (إطار من المقطع) تحته حتى أول إطار، ثم المقطع بلا أزرار يقوده المتحكم.
class _MomentVideo extends StatelessWidget {
  final String media;
  final VideoViewController controller;
  const _MomentVideo({required this.media, required this.controller});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          ValueListenableBuilder<VideoPlayback>(
            valueListenable: controller,
            builder: (_, v, __) => v.firstFrame && !v.failed
                ? const SizedBox.shrink()
                : Stack(fit: StackFit.expand, children: [
                    Image.network(thumbUrl(media), key: const Key('moment-video-poster'), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    if (v.failed)
                      const Center(
                        child: Text('تعذر تشغيل الفيديو', key: Key('moment-video-failed'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black87, blurRadius: 6)])),
                      ),
                  ]),
          ),
          // لكل لحظة متحكم جديد ومشغّل جديد: المفتاح يمنع إعادة استخدام مشغّل اللحظة السابقة
          VideoView(key: ObjectKey(controller), url: mediaUrl(media), poster: thumbUrl(media), controller: controller, autoplay: true, controls: false),
        ]),
      );
}

/// منطقة لمس فيديو اللحظة (بلا أزرار تحكم، كسناب). النقرة كما في الصور: النصف الأيسر [onLeftTap] والأيمن [onRightTap].
/// الضغطة المطوّلة بحسب الموضع الفعلي على الشاشة لا اتجاه الكتابة (قرار المالك): أقصى اليمين (~35%) تسريع 2x ما دام الضغط،
/// أقصى اليسار ترجيع بضعف السرعة (إيقاف وقفز 200 م.ث للخلف كل 100 م.ث)، والوسط إيقاف مؤقت؛ وعند الرفع يعود التشغيل العادي.
/// فوقها رقاقة السرعة أثناء الضغط، ورقاقة «اضغط لتشغيل الصوت» إن رفض المتصفح تشغيل الصوت تلقائياً، و«اضغط للمتابعة» إن أوقفه المتصفح بنفسه.
class MomentVideoGestures extends StatefulWidget {
  final VideoViewController? controller;
  final VoidCallback onLeftTap, onRightTap;
  const MomentVideoGestures({super.key, required this.controller, required this.onLeftTap, required this.onRightTap});

  /// عرض كل منطقة جانبية نسبةً إلى عرض اللحظة
  static const sideZone = .35;
  static const rewindStep = Duration(milliseconds: 200), rewindEvery = Duration(milliseconds: 100);

  @override
  State<MomentVideoGestures> createState() => _MomentVideoGesturesState();
}

enum _Hold { none, fast, rewind, pause }

class _MomentVideoGesturesState extends State<MomentVideoGestures> {
  _Hold _hold = _Hold.none;
  Timer? _rewind;

  double get _width => context.size?.width ?? 0;

  void _tap(TapUpDetails d) {
    final w = _width;
    if (w > 0 && d.localPosition.dx < w / 2) {
      widget.onLeftTap();
    } else {
      widget.onRightTap();
    }
  }

  void _start(LongPressStartDetails d) {
    final c = widget.controller;
    final w = _width;
    if (c == null || w <= 0) return;
    final x = d.localPosition.dx / w;
    final hold = x >= 1 - MomentVideoGestures.sideZone ? _Hold.fast : x <= MomentVideoGestures.sideZone ? _Hold.rewind : _Hold.pause;
    _rewind?.cancel();
    switch (hold) {
      case _Hold.fast:
        c.setRate(2);
        c.play();
      case _Hold.rewind:
        // المتصفح لا يشغّل للخلف: إيقاف وقفزات قصيرة متتالية تعطي ترجيعاً بضعف السرعة
        c.pause();
        _rewind = Timer.periodic(MomentVideoGestures.rewindEvery, (_) => c.seekBy(-MomentVideoGestures.rewindStep));
      case _Hold.pause:
        c.pause();
      case _Hold.none:
        break;
    }
    setState(() => _hold = hold);
  }

  void _end() {
    _rewind?.cancel();
    _rewind = null;
    final hold = _hold;
    if (hold == _Hold.none) return;
    setState(() => _hold = _Hold.none);
    final c = widget.controller;
    if (c == null) return;
    if (hold == _Hold.fast) {
      c.setRate(1);
    } else {
      c.play();
    }
  }

  @override
  void didUpdateWidget(MomentVideoGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    // انتقل العارض إلى لحظة أخرى أثناء الضغط: لا يبقى مؤقّت يقفز في مقطع آخر
    _rewind?.cancel();
    _rewind = null;
    if (_hold == _Hold.fast) oldWidget.controller?.setRate(1);
    _hold = _Hold.none;
  }

  @override
  void dispose() {
    _rewind?.cancel();
    if (_hold == _Hold.fast) widget.controller?.setRate(1);
    super.dispose();
  }

  Widget _chip(String text, Key key, {VoidCallback? onTap, TextDirection? direction}) => Center(
        key: key,
        child: Material(
          color: Colors.black54,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(text, textDirection: direction, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // تعطيل الحركة في النظام: الرقاقات تظهر وتختفي بلا تلاشٍ
    final fade = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 160);
    // رموز السرعة باتجاه ثابت من اليسار لليمين حتى يبقى ⏩ يميناً و⏪ يساراً كما على الشاشة
    final speed = switch (_hold) {
      _Hold.fast => _chip('2x ⏩', const Key('moment-fast'), direction: TextDirection.ltr),
      _Hold.rewind => _chip('⏪ 2x', const Key('moment-rewind'), direction: TextDirection.ltr),
      _ => const SizedBox.shrink(),
    };
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        key: const Key('moment-video-zone'),
        behavior: HitTestBehavior.translucent,
        onTapUp: _tap,
        onLongPressStart: _start,
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: _end,
      ),
      Positioned(
        top: 76,
        left: 12,
        right: 12,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c != null)
            ValueListenableBuilder<VideoPlayback>(
              valueListenable: c,
              builder: (_, v, __) => AnimatedSwitcher(
                duration: fade,
                child: v.failed
                    ? const SizedBox.shrink()
                    : v.soundBlocked
                        ? _chip('🔇 اضغط لتشغيل الصوت', const Key('moment-unmute'), onTap: c.unmute)
                        // المتصفح أوقف المقطع بنفسه (مكالمة، فصل السماعة): لمسة تستأنفه داخل حدث اللمس بدل لحظة متجمدة
                        : v.interrupted && !v.playing
                            ? _chip('▶ اضغط للمتابعة', const Key('moment-resume'), onTap: c.play)
                            : const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 8),
          AnimatedSwitcher(duration: fade, child: speed),
        ]),
      ),
    ]);
  }
}

final _chatMediaName = RegExp(r'^/chat/media/([a-z0-9]{6,16}-[a-f0-9]{24}\.[a-z0-9]{2,5})$', caseSensitive: false);

/// رابط المعاينة الخفيفة لفيديو مرفوع عبر /chat/upload: `GET /chat/vpreview/<name>` (360p، أول ست ثوانٍ، صامتة) يولّدها الخادم
/// عند أول طلب ويحفظها. null لغير ملفاتنا فيأخذ المتصل الرابط الكامل.
String? videoPreviewUrl(String media) {
  final full = mediaUrl(media);
  final m = _chatMediaName.firstMatch(Uri.tryParse(full)?.path ?? '');
  return m == null ? null : '${ApiClient.mediaBase}/chat/vpreview/${m.group(1)}';
}

/// للاختبارات: يفرض طلب أول المقطع بترويسة Range كما على الويب (اختبارات الودجات تعمل على Dart VM).
bool? momentRangeWarmOverride;

/// أول 1.5 م.ب من المقطع: يكفي لبدء التشغيل فوراً لأن الخادم يضع فهرس MP4 في أوله (+faststart).
const momentWarmBytes = 1572864;

/// يسخّن لحظة فيديو قبل الوصول إليها: يحمّل غلافها مسبقاً، وعلى الويب يطلب أول المقطع بترويسة Range عبر عميل الخادم
/// فيجده المتصفح في ذاكرته حين يبدأ التشغيل. على الجوال يكفي الغلاف (video_player يفتح اتصاله بنفسه).
void warmMomentVideo(BuildContext context, ApiClient api, String media) {
  if (media.isEmpty) return;
  unawaited(precacheImage(NetworkImage(thumbUrl(media)), context, onError: (_, __) {}));
  if (momentRangeWarmOverride ?? kIsWeb) unawaited(api.warmMedia(api.media(media), bytes: momentWarmBytes));
}

/// بطاقة التسجيل الصوتي: موجات ثابتة شبه عشوائية (بذرة من الرابط حتى تتطابق بين المحرّر والعارض) وزر تشغيل بتقدم.
/// التشغيل عبر [VoicePlayer]: عنصر <audio> أصلي على الويب يبدأ داخل حدث اللمس (شرط iOS).
class _AudioCard extends StatefulWidget {
  final String? url, mime;
  final Uint8List? bytes;
  final int? durationSec;
  final bool play;
  const _AudioCard({this.url, this.bytes, this.mime, this.durationSec, required this.play});
  @override
  State<_AudioCard> createState() => _AudioCardState();
}

class _AudioCardState extends State<_AudioCard> {
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  Object? _err;

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggle() {
    var p = _player;
    if (p == null) {
      if (widget.bytes == null && (widget.url == null || widget.url!.isEmpty)) return;
      p = VoicePlayer()..setSource(url: widget.url == null ? null : mediaUrl(widget.url!), bytes: widget.bytes, mime: widget.mime);
      _sub = p.changes.listen((_) {
        if (mounted) setState(() {});
      });
      setState(() => _player = p);
    }
    if (p.state.playing) {
      p.pause();
    } else {
      p.play().catchError((Object e) {
        if (mounted) setState(() => _err = e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seed = (widget.url ?? widget.bytes?.length.toString() ?? 'x').hashCode;
    final rnd = math.Random(seed);
    final bars = List.generate(28, (_) => .25 + rnd.nextDouble() * .75);
    final p = _player;
    final total = widget.durationSec != null ? Duration(seconds: widget.durationSec!) : null;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A6E78), Color(0xFF0B2F33)])),
      child: Builder(
        builder: (_) {
          final s = p?.state ?? const VoiceState();
          final failed = _err != null || s.error != null;
          final dur = s.duration ?? total;
          final frac = dur == null || dur.inMilliseconds == 0 ? 0.0 : (s.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.mic_rounded, size: 56, color: Colors.white),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < bars.length; i++)
                  Container(
                    width: 4, height: 14 + bars[i] * 46, margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: i / bars.length <= frac && frac > 0 ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            if (widget.play || widget.bytes != null)
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggle,
                  child: SizedBox(
                    width: 64, height: 64,
                    child: s.loading && !s.playing && !failed
                        ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(failed ? Icons.error_outline_rounded : s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0A6E78), size: 38),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              failed ? 'تعذر تشغيل التسجيل على هذا الجهاز' : dur == null ? 'تسجيل صوتي' : 'تسجيل صوتي · ${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ]);
        },
      ),
    );
  }
}
