// السوق: صفحة نظيفة ومريحة. بحث، سبوت لايت (إعلانات يراها كل من يدخل السوق)، تصنيفات وتصنيفات فرعية، ترتيب وفلاتر
// مختصرة، وشبكة عروض بصور كبيرة. كل التفاصيل في صفحة العرض (listing_page.dart) والإنشاء في listing_form.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/chat_tools_api.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../api/client.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'listing_form.dart';
import 'listing_page.dart';
import 'orders_page.dart';
import 'seller_tools.dart';
import 'wanted_page.dart';

export 'listing_page.dart' show ListingPage, listingProvider;
export 'orders_page.dart' show OrdersPage, ordersProvider, myListingsProvider, MyListingRow, OwnerListingActions, listingStatusLabel, listingStatusColor, toggleListingVisibility, editListing, OrderPage, orderProvider;
export 'listing_form.dart' show showListingForm, ListingDraft;

/// موقع المستخدم للسوق (بلا دقة عالية، ومهلة قصيرة حتى لا تنتظر الصفحة)؛ يُستبدل في الاختبارات.
final marketPosProvider = FutureProvider<({double lat, double lng})?>((ref) async {
  final gps = await DeviceLocation.current(precise: false, timeout: const Duration(seconds: 4));
  if (gps != null) return (lat: gps.latitude, lng: gps.longitude);
  final p = ref.read(myPresenceProvider).valueOrNull;
  return p?.lat != null && p?.lng != null ? (lat: p!.lat!, lng: p.lng!) : null;
});

/// معايير البحث الحالية
class MarketQuery {
  final String q;
  final String? category, sub, kind, condition, sort;
  final int? min, max, radiusKm;
  final bool delivery;
  const MarketQuery({this.q = '', this.category, this.sub, this.kind, this.condition, this.sort, this.min, this.max, this.radiusKm, this.delivery = false});
  MarketQuery copyWith({String? q, Object? category = _keep, Object? sub = _keep, Object? kind = _keep, Object? condition = _keep, Object? sort = _keep, Object? min = _keep, Object? max = _keep, Object? radiusKm = _keep, bool? delivery}) => MarketQuery(
        q: q ?? this.q, category: category == _keep ? this.category : category as String?, sub: sub == _keep ? this.sub : sub as String?, kind: kind == _keep ? this.kind : kind as String?, condition: condition == _keep ? this.condition : condition as String?,
        sort: sort == _keep ? this.sort : sort as String?, min: min == _keep ? this.min : min as int?, max: max == _keep ? this.max : max as int?, radiusKm: radiusKm == _keep ? this.radiusKm : radiusKm as int?, delivery: delivery ?? this.delivery);
  int get activeFilters => (kind != null ? 1 : 0) + (condition != null ? 1 : 0) + (min != null || max != null ? 1 : 0) + (delivery ? 1 : 0) + (radiusKm != null ? 1 : 0);
  @override
  bool operator ==(Object other) => other is MarketQuery && other.q == q && other.category == category && other.sub == sub && other.kind == kind && other.condition == condition && other.sort == sort && other.min == min && other.max == max && other.radiusKm == radiusKm && other.delivery == delivery;
  @override
  int get hashCode => Object.hash(q, category, sub, kind, condition, sort, min, max, radiusKm, delivery);
}
const _keep = Object();

final marketQueryProvider = StateProvider<MarketQuery>((_) => const MarketQuery());
final marketHomeProvider = FutureProvider<MarketHome>((ref) async {
  final pos = await ref.watch(marketPosProvider.future);
  return ref.watch(apiClientProvider).marketHome(lat: pos?.lat, lng: pos?.lng);
});
final marketListProvider = FutureProvider.family<List<Listing>, MarketQuery>((ref, mq) async {
  final pos = await ref.watch(marketPosProvider.future);
  return ref.watch(apiClientProvider).market(q: mq.q, category: mq.category, sub: mq.sub, kind: mq.kind, min: mq.min, max: mq.max, delivery: mq.delivery, condition: mq.condition, sort: mq.sort, lat: pos?.lat, lng: pos?.lng, radiusKm: mq.radiusKm);
});
/// عروض اخترتها للمقارنة (حتى ٣)
final compareProvider = StateProvider<List<Listing>>((_) => const []);

