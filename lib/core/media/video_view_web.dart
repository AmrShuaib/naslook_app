import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'video_controller.dart';

int _seq = 0;

/// عنصر <video> أصلي في المتصفح: يعمل على iOS (playsinline) ويعرض أزرار التحكم.
/// بلا [controls]: معاينة تملأ الإطار (cover) بلا شريط ولا نقر، كصورة متحركة في بطاقة، بخلفية شفافة وإطار [poster]
/// فلا تظهر لوحة سوداء ريثما يُحمَّل المقطع أو إن منع المتصفح التشغيل التلقائي.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false, bool controls = true, String? poster}) {
  final id = 'naslife-video-${_seq++}';
  ui_web.platformViewRegistry.registerViewFactory(id, (int viewId) {
    final v = web.HTMLVideoElement()
      ..src = url
      ..controls = controls
      ..autoplay = autoplay
      ..loop = loop
      ..muted = muted
      ..preload = controls ? 'metadata' : 'auto';
    v.setAttribute('playsinline', 'true');
    if (poster != null && poster.isNotEmpty) v.poster = poster;
    // المتصفح لا يشغّل تلقائياً إلا الصامت؛ والمعاينة لا تلتقط اللمس فتبقى لمسة البطاقة للتطبيق
    if (!controls) v.setAttribute('disablepictureinpicture', 'true');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = controls ? 'contain' : 'cover'
      // المعاينة شفافة: الإطار الثابت الذي ترسمه البطاقة تحتها يبقى ظاهراً حتى أول إطار من المقطع
      ..background = controls ? '#000' : 'transparent';
    if (!controls) v.style.pointerEvents = 'none';
    return v;
  });
  return HtmlElementView(viewType: id);
}

/// عنصر <video> يقوده [VideoViewController]: بلا أزرار أصلية ولا لمس (اللمس لواجهة التطبيق فوقه)، شفاف حتى أول إطار.
Widget createControlledVideo(String url, VideoViewController controller, {bool autoplay = true, bool loop = false, bool muted = false, String? poster, BoxFit? fit}) =>
    _WebVideo(url: url, controller: controller, autoplay: autoplay, loop: loop, muted: muted, poster: poster, fit: fit);

class _WebVideo extends StatefulWidget {
  final String url;
  final VideoViewController controller;
  final bool autoplay, loop, muted;
  final String? poster;
  final BoxFit? fit;
  const _WebVideo({required this.url, required this.controller, required this.autoplay, required this.loop, required this.muted, this.poster, this.fit});
  @override
  State<_WebVideo> createState() => _WebVideoState();
}

class _WebVideoState extends State<_WebVideo> implements VideoViewBackend {
  web.HTMLVideoElement? _v;
  final _subs = <StreamSubscription<web.Event>>[];
  late final Widget _view = IgnorePointer(
    child: HtmlElementView.fromTagName(tagName: 'video', onElementCreated: _setup),
  );

  VideoViewController get _c => widget.controller;

  void _report(VideoPlayback Function(VideoPlayback s) f) {
    if (!mounted) return;
    _c.report(f(_c.value));
  }

  Duration get _pos {
    final t = _v?.currentTime ?? 0;
    return t.isFinite && t > 0 ? Duration(milliseconds: (t * 1000).round()) : Duration.zero;
  }

  Duration? get _dur {
    final d = _v?.duration ?? double.nan;
    return d.isFinite && d > 0 ? Duration(milliseconds: (d * 1000).round()) : null;
  }

  String _fitCss(web.HTMLVideoElement v) => switch (widget.fit) {
        BoxFit.contain || BoxFit.scaleDown => 'contain',
        BoxFit.fill => 'fill',
        BoxFit.cover || BoxFit.fitWidth || BoxFit.fitHeight || BoxFit.none => 'cover',
        // تلقائي: العمودي يملأ الإطار كسناب، والعرضي يُعرض كاملاً بلا قص
        null => v.videoWidth > v.videoHeight && v.videoHeight > 0 ? 'contain' : 'cover',
      };

