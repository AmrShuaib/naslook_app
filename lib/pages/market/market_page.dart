import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/chat_tools_api.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../core/media/pick_image.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../../api/safety_api.dart';
import '../chat/chat_thread_page.dart';
import '../wallet/wallet_page.dart';
import '../../api/client.dart';

final marketProvider = FutureProvider.family<List<Listing>, (String, String?)>((ref, a) => ref.watch(apiClientProvider).market(q: a.$1, category: a.$2));
final myListingsProvider = FutureProvider<List<Listing>>((ref) => ref.watch(apiClientProvider).myListings());
final ordersProvider = FutureProvider<List<Order>>((ref) => ref.watch(apiClientProvider).orders());

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  String q = '';
  String? cat;
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(marketProvider((q, cat)));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('السوق'), actions: [IconButton(icon: const Icon(Icons.receipt_long_outlined), tooltip: 'عروضي وطلباتي', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage(initialTab: 1))))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: const Text('اعرض للبيع')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(hintText: 'ابحث عن خدمة أو منتج', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted)))),
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final e in [const MapEntry<String?, String>(null, 'الكل'), ...marketCategories.entries])
            Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(e.value, style: TextStyle(color: cat == e.key ? Joy.primaryOn : Joy.text)), selected: cat == e.key, onSelected: (_) => setState(() => cat = e.key), showCheckmark: false, selectedColor: Joy.primary)),
        ])),
        Expanded(
          child: list.when(
            data: (items) => items.isEmpty
                ? const EmptyState(icon: Icons.storefront_outlined, title: 'لا عروض بعد', subtitle: 'كن أول من يعرض منتجاً أو خدمة لمن حوله.')
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(marketProvider),
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .78),
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListingCard(items[i]),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(marketProvider)),
          ),
        ),
      ]),
    );
  }

  Future<void> _create() async {
    final d = await showListingForm(context);
    if (d == null || !mounted) return;
    final gps = await DeviceLocation.current(precise: false);
    final pres = ref.read(myPresenceProvider).value;
    try {
      final api = ref.read(apiClientProvider);
      final imageUrl = d.image == null ? null : (await api.uploadMedia(d.image!.bytes, contentType: d.image!.mime, fileName: d.image!.name)).url;
      await api.createListing({
        'title': d.title, 'description': d.description, 'kind': d.kind, 'category': d.category, 'price': d.price, 'placeName': d.placeName,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'lat': gps?.latitude ?? pres?.lat, 'lng': gps?.longitude ?? pres?.lng,
      });
      ref.invalidate(marketProvider); ref.invalidate(myListingsProvider);
      if (mounted) toast(context, 'نُشر عرضك');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }
}

/// مسودة عرض من نموذج الإنشاء أو التعديل.
typedef ListingDraft = ({String title, String description, int price, String kind, String category, String placeName, PickedImage? image, bool removeImage});

String _priceText(int halalas) => halalas % 100 == 0 ? '${halalas ~/ 100}' : (halalas / 100).toStringAsFixed(2);

