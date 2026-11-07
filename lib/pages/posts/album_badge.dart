import 'package:flutter/material.dart';

import '../../api/posts_api.dart' show albumCountLabel;

/// شارة صغيرة فوق غلاف لحظة الألبوم في البطاقات («اللحظات»، بطاقة الصف، «لحظات هنا»): أيقونة الصور وعددها («3 صور»)، لأن
/// البطاقة تعرض الغلاف وحده فيعرف المشاهد أن خلفه صوراً يسحب بينها في العارض.
class AlbumBadge extends StatelessWidget {
  final int count;
  const AlbumBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .58), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.photo_library_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(albumCountLabel(count), maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1)),
        ]),
      );
}
