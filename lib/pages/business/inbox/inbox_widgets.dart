import 'package:flutter/material.dart';

import '../../../api/biz_inbox_api.dart';
import '../../../api/client.dart' show thumbUrl;
import '../../../core/app_theme.dart';

/// شعار الدائرة في المحادثة والقوائم: الصورة المرفوعة أو المضمّنة (asset:)، وإلا أول حرفين من اسمها.
class BizCircleLogo extends StatelessWidget {
  final BizInboxCircle circle;
  final double size;
  const BizCircleLogo({super.key, required this.circle, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final letters = circle.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w.characters.first.toUpperCase()).take(2).join();
    Widget fallback([BuildContext? _, Object? __, StackTrace? ___]) =>
        Center(child: Text(letters.isEmpty ? '؟' : letters, style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w800, fontSize: size * .36)));
    final logo = circle.logoUrl;
    final Widget child = logo == null || logo.isEmpty
        ? fallback()
        : logo.startsWith('asset:')
            ? Image.asset('assets/${logo.substring(6)}', fit: BoxFit.cover, errorBuilder: fallback)
            : Image.network(thumbUrl(logo), fit: BoxFit.cover, errorBuilder: fallback);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(size * .28), border: Border.all(color: Joy.surface, width: 2)),
      child: child,
    );
  }
}

/// شارة «دائرة غير موثّقة»: الدائرة لم تُعتمد وثيقتها بعد (المراسلة مسموحة، والتنبيه للعميل).
class UnverifiedTag extends StatelessWidget {
  final bool compact;
  const UnverifiedTag({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 1 : 3),
        decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.gpp_maybe_outlined, size: compact ? 12 : 14, color: Joy.sunText),
          const SizedBox(width: 3),
          Text('دائرة غير موثّقة', style: TextStyle(fontSize: compact ? 10.5 : 11.5, color: Joy.sunText, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// شارة عدد غير المقروء بلون العلامة.
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge(this.count, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)),
        alignment: Alignment.center,
        child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(color: Joy.primaryOn, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