void invalidateMarket(WidgetRef ref) { ref.invalidate(marketHomeProvider); ref.invalidate(marketListProvider); ref.invalidate(myListingsProvider); }

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  final search = TextEditingController();
  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final mq = ref.watch(marketQueryProvider);
    final home = ref.watch(marketHomeProvider);
    final list = ref.watch(marketListProvider(mq));
    final compare = ref.watch(compareProvider);
    final h = home.valueOrNull;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('السوق'),
        actions: [
          IconButton(key: const Key('market-wanted'), tooltip: 'طلبات المشترين', icon: Badge(isLabelVisible: (h?.wantedOpen ?? 0) > 0, label: Text('${h?.wantedOpen ?? 0}'), child: const Icon(Icons.campaign_outlined)), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WantedPage()))),
          IconButton(key: const Key('market-mine'), tooltip: 'عروضي وطلباتي', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage(initialTab: 1)))),
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            onSelected: (v) {
              if (v == 'seller') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerDashboardPage()));
              if (v == 'alerts') showMarketAlertsSheet(context, ref);
              if (v == 'compare') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePage()));
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'seller', child: ListTile(leading: Icon(Icons.insights_outlined), title: Text('لوحة البائع'))),
              const PopupMenuItem(value: 'alerts', child: ListTile(leading: Icon(Icons.notifications_active_outlined), title: Text('تنبيهات العروض الجديدة'))),
              PopupMenuItem(value: 'compare', child: ListTile(leading: const Icon(Icons.compare_arrows_rounded), title: Text('مقارنة${compare.isEmpty ? '' : ' (${compare.length})'}'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(key: const Key('market-sell'), onPressed: () => createListing(context, ref), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: const Text('اعرض للبيع')),
      body: RefreshIndicator(
        onRefresh: () async => invalidateMarket(ref),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: TextField(
              key: const Key('market-search'), controller: search, textInputAction: TextInputAction.search,
              onSubmitted: (v) => ref.read(marketQueryProvider.notifier).state = mq.copyWith(q: v.trim()),
              onChanged: (v) { if (v.trim().isEmpty && mq.q.isNotEmpty) ref.read(marketQueryProvider.notifier).state = mq.copyWith(q: ''); },
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج أو خدمة', prefixIcon: const Icon(Icons.search_rounded, color: Joy.textMuted), filled: true, fillColor: Joy.surface2, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { search.clear(); ref.read(marketQueryProvider.notifier).state = mq.copyWith(q: ''); }),
              ),
            ),
          )),
          if (h != null && h.spotlight.isNotEmpty && mq.q.isEmpty && mq.category == null) SliverToBoxAdapter(child: SpotlightStrip(items: h.spotlight)),
          SliverToBoxAdapter(child: _CategoryRow(mq: mq, counts: h?.categories ?? const {})),
          if (mq.category != null) SliverToBoxAdapter(child: _SubRow(mq: mq)),
          SliverToBoxAdapter(child: _ControlRow(mq: mq, count: list.valueOrNull?.length)),
          list.when(
            data: (items) => items.isEmpty
                ? SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.storefront_outlined, title: mq.q.isEmpty && mq.category == null ? 'لا عروض بعد' : 'لا نتائج', subtitle: mq.q.isEmpty && mq.category == null ? 'كن أول من يعرض منتجاً أو خدمة لمن حوله.' : 'جرّب تصنيفاً آخر أو وسّع النطاق.'))
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .72),
                      delegate: SliverChildBuilderDelegate((_, i) => ListingCard(items[i]), childCount: items.length),
                    ),
                  ),
            loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: ErrorState(e, onRetry: () => ref.invalidate(marketListProvider))),
          ),
        ]),
      ),
    );
  }
}

/// شريط سبوت لايت: بطاقات عريضة بصورة كاملة وعنوان وسعر، وبطاقة أخيرة لمن يريد إعلانه هنا
class SpotlightStrip extends ConsumerWidget {
  final List<SpotlightItem> items;
  const SpotlightStrip({super.key, required this.items});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 6), child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 18, color: Joy.sunText), const SizedBox(width: 6),
          const Text('سبوت لايت', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(width: 8),
          const Text('إعلانات مميزة', style: TextStyle(color: Joy.textMuted, fontSize: 12)), const Spacer(),
          TextButton(key: const Key('spotlight-info'), onPressed: () => showSpotlightSheet(context, ref), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact), child: const Text('اعرض إعلانك', style: TextStyle(fontSize: 12.5))),
        ])),
        SizedBox(height: 168, child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final s = items[i]; final l = s.listing;
            return GestureDetector(
              key: Key('spot-${l.id}'),
              onTap: () { ref.read(apiClientProvider).spotlightClick(s.id).ignore(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))); },
              child: Container(
                width: 270, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Joy.surface2),
                child: Stack(fit: StackFit.expand, children: [
                  if (l.imageUrl != null) Image.network(thumbUrl(l.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: .72)], stops: const [.35, 1]))),
                  Positioned(right: 12, left: 12, bottom: 10, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Row(children: [Text(l.price == 0 ? 'مجاناً' : money(l.price), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)), const Spacer(), Text(l.seller.nickname, style: const TextStyle(color: Colors.white70, fontSize: 11.5))]),
                  ])),
                  Positioned(top: 10, right: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.sun, borderRadius: BorderRadius.circular(999)), child: const Text('مميز', style: TextStyle(color: Joy.sunText, fontSize: 11, fontWeight: FontWeight.w800)))),
                ]),
              ),
            );
          },
        )),
      ]);
}

