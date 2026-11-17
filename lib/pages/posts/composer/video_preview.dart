import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/media/local_media.dart';
import '../../../core/media/video_view.dart';
import '../post_media.dart';

/// مراجعة الفيديو قبل النشر: يشغّل المقطع المصوَّر من الجهاز نفسه (لم يُرفع بعد) ويعيده حلقةً، صامتاً في البداية لأن
/// المتصفحات لا تسمح بتشغيل تلقائي بصوت، وزر الصوت في عمود الأدوات يفتحه عبر [controller].
/// إن تعذّر إنشاء رابط محلي يبقى الإطار الثابت القديم.
class ComposerVideoPreview extends StatefulWidget {
  final Uint8List bytes;
  final String mime;
  final int? durationSec;
  final VideoViewController controller;
  const ComposerVideoPreview({super.key, required this.bytes, required this.mime, required this.controller, this.durationSec});

  @override
  State<ComposerVideoPreview> createState() => _ComposerVideoPreviewState();
}

class _ComposerVideoPreviewState extends State<ComposerVideoPreview> {
  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    localMediaUrl(widget.bytes, widget.mime).then((u) {
      if (!mounted) return releaseLocalMediaUrl(u);
      setState(() {
        _url = u;
        _failed = u == null;
      });
    });
  }

  @override
  void dispose() {
    releaseLocalMediaUrl(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) {
      // قبل جهوز الرابط أو عند تعذّره: الإطار الثابت برمز التشغيل
      return KeyedSubtree(key: Key(_failed ? 'edit-video-static' : 'edit-video-loading'), child: PostMedia(kind: 'video', bytes: widget.bytes, mime: widget.mime, durationSec: widget.durationSec));
    }
    return ColoredBox(
      key: const Key('edit-video-preview'),
      color: Colors.black,
      child: VideoView(url: url, controller: widget.controller, autoplay: true, loop: true, muted: true, fit: BoxFit.cover),
    );
  }
}
