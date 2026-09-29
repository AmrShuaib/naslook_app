import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/jobs_api.dart';
import '../../api/jobs_models.dart';
import '../../api/models.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../state/jobs_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness;
import '../chat/chat_thread_page.dart';

/// صفحة عرض وظيفي من جهة المرشح: تفاصيل الوظيفة والدائرة، ثم الرد (أقبل / لاحقاً / لا يناسبني)، ثم أسئلة الفرز بعد القبول،
/// ثم طلبي (إجاباتي والمرحلة والمقابلة والمحادثة مع مسؤول التوظيف). الهوية تُكشف للدائرة بعد الإجابة فقط (الخادم يضمن ذلك).

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// تاريخ ووقت بالعربية: «الثلاثاء 30 سبتمبر · 4:30 م».
String jobWhen(DateTime? t) => t == null ? '' : '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} · ${clockOf(t)}';
String jobDate(DateTime? t) => t == null ? '' : '${t.day} ${_months[t.month - 1]} ${t.year}';

/// شارة حالة البطاقة من جهة المرشح: نصّها ولونها.
({String label, Color color, Color bg}) jobMatchBadge(JobMatch m) {
  if (m.stage == 'hired') return (label: 'تعيين', color: Joy.success, bg: const Color(0xFFE6F6EC));
  if (m.stage == 'rejected' && m.status != 'withdrawn' && m.status != 'declined') return (label: 'معتذر', color: Joy.textMuted, bg: Joy.surface2);
  return switch (m.status) {
    'sent' || 'viewed' => (label: 'جديد', color: Joy.primary, bg: Joy.primarySoft),
    'later' => (label: 'مؤجّل', color: Joy.sunText, bg: Joy.sunSoft),
    'accepted' => (label: 'أجب على الأسئلة', color: Joy.accent, bg: Joy.accentSoft),
    'answered' => (label: m.stage == 'interview' ? 'مقابلة' : m.stage == 'offer' ? 'عرض عمل' : 'قيد المراجعة', color: Joy.primary, bg: Joy.primarySoft),
    'declined' => (label: 'اعتذرت', color: Joy.textMuted, bg: Joy.surface2),
    'withdrawn' => (label: 'انسحبت', color: Joy.textMuted, bg: Joy.surface2),
    'expired' => (label: 'انتهى', color: Joy.textMuted, bg: Joy.surface2),
    _ => (label: m.statusLabel, color: Joy.textMuted, bg: Joy.surface2),
  };
}

/// شارة صغيرة بلون الحالة.
class JobBadge extends StatelessWidget {
  final ({String label, Color color, Color bg}) badge;
  const JobBadge(this.badge, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: badge.bg, borderRadius: BorderRadius.circular(999)),
        child: Text(badge.label, style: TextStyle(color: badge.color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// يفتح محادثة التوظيف مع المسؤول ويضع رمز العرض في المؤلّف كأول رسالة (لا يُرسل تلقائياً).
Future<void> openJobChat(BuildContext context, Person who, {required String jobId}) async {
  toast(context, 'تم، افتح المحادثة مع ${who.nickname}');
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: who, initialText: jobCode(jobId))));
}

/// إجراءات الرد على عرض، مشتركة بين صفحة العرض وبطاقات تبويب «الطلبات» وصندوق الواردة.
class JobOfferFlow {
  static ApiClient _api(WidgetRef ref) => ref.read(apiClientProvider);

  /// القبول: بلا أسئلة يفتح الخادم المحادثة فوراً، وإلا تُفتح صفحة العرض لأسئلة الفرز (إن لم نكن فيها).
  static Future<bool> accept(BuildContext context, WidgetRef ref, JobMatch m, {bool openPage = true}) async {
    if (!requireAccount(context)) return false;
    final nav = Navigator.of(context);
    try {
      final r = await _api(ref).acceptJobOffer(m.id);
      invalidateJobs(ref, matchId: m.id);
      if (!context.mounted) return true;
      if (r.chatWith != null) {
        await openJobChat(context, r.chatWith!, jobId: m.jobId);
        return true;
      }
      toast(context, 'قبلت العرض، أجب على أسئلة الفرز');
      if (openPage) nav.push(MaterialPageRoute(builder: (_) => JobOfferPage(matchId: m.id)));
      return true;
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
      return false;
    }
  }