const _catIcons = {'coffee': Icons.coffee_outlined, 'food': Icons.restaurant_outlined, 'photo': Icons.photo_camera_outlined, 'gifts': Icons.card_giftcard_outlined, 'handmade': Icons.palette_outlined, 'delivery': Icons.local_shipping_outlined, 'services': Icons.handyman_outlined, 'other': Icons.category_outlined};
IconData marketCategoryIcon(String c) => _catIcons[c] ?? Icons.category_outlined;

class _CategoryRow extends ConsumerWidget {
  final MarketQuery mq;
  final Map<String, int> counts;
  const _CategoryRow({required this.mq, required this.counts});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(height: 46, child: ListView(key: const Key('cat-row'), scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), children: [
        for (final e in [const MapEntry<String?, String>(null, 'الكل'), ...marketCategories.entries])
          Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(
            key: Key('cat-${e.key ?? 'all'}'),
            avatar: e.key == null ? null : Icon(marketCategoryIcon(e.key!), size: 16, color: mq.category == e.key ? Joy.primaryOn : Joy.textMuted),
            label: Text(e.value, style: TextStyle(color: mq.category == e.key ? Joy.primaryOn : Joy.text, fontSize: 13)),
            selected: mq.category == e.key, showCheckmark: false, selectedColor: Joy.primary, backgroundColor: Joy.surface2, side: BorderSide.none, shape: const StadiumBorder(),
            onSelected: (_) => ref.read(marketQueryProvider.notifier).state = mq.copyWith(category: e.key, sub: null),
          )),
      ]));
}

class _SubRow extends ConsumerWidget {
  final MarketQuery mq;
  const _SubRow({required this.mq});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = marketSubcategories[mq.category] ?? const {};
    if (subs.isEmpty) return const SizedBox.shrink();
    return SizedBox(height: 38, child: ListView(key: const Key('sub-row'), scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 2, 16, 4), children: [
      for (final e in [const MapEntry<String?, String>(null, 'الكل'), ...subs.entries])
        Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
          key: Key('sub-${e.key ?? 'all'}'), label: Text(e.value, style: TextStyle(color: mq.sub == e.key ? Joy.primary : Joy.textMuted, fontSize: 12)), selected: mq.sub == e.key, showCheckmark: false,
          selectedColor: Joy.primarySoft, backgroundColor: Joy.bg, side: const BorderSide(color: Joy.line), shape: const StadiumBorder(), visualDensity: VisualDensity.compact,
          onSelected: (_) => ref.read(marketQueryProvider.notifier).state = mq.copyWith(sub: e.key),
        )),
    ]));
  }
}

/// صف الترتيب والفلاتر: زرّان خفيفان وعدّاد نتائج
class _ControlRow extends ConsumerWidget {
  final MarketQuery mq;
  final int? count;
  const _ControlRow({required this.mq, this.count});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(marketPosProvider).valueOrNull;
    final sortLabel = marketSorts[mq.sort ?? (pos != null ? 'near' : 'new')] ?? 'الأحدث';
    return Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 2), child: Row(children: [
      _Pill(key: const Key('market-sort'), icon: Icons.swap_vert_rounded, label: sortLabel, onTap: () => _pickSort(context, ref)),
      const SizedBox(width: 8),
      _Pill(key: const Key('market-filters'), icon: Icons.tune_rounded, label: mq.activeFilters == 0 ? 'فلاتر' : 'فلاتر · ${mq.activeFilters}', active: mq.activeFilters > 0, onTap: () => showFilterSheet(context, ref)),
      const Spacer(),
      if (count != null) Text(count == 0 ? '' : '$count عرض', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
    ]));
  }

  Future<void> _pickSort(BuildContext context, WidgetRef ref) async {
    final pos = ref.read(marketPosProvider).valueOrNull;
    final v = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final e in marketSorts.entries) if (e.key != 'near' || pos != null) ListTile(key: Key('sort-${e.key}'), title: Text(e.value), trailing: (mq.sort ?? (pos != null ? 'near' : 'new')) == e.key ? const Icon(Icons.check_rounded, color: Joy.primary) : null, onTap: () => Navigator.pop(ctx, e.key)),
    ])));
    if (v != null) ref.read(marketQueryProvider.notifier).state = mq.copyWith(sort: v);
  }
}

