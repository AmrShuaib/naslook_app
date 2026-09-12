import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/biz_models.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness;
import '../business/owner/business_dashboard_page.dart';
import 'admin_shell.dart';

class AdminBizPage extends ConsumerStatefulWidget {
  const AdminBizPage({super.key});
  @override
  ConsumerState<AdminBizPage> createState() => _AdminBizPageState();
}

class _AdminBizPageState extends ConsumerState<AdminBizPage> {
  String filter = 'all';
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminBizProvider);
    final claims = ref.watch(adminClaimsProvider);
    return list.when(
      data: (all) {
        var items = all.where((b) => switch (filter) { 'active' => b.active, 'inactive' => !b.active, 'unowned' => b.ownerId == null, 'owned' => b.ownerId != null, _ => true }).toList();
        if (q.isNotEmpty) items = items.where((b) => b.name.contains(q) || b.latin.toLowerCase().contains(q.toLowerCase()) || b.id.contains(q)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          claims.when(
            data: (cl) => cl.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('طلبات الملكية · ${cl.length}'),
              for (final c in cl)
                JoyCard(child: Row(children: [
                  if (c['user'] is Map) ProfileAvatar(person: Person.fromJson(asMap(c['user'])), size: 40),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${asMap(c['user'])['nickname'] ?? ''} يطلب ملكية ${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)), if ((c['note'] ?? '').toString().isNotEmpty) Text(c['note'].toString(), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))])),
                  IconButton(tooltip: 'قبول', onPressed: () => _decide(c, true), icon: const Icon(Icons.check_circle_rounded, color: Joy.success)),
                  IconButton(tooltip: 'رفض', onPressed: () => _decide(c, false), icon: const Icon(Icons.cancel_rounded, color: Joy.danger)),
                ])),
              const SizedBox(height: 8),
            ]),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(hintText: 'ابحث باسم الدائرة', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted), isDense: true)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final (k, l) in [('all', 'الكل'), ('active', 'منشورة'), ('inactive', 'موقوفة'), ('owned', 'مملوكة'), ('unowned', 'بلا مالك')])
              ChoiceChip(label: Text(l, style: TextStyle(color: filter == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: filter == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => filter = k)),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'لا دوائر مطابقة'),
          for (final b in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _BizCard(b: b)),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminBizProvider)),
    );
  }

  Future<void> _decide(Map<String, dynamic> c, bool approve) async {
    try {
      await ref.read(apiClientProvider).adminClaimDecide(c['bizId'].toString(), asMap(c['user'])['id'].toString(), approve: approve);
      invalidateAdmin(ref);
      if (mounted) toast(context, approve ? 'مُنحت الملكية' : 'رُفض الطلب');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }
}

class _BizCard extends ConsumerWidget {
  final AdminBiz b;
  const _BizCard({required this.b});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = BizCategory.of(b.category);
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(cat.icon, color: Joy.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              if (b.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified_rounded, size: 16, color: Joy.primary)),
              if (!b.active) Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(999)), child: const Text('موقوفة', style: TextStyle(color: Joy.accent, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            Text('${cat.label}${b.sector.isNotEmpty ? ' · ${b.sector}' : ''} · ${b.owner != null ? 'المالك ${b.owner!.nickname}' : 'بلا مالك'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text('${b.orders} طلب · ${money(b.revenue)} · ${b.followers} متابع · ${b.items} عنصر · ${b.views} مشاهدة', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: b.id))), icon: const Icon(Icons.dashboard_customize_outlined, size: 18), label: const Text('لوحة التحكم')),
          OutlinedButton.icon(onPressed: () => openBusiness(context, b.id), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('الصفحة')),
          FilledButton.tonalIcon(onPressed: () => _update(context, ref, verified: !b.verified), icon: Icon(b.verified ? Icons.remove_circle_outline_rounded : Icons.verified_outlined, size: 18), label: Text(b.verified ? 'سحب التوثيق' : 'توثيق')),
          FilledButton.tonalIcon(onPressed: () => _update(context, ref, active: !b.active), icon: Icon(b.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, size: 18), label: Text(b.active ? 'إيقاف' : 'نشر')),
          FilledButton.tonalIcon(onPressed: () => _owner(context, ref), icon: const Icon(Icons.person_pin_circle_outlined, size: 18), label: Text(b.ownerId == null ? 'تعيين مالك' : 'تغيير المالك')),
        ]),
      ]),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, {bool? verified, bool? active}) async {
    try {
      await ref.read(apiClientProvider).adminBizUpdate(b.id, verified: verified, active: active);
      invalidateAdmin(ref);
      invalidateBizAll(ref, b.id);
      if (context.mounted) toast(context, 'تم');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _owner(BuildContext context, WidgetRef ref) async {
    final handle = await askText(context, title: 'مالك ${b.name}', hint: 'النك نيم أو المعرّف SA… (اتركه فارغاً لإزالة المالك)', confirm: 'حفظ', maxLines: 1, initial: b.ownerId);
    if (handle == null) return;
    var id = handle.trim().toUpperCase();
    if (id.isNotEmpty && !RegExp(r'^[A-Z]{2}\d{7}$').hasMatch(id)) {
      try { id = (await ref.read(apiClientProvider).userByHandle(handle.trim().toLowerCase())).id; } catch (_) { if (context.mounted) toast(context, 'لم نجد هذا المستخدم', error: true); return; }
    }
    try {
      await ref.read(apiClientProvider).adminBizUpdate(b.id, ownerId: id.isEmpty ? null : id, clearOwner: id.isEmpty);
      invalidateAdmin(ref);
      invalidateBizAll(ref, b.id);
      if (context.mounted) toast(context, id.isEmpty ? 'أُزيل المالك' : 'عُيّن المالك');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