/// نموذج العرض (إنشاء أو تعديل) مع اختيار صورة من الجهاز. يعيد null عند الإلغاء.
Future<ListingDraft?> showListingForm(BuildContext context, {Listing? initial}) async {
  final title = TextEditingController(text: initial?.title ?? ''), desc = TextEditingController(text: initial?.description ?? '');
  final price = TextEditingController(text: initial == null ? '' : _priceText(initial.price)), place = TextEditingController(text: initial?.placeName ?? '');
  String kind = initial?.kind ?? 'product', category = marketCategories.containsKey(initial?.category) ? initial!.category : 'other';
  PickedImage? img;
  var removeImage = false;
  final existingUrl = initial?.imageUrl;
  final hasExisting = existingUrl != null && existingUrl.isNotEmpty;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final pic = img; // نسخة محلية حتى يتعرف المحلل على عدم فراغها داخل الشجرة
      final showsExisting = hasExisting && !removeImage && pic == null;
      return AlertDialog(
        title: Text(initial == null ? 'عرض جديد' : 'تعديل العرض'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 72, height: 72, clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
              child: pic != null
                  ? Image.memory(pic.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Joy.textMuted))
                  : showsExisting
                      ? Image.network(thumbUrl(existingUrl), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Joy.textMuted))
                      : const Icon(Icons.add_photo_alternate_outlined, color: Joy.textMuted, size: 28),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton.icon(
                onPressed: () async { final p = await pickImage(); if (p != null) setS(() { img = p; removeImage = false; }); },
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(pic == null && !showsExisting ? 'إضافة صورة' : 'تغيير الصورة'),
              ),
              if (pic != null || showsExisting)
                TextButton.icon(onPressed: () => setS(() { img = null; removeImage = true; }), style: TextButton.styleFrom(foregroundColor: Joy.danger), icon: const Icon(Icons.close_rounded, size: 18), label: const Text('بلا صورة')),
            ])),
          ]),
          const SizedBox(height: 10),
          Row(children: [for (final (k, l) in [('product', 'منتج'), ('service', 'خدمة')]) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(l, style: TextStyle(color: kind == k ? Joy.primaryOn : Joy.text)), selected: kind == k, onSelected: (_) => setS(() => kind = k), showCheckmark: false, selectedColor: Joy.primary))]),
          const SizedBox(height: 10),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان'), autofocus: initial == null),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف')),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر (ر.س)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'الفئة'), items: [for (final e in marketCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setS(() => category = v ?? 'other')),
          const SizedBox(height: 10),
          TextField(controller: place, decoration: const InputDecoration(labelText: 'مكان الاستلام (اختياري)')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(initial == null ? 'نشر' : 'حفظ'))],
      );
    }),
  );
  if (ok != true || title.text.trim().isEmpty) return null;
  return (
    title: title.text.trim(), description: desc.text.trim(), price: ((double.tryParse(price.text.replaceAll('،', '.')) ?? 0) * 100).round(),
    kind: kind, category: category, placeName: place.text.trim(), image: img, removeImage: removeImage,
  );
}

class ListingCard extends StatelessWidget {
  final Listing l;
  const ListingCard(this.l, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: l.imageUrl != null && l.imageUrl!.isNotEmpty
                ? Image.network(thumbUrl(l.imageUrl!), fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => _ph())
                : _ph(),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 4),
            Row(children: [ProfileAvatar(person: l.seller, size: 20), const SizedBox(width: 6), Expanded(child: Text(l.seller.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)))]),
            const SizedBox(height: 6),
            Text(l.price == 0 ? 'مجاناً' : money(l.price), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary, fontSize: 14.5)),
          ])),
        ]),
      );
  Widget _ph() => Container(color: l.kind == 'service' ? Joy.primarySoft : Joy.sunSoft, alignment: Alignment.center, child: Icon(l.kind == 'service' ? Icons.handshake_outlined : Icons.shopping_bag_outlined, size: 36, color: l.kind == 'service' ? Joy.primary : Joy.sunText));
}

final listingProvider = FutureProvider.family<Listing, String>((ref, id) => ref.watch(apiClientProvider).listing(id));

class ListingPage extends ConsumerStatefulWidget {
  final String id;
  const ListingPage(this.id, {super.key});
  @override
  ConsumerState<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends ConsumerState<ListingPage> {
  int qty = 1;
  @override
  Widget build(BuildContext context) {
    final l = ref.watch(listingProvider(widget.id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('العرض'), actions: [
        WishButton(kind: 'market', refId: widget.id),
        if (l.value?.mine == false)
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            onSelected: (_) => _reportListing(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ عن العرض')))],
          ),
      ]),
      body: l.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          if (x.imageUrl != null && x.imageUrl!.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(thumbUrl(x.imageUrl!), height: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: Text(x.title, style: Theme.of(context).textTheme.headlineSmall)), Text(x.price == 0 ? 'مجاناً' : money(x.price), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary, fontSize: 20))]),
          Text('${x.kind == 'service' ? 'خدمة' : 'منتج'} · ${marketCategories[x.category] ?? x.category}${x.placeName != null && x.placeName!.isNotEmpty ? ' · ${x.placeName}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          JoyCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
            ProfileAvatar(person: x.seller, size: 44),
            const SizedBox(width: 10),
            Expanded(child: Text(x.seller.nickname, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (!x.mine) OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: x.seller))), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('مراسلة')),
          ])),
          if (x.description.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(x.description, style: const TextStyle(height: 1.65))),
          const SizedBox(height: 8),
          if (x.mine)
            OwnerListingActions(x)
          else if (x.status != 'active')
            const Text('هذا العرض غير متاح حالياً.', style: TextStyle(color: Joy.textMuted))
          else
            Row(children: [
              IconButton(onPressed: qty > 1 ? () => setState(() => qty--) : null, icon: const Icon(Icons.remove_rounded)),
              Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(onPressed: qty < 20 ? () => setState(() => qty++) : null, icon: const Icon(Icons.add_rounded)),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: () => _order(x), icon: const Icon(Icons.account_balance_wallet_outlined), label: Text('اطلب بالمحفظة · ${money(x.price * qty)}'))),
            ]),
          const SizedBox(height: 8),
          const Text('يُحجز المبلغ من محفظتك ولا يصل البائع إلا بعد تأكيد التسليم. يمكنك الإلغاء قبل ذلك.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(listingProvider(widget.id))),
      ),
    );
  }

  Future<void> _reportListing() async {
    final reason = await askText(context, title: 'إبلاغ عن العرض', hint: 'ما المشكلة؟ (احتيال، سلعة مخالفة، مضلل…)', confirm: 'إرسال البلاغ');
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      final r = await ref.read(apiClientProvider).reportContent(type: 'listing', id: widget.id, reason: reason);
      if (mounted) toast(context, r.hidden ? 'وصل بلاغك وأُخفي العرض للمراجعة' : 'وصل بلاغك وسنراجعه');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _order(Listing x) async {
    final note = await askText(context, title: 'ملاحظة للبائع', hint: 'مثال: الاستلام بعد المغرب', confirm: 'تأكيد الطلب', maxLines: 2);
    if (note == null) return;
    try {
      await ref.read(apiClientProvider).order(x.id, qty, note: note);
      ref.invalidate(ordersProvider); ref.invalidate(walletProvider);
      if (mounted) { toast(context, 'تم الطلب'); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage())); }
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('insufficient-funds') ? 'الرصيد غير كافٍ في المحفظة' : e.toString(), error: true);
    }
  }
}

