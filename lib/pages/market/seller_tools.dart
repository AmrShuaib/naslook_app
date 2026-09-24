// أدوات البائع والمشتري: ملف البائع العام، لوحة البائع (إحصاءات وكوبونات وسبوت لايت)، ورقة شراء سبوت لايت،
// تنبيهات العروض الجديدة، وصفحة المقارنة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/platform.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import '../wallet/wallet_page.dart';
import 'listing_page.dart';
import 'market_page.dart';

final sellerProfileProvider = FutureProvider.family<SellerProfile, String>((ref, id) => ref.watch(apiClientProvider).seller(id));
final sellerDashboardProvider = FutureProvider<SellerDashboard>((ref) => ref.watch(apiClientProvider).sellerStats());
final couponsProvider = FutureProvider<List<Coupon>>((ref) => ref.watch(apiClientProvider).coupons());
final spotlightMineProvider = FutureProvider<List<SpotlightMine>>((ref) => ref.watch(apiClientProvider).spotlightMine());
final marketAlertsProvider = FutureProvider<List<MarketAlert>>((ref) => ref.watch(apiClientProvider).marketAlerts());

/// ملف البائع العام
class SellerPage extends ConsumerWidget {
  final String id;
  const SellerPage(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(sellerProfileProvider(id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(p.valueOrNull?.seller.nickname ?? 'البائع'), actions: [
        // البائع شخص لا محتوى: البلاغ يذهب إلى بلاغات المستخدمين، والحظر يخفي عروضه ويغلق الصفحة
        if (p.valueOrNull case final x? when !x.mine)
          ReportMenuButton(type: kReportUser, id: x.seller.id, author: x.seller, keyPrefix: 'seller', iconSize: 24, color: Joy.text, reportLabel: 'إبلاغ عن البائع',
            onBlocked: () { if (context.mounted) Navigator.of(context).maybePop(); }),
      ]),
      body: p.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            ProfileAvatar(person: x.seller, size: 64), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.seller.nickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Row(children: [if (x.stats.ratingAvg != null) ...[const Icon(Icons.star_rounded, size: 16, color: Joy.sunText), Text(' ${x.stats.ratingAvg!.toStringAsFixed(1)} (${x.stats.ratingCount})', style: const TextStyle(fontSize: 12.5, color: Joy.textMuted))] else const Text('لا تقييمات بعد', style: TextStyle(fontSize: 12.5, color: Joy.textMuted)), Text(' · ${x.followers} متابع', style: const TextStyle(fontSize: 12.5, color: Joy.textMuted))]),
              if (x.memberSince != null) Text('عضو منذ ${timeAgo(x.memberSince)}', style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
            ])),
          ]),
          if (x.badges.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final b in x.badges) BadgeChip(b)])),
          if (x.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(x.bio, style: const TextStyle(height: 1.6))),
          const SizedBox(height: 12),
          Row(children: [
            _tile('طلبات مكتملة', '${x.stats.completed}'), _tile('عروض', '${x.stats.activeListings}'), if (x.stats.responseHours != null) _tile('يقبل خلال', x.stats.responseHours! < 1 ? 'أقل من ساعة' : '${x.stats.responseHours!.toStringAsFixed(0)} س'),
          ]),
          const SizedBox(height: 12),
          if (!x.mine) Row(children: [
            Expanded(child: FilledButton.icon(key: const Key('follow-btn'), style: FilledButton.styleFrom(backgroundColor: x.following ? Joy.surface2 : Joy.primary, foregroundColor: x.following ? Joy.text : Joy.primaryOn), onPressed: () async {
              try { x.following ? await ref.read(apiClientProvider).unfollowSeller(id) : await ref.read(apiClientProvider).followSeller(id); ref.invalidate(sellerProfileProvider(id)); if (context.mounted) toast(context, x.following ? 'ألغيت المتابعة' : 'ستصلك عروضه الجديدة'); } catch (e) { if (context.mounted) toast(context, e.toString(), error: true); }
            }, icon: Icon(x.following ? Icons.check_rounded : Icons.notifications_active_outlined, size: 18), label: Text(x.following ? 'متابَع' : 'متابعة'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () { if (requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: x.seller))); }, icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('مراسلة')),
          ]),
          const SectionTitle('عروضه'),
          if (x.listings.isEmpty) const Text('لا عروض حالياً', style: TextStyle(color: Joy.textMuted)),
          GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .72), itemCount: x.listings.length, itemBuilder: (_, i) => ListingCard(x.listings[i])),
          if (x.reviews.isNotEmpty) ...[const SectionTitle('التقييمات'), for (final r in x.reviews) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ReviewTile(r), if (r.listingTitle != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('على: ${r.listingTitle}', style: const TextStyle(color: Joy.textMuted, fontSize: 11)))])],
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(sellerProfileProvider(id))),
      ),
    );
  }
  Widget _tile(String l, String v) => Expanded(child: Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Column(children: [Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text(l, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))])));
}