  void _setup(Object element) {
    if (!mounted) return;
    final v = element as web.HTMLVideoElement;
    _v = v;
    final muted = _c.wantsMuted ?? widget.muted;
    v
      ..controls = false
      ..autoplay = false
      ..loop = widget.loop
      ..muted = muted
      ..defaultPlaybackRate = _c.rate
      ..preload = 'auto';
    v.setAttribute('playsinline', 'true');
    v.setAttribute('webkit-playsinline', 'true');
    v.setAttribute('disablepictureinpicture', 'true');
    // iOS يشترط خاصية muted في الوسم نفسه لقبول التشغيل التلقائي الصامت
    if (muted) v.setAttribute('muted', '');
    final poster = widget.poster;
    if (poster != null && poster.isNotEmpty) v.poster = poster;
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = _fitCss(v)
      ..background = 'transparent'
      ..pointerEvents = 'none';
    _subs.addAll([
      v.onLoadedMetadata.listen((_) {
        v.style.objectFit = _fitCss(v);
        _report((s) => s.copyWith(duration: _dur, width: v.videoWidth.toDouble(), height: v.videoHeight.toDouble()));
      }),
      v.onDurationChange.listen((_) => _report((s) => s.copyWith(duration: _dur))),
      v.onTimeUpdate.listen((_) => _report((s) => s.copyWith(position: _pos))),
      v.onSeeked.listen((_) => _report((s) => s.copyWith(position: _pos))),
      v.onPlay.listen((_) => _report((s) => s.copyWith(ended: false))),
      v.onPlaying.listen((_) => _shown(playing: true)),
      v.onLoadedData.listen((_) => _shown()),
      // التعثّر في التحميل: يتوقف تقدير الموضع حتى يعود التشغيل
      v.onWaiting.listen((_) => _report((s) => s.copyWith(playing: false))),
      v.onPause.listen((_) => _report((s) => s.copyWith(playing: false, position: _pos))),
      v.onEnded.listen((_) => _report((s) => s.copyWith(playing: false, ended: true, position: _dur ?? _pos))),
      v.onError.listen((_) => _report((s) => s.copyWith(playing: false, failed: true))),
      v.onVolumeChange.listen((_) => _report((s) => s.copyWith(muted: v.muted, soundBlocked: v.muted && s.soundBlocked))),
      v.onRateChange.listen((_) => _report((s) => s.copyWith(rate: v.playbackRate))),
    ]);
    v.src = widget.url;
    v.playbackRate = _c.rate;
    _c.attach(this);
    _report((s) => s.copyWith(muted: muted, rate: _c.rate));
    if (widget.autoplay && _c.wantsPlaying && !_c.suspended) play();
  }

  /// أول إطار ظهر: المقطع العرضي يأخذ خلفية سوداء (بدل الغلاف تحته) لأن عرضه كاملاً يترك حواشي
  void _shown({bool? playing}) {
    final v = _v;
    if (v == null) return;
    if (_fitCss(v) == 'contain') v.style.background = '#000';
    _report((s) => s.copyWith(firstFrame: true, playing: playing));
  }

  @override
  void play() {
    final v = _v;
    if (v == null) return;
    // play() قبل أي await حتى يُحتسب ضمن حدث اللمس إن جاء منه (رفع الكتم)
    final p = v.play();
    unawaited(_settle(v, p));
  }

  Future<void> _settle(web.HTMLVideoElement v, JSPromise<JSAny?> p) async {
    try {
      await p.toDart;
    } catch (e) {
      // مسار آخر أوقفه (pause قبل اكتمال play) أو أُزيل العنصر: ليس رفضاً للصوت
      if (!mounted || !identical(_v, v) || !_c.wantsPlaying || _c.suspended || '$e'.contains('AbortError')) return;
      if (!v.muted) {
        // المتصفح يرفض الصوت بلا لمسة: نكمل صامتين ونعرض «اضغط لتشغيل الصوت»
        v.muted = true;
        _report((s) => s.copyWith(muted: true, soundBlocked: true));
        try {
          await v.play().toDart;
        } catch (_) {
          _report((s) => s.copyWith(playing: false));
        }
      } else {
        // رفض حتى الصامت (وضع توفير الطاقة): إن كنا نريد الصوت فلمسة على الرقاقة تشغّله به
        final wantedSound = !(_c.wantsMuted ?? widget.muted);
        _report((s) => s.copyWith(playing: false, soundBlocked: s.soundBlocked || wantedSound));
      }
    }
  }

  @override
  void pause() => _v?.pause();

  @override
  void setRate(double rate) {
    final v = _v;
    if (v == null) return;
    v.defaultPlaybackRate = rate;
    v.playbackRate = rate;
  }

  @override
  void seekBy(Duration delta) {
    final v = _v;
    if (v == null) return;
    final d = v.duration;
    var t = v.currentTime + delta.inMilliseconds / 1000;
    if (d.isFinite && t > d) t = d;
    if (t < 0 || !t.isFinite) t = 0;
    v.currentTime = t;
    _report((s) => s.copyWith(position: Duration(milliseconds: (t * 1000).round()), ended: false));
  }

  @override
  void setMuted(bool muted) {
    final v = _v;
    if (v == null) return;
    v.muted = muted;
    if (!muted) v.removeAttribute('muted');
    _report((s) => s.copyWith(muted: muted, soundBlocked: muted && s.soundBlocked));
  }

  @override
  void dispose() {
    _c.detach(this);
    for (final s in _subs) {
      s.cancel();
    }
    final v = _v;
    if (v != null) {
      // إيقاف التحميل فوراً: العارض ينتقل بين لحظات كثيرة ولا يجوز أن تبقى مقاطعها تُحمَّل في الخلفية
      v.pause();
      v.removeAttribute('src');
      v.load();
    }
    _v = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _view;
}
