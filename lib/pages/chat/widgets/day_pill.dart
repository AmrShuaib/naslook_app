import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';

/// حبّة فاصل اليوم بين مجموعات الرسائل («اليوم»، «أمس»، اسم اليوم، أو التاريخ) مع 16 نقطة حولها.
class DayPill extends StatelessWidget {
  final String label;
  const DayPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: const TextStyle(fontSize: 11, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
