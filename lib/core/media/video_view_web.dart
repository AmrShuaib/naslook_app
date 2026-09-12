import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _seq = 0;

/// عنصر <video> أصلي في المتصفح: يعمل على iOS (playsinline) ويعرض أزرار التحكم.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false}) {
  final id = 'naslife-video-${_seq++}';
  ui_web.platformViewRegistry.registerViewFactory(id, (int viewId) {
    final v = web.HTMLVideoElement()
      ..src = url
      ..controls = true
      ..autoplay = autoplay
      ..loop = loop
      ..muted = muted
      ..preload = 'metadata';
    v.setAttribute('playsinline', 'true');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..background = '#000';
    return v;
  });
  return HtmlElementView(viewType: id);
}
