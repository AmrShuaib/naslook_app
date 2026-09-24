// عروضي وطلباتي: عروضي بحالاتها (مسودة، مجدول، قيد المراجعة، ظاهر، مخفي) مع رفع وسبوت لايت؛ والطلبات بمراحلها
// ورمز الاستلام والتأكيد والإلغاء والنزاع والتقييم والفاتورة.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat/chat_thread_page.dart';

import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../wallet/wallet_page.dart';
import 'market_page.dart';
import 'seller_tools.dart';

final myListingsProvider = FutureProvider<List<Listing>>((ref) => ref.watch(apiClientProvider).myListings());
final ordersProvider = FutureProvider<List<Order>>((ref) => ref.watch(apiClientProvider).orders());

class OrdersPage extends ConsumerWidget {
  /// 0 = عروضي، 1 = الطلبات
  final int initialTab;
  const OrdersPage({super.key, this.initialTab = 1});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2, initialIndex: initialTab.clamp(0, 1),
        child: Scaffold(
          backgroundColor: Joy.bg,
          appBar: AppBar(title: const Text('عروضي وطلباتي'), bottom: const TabBar(tabs: [Tab(text: 'عروضي'), Tab(text: 'الطلبات')]), actions: [
            IconButton(tooltip: 'لوحة البائع', icon: const Icon(Icons.insights_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerDashboardPage()))),
          ]),
          body: const TabBarView(children: [_MyListings(), _MyOrders()]),
        ),
      );
}

class _MyOrders extends ConsumerWidget {
  const _MyOrders();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(ordersProvider);
    return o.when(
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا طلبات بعد')
          : RefreshIndicator(onRefresh: () async => ref.invalidate(ordersProvider), child: ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => OrderCard(list[i]))),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(ordersProvider)),
    );
  }
}

class _MyListings extends ConsumerWidget {
  const _MyListings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(myListingsProvider);
    return l.when(
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.storefront_outlined, title: 'لم تعرض شيئاً للبيع بعد', subtitle: 'من صفحة السوق اضغط «اعرض للبيع» وأضف صوراً ووصفاً وسعراً.')
          : RefreshIndicator(onRefresh: () async => ref.invalidate(myListingsProvider), child: ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => MyListingRow(list[i]))),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myListingsProvider)),
    );
  }
}

String listingStatusLabel(String status) => switch (status) { 'active' => 'ظاهر في السوق', 'hidden' => 'مخفي', 'blocked' => 'أخفته الإدارة', 'draft' => 'مسودة', 'scheduled' => 'مجدول للنشر', 'pending' => 'بانتظار المراجعة', _ => status };
Color listingStatusColor(String status) => switch (status) { 'active' => Joy.success, 'blocked' => Joy.danger, 'pending' || 'scheduled' => Joy.warning, _ => Joy.textMuted };

Future<void> toggleListingVisibility(BuildContext context, WidgetRef ref, Listing x) async {
  try {
    final next = x.status == 'active' ? 'hidden' : 'active';
    await ref.read(apiClientProvider).updateListing(x.id, {'status': next});
    invalidateMarket(ref); ref.invalidate(listingProvider(x.id));
    if (context.mounted) toast(context, next == 'active' ? 'صار العرض ظاهراً في السوق' : 'أُخفي العرض ولا يراه غيرك');
  } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
}

/// يفتح نموذج التعديل ويرفع الصور الجديدة إن اختيرت ثم يحفظ.
Future<void> editListing(BuildContext context, WidgetRef ref, Listing x) async {
  final d = await showListingForm(context, initial: x);
  if (d == null || !context.mounted) return;
  try {
    final api = ref.read(apiClientProvider);
    final urls = [...d.existingImages];
    for (final img in d.newImages) {
      urls.add((await api.uploadMedia(img.bytes, contentType: img.mime, fileName: img.name)).url);
    }
    final body = d.toBody()..remove('publishAt')..addAll({'images': urls, 'imageUrl': urls.isEmpty ? null : urls.first});
    if (x.status != 'draft') body.remove('status');
    await api.updateListing(x.id, body);
    invalidateMarket(ref); ref.invalidate(listingProvider(x.id));
    if (context.mounted) toast(context, 'حُفظت التعديلات');
  } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
}

