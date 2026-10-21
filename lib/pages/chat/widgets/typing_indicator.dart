import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../ui/profile_avatar.dart';

/// «يكتب…» بصرياً: فقاعة واردة فيها ثلاث نقاط تقفز بالتناوب، وصورة الطرف الآخر بجانبها كما لو كانت رسالة منه.
class TypingIndicator extends StatefulWidget {
  final Person peer;
  const TypingIndicator({super.key, required this.peer});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          ProfileAvatar(person: widget.peer, size: 28),
          const SizedBox(width: 6),
          Container(
            key: const Key('typing-indicator'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Joy.bubbleIn,
              border: Border.all(color: Joy.bubbleInBorder),
              borderRadius: const BorderRadiusDirectional.only(topStart: Radius.circular(18), topEnd: Radius.circular(18), bottomStart: Radius.circular(6), bottomEnd: Radius.circular(18)),
            ),
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Transform.translate(
                    // كل نقطة تتأخر عن سابقتها بثلث الدورة
                    offset: Offset(0, -4 * math.max(0, math.sin((_ctl.value - i * 0.18) * 2 * math.pi))),
                    child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Joy.textMuted, shape: BoxShape.circle)),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      );
}
