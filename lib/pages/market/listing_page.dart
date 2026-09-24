// صفحة العرض: معرض صور، سعر، بائع بتقييمه وشاراته ومتابعته، وصف، خيارات، موعد للخدمة، كوبون، طلب برمز استلام،
// أسئلة وأجوبة عامة، تقييمات، مشاركة ومقارنة وإبلاغ؛ ولصاحب العرض: تعديل وإخفاء ورفع وسبوت لايت.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/share/share_links.dart';
import '../../state/app_state.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../chat/chat_thread_page.dart';
import '../wallet/wallet_page.dart';
import 'market_page.dart';
import 'seller_tools.dart';

final listingProvider = FutureProvider.family<Listing, String>((ref, id) => ref.watch(apiClientProvider).listing(id));
final listingQuestionsProvider = FutureProvider.family<List<MarketQuestion>, String>((ref, id) => ref.watch(apiClientProvider).questions(id));
final listingReviewsProvider = FutureProvider.family<List<MarketReview>, String>((ref, id) => ref.watch(apiClientProvider).listingReviews(id));

class ListingPage extends ConsumerStatefulWidget {
  final String id;
  const ListingPage(this.id, {super.key});
  @override
  ConsumerState<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends ConsumerState<ListingPage> {
  int qty = 1, page = 0;
  String? variant;
  DateTime? slot;
  final coupon = TextEditingController();
  Map<String, dynamic>? couponCheck;
  final question = TextEditingController();
  final pageCtl = PageController();

  @override
  void initState() { super.initState(); Future.microtask(() => ref.read(apiClientProvider).viewListing(widget.id).ignore()); }
  @override
  void dispose() { coupon.dispose(); question.dispose(); pageCtl.dispose(); super.dispose(); }

  int _unit(Listing x) => variant == null ? x.price : (x.variants.where((v) => v.name == variant).firstOrNull?.price ?? x.price);
  int _subtotal(Listing x) => _unit(x) * qty;

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(listingProvider(widget.id));
    final compare = ref.watch(compareProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('العرض'), actions: [
        if (l.valueOrNull != null) IconButton(key: const Key('share-listing'), tooltip: 'مشاركة', icon: const Icon(Icons.ios_share_rounded), onPressed: () => shareLink(context, title: l.value!.title, url: '${ApiClient.mediaBase}/l/${widget.id}', subtitle: '${money(l.value!.price)} · سوق ناس لايف', code: listingCode(widget.id))),
        IconButton(key: const Key('copy-listing-code'), tooltip: 'انسخ رمز المحادثة', icon: const Icon(Icons.bolt_rounded), onPressed: () async { await Clipboard.setData(ClipboardData(text: listingCode(widget.id))); if (context.mounted) toast(context, 'نُسخ الرمز ${listingCode(widget.id)}، الصقه في أي محادثة'); }),
        WishButton(kind: 'market', refId: widget.id),
        if (l.valueOrNull?.mine == false)
          PopupMenuButton<String>(key: const Key('listing-menu'), tooltip: 'المزيد', onSelected: (v) { if (v == 'report') { _reportListing(l.value!); } else if (v == 'block') { _blockSeller(l.value!); } else if (v == 'compare') { _toggleCompare(l.value!); } },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'compare', child: ListTile(leading: const Icon(Icons.compare_arrows_rounded), title: Text(compare.any((c) => c.id == widget.id) ? 'إزالة من المقارنة' : 'أضف للمقارنة'))),
              const PopupMenuItem(key: Key('listing-report'), value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ عن العرض'))),
              if (ref.read(appStateProvider).user != null)
                PopupMenuItem(key: const Key('listing-block'), value: 'block', child: ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${l.value!.seller.nickname}', style: const TextStyle(color: Joy.danger)))),
            ]),
      ]),
      body: l.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(0, 0, 0, 32), children: [
          _Gallery(images: x.images, kind: x.kind, ctl: pageCtl, page: page, onPage: (i) => setState(() => page = i)),
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, height: 1.3))),
              const SizedBox(width: 12),
              Text(x.price == 0 ? 'مجاناً' : money(x.variants.isEmpty ? x.price : _unit(x)), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 20)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(x.kind == 'service' ? 'خدمة' : 'منتج', Icons.sell_outlined), if (x.subcategoryLabel.isNotEmpty) _chip(x.subcategoryLabel, marketCategoryIcon(x.category)) else _chip(marketCategories[x.category] ?? x.category, marketCategoryIcon(x.category)),
              if (x.condition != null) _chip(marketConditions[x.condition] ?? x.condition!, Icons.new_releases_outlined), if (x.delivery) _chip('توصيل متاح', Icons.local_shipping_outlined),
              if (x.placeName != null && x.placeName!.isNotEmpty) _chip('${x.placeName}${x.distanceKm != null ? ' · ${x.distanceKm!.toStringAsFixed(1)} كم' : ''}', Icons.place_outlined),
              if (x.spotlight) _chip('سبوت لايت', Icons.auto_awesome_rounded, bg: Joy.sunSoft, fg: Joy.sunText),
            ]),
            const SizedBox(height: 14),
            _SellerCard(l: x),
            if (x.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(x.description, style: const TextStyle(height: 1.7, fontSize: 14.5))),
            const SizedBox(height: 14),
            if (x.mine) OwnerListingActions(x)
            else if (x.status != 'active') const Text('هذا العرض غير متاح حالياً.', style: TextStyle(color: Joy.textMuted))
            else _buyBox(x),
            _Questions(listing: x, controller: question),
            _Reviews(listingId: x.id, ratingAvg: x.ratingAvg, count: x.ratingCount),
          ])),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(listingProvider(widget.id))),
      ),
    );
  }

  Widget _chip(String t, IconData i, {Color bg = Joy.surface2, Color fg = Joy.textMuted}) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: fg), const SizedBox(width: 4), Text(t, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600))]));

  Widget _buyBox(Listing x) {
    final total = _subtotal(x); final disc = couponCheck?['valid'] == true ? (couponCheck!['discount'] as num).toInt() : 0;
    final v = x.variants.where((v) => v.name == variant).firstOrNull;
    final out = x.variants.isEmpty ? x.stock == 0 : (v != null && v.stock == 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (x.variants.isNotEmpty) ...[
        const Text('اختر', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final v in x.variants) ChoiceChip(key: Key('variant-${v.name}'), label: Text('${v.name} · ${money(v.price)}${v.stock == 0 ? ' (نفد)' : ''}'), selected: variant == v.name, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: v.stock == 0 ? null : (_) => setState(() { variant = v.name; couponCheck = null; }))]),
        const SizedBox(height: 12),
      ],
      if (x.isService && x.availability != null) ...[
        const Text('الموعد', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6),
        SlotPicker(availability: x.availability!, value: slot, onChanged: (d) => setState(() => slot = d)),
        const SizedBox(height: 12),
      ],
      if (x.stock != null && x.variants.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(x.stock == 0 ? 'نفدت الكمية' : 'المتوفر: ${x.stock}', style: TextStyle(color: x.stock == 0 ? Joy.danger : Joy.textMuted, fontSize: 12.5))),
      Row(children: [
        if (!x.isService) ...[
          IconButton(onPressed: qty > 1 ? () => setState(() { qty--; couponCheck = null; }) : null, icon: const Icon(Icons.remove_rounded)),
          Text('$qty', key: const Key('qty'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(onPressed: qty < 20 ? () => setState(() { qty++; couponCheck = null; }) : null, icon: const Icon(Icons.add_rounded)),
          const SizedBox(width: 8),
        ],
        Expanded(child: TextField(key: const Key('coupon'), controller: coupon, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: 'كوبون خصم', isDense: true, prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 18),
          suffixIcon: TextButton(onPressed: () => _checkCoupon(x), child: const Text('تحقق'))), onChanged: (_) => setState(() => couponCheck = null))),
      ]),
      if (couponCheck != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(couponCheck!['valid'] == true ? 'خصم ${money(disc)}' : marketErrText(couponCheck!['error']?.toString() ?? 'bad-coupon'), style: TextStyle(color: couponCheck!['valid'] == true ? Joy.success : Joy.danger, fontSize: 12.5))),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('order-btn'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: out || (x.variants.isNotEmpty && variant == null) || (x.isService && x.availability != null && slot == null) ? null : () => _order(x),
        icon: const Icon(Icons.account_balance_wallet_outlined), label: Text(out ? 'غير متوفر' : x.variants.isNotEmpty && variant == null ? 'اختر الخيار أولاً' : x.isService && x.availability != null && slot == null ? 'اختر الموعد أولاً' : 'اطلب بالمحفظة · ${money(total - disc)}'),
      ),
      const SizedBox(height: 8),
      const Text('يُحجز المبلغ من محفظتك ولا يصل البائع إلا بعد تأكيدك الاستلام أو إدخاله رمز الاستلام الذي ستراه في طلبك.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
    ]);
  }

  Future<void> _checkCoupon(Listing x) async {
    final code = coupon.text.trim().toUpperCase(); if (code.isEmpty) return;
    try { final r = await ref.read(apiClientProvider).checkCoupon(seller: x.seller.id, code: code, total: _subtotal(x)); if (mounted) setState(() => couponCheck = r); } catch (e) { if (mounted) toast(context, marketErrText(e), error: true); }
  }

  Future<void> _order(Listing x) async {
    final note = await askText(context, title: 'ملاحظة للبائع', hint: 'مثال: الاستلام بعد المغرب', confirm: 'تأكيد الطلب', maxLines: 2);
    if (note == null || !mounted) return;
    try {
      final r = await ref.read(apiClientProvider).order(x.id, x.isService ? 1 : qty, note: note, variant: variant, coupon: coupon.text.trim().toUpperCase(), slot: slot);
      ref.invalidate(ordersProvider); ref.invalidate(walletProvider); ref.invalidate(listingProvider(x.id));
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('تم الطلب'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('رمز الاستلام الخاص بك:'), const SizedBox(height: 8),
          Center(child: Text(r['code']?.toString() ?? '', key: const Key('order-code'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: 6))),
          const SizedBox(height: 8), const Text('أعطه للبائع عند الاستلام أو أكّد الاستلام من صفحة الطلب. لا يصل المبلغ للبائع قبل ذلك.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')), FilledButton(onPressed: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage())); }, child: const Text('طلباتي'))],
      ));
    } catch (e) { if (mounted) toast(context, marketErrText(e), error: true); }
  }

  void _toggleCompare(Listing x) {
    final cur = ref.read(compareProvider);
    if (cur.any((c) => c.id == x.id)) { ref.read(compareProvider.notifier).state = cur.where((c) => c.id != x.id).toList(); toast(context, 'أُزيل من المقارنة'); return; }
    if (cur.length >= 3) { toast(context, 'المقارنة حتى ٣ عروض', error: true); return; }
    ref.read(compareProvider.notifier).state = [...cur, x]; toast(context, 'أُضيف للمقارنة (${cur.length + 1})');
  }

  Future<void> _reportListing(Listing x) async {
    final r = await showReportSheet(context, ref, type: 'listing', id: widget.id, author: x.seller, title: 'إبلاغ عن العرض');
    if (r != null && (r.hidden || r.blocked) && mounted) Navigator.of(context).maybePop();
  }

  /// حظر البائع: لن تظهر عروضه وأسئلته وتقييماته لك (والخادم يمنع الطلب منه ومراسلته).
  Future<void> _blockSeller(Listing x) async {
    if (await confirmBlock(context, ref, x.seller) && mounted) Navigator.of(context).maybePop();
  }
}

