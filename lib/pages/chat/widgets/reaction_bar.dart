import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../ui/reactions.dart';

/// شريط الإيموجي أعلى خيارات الرسالة: كل إيموجي ينبثق بمنحنى ارتداد متأخّر قليلاً عن سابقه.
class ReactionBar extends StatelessWidget {
  /// إيموجيي الحالي على الرسالة (مظلّل) إن وُجد.
  final String? selected;
  final ValueChanged<String> onPick;
  const ReactionBar({super.key, this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < reactionEmojis.length; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 220 + i * 35),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
              child: InkWell(
                key: Key('react-${reactionEmojis[i]}'),
                customBorder: const CircleBorder(),
                onTap: () => onPick(reactionEmojis[i]),
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: selected == reactionEmojis[i] ? Joy.primarySoft : Joy.surface2),
                  child: Text(reactionEmojis[i], style: const TextStyle(fontSize: 22)),
                ),
              ),
            ),
        ]),
      );
}
