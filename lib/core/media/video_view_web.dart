import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _seq = 0;

/// عنصر <video> أصلي في المتصفح: يعمل على iOS (playsinline) ويعرض أزرار التحكم.
/// بلا [controls]: معاينة تملأ الإطار (cover) بلا شريط ولا نقر، كصورة متحركة في بطاقة.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false, bool controls = true}) {
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
    // المتصفح لا يشغّل تلقائياً إلا الصامت؛ والمعاينة لا تلتقط اللمس فتبقى لمسة البطاقة للتطبيق
    if (!controls) v.setAttribute('disablepictureinpicture', 'true');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = controls ? 'contain' : 'cover'
      ..background = '#000';
    if (!controls) v.style.pointerEvents = 'none';
    return v;
  });
  return HtmlElementView(viewType: id);
}
