import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'native_io.dart';
import 'video_controller.dart';
import 'video_view_stub.dart' as stub;

/// على iOS/Android: مشغّل video_player داخل التطبيق. على سطح المكتب (ومنها بيئة الاختبار) نعود للزر الخارجي
/// لأن video_player لا يملك تنفيذاً هناك.
/// [poster] للويب فقط: المعاينة الأصلية شفافة حتى تجهز فيظهر إطار البطاقة تحتها.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false, bool controls = true, String? poster}) =>
    isNativeMobile ? _NativeVideo(url: url, autoplay: autoplay, loop: loop, muted: muted, controls: controls) : stub.createVideo(url, autoplay: autoplay, loop: loop, muted: muted, controls: controls, poster: poster);

/// مشغّل يقوده [VideoViewController] (عارض اللحظات وبطاقاتها): بلا أزرار، شفاف حتى يجهز أو إن فشل فيظهر الغلاف تحته.
Widget createControlledVideo(String url, VideoViewController controller, {bool autoplay = true, bool loop = false, bool muted = false, String? poster, BoxFit? fit}) => isNativeMobile
    ? _ControlledNativeVideo(url: url, controller: controller, autoplay: autoplay, loop: loop, muted: muted, fit: fit)
    : stub.createControlledVideo(url, controller, autoplay: autoplay, loop: loop, muted: muted, poster: poster, fit: fit);

class _ControlledNativeVideo extends StatefulWidget {
  final String url;
  final VideoViewController controller;
  final bool autoplay, loop, muted;
  final BoxFit? fit;
  const _ControlledNativeVideo({required this.url, required this.controller, required this.autoplay, required this.loop, required this.muted, this.fit});
  @override
  State<_ControlledNativeVideo> createState() => _ControlledNativeVideoState();
}

class _ControlledNativeVideoState extends State<_ControlledNativeVideo> implements VideoViewBackend {
  late final VideoPlayerController _p;
  bool _ready = false, _failed = false;

  VideoViewController get _c => widget.controller;
  bool get _muted => _c.wantsMuted ?? widget.muted;

  @override
  void initState() {
    super.initState();
    // mixWithOthers للفيديو الصامت حتى لا يوقف موسيقى المستخدم
    _p = VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: _muted));
    _p.addListener(_onTick);
    _c.attach(this);
    _p.initialize().then((_) async {
      if (!mounted) return;
      await _p.setLooping(widget.loop);
      await _p.setVolume(_muted ? 0 : 1);
      if (_c.rate != 1) await _p.setPlaybackSpeed(_c.rate);
      if (!mounted) return;
      final size = _p.value.size;
      _c.report(_c.value.copyWith(duration: _p.value.duration, muted: _muted, rate: _c.rate, width: size.width, height: size.height, firstFrame: true));
      setState(() => _ready = true);
      if (widget.autoplay && _c.wantsPlaying && !_c.suspended) await _p.play();
    }).catchError((Object _) {
      if (!mounted) return;
      setState(() => _failed = true);
      _c.report(_c.value.copyWith(failed: true, playing: false));
    });
  }

  void _onTick() {
    if (!mounted) return;
    final v = _p.value;
    if (v.hasError && !_failed) {
      setState(() => _failed = true);
      _c.report(_c.value.copyWith(failed: true, playing: false));
      return;
    }
    if (!_ready) return;
    // الانتهاء بلا تكرار: الموضع بلغ المدة والمشغّل توقف
    final ended = !widget.loop && !v.isPlaying && (v.isCompleted || (v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 60)));
    _c.report(_c.value.copyWith(position: v.position, duration: v.duration, playing: v.isPlaying && !v.isBuffering, ended: ended, rate: v.playbackSpeed));
  }

  @override
  void play() {
    if (!_ready) return;
    final v = _p.value;
    // بعد الانتهاء: من البداية
    if (v.duration > Duration.zero && v.position >= v.duration) _p.seekTo(Duration.zero);
    _p.play();
  }

  @override
  void pause() {
    if (_ready) _p.pause();
  }

  @override
  void setRate(double rate) {
    if (_ready) _p.setPlaybackSpeed(rate);
  }

  @override
  void seekBy(Duration delta) {
    if (!_ready) return;
    final v = _p.value;
    var t = v.position + delta;
    if (t < Duration.zero) t = Duration.zero;
    if (v.duration > Duration.zero && t > v.duration) t = v.duration;
    _p.seekTo(t);
    _c.report(_c.value.copyWith(position: t, ended: false));
  }

  @override
  void setMuted(bool muted) {
    if (_ready) _p.setVolume(muted ? 0 : 1);
    _c.report(_c.value.copyWith(muted: muted, soundBlocked: false));
  }

  @override
  void dispose() {
    _c.detach(this);
    _p.removeListener(_onTick);
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // شفاف ريثما يجهز أو إن فشل: الغلاف الذي يرسمه الحاضن تحته يبقى ظاهراً
    if (_failed || !_ready) return const SizedBox.shrink();
    final size = _p.value.size;
    final w = size.width == 0 ? 9.0 : size.width, h = size.height == 0 ? 16.0 : size.height;
    final fit = widget.fit ?? (w > h ? BoxFit.contain : BoxFit.cover);
    final video = FittedBox(fit: fit, clipBehavior: Clip.hardEdge, child: SizedBox(width: w, height: h, child: VideoPlayer(_p)));
    // اللمس لواجهة التطبيق فوقه؛ والمقطع العرضي على أسود بدل الغلاف في الحواشي
    return IgnorePointer(child: fit == BoxFit.contain ? ColoredBox(color: Colors.black, child: video) : video);
  }
}