class _Pill extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  const _Pill({super.key, required this.icon, required this.label, this.active = false, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: active ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: active ? Joy.primary : Joy.textMuted), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? Joy.primary : Joy.text))]),
      ));
}

/// ورقة الفلاتر: النوع، السعر، التوصيل، الحالة، النطاق
Future<void> showFilterSheet(BuildContext context, WidgetRef ref) async {
  var mq = ref.read(marketQueryProvider);
  final min = TextEditingController(text: mq.min == null ? '' : '${mq.min! ~/ 100}'), max = TextEditingController(text: mq.max == null ? '' : '${mq.max! ~/ 100}');
  final pos = ref.read(marketPosProvider).valueOrNull;
  await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('فلاتر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [for (final (k, l) in [(null, 'الكل'), ('product', 'منتجات'), ('service', 'خدمات')]) ChoiceChip(key: Key('f-kind-${k ?? 'all'}'), label: Text(l), selected: mq.kind == k, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setS(() => mq = mq.copyWith(kind: k)))]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(key: const Key('f-min'), controller: min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر من (ر.س)', isDense: true))), const SizedBox(width: 10),
        Expanded(child: TextField(key: const Key('f-max'), controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إلى (ر.س)', isDense: true))),
      ]),
      const SizedBox(height: 8),
      SwitchListTile(key: const Key('f-delivery'), contentPadding: EdgeInsets.zero, value: mq.delivery, onChanged: (v) => setS(() => mq = mq.copyWith(delivery: v)), title: const Text('توصيل متاح فقط')),
      Wrap(spacing: 8, children: [for (final (k, l) in [(null, 'أي حالة'), ('new', 'جديد'), ('used', 'مستعمل')]) ChoiceChip(label: Text(l), selected: mq.condition == k, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setS(() => mq = mq.copyWith(condition: k)))]),
      if (pos != null) ...[
        const SizedBox(height: 12),
        const Text('النطاق', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Wrap(spacing: 8, children: [for (final (k, l) in [(null, 'الكل'), (5, 'حيّي · ٥ كم'), (30, 'مدينتي · ٣٠ كم'), (150, '١٥٠ كم')]) ChoiceChip(key: Key('f-radius-${k ?? 'all'}'), label: Text(l), selected: mq.radiusKm == k, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setS(() => mq = mq.copyWith(radiusKm: k)))]),
      ],
      const SizedBox(height: 16),
      Row(children: [
        TextButton(onPressed: () { ref.read(marketQueryProvider.notifier).state = MarketQuery(q: mq.q, category: mq.category, sub: mq.sub, sort: mq.sort); Navigator.pop(ctx); }, child: const Text('مسح الكل')),
        const Spacer(),
        FilledButton(key: const Key('f-apply'), onPressed: () {
          final mn = parseSar(min.text), mx = parseSar(max.text);
          ref.read(marketQueryProvider.notifier).state = mq.copyWith(min: mn > 0 ? mn : null, max: mx > 0 ? mx : null);
          Navigator.pop(ctx);
        }, child: const Text('تطبيق')),
      ]),
    ]),
  )));
}

