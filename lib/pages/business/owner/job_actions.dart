import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/client.dart';
import '../../../api/jobs_api.dart';
import '../../../api/jobs_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/widgets.dart';
import 'business_editor.dart' show ownerErrText;
import 'job_editor_page.dart';
import 'job_stats_page.dart';

/// إجراءات العرض الوظيفي المشتركة بين تبويب التوظيف ولوحة المرشحين: القائمة حسب الحالة وتنفيذها مع رسائل موحّدة.
typedef JobAction = ({String id, String label, IconData icon, bool danger});

List<JobAction> jobActionsFor(Job job) {
  final s = job.status;
  return [
    if (s == 'draft' || s == 'paused' || s == 'closed' || s == 'filled') (id: 'publish', label: s == 'paused' ? 'استئناف النشر' : s == 'draft' ? 'نشر الآن' : 'إعادة النشر', icon: Icons.rocket_launch_outlined, danger: false),
    if (s == 'open') (id: 'pause', label: 'إيقاف مؤقت', icon: Icons.pause_circle_outline_rounded, danger: false),
    if (s == 'open' || s == 'paused' || s == 'pending') (id: 'filled', label: 'شُغلت الوظيفة', icon: Icons.task_alt_rounded, danger: false),
    if (s == 'open' || s == 'paused' || s == 'pending') (id: 'close', label: 'إغلاق العرض', icon: Icons.stop_circle_outlined, danger: false),
    (id: 'edit', label: 'تعديل', icon: Icons.edit_outlined, danger: false),
    (id: 'duplicate', label: 'تكرار كمسودة', icon: Icons.copy_outlined, danger: false),
    (id: 'stats', label: 'الإحصاءات', icon: Icons.bar_chart_rounded, danger: false),
    if (s == 'draft') (id: 'delete', label: 'حذف المسودة', icon: Icons.delete_outline_rounded, danger: true),
  ];
}

/// نص النجاح بعد النشر: عدد من وصلتهم البطاقة، أو انتظار الموافقة إن كانت الإدارة تراجع العروض.
String jobPublishedText(Job job) {
  if (job.status == 'pending') return 'أُرسل العرض للمراجعة وسيُنشر بعد موافقة الإدارة';
  final m = job.matched;
  if (m == null) return 'نُشر العرض';
  if (m.sent == 0) return 'نُشر العرض ولم نجد مرشحاً مطابقاً بعد؛ سنرسله لمن يطابقه لاحقاً';
  return 'وصل العرض إلى ${m.sent} مرشحاً';
}

/// رسالة خطأ التوظيف: الرمز مترجم في العميل، ونضيف توضيحاً عند حد الباقة.
String jobErrText(Object e) {
  if (e is ApiException && e.body?['error'] == 'plan-limit') return e.message;
  return ownerErrText(e);
}

/// ينفّذ إجراءً على عرض ويعيد true عند النجاح (بعد تحديث المزوّدات). يفتح المحرر أو الإحصاءات عند الحاجة.
Future<bool> runJobAction(BuildContext context, WidgetRef ref, String bizId, Job job, String action, {JobsBoard? board}) async {
  final api = ref.read(apiClientProvider);
  try {
    switch (action) {
      case 'edit':
        await openJobEditor(context, ref, bizId, board: board, initial: job);
        return true;
      case 'stats':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobStatsPage(bizId: bizId, jobId: job.id, pro: board?.plan.pro ?? false)));
        return true;
      case 'publish':
        final j = await api.publishJob(bizId, job.id);
        if (context.mounted) toast(context, jobPublishedText(j));
      case 'pause':
        await api.pauseJob(bizId, job.id);
        if (context.mounted) toast(context, 'أُوقف العرض مؤقتاً؛ لا تصل بطاقات جديدة حتى تستأنفه');
      case 'close':
      case 'filled':
        final filled = action == 'filled';
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(filled ? 'شُغلت الوظيفة؟' : 'إغلاق العرض؟'),
            content: Text(filled ? 'يُغلق العرض ويُعلَّم بأنه شُغل، وتنتهي البطاقات المعلّقة لدى المرشحين.' : 'يتوقف العرض وتنتهي البطاقات المعلّقة لدى المرشحين. يمكنك إعادة نشره لاحقاً.'),
            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(filled ? 'شُغلت' : 'إغلاق'))],
          ),
        );
        if (ok != true) return false;
        await api.closeJob(bizId, job.id, filled: filled);
        if (context.mounted) toast(context, filled ? 'مبروك، شُغلت الوظيفة' : 'أُغلق العرض');
      case 'duplicate':
        final j = await api.duplicateJob(bizId, job.id);
        if (context.mounted) toast(context, 'كُرّر العرض «${j.title}» كمسودة');
      case 'delete':
        final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('حذف المسودة؟'), content: const Text('لا يمكن التراجع عن حذف المسودة.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))]));
        if (ok != true) return false;
        await api.deleteJob(bizId, job.id);
        if (context.mounted) toast(context, 'حُذفت المسودة');
      default:
        return false;
    }
    invalidateBizJobs(ref, bizId);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, jobErrText(e), error: true);
    return false;
  }
}

/// ورقة إجراءات العرض (للضغط المطوّل أو زر القائمة في الجوال).
Future<void> showJobActionsSheet(BuildContext context, WidgetRef ref, String bizId, Job job, {JobsBoard? board}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(job.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        for (final a in jobActionsFor(job))
          ListTile(key: Key('job-sheet-${a.id}'), leading: Icon(a.icon, color: a.danger ? Joy.danger : Joy.primary), title: Text(a.label, style: TextStyle(color: a.danger ? Joy.danger : Joy.text)), onTap: () => Navigator.pop(ctx, a.id)),
      ]),
    ),
  );
  if (action != null && context.mounted) await runJobAction(context, ref, bizId, job, action, board: board);
}

/// شارة الحالة (منشور/مسودة/موقوف…) بلون يدل عليها.
class JobStatusChip extends StatelessWidget {
  final String status;
  const JobStatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = switch (status) { 'open' => Joy.success, 'pending' => Joy.warning, 'paused' => Joy.accent, 'filled' => Joy.primary, _ => Joy.textMuted };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(jobStatusLabel(status), style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)));
  }
}
