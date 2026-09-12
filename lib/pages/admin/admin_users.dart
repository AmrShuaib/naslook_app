import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness;
import '../wallet/wallet_page.dart' show TxRow;
import 'admin_shell.dart';

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});
  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  String q = '';
  String? filter;
  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider((q: q, filter: filter)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: TextField(onSubmitted: (v) => setState(() => q = v.trim()), onChanged: (v) { if (v.trim().isEmpty && q.isNotEmpty) setState(() => q = ''); }, decoration: const InputDecoration(hintText: 'ابحث بالنك نيم أو المعرّف SA…', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted), isDense: true)),
      ),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        for (final (k, l) in [(null, 'الأحدث'), ('suspended', 'الموقوفون'), ('admins', 'المديرون')])
          Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(label: Text(l, style: TextStyle(color: filter == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: filter == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => filter = k))),
      ])),
      Expanded(
        child: users.when(
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.person_search_outlined, title: 'لا نتائج')
              : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
                  JoyCard(padding: EdgeInsets.zero, child: Column(children: [
                    for (final (i, u) in list.indexed)
                      ListRow(
                        leading: ProfileAvatar(person: u.person, size: 44),
                        title: Row(children: [
                          Flexible(child: Text(u.nickname.isEmpty ? u.id : u.nickname, overflow: TextOverflow.ellipsis)),
                          if (u.isAdmin) _badge('مدير', Joy.primary, Joy.primarySoft),
                          if (u.suspended) _badge('موقوف', Joy.danger, Joy.accentSoft),
                        ]),
                        subtitle: Text('${u.id} · انضم ${timeAgo(u.createdAt)}'),
                        trailing: Text(u.balance == null ? '' : money(u.balance!), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.text, fontSize: 13)),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: u.id))),
                        divider: i < list.length - 1,
                      ),
                  ])),
                ]),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminUsersProvider)),
        ),
      ),
    ]);
  }
}

Widget _badge(String t, Color fg, Color bg) => Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)));

