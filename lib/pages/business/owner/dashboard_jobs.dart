import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_models.dart';
import '../../../api/jobs_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/platform.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show shortDate;
import 'job_actions.dart';
import 'job_candidates_page.dart';
import 'job_editor_page.dart';

/// تبويب التوظيف في لوحة الدائرة: الباقة، الأرقام العامة، وقائمة العروض الوظيفية بإجراءاتها.
/// يظهر للمالك والمدير ومسؤول التوظيف (Biz.canHire)؛ لغيرهم قفل توضيحي.
class JobsTab extends ConsumerWidget {
  final Biz biz;
  const JobsTab({super.key, required this.biz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!biz.canHire) {
      return const EmptyState(key: Key('jobs-locked'), icon: Icons.lock_outline_rounded, title: 'التوظيف للمالك والمدير ومسؤول التوظيف', subtitle: 'اطلب من مالك الدائرة إضافتك إلى الفريق بدور «توظيف» لتدير العروض والمرشحين.');
    }
    final board = ref.watch(jobsBoardProvider(biz.id));
    final overview = ref.watch(jobsOverviewProvider(biz.id)).valueOrNull;
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('job-new'),
        onPressed: () => openJobEditor(context, ref, biz.id, board: board.valueOrNull),
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        icon: const Icon(Icons.post_add_rounded),
        label: const Text('عرض جديد'),
      ),
      body: board.when(
        data: (b) => RefreshIndicator(
          onRefresh: () async => invalidateBizJobs(ref, biz.id),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            children: [
              if (!b.enabled)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
                  child: const Row(children: [Icon(Icons.pause_circle_outline_rounded, color: Joy.accent), SizedBox(width: 8), Expanded(child: Text('التوظيف موقوف مؤقتاً من إدارة المنصة؛ يمكنك تجهيز المسودات وسيُتاح النشر عند إعادة التفعيل', style: TextStyle(color: Joy.accent, fontWeight: FontWeight.w600, fontSize: 12.5)))]),
                ),
              JobPlanCard(plan: b.plan),
              const SizedBox(height: 10),
              _Overview(board: b, overview: overview),
              const SizedBox(height: 4),
              if (b.items.isEmpty)
                const EmptyState(icon: Icons.work_outline_rounded, title: 'لا عروض وظيفية بعد', subtitle: 'اكتب نقاطاً عن الوظيفة ويصوغ لك المحرك العرض كاملاً، ثم يصل لمن يطابقه من الباحثين عن عمل في مدينتك.')
              else
                SectionTitle('العروض · ${b.items.length}'),
              for (final j in b.items) _JobRow(bizId: biz.id, board: b, job: j),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => invalidateBizJobs(ref, biz.id)),
      ),
    );
  }
}

/// بطاقة الباقة: المجانية بعدّاد العروض النشطة، والمتقدمة بتاريخ انتهائها.
/// على iOS الأصلي لا نذكر الترقية أو الدفع (إرشادات أبل للخدمات الرقمية).
class JobPlanCard extends StatelessWidget {
  final JobPlan plan;
  const JobPlanCard({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final pro = plan.pro;
    final line = pro
        ? (plan.until == null ? 'عروض بلا حد وتصدير المرشحين' : 'الباقة المتقدمة حتى ${shortDate(plan.until!)}')
        : '${plan.active} من ${plan.freeActive} عروض نشطة';
    return JoyCard(
      key: const Key('jobs-plan'),
      color: pro ? Joy.primarySoft : null,
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: pro ? Joy.surface : Joy.primarySoft, shape: BoxShape.circle), child: Icon(pro ? Icons.workspace_premium_rounded : Icons.work_outline_rounded, color: Joy.primary, size: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pro ? 'الباقة المتقدمة' : 'الباقة المجانية', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(line, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          if (!pro && !isIosNative) const Text('للمزيد من العروض النشطة وتصدير المرشحين: الباقة المتقدمة عبر إدارة ناس لايف', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)),
        ])),
        if (!pro) Text('${plan.active}/${plan.freeActive}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: plan.atLimit ? Joy.accent : Joy.primary)),
      ]),
    );
  }
}

/// الأرقام العامة من /manage/jobs/stats، وعند غيابها تُحسب من اللوحة نفسها حتى لا تبقى فارغة.
class _Overview extends StatelessWidget {
  final JobsBoard board;
  final JobsOverview? overview;
  const _Overview({required this.board, this.overview});

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final items = board.items;
    final open = o?.open ?? items.where((j) => j.isOpen).length;
    final candidates = o?.candidates ?? items.fold<int>(0, (n, j) => n + (j.counts?.sent ?? 0));
    final answered = o?.answered ?? items.fold<int>(0, (n, j) => n + (j.counts?.answered ?? 0));
    final interviews = o?.upcomingInterviews ?? board.upcomingInterviews;
    final hired = o?.hired ?? items.fold<int>(0, (n, j) => n + (j.counts?.byStage['hired'] ?? 0));
    return Row(children: [
      _Stat('منشورة', '$open', Icons.campaign_outlined),
      _Stat('مرشحون', '$candidates', Icons.people_outline_rounded),
      _Stat('أجابوا', '$answered', Icons.question_answer_outlined),
      _Stat('مقابلات', '$interviews', Icons.event_available_outlined),
      _Stat('تعيينات', '$hired', Icons.task_alt_rounded),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(left: 6, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
          child: Column(children: [
            Icon(icon, size: 18, color: Joy.primary),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 10.5)),
          ]),
        ),
      );
}

/// صف عرض: الحالة، العنوان، المدينة والنوع، العدّادات، والمسؤول. الضغط يفتح المرشحين، والقائمة أو الضغط المطوّل الإجراءات.
class _JobRow extends ConsumerWidget {
  final String bizId;
  final JobsBoard board;
  final Job job;
  const _JobRow({required this.bizId, required this.board, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = job;
    final c = j.counts ?? const JobCounts();
    final meta = [if (j.city.isNotEmpty) j.city, j.typeLabel, if (j.department.isNotEmpty) j.department].join(' · ');
    final counts = 'أُرسل ${c.sent} · قبِل ${c.accepted} · أجاب ${c.answered}';
    final deadline = j.deadline == null ? null : 'حتى ${shortDate(j.deadline!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => showJobActionsSheet(context, ref, bizId, j, board: board),
        child: JoyCard(
          key: Key('job-${j.id}'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobCandidatesPage(bizId: bizId, jobId: j.id))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              JobStatusChip(j.status),
              const SizedBox(width: 8),
              Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))),
              if (deadline != null) Text(deadline, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
              PopupMenuButton<String>(
                key: Key('job-menu-${j.id}'),
                tooltip: 'إجراءات',
                onSelected: (v) => runJobAction(context, ref, bizId, j, v, board: board),
                itemBuilder: (_) => [
                  for (final a in jobActionsFor(j))
                    PopupMenuItem(value: a.id, child: Row(children: [Icon(a.icon, size: 18, color: a.danger ? Joy.danger : Joy.textMuted), const SizedBox(width: 8), Text(a.label, style: TextStyle(color: a.danger ? Joy.danger : Joy.text))])),
                ],
                icon: const Icon(Icons.more_horiz_rounded, color: Joy.textMuted),
              ),
            ]),
            const SizedBox(height: 4),
            Text(j.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(counts, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
              if (j.assignee != null) ...[
                Avatar(name: j.assignee!.nickname, url: j.assignee!.avatarUrl, size: 22),
                const SizedBox(width: 4),
                Text(j.assignee!.nickname, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
