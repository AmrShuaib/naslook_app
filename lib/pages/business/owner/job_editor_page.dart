import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/client.dart';
import '../../../api/jobs_api.dart';
import '../../../api/jobs_models.dart';
import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show shortDate;
import 'job_actions.dart';

/// يفتح منشئ العرض (جديد أو تعديل) ويحدّث لوحة التوظيف بعد الرجوع.
Future<Job?> openJobEditor(BuildContext context, WidgetRef ref, String bizId, {JobsBoard? board, Job? initial}) async {
  final j = await Navigator.of(context).push<Job>(MaterialPageRoute(builder: (_) => JobEditorPage(bizId: bizId, board: board, initial: initial)));
  if (context.mounted) invalidateBizJobs(ref, bizId);
  return j;
}

/// منشئ العرض الوظيفي: الخطوة الأولى «المحرك» (مسمّى ونقاط → مسودة كاملة من الذكاء الاصطناعي أو القالب)،
/// والثانية النموذج الكامل مع أسئلة الفرز ومعاينة المطابقة، ثم حفظ كمسودة أو نشر فوري.
class JobEditorPage extends ConsumerStatefulWidget {
  final String bizId;
  final JobsBoard? board;
  final Job? initial;
  const JobEditorPage({super.key, required this.bizId, this.board, this.initial});
  @override
  ConsumerState<JobEditorPage> createState() => _JobEditorPageState();
}

class _JobEditorPageState extends ConsumerState<JobEditorPage> {
  Job? get i => widget.initial;
  late final title = TextEditingController(text: i?.title ?? '');
  late final titleEn = TextEditingController(text: i?.titleEn ?? '');
  late final desc = TextEditingController(text: i?.description ?? '');
  late final descEn = TextEditingController(text: i?.descriptionEn ?? '');
  late final department = TextEditingController(text: i?.department ?? '');
  late final city = TextEditingController(text: i?.city ?? '');
  late final salaryMin = TextEditingController(text: i?.salaryMin?.toString() ?? '');
  late final salaryMax = TextEditingController(text: i?.salaryMax?.toString() ?? '');
  late final experience = TextEditingController(text: '${i?.experienceMin ?? 0}');
  late final openings = TextEditingController(text: '${i?.openings ?? 1}');
  final bullets = <TextEditingController>[for (var k = 0; k < 3; k++) TextEditingController()];
  late List<String> must = [...?i?.must], nice = [...?i?.nice], skills = [...?i?.skills];
  late List<JobQuestion> questions = [...?i?.questions];
  late String type = i?.type ?? 'full', education = i?.education ?? 'none';
  late bool salaryVisible = i?.salaryVisible ?? false, public = i?.public ?? true;
  // المحرك مفتوح للعرض الجديد ومطويّ عند التعديل حتى لا يغطي على النموذج
  late bool engineOpen = i == null;
  late String? assigneeId = i?.assigneeId;
  late DateTime? deadline = i?.deadline;
  late String? draftSource = i?.draftSource;
  JobDraft? draft;
  JobPreview? preview;
  bool drafting = false, previewing = false, saving = false;
  int _qSeq = 0;

  @override
  void dispose() {
    for (final c in [title, titleEn, desc, descEn, department, city, salaryMin, salaryMax, experience, openings, ...bullets]) {
      c.dispose();
    }
    super.dispose();
  }

  JobsBoard? get board => widget.board ?? ref.watch(jobsBoardProvider(widget.bizId)).valueOrNull;

  Map<String, dynamic> _body() => {
        'title': title.text.trim(), 'titleEn': titleEn.text.trim(), 'department': department.text.trim(), 'description': desc.text.trim(), 'descriptionEn': descEn.text.trim(),
        'requirements': {'must': must, 'nice': nice}, 'skills': skills, 'city': city.text.trim(), 'type': type, 'experienceMin': int.tryParse(experience.text.trim()) ?? 0, 'education': education,
        'salaryMin': int.tryParse(salaryMin.text.trim()), 'salaryMax': int.tryParse(salaryMax.text.trim()), 'salaryVisible': salaryVisible, 'openings': int.tryParse(openings.text.trim()) ?? 1,
        'deadline': deadline?.toUtc().toIso8601String(), 'public': public, 'questions': questions.map((q) => q.toJson()).toList(), 'assigneeId': assigneeId ?? '',
        if (draftSource != null) 'draftSource': draftSource,
      };

