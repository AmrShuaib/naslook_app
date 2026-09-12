import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';
import 'admin_users.dart';

class AdminFinancePage extends ConsumerWidget {
  const AdminFinancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fin = ref.watch(adminFinanceProvider);
    return fin.when(
      data: (f) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        TileGrid(children: [
          StatTile(label: 'إجمالي الأرصدة', value: money(f.balance), icon: Icons.account_balance_wallet_outlined, color: Joy.success, hint: '${f.accounts} محفظة'),
          StatTile(label: 'النقاط', value: '${f.points}', icon: Icons.stars_rounded, color: Joy.warning),
          StatTile(label: 'مشتريات 14 يوماً', value: money(f.daily.fold(0, (s, d) => s + d.purchases)), icon: Icons.shopping_bag_outlined, color: Joy.accent),
          StatTile(label: 'استردادات 14 يوماً', value: money(f.daily.fold(0, (s, d) => s + d.refunds)), icon: Icons.replay_rounded, color: Joy.textMuted),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: SectionTitle('الشحن والمشتريات يومياً')),
          TextButton.icon(
            onPressed: () {
              final token = ref.read(appStateProvider).session?.token;
              launchUrl(Uri.parse(ref.read(apiClientProvider).adminExportUrl(days: 30, token: token)), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تصدير CSV (30 يوماً)'),
          ),
        ]),
        JoyCard(child: _FinanceBars(daily: f.daily)),
        const SizedBox(height: 8),
        const SectionTitle('حسب نوع الحركة'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, k) in f.byKind.indexed)
            ListRow(leading: const Icon(Icons.swap_horiz_rounded, color: Joy.textMuted), title: Text(WalletTx(id: '', kind: k.kind, amount: 0).label), subtitle: Text('${k.count} حركة'), trailing: Text(money(k.amount), style: TextStyle(fontWeight: FontWeight.w700, color: k.amount >= 0 ? Joy.success : Joy.danger)), divider: i < f.byKind.length - 1),
          if (f.byKind.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('لا حركات في المدة', style: TextStyle(color: Joy.textMuted))),
        ])),
        const SizedBox(height: 8),
        const SectionTitle('أعلى الأرصدة'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, t) in f.topBalances.indexed)
            ListRow(leading: ProfileAvatar(person: t.user, size: 40), title: Text(t.user.nickname.isEmpty ? t.user.id : t.user.nickname), subtitle: Text(t.user.id), trailing: Text(money(t.balance), style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: t.user.id))), divider: i < f.topBalances.length - 1),
        ])),
        const SizedBox(height: 8),
        const SectionTitle('آخر الحركات على المنصة'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, r) in f.recent.indexed)
            ListRow(
              leading: ProfileAvatar(person: r.user, size: 40),
              title: Text('${r.user.nickname.isEmpty ? r.user.id : r.user.nickname} · ${r.tx.label}'),
              subtitle: Text('${r.tx.note ?? ''} · ${timeAgo(r.tx.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('${r.tx.amount >= 0 ? '+' : ''}${money(r.tx.amount)}', style: TextStyle(fontWeight: FontWeight.w700, color: r.tx.amount >= 0 ? Joy.success : Joy.danger, fontSize: 13)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: r.user.id))),
              divider: i < f.recent.length - 1,
            ),
        ])),
      ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminFinanceProvider)),
    );
  }
}

class _FinanceBars extends StatelessWidget {
  final List<({DateTime day, int topups, int purchases, int refunds})> daily;
  const _FinanceBars({required this.daily});
  @override
  Widget build(BuildContext context) {
    final max = daily.fold<int>(0, (m, d) => [d.topups, d.purchases, m].reduce((a, b) => a > b ? a : b));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [_Legend(color: Joy.primary, label: 'شحن'), SizedBox(width: 12), _Legend(color: Joy.accent, label: 'مشتريات')]),
      const SizedBox(height: 8),
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in daily)
            Expanded(child: Tooltip(message: '${d.day.day}/${d.day.month}: شحن ${money(d.topups)} · مشتريات ${money(d.purchases)}', child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 5, height: max == 0 ? 2 : 2 + 90 * d.topups / max, margin: const EdgeInsets.only(left: 1), decoration: const BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.vertical(top: Radius.circular(3)))),
                Container(width: 5, height: max == 0 ? 2 : 2 + 90 * d.purchases / max, decoration: const BoxDecoration(color: Joy.accent, borderRadius: BorderRadius.vertical(top: Radius.circular(3)))),
              ]),
              const SizedBox(height: 4),
              Text('${d.day.day}', style: const TextStyle(fontSize: 9.5, color: Joy.textMuted, height: 1)),
            ]))),
        ]),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11.5, color: Joy.textMuted))]);
}
