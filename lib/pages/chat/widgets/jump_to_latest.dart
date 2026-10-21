import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';

/// زر «إلى الأحدث» العائم: يظهر بتلاشٍ حين تبتعد القائمة عن نهايتها، ويحمل عدد رسائل الطرف الآخر الجديدة.
class JumpToLatest extends StatelessWidget {
  final bool visible;
  final int count;
  final VoidCallback onTap;
  const JumpToLatest({super.key, required this.visible, this.count = 0, required this.onTap});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedScale(
            scale: visible ? 1 : .8,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Stack(clipBehavior: Clip.none, children: [
              Material(
                color: Joy.surface,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: Colors.black26,
                child: InkWell(
                  key: const Key('jump-to-latest'),
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.keyboard_double_arrow_down_rounded, color: Joy.primary, size: 24)),
                ),
              ),
              if (count > 0)
                PositionedDirectional(
                  top: -6,
                  end: -4,
                  child: Container(
                    key: const Key('jump-count'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999), border: Border.all(color: Joy.surface, width: 1.5)),
                    child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: Joy.primaryOn, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
      );
}