class OrdersPage extends ConsumerWidget {
  /// 0 = عروضي، 1 = الطلبات
  final int initialTab;
  const OrdersPage({super.key, this.initialTab = 1});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        initialIndex: initialTab.clamp(0, 1),
        child: Scaffold(
          backgroundColor: Joy.bg,
          appBar: AppBar(title: const Text('عروضي وطلباتي'), bottom: const TabBar(tabs: [Tab(text: 'عروضي'), Tab(text: 'الطلبات')])),
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
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(ordersProvider),
              child: ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => _OrderCard(list[i])),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(ordersProvider)),
    );
  }
}

/// عروضي كلها: الظاهرة والمخفية وما أخفته الإدارة، مع إظهار/إخفاء سريع.
class _MyListings extends ConsumerWidget {
  const _MyListings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(myListingsProvider);
    return l.when(
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.storefront_outlined, title: 'لم تعرض شيئاً للبيع بعد', subtitle: 'من صفحة السوق اضغط «اعرض للبيع» وأضف صورة ووصفاً وسعراً.')
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(myListingsProvider),
              child: ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => MyListingRow(list[i])),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myListingsProvider)),
    );
  }
}

String listingStatusLabel(String status) => switch (status) { 'active' => 'ظاهر في السوق', 'hidden' => 'مخفي', 'blocked' => 'أخفته الإدارة', _ => status };
Color listingStatusColor(String status) => switch (status) { 'active' => Joy.success, 'blocked' => Joy.danger, _ => Joy.textMuted };

/// يبدّل ظهور عرضي بين ظاهر ومخفي (ما لم تكن الإدارة قد أخفته).
Future<void> toggleListingVisibility(BuildContext context, WidgetRef ref, Listing x) async {
  try {
    final next = x.status == 'active' ? 'hidden' : 'active';
    await ref.read(apiClientProvider).updateListing(x.id, {'status': next});
    ref.invalidate(marketProvider); ref.invalidate(myListingsProvider); ref.invalidate(listingProvider(x.id));
    if (context.mounted) toast(context, next == 'active' ? 'صار العرض ظاهراً في السوق' : 'أُخفي العرض ولا يراه غيرك');
  } catch (e) {
    if (context.mounted) toast(context, e.toString().contains('blocked') ? 'أخفته الإدارة؛ تواصل مع الدعم' : e.toString(), error: true);
  }
}

/// يفتح نموذج التعديل ويرفع الصورة الجديدة إن اختيرت ثم يحفظ.
Future<void> editListing(BuildContext context, WidgetRef ref, Listing x) async {
  final d = await showListingForm(context, initial: x);
  if (d == null || !context.mounted) return;
  try {
    final api = ref.read(apiClientProvider);
    final imageUrl = d.image == null ? null : (await api.uploadMedia(d.image!.bytes, contentType: d.image!.mime, fileName: d.image!.name)).url;
    await api.updateListing(x.id, {
      'title': d.title, 'description': d.description, 'price': d.price, 'kind': d.kind, 'category': d.category, 'placeName': d.placeName,
      if (imageUrl != null) 'imageUrl': imageUrl else if (d.removeImage) 'imageUrl': null,
    });
    ref.invalidate(marketProvider); ref.invalidate(myListingsProvider); ref.invalidate(listingProvider(x.id));
    if (context.mounted) toast(context, 'حُفظت التعديلات');
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), error: true);
  }
}