class _Gallery extends StatelessWidget {
  final List<String> images; final String kind; final PageController ctl; final int page; final ValueChanged<int> onPage;
  const _Gallery({required this.images, required this.kind, required this.ctl, required this.page, required this.onPage});
  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return Container(height: 200, color: Joy.surface2, alignment: Alignment.center, child: Icon(kind == 'service' ? Icons.handshake_outlined : Icons.shopping_bag_outlined, size: 48, color: Joy.control));
    return SizedBox(height: 300, child: Stack(children: [
      PageView.builder(controller: ctl, itemCount: images.length, onPageChanged: onPage, itemBuilder: (_, i) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Viewer(images: images, initial: i))),
        child: Image.network(thumbUrl(images[i]), fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: Joy.surface2)))),
      if (images.length > 1) Positioned(bottom: 10, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < images.length; i++) AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 3), width: i == page ? 18 : 6, height: 6, decoration: BoxDecoration(color: i == page ? Colors.white : Colors.white60, borderRadius: BorderRadius.circular(999)))])),
      if (images.length > 1) Positioned(top: 10, left: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)), child: Text('${page + 1}/${images.length}', style: const TextStyle(color: Colors.white, fontSize: 11)))),
    ]));
  }
}

class _Viewer extends StatelessWidget {
  final List<String> images; final int initial;
  const _Viewer({required this.images, required this.initial});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView.builder(controller: PageController(initialPage: initial), itemCount: images.length, itemBuilder: (_, i) => InteractiveViewer(child: Center(child: Image.network(mediaUrl(images[i]), fit: BoxFit.contain)))));
}

