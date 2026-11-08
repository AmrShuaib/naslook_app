// سلة الدائرة في صفحتها العامة (نوفمبر 2026): اختيار خيارات المنتج، شريط السلة، ورقة السلة، وإتمام الطلب بملاحظة ووقت استلام
// («في أقرب وقت» أو وقت اليوم ضمن ساعات العمل) ثم الدفع من المحفظة (المبلغ محجوز حتى الاستلام) أو في المكان حين يقبله كل صنف مدفوع.
// مبلغ الإتمام من معاينة الخادم (POST /biz/:id/orders/quote) بالعرض الذي سيُطبَّق، ويُرسل مع الطلب expectTotal فلا يُخصم غيره.
// المواعيد والتذاكر والغرف والسيارات تبقى على مسار الصنف الواحد في business_page.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/client.dart' show ApiException;
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../core/platform.dart';
import '../../core/require_account.dart';
import '../../core/require_adult.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/circle_cart.dart';
import '../../ui/widgets.dart';
import '../wallet/wallet_page.dart';
import 'business_page.dart' show showActionSheet, showOrderSheet, bizErrText;

/// اختيار خيارات منتج: مجموعة لكل سطر برقائق (واحدة أو عدة)، وفرق السعر بجانب الخيار.
class ItemOptionsPicker extends StatelessWidget {
  final BizItem item;
  final Map<String, List<String>> selection;
  final ValueChanged<Map<String, List<String>>> onChanged;
  const ItemOptionsPicker({super.key, required this.item, required this.selection, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final g in item.options) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(g.ruleLabel, style: TextStyle(color: g.required ? Joy.accent : Joy.textMuted, fontSize: 11.5)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in g.choices)
              ChoiceChip(
                key: Key('opt-${g.id}-${c.id}'),
                label: Text(c.delta > 0 ? '${c.name} +${money(c.delta)}' : c.name),
                selected: selection[g.id]?.contains(c.id) == true,
                showCheckmark: g.multi,
                selectedColor: Joy.primarySoft,
                onSelected: (on) {
                  final cur = [...?selection[g.id]];
                  if (g.multi) {
                    on ? cur.add(c.id) : cur.remove(c.id);
                  } else {
                    cur
                      ..clear()
                      // الاختياري يُلغى بلمسة ثانية، والإلزامي يبقى على اختيار واحد
                      ..addAll(on || g.required ? [c.id] : const []);
                  }
                  onChanged({...selection, g.id: cur});
                },
              ),
          ]),
        ],
      ]);
}