class MyListingRow extends ConsumerWidget {
  final Listing l;
  const MyListingRow(this.l, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Row(children: [
          Container(
            width: 48, height: 48, clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
            child: l.imageUrl != null && l.imageUrl!.isNotEmpty ? Image.network(thumbUrl(l.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Joy.textMuted)) : const Icon(Icons.storefront_outlined, color: Joy.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('${l.price == 0 ? 'مجاناً' : money(l.price)} · ${listingStatusLabel(l.status)}', style: TextStyle(color: listingStatusColor(l.status), fontSize: 12.5, fontWeight: FontWeight.w600)),
          ])),
          if (l.status == 'blocked')
            const Icon(Icons.block_rounded, color: Joy.danger)
          else
            IconButton(
              tooltip: l.status == 'active' ? 'إخفاء' : 'إظهار',
              onPressed: () => toggleListingVisibility(context, ref, l),
              icon: Icon(l.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: l.status == 'active' ? Joy.textMuted : Joy.primary),
            ),
        ]),
      );
}

/// إجراءات صاحب العرض داخل صفحته: حالة العرض، تعديل، إخفاء/إظهار.
class OwnerListingActions extends ConsumerWidget {
  final Listing x;
  const OwnerListingActions(this.x, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (x.status != 'active')
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: x.status == 'blocked' ? Joy.accentSoft : Joy.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(x.status == 'blocked' ? Icons.block_rounded : Icons.visibility_off_outlined, color: x.status == 'blocked' ? Joy.accent : Joy.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(x.status == 'blocked' ? 'أخفته الإدارة من السوق؛ تواصل مع الدعم إن كان ذلك خطأً.' : 'العرض مخفي ولا يراه أحد غيرك.', style: TextStyle(color: x.status == 'blocked' ? Joy.accent : Joy.textMuted, fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => editListing(context, ref, x), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل')),
          if (x.status != 'blocked')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: x.status == 'active' ? Joy.danger : Joy.primary),
              onPressed: () => toggleListingVisibility(context, ref, x),
              icon: Icon(x.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              label: Text(x.status == 'active' ? 'إخفاء العرض' : 'إظهار العرض'),
            ),
        ]),
      ]);
}

class _OrderCard extends ConsumerWidget {
  final Order o;
  const _OrderCard(this.o);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = o.mineAsSeller ? o.buyer : o.seller;
    final status = switch (o.status) { 'paid' => 'مدفوع · بانتظار التسليم', 'delivered' => 'تم التسليم', 'cancelled' => 'ملغى', _ => o.status };
    return JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ProfileAvatar(person: other, size: 40),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${o.title} × ${o.qty}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          Text('${o.mineAsSeller ? 'المشتري' : 'البائع'}: ${other.nickname} · ${timeAgo(o.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ])),
        Text(money(o.total), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary)),
      ]),
      if (o.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(o.note, style: const TextStyle(fontSize: 13))),
      const SizedBox(height: 10),
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: o.status == 'delivered' ? Joy.primarySoft : o.status == 'cancelled' ? Joy.surface2 : Joy.sunSoft, borderRadius: BorderRadius.circular(999)), child: Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: o.status == 'delivered' ? Joy.primary : o.status == 'cancelled' ? Joy.textMuted : Joy.sunText))),
        const Spacer(),
        if (o.status == 'paid' && o.mineAsSeller) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 40)), onPressed: () => _act(context, ref, deliver: true), child: const Text('تم التسليم')),
        if (o.status == 'paid') TextButton(onPressed: () => _act(context, ref, deliver: false), child: const Text('إلغاء', style: TextStyle(color: Joy.danger))),
      ]),
    ]));
  }
  Future<void> _act(BuildContext context, WidgetRef ref, {required bool deliver}) async {
    try {
      final api = ref.read(apiClientProvider);
      if (deliver) { await api.deliverOrder(o.id); } else { await api.cancelOrder(o.id); }
      ref.invalidate(ordersProvider); ref.invalidate(walletProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }
}
