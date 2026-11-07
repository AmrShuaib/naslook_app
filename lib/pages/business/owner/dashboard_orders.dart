import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/commerce_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/qr_scanner.dart';
import '../../../ui/widgets.dart';
import '../../chat/chat_thread_page.dart' show ChatThreadPage;
import '../biz_order_page.dart' show BizOrderPage, OrderLinesBlock, VenueActions, orderErrText;
import '../business_page.dart' show dayLabel, shortDate;
import 'business_editor.dart';

const _filters = [('upcoming', 'القادمة'), ('today', 'اليوم'), ('confirmed', 'مؤكدة'), ('used', 'مستخدمة'), ('disputed', 'مشكلات'), ('no_show', 'لم يحضر'), ('cancelled', 'ملغاة'), ('', 'الكل')];

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
    final cash = ref.watch(bizStatsProvider(widget.biz.id)).valueOrNull?.money;
    return Column(children: [
      if (cash != null && !cash.isEmpty) _MoneyStrip(cash),
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
          // مسح رمز QR من جوال العميل بالكاميرا، والإدخال اليدوي في الورقة نفسها
          FilledButton.tonalIcon(key: const Key('orders-checkin-code'), onPressed: () => checkinByCode(context, ref, widget.biz), icon: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('مسح رمز الاستلام')),
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

/// شريط مال الدائرة: المحجوز حتى الاستلام (لا يصل المحفظة بعد)، والمحرَّر إلى المحفظة، والدفع في المكان المستحق، والمشكلات المفتوحة.
class _MoneyStrip extends StatelessWidget {
  final BizMoney m;
  const _MoneyStrip(this.m);
  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, Color color, {Key? key}) => Expanded(
          key: key,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: JoyCard(
        key: const Key('orders-money'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            cell('محجوز حتى الاستلام', money(m.held), Joy.sunText, key: const Key('orders-money-held')),
            cell('وصل محفظتك', money(m.released), Joy.success, key: const Key('orders-money-released')),
            cell('يُدفع في المكان', money(m.venueDue), Joy.primary, key: const Key('orders-money-venue')),
          ]),
          const SizedBox(height: 6),
          // «تجمّد X» فقط حين يجمّد النزاع مالاً محجوزاً (النزاع على مبلغ حُرّر أو طلب قديم لا يجمّد شيئاً)
          Text(
            'يصل المبلغ محفظتك عند تأكيد الاستلام، أو بعد ${arCount(m.holdDays, one: 'يوم واحد', two: 'يومين', few: 'أيام', many: 'يوماً')} من الموعد أو الشراء'
            '${m.disputesOpen > 0 ? ' · ${arCount(m.disputesOpen, one: 'مشكلة مفتوحة', two: 'مشكلتان مفتوحتان', few: 'مشكلات مفتوحة', many: 'مشكلة مفتوحة')}${m.disputed > 0 ? ' تجمّد ${money(m.disputed)}' : ''}' : ''}',
            key: const Key('orders-money-note'),
            style: TextStyle(color: m.disputesOpen > 0 ? Joy.danger : Joy.textMuted, fontSize: 11.5),
          ),
        ]),
      ),
    );
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
          // طلب السلة: أسطره مختصرة («2 × لاتيه، 1 × كرواسون») بدل العنوان، والخيارات في ورقة الطلب
          Text(o.isCart ? o.summary : '${o.title} · ${o.summary}', key: Key('owner-order-summary-${o.id}'), style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$when · ${o.code}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          // حالة المال باختصار: مشكلة مفتوحة، أو دفع في المكان لم يُسجَّل، أو مبلغ محجوز
          if (o.disputeOpen || o.venueUnpaid || o.held)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                o.disputeOpen ? 'مشكلة من العميل · المبلغ مجمّد' : o.venueUnpaid ? 'الدفع في المكان: لم يُدفع بعد' : 'محجوز حتى الاستلام',
                key: Key('owner-order-money-${o.id}'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: o.disputeOpen ? Joy.danger : o.venueUnpaid ? Joy.sunText : Joy.textMuted),
              ),
            ),
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
        if (o.isCart) ...[
          KeyedSubtree(key: const Key('owner-order-lines'), child: OrderLinesBlock(order: o)),
          kv('الاستلام', o.pickupLabel),
        ] else ...[
          kv('العنصر', o.title),
          kv('التفاصيل', o.summary),
        ],
        if (o.startAt != null) kv(isSlotKind(o.kind) ? 'الموعد' : 'من', isSlotKind(o.kind) ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} · ${shortDate(o.startAt!)}'),
        if (o.endAt != null && !isSlotKind(o.kind)) kv('إلى', '${dayLabel(o.endAt!)} · ${shortDate(o.endAt!)}'),
        if (o.meta['guests'] != null) kv('النزلاء', '${o.meta['guests']}'),
        if (o.meta['hall'] != null) kv('الصالة', '${o.meta['hall']}'),
        if (o.note.isNotEmpty) kv('ملاحظة العميل', o.note),
        kv('المبلغ', money(o.total)),
        if (o.payment != 'free') KeyedSubtree(key: const Key('owner-money-line'), child: kv('الدفع', o.ownerMoneyLabel)),
        kv('وقت الطلب', '${dayLabel(o.createdAt ?? DateTime.now())} · ${clockOf(o.createdAt)}'),
        // الدفع في المكان: «لم يُدفع بعد» مع «تم الدفع» و«لم يحضر» بعد حلول الموعد
        if (o.venueUnpaid) ...[
          const SizedBox(height: 10),
          VenueActions(order: o, onDone: () { if (ctx.mounted) Navigator.pop(ctx); }),
        ],
        if (o.dispute != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('owner-open-dispute'),
            onPressed: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizOrderPage(orderId: o.id))); },
            icon: Icon(o.disputeOpen ? Icons.gavel_rounded : Icons.task_alt_rounded, size: 18, color: o.disputeOpen ? Joy.danger : Joy.success),
            label: Text(o.disputeOpen ? 'مشكلة من العميل · اعرضها ورد' : 'عرض قرار المشكلة', style: TextStyle(color: o.disputeOpen ? Joy.danger : Joy.success)),
          ),
        ],
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
          // بعد قرار الإدارة في نزاع الطلب لا إلغاء ينقضه (الخادم يرفضه 409)
          if (biz.canManage && o.ownerCancellable) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('owner-cancel-order'),
              onPressed: () async {
                // المحجوز يعود للعميل بلا مساس بمحفظتك؛ ما وصل محفظتك (طلب قديم أو مبلغ حُرّر) يُخصم منها؛ والدفع في المكان لا استرداد له
                final content = !o.fromWallet
                    ? (o.atVenue ? 'لم يدفع العميل عبر التطبيق، فيُلغى الطلب فقط.' : 'سيُلغى الطلب.')
                    : o.held
                        ? 'سيُعاد ${money(o.total)} كاملاً إلى العميل من المبلغ المحجوز، ولا يُخصم شيء من محفظتك.'
                        : 'سيُعاد ${money(o.total)} كاملاً إلى محفظة العميل ويُخصم من محفظتك.';
                final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(key: const Key('owner-cancel-dialog'), title: const Text('إلغاء الطلب؟'), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: Text(o.fromWallet ? 'إلغاء واسترداد' : 'إلغاء الطلب'))]));
                if (ok != true) return;
                try {
                  await ref.read(apiClientProvider).ownerCancelOrder(biz.id, o.id);
                  invalidateBizAll(ref, biz.id);
                  if (ctx.mounted) { Navigator.pop(ctx); toast(ctx, o.fromWallet ? 'أُلغي الطلب وأُعيد المبلغ للعميل' : 'أُلغي الطلب'); }
                } catch (e) { if (ctx.mounted) toast(ctx, ownerErrText(e), error: true); }
              },
              icon: const Icon(Icons.close_rounded, size: 18, color: Joy.danger),
              label: Text(o.fromWallet ? 'إلغاء واسترداد المبلغ للعميل' : 'إلغاء الطلب', style: const TextStyle(color: Joy.danger)),
            ),
          ],
        ],
      ]),
    ),
  );
}

