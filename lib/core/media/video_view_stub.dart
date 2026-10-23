import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'video_controller.dart';

/// على غير الويب: زر يفتح الفيديو في مشغّل النظام. المعاينة بلا تحكم (بطاقات «اللحظات») لا يمكنها الدوران هنا فتعرض
/// الزر نفسه بحجم أصغر.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false, bool controls = true, String? poster}) => Center(
      child: IconButton(
        iconSize: controls ? 64 : 40,
        color: Colors.white,
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.play_circle_fill_rounded),
      ),
    );

/// بلا مشغّل داخلي (سطح المكتب): الزر نفسه، والمتحكم يبقى بلا مشغّل فلا تقدّم ولا انتهاء.
Widget createControlledVideo(String url, VideoViewController controller, {bool autoplay = true, bool loop = false, bool muted = false, String? poster, BoxFit? fit}) =>
    createVideo(url, autoplay: autoplay, loop: loop, muted: muted, controls: !loop, poster: poster);

/// عناصر الصوت المفتوحة تخص سفاري على الويب فقط.
void prepareSoundVideos() {}
