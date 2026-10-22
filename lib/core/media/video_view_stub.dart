import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