/// شريط السلة أسفل صفحة الدائرة ما دام فيها شيء: عدد القطع والإجمالي التقديري وزر «اعرض السلة».
class CircleCartBar extends ConsumerWidget {
  final Biz biz;
  final VoidCallback onOpen;
  const CircleCartBar({super.key, required this.biz, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(circleCartProvider(biz.id));
    if (lines.isEmpty) return const SizedBox.shrink();
    final resolved = resolveCart(biz, lines);
    final pieces = lines.fold(0, (n, l) => n + l.qty);
    final total = resolved.where((r) => r.ok).fold(0, (n, r) => n + r.total);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: FilledButton(
          key: const Key('cart-bar'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: onOpen,
          child: Row(children: [
            const Icon(Icons.shopping_basket_outlined, size: 20),
            const SizedBox(width: 8),
            Text('السلة · ${arCount(pieces, one: 'قطعة واحدة', two: 'قطعتان', few: 'قطع', many: 'قطعة')}', key: const Key('cart-bar-count')),
            const Spacer(),
            Text(money(total), key: const Key('cart-bar-total'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

/// السلة ثم إتمام الطلب ثم الطلب نفسه؛ كل خطوة ورقة مستقلة تعود إلى صفحة الدائرة.
Future<void> openCircleCart(BuildContext context, WidgetRef ref, Biz biz) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
    builder: (_) => _CartSheet(bizId: biz.id, fallback: biz),
  );
  if (go != true || !context.mounted) return;
  // الطلب يُحسب من الكتالوج الأحدث (الأسعار والمخزون والخيارات قد تغيّرت منذ فتح الصفحة)
  final fresh = ref.read(bizDetailProvider(biz.id)).valueOrNull ?? biz;
  final choice = await _showCheckout(context, ref, fresh);
  if (choice == null || !context.mounted) return;
  await placeCartOrder(context, ref, fresh, payment: choice.payment, pickupAt: choice.pickupAt, note: choice.note, quote: choice.quote, loc: choice.loc);
}

class _CartSheet extends ConsumerWidget {
  final String bizId;
  final Biz fallback;
  const _CartSheet({required this.bizId, required this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biz = ref.watch(bizDetailProvider(bizId)).valueOrNull ?? fallback;
    final cart = ref.read(circleCartProvider(bizId).notifier);
    final lines = ref.watch(circleCartProvider(bizId));
    final resolved = resolveCart(biz, lines);
    final total = resolved.where((r) => r.ok).fold(0, (n, r) => n + r.total);
    final blocked = resolved.any((r) => !r.ok);
    return Column(key: const Key('cart-sheet'), mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
        child: Row(children: [
          Expanded(child: Text('سلتك في ${biz.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          if (lines.isNotEmpty)
            TextButton(
              key: const Key('cart-clear'),
              onPressed: () {
                cart.clear();
                Navigator.pop(context, false);
              },
              child: const Text('إفراغ السلة', style: TextStyle(color: Joy.danger)),
            ),
        ]),
      ),
      Flexible(
        child: lines.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('السلة فارغة', style: TextStyle(color: Joy.textMuted)))
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: resolved.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final r = resolved[i];
                  final max = r.item?.stock == null ? maxCartQty : r.item!.stock!.clamp(1, maxCartQty);
                  return Row(key: Key('cart-line-$i'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (r.optionsLabel.isNotEmpty) Text(r.optionsLabel, key: Key('cart-line-options-$i'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                        if (!r.ok) Text(r.problem!, key: Key('cart-problem-$i'), style: const TextStyle(color: Joy.danger, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (r.ok) Text('${money(r.unit)} للقطعة', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(key: Key('cart-minus-$i'), visualDensity: VisualDensity.compact, onPressed: () => cart.setQty(r.line.key, r.line.qty - 1),
                            icon: Icon(r.line.qty == 1 ? Icons.delete_outline_rounded : Icons.remove_circle_outline_rounded, color: r.line.qty == 1 ? Joy.danger : null)),
                        Text('${r.line.qty}', key: Key('cart-qty-$i'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        IconButton(key: Key('cart-plus-$i'), visualDensity: VisualDensity.compact, onPressed: r.ok && r.line.qty < max ? () => cart.setQty(r.line.key, r.line.qty + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
                      ]),
                      Text(r.ok ? money(r.total) : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ]);
                },
              ),
      ),
      if (lines.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 14 + MediaQuery.viewPaddingOf(context).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(money(total), key: const Key('cart-total'), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 17)),
              ]),
            ),
            if (blocked) const Padding(padding: EdgeInsets.only(top: 6), child: Text('احذف ما لم يعد متاحاً أو عدّل كميته لإتمام الطلب', key: Key('cart-blocked'), style: TextStyle(color: Joy.danger, fontSize: 12))),
            const SizedBox(height: 8),
            FilledButton.icon(key: const Key('cart-checkout'), onPressed: blocked ? null : () => Navigator.pop(context, true), icon: const Icon(Icons.shopping_bag_outlined), label: const Text('إتمام الطلب')),
          ]),
        ),
    ]);
  }
}

typedef _Priced = ({CartQuote? quote, LatLng? loc});
typedef _Checkout = ({String payment, DateTime? pickupAt, String note, CartQuote? quote, LatLng? loc});

/// معاينة الخادم بحساب الطلب نفسه (الأسعار الحالية والعرض الذي سيُطبَّق)، والموقع حين للدائرة عروض ليُفتح «لمن هنا الآن» في
/// المعاينة والطلب معاً. تعذّرها يُبقي التقدير المحلي والخادم يحسب المبلغ عند الطلب.
Future<_Priced> _priceCart(WidgetRef ref, Biz biz, List<CartLine> lines) async {
  LatLng? loc;
  try {
    loc = biz.offers > 0 ? await DeviceLocation.current(precise: true, timeout: const Duration(seconds: 3)) : null;
  } catch (_) {
    loc = null;
  }
  try {
    final q = await ref.read(apiClientProvider).quoteBizCart(biz.id, lines: [for (final l in lines) l.toJson()], lat: loc?.latitude, lng: loc?.longitude);
    // معاينة لا تطابق أسطر السلة (خادم أقدم) لا يُعتمد عليها
    return (quote: q.lines.length == lines.length ? q : null, loc: loc);
  } catch (_) {
    return (quote: null, loc: loc);
  }
}

/// إتمام الطلب: الأسطر والملاحظة ووقت الاستلام، ثم الدفع من المحفظة أو في المكان (إن قبله كل صنف مدفوع في السلة).
/// المبلغ المعروض والمكتوب على زر الدفع من معاينة الخادم، وهو نفسه ما يُخصم (يُرسل expectTotal)؛ الزر ينتظر المعاينة.
Future<_Checkout?> _showCheckout(BuildContext context, WidgetRef ref, Biz biz) async {
  final lines = ref.read(circleCartProvider(biz.id));
  final resolved = resolveCart(biz, lines);
  if (resolved.isEmpty || resolved.any((r) => !r.ok)) return null;
  final estimate = resolved.fold(0, (n, r) => n + r.total);
  _Priced? got;
  final priced = _priceCart(ref, biz, lines).then((v) => got = v);
  final times = biz.pickupTimes;
  var note = '';
  DateTime? pickup;
  String two(int n) => n.toString().padLeft(2, '0');
  String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
  Widget priceOf(Widget Function(CartQuote? q, bool waiting) build) =>
      FutureBuilder<_Priced>(future: priced, builder: (_, snap) => build(snap.data?.quote, snap.connectionState != ConnectionState.done));
  final pay = await showActionSheet<String>(
    context,
    body: (ctx, setS) => Column(key: const Key('checkout-sheet'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('إتمام الطلب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      Text(biz.title, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
      const SizedBox(height: 10),
      priceOf((q, waiting) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, r) in resolved.indexed)
              Padding(
                key: Key('checkout-line-$i'),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.line.qty} × ${r.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (r.optionsLabel.isNotEmpty) Text(r.optionsLabel, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    ]),
                  ),
                  // بالمعاينة: مجموع السطر بأسعار الدائرة الحالية قبل العرض، والتوفير في سطره تحت الأسطر
                  Text(money(q != null ? q.lines[i].total : r.total), key: Key('checkout-line-total-$i'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            if (q != null && q.discount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.local_offer_rounded, size: 15, color: Joy.success),
                  const SizedBox(width: 6),
                  Expanded(child: Text('وفّرت ${money(q.discount)} بعرض «${q.offer?.title ?? ''}»', key: const Key('checkout-savings'), style: const TextStyle(color: Joy.success, fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
          ])),
      const Divider(height: 18),
      const Text('وقت الاستلام', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(key: const Key('pickup-asap'), label: const Text('في أقرب وقت'), selected: pickup == null, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setS(() => pickup = null)),
        for (final t in times ?? const <DateTime>[])
          ChoiceChip(key: Key('pickup-${clock(t)}'), label: Text(clock(t), style: const TextStyle(fontFamily: AppTheme.bodyFont)), selected: pickup == t, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setS(() => pickup = t)),
      ]),
      // الساعات غير المفهومة لا تعطي أوقاتاً: «في أقرب وقت» وحده (والخادم يرفض غيره)
      if (times == null)
        const Padding(padding: EdgeInsets.only(top: 4), child: Text('لم تحدد الدائرة ساعات عملها، فيُجهَّز الطلب في أقرب وقت', key: Key('pickup-asap-only'), style: TextStyle(color: Joy.textMuted, fontSize: 12)))
      else if (times.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 4), child: Text('لا أوقات متبقية اليوم ضمن ساعات العمل', key: Key('pickup-none-left'), style: TextStyle(color: Joy.textMuted, fontSize: 12))),
      const SizedBox(height: 10),
      _NoteField(onChanged: (v) => note = v),
      priceOf((q, waiting) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (waiting) const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: SizedBox(key: Key('checkout-quoting'), width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
              Text(money(q?.total ?? estimate), key: const Key('checkout-total'), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 17)),
            ]),
          )),
      priceOf((q, waiting) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              q != null ? 'هذا ما يُخصم عند الطلب، بأسعار الدائرة الحالية والعروض المتاحة لك.' : 'يُحسب المبلغ النهائي من أسعار الدائرة الحالية عند الطلب، والعروض تُطبَّق تلقائياً.',
              style: const TextStyle(color: Joy.textMuted, fontSize: 11.5),
            ),
          )),
    ]),
    action: (ctx, _) => priceOf((q, waiting) {
      final total = q?.total ?? estimate;
      final venue = total > 0 && (q?.venueOk ?? resolved.every((r) => r.venueOk));
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          key: const Key('checkout-pay-wallet'),
          onPressed: waiting ? null : () => Navigator.pop(ctx, 'wallet'),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(total == 0 ? 'أرسل الطلب' : venue ? 'ادفع الآن من المحفظة · ${money(total)}' : 'ادفع ${money(total)} من المحفظة'),
        ),
        if (venue) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('checkout-pay-venue'), onPressed: waiting ? null : () => Navigator.pop(ctx, 'at_venue'), icon: const Icon(Icons.storefront_outlined), label: const Text('اطلب الآن وادفع في المكان')),
        ],
      ]);
    }),
  );
  return pay == null ? null : (payment: pay, pickupAt: pickup, note: note.trim(), quote: got?.quote, loc: got?.loc);
}