class MyListingRow extends ConsumerWidget {
  final Listing l;
  const MyListingRow(this.l, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Row(children: [
          Container(width: 52, height: 52, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
            child: l.imageUrl != null && l.imageUrl!.isNotEmpty ? Image.network(thumbUrl(l.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Joy.textMuted)) : const Icon(Icons.storefront_outlined, color: Joy.textMuted)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('${l.price == 0 ? 'مجاناً' : money(l.price)} · ${listingStatusLabel(l.status)}${l.spotlight ? ' · سبوت لايت' : ''}', style: TextStyle(color: listingStatusColor(l.status), fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text('${l.views} مشاهدة · ${l.sold} مبيعة${l.stock != null ? ' · المتوفر ${l.stock}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ])),
          if (l.status == 'blocked') const Icon(Icons.block_rounded, color: Joy.danger)
          else if (l.status == 'draft') TextButton(onPressed: () => editListing(context, ref, l), child: const Text('أكمل ونشر'))
          else if (l.status == 'active' || l.status == 'hidden') IconButton(tooltip: l.status == 'active' ? 'إخفاء' : 'إظهار', onPressed: () => toggleListingVisibility(context, ref, l), icon: Icon(l.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: l.status == 'active' ? Joy.textMuted : Joy.primary)),
        ]),
      );
}

/// إجراءات صاحب العرض داخل صفحته
class OwnerListingActions extends ConsumerWidget {
  final Listing x;
  const OwnerListingActions(this.x, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (x.status != 'active')
          Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: x.status == 'blocked' ? Joy.accentSoft : Joy.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(x.status == 'blocked' ? Icons.block_rounded : x.status == 'pending' ? Icons.hourglass_top_rounded : Icons.visibility_off_outlined, color: x.status == 'blocked' ? Joy.accent : Joy.textMuted), const SizedBox(width: 8),
              Expanded(child: Text(switch (x.status) { 'blocked' => 'أخفته الإدارة من السوق؛ تواصل مع الدعم إن كان ذلك خطأً.', 'pending' => 'بانتظار مراجعة الإدارة، وسيظهر بعد الموافقة.', 'draft' => 'مسودة لم تُنشر بعد.', 'scheduled' => 'مجدول للنشر ${x.publishAt != null ? '${x.publishAt!.day}/${x.publishAt!.month} ${clockOf(x.publishAt)}' : ''}', _ => 'العرض مخفي ولا يراه أحد غيرك.' }, style: TextStyle(color: x.status == 'blocked' ? Joy.accent : Joy.text, fontSize: 13))),
            ])),
        Row(children: [_stat('المشاهدات', '${x.views}'), _stat('المبيعات', '${x.sold}'), if (x.ratingAvg != null) _stat('التقييم', x.ratingAvg!.toStringAsFixed(1))]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(key: const Key('owner-edit'), onPressed: () => editListing(context, ref, x), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل')),
          if (x.status == 'active' || x.status == 'hidden')
            OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: x.status == 'active' ? Joy.danger : Joy.primary), onPressed: () => toggleListingVisibility(context, ref, x), icon: Icon(x.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18), label: Text(x.status == 'active' ? 'إخفاء العرض' : 'إظهار العرض')),
          if (x.status == 'draft') FilledButton.icon(onPressed: () => editListing(context, ref, x), icon: const Icon(Icons.publish_rounded, size: 18), label: const Text('أكمل ونشر')),
          if (x.status == 'active') OutlinedButton.icon(key: const Key('owner-bump'), onPressed: () async { try { await ref.read(apiClientProvider).bumpListing(x.id); invalidateMarket(ref); if (context.mounted) toast(context, 'رُفع عرضك إلى الأعلى'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); } }, icon: const Icon(Icons.arrow_upward_rounded, size: 18), label: const Text('رفع للأعلى')),
          // سبوت لايت إعلان رقمي مدفوع: لا يُباع في iOS
          if (x.status == 'active' && !isIosNative) FilledButton.tonalIcon(key: const Key('owner-spotlight'), onPressed: () => showSpotlightSheet(context, ref, listing: x), icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: Text(x.spotlight ? 'تمديد سبوت لايت' : 'سبوت لايت')),
        ]),
      ]);
  Widget _stat(String l, String v) => Padding(padding: const EdgeInsets.only(left: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text(l, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]));
}

