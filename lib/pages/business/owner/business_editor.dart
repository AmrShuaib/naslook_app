import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/location.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import 'business_dashboard_page.dart';
import '../../../api/client.dart';

/// يفتح محرّر الدائرة: إنشاء جديدة أو تعديل ملف دائرة قائمة.
Future<void> openBusinessEditor(BuildContext context, {Biz? biz}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessEditorPage(biz: biz)));

const bizColorPresets = ['#0A6E78', '#0058A3', '#00704A', '#DA291C', '#111111', '#1428A0', '#E4002B', '#6D28D9', '#0B2D5B', '#3A2E2A', '#ED5C0F', '#00A3E0', '#FFCF00', '#875C0A', '#1FA35A', '#BF3A1E'];

/// نموذج إنشاء/تعديل ملف الدائرة: الأسماء والفئة والوصف والموقع على الخريطة والتواصل واللون والمميزات والصور والنشر.
class BusinessEditorPage extends ConsumerStatefulWidget {
  final Biz? biz;
  const BusinessEditorPage({super.key, this.biz});
  @override
  ConsumerState<BusinessEditorPage> createState() => _BusinessEditorPageState();
}

class _BusinessEditorPageState extends ConsumerState<BusinessEditorPage> {
  late final TextEditingController name, nameAr, sector, description, address, hours, phone, website, highlight;
  late BizCategory category;
  late String color;
  late List<String> highlights;
  String? logoUrl, coverUrl;
  LatLng? point;
  bool active = true, busy = false, uploading = false;
  final _map = MapController();

