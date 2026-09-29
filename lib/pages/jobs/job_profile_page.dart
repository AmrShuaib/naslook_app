import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/chat_tools_api.dart';
import '../../api/jobs_api.dart';
import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../core/media/media.dart';
import '../../state/app_state.dart';
import '../../state/jobs_providers.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart' show errText;
import 'job_offers_page.dart';

/// بديل للاختبارات: يعيد ملف السيرة الذاتية بدل فتح منتقي الملفات.
Future<PickedMedia?> Function()? pickJobCvOverride;

/// الحد الأقصى لحجم السيرة الذاتية.
const maxCvBytes = 5 * 1024 * 1024;

/// «أبحث عن عمل»: ملف التوظيف الخاص. لا يراه أحد؛ الدوائر التي تنشر وظيفة تناسبه ترسل بطاقة عرض، ولا تُكشف الهوية
/// إلا بعد قبول العرض والإجابة على أسئلة الفرز.
class JobProfilePage extends ConsumerStatefulWidget {
  const JobProfilePage({super.key});
  @override
  ConsumerState<JobProfilePage> createState() => _JobProfilePageState();
}

class _JobProfilePageState extends ConsumerState<JobProfilePage> {
  bool _inited = false, _exists = false, _busy = false, _cvBusy = false;
  bool _active = true;
  List<String> _titles = const [], _fields = const [], _districts = const [], _types = const [], _skills = const [], _languages = const [];
  final _city = TextEditingController(), _salaryMin = TextEditingController(), _salaryMax = TextEditingController(), _summary = TextEditingController();
  int _exp = 0;
  String _education = 'none', _availability = 'now';
  String? _cvUrl, _cvName, _titlesError;

  static const cities = ['جدة', 'الدمام', 'الرياض'];

  @override
  void dispose() {
    _city.dispose();
    _salaryMin.dispose();
    _salaryMax.dispose();
    _summary.dispose();
    super.dispose();
  }