class _NativeVideo extends StatefulWidget {
  final String url;
  final bool autoplay, loop, muted, controls;
  const _NativeVideo({required this.url, required this.autoplay, required this.loop, required this.muted, required this.controls});
  @override
  State<_NativeVideo> createState() => _NativeVideoState();
}

class _NativeVideoState extends State<_NativeVideo> {
  late final VideoPlayerController _c;
  bool _ready = false, _failed = false, _showControls = true;
  /// المعاينة تتبع TickerMode: تتوقف تحت مسار يغطيها (العارض بملء الشاشة) أو في تبويب خلفي، وتعود حين تظهر
  bool _ticking = true;

  @override
  void initState() {
    super.initState();
    // mixWithOthers للفيديو الصامت حتى لا يوقف موسيقى المستخدم
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: widget.muted));
    _c.addListener(_onTick);
    _c.initialize().then((_) async {
      if (!mounted) return;
      await _c.setLooping(widget.loop);
      await _c.setVolume(widget.muted ? 0 : 1);
      if (widget.autoplay && (widget.controls || _ticking)) {
        await _c.play();
        _showControls = false;
      }
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controls) return;
    final on = TickerMode.valuesOf(context).enabled;
    if (on == _ticking) return;
    _ticking = on;
    if (!_ready || !widget.autoplay) return;
    if (on) {
      _c.play();
    } else {
      _c.pause();
    }
  }

  void _onTick() {
    if (!mounted) return;
    if (_c.value.hasError && !_failed) {
      setState(() => _failed = true);
      return;
    }
    // انتهاء المقطع بلا تكرار: نُظهر زر التشغيل
    if (_ready && !widget.loop && !_c.value.isPlaying && _c.value.position >= _c.value.duration && !_showControls) {
      setState(() => _showControls = true);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_c.value.isPlaying) {
      await _c.pause();
      if (mounted) setState(() => _showControls = true);
    } else {
      if (_c.value.position >= _c.value.duration) await _c.seekTo(Duration.zero);
      await _c.play();
      if (mounted) setState(() => _showControls = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // المعاينة بلا تحكم لا تعرض دوّارة ولا رسالة خطأ: تبقى شفافة فيظهر الإطار الثابت تحتها
    if (!widget.controls && (_failed || !_ready)) return const SizedBox.shrink();
    if (_failed) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white54),
        SizedBox(height: 8),
        Text('تعذر تشغيل الفيديو', style: TextStyle(color: Colors.white70)),
      ]));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator(color: Colors.white));
    // معاينة بلا تحكم: الإطار يُملأ بالقص (كصورة الغلاف) ولا زر ولا شريط ولا لمس؛ اللمس للبطاقة الحاضنة
    if (!widget.controls) {
      return IgnorePointer(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: _c.value.size.width == 0 ? 16 : _c.value.size.width, height: _c.value.size.height == 0 ? 9 : _c.value.size.height, child: VideoPlayer(_c)),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(alignment: Alignment.center, children: [
        Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio == 0 ? 16 / 9 : _c.value.aspectRatio, child: VideoPlayer(_c))),
        if (_showControls) const IgnorePointer(child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(top: false, child: VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white12))),
        ),
      ]),
    );
  }
}

/// عناصر الصوت المفتوحة تخص سفاري على الويب فقط.
void prepareSoundVideos() {}
