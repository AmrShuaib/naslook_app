import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'native_io.dart';
import 'video_view_stub.dart' as stub;

/// على iOS/Android: مشغّل video_player داخل التطبيق. على سطح المكتب (ومنها بيئة الاختبار) نعود للزر الخارجي
/// لأن video_player لا يملك تنفيذاً هناك.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false}) =>
    isNativeMobile ? _NativeVideo(url: url, autoplay: autoplay, loop: loop, muted: muted) : stub.createVideo(url, autoplay: autoplay, loop: loop, muted: muted);

class _NativeVideo extends StatefulWidget {
  final String url;
  final bool autoplay, loop, muted;
  const _NativeVideo({required this.url, required this.autoplay, required this.loop, required this.muted});
  @override
  State<_NativeVideo> createState() => _NativeVideoState();
}

class _NativeVideoState extends State<_NativeVideo> {
  late final VideoPlayerController _c;
  bool _ready = false, _failed = false, _showControls = true;

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
      if (widget.autoplay) {
        await _c.play();
        _showControls = false;
      }
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
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
    if (_failed) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white54),
        SizedBox(height: 8),
        Text('تعذر تشغيل الفيديو', style: TextStyle(color: Colors.white70)),
      ]));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator(color: Colors.white));
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
