import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';
import 'admin_users.dart';

class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});
  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
  bool all = false;
  @override
  Widget build(BuildContext context) {
    final rep = ref.watch(adminReportsProvider(all));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(children: [
          for (final (v, l) in [(false, 'المفتوحة'), (true, 'الكل')])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(label: Text(l, style: TextStyle(color: all == v ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: all == v, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => all = v))),
          Expanded(child: Text(rep.valueOrNull?.blocks != null ? '${rep.valueOrNull!.blocks} حظر بين المستخدمين' : '', textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        ]),
      ),
      Expanded(
        child: rep.when(
          data: (r) {
            if (!r.available) return const EmptyState(icon: Icons.flag_outlined, title: 'جدول البلاغات غير متاح', subtitle: 'لم نجد جدول بلاغات في قاعدة بيانات الخادم الأساسي. البلاغات من التطبيق تُرسل إلى الخادم الأساسي وستظهر هنا فور توفر الجدول.');
            if (r.items.isEmpty) return EmptyState(icon: Icons.flag_outlined, title: all ? 'لا بلاغات' : 'لا بلاغات مفتوحة', subtitle: 'كل البلاغات عولجت.');
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [for (final it in r.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ReportCard(r: it))]);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminReportsProvider)),
        ),
      ),
    ]);
  }
}

class _ReportCard extends ConsumerWidget {
  final AdminReport r;
  const _ReportCard({required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = r.action != null;
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (r.target != null) ProfileAvatar(person: r.target!, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('بلاغ ضد ${r.target?.nickname.isNotEmpty == true ? r.target!.nickname : r.targetId ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text('من ${r.reporter?.nickname.isNotEmpty == true ? r.reporter!.nickname : r.reporterId ?? '—'} · ${timeAgo(r.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          if (done) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(switch (r.action!.action) { 'warn' => 'تحذير', 'suspend' => 'إيقاف', _ => 'تجاهل' }, style: const TextStyle(fontSize: 11, color: Joy.textMuted, fontWeight: FontWeight.w600))),
        ]),
        if (r.reason != null || r.text != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text([if (r.reason != null) r.reason!, if (r.text != null && r.text!.isNotEmpty) r.text!].join(': '), style: const TextStyle(height: 1.5))),
        if (done && r.action!.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظة الإدارة: ${r.action!.note}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (r.targetId != null) OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: r.targetId!))), icon: const Icon(Icons.person_search_outlined, size: 18), label: const Text('ملف المُبلَّغ عنه')),
          if (!done) ...[
            FilledButton.tonalIcon(onPressed: () => _act(context, ref, 'ignore'), icon: const Icon(Icons.done_rounded, size: 18), label: const Text('تجاهل')),
            FilledButton.tonalIcon(onPressed: () => _act(context, ref, 'warn'), icon: const Icon(Icons.warning_amber_rounded, size: 18), label: const Text('تحذير')),
            FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => _act(context, ref, 'suspend'), icon: const Icon(Icons.block_rounded, size: 18), label: const Text('إيقاف الحساب')),
          ],
        ]),
      ]),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final note = await askText(context, title: switch (action) { 'warn' => 'تحذير المستخدم', 'suspend' => 'إيقاف الحساب', _ => 'تجاهل البلاغ' }, hint: 'ملاحظة تُحفظ في السجل', confirm: 'تأكيد');
    if (note == null || r.id == null) return;
    try {
      await ref.read(apiClientProvider).adminReportAction(r.id!, action: action, note: note.trim(), targetId: r.targetId);
      invalidateAdmin(ref);
      if (context.mounted) toast(context, 'سُجّل الإجراء');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