/// بطاقة البائع: تقييم وشارات ومتابعة ومراسلة
class _SellerCard extends ConsumerWidget {
  final Listing l;
  const _SellerCard({required this.l});
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerPage(l.seller.id))),
        child: Row(children: [
          ProfileAvatar(person: l.seller, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.seller.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (l.sellerRating != null) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star_rounded, size: 15, color: Joy.sunText), Text(' ${l.sellerRating!.toStringAsFixed(1)} (${l.sellerRatingCount})', style: const TextStyle(fontSize: 12, color: Joy.textMuted))]) else const Text('بائع جديد', style: TextStyle(fontSize: 12, color: Joy.textMuted)),
              for (final b in l.sellerBadges.take(2)) BadgeChip(b),
            ]),
          ])),
          if (!l.mine) OutlinedButton(key: const Key('message-seller'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: l.seller))), style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('مراسلة')),
        ]),
      );
}

class BadgeChip extends StatelessWidget {
  final String badge;
  const BadgeChip(this.badge, {super.key});
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (badge) { 'verified' => (Icons.verified_rounded, Joy.primary), 'trusted' => (Icons.shield_rounded, Joy.success), 'top' => (Icons.star_rounded, Joy.sunText), 'fast' => (Icons.bolt_rounded, Joy.accent), _ => (Icons.workspace_premium_rounded, Joy.warning) };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: color), const SizedBox(width: 3), Text(sellerBadgeLabels[badge] ?? badge, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700))]));
  }
}

