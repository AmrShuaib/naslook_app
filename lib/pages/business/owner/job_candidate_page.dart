import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/jobs_api.dart';
import '../../../api/jobs_models.dart';
import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import '../../chat/chat_thread_page.dart' show ChatThreadPage;
import '../business_page.dart' show dayLabel;
import 'job_actions.dart';
import 'job_candidates_page.dart' show ScoreBadge, ReasonChips, candidateStatusLabel;

/// بديل للاختبارات: يستقبل رابط السيرة الذاتية بدل فتحه في المتصفح.
Future<void> Function(Uri uri)? openCvOverride;

/// صفحة مرشح واحد: مجهول (درجة وأسباب وسجل) أو مكشوف (الملف والإجابات والمرحلة والمسؤول والملاحظات والمقابلات والمراسلة).
class JobCandidatePage extends ConsumerStatefulWidget {
  final String bizId, jobId, matchId;
  const JobCandidatePage({super.key, required this.bizId, required this.jobId, required this.matchId});
  @override
  ConsumerState<JobCandidatePage> createState() => _JobCandidatePageState();
}

class _JobCandidatePageState extends ConsumerState<JobCandidatePage> {
  final note = TextEditingController();
  int? noteRating;
  bool busy = false;

  JobMatchRef get _ref => (bizId: widget.bizId, jobId: widget.jobId, matchId: widget.matchId);

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    setState(() => busy = true);
    try {
      await f();
      invalidateBizJobs(ref, widget.bizId);
      if (ok != null && mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, jobErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setStage(String s) => _run(() => ref.read(apiClientProvider).updateJobCandidate(widget.bizId, widget.jobId, widget.matchId, stage: s), ok: 'المرحلة: ${jobStageLabel(s)}');
  Future<void> _setAssignee(String? id) => _run(() => ref.read(apiClientProvider).updateJobCandidate(widget.bizId, widget.jobId, widget.matchId, assigneeId: id ?? ''), ok: 'حُدّث المسؤول');

  Future<void> _addNote() async {
    final t = note.text.trim();
    if (t.isEmpty && noteRating == null) {
      toast(context, 'اكتب ملاحظة أو اختر تقييماً', error: true);
      return;
    }
    await _run(() async {
      await ref.read(apiClientProvider).addJobNote(widget.bizId, widget.jobId, widget.matchId, text: t, rating: noteRating);
      note.clear();
      noteRating = null;
    }, ok: 'أُضيفت الملاحظة');
  }

  Future<void> _schedule() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)), initialDate: now.add(const Duration(days: 1)), helpText: 'تاريخ المقابلة');
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0), helpText: 'وقت المقابلة');
    if (tm == null || !mounted) return;
    final at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
    var mode = 'onsite';
    final place = TextEditingController(), memo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('تحديد مقابلة'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dayLabel(at)} · ${clockOf(at)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final e in JobInterview.modes.entries)
                ChoiceChip(key: Key('iv-mode-${e.key}'), label: Text(e.value, style: TextStyle(color: mode == e.key ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: mode == e.key, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setS(() => mode = e.key)),
            ]),
            const SizedBox(height: 10),
            TextField(key: const Key('iv-place'), controller: place, decoration: InputDecoration(labelText: mode == 'onsite' ? 'المكان' : 'الرابط أو الرقم', isDense: true)),
            const SizedBox(height: 8),
            TextField(key: const Key('iv-note'), controller: memo, decoration: const InputDecoration(labelText: 'ملاحظة للمرشح (اختياري)', isDense: true)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('iv-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('تحديد'))],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => ref.read(apiClientProvider).scheduleJobInterview(widget.bizId, widget.jobId, widget.matchId, at: at, mode: mode, place: place.text.trim(), note: memo.text.trim()), ok: 'حُدّدت المقابلة وأُخطر المرشح');
  }

  Future<void> _interviewStatus(JobInterview iv, String status) => _run(() => ref.read(apiClientProvider).updateJobInterview(widget.bizId, widget.jobId, widget.matchId, iv.id, status), ok: status == 'done' ? 'سُجّلت المقابلة كمنجزة' : 'أُلغيت المقابلة وأُخطر المرشح');

  Future<void> _openCv(String url) async {
    final u = Uri.tryParse(url);
    if (u == null) return;
    if (openCvOverride != null) return openCvOverride!(u);
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(jobCandidateProvider(_ref));
    final board = ref.watch(jobsBoardProvider(widget.bizId)).valueOrNull;
    final myId = ref.watch(appStateProvider.select((s) => s.session?.user.id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(data.valueOrNull?.name ?? 'المرشح')),
      body: data.when(
        data: (c) {
          final p = c.profile;
          final job = board?.items.where((j) => j.id == widget.jobId).firstOrNull;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(jobCandidateProvider(_ref)),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              // ---- الرأس
              JoyCard(child: Row(children: [
                if (c.anonymous)
                  Container(width: 52, height: 52, decoration: const BoxDecoration(color: Joy.surface2, shape: BoxShape.circle), child: const Icon(Icons.person_outline_rounded, color: Joy.textMuted, size: 28))
                else
                  ProfileAvatar(person: c.user!, size: 52),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  if (job != null) Text(job.title, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ScoreBadge(c.scorePct),
                    Text(c.stageLabel.isNotEmpty ? c.stageLabel : jobStageLabel(c.stage), style: const TextStyle(color: Joy.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    Text('· ${candidateStatusLabel(c.status)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    Text(c.source == 'apply' ? '· تقدّم بنفسه' : '· رشّحه النظام', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                  ]),
                ])),
                if (!c.anonymous && c.user != null)
                  IconButton(key: const Key('cand-chat'), tooltip: 'مراسلة', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: c.user!))), icon: const Icon(Icons.chat_bubble_outline_rounded, color: Joy.primary)),
              ])),
              const SizedBox(height: 10),
              if (c.reasons.isNotEmpty) ...[const SectionTitle('لماذا وصله العرض'), ReasonChips(c.reasons), const SizedBox(height: 10)],
              // ---- المجهول: الهوية بعد الإجابة
              if (c.anonymous)
                Container(
                  key: const Key('cand-anon-note'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
                  child: const Row(children: [Icon(Icons.visibility_off_outlined, color: Joy.sunText), SizedBox(width: 8), Expanded(child: Text('تظهر هوية المرشح وملفه بعد إجابته على أسئلة الفرز. حتى ذلك الحين ترى الدرجة والأسباب فقط، ولا تُتاح مراحل المقابلة والعرض والتعيين.', style: TextStyle(color: Joy.sunText, fontSize: 12.5, height: 1.5)))]),
                ),
              // ---- المكشوف: الملف والإجابات
              if (!c.anonymous) ...[
                const SectionTitle('ملف التوظيف'),
                if (p == null) const JoyCard(child: Text('حذف المرشح ملف التوظيف الخاص به', style: TextStyle(color: Joy.textMuted))) else _ProfileBlock(profile: p, onCv: _openCv),
                const SizedBox(height: 10),
                if (c.answers.isNotEmpty) ...[
                  const SectionTitle('إجابات الفرز'),
                  JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final a in c.answers) ...[
                      Text(a.text, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                      Text(a.display, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (a != c.answers.last) const Divider(height: 14),
                    ],
                  ])),
                  const SizedBox(height: 10),
                ],
              ],
              // ---- المرحلة والمسؤول
              const SectionTitle('المرحلة'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in jobStages.entries)
                  ChoiceChip(
                    key: Key('stage-${e.key}'),
                    label: Text(e.value, style: TextStyle(color: c.stage == e.key ? Joy.primaryOn : Joy.text, fontSize: 12.5)),
                    selected: c.stage == e.key,
                    showCheckmark: false,
                    selectedColor: e.key == 'rejected' ? Joy.danger : Joy.primary,
                    onSelected: busy || c.stage == e.key ? null : (_) => _setStage(e.key),
                  ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('cand-assignee'),
                initialValue: board != null && board.team.any((x) => x.id == c.assignee?.id) ? c.assignee!.id : null,
                decoration: const InputDecoration(labelText: 'المسؤول عن المرشح'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('بلا مسؤول محدد')),
                  for (final Person x in board?.team ?? const []) DropdownMenuItem(value: x.id, child: Text(x.nickname)),
                ],
                onChanged: busy ? null : (v) => _setAssignee(v),
              ),
              const SizedBox(height: 16),
              // ---- الملاحظات
              SectionTitle('ملاحظات الفريق · ${c.notes.length}'),
              for (final n in c.notes)
                JoyCard(
                  key: Key('note-${n.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (n.author != null) Avatar(name: n.author!.nickname, url: n.author!.avatarUrl, size: 30),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(n.author?.nickname ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(width: 6),
                        if (n.rating != null) Row(children: [for (var k = 1; k <= 5; k++) Icon(k <= n.rating! ? Icons.star_rounded : Icons.star_outline_rounded, size: 14, color: Joy.warning)]),
                        const Spacer(),
                        Text(timeAgo(n.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
                      ]),
                      if (n.text.isNotEmpty) Text(n.text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                    ])),
                    if (n.author?.id == myId)
                      IconButton(key: Key('note-del-${n.id}'), tooltip: 'حذف', visualDensity: VisualDensity.compact, onPressed: busy ? null : () => _run(() => ref.read(apiClientProvider).deleteJobNote(widget.bizId, widget.jobId, widget.matchId, n.id), ok: 'حُذفت الملاحظة'), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger)),
                  ]),
                ),
              const SizedBox(height: 6),
              JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('تقييمي', style: TextStyle(fontSize: 12.5, color: Joy.textMuted)),
                  const SizedBox(width: 6),
                  for (var k = 1; k <= 5; k++)
                    IconButton(key: Key('note-star-$k'), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => setState(() => noteRating = noteRating == k ? null : k), icon: Icon(k <= (noteRating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, color: Joy.warning, size: 22)),
                ]),
                TextField(key: const Key('note-text'), controller: note, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'ملاحظة للفريق (لا يراها المرشح)', isDense: true)),
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton(key: const Key('note-add'), onPressed: busy ? null : _addNote, child: const Text('إضافة'))),
              ])),
              const SizedBox(height: 16),
              // ---- المقابلات
              Row(children: [
                Expanded(child: Text('المقابلات · ${c.interviews.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                if (!c.anonymous) TextButton.icon(key: const Key('interview-new'), onPressed: busy ? null : _schedule, icon: const Icon(Icons.event_available_outlined, size: 18), label: const Text('تحديد مقابلة')),
              ]),
              if (c.interviews.isEmpty) Text(c.anonymous ? 'تُحدَّد المقابلات بعد ظهور هوية المرشح.' : 'لا مقابلات بعد.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              for (final iv in c.interviews)
                JoyCard(
                  key: Key('iv-${iv.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    Icon(iv.status == 'done' ? Icons.check_circle_outline_rounded : iv.status == 'cancelled' ? Icons.cancel_outlined : Icons.event_outlined, color: iv.status == 'cancelled' ? Joy.textMuted : Joy.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(iv.at == null ? '' : '${dayLabel(iv.at!)} · ${clockOf(iv.at)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text([iv.modeLabel, if (iv.place.isNotEmpty) iv.place, switch (iv.status) { 'done' => 'تمت', 'cancelled' => 'ملغاة', _ => 'مجدولة' }].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                      if (iv.note.isNotEmpty) Text(iv.note, style: const TextStyle(fontSize: 12.5)),
                    ])),
                    if (iv.status == 'scheduled') ...[
                      IconButton(key: Key('iv-done-${iv.id}'), tooltip: 'تمت', visualDensity: VisualDensity.compact, onPressed: busy ? null : () => _interviewStatus(iv, 'done'), icon: const Icon(Icons.task_alt_rounded, color: Joy.success)),
                      IconButton(key: Key('iv-cancel-${iv.id}'), tooltip: 'إلغاء', visualDensity: VisualDensity.compact, onPressed: busy ? null : () => _interviewStatus(iv, 'cancelled'), icon: const Icon(Icons.close_rounded, color: Joy.danger)),
                    ],
                  ]),
                ),
              const SizedBox(height: 16),
              // ---- السجل
              if (c.events.isNotEmpty) ...[
                const SectionTitle('السجل'),
                JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final e in c.events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        const Icon(Icons.circle, size: 7, color: Joy.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.label, style: const TextStyle(fontSize: 13))),
                        Text(timeAgo(e.at), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
                      ]),
                    ),
                ])),
              ],
            ]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobCandidateProvider(_ref))),
      ),
    );
  }
}

