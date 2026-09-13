import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/commerce_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import '../../chat/chat_thread_page.dart' show ChatThreadPage;
import '../business_page.dart' show dayLabel, shortDate;
import 'business_editor.dart';

const _filters = [('upcoming', 'القادمة'), ('today', 'اليوم'), ('confirmed', 'مؤكدة'), ('used', 'مستخدمة'), ('cancelled', 'ملغاة'), ('', 'الكل')];

/// طلبات الدائرة لصاحبها وطاقمه: تصفية بالحالة، بحث بالرمز، تأكيد الاستلام، إلغاء واسترداد للعميل.
class OrdersTab extends ConsumerStatefulWidget {
  final Biz biz;
  const OrdersTab({super.key, required this.biz});
  @override
  ConsumerState<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<OrdersTab> {
  String status = 'upcoming';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(bizOrdersProvider((id: widget.biz.id, status: status)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => q = v.trim().toUpperCase()),
              decoration: const InputDecoration(hintText: 'ابحث برمز الحجز NAS-…', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(onPressed: () => checkinByCode(context, ref, widget.biz), icon: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('استلام')),
        ]),
      ),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          for (final (key, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(label: Text(label, style: TextStyle(color: status == key ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: status == key, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => status = key)),
            ),
        ]),
      ),
      Expanded(
        child: list.when(
          data: (orders) {
            final shown = q.isEmpty ? orders : orders.where((o) => o.code.contains(q) || (o.customer?.nickname.toUpperCase().contains(q) ?? false)).toList();
            if (shown.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, title: q.isEmpty ? 'لا طلبات هنا' : 'لا نتائج', subtitle: status == 'upcoming' ? 'الطلبات والحجوزات القادمة تظهر هنا فور وصولها.' : null);
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(bizOrdersProvider),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: shown.length,
                itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: OwnerOrderCard(biz: widget.biz, o: shown[i])),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizOrdersProvider)),
        ),
      ),
    ]);
  }
}

class OwnerOrderCard extends ConsumerWidget {
  final Biz biz;
  final BizOrder o;
  const OwnerOrderCard({super.key, required this.biz, required this.o});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = o.customer;
    final active = o.status == 'confirmed';
    final when = o.startAt == null ? 'طُلب ${timeAgo(o.createdAt)}' : isSlotKind(o.kind) ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} ${shortDate(o.startAt!)}${o.endAt != null ? ' → ${shortDate(o.endAt!)}' : ''}';
    return JoyCard(
      onTap: () => showOwnerOrderSheet(context, ref, biz, o),
      child: Row(children: [
        if (c != null) ProfileAvatar(person: c, size: 44) else const Avatar(name: '?', size: 44),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(c?.nickname.isNotEmpty == true ? c!.nickname : 'عميل', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: active ? Joy.primarySoft : o.status == 'used' ? Joy.sunSoft : Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(o.statusLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Joy.primary : o.status == 'used' ? Joy.sunText : Joy.textMuted))),
          ]),
          Text('${o.title} · ${o.summary}', style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$when · ${o.code}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Text(money(o.total), style: TextStyle(fontWeight: FontWeight.w800, color: active ? Joy.primary : Joy.textMuted, fontSize: 13.5)),
      ]),
    );
  }
}

/// ورقة طلب من جهة صاحب النشاط: تفاصيل العميل والحجز، تأكيد الاستلام، الإلغاء مع الاسترداد، مراسلة العميل.
void showOwnerOrderSheet(BuildContext context, WidgetRef ref, Biz biz, BizOrder o) {
  Widget kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(color: Joy.textMuted)), const SizedBox(width: 12), Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]));
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (o.customer != null) ProfileAvatar(person: o.customer!, size: 48),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.customer?.nickname.isNotEmpty == true ? o.customer!.nickname : 'عميل', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text('${o.kindLabel} · ${o.statusLabel}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          if (o.customer != null && o.customer!.id.isNotEmpty)
            IconButton(tooltip: 'مراسلة', onPressed: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: o.customer!))); }, icon: const Icon(Icons.chat_bubble_outline_rounded, color: Joy.primary)),
        ]),
        const SizedBox(height: 12),
        SelectableText(o.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 18, color: Joy.primary)),
        const SizedBox(height: 8),
        kv('العنصر', o.title),
        kv('التفاصيل', o.summary),
        if (o.startAt != null) kv(isSlotKind(o.kind) ? 'الموعد' : 'من', isSlotKind(o.kind) ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} · ${shortDate(o.startAt!)}'),
        if (o.endAt != null && !isSlotKind(o.kind)) kv('إلى', '${dayLabel(o.endAt!)} · ${shortDate(o.endAt!)}'),
        if (o.meta['guests'] != null) kv('النزلاء', '${o.meta['guests']}'),
        if (o.meta['hall'] != null) kv('الصالة', '${o.meta['hall']}'),
        if (o.note.isNotEmpty) kv('ملاحظة العميل', o.note),
        kv('المبلغ', money(o.total)),
        kv('وقت الطلب', '${dayLabel(o.createdAt ?? DateTime.now())} · ${clockOf(o.createdAt)}'),
        const SizedBox(height: 14),
        if (o.status == 'confirmed') ...[
          FilledButton.icon(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).checkinBiz(biz.id, orderId: o.id);
                invalidateBizAll(ref, biz.id);
                if (ctx.mounted) { Navigator.pop(ctx); toast(ctx, 'تم تأكيد الاستلام'); }
              } catch (e) { if (ctx.mounted) toast(ctx, ownerErrText(e), error: true); }
            },
            icon: const Icon(Icons.task_alt_rounded),
            label: Text(o.kind == 'product' ? 'تأكيد التسليم' : isSlotKind(o.kind) ? 'تأكيد الدخول' : 'تأكيد الوصول'),
          ),
          if (biz.canManage) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(title: const Text('إلغاء الطلب؟'), content: Text('سيُعاد ${money(o.total)} كاملاً إلى محفظة العميل ويُخصم من محفظتك.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إلغاء واسترداد'))]));
                if (ok != true) return;
                try {
                  await ref.read(apiClientProvider).ownerCancelOrder(biz.id, o.id);
                  invalidateBizAll(ref, biz.id);
                  if (ctx.mounted) { Navigator.pop(ctx); toast(ctx, 'أُلغي الطلب وأُعيد المبلغ للعميل'); }
                } catch (e) { if (ctx.mounted) toast(ctx, ownerErrText(e), error: true); }
              },
              icon: const Icon(Icons.close_rounded, size: 18, color: Joy.danger),
              label: const Text('إلغاء واسترداد المبلغ للعميل', style: TextStyle(color: Joy.danger)),
            ),
          ],
        ],
      ]),
    ),
  );
}

/// تأكيد الاستلام بإدخال رمز الحجز يدوياً (أو لصقه من ماسح QR).
Future<void> checkinByCode(BuildContext context, WidgetRef ref, Biz biz) async {
  final code = await askText(context, title: 'تأكيد الاستلام', hint: 'رمز الحجز مثل NAS-1A2B3C4D', confirm: 'تأكيد', maxLines: 1);
  if (code == null || code.trim().isEmpty) return;
  try {
    final o = await ref.read(apiClientProvider).checkinBiz(biz.id, code: code.trim().toUpperCase());
    invalidateBizAll(ref, biz.id);
    if (!context.mounted) return;
    toast(context, 'تم التأكيد · ${o.customer?.nickname ?? ''} · ${o.title}');
  } catch (e) {
    if (context.mounted) toast(context, ownerErrText(e), error: true);
  }
}
