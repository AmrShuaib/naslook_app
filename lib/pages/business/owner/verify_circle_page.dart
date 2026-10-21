import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../api/client.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show shortDate;

/// اكتمال الدائرة وحالة توثيقها (GET /biz/:id/completeness). يسكن هنا لأن اللوحة وصفحة التوثيق تقرآنه معاً.
final bizCompletenessProvider = FutureProvider.family<Completeness, String>((ref, id) => ref.watch(apiClientProvider).bizCompleteness(id));

/// يحدّث الاكتمال وكل ما يخص الدائرة بعد التوثيق أو «هنا اليوم» أو تعديل الملف.
void invalidateCompleteness(WidgetRef ref, String id) {
  ref.invalidate(bizCompletenessProvider(id));
  invalidateBizAll(ref, id);
}

/// يفتح صفحة توثيق الدائرة (سجل تجاري أو وثيقة عمل حر).
Future<void> openVerifyCircle(BuildContext context, String bizId, {Biz? initial}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VerifyCirclePage(bizId: bizId, initial: initial)));

/// رسالة مفهومة لأخطاء التوثيق.
String verifyErrText(Object e) {
  final s = '${e is ApiException ? (e.body?['error'] ?? '') : ''} $e';
  if (s.contains('already-approved')) return 'الدائرة موثّقة بالفعل';
  if (s.contains('bad-entity-kind')) return 'اختر نوع الكيان: سجل تجاري أو وثيقة عمل حر';
  if (s.contains('bad-entity-number')) return 'رقم الكيان غير صحيح';
  if (s.contains('doc-required') || s.contains('bad-doc')) return 'صورة المستند مطلوبة';
  if (s.contains('forbidden')) return 'التوثيق للمالك أو المدير فقط';
  if (e is ApiException) return e.message;
  return s;
}

/// صحة رقم الكيان: السجل التجاري 10 أرقام، ووثيقة العمل الحر 8–20 حرفاً أو رقماً.
bool validEntityNumber(String kind, String number) {
  final n = latinDigits(number.trim());
  return kind == 'cr' ? RegExp(r'^\d{10}$').hasMatch(n) : RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch(n);
}

/// صفحة التوثيق: نوع الكيان ورقمه وصورة المستند، ثم إحدى ثلاث حالات (قيد المراجعة، موثّقة، مرفوضة مع السبب وإعادة الإرسال).
class VerifyCirclePage extends ConsumerStatefulWidget {
  final String bizId;
  final Biz? initial;
  const VerifyCirclePage({super.key, required this.bizId, this.initial});
  @override
  ConsumerState<VerifyCirclePage> createState() => _VerifyCirclePageState();
}

class _VerifyCirclePageState extends ConsumerState<VerifyCirclePage> {
  String kind = 'cr';
  final number = TextEditingController();
  String? docUrl, numberError;
  bool uploading = false, busy = false, resubmitting = false;

  @override
  void initState() {
    super.initState();
    number.addListener(() { if (numberError != null) setState(() => numberError = null); });
  }

