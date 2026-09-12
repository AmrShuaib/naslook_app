import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';
import '../wallet/wallet_page.dart';

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
      appBar: AppBar(title: const Text('السوق'), actions: [IconButton(icon: const Icon(Icons.receipt_long_outlined), tooltip: 'طلباتي', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage())))]),
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
    final title = TextEditingController(), desc = TextEditingController(), price = TextEditingController(), place = TextEditingController();
    String kind = 'product', category = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text('عرض جديد'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [for (final (k, l) in [('product', 'منتج'), ('service', 'خدمة')]) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(l, style: TextStyle(color: kind == k ? Joy.primaryOn : Joy.text)), selected: kind == k, onSelected: (_) => setS(() => kind = k), showCheckmark: false, selectedColor: Joy.primary))]),
          const SizedBox(height: 10),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان'), autofocus: true),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف')),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر (ر.س)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'الفئة'), items: [for (final e in marketCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setS(() => category = v ?? 'other')),
          const SizedBox(height: 10),
          TextField(controller: place, decoration: const InputDecoration(labelText: 'مكان الاستلام (اختياري)')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر'))],
      )),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    final gps = await DeviceLocation.current(precise: false);
    final pres = ref.read(myPresenceProvider).value;
    try {
      await ref.read(apiClientProvider).createListing({
        'title': title.text.trim(), 'description': desc.text.trim(), 'kind': kind, 'category': category,
        'price': ((double.tryParse(price.text.replaceAll('،', '.')) ?? 0) * 100).round(), 'placeName': place.text.trim(),
        'lat': gps?.latitude ?? pres?.lat, 'lng': gps?.longitude ?? pres?.lng,
      });
      ref.invalidate(marketProvider); ref.invalidate(myListingsProvider);
      if (mounted) toast(context, 'نُشر عرضك');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }
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
                ? Image.network(l.imageUrl!, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => _ph())
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
      appBar: AppBar(title: const Text('العرض')),
      body: l.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          if (x.imageUrl != null && x.imageUrl!.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(x.imageUrl!, height: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
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
            OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: () async { await ref.read(apiClientProvider).hideListing(x.id); ref.invalidate(marketProvider); ref.invalidate(myListingsProvider); if (context.mounted) Navigator.pop(context); }, child: const Text('إخفاء العرض'))
          else if (x.status == 'active')
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
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(ordersProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الطلبات')),
      body: o.when(
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا طلبات بعد')
            : ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => _OrderCard(list[i])),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(ordersProvider)),
      ),
    );
  }
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