/// حقل الملاحظة يملك متحكّمه فيُتلف مع الورقة بعد انتهاء حركة إغلاقها (لا قبلها)
class _NoteField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _NoteField({required this.onChanged});
  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  final c = TextEditingController();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('checkout-note'), controller: c, maxLines: 2, maxLength: 300, onChanged: widget.onChanged,
        decoration: const InputDecoration(labelText: 'ملاحظة للدائرة (اختياري)', hintText: 'مثلاً: بدون سكر'),
      );
}

/// يرسل السلة طلباً واحداً بالمبلغ الذي عرضته المعاينة [quote] (expectTotal)؛ عند «الرصيد غير كافٍ» يعرض الدفع في المكان مخرجاً
/// حين يقبله كل صنف مدفوع (وفي iOS لا دعوة للشحن)، وعند تغيّر المبلغ منذ المعاينة لا يُخصم شيء ويُخبر بالمبلغ الجديد.
Future<void> placeCartOrder(BuildContext context, WidgetRef ref, Biz biz, {required String payment, DateTime? pickupAt, String note = '', CartQuote? quote, LatLng? loc}) async {
  if (!requireAccount(context)) return;
  final lines = ref.read(circleCartProvider(biz.id));
  final resolved = resolveCart(biz, lines);
  if (resolved.isEmpty) return;
  final total = quote?.total ?? resolved.fold<int>(0, (n, r) => n + r.total);
  // الطلب المدفوع (والدفع في المكان كذلك) يحتاج إقرار 18+ مرة واحدة؛ السلة المجانية لا
  if (total > 0 && (!await requireAdult(context, ref) || !context.mounted)) return;
  final venue = total > 0 && (quote?.venueOk ?? resolved.every((r) => r.venueOk));
  try {
    final at = quote != null ? loc : biz.offers > 0 ? await DeviceLocation.current(precise: true, timeout: const Duration(seconds: 3)) : null;
    final o = await ref.read(apiClientProvider).orderBizCart(biz.id,
        lines: [for (final l in lines) l.toJson()], note: note, pickupAt: pickupAt, payment: payment, lat: at?.latitude, lng: at?.longitude, expectTotal: quote?.total);
    ref.read(circleCartProvider(biz.id).notifier).clear();
    invalidateBiz(ref, biz.id);
    ref.invalidate(walletProvider);
    if (context.mounted) showOrderSheet(context, o, biz: biz);
  } catch (e) {
    if (!context.mounted) return;
    // تغيّر السعر أو العرض بين المعاينة والطلب: الخادم لم يخصم شيئاً، والسلة باقية ليراجعها بالمبلغ الجديد
    if (e is ApiException && e.body?['error'] == 'total-changed') {
      invalidateBiz(ref, biz.id);
      final now = e.body?['total'];
      toast(context, now is num ? 'تغيّر مبلغ الطلب إلى ${money(now.toInt())}، راجع سلتك وأعد المحاولة' : 'تغيّر مبلغ الطلب، راجع سلتك وأعد المحاولة', error: true);
      return;
    }
    if (!e.toString().contains('insufficient-funds')) {
      // سعر أو مخزون أو خيار تغيّر: نحدّث الكتالوج فتظهر المشكلة على سطرها في السلة
      invalidateBiz(ref, biz.id);
      toast(context, bizErrText(e), error: true);
      return;
    }
    if (isIosNative) {
      final atVenue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('cart-funds-ios'),
          title: const Text('الرصيد غير كافٍ'),
          content: Text(venue ? 'رصيد محفظتك لا يغطي هذا المبلغ. يمكنك الطلب الآن والدفع في المكان.' : 'رصيد محفظتك لا يغطي هذا المبلغ'),
          actions: [
            if (venue) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
            if (venue)
              FilledButton(key: const Key('cart-funds-venue'), onPressed: () => Navigator.pop(ctx, true), child: const Text('اطلب وادفع في المكان'))
            else
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
          ],
        ),
      );
      if (atVenue == true && context.mounted) await placeCartOrder(context, ref, biz, payment: 'at_venue', pickupAt: pickupAt, note: note, quote: quote, loc: loc);
      return;
    }
    final go = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('cart-funds'),
        title: const Text('الرصيد غير كافٍ'),
        content: Text(venue ? 'رصيد محفظتك لا يغطي هذا المبلغ. اشحن المحفظة ثم أعد المحاولة، أو اطلب الآن وادفع في المكان.' : 'رصيد محفظتك لا يغطي هذا المبلغ. اشحن المحفظة ثم أعد المحاولة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          if (venue) TextButton(key: const Key('cart-funds-venue'), onPressed: () => Navigator.pop(ctx, 'venue'), child: const Text('ادفع في المكان')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'wallet'), child: const Text('المحفظة')),
        ],
      ),
    );
    if (!context.mounted) return;
    if (go == 'wallet') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage()));
    if (go == 'venue') await placeCartOrder(context, ref, biz, payment: 'at_venue', pickupAt: pickupAt, note: note, quote: quote, loc: loc);
  }
}
