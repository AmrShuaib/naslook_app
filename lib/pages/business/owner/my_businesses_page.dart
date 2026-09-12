import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show openBusiness, BizLogo;
import 'business_dashboard_page.dart';
import 'business_editor.dart';

/// دوائري التجارية: ما أملكه أو أعمل فيه، مع إنشاء دائرة جديدة وطلبات الملكية.
class MyBusinessesPage extends ConsumerWidget {
  const MyBusinessesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myBusinessesProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('نشاطي التجاري'),
        actions: [
          if (mine.valueOrNull?.admin == true) IconButton(tooltip: 'طلبات الملكية', icon: const Icon(Icons.fact_check_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClaimsPage()))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openBusinessEditor(context),
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('دائرة تجارية جديدة'),
      ),
      body: mine.when(
        data: (m) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myBusinessesProvider),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 96), children: [
            if (m.circles.isEmpty && m.claims.isEmpty)
              const EmptyState(icon: Icons.storefront_outlined, title: 'لا دوائر تجارية بعد', subtitle: 'أنشئ دائرة لنشاطك: متجر أو مقهى أو سينما أو فندق أو تأجير سيارات، وأدر كتالوجك وطلباتك من هنا. أو اطلب ملكية دائرة موجودة من صفحتها.'),
            if (m.circles.isNotEmpty) const SectionTitle('دوائري'),
            for (final b in m.circles) Padding(padding: const EdgeInsets.only(bottom: 10), child: _OwnedRow(b)),
            if (m.claims.isNotEmpty) ...[
              const SectionTitle('طلبات الملكية'),
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [
                for (final (i, c) in m.claims.indexed)
                  ListRow(
                    leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(c.status == 'approved' ? Icons.check_circle_outline_rounded : c.status == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top_rounded, color: c.status == 'approved' ? Joy.success : c.status == 'rejected' ? Joy.danger : Joy.warning)),
                    title: Text(c.name),
                    subtitle: Text('${c.statusLabel}${c.note.isNotEmpty ? ' · ${c.note}' : ''}'),
                    onTap: () => openBusiness(context, c.bizId),
                    divider: i < m.claims.length - 1,
                  ),
              ])),
            ],
          ]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myBusinessesProvider)),
      ),
    );
  }
}

class _OwnedRow extends StatelessWidget {
  final Biz b;
  const _OwnedRow(this.b);
  @override
  Widget build(BuildContext context) => JoyCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: b.id, initial: b))),
        child: Row(children: [
          BizLogo(biz: b, size: 54),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: b.active ? Joy.primarySoft : Joy.accentSoft, borderRadius: BorderRadius.circular(999)), child: Text(b.active ? 'منشورة' : 'موقوفة', style: TextStyle(fontSize: 10.5, color: b.active ? Joy.primary : Joy.accent, fontWeight: FontWeight.w600))),
            ]),
            Text('${b.category.label} · ${b.roleLabel}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text('${b.itemsCount} عنصر · ${b.followers} متابع · ${b.views} مشاهدة', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
          const Icon(Icons.dashboard_customize_outlined, color: Joy.primary),
        ]),
      );
}

/// طلبات ملكية الدوائر المزروعة (للمدير).
class ClaimsPage extends ConsumerWidget {
  const ClaimsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(bizClaimsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('طلبات الملكية')),
      body: claims.when(
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.fact_check_outlined, title: 'لا طلبات معلّقة')
            : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                for (final c in list)
                  JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (c.user != null) ProfileAvatar(person: c.user!, size: 40),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c.user?.nickname ?? ''} يطلب ملكية ${c.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (c.note.isNotEmpty) Text(c.note, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                        Text(timeAgo(c.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                      ])),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: FilledButton(onPressed: () => _decide(context, ref, c, true), child: const Text('قبول'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () => _decide(context, ref, c, false), child: const Text('رفض'))),
                    ]),
                  ])),
              ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizClaimsProvider)),
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, BizClaim c, bool approve) async {
    try {
      await ref.read(apiClientProvider).decideClaim(c.bizId, c.user?.id ?? '', approve: approve);
      ref.invalidate(bizClaimsProvider);
      ref.invalidate(myBusinessesProvider);
      if (context.mounted) toast(context, approve ? 'مُنحت الملكية' : 'رُفض الطلب');
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }
}