  Future<void> _draft() async {
    final t = title.text.trim();
    if (t.isEmpty) {
      toast(context, 'اكتب المسمّى الوظيفي أولاً', error: true);
      return;
    }
    setState(() => drafting = true);
    try {
      final d = await ref.read(apiClientProvider).draftJob(widget.bizId,
          title: t, bullets: bullets.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(), type: type, city: city.text.trim(), department: department.text.trim(),
          salaryMin: int.tryParse(salaryMin.text.trim()), salaryMax: int.tryParse(salaryMax.text.trim()));
      if (!mounted) return;
      setState(() {
        draft = d;
        draftSource = d.source;
        if (d.title.isNotEmpty) title.text = d.title;
        if (d.titleEn.isNotEmpty) titleEn.text = d.titleEn;
        desc.text = d.description;
        descEn.text = d.descriptionEn;
        must = [...d.must];
        nice = [...d.nice];
        skills = [...d.skills];
        questions = [...d.questions];
        preview = null;
      });
      toast(context, d.fromAi ? 'صيغت المسودة بالذكاء الاصطناعي؛ راجعها وعدّلها قبل النشر' : 'جُهّزت مسودة من القالب؛ عدّلها كما تريد');
    } catch (e) {
      if (mounted) toast(context, jobErrText(e), error: true);
    } finally {
      if (mounted) setState(() => drafting = false);
    }
  }

  Future<void> _preview() async {
    setState(() => previewing = true);
    try {
      final p = await ref.read(apiClientProvider).previewDraftMatch(widget.bizId, _body());
      if (mounted) setState(() => preview = p);
    } catch (e) {
      if (mounted) toast(context, jobErrText(e), error: true);
    } finally {
      if (mounted) setState(() => previewing = false);
    }
  }