  static Future<void> later(BuildContext context, WidgetRef ref, JobMatch m) async {
    try {
      await _api(ref).laterJobOffer(m.id);
      invalidateJobs(ref, matchId: m.id);
      if (context.mounted) toast(context, 'أُجّل العرض، تجده في «عروض التوظيف»');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  static Future<void> decline(BuildContext context, WidgetRef ref, JobMatch m) async {
    final reason = await _askReason(context);
    if (reason == null || !context.mounted) return;
    try {
      await _api(ref).declineJobOffer(m.id, reason: reason);
      invalidateJobs(ref, matchId: m.id);
      if (context.mounted) toast(context, 'اعتذرت عن العرض');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  static Future<bool> withdraw(BuildContext context, WidgetRef ref, JobMatch m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سحب الطلب؟'),
        content: Text('تُزال من قائمة مرشحي «${m.job?.title ?? 'الوظيفة'}» ولا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(key: const Key('withdraw-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('اسحب طلبي')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    try {
      await _api(ref).withdrawJobOffer(m.id);
      invalidateJobs(ref, matchId: m.id);
      if (context.mounted) toast(context, 'سُحب طلبك');
      return true;
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
      return false;
    }
  }

  /// سبب الاعتذار اختياري (أسباب جاهزة أو نص)؛ null عند الإلغاء.
  static Future<String?> _askReason(BuildContext context) {
    final c = TextEditingController();
    const reasons = ['الراتب لا يناسبني', 'المكان بعيد', 'نوع الدوام لا يناسبني', 'لست متاحاً الآن'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('لا يناسبني'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('السبب اختياري ويساعد الدائرة على تحسين عروضها. لا يُكشف اسمك.', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (i, r) in reasons.indexed)
                ChoiceChip(key: Key('decline-reason-$i'), label: Text(r), selected: c.text == r, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: c.text == r ? Joy.primaryOn : Joy.text, fontSize: 12.5), onSelected: (_) => setState(() => c.text = r)),
            ]),
            const SizedBox(height: 8),
            TextField(key: const Key('decline-reason'), controller: c, maxLines: 2, decoration: const InputDecoration(hintText: 'أو اكتب سبباً')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(key: const Key('decline-confirm'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('اعتذر')),
          ],
        ),
      ),
    );
  }
}

class JobOfferPage extends ConsumerStatefulWidget {
  final String matchId;
  const JobOfferPage({super.key, required this.matchId});
  @override
  ConsumerState<JobOfferPage> createState() => _JobOfferPageState();
}

class _JobOfferPageState extends ConsumerState<JobOfferPage> {
  /// إجاباتي بمعرّف السؤال (نص أو رقم أو true/false أو خيار)، والإلزامية التي لم تُجب بعد محاولة الإرسال.
  final _answers = <String, dynamic>{};
  final _missing = <String>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(jobOfferProvider(widget.matchId));
    final m = offer.valueOrNull;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('عرض وظيفي')),
      body: offer.when(
        data: _body,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobOfferProvider(widget.matchId))),
      ),
      bottomNavigationBar: m == null ? null : _bottom(m),
    );
  }

  Future<void> _act(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// أزرار الرد: للجديد والمؤجّل، وللمعتذر «غيّرت رأيي» (الخادم يقبل القبول بعد الاعتذار ما دام العرض مفتوحاً).
  Widget? _bottom(JobMatch m) {
    final canAnswer = m.pending || m.status == 'later' || m.status == 'declined';
    if (!canAnswer || m.job?.isOpen == false) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(child: FilledButton(key: const Key('offer-accept'), onPressed: _busy ? null : () => _act(() => JobOfferFlow.accept(context, ref, m, openPage: false)), child: Text(m.status == 'declined' ? 'غيّرت رأيي، أقبل' : 'أقبل'))),
          if (m.pending) ...[
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('offer-later'), onPressed: _busy ? null : () => _act(() => JobOfferFlow.later(context, ref, m)), child: const Text('لاحقاً')),
          ],
          if (m.status != 'declined') ...[
            const SizedBox(width: 8),
            TextButton(key: const Key('offer-decline'), onPressed: _busy ? null : () => _act(() => JobOfferFlow.decline(context, ref, m)), child: const Text('لا يناسبني', style: TextStyle(color: Joy.textMuted))),
          ],
        ]),
      ),
    );
  }

  Widget _body(JobMatch m) {
    final j = m.job;
    final b = j?.biz;
    final salary = j?.salaryText ?? '';
    final hasReq = j != null && (j.must.isNotEmpty || j.nice.isNotEmpty || j.skills.isNotEmpty);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(jobOfferProvider(widget.matchId)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          JoyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                key: const Key('offer-biz'),
                borderRadius: BorderRadius.circular(12),
                onTap: b == null ? null : () => openBusiness(context, b.id),
                child: Row(children: [
                  Avatar(name: b?.title ?? j?.bizName ?? '؟', url: b?.logoUrl, size: 44, radius: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(b?.title ?? j?.bizName ?? 'دائرة', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                        if (b?.verified == true) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.verified_rounded, size: 16, color: Joy.primary)),
                      ]),
                      if (b != null && b.address.isNotEmpty) Text(b.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    ]),
                  ),
                  if (b != null) const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
                ]),
              ),
              const Divider(height: 20),
              Text(j?.title ?? 'عرض وظيفي', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (j != null && j.city.isNotEmpty) _Pill(Icons.place_outlined, [j.city, if (j.district.isNotEmpty) j.district].join(' · ')),
                if (j != null) _Pill(Icons.schedule_rounded, j.typeLabel),
                if (j != null && j.department.isNotEmpty) _Pill(Icons.apartment_outlined, j.department),
                if (j != null && j.experienceMin > 0) _Pill(Icons.history_rounded, 'خبرة ${j.experienceMin}+ سنوات'),
                if (j != null && j.education != 'none') _Pill(Icons.school_outlined, jobEducation[j.education] ?? j.education),
                if (j != null && j.openings > 1) _Pill(Icons.people_outline_rounded, '${j.openings} شواغر'),
              ]),
              if (salary.isNotEmpty) ...[const SizedBox(height: 8), Text(salary, key: const Key('offer-salary'), style: const TextStyle(color: Joy.accent, fontWeight: FontWeight.w700, fontSize: 14.5))],
              if (j?.deadline != null) ...[const SizedBox(height: 6), Text('آخر موعد للتقديم: ${jobDate(j!.deadline)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))],
              const SizedBox(height: 10),
              Row(children: [
                JobBadge(jobMatchBadge(m)),
                const SizedBox(width: 8),
                if (m.sentAt != null) Text('وصلك ${timeAgo(m.sentAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              ]),
            ]),
          ),
          if (m.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionTitle('لماذا وصلك هذا العرض'),
            JoyCard(child: Wrap(spacing: 6, runSpacing: 6, children: [for (final r in m.reasons) _reasonChip(r)])),
          ],
          if (j != null && j.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionTitle('عن الوظيفة'),
            JoyCard(child: Text(j.description, style: const TextStyle(height: 1.6))),
          ],
          if (hasReq) ...[
            const SizedBox(height: 12),
            const SectionTitle('المتطلبات'),
            JoyCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (j.must.isNotEmpty) ..._bullets('المطلوب', j.must, Joy.accent),
                if (j.nice.isNotEmpty) ..._bullets('يُفضّل', j.nice, Joy.primary),
                if (j.skills.isNotEmpty) ...[
                  const Text('المهارات', style: TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final s in j.skills) _reasonChip(s)]),
                ],
              ]),
            ),
          ],
          if (m.interview != null) ...[
            const SizedBox(height: 12),
            const SectionTitle('المقابلة'),
            _InterviewCard(m.interview!),
          ],
          if (m.closed) ...[const SizedBox(height: 12), _closedCard(m)],
          if (m.needsAnswers && m.job?.isOpen != false) ...[
            const SizedBox(height: 12),
            const SectionTitle('أسئلة الفرز'),
            _questionsCard(m),
          ],
          if (m.answered) ...[
            const SizedBox(height: 12),
            const SectionTitle('طلبي'),
            _applicationCard(m),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _bullets(String title, List<String> items, Color color) => [
        Text(title, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 7), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
              const SizedBox(width: 8),
              Expanded(child: Text(it, style: const TextStyle(height: 1.4))),
            ]),
          ),
        const SizedBox(height: 8),
      ];

  Widget _reasonChip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: const TextStyle(color: Joy.primary, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _closedCard(JobMatch m) {
    final (icon, text, color) = switch (m.status) {
      'declined' => (Icons.do_not_disturb_on_outlined, 'اعتذرت عن هذا العرض${m.declinedAt == null ? '' : ' ${timeAgo(m.declinedAt)}'}.', Joy.textMuted),
      'withdrawn' => (Icons.logout_rounded, 'سحبت طلبك من هذا العرض.', Joy.textMuted),
      'expired' => (Icons.timer_off_outlined, 'انتهت مدة هذا العرض.', Joy.textMuted),
      _ => m.stage == 'hired' ? (Icons.celebration_outlined, 'مبروك! تم تعيينك في هذه الوظيفة.', Joy.success) : (Icons.info_outline_rounded, 'اعتذرت الدائرة هذه المرة، وستصلك عروض أخرى تناسب ملفك.', Joy.textMuted),
    };
    return JoyCard(
      key: const Key('offer-closed'),
      child: Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: color == Joy.success ? Joy.text : Joy.textMuted)))]),
    );
  }

  // ---- أسئلة الفرز
  Widget _questionsCard(JobMatch m) => JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('بعد إرسال إجاباتك تُكشف هويتك للدائرة وتُفتح محادثة مع مسؤول التوظيف.', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
          if (m.questions.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا أسئلة على هذا العرض؛ أرسل طلبك مباشرة.', style: TextStyle(color: Joy.textMuted, fontSize: 13))),
          for (final q in m.questions) Padding(padding: const EdgeInsets.only(top: 14), child: _question(q)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(key: const Key('answers-submit'), onPressed: _busy ? null : () => _submit(m), child: Text(m.questions.isEmpty ? 'أرسل طلبي' : 'إرسال الإجابات')),
          ),
        ]),
      );

  Widget _question(JobQuestion q) {
    final missing = _missing.contains(q.id);
    void set(dynamic v) => setState(() {
          _answers[q.id] = v;
          _missing.remove(q.id);
        });
    Widget chip(Key key, String label, bool selected, VoidCallback onTap) => ChoiceChip(
          key: key, label: Text(label), selected: selected, showCheckmark: false, selectedColor: Joy.primary,
          labelStyle: TextStyle(color: selected ? Joy.primaryOn : Joy.text, fontWeight: FontWeight.w600, fontSize: 13), onSelected: (_) => onTap());
    final Widget input = switch (q.kind) {
      'yesno' => Wrap(spacing: 8, children: [
          chip(Key('q-${q.id}-yes'), 'نعم', _answers[q.id] == true, () => set(true)),
          chip(Key('q-${q.id}-no'), 'لا', _answers[q.id] == false, () => set(false)),
        ]),
      'choice' => Wrap(spacing: 6, runSpacing: 6, children: [for (final (i, o) in q.options.indexed) chip(Key('q-${q.id}-$i'), o, _answers[q.id] == o, () => set(o))]),
      'number' => TextField(
          key: Key('q-${q.id}'), keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'رقم'),
          // نرسل رقماً إن فُهم، وإلا النص كما كُتب ليرفضه الخادم بوضوح
          onChanged: (v) { final t = v.trim(); _answers[q.id] = t.isEmpty ? null : (num.tryParse(t) ?? t); _missing.remove(q.id); }),
      _ => TextField(
          key: Key('q-${q.id}'), maxLines: 4, minLines: 1, maxLength: 1500, decoration: const InputDecoration(hintText: 'اكتب إجابتك', counterText: ''),
          onChanged: (v) { _answers[q.id] = v; _missing.remove(q.id); }),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(text: q.text, children: [if (q.required) const TextSpan(text: ' *', style: TextStyle(color: Joy.danger))]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 6),
      input,
      if (missing) const Padding(padding: EdgeInsets.only(top: 4), child: Text('هذا السؤال إلزامي', style: TextStyle(color: Joy.danger, fontSize: 12))),
    ]);
  }

  Future<void> _submit(JobMatch m) async {
    final missing = <String>{};
    for (final q in m.questions) {
      final v = _answers[q.id];
      final empty = v == null || (v is String && v.trim().isEmpty);
      if (q.required && empty) missing.add(q.id);
    }
    if (missing.isNotEmpty) {
      setState(() => _missing..clear()..addAll(missing));
      toast(context, 'أجب على الأسئلة الإلزامية', error: true);
      return;
    }
    final answers = [for (final q in m.questions) {'id': q.id, 'value': _answers[q.id] is String ? (_answers[q.id] as String).trim() : _answers[q.id]}];
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiClientProvider).answerJobOffer(m.id, answers);
      invalidateJobs(ref, matchId: m.id);
      if (!mounted) return;
      if (r.chatWith != null) {
        await openJobChat(context, r.chatWith!, jobId: m.jobId);
      } else {
        toast(context, 'أُرسلت إجاباتك، ستتواصل معك الدائرة');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- طلبي بعد الإجابة
  Widget _applicationCard(JobMatch m) {
    final who = m.assignee;
    final canWithdraw = (m.status == 'accepted' || m.status == 'answered') && !['hired', 'rejected'].contains(m.stage);
    final answers = m.answers ?? const <JobAnswer>[];
    return JoyCard(
      key: const Key('offer-application'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.timeline_rounded, color: Joy.primary, size: 18),
          const SizedBox(width: 6),
          Text('المرحلة: ${m.stageLabel.isNotEmpty ? m.stageLabel : jobStageLabel(m.stage)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        if (m.answeredAt != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('أجبت ${timeAgo(m.answeredAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        if (answers.isNotEmpty) ...[
          const Divider(height: 20),
          const Text('إجاباتي', style: TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          for (final a in answers)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.text, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                Text(a.display, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        if (who != null) ...[
          const Divider(height: 20),
          Row(children: [
            ProfileAvatar(person: who, size: 36),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(who.nickname, style: const TextStyle(fontWeight: FontWeight.w600)), const Text('مسؤول التوظيف', style: TextStyle(color: Joy.textMuted, fontSize: 12))])),
            OutlinedButton.icon(key: const Key('offer-chat'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: who))), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('محادثة')),
          ]),
        ],
        if (canWithdraw) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(key: const Key('offer-withdraw'), onPressed: _busy ? null : () => _act(() => JobOfferFlow.withdraw(context, ref, m)), icon: const Icon(Icons.logout_rounded, size: 18, color: Joy.danger), label: const Text('سحب الطلب', style: TextStyle(color: Joy.danger))),
          ),
        ],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Joy.textMuted), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 12, color: Joy.text, fontWeight: FontWeight.w500))]),
      );
}

/// بطاقة موعد المقابلة: الوقت والطريقة والمكان والملاحظة وحالتها.
class _InterviewCard extends StatelessWidget {
  final JobInterview iv;
  const _InterviewCard(this.iv);
  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (iv.status) {
      'done' => ('تمت', Joy.success, const Color(0xFFE6F6EC)),
      'cancelled' => ('أُلغيت', Joy.textMuted, Joy.surface2),
      _ => ('مجدولة', Joy.accent, Joy.accentSoft),
    };
    return JoyCard(
      key: const Key('offer-interview'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.event_available_outlined, color: Joy.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(jobWhen(iv.at), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text([iv.modeLabel, if (iv.place.isNotEmpty) iv.place].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
            if (iv.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(iv.note, style: const TextStyle(fontSize: 13))),
          ]),
        ),
        JobBadge((label: label, color: color, bg: bg)),
      ]),
    );
  }
}