/// ملف التوظيف للمرشح المكشوف: المسمّيات والمدينة والدوام والخبرة والمؤهل والمهارات واللغات والراتب والجاهزية والنبذة والسيرة.
class _ProfileBlock extends StatelessWidget {
  final JobProfile profile;
  final Future<void> Function(String url) onCv;
  const _ProfileBlock({required this.profile, required this.onCv});

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 16, color: Joy.textMuted), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)))]),
      );

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final salary = p.salaryMin == null && p.salaryMax == null ? null : p.salaryMin != null && p.salaryMax != null ? '${p.salaryMin} – ${p.salaryMax} ر.س' : p.salaryMin != null ? 'من ${p.salaryMin} ر.س' : 'حتى ${p.salaryMax} ر.س';
    return JoyCard(
      key: const Key('cand-profile'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.titles.isNotEmpty) _line(Icons.badge_outlined, p.titles.join(' · ')),
        if (p.city.isNotEmpty) _line(Icons.place_outlined, [p.city, ...p.districts].join(' · ')),
        if (p.types.isNotEmpty) _line(Icons.schedule_outlined, p.types.map(jobTypeLabel).join(' · ')),
        _line(Icons.work_history_outlined, 'خبرة ${p.experienceYears} ${p.experienceYears == 1 ? 'سنة' : 'سنوات'}${p.education != 'none' ? ' · ${jobEducation[p.education] ?? p.education}' : ''}'),
        if (p.skills.isNotEmpty) _line(Icons.psychology_outlined, p.skills.join('، ')),
        if (p.languages.isNotEmpty) _line(Icons.translate_rounded, p.languages.join('، ')),
        if (salary != null) _line(Icons.payments_outlined, 'يتوقع $salary'),
        _line(Icons.event_available_outlined, 'الجاهزية: ${jobAvailability[p.availability] ?? p.availability}'),
        if (p.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.summary, style: const TextStyle(fontSize: 13.5, height: 1.5, color: Joy.text))),
        if (p.cvUrl != null && p.cvUrl!.isNotEmpty)
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('cand-cv'), onPressed: () => onCv(p.cvUrl!), icon: const Icon(Icons.description_outlined, size: 18), label: Text(p.cvName?.isNotEmpty == true ? p.cvName! : 'السيرة الذاتية'))),
      ]),
    );
  }
}
