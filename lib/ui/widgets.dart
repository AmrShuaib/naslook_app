import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../api/client.dart';

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
          ? Image.network(thumbUrl(url!), width: size, height: size, fit: BoxFit.cover,
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
      // Material شفاف داخل البطاقة حتى ترسم ListTile وتأثيرات اللمس داخلها لا على أقرب Material خارجها
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: card);
  }
}

/// شاشة فارغة مفيدة: عنوان يقول ما الناقص، جملة تشرح لماذا هذا المكان أو كيف يمتلئ، وزر واحد للخطوة التالية.
/// الزر إما ودجة جاهزة في [action] (الشكل القديم) أو [actionLabel] مع [onAction] فيُبنى زر موحّد.
/// [tint] لون نوع المحتوى (من `Joy.kindColor`) للأيقونة والزر، و[compact] للاستخدام داخل بطاقة أو قسم.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Key? actionKey;
  final Color? tint;
  final bool compact;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.tint,
    this.compact = false,
  });

  Widget? _button() {
    if (action != null) return action;
    if (actionLabel == null || onAction == null) return null;
    // لون النوع الفاتح (أصفر العروض) لا يُقرأ عليه الأبيض: نص داكن حينها
    final bg = tint ?? Joy.primary;
    final fg = bg.computeLuminance() > .45 ? Joy.text : Colors.white;
    final style = FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, visualDensity: compact ? VisualDensity.compact : null);
    final label = Text(actionLabel!, textAlign: TextAlign.center);
    return actionIcon == null
        ? FilledButton(key: actionKey, onPressed: onAction, style: style, child: label)
        : FilledButton.icon(key: actionKey, onPressed: onAction, style: style, icon: Icon(actionIcon, size: 18), label: label);
  }

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Joy.primary;
    final soft = tint == null ? Joy.primarySoft : color.withValues(alpha: .12);
    final disc = compact ? 48.0 : 72.0;
    final button = _button();
    final body = Padding(
      padding: EdgeInsets.all(compact ? 16 : 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: disc, height: disc, decoration: BoxDecoration(color: soft, shape: BoxShape.circle), child: Icon(icon, color: color, size: compact ? 22 : 32)),
        SizedBox(height: compact ? 10 : 14),
        Text(title, style: TextStyle(fontSize: compact ? 15 : 17, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: TextStyle(color: Joy.textMuted, fontSize: compact ? 13 : null, height: 1.5), textAlign: TextAlign.center)],
        if (button != null) ...[SizedBox(height: compact ? 12 : 16), button],
      ]),
    );
    // داخل قائمة عمودية الارتفاع مفتوح فلا طفح؛ وخارجها (جسم صفحة بارتفاع محدود) يحميه التمرير حين يكبر الخط.
    // لا نضيف تمريراً داخل قائمة حتى لا يصير في الصفحة قابلان للتمرير.
    final inList = Scrollable.maybeOf(context, axis: Axis.vertical) != null;
    return Center(child: inList ? body : SingleChildScrollView(child: body));
  }
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
  // أقدم من أسبوع: تاريخ يُقرأ («8 نوفمبر» لا «8/11» الذي لا يُعرف أيه اليوم وأيه الشهر)، ومعه السنة إن لم تكن الحالية
  final date = '${t.day} ${_arMonths[t.month - 1]}';
  return t.year == DateTime.now().year ? date : '$date ${t.year}';
}

const _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

String clockOf(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'ص' : 'م'}';
}

/// يعرض الرسالة فوراً بدل انتظار انتهاء الرسالة السابقة في الطابور (الأخطاء لا تُحجب خلف رسائل النجاح).
void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Joy.danger : null));
}

Future<String?> askText(BuildContext context, {required String title, String? hint, String confirm = 'إرسال', int maxLines = 3, String? initial, TextInputType? keyboardType}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: maxLines, autofocus: true, keyboardType: keyboardType, decoration: InputDecoration(hintText: hint)),
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
