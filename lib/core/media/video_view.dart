import 'package:flutter/widgets.dart';

import 'video_view_stub.dart' if (dart.library.js_interop) 'video_view_web.dart' as impl;

/// مشغّل فيديو: على الويب عنصر <video> أصلي، وعلى غيره زر يفتح الرابط. يُسجَّل العنصر مرة واحدة لكل ودجت.
class VideoView extends StatefulWidget {
  final String url;
  final bool autoplay, loop, muted;
  const VideoView({super.key, required this.url, this.autoplay = false, this.loop = false, this.muted = false});
  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final Widget _child = impl.createVideo(widget.url, autoplay: widget.autoplay, loop: widget.loop, muted: widget.muted);
  @override
  Widget build(BuildContext context) => _child;
}