/// اختيار موعد من أوقات الخدمة: أيام السبعة القادمة ثم ساعات اليوم المختار
class SlotPicker extends StatefulWidget {
  final Availability availability; final DateTime? value; final ValueChanged<DateTime?> onChanged;
  const SlotPicker({super.key, required this.availability, this.value, required this.onChanged});
  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  DateTime? day;
  List<DateTime> get days { final now = DateTime.now(); return [for (var i = 0; i < 14; i++) DateTime(now.year, now.month, now.day + i)].where((d) => widget.availability.days.contains(d.weekday % 7)).take(7).toList(); }
  List<DateTime> slotsOf(DateTime d) {
    final a = widget.availability; int hm(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);
    final out = <DateTime>[]; for (var m = hm(a.from); m + a.slotMinutes <= hm(a.to); m += a.slotMinutes) { final t = DateTime(d.year, d.month, d.day, m ~/ 60, m % 60); if (t.isAfter(DateTime.now())) out.add(t); }
    return out;
  }
  @override
  Widget build(BuildContext context) {
    final ds = days; final d = day ?? (ds.isEmpty ? null : ds.first);
    if (d == null) return const Text('لا مواعيد متاحة حالياً', style: TextStyle(color: Joy.textMuted));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [for (final x in ds) Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(key: Key('day-${x.day}'), label: Text('${weekdayLabels[x.weekday % 7]} ${x.day}/${x.month}', style: const TextStyle(fontSize: 12)), selected: x == d, showCheckmark: false, selectedColor: Joy.primarySoft, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() { day = x; widget.onChanged(null); })))])),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in slotsOf(d)) ChoiceChip(key: Key('slot-${t.hour}-${t.minute}'), label: Text(clockOf(t), style: const TextStyle(fontSize: 12)), selected: widget.value == t, showCheckmark: false, selectedColor: Joy.primarySoft, visualDensity: VisualDensity.compact, onSelected: (_) => widget.onChanged(t))]),
    ]);
  }
}

