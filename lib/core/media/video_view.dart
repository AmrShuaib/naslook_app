import 'package:flutter/material.dart';

import 'video_controller.dart';
import 'video_view_stub.dart' if (dart.library.js_interop) 'video_view_web.dart' if (dart.library.io) 'video_view_io.dart' as impl;

export 'video_controller.dart';

/// مشغّل فيديو: على الويب عنصر <video> أصلي، وعلى iOS/Android مشغّل video_player داخل التطبيق.
/// يُنشأ المشغّل مرة واحدة لكل ودجت. [controls] false = معاينة صامتة تدور كصورة متحركة (بلا شريط تحكم، تملأ الإطار)،
/// شفافة ريثما تجهز أو إن تعذّر تشغيلها فيظهر ما تحتها (الإطار الثابت في البطاقة).
/// مع [controller]: لا أزرار تحكم أصلية أبداً، والتطبيق يرسم واجهته (عارض اللحظات): المتحكم يشغّل ويوقف ويسرّع ويقفز ويكتم،
/// ويتابع الموضع والمدة والانتهاء. يبقى شفافاً حتى أول إطار، ويتوقف مؤقتاً حين تُغطّى صفحته (TickerMode).
class VideoView extends StatefulWidget {
  /// بديل للاختبارات: اختبارات الودجات تعمل على Dart VM (dart.library.io) فلا يجوز أن تلمس قناة المنصة.
  static Widget Function(String url, {bool autoplay, bool loop, bool muted, bool controls})? factoryOverride;
  /// بديل للاختبارات يستلم المتحكم: الاختبار يربطه بمشغّل وهمي ([VideoViewBackend]) فيحاكي الموضع والانتهاء ورفض الصوت.
  /// بلا هذا البديل يُستخدم [factoryOverride] إن وُجد ويبقى المتحكم بلا مشغّل.
  static Widget Function(String url, VideoViewController controller, {bool autoplay, bool loop, bool muted, String? poster})? controlledFactoryOverride;

  /// الويب: يجهّز عناصر <video> يُعاد استعمالها لمشغّل الصوت (العارض) وتُفتح عند كل لمسة، لأن سفاري iOS لا يقبل الصوت
  /// إلا لعنصر شُغّل داخل لمسة. بلا أثر خارج الويب.
  static void prepareSound() => impl.prepareSoundVideos();

  final String url;
  final bool autoplay, loop, muted, controls;
  /// إطار ثابت يعرضه عنصر الويب ريثما يبدأ التشغيل أو إن منع المتصفح التشغيل التلقائي (خاصية poster)
  final String? poster;
  final VideoViewController? controller;
  /// ملاءمة المقطع مع [controller]؛ null = يملأ الإطار للمقطع العمودي ويُعرض كاملاً على أسود للمقطع العرضي
  final BoxFit? fit;
  const VideoView({super.key, required this.url, this.autoplay = false, this.loop = false, this.muted = false, this.controls = true, this.poster, this.controller, this.fit});
  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final Widget _child = _create();

  Widget _create() {
    final w = widget, c = w.controller;
    if (c != null) {
      final co = VideoView.controlledFactoryOverride;
      if (co != null) return co(w.url, c, autoplay: w.autoplay, loop: w.loop, muted: w.muted, poster: w.poster);
    }
    final o = VideoView.factoryOverride;
    if (o != null) return o(w.url, autoplay: w.autoplay, loop: w.loop, muted: w.muted, controls: w.controls);
    if (c != null) return impl.createControlledVideo(w.url, c, autoplay: w.autoplay, loop: w.loop, muted: w.muted, poster: w.poster, fit: w.fit);
    return impl.createVideo(w.url, autoplay: w.autoplay, loop: w.loop, muted: w.muted, controls: w.controls, poster: w.poster);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // صفحة مغطاة بمسار آخر (محادثة فُتحت من العارض) أو تبويب خلفي: لا صوت ولا تحميل خلفها
    widget.controller?.setSuspended(!TickerMode.valuesOf(context).enabled);
  }

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