  /// يملأ الحقول من الملف المحفوظ مرة واحدة عند أول وصول للبيانات.
  void _init(JobProfileState st) {
    if (_inited) return;
    _inited = true;
    final p = st.profile;
    if (p == null) return;
    _exists = true;
    _active = p.active;
    _titles = [...p.titles];
    _fields = [...p.fields];
    _districts = [...p.districts];
    _types = [...p.types];
    _skills = [...p.skills];
    _languages = [...p.languages];
    _city.text = p.city;
    _exp = p.experienceYears;
    _education = jobEducation.containsKey(p.education) ? p.education : 'none';
    _availability = jobAvailability.containsKey(p.availability) ? p.availability : 'now';
    _salaryMin.text = p.salaryMin?.toString() ?? '';
    _salaryMax.text = p.salaryMax?.toString() ?? '';
    _summary.text = p.summary;
    _cvUrl = p.cvUrl;
    _cvName = p.cvName;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(jobProfileProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('أبحث عن عمل'),
        actions: [if (_exists) IconButton(key: const Key('jp-delete'), tooltip: 'حذف الملف', icon: const Icon(Icons.delete_outline_rounded), onPressed: _busy ? null : _delete)],
      ),
      body: st.when(
        data: (d) {
          _init(d);
          return _form(d);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobProfileProvider)),
      ),
      bottomNavigationBar: st.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(key: const Key('jp-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'جارٍ الحفظ…' : _exists ? 'حفظ' : 'إنشاء الملف')),
              ),
            ),
    );
  }

  Widget _form(JobProfileState d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_exists) ...[
            JoyCard(
              key: const Key('jp-stats'),
              child: Row(children: [
                _stat('${d.pending}', 'بانتظار ردك'),
                _stat('${d.total}', 'عرض وصلك'),
                OutlinedButton(key: const Key('jp-offers'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobOffersPage())), child: const Text('العروض')),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          JoyCard(
            color: Joy.primarySoft,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline_rounded, color: Joy.primary),
              const SizedBox(width: 10),
              const Expanded(child: Text('ملفك خاص ولا يظهر لأحد. حين تنشر دائرة وظيفة تناسبك تصلك بطاقة عرض في «الطلبات»، ولا تُكشف هويتك للدائرة إلا بعد أن تقبل العرض وتجيب على أسئلة الفرز.', style: TextStyle(fontSize: 13, height: 1.5))),
            ]),
          ),
          const SizedBox(height: 12),
          JoyCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const Key('jp-active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('متاح للعروض'),
              subtitle: Text(_active ? 'تصلك بطاقات الوظائف التي تناسب ملفك' : 'موقوف: لا تصلك عروض جديدة حتى تعيد تفعيله'),
              secondary: const Icon(Icons.work_outline_rounded, color: Joy.primary),
            ),
          ),
          const SizedBox(height: 14),
          const SectionTitle('ماذا تبحث عنه'),
          JoyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ChipsField(fieldKey: const Key('jp-titles'), label: 'المسميات الوظيفية *', hint: 'مثل: باريستا، كاشير، محاسب', values: _titles, max: 6, error: _titlesError, onChanged: (v) => setState(() { _titles = v; _titlesError = null; })),
              const SizedBox(height: 12),
              _ChipsField(fieldKey: const Key('jp-fields'), label: 'المجالات', hint: 'مثل: مقاهي، مبيعات، تقنية', values: _fields, max: 6, onChanged: (v) => setState(() => _fields = v)),
              const SizedBox(height: 12),
              _label('نوع الدوام'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in jobTypes.entries)
                  FilterChip(
                    key: Key('jp-type-${e.key}'), label: Text(e.value), selected: _types.contains(e.key), showCheckmark: false, selectedColor: Joy.primary,
                    labelStyle: TextStyle(color: _types.contains(e.key) ? Joy.primaryOn : Joy.text, fontSize: 13),
                    onSelected: (on) => setState(() => _types = on ? [..._types, e.key] : [for (final t in _types) if (t != e.key) t]),
                  ),
              ]),
              const SizedBox(height: 12),
              _label('متى تستطيع البدء'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in jobAvailability.entries)
                  ChoiceChip(
                    key: Key('jp-avail-${e.key}'), label: Text(e.value), selected: _availability == e.key, showCheckmark: false, selectedColor: Joy.primary,
                    labelStyle: TextStyle(color: _availability == e.key ? Joy.primaryOn : Joy.text, fontSize: 13), onSelected: (_) => setState(() => _availability = e.key),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          const SectionTitle('المكان'),
          JoyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in cities)
                  ChoiceChip(
                    key: Key('jp-city-$c'), label: Text(c), selected: _city.text.trim() == c, showCheckmark: false, selectedColor: Joy.primary,
                    labelStyle: TextStyle(color: _city.text.trim() == c ? Joy.primaryOn : Joy.text, fontSize: 13), onSelected: (_) => setState(() => _city.text = c),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(key: const Key('jp-city'), controller: _city, decoration: const InputDecoration(labelText: 'المدينة', hintText: 'أو اكتب مدينة أخرى'), onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              _ChipsField(fieldKey: const Key('jp-districts'), label: 'الأحياء المفضّلة', hint: 'مثل: الحمراء، الشاطئ', values: _districts, max: 8, onChanged: (v) => setState(() => _districts = v)),
            ]),
          ),
          const SizedBox(height: 14),
          const SectionTitle('الخبرة والتعليم'),
          JoyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('سنوات الخبرة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                IconButton(key: const Key('jp-exp-minus'), tooltip: 'أقل', icon: const Icon(Icons.remove_circle_outline_rounded, color: Joy.primary), onPressed: _exp > 0 ? () => setState(() => _exp--) : null),
                Text('$_exp', key: const Key('jp-exp'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                IconButton(key: const Key('jp-exp-plus'), tooltip: 'أكثر', icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.primary), onPressed: _exp < 50 ? () => setState(() => _exp++) : null),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('jp-education'),
                initialValue: _education,
                decoration: const InputDecoration(labelText: 'المؤهل'),
                items: [for (final e in jobEducation.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _education = v ?? 'none'),
              ),
              const SizedBox(height: 12),
              _ChipsField(fieldKey: const Key('jp-skills'), label: 'المهارات', hint: 'مثل: خدمة عملاء، إكسل', values: _skills, max: 20, onChanged: (v) => setState(() => _skills = v)),
              const SizedBox(height: 12),
              _ChipsField(fieldKey: const Key('jp-languages'), label: 'اللغات', hint: 'مثل: العربية، الإنجليزية', values: _languages, max: 6, onChanged: (v) => setState(() => _languages = v)),
            ]),
          ),
          const SizedBox(height: 14),
          const SectionTitle('الراتب المتوقع (اختياري)'),
          JoyCard(
            child: Row(children: [
              Expanded(child: TextField(key: const Key('jp-salary-min'), controller: _salaryMin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'من (ر.س)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(key: const Key('jp-salary-max'), controller: _salaryMax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إلى (ر.س)'))),
            ]),
          ),
          const SizedBox(height: 14),
          const SectionTitle('نبذة والسيرة الذاتية'),
          JoyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(key: const Key('jp-summary'), controller: _summary, maxLines: 6, minLines: 3, maxLength: 600, decoration: const InputDecoration(hintText: 'نبذة قصيرة عن خبرتك وما تبحث عنه')),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.picture_as_pdf_outlined, color: Joy.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: _cvUrl == null
                      ? const Text('السيرة الذاتية: ملف PDF حتى 5 ميغابايت', style: TextStyle(color: Joy.textMuted, fontSize: 13))
                      : Text(_cvName ?? 'cv.pdf', key: const Key('jp-cv-name'), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                if (_cvBusy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (_cvUrl == null)
                  OutlinedButton(key: const Key('jp-cv-pick'), onPressed: _pickCv, child: const Text('إرفاق'))
                else
                  IconButton(key: const Key('jp-cv-remove'), tooltip: 'إزالة', icon: const Icon(Icons.close_rounded, color: Joy.textMuted), onPressed: () => setState(() { _cvUrl = null; _cvName = null; })),
              ]),
            ]),
          ),
        ],
      );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)));

  Widget _stat(String n, String label) => Expanded(
        child: Column(children: [
          Text(n, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Joy.primary)),
          Text(label, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
        ]),
      );

  /// السيرة الذاتية: PDF فقط بحد 5 ميغابايت، تُرفع عبر /chat/upload ويُحفظ رابطها مع الملف.
  Future<void> _pickCv() async {
    try {
      PickedMedia? f;
      if (pickJobCvOverride != null) {
        f = await pickJobCvOverride!();
      } else if (kIsWeb && WebMedia.available) {
        f = await WebMedia.pick('pdf');
      } else {
        // لا منتقي مستندات في النسخة الأصلية بعد؛ الصور فقط عبر image_picker
        toast(context, 'إرفاق السيرة الذاتية متاح من نسخة الويب حالياً');
        return;
      }
      if (f == null) return;
      final isPdf = f.mime == 'application/pdf' || f.name.toLowerCase().endsWith('.pdf');
      if (!isPdf) {
        if (mounted) toast(context, 'الملف يجب أن يكون PDF', error: true);
        return;
      }
      if (f.bytes.length > maxCvBytes) {
        if (mounted) toast(context, 'حجم الملف أكبر من 5 ميغابايت', error: true);
        return;
      }
      setState(() => _cvBusy = true);
      final up = await ref.read(apiClientProvider).uploadMedia(f.bytes, contentType: 'application/pdf', fileName: f.name);
      if (!mounted) return;
      setState(() {
        _cvUrl = up.url;
        _cvName = f!.name;
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _cvBusy = false);
    }
  }

  Future<void> _save() async {
    if (_titles.isEmpty) {
      setState(() => _titlesError = 'أضف مسمّى وظيفياً واحداً على الأقل');
      toast(context, 'أضف مسمّى وظيفياً واحداً على الأقل', error: true);
      return;
    }
    final min = int.tryParse(_salaryMin.text.trim()), max = int.tryParse(_salaryMax.text.trim());
    if (min != null && max != null && max < min) {
      toast(context, 'الحد الأعلى للراتب أقل من الأدنى', error: true);
      return;
    }
    final p = JobProfile(
      active: _active, titles: _titles, fields: _fields, city: _city.text.trim(), districts: _districts, types: _types, experienceYears: _exp, education: _education, skills: _skills,
      languages: _languages, salaryMin: min, salaryMax: max, availability: _availability, summary: _summary.text.trim(), cvUrl: _cvUrl, cvName: _cvUrl == null ? null : _cvName,
    );
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).saveJobProfile(p.toJson());
      invalidateJobs(ref);
      if (!mounted) return;
      setState(() => _exists = true);
      toast(context, _active ? 'حُفظ ملفك، ستصلك العروض التي تناسبك' : 'حُفظ ملفك (موقوف عن العروض)');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف ملف التوظيف؟'),
        content: const Text('يتوقف وصول العروض إليك وتُحذف بياناتك الوظيفية. طلباتك الحالية تبقى كما هي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(key: const Key('jp-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).deleteJobProfile();
      invalidateJobs(ref);
      if (!mounted) return;
      toast(context, 'حُذف ملفك');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// حقل رقائق: يكتب المستخدم قيمة ويضغط إدخال (أو فاصلة أو زر +) فتُضاف رقاقة قابلة للحذف، بحد أقصى.
class _ChipsField extends StatefulWidget {
  final Key fieldKey;
  final String label, hint;
  final List<String> values;
  final int max;
  final String? error;
  final ValueChanged<List<String>> onChanged;
  const _ChipsField({required this.fieldKey, required this.label, required this.hint, required this.values, required this.max, this.error, required this.onChanged});
  @override
  State<_ChipsField> createState() => _ChipsFieldState();
}

class _ChipsFieldState extends State<_ChipsField> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _add() {
    final parts = _ctl.text.split(RegExp(r'[،,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final next = [...widget.values];
    for (final p in parts) {
      if (next.length >= widget.max) break;
      if (!next.contains(p)) next.add(p);
    }
    _ctl.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.values.length >= widget.max;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      if (widget.values.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in widget.values)
              InputChip(label: Text(v, style: const TextStyle(fontSize: 12.5)), onDeleted: () => widget.onChanged([for (final x in widget.values) if (x != v) x])),
          ]),
        ),
      const SizedBox(height: 6),
      TextField(
        key: widget.fieldKey,
        controller: _ctl,
        enabled: !full,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          hintText: full ? 'بلغت الحد الأقصى' : widget.hint,
          errorText: widget.error,
          helperText: '${widget.values.length}/${widget.max}',
          suffixIcon: IconButton(tooltip: 'إضافة', icon: const Icon(Icons.add_rounded), onPressed: full ? null : _add),
        ),
      ),
    ]);
  }
}