  @override
  void dispose() {
    number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comp = ref.watch(bizCompletenessProvider(widget.bizId));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('توثيق الدائرة')),
      body: comp.when(
        data: (c) {
          final v = c.verification;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
            const _Intro(),
            const SizedBox(height: 12),
            if (v.approved)
              _StateCard(
                key: const Key('verify-approved'),
                icon: Icons.verified_rounded, color: Joy.success, soft: const Color(0xFFE6F6EC),
                title: 'دائرتك موثّقة',
                lines: ['${entityKindLabel(v.entityKind)}${v.reviewedAt != null ? ' · ${shortDate(v.reviewedAt!)}' : ''}', 'يمكنك الآن البيع والحجز وربط الدفع من اللوحة.'],
              )
            else if (v.pending)
              _StateCard(
                key: const Key('verify-pending'),
                icon: Icons.hourglass_top_rounded, color: Joy.warning, soft: Joy.sunSoft,
                title: 'قيد المراجعة من الإدارة، عادةً خلال يوم عمل',
                lines: ['${entityKindLabel(v.entityKind)}${v.submittedAt != null ? ' · أُرسل ${shortDate(v.submittedAt!)}' : ''}', 'سنخبرك بإشعار فور القرار.'],
              )
            else if (v.rejected && !resubmitting)
              _StateCard(
                key: const Key('verify-rejected'),
                icon: Icons.cancel_outlined, color: Joy.danger, soft: Joy.accentSoft,
                title: 'رُفض طلب التوثيق',
                lines: [if (v.reason != null) 'السبب: ${v.reason}', if (v.reviewedAt != null) shortDate(v.reviewedAt!)],
                action: FilledButton.icon(key: const Key('verify-resubmit'), onPressed: () => setState(() { resubmitting = true; kind = v.entityKind ?? kind; }), icon: const Icon(Icons.refresh_rounded), label: const Text('أعد الإرسال')),
              )
            else
              _form(context),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizCompletenessProvider(widget.bizId))),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final valid = validEntityNumber(kind, number.text) && docUrl != null && !busy && !uploading;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('نوع الكيان'),
      JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(key: const Key('verify-kind-cr'), label: const Text('سجل تجاري'), selected: kind == 'cr', showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: kind == 'cr' ? Joy.primaryOn : Joy.text), onSelected: (_) => setState(() => kind = 'cr')),
          ChoiceChip(key: const Key('verify-kind-freelance'), label: const Text('وثيقة العمل الحر'), selected: kind == 'freelance', showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: kind == 'freelance' ? Joy.primaryOn : Joy.text), onSelected: (_) => setState(() => kind = 'freelance')),
        ]),
        const SizedBox(height: 10),
        const Text('سجل تجاري: للمؤسسات والشركات المسجّلة لدى وزارة التجارة.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const Text('وثيقة العمل الحر: للأفراد المستقلين الحاصلين على وثيقة من منصة العمل الحر.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
      ])),
      const SectionTitle('الرقم'),
      JoyCard(
        child: TextField(
          key: const Key('verify-number'),
          controller: number,
          keyboardType: kind == 'cr' ? TextInputType.number : TextInputType.text,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: kind == 'cr' ? 'رقم السجل التجاري (10 أرقام)' : 'رقم وثيقة العمل الحر', hintText: kind == 'cr' ? '1010XXXXXX' : 'FL-XXXXXXXX', errorText: numberError),
        ),
      ),
      const SectionTitle('صورة المستند'),
      JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (docUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: Image.network(thumbUrl(docUrl!), key: const Key('verify-doc-preview'), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Joy.surface2, alignment: Alignment.center, child: const Icon(Icons.description_outlined, color: Joy.textMuted, size: 40))),
            ),
          ),
        if (docUrl != null) const SizedBox(height: 8),
        if (uploading)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
        else
          Row(children: [
            Expanded(child: OutlinedButton.icon(key: const Key('verify-doc-pick'), onPressed: () => _upload(camera: false), icon: const Icon(Icons.photo_library_outlined, size: 18), label: Text(docUrl == null ? 'من الجهاز' : 'تغيير'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(key: const Key('verify-doc-camera'), onPressed: () => _upload(camera: true), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('الكاميرا'))),
          ]),
        const SizedBox(height: 6),
        Text(kind == 'cr' ? 'صورة واضحة لشهادة السجل التجاري أو طباعتها من منصة وزارة التجارة.' : 'صورة واضحة لوثيقة العمل الحر الصادرة من freelance.sa.', style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
      ])),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('verify-submit'),
        onPressed: valid ? _submit : null,
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.verified_user_outlined),
        label: Text(resubmitting ? 'أعد الإرسال' : 'إرسال للتوثيق'),
      ),
      const SizedBox(height: 8),
      const Text('لا يظهر رقم الكيان ولا المستند لأحد غير الإدارة. التحقق التلقائي عبر واثق قريباً.', style: TextStyle(color: Joy.textMuted, fontSize: 11.5, height: 1.5)),
    ]);
  }

  Future<void> _upload({required bool camera}) async {
    try {
      final img = await pickImage(camera: camera);
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => docUrl = up.url);
    } catch (e) {
      if (mounted) toast(context, verifyErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _submit() async {
    final n = latinDigits(number.text.trim());
    if (!validEntityNumber(kind, n)) {
      setState(() => numberError = kind == 'cr' ? 'السجل التجاري 10 أرقام' : 'الرقم بين 8 و20 حرفاً أو رقماً');
      return;
    }
    final doc = docUrl;
    if (doc == null) { toast(context, 'صورة المستند مطلوبة', error: true); return; }
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).submitVerification(widget.bizId, entityKind: kind, entityNumber: n, docUrl: doc);
      invalidateCompleteness(ref, widget.bizId);
      if (!mounted) return;
      setState(() => resubmitting = false);
      toast(context, 'أُرسل طلب التوثيق');
    } catch (e) {
      if (mounted) toast(context, verifyErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) => JoyCard(
        color: Joy.primarySoft,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_outlined, color: Joy.primary),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('التوثيق يفتح البيع والحجز وربط الدفع', style: TextStyle(fontWeight: FontWeight.w700, color: Joy.primary)),
            SizedBox(height: 4),
            Text('أرسل سجلك التجاري أو وثيقة العمل الحر مرة واحدة. تراجعها الإدارة يدوياً الآن، وتلقائياً عبر واثق لاحقاً. دائرتك تبقى ظاهرة على الخريطة أثناء المراجعة.', style: TextStyle(color: Joy.text, fontSize: 12.5, height: 1.5)),
          ])),
        ]),
      );
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final Color color, soft;
  final String title;
  final List<String> lines;
  final Widget? action;
  const _StateCard({super.key, required this.icon, required this.color, required this.soft, required this.title, this.lines = const [], this.action});
  @override
  Widget build(BuildContext context) => JoyCard(
        color: soft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: color))),
          ]),
          for (final l in lines) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l, style: const TextStyle(fontSize: 13, height: 1.5))),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ]),
      );
}
