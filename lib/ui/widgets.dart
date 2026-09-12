import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// صورة شخصية: صورة الخادم إن وُجدت، وإلا الحرف الأول على لون هادئ.
class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool ring;
  final bool online;
  final double radius;
  const Avatar({super.key, required this.name, this.url, this.size = 44, this.ring = false, this.online = false, this.radius = -1});

  @override
  Widget build(BuildContext context) {
    final r = radius < 0 ? size / 2 : radius;
    final initial = name.isEmpty ? '؟' : name.characters.first.toUpperCase();
    Widget inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Joy.avatarFor(name), borderRadius: BorderRadius.circular(r)),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url != null && url!.isNotEmpty
          ? Image.network(url!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(initial, style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: Joy.text)))
          : Text(initial, style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: Joy.text)),
    );
    if (ring) {
      inner = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r + 4),
          gradient: const LinearGradient(colors: [Joy.accent, Joy.sun, Joy.primary]),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(r + 2)),
          child: inner,
        ),
      );
    }
    if (!online) return inner;
    return Stack(clipBehavior: Clip.none, children: [
      inner,
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(width: 13, height: 13, decoration: BoxDecoration(color: Joy.success, shape: BoxShape.circle, border: Border.all(color: Joy.surface, width: 2))),
      ),
    ]);
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(fontSize: 13))),
        ],
      );
}

class JoyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  const JoyCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? Joy.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Joy.line),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: card);
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72, decoration: const BoxDecoration(color: Joy.primarySoft, shape: BoxShape.circle), child: Icon(icon, color: Joy.primary, size: 32)),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: const TextStyle(color: Joy.textMuted), textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorState(this.error, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'تعذر جلب البيانات',
        subtitle: error.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), ''),
        action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      );
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  if (d.inDays == 1) return 'أمس';
  if (d.inDays < 7) return 'قبل ${d.inDays} أيام';
  return '${t.day}/${t.month}';
}

String clockOf(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'ص' : 'م'}';
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Joy.danger : null));
}

Future<String?> askText(BuildContext context, {required String title, String? hint, String confirm = 'إرسال', int maxLines = 3, String? initial}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: maxLines, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirm)),
      ],
    ),
  );
}


/// صف قائمة مسطّح على طراز واتساب: صورة، عنوان عريض، سطر ثانٍ رمادي، وعناصر في النهاية، وخط فاصل يبدأ بعد الصورة.
class ListRow extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  const ListRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.divider = true});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: Joy.text), child: title),
                if (subtitle != null) ...[const SizedBox(height: 2), DefaultTextStyle.merge(style: const TextStyle(color: Joy.textMuted, fontSize: 13), child: subtitle!)],
              ])),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
          ),
          if (divider) const Padding(padding: EdgeInsetsDirectional.only(start: 80), child: Divider(height: 1)),
        ]),
      );
}