/// لوحة البائع: أرقام اليوم والأسبوع والشهر، التحويل، أعلى العروض، الكوبونات، وسبوت لايت
class SellerDashboardPage extends ConsumerWidget {
  const SellerDashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(sellerDashboardProvider);
    final coupons = ref.watch(couponsProvider).valueOrNull ?? const <Coupon>[];
    final spots = ref.watch(spotlightMineProvider).valueOrNull ?? const <SpotlightMine>[];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('لوحة البائع'), actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () { ref.invalidate(sellerDashboardProvider); ref.invalidate(couponsProvider); ref.invalidate(spotlightMineProvider); })]),
      body: d.when(
        data: (s) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [_kpi('اليوم', money(s.todayRevenue), '${s.todayOrders} طلب'), _kpi('٧ أيام', money(s.weekRevenue), '${s.weekOrders} طلب'), _kpi('٣٠ يوماً', money(s.monthRevenue), 'صافي ${money(s.monthNet)}')]),
          const SizedBox(height: 8),
          Row(children: [_kpi('مشاهدات ٧ أيام', '${s.views7}', 'تحويل ${s.conversionPct}٪'), _kpi('بانتظارك', '${s.pending}', '${s.awaitingConfirm} بانتظار تأكيد المشتري'), _kpi('التقييم', s.ratingAvg?.toStringAsFixed(1) ?? '—', '${s.ratingCount} تقييم · ${s.followers} متابع')]),
          if (s.disputed > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('لديك ${s.disputed} نزاع مفتوح تراجعه الإدارة', style: const TextStyle(color: Joy.danger, fontWeight: FontWeight.w600))),
          if (s.badges.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, children: [for (final b in s.badges) BadgeChip(b)])),
          const SectionTitle('أعلى عروضك'),
          if (s.top.isEmpty) const Text('لا بيانات بعد', style: TextStyle(color: Joy.textMuted)),
          JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, t) in s.top.indexed) ListRow(leading: Container(width: 40, height: 40, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(10)), child: t.imageUrl != null ? Image.network(thumbUrl(t.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()) : null), title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${t.views7} مشاهدة هذا الأسبوع · ${t.sold} مبيعة · ${money(t.revenue)}'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(t.id))), divider: i < s.top.length - 1)])),
          Row(children: [const Expanded(child: SectionTitle('كوبونات الخصم')), TextButton.icon(key: const Key('coupon-new'), onPressed: () => _newCoupon(context, ref), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('كوبون جديد'))]),
          if (coupons.isEmpty) const Text('أنشئ كوبوناً يكتبه المشتري عند الطلب (مثال: WELCOME10).', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, c) in coupons.indexed) ListRow(leading: Icon(Icons.confirmation_number_outlined, color: c.active ? Joy.primary : Joy.textMuted), title: Text('${c.code} · ${c.label}'), subtitle: Text('${c.used}${c.maxUses != null ? '/${c.maxUses}' : ''} استخدام${c.minTotal > 0 ? ' · حد أدنى ${money(c.minTotal)}' : ''}${c.expiresAt != null ? ' · ينتهي ${c.expiresAt!.day}/${c.expiresAt!.month}' : ''}'),
            trailing: Switch(value: c.active, onChanged: (v) async { await ref.read(apiClientProvider).setCouponActive(c.code, v); ref.invalidate(couponsProvider); }), divider: i < coupons.length - 1)])),
          const SizedBox(height: 12),
          _UpgradeCard(),
          // على iOS لا يُباع سبوت لايت (إعلان رقمي، قاعدة أبل 3.1.1): بلا زر شراء ولا مبالغ، ونعرض الإعلانات الجارية فقط إن وُجدت
          if (!isIosNative || spots.isNotEmpty)
            Row(children: [const Expanded(child: SectionTitle('سبوت لايت')), if (!isIosNative) TextButton.icon(key: const Key('spotlight-buy'), onPressed: () => showSpotlightSheet(context, ref), icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: const Text('اشترِ إعلاناً'))]),
          if (spots.isEmpty && !isIosNative) const Text('ضع عرضك في أعلى السوق ليراه كل من يدخله.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, sp) in spots.indexed) ListRow(leading: Icon(Icons.auto_awesome_rounded, color: sp.status == 'active' ? Joy.sunText : Joy.textMuted), title: Text(sp.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${sp.status == 'active' ? 'نشط حتى ${sp.endsAt!.day}/${sp.endsAt!.month}' : 'انتهى'} · ${sp.views} ظهور · ${sp.clicks} نقرة${sp.granted ? ' · منحة من الإدارة' : isIosNative ? '' : ' · ${money(sp.paid)}'}'), divider: i < spots.length - 1)])),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(sellerDashboardProvider)),
      ),
    );
  }
  Widget _kpi(String l, String v, String h) => Expanded(child: Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: Joy.textMuted, fontSize: 11)), Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), Text(h, style: const TextStyle(color: Joy.textMuted, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)])));

  Future<void> _newCoupon(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController(), pct = TextEditingController(), amount = TextEditingController(), min = TextEditingController(), uses = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('كوبون جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('coupon-code'), controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'الرمز (حروف وأرقام)')),
      Row(children: [Expanded(child: TextField(key: const Key('coupon-pct'), controller: pct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نسبة ٪'))), const SizedBox(width: 8), Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أو مبلغ ثابت (ر.س)')))]),
      Row(children: [Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد أدنى (ر.س)'))), const SizedBox(width: 8), Expanded(child: TextField(controller: uses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الاستخدامات')))]),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('coupon-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء'))]));
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).createCoupon({'code': code.text.trim(), if (pct.text.trim().isNotEmpty) 'percent': int.tryParse(pct.text.trim()), if (amount.text.trim().isNotEmpty) 'amount': parseSar(amount.text), 'minTotal': parseSar(min.text), if (uses.text.trim().isNotEmpty) 'maxUses': int.tryParse(uses.text.trim())});
      ref.invalidate(couponsProvider); if (context.mounted) toast(context, 'أُنشئ الكوبون');
    } catch (e) { if (context.mounted) toast(context, e.toString().contains('exists') ? 'الرمز مستخدم من قبل' : e.toString().contains('bad-discount') ? 'حدد نسبة بين ١ و٩٠ أو مبلغاً' : marketErrText(e), error: true); }
  }
}

