import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/jobs_api.dart';
import '../../../api/jobs_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/platform.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show Stars, dayLabel;
import 'job_actions.dart';
import 'job_candidate_page.dart';
import 'job_stats_page.dart';

/// حالة بطاقة المرشح من جهة الدائرة (الغائب: «قبلت/أجبت» بصيغة المتكلم في matchStatuses).
const candidateStatuses = <String, String>{'sent': 'أُرسلت البطاقة', 'viewed': 'شاهد العرض', 'accepted': 'قبل العرض', 'declined': 'رفض', 'later': 'أجّل', 'answered': 'أجاب', 'withdrawn': 'انسحب', 'expired': 'انتهت البطاقة'};
String candidateStatusLabel(String s) => candidateStatuses[s] ?? s;

/// لوحة مرشحي عرض واحد: رأس بالعنوان والحالة والإجراءات، مرشّح المراحل، وصفوف المرشحين (المجهولون بدرجة وأسباب،
/// والمكشوفون بالاسم والملف). التصفية محلية لأن الخادم يعيد كل المرشحين (حتى 300) دفعة واحدة.
class JobCandidatesPage extends ConsumerStatefulWidget {
  final String bizId, jobId;
  const JobCandidatesPage({super.key, required this.bizId, required this.jobId});
  @override
  ConsumerState<JobCandidatesPage> createState() => _JobCandidatesPageState();
}

class _JobCandidatesPageState extends ConsumerState<JobCandidatesPage> {
  String stage = '';

  JobRef get _ref => (bizId: widget.bizId, jobId: widget.jobId);

  Future<void> _export() async {
    try {
      final csv = await ref.read(apiClientProvider).exportJobCandidates(widget.bizId, widget.jobId);
      if (mounted) await showCsvDialog(context, csv);
    } catch (e) {
      if (mounted) toast(context, jobErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(jobCandidatesProvider(_ref));
    final board = ref.watch(jobsBoardProvider(widget.bizId)).valueOrNull;
    final job = data.valueOrNull?.job;
    final pro = board?.plan.pro ?? false;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(job?.title ?? 'المرشحون', overflow: TextOverflow.ellipsis),
        actions: [
          if (job != null)
            PopupMenuButton<String>(
              key: const Key('cands-menu'),
              tooltip: 'إجراءات العرض',
              onSelected: (v) async {
                if (v == 'export') return _export();
                await runJobAction(context, ref, widget.bizId, job, v, board: board);
              },
              itemBuilder: (_) => [
                for (final a in jobActionsFor(job).where((a) => a.id != 'delete'))
                  PopupMenuItem(value: a.id, child: Row(children: [Icon(a.icon, size: 18, color: Joy.textMuted), const SizedBox(width: 8), Text(a.label)])),
                if (pro) const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download_outlined, size: 18, color: Joy.textMuted), SizedBox(width: 8), Text('تصدير CSV')])),
              ],
            ),
        ],
      ),
      body: data.when(
        data: (d) {
          final items = stage.isEmpty ? d.items : d.items.where((c) => c.stage == stage).toList();
          return RefreshIndicator(
            onRefresh: () async => invalidateBizJobs(ref, widget.bizId),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              if (d.job != null) _Header(job: d.job!, counts: d.counts, pro: pro, onStats: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobStatsPage(bizId: widget.bizId, jobId: widget.jobId, pro: pro))), onExport: _export),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _StageChip(id: '', label: 'الكل', n: d.items.length, selected: stage.isEmpty, onTap: () => setState(() => stage = '')),
                  for (final s in d.stages) _StageChip(id: s.id, label: s.label, n: s.n, selected: stage == s.id, onTap: () => setState(() => stage = s.id)),
                ]),
              ),
              const SizedBox(height: 10),
              if (d.items.isEmpty)
                const EmptyState(icon: Icons.people_outline_rounded, title: 'لا مرشحين بعد', subtitle: 'تصل بطاقات العرض تلقائياً لمن يطابقه من الباحثين عن عمل، ويظهر هنا من يشاهدها أو يقبلها.')
              else if (items.isEmpty)
                const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'لا مرشحين في هذه المرحلة'),
              for (final c in items) CandidateRow(candidate: c, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobCandidatePage(bizId: widget.bizId, jobId: widget.jobId, matchId: c.id)))),
            ]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobCandidatesProvider(_ref))),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Job job;
  final JobCounts counts;
  final bool pro;
  final VoidCallback onStats, onExport;
  const _Header({required this.job, required this.counts, required this.pro, required this.onStats, required this.onExport});

  @override
  Widget build(BuildContext context) => JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            JobStatusChip(job.status),
            const SizedBox(width: 8),
            Expanded(child: Text([if (job.city.isNotEmpty) job.city, job.typeLabel].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
            TextButton.icon(key: const Key('cands-stats'), onPressed: onStats, icon: const Icon(Icons.bar_chart_rounded, size: 18), label: const Text('الإحصاءات')),
            if (pro) IconButton(key: const Key('cands-export'), tooltip: 'تصدير CSV', onPressed: onExport, icon: const Icon(Icons.download_outlined, color: Joy.primary)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _Num('أُرسل', counts.sent),
            _Num('شاهد', counts.viewed),
            _Num('قبِل', counts.accepted),
            _Num('أجاب', counts.answered),
            _Num('رفض', counts.declined),
          ]),
          if (!pro && !isIosNative) const Padding(padding: EdgeInsets.only(top: 6), child: Text('تصدير المرشحين إلى CSV متاح في الباقة المتقدمة', style: TextStyle(color: Joy.textMuted, fontSize: 11.5))),
        ]),
      );
}

