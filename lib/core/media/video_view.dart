import 'package:flutter/material.dart';

import 'video_view_stub.dart' if (dart.library.js_interop) 'video_view_web.dart' if (dart.library.io) 'video_view_io.dart' as impl;

/// مشغّل فيديو: على الويب عنصر <video> أصلي، وعلى iOS/Android مشغّل video_player داخل التطبيق.
/// يُنشأ المشغّل مرة واحدة لكل ودجت.
class VideoView extends StatefulWidget {
  /// بديل للاختبارات: اختبارات الودجات تعمل على Dart VM (dart.library.io) فلا يجوز أن تلمس قناة المنصة.
  static Widget Function(String url, {bool autoplay, bool loop, bool muted})? factoryOverride;

  final String url;
  final bool autoplay, loop, muted;
  const VideoView({super.key, required this.url, this.autoplay = false, this.loop = false, this.muted = false});
  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final Widget _child = VideoView.factoryOverride?.call(widget.url, autoplay: widget.autoplay, loop: widget.loop, muted: widget.muted) ??
      impl.createVideo(widget.url, autoplay: widget.autoplay, loop: widget.loop, muted: widget.muted);
  @override
  Widget build(BuildContext context) => _child;
}

/// يفتح الفيديو بملء الشاشة داخل التطبيق (بدل تبويب أو مشغّل خارجي).
Future<void> openVideoFullScreen(BuildContext context, String url) => Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        key: const Key('video-full'),
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: VideoView(url: url, autoplay: true)),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(child: IconButton(key: const Key('video-close'), tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => Navigator.pop(ctx))),
          ),
        ]),
      ),
    ));