/// ورقة سبوت لايت: اشرح السعر، اختر عرضاً من عروضي، وعدد الأيام، وادفع من المحفظة
Future<void> showSpotlightSheet(BuildContext context, WidgetRef ref, {Listing? listing}) async {
  // لا شراء لسبوت لايت في iOS (والخادم يرفضه بـ iap-required)؛ الزر مخفي أصلاً وهذا حاجز أخير
  if (isIosNative) return;
  if (!requireAccount(context)) return;
  final api = ref.read(apiClientProvider);
  Map<String, dynamic> price = const {'perDay': 2000, 'maxDays': 30};
  List<Listing> mine = const [];
  try { price = await api.spotlightPrice(); mine = (await api.myListings()).where((l) => l.status == 'active').toList(); } catch (_) {}
  if (!context.mounted) return;
  final perDay = (price['perDay'] as num?)?.toInt() ?? 2000; final maxDays = (price['maxDays'] as num?)?.toInt() ?? 30;
  var days = 3; Listing? chosen = listing ?? (mine.length == 1 ? mine.first : null);
  final wallet = ref.read(walletProvider).valueOrNull;
  await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.auto_awesome_rounded, color: Joy.sunText), const SizedBox(width: 8), const Text('سبوت لايت', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))]),
      const SizedBox(height: 6),
      Text('إعلانك في أعلى السوق يراه كل من يدخله. ${money(perDay)} لليوم الواحد، يُدفع من محفظتك.', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
      const SizedBox(height: 12),
      if (listing == null) ...[
        if (mine.isEmpty) const Text('ليس لديك عروض ظاهرة الآن. انشر عرضاً أولاً.', style: TextStyle(color: Joy.danger))
        else DropdownButtonFormField<String>(key: const Key('spot-listing'), initialValue: chosen?.id, decoration: const InputDecoration(labelText: 'العرض'), items: [for (final l in mine) DropdownMenuItem(value: l.id, child: Text(l.title, overflow: TextOverflow.ellipsis))], onChanged: (v) => setS(() => chosen = mine.firstWhere((l) => l.id == v))),
        const SizedBox(height: 8),
      ],
      Row(children: [const Text('المدة'), const Spacer(), IconButton(onPressed: days > 1 ? () => setS(() => days--) : null, icon: const Icon(Icons.remove_rounded)), Text('$days يوم', key: const Key('spot-days'), style: const TextStyle(fontWeight: FontWeight.w700)), IconButton(onPressed: days < maxDays ? () => setS(() => days++) : null, icon: const Icon(Icons.add_rounded))]),
      Row(children: [const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(), Text(money(perDay * days), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Joy.primary))]),
      if (wallet != null) Text('رصيد محفظتك ${money(wallet.balance)}', style: TextStyle(color: wallet.balance < perDay * days ? Joy.danger : Joy.textMuted, fontSize: 12)),
      const SizedBox(height: 12),
      FilledButton.icon(key: const Key('spot-pay'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: chosen == null ? null : () async {
        try { final r = await api.buySpotlight(chosen!.id, days); if (!ctx.mounted) return; Navigator.pop(ctx); invalidateMarket(ref); ref.invalidate(spotlightMineProvider); ref.invalidate(walletProvider); ref.invalidate(listingProvider(chosen!.id)); toast(context, 'صار عرضك في سبوت لايت لمدة $days يوم (${money((r['paid'] as num).toInt())})'); }
        catch (e) { if (ctx.mounted) toast(ctx, marketErrText(e), error: true); }
      }, icon: const Icon(Icons.account_balance_wallet_outlined), label: Text('ادفع ${money(perDay * days)} من المحفظة')),
    ]),
  )));
}