  Future<void> _save({required bool publish}) async {
    if (title.text.trim().length < 3) {
      toast(context, 'اكتب مسمّى وظيفياً (3 أحرف على الأقل)', error: true);
      return;
    }
    if (publish && desc.text.trim().length < 30) {
      toast(context, 'اكتب وصفاً للوظيفة (30 حرفاً على الأقل) أو اضغط «اكتب لي العرض»', error: true);
      return;
    }
    final mn = int.tryParse(salaryMin.text.trim()), mx = int.tryParse(salaryMax.text.trim());
    if (mn != null && mx != null && mx < mn) {
      toast(context, 'الحد الأعلى للراتب أقل من الأدنى', error: true);
      return;
    }
    setState(() => saving = true);
    final api = ref.read(apiClientProvider);
    try {
      draftSource ??= 'manual';
      Job job;
      final existing = i;
      if (existing == null) {
        job = await api.createJob(widget.bizId, _body(), publish: publish);
      } else {
        job = await api.updateJob(widget.bizId, existing.id, _body());
        if (publish && !job.isOpen) job = await api.publishJob(widget.bizId, existing.id);
      }
      if (!mounted) return;
      invalidateBizJobs(ref, widget.bizId);
      toast(context, publish ? jobPublishedText(job) : existing == null || existing.status == 'draft' ? 'حُفظت المسودة' : 'حُفظت التعديلات');
      Navigator.of(context).maybePop(job);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.body?['error'] == 'plan-limit') {
        // الخادم يحفظ العرض كمسودة ثم يرفض النشر؛ نوجّه إلى بطاقة الباقة أعلى تبويب التوظيف
        invalidateBizJobs(ref, widget.bizId);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${e.message}${i == null ? '؛ حُفظ العرض كمسودة' : ''}'),
            backgroundColor: Joy.danger,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'الباقة', textColor: Joy.sun, onPressed: () => Navigator.of(context).maybePop()),
          ));
      } else {
        toast(context, jobErrText(e), error: true);
      }
    } catch (e) {
      if (mounted) toast(context, jobErrText(e), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: deadline != null && deadline!.isAfter(now) ? deadline! : now.add(const Duration(days: 14)), helpText: 'آخر موعد للتقديم');
    if (d != null) setState(() => deadline = DateTime(d.year, d.month, d.day, 23, 59));
  }

  void _addQuestion() {
    if (questions.length >= 10) return;
    setState(() => questions = [...questions, JobQuestion(id: 'nq${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_qSeq++}', text: '', kind: 'text')]);
  }

  @override
  Widget build(BuildContext context) {
    final b = board;
    final editing = i != null;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(editing ? 'تعديل العرض' : 'عرض وظيفي جديد')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        _engineCard(b),
        const SizedBox(height: 14),
        const SectionTitle('تفاصيل العرض'),
        if (!engineOpen) ...[
          TextField(key: const Key('job-title'), controller: title, decoration: const InputDecoration(labelText: 'المسمّى الوظيفي')),
          const SizedBox(height: 10),
        ],
        TextField(key: const Key('job-title-en'), controller: titleEn, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'المسمّى بالإنجليزية (اختياري)')),
        const SizedBox(height: 10),
        TextField(key: const Key('job-desc'), controller: desc, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'وصف الوظيفة', alignLabelWithHint: true, helperText: '30 حرفاً على الأقل للنشر')),
        ExpansionTile(
          key: const Key('job-desc-en-tile'),
          tilePadding: EdgeInsets.zero,
          title: const Text('الوصف بالإنجليزية (اختياري)', style: TextStyle(fontSize: 13.5, color: Joy.textMuted)),
          children: [TextField(key: const Key('job-desc-en'), controller: descEn, textDirection: TextDirection.ltr, minLines: 3, maxLines: 10, decoration: const InputDecoration(labelText: 'Description'))],
        ),
        if (!engineOpen) ..._basics(),
        const SizedBox(height: 10),
        _ChipsField(id: 'must', label: 'متطلبات أساسية', hint: 'مثال: خبرة سنة في المبيعات', items: must, onChanged: (v) => setState(() => must = v)),
        _ChipsField(id: 'nice', label: 'يُفضَّل', hint: 'مثال: رخصة قيادة', items: nice, onChanged: (v) => setState(() => nice = v)),
        _ChipsField(id: 'skills', label: 'المهارات (تُستخدم في المطابقة)', hint: 'مثال: خدمة العملاء', items: skills, onChanged: (v) => setState(() => skills = v), max: 12),
        Row(children: [
          Expanded(child: TextField(key: const Key('job-exp'), controller: experience, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأدنى للخبرة (سنوات)'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const Key('job-openings'), controller: openings, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الشواغر'))),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('job-education'),
          initialValue: education,
          decoration: const InputDecoration(labelText: 'المؤهل'),
          items: [for (final e in jobEducation.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => education = v ?? 'none'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const Key('job-deadline'), onPressed: _pickDeadline, icon: const Icon(Icons.event_outlined, size: 18), label: Text(deadline == null ? 'آخر موعد للتقديم (اختياري)' : 'حتى ${shortDate(deadline!)}'))),
          if (deadline != null) IconButton(key: const Key('job-deadline-clear'), tooltip: 'إزالة الموعد', onPressed: () => setState(() => deadline = null), icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
        SwitchListTile(key: const Key('job-salary-visible'), contentPadding: EdgeInsets.zero, value: salaryVisible, onChanged: (v) => setState(() => salaryVisible = v), title: const Text('إظهار الراتب للمتقدمين'), subtitle: const Text('العروض التي تُظهر الراتب تحصل على إجابات أسرع', style: TextStyle(fontSize: 12))),
        SwitchListTile(key: const Key('job-public'), contentPadding: EdgeInsets.zero, value: public, onChanged: (v) => setState(() => public = v), title: const Text('عرض عام'), subtitle: const Text('يظهر في قائمة الوظائف وصفحة الدائرة؛ وإلا يصل فقط لمن يطابقه', style: TextStyle(fontSize: 12))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('job-assignee'),
          initialValue: b != null && b.team.any((p) => p.id == assigneeId) ? assigneeId : null,
          decoration: const InputDecoration(labelText: 'المسؤول عن المرشحين'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('مالك الدائرة (افتراضي)')),
            for (final Person p in b?.team ?? const []) DropdownMenuItem(value: p.id, child: Text(p.nickname)),
          ],
          onChanged: (v) => setState(() => assigneeId = v),
        ),
        const SizedBox(height: 16),
        _QuestionsEditor(questions: questions, onChanged: (v) => setState(() => questions = v), onAdd: _addQuestion),
        const SizedBox(height: 16),
        JoyCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('معاينة المطابقة', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              preview == null ? 'كم باحثاً عن عمل يطابق هذا العرض الآن؟ (أعداد فقط، بلا هويات)' : '${preview!.strong} مطابق قوي · ${preview!.good} جيد · من ${preview!.profiles} ملف نشط',
              key: const Key('job-preview-text'),
              style: const TextStyle(color: Joy.textMuted, fontSize: 12.5),
            ),
          ])),
          const SizedBox(width: 8),
          OutlinedButton(key: const Key('job-preview'), onPressed: previewing ? null : _preview, child: previewing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('معاينة')),
        ])),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(key: const Key('job-save'), onPressed: saving ? null : () => _save(publish: false), child: Text(!editing || i!.status == 'draft' ? 'حفظ كمسودة' : 'حفظ'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const Key('job-publish'),
                onPressed: saving ? null : () => _save(publish: true),
                icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Joy.primaryOn)) : const Icon(Icons.rocket_launch_outlined, size: 18),
                label: Text(editing && i!.isOpen ? 'حفظ التعديلات' : 'نشر الآن'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// النوع والقسم والمدينة والراتب: تظهر داخل المحرك حين يكون مفتوحاً، وإلا في النموذج.
  List<Widget> _basics() => [
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const Key('job-type'),
              initialValue: type,
              decoration: const InputDecoration(labelText: 'نوع الدوام'),
              items: [for (final e in jobTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => type = v ?? 'full'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const Key('job-department'), controller: department, decoration: const InputDecoration(labelText: 'القسم (اختياري)'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(key: const Key('job-city'), controller: city, decoration: const InputDecoration(labelText: 'المدينة', hintText: 'مدينة الدائرة'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const Key('job-salary-min'), controller: salaryMin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الراتب من'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const Key('job-salary-max'), controller: salaryMax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إلى'))),
        ]),
      ];

  Widget _engineCard(JobsBoard? b) => JoyCard(
        key: const Key('job-engine'),
        color: Joy.primarySoft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Joy.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('المحرك: نقاط قليلة ونصوغ لك العرض', style: TextStyle(fontWeight: FontWeight.w700))),
            if (draft != null)
              Container(
                key: const Key('job-draft-source'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(999)),
                child: Text(draft!.fromAi ? 'صيغ بالذكاء الاصطناعي' : 'قالب', style: const TextStyle(color: Joy.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            IconButton(key: const Key('job-engine-toggle'), tooltip: engineOpen ? 'طيّ' : 'فتح', onPressed: () => setState(() => engineOpen = !engineOpen), icon: Icon(engineOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded)),
          ]),
          if (engineOpen) ...[
            const Text('اكتب المسمّى و3 إلى 8 نقاط عن الوظيفة ثم اضغط «اكتب لي العرض». تصلك مسودة كاملة (وصف، متطلبات، مهارات، أسئلة فرز) تعدّلها قبل النشر.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 10),
            TextField(key: const Key('job-title'), controller: title, decoration: const InputDecoration(labelText: 'المسمّى الوظيفي', hintText: 'مثال: موظف خدمة عملاء')),
            const SizedBox(height: 10),
            const Text('نقاط عن الوظيفة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            for (var k = 0; k < bullets.length; k++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  key: Key('job-bullet-$k'),
                  controller: bullets[k],
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.circle, size: 8), hintText: const ['استقبال العملاء والرد على استفساراتهم', 'العمل على نظام نقاط البيع', 'ورديات صباحية ومسائية', 'التنسيق مع فريق المستودع', 'إعداد تقرير يومي', 'خبرة في المجال', 'اللغة الإنجليزية', 'رخصة قيادة'][k], isDense: true),
                ),
              ),
            if (bullets.length < 8)
              Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('job-bullet-add'), onPressed: () => setState(() => bullets.add(TextEditingController())), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('نقطة أخرى'))),
            ..._basics(),
            const SizedBox(height: 10),
            if (b != null && !b.aiAvailable)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('مفتاح الذكاء الاصطناعي غير مضبوط في لوحة الإدارة، فسنجهّز المسودة من القالب الجاهز.', key: Key('job-ai-hint'), style: TextStyle(color: Joy.warning, fontSize: 12))),
            if (draft?.aiError != null && draft!.aiError!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('تعذّر الذكاء الاصطناعي (${draft!.aiError}) فاستُخدم القالب', key: const Key('job-ai-error'), style: const TextStyle(color: Joy.warning, fontSize: 12))),
            FilledButton.icon(
              key: const Key('job-draft'),
              onPressed: drafting ? null : _draft,
              icon: drafting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Joy.primaryOn)) : const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(drafting ? 'نصوغ العرض…' : 'اكتب لي العرض'),
            ),
          ],
        ]),
      );
}