class _Questions extends ConsumerWidget {
  final Listing listing; final TextEditingController controller;
  const _Questions({required this.listing, required this.controller});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedIdsProvider);
    final qs = [for (final q in ref.watch(listingQuestionsProvider(listing.id)).valueOrNull ?? const <MarketQuestion>[]) if (!isBlockedId(blocked, q.user.id)) q];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Text('أسئلة وأجوبة${qs.isEmpty ? '' : ' (${qs.length})'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 6),
      if (qs.isEmpty) const Text('لا أسئلة بعد. اسأل البائع وسيظهر الجواب للجميع.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      for (final q in qs) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.help_outline_rounded, size: 16, color: Joy.textMuted), const SizedBox(width: 6), Expanded(child: Text(q.text, style: const TextStyle(fontWeight: FontWeight.w600))), Text(timeAgo(q.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
          SizedBox(height: 28, child: ReportMenuButton(type: 'listing-question', id: q.id, author: q.user, keyPrefix: 'question-${q.id}', iconSize: 18, reportLabel: 'إبلاغ عن السؤال',
            onReported: (r) { if (r.hidden) ref.invalidate(listingQuestionsProvider(listing.id)); }))]),
        if (q.answer != null) Padding(padding: const EdgeInsets.only(right: 22, top: 3), child: Text(q.answer!, style: const TextStyle(color: Joy.text, height: 1.5)))
        else if (listing.mine) Padding(padding: const EdgeInsets.only(right: 22), child: TextButton(key: Key('answer-${q.id}'), onPressed: () async {
          final a = await askText(context, title: 'الجواب', confirm: 'نشر الجواب'); if (a == null || a.isEmpty) return;
          try { await ref.read(apiClientProvider).answerQuestion(q.id, a); ref.invalidate(listingQuestionsProvider(listing.id)); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
        }, child: const Text('أجب'))),
      ])),
      if (!listing.mine && listing.status == 'active') Row(children: [
        Expanded(child: TextField(key: const Key('ask-field'), controller: controller, decoration: const InputDecoration(hintText: 'اسأل البائع سؤالاً عاماً', isDense: true))),
        IconButton(key: const Key('ask-send'), icon: const Icon(Icons.send_rounded, color: Joy.primary), onPressed: () async {
          final t = controller.text.trim(); if (t.length < 3) return;
          try { await ref.read(apiClientProvider).askQuestion(listing.id, t); controller.clear(); ref.invalidate(listingQuestionsProvider(listing.id)); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
        }),
      ]),
    ]);
  }
}

class _Reviews extends ConsumerWidget {
  final String listingId; final double? ratingAvg; final int count;
  const _Reviews({required this.listingId, this.ratingAvg, this.count = 0});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedIdsProvider);
    final rs = [for (final r in ref.watch(listingReviewsProvider(listingId)).valueOrNull ?? const <MarketReview>[]) if (!isBlockedId(blocked, r.buyer.id)) r];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Row(children: [const Text('التقييمات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(width: 8), if (ratingAvg != null) ...[const Icon(Icons.star_rounded, size: 18, color: Joy.sunText), Text('${ratingAvg!.toStringAsFixed(1)} · $count', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))]]),
      const SizedBox(height: 6),
      if (rs.isEmpty) const Text('لا تقييمات بعد. التقييم متاح للمشترين بعد اكتمال الطلب.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      for (final r in rs) ReviewTile(r),
    ]);
  }
}

class ReviewTile extends ConsumerWidget {
  final MarketReview r;
  const ReviewTile(this.r, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [ProfileAvatar(person: r.buyer, size: 24), const SizedBox(width: 6), Flexible(child: Text(r.buyer.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), const SizedBox(width: 6), Stars(r.rating), const Spacer(), Text(timeAgo(r.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
          // معرّف تقييم العرض على الخادم هو رقم الطلب
          SizedBox(height: 28, child: ReportMenuButton(type: 'listing-review', id: r.orderId, author: r.buyer, keyPrefix: 'review-${r.orderId}', iconSize: 18, reportLabel: 'إبلاغ عن التقييم',
            onReported: (x) { if (x.hidden) ref.invalidate(listingReviewsProvider(r.listingId)); }))]),
        if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(r.text, style: const TextStyle(height: 1.5))),
        if (r.reply != null) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(10)), child: Text('ردّ البائع: ${r.reply}', style: const TextStyle(fontSize: 12.5))),
      ]));
}

class Stars extends StatelessWidget {
  final int n; final double size;
  const Stars(this.n, {super.key, this.size = 14});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 1; i <= 5; i++) Icon(i <= n ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: Joy.sunText)]);
}