/// تنبيهات العروض الجديدة: بكلمة أو تصنيف ضمن نطاق من موقعي
Future<void> showMarketAlertsSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (ctx) => Consumer(builder: (ctx, ref, _) {
    final alerts = ref.watch(marketAlertsProvider).valueOrNull ?? const <MarketAlert>[];
    return Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('تنبيهات العروض الجديدة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const Text('يصلك إشعار عند نشر عرض يطابق كلمة أو تصنيفاً قرب موقعك.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      const SizedBox(height: 8),
      if (alerts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('لا تنبيهات بعد', style: TextStyle(color: Joy.textMuted))),
      for (final a in alerts) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notifications_active_outlined, color: Joy.primary), title: Text([if (a.q != null) '«${a.q}»', if (a.category != null) marketCategories[a.category] ?? a.category!, if (a.subcategory != null) marketSubcategories[a.category]?[a.subcategory] ?? ''].join(' · ')), subtitle: Text(a.lat != null ? 'ضمن ${a.radiusKm} كم من موقعك' : 'في كل المدن'),
        trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger), onPressed: () async { await ref.read(apiClientProvider).deleteMarketAlert(a.id); ref.invalidate(marketAlertsProvider); })),
      const SizedBox(height: 6),
      FilledButton.tonalIcon(key: const Key('alert-new'), onPressed: () => _newAlert(ctx, ref), icon: const Icon(Icons.add_alert_outlined, size: 18), label: const Text('تنبيه جديد')),
    ]));
  }));
}

Future<void> _newAlert(BuildContext context, WidgetRef ref) async {
  final q = TextEditingController(); String? cat; var radius = 25;
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('تنبيه جديد'), content: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(key: const Key('alert-q'), controller: q, decoration: const InputDecoration(labelText: 'كلمة (اختياري)', hintText: 'مثال: كنب، درس فيزياء')),
    DropdownButtonFormField<String?>(initialValue: cat, decoration: const InputDecoration(labelText: 'التصنيف (اختياري)'), items: [const DropdownMenuItem(value: null, child: Text('أي تصنيف')), for (final e in marketCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setS(() => cat = v)),
    DropdownButtonFormField<int>(initialValue: radius, decoration: const InputDecoration(labelText: 'النطاق'), items: const [5, 25, 100, 500].map((r) => DropdownMenuItem(value: r, child: Text(r == 500 ? 'كل المدن' : '$r كم'))).toList(), onChanged: (v) => setS(() => radius = v ?? 25)),
  ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('alert-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))])));
  if (ok != true || !context.mounted) return;
  final pos = ref.read(marketPosProvider).valueOrNull;
  try { await ref.read(apiClientProvider).createMarketAlert({'q': q.text.trim(), 'category': cat, 'radiusKm': radius, if (pos != null && radius < 500) ...{'lat': pos.lat, 'lng': pos.lng}}); ref.invalidate(marketAlertsProvider); } catch (e) { if (context.mounted) toast(context, e.toString().contains('empty') ? 'اكتب كلمة أو اختر تصنيفاً' : marketErrText(e), error: true); }
}

/// مقارنة حتى ٣ عروض جنباً إلى جنب
class ComparePage extends ConsumerWidget {
  const ComparePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(compareProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('مقارنة'), actions: [if (items.isNotEmpty) TextButton(onPressed: () => ref.read(compareProvider.notifier).state = const [], child: const Text('مسح'))]),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.compare_arrows_rounded, title: 'لا عروض للمقارنة', subtitle: 'من قائمة «المزيد» في أي عرض اختر «أضف للمقارنة».')
          : SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(20), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in items) SizedBox(width: 200, child: Padding(padding: const EdgeInsets.only(left: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ListingCard(l),
                const SizedBox(height: 8),
                for (final (k, v) in [('السعر', l.price == 0 ? 'مجاناً' : money(l.price)), ('التقييم', l.ratingAvg?.toStringAsFixed(1) ?? (l.sellerRating?.toStringAsFixed(1) ?? '—')), ('الحالة', marketConditions[l.condition] ?? '—'), ('التوصيل', l.delivery ? 'متاح' : 'لا'), ('المسافة', l.distanceKm != null ? '${l.distanceKm!.toStringAsFixed(1)} كم' : '—'), ('المبيعات', '${l.sold}'), ('البائع', l.seller.nickname)])
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Text('$k: ', style: const TextStyle(color: Joy.textMuted, fontSize: 12)), Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)))])),
                TextButton(onPressed: () => ref.read(compareProvider.notifier).state = items.where((x) => x.id != l.id).toList(), child: const Text('إزالة')),
              ]))),
            ])),
    );
  }
}

