// قسم السوق في لوحة الإدارة: أرقام ٣٠ يوماً، عروض بانتظار المراجعة، نزاعات وحسمها، أعلى البائعين، تصنيفات راكدة،
// منح سبوت لايت، وتمييز بائع مرخّص.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../market/market_page.dart';
import 'admin_shell.dart';

final adminMarketProvider = FutureProvider<MarketAdminOverview>((ref) => ref.watch(apiClientProvider).adminMarketOverview());

class AdminMarketPage extends ConsumerWidget {
  const AdminMarketPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(adminMarketProvider);
    return d.when(
      data: (o) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        TileGrid(children: [
          StatTile(label: 'حجم التداول ٣٠ يوماً', value: money(o.gmv30), icon: Icons.shopping_bag_outlined, color: Joy.primary, hint: '${o.orders30} طلب · متوسط السلة ${money(o.basket)}'),
          StatTile(label: 'عمولة المنصة', value: money(o.commission30), icon: Icons.percent_rounded, color: Joy.success, hint: 'النسبة الحالية ${o.commissionPct}٪'),
          StatTile(label: 'سبوت لايت', value: money(o.spotlightRevenue30), icon: Icons.auto_awesome_rounded, color: Joy.sunText, hint: '${o.spotlightActive} نشط · ${money(o.spotlightPricePerDay)}/يوم'),
          StatTile(label: 'نزاعات مفتوحة', value: '${o.disputesOpen}', icon: Icons.gavel_rounded, color: o.disputesOpen > 0 ? Joy.danger : Joy.textMuted, hint: '${o.ordersOpen} طلب جارٍ · إلغاء ${o.cancelRatePct}٪'),
          StatTile(label: 'عروض ظاهرة', value: '${o.listings['active'] ?? 0}', icon: Icons.storefront_outlined, hint: '${o.listings['pending'] ?? 0} للمراجعة · ${o.listings['blocked'] ?? 0} محجوبة · ${o.listings['draft'] ?? 0} مسودات'),
        ]),
        Row(children: [const Expanded(child: SectionTitle('إجراءات')), TextButton.icon(key: const Key('am-grant'), onPressed: () => _grantSpotlight(context, ref), icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: const Text('منح سبوت لايت')), TextButton.icon(key: const Key('am-license'), onPressed: () => _license(context, ref), icon: const Icon(Icons.workspace_premium_rounded, size: 18), label: const Text('تمييز بائع مرخّص'))]),
        if (o.pending.isNotEmpty) ...[
          SectionTitle('بانتظار المراجعة (${o.pending.length})'),
          JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, l) in o.pending.indexed) ListRow(
            leading: Container(width: 40, height: 40, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(10)), child: l.imageUrl != null ? Image.network(l.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()) : null),
            title: Text(l.title), subtitle: Text('${l.seller.nickname} · ${money(l.price)} · ${marketCategories[l.category] ?? l.category}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: Key('am-approve-${l.id}'), tooltip: 'قبول', icon: const Icon(Icons.check_circle_outline_rounded, color: Joy.success), onPressed: () => _pending(context, ref, l, true)),
              IconButton(key: Key('am-reject-${l.id}'), tooltip: 'رفض', icon: const Icon(Icons.cancel_outlined, color: Joy.danger), onPressed: () => _pending(context, ref, l, false)),
            ]), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))), divider: i < o.pending.length - 1)])),
        ],
        if (o.disputes.isNotEmpty) ...[
          SectionTitle('النزاعات (${o.disputes.length})'),
          for (final d in o.disputes) JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text('${d.title} · ${money(d.total)}', style: const TextStyle(fontWeight: FontWeight.w700))), Text(timeAgo(d.updatedAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]),
            Text('المشتري ${d.buyer.nickname} · البائع ${d.seller.nickname}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            if (d.disputeReason != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('السبب: ${d.disputeReason}')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(key: Key('am-refund-${d.id}'), onPressed: () => _resolve(context, ref, d, 'refund'), child: const Text('إعادة المبلغ للمشتري')),
              OutlinedButton(key: Key('am-release-${d.id}'), onPressed: () => _resolve(context, ref, d, 'release'), child: const Text('تحرير المبلغ للبائع')),
              OutlinedButton(onPressed: () => _resolve(context, ref, d, 'split'), child: const Text('تقسيم')),
            ]),
          ])),
        ],
        const SectionTitle('أعلى البائعين هذا الشهر'),
        if (o.topSellers.isEmpty) const Text('لا مبيعات مكتملة بعد', style: TextStyle(color: Joy.textMuted)),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, t) in o.topSellers.indexed) ListRow(leading: ProfileAvatar(person: t.seller, size: 36), title: Text(t.seller.nickname), subtitle: Text('${t.orders} طلب مكتمل'), trailing: Text(money(t.revenue), style: const TextStyle(fontWeight: FontWeight.w700)), divider: i < o.topSellers.length - 1)])),
        const SectionTitle('التصنيفات'),
        JoyCard(child: Wrap(spacing: 8, runSpacing: 8, children: [for (final c in o.categories) Chip(avatar: Icon(marketCategoryIcon(c.category), size: 16, color: c.stale ? Joy.warning : Joy.primary), label: Text('${marketCategories[c.category] ?? c.category} · ${c.active}${c.stale ? ' · راكد' : ''}'), backgroundColor: c.stale ? Joy.sunSoft : Joy.surface2, side: BorderSide.none)])),
        if (o.cities.isNotEmpty) ...[const SectionTitle('المدن الأكثر نشاطاً'), JoyCard(child: Wrap(spacing: 8, runSpacing: 8, children: [for (final c in o.cities) Chip(label: Text('${c.city} · ${c.orders}'), backgroundColor: Joy.surface2, side: BorderSide.none)]))],
      ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminMarketProvider)),
    );
  }

  Future<void> _pending(BuildContext context, WidgetRef ref, Listing l, bool approve) async {
    final note = approve ? '' : await askText(context, title: 'سبب الرفض', hint: 'يصل للبائع', confirm: 'رفض');
    if (note == null || !context.mounted) return;
    try { await ref.read(apiClientProvider).adminMarketPending(l.id, approve: approve, note: note); ref.invalidate(adminMarketProvider); if (context.mounted) toast(context, approve ? 'نُشر العرض' : 'رُفض العرض'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
  }
  Future<void> _resolve(BuildContext context, WidgetRef ref, Order d, String resolution) async {
    final note = await askText(context, title: 'قرار النزاع', hint: 'ملاحظة تصل للطرفين (اختياري)', confirm: 'تنفيذ');
    if (note == null || !context.mounted) return;
    try { await ref.read(apiClientProvider).adminMarketDispute(d.id, resolution: resolution, note: note); ref.invalidate(adminMarketProvider); if (context.mounted) toast(context, 'حُسم النزاع'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
  }
  Future<void> _grantSpotlight(BuildContext context, WidgetRef ref) async {
    final id = await askText(context, title: 'منح سبوت لايت', hint: 'معرّف العرض (UUID)', confirm: 'التالي', maxLines: 1);
    if (id == null || id.isEmpty || !context.mounted) return;
    final days = await askText(context, title: 'عدد الأيام', initial: '7', confirm: 'منح', maxLines: 1, keyboardType: TextInputType.number);
    if (days == null || !context.mounted) return;
    try { await ref.read(apiClientProvider).adminMarketSpotlight(id.trim(), int.tryParse(days) ?? 7); ref.invalidate(adminMarketProvider); if (context.mounted) toast(context, 'مُنح العرض سبوت لايت'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
  }
  Future<void> _license(BuildContext context, WidgetRef ref) async {
    final id = await askText(context, title: 'بائع مرخّص', hint: 'معرّف الحساب (SA…)', confirm: 'تمييز', maxLines: 1);
    if (id == null || id.isEmpty || !context.mounted) return;
    try { await ref.read(apiClientProvider).adminMarketSellerFlags(id.trim().toUpperCase(), licensed: true); ref.invalidate(adminMarketProvider); if (context.mounted) toast(context, 'مُيّز البائع بشارة مرخّص'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
  }
}