/// صفحة مستخدم في الإدارة: الملف والرصيد والحركات والإجراءات.
class AdminUserPage extends ConsumerWidget {
  final String id;
  const AdminUserPage({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(adminUserProvider(id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(d.valueOrNull?.user.nickname ?? id)),
      body: d.when(
        data: (x) {
          final u = x.user;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
            JoyCard(child: Row(children: [
              ProfileAvatar(person: u.person, size: 64),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(u.nickname.isEmpty ? u.id : u.nickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))), if (u.isAdmin) _badge('مدير', Joy.primary, Joy.primarySoft), if (u.suspended) _badge('موقوف', Joy.danger, Joy.accentSoft)]),
                Text('${u.id} · انضم ${timeAgo(u.createdAt)}${u.lastSeen != null ? ' · آخر ظهور ${timeAgo(u.lastSeen)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                if (u.bio.isNotEmpty) Text(u.bio, style: const TextStyle(fontSize: 13)),
                if (u.suspended && u.flagNote.isNotEmpty) Text('سبب الإيقاف: ${u.flagNote}', style: const TextStyle(color: Joy.danger, fontSize: 12.5)),
              ])),
            ])),
            const SizedBox(height: 8),
            TileGrid(children: [
              StatTile(label: 'الرصيد', value: money(u.balance ?? 0), icon: Icons.account_balance_wallet_outlined, color: Joy.success),
              StatTile(label: 'النقاط', value: '${x.points}', icon: Icons.stars_rounded, color: Joy.warning),
              StatTile(label: 'طلبات الدوائر', value: '${x.ordersCount}', icon: Icons.shopping_bag_outlined, color: Joy.accent, hint: money(x.ordersTotal)),
              StatTile(label: 'بلاغات ضده', value: '${x.reportsAbout.length}', icon: Icons.flag_outlined, color: x.reportsAbout.isEmpty ? Joy.textMuted : Joy.danger),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _credit(context, ref, u, true), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('إضافة رصيد')),
              OutlinedButton.icon(onPressed: () => _credit(context, ref, u, false), icon: const Icon(Icons.remove_rounded, size: 18), label: const Text('خصم رصيد')),
              OutlinedButton.icon(
                onPressed: () => _suspend(context, ref, u),
                icon: Icon(u.suspended ? Icons.check_circle_outline_rounded : Icons.block_rounded, size: 18, color: u.suspended ? Joy.success : Joy.danger),
                label: Text(u.suspended ? 'إعادة تفعيل الحساب' : 'إيقاف الحساب', style: TextStyle(color: u.suspended ? Joy.success : Joy.danger)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(u.isAdmin ? 'سحب صلاحية المدير؟' : 'ترقية إلى مدير نظام؟'), content: Text(u.isAdmin ? 'لن يستطيع ${u.nickname} فتح لوحة الإدارة.' : 'سيستطيع ${u.nickname} فتح لوحة الإدارة وتنفيذ كل الإجراءات.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد'))]));
                  if (ok != true) return;
                  try {
                    await ref.read(apiClientProvider).adminGrant(u.id, grant: !u.isAdmin);
                    invalidateAdmin(ref);
                    if (context.mounted) toast(context, u.isAdmin ? 'سُحبت الصلاحية' : 'أصبح مديراً');
                  } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
                },
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: Text(u.isAdmin ? 'سحب صلاحية المدير' : 'ترقية إلى مدير'),
              ),
              OutlinedButton.icon(onPressed: () => openProfile(context, u.person), icon: const Icon(Icons.person_outline_rounded, size: 18), label: const Text('الملف العام')),
            ]),
            if (x.circles.isNotEmpty) ...[
              const SectionTitle('دوائره التجارية'),
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, c) in x.circles.indexed) ListRow(leading: const Icon(Icons.storefront_outlined, color: Joy.primary), title: Text(c.name), subtitle: Text('${c.category} · ${c.active ? 'منشورة' : 'موقوفة'}'), onTap: () => openBusiness(context, c.id), divider: i < x.circles.length - 1)])),
            ],
            if (x.reportsAbout.isNotEmpty) ...[
              const SectionTitle('بلاغات ضده'),
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, r) in x.reportsAbout.indexed) ListRow(leading: const Icon(Icons.flag_outlined, color: Joy.danger), title: Text(r.reason ?? 'بلاغ'), subtitle: Text('${r.text ?? ''} · من ${r.reporterId ?? ''} · ${timeAgo(r.createdAt)}'), divider: i < x.reportsAbout.length - 1)])),
            ],
            const SectionTitle('آخر الحركات'),
            if (x.transactions.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا حركات'),
            if (x.transactions.isNotEmpty) JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, t) in x.transactions.indexed) TxRow(t, last: i == x.transactions.length - 1)])),
            if (x.actions.isNotEmpty) ...[
              const SectionTitle('إجراءات الإدارة عليه'),
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, a) in x.actions.indexed) ListRow(leading: const Icon(Icons.history_rounded, color: Joy.textMuted), title: Text(a.label), subtitle: Text('${a.adminId} · ${timeAgo(a.createdAt)}'), divider: i < x.actions.length - 1)])),
            ],
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminUserProvider(id))),
      ),
    );
  }

  Future<void> _credit(BuildContext context, WidgetRef ref, AdminUser u, bool add) async {
    final amount = TextEditingController(), note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(add ? 'إضافة رصيد إلى ${u.nickname}' : 'خصم رصيد من ${u.nickname}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ بالريال')),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة تظهر للمستخدم')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(add ? 'إضافة' : 'خصم'))],
      ),
    );
    if (ok != true) return;
    final h = parseSar(amount.text);
    if (h <= 0) { if (context.mounted) toast(context, 'اكتب مبلغاً صحيحاً', error: true); return; }
    try {
      final bal = await ref.read(apiClientProvider).adminCredit(u.id, add ? h : -h, note: note.text.trim());
      invalidateAdmin(ref);
      if (context.mounted) toast(context, 'الرصيد الآن ${money(bal)}');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _suspend(BuildContext context, WidgetRef ref, AdminUser u) async {
    final note = TextEditingController(text: u.flagNote);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(u.suspended ? 'إعادة تفعيل ${u.nickname}؟' : 'إيقاف ${u.nickname}؟'),
        content: u.suspended ? const Text('سيستطيع الشراء والحجز والتحويل من جديد.') : Column(mainAxisSize: MainAxisSize.min, children: [const Text('يُمنع من الشراء والحجز والتحويل عبر المنصة. تبقى بياناته محفوظة.'), const SizedBox(height: 10), TextField(controller: note, decoration: const InputDecoration(labelText: 'السبب'))]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')), FilledButton(style: u.suspended ? null : FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: Text(u.suspended ? 'تفعيل' : 'إيقاف'))],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).adminSuspend(u.id, suspended: !u.suspended, note: note.text.trim());
      invalidateAdmin(ref);
      if (context.mounted) toast(context, u.suspended ? 'أُعيد تفعيل الحساب' : 'أُوقف الحساب');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