/// تأكيد الاستلام بمسح رمز QR من جوال العميل (أو كتابته في الورقة نفسها): ملخص الطلب أولاً (من العميل، ماذا، متى، الدفع)
/// ثم «تأكيد» بطلب الخادم نفسه (POST /biz/:id/checkin بالرمز)، و«امسح التالي» يعيد الكاميرا للعميل التالي.
Future<void> checkinByCode(BuildContext context, WidgetRef ref, Biz biz) async {
  final api = ref.read(apiClientProvider);
  for (;;) {
    if (!context.mounted) return;
    final code = await showQrScanSheet(context, title: 'تأكيد الاستلام', help: 'وجّه الكاميرا إلى رمز الحجز على جوال العميل', manualHint: 'رمز الحجز مثل NAS-1A2B3C4D', check: checkVenueCode);
    if (code == null || !context.mounted) return;
    BizOrder? o;
    Object? lookupErr;
    try {
      // البحث في طلبات هذه الدائرة فقط (الصلاحية نفسها التي يحتاجها الاستلام)، ثم المطابقة التامة للرمز
      o = (await api.bizOrders(biz.id, q: code)).where((x) => x.code.toUpperCase() == code).firstOrNull;
    } catch (e) {
      lookupErr = e;
    }
    if (!context.mounted) return;
    final c = o?.customer;
    final step = await showScanSummary(
      context,
      code: code,
      header: Row(key: const Key('order-summary'), children: [
        if (c != null) ProfileAvatar(person: c, size: 46) else const Icon(Icons.receipt_long_outlined, size: 40, color: Joy.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c?.nickname.isNotEmpty == true ? c!.nickname : o == null ? 'طلب' : 'عميل', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (o != null) Text('${o.kindLabel} · ${o.statusLabel}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ])),
      ]),
      rows: [
        if (o != null) ...[
          ('العنصر', o.title),
          if (o.summary.isNotEmpty) ('التفاصيل', o.summary),
          if (o.startAt != null) (isSlotKind(o.kind) ? 'الموعد' : 'من', isSlotKind(o.kind) ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} · ${shortDate(o.startAt!)}'),
          ('المبلغ', money(o.total)),
          if (o.payment != 'free') ('الدفع', o.ownerMoneyLabel),
        ],
      ],
      // تعذر الجلب لا يمنع الاستلام: الخادم يتحقق من الرمز عند التأكيد كما في الإدخال اليدوي
      warning: lookupErr != null
          ? 'تعذر جلب تفاصيل الطلب. يمكنك التأكيد والخادم يتحقق من الرمز.'
          : o == null
              ? 'لا طلب بهذا الرمز في هذه الدائرة'
              : o.status == 'used'
                  ? 'استُخدم هذا الرمز من قبل${o.usedAt != null ? ' · ${dayLabel(o.usedAt!)} ${clockOf(o.usedAt)}' : ''}'
                  : o.status == 'cancelled'
                      ? 'هذا الطلب ملغى'
                      : o.status == 'no_show'
                          ? 'سُجّل هذا الحجز: لم يحضر'
                          : o.status != 'confirmed'
                              ? 'لا يمكن تأكيد هذا الطلب (${o.statusLabel})'
                              : o.disputeOpen
                                  ? 'مشكلة مفتوحة من العميل: يبقى المبلغ مجمّداً حتى تحسمها الإدارة'
                                  : o.venueUnpaid
                                      ? 'الدفع في المكان: اطلب ${money(o.total)} من العميل'
                                      : null,
      blocked: lookupErr == null && (o == null || o.status != 'confirmed'),
      confirmLabel: o == null ? 'تأكيد الاستلام' : o.kind == 'product' ? 'تأكيد التسليم' : isSlotKind(o.kind) ? 'تأكيد الدخول' : 'تأكيد الوصول',
      onConfirm: (sheet) async {
        final done = await api.checkinBiz(biz.id, code: code);
        invalidateBizAll(ref, biz.id);
        var msg = 'تم التأكيد · ${done.customer?.nickname.isNotEmpty == true ? '${done.customer!.nickname} · ' : ''}${done.title}';
        // حجز بالدفع في المكان: بعد الاستلام يُطلب المبلغ ويُسجَّل «تم الدفع»؛ فشل التسجيل لا يلغي الاستلام الذي تم
        if (done.venueUnpaid && sheet.mounted && await _askVenuePaid(sheet, done)) {
          try {
            await api.markVenuePaid(biz.id, done.id);
            invalidateBizAll(ref, biz.id);
            msg += ' · سُجّل الدفع';
          } catch (e) {
            msg += ' · لم يُسجَّل الدفع (${orderErrText(e)})، سجّله من ورقة الطلب';
          }
        } else if (done.isCart && sheet.mounted) {
          // طلب السلة: ما يُسلَّم للعميل سطراً سطراً بخياراته قبل إغلاق الورقة
          await _showHandover(sheet, done);
        }
        return msg;
      },
      errText: ownerErrText,
    );
    if (step == ScanStep.done) return;
  }
}

Future<bool> _askVenuePaid(BuildContext context, BizOrder o) async {
  final paid = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      key: const Key('checkin-venue-dialog'),
      title: const Text('الدفع في المكان: لم يُدفع بعد'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (o.isCart) OrderLinesBlock(order: o),
        Text('اطلب ${money(o.total)} من ${o.customer?.nickname.isNotEmpty == true ? o.customer!.nickname : 'العميل'} ثم أكّد الدفع.'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لاحقاً')), FilledButton(key: const Key('checkin-venue-paid'), onPressed: () => Navigator.pop(d, true), child: const Text('تم الدفع'))],
    ),
  );
  return paid == true;
}

/// بعد استلام طلب سلة بالرمز: ما يُسلَّم للعميل سطراً سطراً بخياراته.
Future<void> _showHandover(BuildContext context, BizOrder o) => showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        key: const Key('checkin-lines-dialog'),
        title: Text('سلّم الطلب · ${o.code}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OrderLinesBlock(order: o),
          if (o.note.isNotEmpty) Text('ملاحظة العميل: ${o.note}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ])),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('تم'))],
      ),
    );