class _Num extends StatelessWidget {
  final String label;
  final int n;
  const _Num(this.label, this.n);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 11))]));
}

class _StageChip extends StatelessWidget {
  final String id, label;
  final int n;
  final bool selected;
  final VoidCallback onTap;
  const _StageChip({required this.id, required this.label, required this.n, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
          key: Key('stage-filter-${id.isEmpty ? 'all' : id}'),
          label: Text('$label $n', style: TextStyle(color: selected ? Joy.primaryOn : Joy.text, fontSize: 12.5)),
          selected: selected,
          showCheckmark: false,
          selectedColor: Joy.primary,
          onSelected: (_) => onTap(),
        ),
      );
}

/// صف مرشح: مجهول («مرشح #N» بدرجة وأسباب) أو مكشوف (اسم وصورة ومدينة وخبرة وتقييم ومسؤول ومقابلة).
class CandidateRow extends StatelessWidget {
  final JobCandidate candidate;
  final VoidCallback? onTap;
  const CandidateRow({super.key, required this.candidate, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final p = c.profile;
    final iv = c.nextInterview;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: JoyCard(
        key: Key('cand-${c.id}'),
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.anonymous)
            Container(width: 44, height: 44, decoration: const BoxDecoration(color: Joy.surface2, shape: BoxShape.circle), child: const Icon(Icons.person_outline_rounded, color: Joy.textMuted))
          else
            Avatar(name: c.user?.nickname ?? c.label, url: c.user?.avatarUrl, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              ScoreBadge(c.scorePct),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(c.stageLabel.isNotEmpty ? c.stageLabel : jobStageLabel(c.stage), style: const TextStyle(color: Joy.primary, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 3),
            if (c.anonymous) ...[
              Text('${candidateStatusLabel(c.status)} · ${timeAgo(c.viewedAt ?? c.sentAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              if (c.reasons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: ReasonChips(c.reasons)),
            ] else ...[
              if (p != null) Text([if (p.city.isNotEmpty) p.city, 'خبرة ${p.experienceYears} ${p.experienceYears == 1 ? 'سنة' : 'سنوات'}', if (p.titles.isNotEmpty) p.titles.first].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              Text('أجاب ${timeAgo(c.answeredAt)}${c.source == 'apply' ? ' · تقدّم بنفسه' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (c.rating != null) Stars(rating: c.rating, count: c.notesCount),
                if (c.assignee != null) Text('المسؤول: ${c.assignee!.nickname}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                if (iv?.at != null) Text('مقابلة ${dayLabel(iv!.at!)} ${clockOf(iv.at)}', style: const TextStyle(color: Joy.primary, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}

/// درجة المطابقة كنسبة مئوية بلون يدل على قوتها.
class ScoreBadge extends StatelessWidget {
  final int pct;
  const ScoreBadge(this.pct, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = pct >= 75 ? Joy.success : pct >= 45 ? Joy.primary : Joy.textMuted;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text('$pct%', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)));
  }
}

/// أسباب المطابقة كرقائق صغيرة.
class ReasonChips extends StatelessWidget {
  final List<String> reasons;
  const ReasonChips(this.reasons, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4, children: [
        for (final r in reasons) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(r, style: const TextStyle(fontSize: 11, color: Joy.text))),
      ]);
}