/// قائمة بنود قصيرة كرقائق قابلة للحذف مع حقل إضافة.
class _ChipsField extends StatefulWidget {
  final String id, label, hint;
  final List<String> items;
  final int max;
  final ValueChanged<List<String>> onChanged;
  const _ChipsField({required this.id, required this.label, required this.hint, required this.items, required this.onChanged, this.max = 12});
  @override
  State<_ChipsField> createState() => _ChipsFieldState();
}

class _ChipsFieldState extends State<_ChipsField> {
  final c = TextEditingController();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _add() {
    final v = c.text.trim();
    if (v.isEmpty || widget.items.contains(v) || widget.items.length >= widget.max) return;
    widget.onChanged([...widget.items, v]);
    c.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (widget.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final it in widget.items)
                  InputChip(key: Key('${widget.id}-chip-${widget.items.indexOf(it)}'), label: Text(it, style: const TextStyle(fontSize: 12)), onDeleted: () => widget.onChanged([...widget.items]..remove(it)), visualDensity: VisualDensity.compact),
              ]),
            ),
          TextField(
            key: Key('${widget.id}-input'),
            controller: c,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(hintText: widget.hint, isDense: true, suffixIcon: IconButton(key: Key('${widget.id}-add'), tooltip: 'إضافة', onPressed: _add, icon: const Icon(Icons.add_circle_outline_rounded))),
          ),
        ]),
      );
}