  Biz? get b => widget.biz;
  bool get isNew => b == null;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: b?.name ?? '');
    nameAr = TextEditingController(text: b?.nameAr ?? '');
    sector = TextEditingController(text: b?.sector ?? '');
    description = TextEditingController(text: b?.description ?? '');
    address = TextEditingController(text: b?.address ?? '');
    hours = TextEditingController(text: b?.hours ?? '');
    phone = TextEditingController(text: b?.phone ?? '');
    website = TextEditingController(text: b?.website ?? '');
    highlight = TextEditingController();
    category = b?.category ?? BizCategory.brand;
    color = b?.colorHex ?? bizColorPresets.first;
    highlights = List.of(b?.highlights ?? const []);
    logoUrl = b?.logoUrl;
    coverUrl = b?.coverUrl;
    active = b?.active ?? true;
    point = b == null ? null : LatLng(b!.lat, b!.lng);
    if (point == null) {
      Future.microtask(() async {
        final gps = await DeviceLocation.current(precise: false);
        if (mounted && point == null) setState(() => point = gps ?? const LatLng(21.5433, 39.1728));
      });
    }
  }

  @override
  void dispose() {
    for (final c in [name, nameAr, sector, description, address, hours, phone, website, highlight]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.read(apiClientProvider).baseUrl;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(isNew ? 'دائرة تجارية جديدة' : 'ملف الدائرة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        // ---- الصور
        const SectionTitle('الشعار والغلاف'),
        JoyCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            InkWell(
              onTap: uploading ? null : () => _upload(cover: true),
              child: Container(
                height: 120,
                decoration: BoxDecoration(color: _hex(color).withValues(alpha: .85), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), image: coverUrl != null ? DecorationImage(image: NetworkImage(thumbUrl(coverUrl!)), fit: BoxFit.cover) : null),
                alignment: Alignment.center,
                child: uploading ? const CircularProgressIndicator(color: Colors.white) : Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add_photo_alternate_outlined, color: Colors.white), const SizedBox(width: 6), Text(coverUrl == null ? 'صورة الغلاف' : 'تغيير الغلاف', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                InkWell(
                  onTap: uploading ? null : () => _upload(cover: false),
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(color: _hex(color), borderRadius: BorderRadius.circular(20), image: logoUrl != null ? DecorationImage(image: NetworkImage(thumbUrl(logoUrl!)), fit: BoxFit.cover) : null),
                    alignment: Alignment.center,
                    child: logoUrl == null ? const Icon(Icons.add_a_photo_outlined, color: Colors.white) : null,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('الشعار يظهر في القوائم والخريطة، والغلاف أعلى صفحة الدائرة. الصور تُرفع إلى خادم Naslife.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5))),
                if (logoUrl != null) IconButton(tooltip: 'إزالة الشعار', onPressed: () => setState(() => logoUrl = null), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger)),
              ]),
            ),
          ]),
        ),
        // ---- الأساسيات
        const SectionTitle('الأساسيات'),
        JoyCard(child: Column(children: [
          TextField(controller: nameAr, decoration: const InputDecoration(labelText: 'الاسم بالعربية', hintText: 'قهوة المرسى'), textInputAction: TextInputAction.next),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم اللاتيني (اختياري)', hintText: 'Marsa Coffee'), textInputAction: TextInputAction.next),
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerStart, child: Text('التخصص التجاري', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in BizCategory.values)
              ChoiceChip(
                avatar: Icon(c.icon, size: 16, color: category == c ? Joy.primaryOn : Joy.textMuted),
                label: Text(c.label, style: TextStyle(color: category == c ? Joy.primaryOn : Joy.text)),
                selected: category == c,
                showCheckmark: false,
                selectedColor: Joy.primary,
                onSelected: isNew ? (_) => setState(() => category = c) : null,
              ),
          ]),
          if (!isNew) const Padding(padding: EdgeInsets.only(top: 6), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('التخصص يُحدَّد عند الإنشاء لأن الكتالوج يعتمد عليه', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)))),
          const SizedBox(height: 10),
          TextField(controller: sector, decoration: InputDecoration(labelText: 'القطاع', hintText: switch (category) { BizCategory.brand => 'مقهى، أزياء، إلكترونيات…', BizCategory.cinema => 'سينما', BizCategory.hotel => 'فندق 4 نجوم', BizCategory.carRental => 'تأجير سيارات' })),
          const SizedBox(height: 10),
          TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف', hintText: 'عرّف بنشاطك في سطرين أو ثلاثة')),
        ])),
        // ---- الموقع
        const SectionTitle('الموقع'),
        JoyCard(child: Column(children: [
          TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'شارع التحلية، العزيزية، جدة')),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 200,
              child: point == null
                  ? const Center(child: CircularProgressIndicator())
                  : FlutterMap(
                      mapController: _map,
                      options: MapOptions(initialCenter: point!, initialZoom: 14, onTap: (_, p) => setState(() => point = p), interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
                      children: [
                        TileLayer(urlTemplate: '$base/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
                        MarkerLayer(markers: [Marker(point: point!, width: 40, height: 40, child: const Icon(Icons.location_on_rounded, color: Joy.accent, size: 40))]),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('اضغط على الخريطة لتحديد موقع الفرع بدقة', style: TextStyle(color: Joy.textMuted, fontSize: 12))),
            TextButton.icon(
              onPressed: () async {
                final gps = await DeviceLocation.current();
                if (gps == null) { if (context.mounted) toast(context, 'لم يُسمح بالوصول إلى الموقع'); return; }
                setState(() => point = gps);
                _map.move(gps, 16);
              },
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('موقعي'),
            ),
          ]),
        ])),
        // ---- التواصل
        const SectionTitle('التواصل وساعات العمل'),
        JoyCard(child: Column(children: [
          TextField(controller: hours, decoration: const InputDecoration(labelText: 'ساعات العمل', hintText: 'يومياً 9:00 ص – 12:00 م')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف', hintText: '+9665xxxxxxxx')),
          const SizedBox(height: 10),
          TextField(controller: website, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'الموقع الإلكتروني', hintText: 'https://')),
        ])),
        // ---- الهوية
        const SectionTitle('لون العلامة والمميزات'),
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in bizColorPresets)
              InkWell(
                onTap: () => setState(() => color = c),
                borderRadius: BorderRadius.circular(999),
                child: Container(width: 34, height: 34, decoration: BoxDecoration(color: _hex(c), shape: BoxShape.circle, border: Border.all(color: color == c ? Joy.text : Joy.line, width: color == c ? 3 : 1)), child: color == c ? Icon(Icons.check_rounded, size: 18, color: _hex(c).computeLuminance() > .5 ? Joy.text : Colors.white) : null),
              ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in highlights) InputChip(label: Text(h, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12.5)), onDeleted: () => setState(() => highlights.remove(h))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: highlight, decoration: const InputDecoration(hintText: 'ميزة: توصيل، مواقف مجانية، واي فاي…'), onSubmitted: (_) => _addHighlight())),
            IconButton(onPressed: _addHighlight, icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.primary)),
          ]),
        ])),
        if (!isNew) ...[
          const SectionTitle('النشر'),
          JoyCard(child: SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v), title: const Text('الدائرة منشورة'), subtitle: const Text('عند الإيقاف تختفي من القوائم والخريطة ولا تستقبل طلبات، وتبقى بياناتك محفوظة'))),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: busy ? null : _save, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined), label: Text(isNew ? 'إنشاء الدائرة' : 'حفظ التعديلات')),
      ]),
    );
  }

  void _addHighlight() {
    final v = highlight.text.trim();
    if (v.isEmpty) return;
    if (highlights.length >= 12) { toast(context, 'حتى 12 ميزة'); return; }
    setState(() { if (!highlights.contains(v)) highlights.add(v); highlight.clear(); });
  }

  Future<void> _upload({required bool cover}) async {
    try {
      final img = await pickImage();
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (!mounted) return;
      setState(() { if (cover) { coverUrl = up.url; } else { logoUrl = up.url; } });
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _save() async {
    if (nameAr.text.trim().isEmpty && name.text.trim().isEmpty) { toast(context, 'اكتب اسم الدائرة', error: true); return; }
    if (point == null) { toast(context, 'حدّد موقع الفرع على الخريطة', error: true); return; }
    setState(() => busy = true);
    final body = <String, dynamic>{
      'name': name.text.trim().isEmpty ? nameAr.text.trim() : name.text.trim(), 'nameAr': nameAr.text.trim(), 'category': category.key, 'sector': sector.text.trim(), 'description': description.text.trim(),
      'lat': point!.latitude, 'lng': point!.longitude, 'address': address.text.trim(), 'hours': hours.text.trim(), 'phone': phone.text.trim(), 'website': website.text.trim(),
      'color': color, 'highlights': highlights, 'logoUrl': logoUrl, 'coverUrl': coverUrl, if (!isNew) 'active': active,
    };
    try {
      final api = ref.read(apiClientProvider);
      final saved = isNew ? await api.createBiz(body) : await api.updateBiz(b!.id, body);
      invalidateBizAll(ref, saved.id);
      if (!mounted) return;
      toast(context, isNew ? 'أُنشئت دائرتك' : 'حُفظت التعديلات');
      if (isNew) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: saved.id, initial: saved)));
      } else {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

Color _hex(String h) {
  final s = h.replaceFirst('#', '');
  return s.length == 6 ? Color(int.parse('FF$s', radix: 16)) : Joy.primary;
}


/// رسالة خطأ مفهومة لعمليات لوحة التحكم.
String ownerErrText(Object e) {
  final s = e.toString();
  if (s.contains('forbidden')) return 'ليست لديك صلاحية لهذا الإجراء';
  if (s.contains('bad-location')) return 'حدّد موقعاً صحيحاً على الخريطة';
  if (s.contains('bad-name')) return 'اكتب اسم الدائرة';
  if (s.contains('bad-title')) return 'اكتب العنوان';
  if (s.contains('bad-times')) return 'أضف وقت عرض واحداً على الأقل بصيغة 19:30';
  if (s.contains('too-many')) return 'وصلت إلى الحد الأقصى';
  if (s.contains('user-not-found')) return 'لم نجد هذا المستخدم';
  if (s.contains('is-owner')) return 'هذا المستخدم هو المالك أصلاً';
  if (s.contains('already-owned')) return 'لهذه الدائرة مالك بالفعل';
  if (s.contains('code-invalid')) return 'رمز غير صحيح لهذه الدائرة';
  if (s.contains('already-used')) return 'هذا الرمز استُخدم من قبل';
  if (s.contains('already-cancelled')) return 'هذا الطلب ملغى';
  if (s.contains('not-cancellable')) return 'لا يمكن إلغاء هذا الطلب';
  if (s.contains('insufficient-funds')) return 'الرصيد غير كافٍ';
  if (s.contains('admin-only')) return 'هذا الإجراء لمدير النظام فقط';
  return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
}
