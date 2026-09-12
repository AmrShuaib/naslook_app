import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// على غير الويب: زر يفتح الفيديو في مشغّل النظام.
Widget createVideo(String url, {bool autoplay = false, bool loop = false, bool muted = false}) => Center(
      child: IconButton(
        iconSize: 64,
        color: Colors.white,
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.play_circle_fill_rounded),
      ),
    );
