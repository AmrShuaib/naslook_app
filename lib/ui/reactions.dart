import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';

/// تفاعل بإيموجي على مشاركة أو رد أو رسالة: الإيموجي وعدده وهل هو تفاعلي.
class Reaction {
  final String emoji;
  final int count;
  final bool mine;
  const Reaction({required this.emoji, required this.count, this.mine = false});
  factory Reaction.fromJson(Map m) => Reaction(emoji: m['emoji']?.toString() ?? '', count: (m['count'] as num?)?.toInt() ?? 0, mine: m['mine'] == true);
}

/// المجموعة الثابتة المسموحة على الخادم (بالترتيب المعروض في شريط الاختيار).
const reactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👏', '☕', '👍'];

List<Reaction> parseReactions(dynamic v) => [for (final r in (v is List ? v : const [])) if (r is Map) Reaction.fromJson(r)];

/// يطبّق نتيجة تفاعلي محلياً على قائمة تفاعلات (قبل وصول رد الخادم أو بدونه).
List<Reaction> applyMyReaction(List<Reaction> current, String? emoji) {
  final out = <Reaction>[];
  var placed = false;
  for (final r in current) {
    var c = r.count, mine = r.mine;
    if (r.mine) {
      c -= 1;
      mine = false;
    }
    if (emoji != null && r.emoji == emoji) {
      c += 1;
      mine = true;
      placed = true;
    }
    if (c > 0) out.add(Reaction(emoji: r.emoji, count: c, mine: mine));
  }
  if (emoji != null && !placed) out.add(Reaction(emoji: emoji, count: 1, mine: true));
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// شريط اختيار عائم يظهر عند موضع الضغط المطوّل (كما في واتساب): يعيد الإيموجي المختار أو null.
Future<String?> showReactionPicker(BuildContext context, {Offset? at, String? current}) {
  HapticFeedback.mediumImpact();
  final size = MediaQuery.sizeOf(context);
  const width = 8 * 46.0 + 12;
  final left = ((at?.dx ?? size.width / 2) - width / 2).clamp(8.0, size.width - width - 8);
  final top = ((at?.dy ?? size.height / 2) - 72).clamp(48.0, size.height - 80);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق',
    barrierColor: Colors.black.withValues(alpha: .08),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: .85, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)), alignment: Alignment.center, child: child)),
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        child: Material(
          key: const Key('reaction-picker'),
          color: Joy.surface,
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in reactionEmojis)
                InkWell(
                  key: Key('react-$e'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx, e),
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: e == current ? Joy.primarySoft : null),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]),
  );
}

/// شرائح التفاعلات تحت المحتوى: الإيموجي وعدده، وتفاعلي مظلّل؛ اللمس يبدّل تفاعلي على هذا الإيموجي.
class ReactionChips extends StatelessWidget {
  final List<Reaction> reactions;
  final ValueChanged<String>? onTap;
  final bool compact;
  const ReactionChips({super.key, required this.reactions, this.onTap, this.compact = false});
  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final r in reactions)
        InkWell(
          key: Key('chip-${r.emoji}'),
          borderRadius: BorderRadius.circular(999),
          onTap: onTap == null ? null : () => onTap!(r.emoji),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 1 : 2),
            decoration: BoxDecoration(
              color: r.mine ? Joy.primarySoft : Joy.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: r.mine ? Joy.primary.withValues(alpha: .5) : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(r.emoji, style: TextStyle(fontSize: compact ? 12 : 14)),
              const SizedBox(width: 3),
              Text('${r.count}', style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: r.mine ? Joy.primary : Joy.textMuted)),
            ]),
          ),
        ),
    ]);
  }
}

/// كاشف نقر مزدوج لا يؤخّر النقرات المفردة: يراقب نزول المؤشر فقط (خارج ساحة الإيماءات)، فتبقى أزرار
/// التشغيل والروابط داخل الفقاعة فورية، وينطلق [onDoubleTap] عند نزولين متقاربين زمناً ومكاناً.
class DoubleTapDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDoubleTap;
  const DoubleTapDetector({super.key, required this.child, this.onDoubleTap});
  @override
  State<DoubleTapDetector> createState() => _DoubleTapDetectorState();
}

class _DoubleTapDetectorState extends State<DoubleTapDetector> {
  DateTime? _lastDown;
  Offset? _lastPos;
  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          final now = DateTime.now();
          final last = _lastDown;
          if (last != null && _lastPos != null && now.difference(last) < const Duration(milliseconds: 350) && (e.position - _lastPos!).distance < 40) {
            _lastDown = null;
            _lastPos = null;
            widget.onDoubleTap?.call();
            return;
          }
          _lastDown = now;
          _lastPos = e.position;
        },
        child: widget.child,
      );
}

/// قلب أحمر كبير ينبثق ثم يتلاشى عند النقر المزدوج (كما في إنستغرام). يُشغَّل كلما تغيّر [trigger].
class HeartBurst extends StatelessWidget {
  final int trigger;
  final double size;
  const HeartBurst({super.key, required this.trigger, this.size = 96});
  @override
  Widget build(BuildContext context) {
    if (trigger == 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(trigger),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 850),
        curve: Curves.linear,
        builder: (_, t, __) {
          final scale = t < .3 ? .3 + (t / .3) * .95 : 1.25 - ((t - .3) / .7) * .25;
          final opacity = t < .65 ? 1.0 : (1 - t) / .35;
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: Icon(Icons.favorite_rounded, key: const Key('heart-burst'), size: size, color: const Color(0xFFE0245E), shadows: const [Shadow(color: Colors.black26, blurRadius: 12)])),
          );
        },
      ),
    );
  }
}