/// بطاقة عرض في الشبكة: صورة كبيرة، عنوان، سعر، تقييم، بائع، ومسافة
class ListingCard extends StatelessWidget {
  final Listing l;
  const ListingCard(this.l, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Stack(fit: StackFit.expand, children: [
            l.imageUrl != null && l.imageUrl!.isNotEmpty ? Image.network(thumbUrl(l.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph()) : _ph(),
            if (l.spotlight) Positioned(top: 8, right: 8, child: _tag('مميز', Joy.sun, Joy.sunText)),
            if (l.outOfStock) Positioned(top: 8, left: 8, child: _tag('نفد', Joy.surface2, Joy.textMuted)),
            if (l.distanceKm != null) Positioned(bottom: 8, left: 8, child: _tag(l.distanceKm! < 1 ? 'قريب جداً' : '${l.distanceKm!.toStringAsFixed(l.distanceKm! < 10 ? 1 : 0)} كم', Colors.white.withValues(alpha: .92), Joy.text)),
          ]))),
          const SizedBox(height: 8),
          Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 3),
          Row(children: [
            Text(l.price == 0 ? 'مجاناً' : money(l.price), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.text, fontSize: 14)),
            const Spacer(),
            if (l.ratingAvg != null || l.sellerRating != null) ...[const Icon(Icons.star_rounded, size: 14, color: Joy.sunText), Text((l.ratingAvg ?? l.sellerRating)!.toStringAsFixed(1), style: const TextStyle(fontSize: 11.5, color: Joy.textMuted))],
          ]),
          Text('${l.seller.nickname}${l.placeName != null && l.placeName!.isNotEmpty ? ' · ${l.placeName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
        ]),
      );
  Widget _ph() => Container(color: Joy.surface2, alignment: Alignment.center, child: Icon(l.kind == 'service' ? Icons.handshake_outlined : Icons.shopping_bag_outlined, size: 34, color: Joy.control));
  static Widget _tag(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)));
}

/// إنشاء عرض: النموذج ثم رفع الصور ثم النشر
Future<void> createListing(BuildContext context, WidgetRef ref) async {
  final d = await showListingForm(context);
  if (d == null || !context.mounted) return;
  try {
    final api = ref.read(apiClientProvider);
    final pos = ref.read(marketPosProvider).valueOrNull;
    final pres = ref.read(myPresenceProvider).valueOrNull;
    final urls = [...d.existingImages];
    for (final img in d.newImages) {
      urls.add((await api.uploadMedia(img.bytes, contentType: img.mime, fileName: img.name)).url);
    }
    final body = d.toBody()..addAll({'images': urls, if (urls.isNotEmpty) 'imageUrl': urls.first, 'lat': pos?.lat ?? pres?.lat, 'lng': pos?.lng ?? pres?.lng});
    final l = await api.createListing(body);
    invalidateMarket(ref);
    if (context.mounted) toast(context, l.status == 'draft' ? 'حُفظ كمسودة' : l.status == 'scheduled' ? 'سيُنشر في موعده' : l.status == 'pending' ? 'أُرسل للمراجعة وسيظهر بعد الموافقة' : 'نُشر عرضك');
  } catch (e) {
    if (context.mounted) toast(context, marketErrText(e), error: true);
  }
}

String marketErrText(Object e) {
  final code = e is ApiException ? (e.body?['error']?.toString() ?? '') : '';
  final s = code.isNotEmpty ? code : e.toString();
  if (s.contains('insufficient-funds')) return 'الرصيد غير كافٍ في المحفظة';
  if (s.contains('contact-in-text')) return 'لا تكتب أرقام جوال أو روابط في العرض؛ التواصل عبر المراسلة داخل ناس لايف';
  if (s.contains('duplicate-listing')) return 'لديك عرض مطابق بالعنوان والسعر نفسيهما';
  if (s.contains('new-account-limit')) return 'الحساب الجديد يمكنه نشر ٣ عروض في أول يوم';
  if (s.contains('banned-words')) return 'يحتوي كلمات غير مسموح بها';
  if (s.contains('out-of-stock')) return 'الكمية المطلوبة غير متوفرة';
  if (s.contains('slot-taken')) return 'هذا الموعد محجوز، اختر موعداً آخر';
  if (s.contains('slot-unavailable') || s.contains('slot-required')) return 'اختر موعداً داخل أوقات الخدمة';
  if (s.contains('variant-required')) return 'اختر الخيار المناسب أولاً';
  if (s.contains('bad-coupon')) return 'الكوبون غير صالح';
  if (s.contains('coupon-min')) return 'الكوبون يتطلب حداً أدنى للطلب';
  if (s.contains('bump-too-soon')) return 'يمكنك رفع العرض مرة كل ٢٤ ساعة';
  if (s.contains('spotlight-full')) return 'مساحة سبوت لايت ممتلئة حالياً، جرّب لاحقاً';
  if (s.contains('bad-code')) return 'الرمز غير صحيح';
  if (s.contains('pending-review')) return 'العرض بانتظار مراجعة الإدارة';
  if (s.contains('blocked')) return 'أخفته الإدارة؛ تواصل مع الدعم';
  return e is ApiException ? e.message : s;
}