/// معاينة الترقية إلى دائرة أعمال (تُحمَّل مع لوحة البائع)
final upgradePreviewProvider = FutureProvider<UpgradePreview>((ref) => ref.watch(apiClientProvider).upgradePreview());

/// بطاقة «رقِّ حسابك إلى دائرة أعمال»: تنشئ دائرة من ملف البائع وتنسخ عروضه النشطة إلى كتالوجها
class _UpgradeCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pv = ref.watch(upgradePreviewProvider).valueOrNull;
    if (pv == null) return const SizedBox.shrink();
    if (pv.upgradedBizId != null) {
      return JoyCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessPage(id: pv.upgradedBizId!))), child: Row(children: [
        const Icon(Icons.storefront_rounded, color: Joy.primary), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('دائرتك التجارية', style: TextStyle(fontWeight: FontWeight.w700)), Text('${pv.upgradedItems} صنفاً نُسخت من عروضك · افتح لوحة المالك', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))])),
        const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
      ]));
    }
    if (!pv.eligible) return const SizedBox.shrink();
    return JoyCard(color: Joy.primarySoft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.storefront_rounded, color: Joy.primary), SizedBox(width: 8), Expanded(child: Text('رقِّ حسابك إلى دائرة أعمال', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))]),
      const SizedBox(height: 6),
      Text('تظهر على الخريطة وفي الدوائر باسم تجاري وكتالوج وعروض ومجتمع خاص، وتُنسخ عروضك الـ${pv.listings} النشطة إلى الكتالوج تلقائياً.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      const SizedBox(height: 10),
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(key: const Key('seller-upgrade'), onPressed: () => _upgrade(context, ref, pv), icon: const Icon(Icons.upgrade_rounded, size: 18), label: const Text('إنشاء دائرتي'))),
    ]));
  }

  Future<void> _upgrade(BuildContext context, WidgetRef ref, UpgradePreview pv) async {
    final name = TextEditingController(text: pv.suggestedName), desc = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('دائرة أعمال جديدة'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('upgrade-name'), controller: name, decoration: const InputDecoration(labelText: 'الاسم التجاري')),
      const SizedBox(height: 8),
      TextField(key: const Key('upgrade-desc'), controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'نبذة قصيرة (اختياري)')),
      const SizedBox(height: 6),
      Text('الفئة: ${bizCategoryLabel(pv.suggestedCategory)} · الموقع من عروضك · يمكنك تعديل كل شيء لاحقاً من لوحة المالك.', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('upgrade-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء'))]));
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    try {
      final bizId = await ref.read(apiClientProvider).upgradeSeller(nameAr: name.text.trim(), description: desc.text.trim());
      ref.invalidate(upgradePreviewProvider);
      if (context.mounted) { toast(context, 'أُنشئت دائرتك'); Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessPage(id: bizId))); }
    } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
}

String bizCategoryLabel(String c) => switch (c) { 'cafe' => 'مقهى', 'restaurant' => 'مطعم', 'company' => 'شركة', _ => 'علامة تجارية' };