/// محرر أسئلة الفرز: إضافة وحذف وترتيب، أنواع نص/نعم-لا/اختيار/رقم، وخيارات للاختيار، وإلزامية. الحد 10 أسئلة.
class _QuestionsEditor extends StatelessWidget {
  final List<JobQuestion> questions;
  final ValueChanged<List<JobQuestion>> onChanged;
  final VoidCallback onAdd;
  const _QuestionsEditor({required this.questions, required this.onChanged, required this.onAdd});

  void _set(int k, JobQuestion q) => onChanged([for (var x = 0; x < questions.length; x++) x == k ? q : questions[x]]);
  void _move(int k, int d) {
    final l = [...questions];
    final q = l.removeAt(k);
    l.insert(k + d, q);
    onChanged(l);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('أسئلة الفرز · ${questions.length}/10', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          if (questions.length < 10) TextButton.icon(key: const Key('job-q-add'), onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('سؤال')),
        ]),
        const Text('تظهر لك هوية المرشح بعد إجابته على هذه الأسئلة؛ اجعلها قصيرة ومحددة.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        if (questions.isEmpty) const Text('بلا أسئلة: تظهر هوية من يقبل العرض مباشرة.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        for (var k = 0; k < questions.length; k++)
          Padding(
            key: ValueKey('q-${questions[k].id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: JoyCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${k + 1}', style: const TextStyle(color: Joy.textMuted, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(key: Key('job-q-$k'), initialValue: questions[k].text, decoration: const InputDecoration(hintText: 'نص السؤال', isDense: true), onChanged: (v) => _set(k, questions[k].copyWith(text: v)))),
                  IconButton(key: Key('job-q-$k-up'), tooltip: 'أعلى', onPressed: k == 0 ? null : () => _move(k, -1), icon: const Icon(Icons.arrow_upward_rounded, size: 18), visualDensity: VisualDensity.compact),
                  IconButton(key: Key('job-q-$k-down'), tooltip: 'أسفل', onPressed: k == questions.length - 1 ? null : () => _move(k, 1), icon: const Icon(Icons.arrow_downward_rounded, size: 18), visualDensity: VisualDensity.compact),
                  IconButton(key: Key('job-q-$k-del'), tooltip: 'حذف', onPressed: () => onChanged([...questions]..removeAt(k)), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger), visualDensity: VisualDensity.compact),
                ]),
                Row(children: [
                  DropdownButton<String>(
                    key: Key('job-q-$k-kind'),
                    value: JobQuestion.kinds.containsKey(questions[k].kind) ? questions[k].kind : 'text',
                    isDense: true,
                    underline: const SizedBox(),
                    items: [for (final e in JobQuestion.kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))],
                    onChanged: (v) => _set(k, questions[k].copyWith(kind: v ?? 'text', options: v == 'choice' ? questions[k].options : const [])),
                  ),
                  const Spacer(),
                  const Text('إلزامي', style: TextStyle(fontSize: 12.5, color: Joy.textMuted)),
                  Switch(key: Key('job-q-$k-required'), value: questions[k].required, onChanged: (v) => _set(k, questions[k].copyWith(required: v))),
                ]),
                if (questions[k].kind == 'choice')
                  TextFormField(
                    key: Key('job-q-$k-options'),
                    initialValue: questions[k].options.join('، '),
                    decoration: const InputDecoration(hintText: 'الخيارات مفصولة بفاصلة (خياران على الأقل)', isDense: true),
                    onChanged: (v) => _set(k, questions[k].copyWith(options: v.split(RegExp(r'[،,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList())),
                  ),
              ]),
            ),
          ),
      ]);
}