Color orderStatusColor(String s) => switch (s) { 'completed' => Joy.success, 'cancelled' || 'refunded' => Joy.textMuted, 'disputed' => Joy.danger, 'delivered' => Joy.primary, _ => Joy.warning };

class OrderCard extends ConsumerWidget {
  final Order o;
  const OrderCard(this.o, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = o.mineAsSeller || o.mineAsCourier ? o.buyer : o.seller;
    return JoyCard(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderPage(o.id))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ProfileAvatar(person: other, size: 40), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${o.title}${o.variant != null ? ' (${o.variant})' : ''}${o.qty > 1 ? ' × ${o.qty}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          Text('${o.mineAsCourier ? 'توصيل إلى' : o.mineAsSeller ? 'المشتري' : 'البائع'}: ${other.nickname} · ${timeAgo(o.createdAt)}${o.slot != null ? ' · موعد ${o.slot!.day}/${o.slot!.month} ${clockOf(o.slot)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ])),
        Text(money(o.total), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: orderStatusColor(o.status).withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(o.status == 'delivered' && !o.mineAsSeller ? 'تم التسليم · أكّد الاستلام' : orderStatusLabels[o.status] ?? o.status, style: TextStyle(color: orderStatusColor(o.status), fontSize: 12, fontWeight: FontWeight.w700))),
        const Spacer(),
        if (o.status == 'completed' && !o.mineAsSeller && !o.reviewed) TextButton(onPressed: () => reviewOrder(context, ref, o), child: const Text('قيّم')),
        if (o.status == 'paid' && o.mineAsSeller) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 38)), onPressed: () => advanceOrder(context, ref, o, 'preparing'), child: const Text('بدء التحضير')),
        if (!o.mineAsSeller && o.code != null && o.open) Text('رمزك ${o.code}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
      ]),
    ]));
  }
}

