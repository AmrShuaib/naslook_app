import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/jobs_api.dart';
import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness;
import 'admin_shell.dart';

/// قسم «التوظيف» في لوحة الإدارة: الإجماليات، تصفية بالحالة، وقائمة العروض مع الموافقة والإغلاق وتغيير الباقة.
class AdminJobsPage extends ConsumerStatefulWidget {
  const AdminJobsPage({super.key});
  @override
  ConsumerState<AdminJobsPage> createState() => _AdminJobsPageState();
}

class _AdminJobsPageState extends ConsumerState<AdminJobsPage> {
  String status = '';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(adminJobsProvider(status));
    return data.when(
      skipLoadingOnReload: true,
      data: (d) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminJobsProvider),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          if (!d.jobsEnabled)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [Icon(Icons.pause_circle_outline_rounded, color: Joy.accent), SizedBox(width: 8), Expanded(child: Text('التوظيف مطفأ من الإعدادات؛ لا تُنشر وظائف ولا تُرسل بطاقات', key: Key('admin-jobs-disabled'), style: TextStyle(color: Joy.accent, fontWeight: FontWeight.w600, fontSize: 13)))]),
            ),
          Row(children: [
            _Stat('مفتوحة', d.open, Icons.work_outline_rounded, Joy.primary, key: const Key('admin-jobs-open')),
            const SizedBox(width: 8),
            _Stat('بانتظار الموافقة', d.pending, Icons.hourglass_top_rounded, Joy.accent, key: const Key('admin-jobs-pending')),
            const SizedBox(width: 8),
            _Stat('باحثون', d.seekers, Icons.badge_outlined, Joy.sunText),
            const SizedBox(width: 8),
            _Stat('تعيينات', d.hired, Icons.how_to_reg_outlined, Joy.success),
          ]),
          const SizedBox(height: 6),
          Text('الباقة المجانية: ${d.jobsFreeActive} عروض نشطة · ${d.jobsWeeklyCap} بطاقات أسبوعياً للباحث · حد المطابقة ${(d.jobsMinScore * 100).round()}٪${d.jobsRequireApproval ? ' · النشر بموافقة الإدارة' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in [('', 'الكل'), ...jobStatuses.entries.map((e) => (e.key, e.value))])
              ChoiceChip(key: Key('admin-jobs-filter-${k.isEmpty ? 'all' : k}'), label: Text(l, style: TextStyle(color: status == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: status == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => status = k)),
          ]),
          const SizedBox(height: 10),
          if (d.items.isEmpty) const EmptyState(icon: Icons.work_outline_rounded, title: 'لا وظائف في هذه الحالة'),
          for (final j in d.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _JobCard(job: j, onChanged: () => ref.invalidate(adminJobsProvider))),
        ]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminJobsProvider(status))),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int n;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.n, this.icon, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Expanded(
        child: JoyCard(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text('$n', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
          ]),
        ),
      );
}

/// بطاقة عرض في الإدارة: الدائرة والمسمّى والحالة والعدّادات والباقة، مع الإجراءات.
class _JobCard extends ConsumerStatefulWidget {
  final Job job;
  final VoidCallback onChanged;
  const _JobCard({required this.job, required this.onChanged});
  @override
  ConsumerState<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<_JobCard> {
  bool busy = false;

  Future<void> _run(Future<void> Function() fn, String ok) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
      widget.onChanged();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _approve() => _run(() => ref.read(apiClientProvider).adminApproveJob(widget.job.id), 'نُشر العرض وأُرسلت بطاقاته للمطابقين');

  Future<void> _close() async {
    final reason = await askText(context, title: 'إغلاق «${widget.job.title}»', hint: 'سبب الإغلاق (يصل إلى فريق الدائرة)', confirm: 'إغلاق', maxLines: 2);
    if (reason == null) return;
    await _run(() => ref.read(apiClientProvider).adminCloseJob(widget.job.id, reason: reason.trim()), 'أُغلق العرض');
  }

  /// حوار الباقة: مجانية أو متقدمة مع عدد الأشهر.
  Future<void> _plan() async {
    var plan = widget.job.plan == 'pro' ? 'pro' : 'free';
    final months = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('باقة التوظيف · ${widget.job.bizName ?? widget.job.bizId}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final (k, l) in [('free', 'مجانية'), ('pro', 'متقدمة')])
                ChoiceChip(key: Key('admin-job-plan-$k'), label: Text(l, style: TextStyle(color: plan == k ? Joy.primaryOn : Joy.text)), selected: plan == k, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setS(() => plan = k)),
            ]),
            const SizedBox(height: 8),
            Text(plan == 'pro' ? 'عروض بلا حد وتصدير المرشحين حتى نهاية المدة' : 'عدد محدود من العروض النشطة (من الإعدادات)', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            if (plan == 'pro') ...[
              const SizedBox(height: 8),
              TextField(key: const Key('admin-job-plan-months'), controller: months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الأشهر (1–36)')),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')),
            FilledButton(key: const Key('admin-job-plan-save'), onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final m = (int.tryParse(months.text.trim()) ?? 1).clamp(1, 36);
    await _run(() => ref.read(apiClientProvider).adminSetJobPlan(widget.job.bizId, plan: plan, months: m), plan == 'pro' ? 'فُعّلت الباقة المتقدمة $m ${m == 1 ? 'شهراً' : 'أشهر'}' : 'أُعيدت الدائرة إلى الباقة المجانية');
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final c = j.counts;
    final (pillBg, pillFg) = switch (j.status) {
      'open' => (Joy.primarySoft, Joy.primary),
      'pending' => (Joy.accentSoft, Joy.accent),
      'filled' => (const Color(0xFFE3F5EA), Joy.success),
      _ => (Joy.surface2, Joy.textMuted),
    };
    return JoyCard(
      key: Key('admin-job-${j.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.work_outline_rounded, color: Joy.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(j.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)), child: Text(j.statusLabel, style: TextStyle(color: pillFg, fontSize: 10.5, fontWeight: FontWeight.w700))),
              if (j.plan == 'pro') Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(999)), child: const Text('متقدمة', style: TextStyle(color: Joy.sunText, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            Text('${j.bizName ?? j.bizId} · ${j.typeLabel}${j.city.isNotEmpty ? ' · ${j.city}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text('${c?.sent ?? 0} بطاقة · ${c?.accepted ?? 0} قبول · ${c?.answered ?? 0} أجاب · ${c?.byStage['hired'] ?? 0} تعيين · ${j.views} مشاهدة${j.updatedAt != null ? ' · ${timeAgo(j.updatedAt)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (j.status == 'pending') FilledButton.icon(key: Key('admin-job-approve-${j.id}'), onPressed: busy ? null : _approve, icon: const Icon(Icons.check_rounded, size: 18), label: const Text('موافقة')),
          if (j.status != 'closed' && j.status != 'filled') FilledButton.tonalIcon(key: Key('admin-job-close-${j.id}'), onPressed: busy ? null : _close, icon: const Icon(Icons.block_rounded, size: 18), label: const Text('إغلاق')),
          FilledButton.tonalIcon(key: Key('admin-job-plan-${j.id}'), onPressed: busy ? null : _plan, icon: const Icon(Icons.workspace_premium_outlined, size: 18), label: const Text('باقة')),
          OutlinedButton.icon(onPressed: () => openBusiness(context, j.bizId), icon: const Icon(Icons.storefront_outlined, size: 18), label: const Text('الدائرة')),
        ]),
      ]),
    );
  }
}