Future<void> advanceOrder(BuildContext context, WidgetRef ref, Order o, String stage) async {
  try { await ref.read(apiClientProvider).orderStage(o.id, stage); ref.invalidate(ordersProvider); ref.invalidate(orderProvider(o.id)); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
}

Future<void> reviewOrder(BuildContext context, WidgetRef ref, Order o) async {
  var rating = 5; final text = TextEditingController();
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    title: Text('تقييم ${o.seller.nickname}'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(key: Key('star-$i'), onPressed: () => setS(() => rating = i), icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: Joy.sunText, size: 30))]),
      TextField(controller: text, maxLines: 3, decoration: const InputDecoration(hintText: 'كيف كانت التجربة؟ (اختياري)')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('review-send'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال'))],
  )));
  if (ok != true || !context.mounted) return;
  try { await ref.read(apiClientProvider).reviewOrder(o.id, rating, text.text.trim()); ref.invalidate(ordersProvider); ref.invalidate(orderProvider(o.id)); if (context.mounted) toast(context, 'شكراً لتقييمك'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
}

final orderProvider = FutureProvider.family<Order, String>((ref, id) => ref.watch(apiClientProvider).orderDetail(id));

/// صفحة الطلب: مراحله، رمز الاستلام، وإجراءات كل طرف
class OrderPage extends ConsumerWidget {
  final String id;
  const OrderPage(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(orderProvider(id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الطلب'), actions: [if (o.valueOrNull != null) IconButton(key: const Key('order-invoice'), tooltip: 'الفاتورة', icon: const Icon(Icons.receipt_outlined), onPressed: () => launchUrl(Uri.parse(ref.read(apiClientProvider).invoiceUrl(id)), mode: LaunchMode.externalApplication))]),
      body: o.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          JoyCard(child: Row(children: [
            Container(width: 56, height: 56, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: x.imageUrl != null ? Image.network(thumbUrl(x.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()) : const Icon(Icons.storefront_outlined, color: Joy.textMuted)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x.title}${x.variant != null ? ' (${x.variant})' : ''}${x.qty > 1 ? ' × ${x.qty}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(x.mineAsCourier ? 'البائع ${x.seller.nickname} → المشتري ${x.buyer.nickname} · ${timeAgo(x.createdAt)}' : '${x.mineAsSeller ? 'المشتري' : 'البائع'}: ${(x.mineAsSeller ? x.buyer : x.seller).nickname} · ${timeAgo(x.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              if (x.slot != null) Text('الموعد: ${weekdayLabels[x.slot!.weekday % 7]} ${x.slot!.day}/${x.slot!.month} ${clockOf(x.slot)}', style: const TextStyle(fontSize: 12.5)),
              if (x.note.isNotEmpty) Text('ملاحظة: ${x.note}', style: const TextStyle(fontSize: 12.5)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(money(x.total), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 16)), if (x.discount > 0) Text('خصم ${money(x.discount)}', style: const TextStyle(color: Joy.success, fontSize: 11.5)), if (x.mineAsSeller && (x.commission ?? 0) > 0) Text('عمولة ${money(x.commission!)}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]),
          ])),
          const SizedBox(height: 12),
          if (x.status == 'cancelled' || x.status == 'refunded') _banner(x.status == 'refunded' ? 'أُعيد المبلغ إلى المشتري بعد حسم النزاع.' : 'أُلغي الطلب${x.total > 0 ? ' واستُرد المبلغ إلى محفظة المشتري' : ''}.', Icons.cancel_outlined, Joy.textMuted)
          else if (x.status == 'disputed') _banner('نزاع مفتوح: ${x.disputeReason ?? ''}. الإدارة تراجعه والمبلغ مجمّد.', Icons.gavel_rounded, Joy.danger)
          else _Timeline(status: x.status),
          if (x.disputeNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('قرار الإدارة: ${x.disputeNote}', style: const TextStyle(fontSize: 12.5))),
          const SizedBox(height: 16),
          // مندوب التوصيل: يراه الطرفان، ويعيّنه البائع من زر أدناه
          if (x.courier != null) JoyCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
            ProfileAvatar(person: x.courier!, size: 40), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.mineAsCourier ? 'أنت مندوب التوصيل' : 'مندوب التوصيل: ${x.courier!.nickname}', key: const Key('order-courier-name'), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (x.courierNote.isNotEmpty) Text(x.courierNote, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ])),
            if (!x.mineAsCourier) IconButton(tooltip: 'مراسلة', icon: const Icon(Icons.chat_bubble_outline_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: x.courier!)))),
            if (x.mineAsSeller && x.open) IconButton(key: const Key('order-courier-clear'), tooltip: 'إلغاء التكليف', icon: const Icon(Icons.close_rounded), onPressed: () => _clearCourier(context, ref, x)),
          ])),
          if (x.courier != null) const SizedBox(height: 12),
          if (x.mineAsBuyer && x.code != null && x.open) JoyCard(child: Column(children: [
            const Text('رمز الاستلام', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text(x.code!, key: const Key('order-code'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34, letterSpacing: 8)),
            const Text('أعطه للبائع عند الاستلام، أو أكّد الاستلام بنفسك من الزر أدناه.', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // المشتري
            if (x.mineAsBuyer && x.open) FilledButton.icon(key: const Key('order-confirm'), onPressed: () => _confirm(context, ref, x), icon: const Icon(Icons.check_circle_outline_rounded, size: 18), label: const Text('تأكيد الاستلام')),
            if (x.mineAsBuyer && x.status == 'paid') OutlinedButton(key: const Key('order-cancel'), style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: () => _cancel(context, ref, x), child: const Text('إلغاء الطلب')),
            if (x.mineAsBuyer && x.open) OutlinedButton.icon(key: const Key('order-dispute'), style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: () => _dispute(context, ref, x), icon: const Icon(Icons.report_problem_outlined, size: 18), label: const Text('فتح نزاع')),
            if (x.mineAsBuyer && x.status == 'completed' && !x.reviewed) FilledButton.tonalIcon(key: const Key('order-review'), onPressed: () => reviewOrder(context, ref, x), icon: const Icon(Icons.star_outline_rounded, size: 18), label: const Text('قيّم البائع')),
            // البائع
            if (x.mineAsSeller && x.status == 'paid') FilledButton(key: const Key('stage-preparing'), onPressed: () => advanceOrder(context, ref, x, 'preparing'), child: const Text('بدء التحضير')),
            // البائع أو المندوب المعيَّن
            if ((x.mineAsSeller || x.mineAsCourier) && x.status == 'preparing') FilledButton(key: const Key('stage-on_the_way'), onPressed: () => advanceOrder(context, ref, x, 'on_the_way'), child: const Text('في الطريق')),
            if ((x.mineAsSeller || x.mineAsCourier) && (x.status == 'preparing' || x.status == 'on_the_way')) FilledButton(key: const Key('stage-delivered'), onPressed: () => advanceOrder(context, ref, x, 'delivered'), child: const Text('تم التسليم')),
            if (x.mineAsSeller && x.open) OutlinedButton.icon(key: const Key('seller-code'), onPressed: () => _sellerCode(context, ref, x), icon: const Icon(Icons.pin_outlined, size: 18), label: const Text('إدخال رمز المشتري')),
            if (x.mineAsSeller && x.courier == null && const {'paid', 'preparing', 'on_the_way'}.contains(x.status)) OutlinedButton.icon(key: const Key('order-courier'), onPressed: () => _assignCourier(context, ref, x), icon: const Icon(Icons.delivery_dining_outlined, size: 18), label: const Text('تعيين مندوب توصيل')),
            if (x.mineAsSeller && x.open) TextButton(style: TextButton.styleFrom(foregroundColor: Joy.danger), onPressed: () => _cancel(context, ref, x), child: const Text('إلغاء وردّ المبلغ')),
          ]),
          if (x.status == 'delivered' && x.mineAsBuyer) const Padding(padding: EdgeInsets.only(top: 10), child: Text('إن لم تؤكد خلال ٧٢ ساعة من التسليم يكتمل الطلب تلقائياً ويصل المبلغ للبائع.', style: TextStyle(color: Joy.textMuted, fontSize: 12))),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(orderProvider(id))),
      ),
    );
  }

  Widget _banner(String t, IconData i, Color c) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)), child: Row(children: [Icon(i, color: c), const SizedBox(width: 8), Expanded(child: Text(t, style: TextStyle(color: c, fontSize: 13)))]));

  Future<void> _confirm(BuildContext context, WidgetRef ref, Order x) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تأكيد الاستلام؟'), content: Text('سيصل المبلغ ${money(x.total)} إلى البائع ولا يمكن التراجع.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('confirm-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، استلمت'))]));
    if (ok != true || !context.mounted) return;
    try { await ref.read(apiClientProvider).confirmOrder(x.id); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); ref.invalidate(walletProvider); if (context.mounted) toast(context, 'اكتمل الطلب، شكراً لك'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
  /// البائع يعيّن مستخدماً في ناس لايف مندوباً للتوصيل باسم المستخدم
  Future<void> _assignCourier(BuildContext context, WidgetRef ref, Order x) async {
    final nick = TextEditingController(), note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تعيين مندوب توصيل'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('courier-nick'), controller: nick, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المستخدم في ناس لايف', hintText: 'مثال: rider')),
      const SizedBox(height: 8),
      TextField(key: const Key('courier-note'), controller: note, decoration: const InputDecoration(labelText: 'ملاحظة للمندوب (اختياري)', hintText: 'يتصل بالمشتري قبل الوصول')),
      const SizedBox(height: 6),
      const Text('سيرى المندوب الطلب في «الطلبات» ويستطيع تحديثه إلى «في الطريق» و«تم التسليم»، ولن يرى رمز المشتري.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('courier-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('تعيين'))]));
    if (ok != true || nick.text.trim().isEmpty || !context.mounted) return;
    try { await ref.read(apiClientProvider).setCourier(x.id, nickname: nick.text.trim(), note: note.text.trim()); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); if (context.mounted) toast(context, 'تم تعيين المندوب وإخطاره'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
  Future<void> _clearCourier(BuildContext context, WidgetRef ref, Order x) async {
    try { await ref.read(apiClientProvider).clearCourier(x.id); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
  Future<void> _sellerCode(BuildContext context, WidgetRef ref, Order x) async {
    final code = await askText(context, title: 'رمز المشتري', hint: '٤ أرقام يعطيها لك المشتري عند التسليم', confirm: 'تأكيد', maxLines: 1, keyboardType: TextInputType.number);
    if (code == null || code.isEmpty || !context.mounted) return;
    try { await ref.read(apiClientProvider).confirmOrder(x.id, code: code.trim()); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); ref.invalidate(walletProvider); if (context.mounted) toast(context, 'اكتمل الطلب ووصلك المبلغ'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
  Future<void> _cancel(BuildContext context, WidgetRef ref, Order x) async {
    try { await ref.read(apiClientProvider).cancelOrder(x.id); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); ref.invalidate(walletProvider); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
  Future<void> _dispute(BuildContext context, WidgetRef ref, Order x) async {
    final reason = await askText(context, title: 'فتح نزاع', hint: 'اشرح المشكلة بوضوح (لم يصل، مختلف عن الوصف…)', confirm: 'إرسال');
    if (reason == null || reason.length < 5 || !context.mounted) return;
    try { await ref.read(apiClientProvider).disputeOrder(x.id, reason); ref.invalidate(orderProvider(x.id)); ref.invalidate(ordersProvider); if (context.mounted) toast(context, 'فُتح النزاع وستراجعه الإدارة'); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
}

class _Timeline extends StatelessWidget {
  final String status;
  const _Timeline({required this.status});
  @override
  Widget build(BuildContext context) {
    final idx = orderStages.indexOf(status);
    return Row(children: [for (final (i, s) in orderStages.indexed) Expanded(child: Column(children: [
      Row(children: [
        Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= idx ? Joy.primary : Joy.line))),
        Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: i <= idx ? Joy.primary : Joy.surface2, border: Border.all(color: i <= idx ? Joy.primary : Joy.line)), child: i < idx ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null),
        Expanded(child: Container(height: 3, color: i == orderStages.length - 1 ? Colors.transparent : (i < idx ? Joy.primary : Joy.line))),
      ]),
      const SizedBox(height: 4),
      Text(orderStatusLabels[s] ?? s, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500, color: i <= idx ? Joy.text : Joy.textMuted)),
    ]))]);
  }
}

/// نسخ رمز الطلب للمشاركة في الدردشة (يستخدمه بطاقات الدردشة)
Future<void> copyOrderCode(BuildContext context, String code) async { await Clipboard.setData(ClipboardData(text: code)); if (context.mounted) toast(context, 'نُسخ الرمز'); }
