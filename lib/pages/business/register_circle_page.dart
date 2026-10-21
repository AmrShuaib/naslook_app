import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/location.dart';
import '../../core/media/pick_image.dart';
import '../../core/share/share_links.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../ui/widgets.dart';
import 'owner/business_dashboard_page.dart';
import 'owner/verify_circle_page.dart';

/// يفتح معالج تسجيل الدائرة (ست خطوات، سؤال واحد في كل شاشة).
Future<void> openRegisterCircle(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterCirclePage()));

/// كود الخطأ من جسم الرد إن وُجد مع نص الاستثناء (العميل قد يترجم الكود فلا يبقى في النص).
String _errCode(Object e) => '${e is ApiException ? (e.body?['error'] ?? '') : ''} $e';

/// رسالة مفهومة لأخطاء التسجيل (أكواد عقد POST /biz/register).
String registerErrText(Object e) {
  final s = _errCode(e);
  if (s.contains('bad-category')) return 'اختر نوع النشاط';
  if (s.contains('bad-name')) return 'اكتب اسماً عربياً من حرفين إلى 60 حرفاً';
  if (s.contains('logo-required')) return 'الشعار إلزامي: ارفع صورة شعار دائرتك';
  if (s.contains('bad-presence')) return 'اختر طريقة الحضور: مكان ثابت أو أذهب إلى العميل';
  if (s.contains('bad-location')) return 'حدّد موقع الدائرة';
  if (s.contains('bad-radius')) return 'نطاق الخدمة بين 2 و50 كم';
  if (s.contains('bad-phone')) return 'رقم الجوال غير صحيح؛ اكتبه بصيغة 05XXXXXXXX';
  if (s.contains('bad-role')) return 'اختر صفتك: صاحب النشاط أو مدير مفوض';
  if (s.contains('too-many')) return 'وصلت إلى الحد الأقصى من الدوائر (20)';
  if (s.contains('suspended')) return 'حسابك موقوف فلا يمكنه تسجيل دائرة';
  if (e is ApiException) return e.message;
  return s;
}

/// الخطوة التي يعود إليها المعالج حين يرفض الخادم حقلاً.
int? registerErrStep(Object e) {
  final s = _errCode(e);
  if (s.contains('bad-category')) return 0;
  if (s.contains('bad-name')) return 1;
  if (s.contains('logo-required')) return 2;
  if (s.contains('bad-presence') || s.contains('bad-location') || s.contains('bad-radius')) return 3;
  if (s.contains('bad-phone')) return 4;
  if (s.contains('bad-role')) return 5;
  return null;
}

/// ترتيب الفئات في المعالج: الأنشطة المحلية الشائعة أولاً.
const registerCategories = [
  BizCategory.cafe, BizCategory.restaurant, BizCategory.shop, BizCategory.services, BizCategory.salon, BizCategory.clinic, BizCategory.entertainment,
  BizCategory.brand, BizCategory.hotel, BizCategory.carRental, BizCategory.cinema, BizCategory.hospital, BizCategory.company, BizCategory.university, BizCategory.airport, BizCategory.other,
];

const _steps = 6;

/// معالج التسجيل: النوع ← الاسم (مع فحص التكرار) ← الشعار (إلزامي) ← الحضور (ثابت أو متنقل) ← الجوال ← الصفة ← «دائرتك جاهزة».
class RegisterCirclePage extends ConsumerStatefulWidget {
  const RegisterCirclePage({super.key});
  @override
  ConsumerState<RegisterCirclePage> createState() => _RegisterCirclePageState();
}

class _RegisterCirclePageState extends ConsumerState<RegisterCirclePage> {
  int step = 0; // 0..5 خطوات، 6 = جاهزة، 7 = طلب استلام قيد المراجعة
  BizCategory? category;
  final nameAr = TextEditingController(), name = TextEditingController(), phone = TextEditingController(), district = TextEditingController();
  Timer? _debounce;
  List<RegisterDuplicate> dups = const [];
  bool checking = false, uploading = false, locating = false, busy = false;
  String? logoUrl, locError, phoneError, claimedName;
  String presence = 'fixed', role = 'owner';
  LatLng? point;
  double radiusKm = 15;
  final districts = <String>[];
  Registered? result;

  @override
  void initState() {
    super.initState();
    nameAr.addListener(_onNameChanged);
    // الكتابة تمسح الخطأ وتعيد بناء زر «التالي» (يُفعَّل حين يُكتب رقم)
    phone.addListener(() => setState(() => phoneError = null));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [nameAr, name, phone, district]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- الاسم: فحص التكرار بعد 600 مللي ثانية من آخر حرف
  void _onNameChanged() {
    setState(() {});
    _debounce?.cancel();
    final n = nameAr.text.trim();
    if (n.length < 2) { if (dups.isNotEmpty) setState(() => dups = const []); return; }
    _debounce = Timer(const Duration(milliseconds: 600), () => _check(n));
  }

  /// موقع للفحص بلا طلب إذن: آخر موقع معروف، أو تحديد جديد فقط إن كان الإذن ممنوحاً من قبل.
  /// طلب الإذن نفسه يُترك لخطوة الحضور (4) حيث يُشرح سببه؛ وبلا موقع يفحص الخادم الاسم بلا تصفية بالمسافة.
  static Future<LatLng?> knownLocation() async {
    final l = DeviceLocation.last;
    if (l != null) return l;
    if (DeviceLocation.status != LocationStatus.granted) return null;
    return DeviceLocation.current(precise: false, timeout: const Duration(seconds: 3));
  }

  Future<void> _check(String n) async {
    setState(() => checking = true);
    try {
      final loc = await knownLocation();
      final r = await ref.read(apiClientProvider).registerCheck(n, lat: loc?.latitude, lng: loc?.longitude);
      if (!mounted || nameAr.text.trim() != n) return;
      setState(() => dups = r.duplicates);
    } catch (_) {
      // فحص التكرار مساعد فقط؛ فشله لا يوقف التسجيل
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _claim(RegisterDuplicate d) async {
    final note = await askText(context, title: 'استلام ${d.title}', hint: 'عرّف بنفسك وصلتك بالنشاط', initial: 'أنا صاحب نشاط ${d.title} وأطلب استلام دائرته', confirm: 'إرسال الطلب');
    if (note == null || !mounted) return;
    try {
      final status = await ref.read(apiClientProvider).claimBiz(d.id, note: note.trim());
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(bizDetailProvider(d.id));
      if (!mounted) return;
      if (status == 'approved') {
        toast(context, 'أصبحت مالك الدائرة');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: d.id)));
        return;
      }
      setState(() { claimedName = d.title; step = 7; });
    } catch (e) {
      if (mounted) toast(context, registerErrText(e), error: true);
    }
  }

  // ---- الشعار
  Future<void> _uploadLogo({required bool camera}) async {
    try {
      final img = await pickImage(camera: camera);
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => logoUrl = up.url);
    } catch (e) {
      if (mounted) toast(context, registerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  // ---- الموقع
  Future<void> _locate({bool browse = false}) async {
    setState(() { locating = true; locError = null; });
    final gps = browse ? await DeviceLocation.browse() : await DeviceLocation.current();
    if (!mounted) return;
    setState(() {
      locating = false;
      if (gps != null) {
        point = gps;
      } else if (browse) {
        point = DeviceLocation.jeddah;
      } else {
        locError = 'لم يُسمح بالوصول إلى الموقع؛ حدّده على الخريطة';
      }
    });
  }

  Future<void> _pickOnMap() async {
    final p = await Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => _MapPickPage(initial: point ?? DeviceLocation.lastBrowse ?? DeviceLocation.jeddah)));
    if (p != null && mounted) setState(() { point = p; locError = null; });
  }

  void _addDistrict() {
    final v = district.text.trim();
    if (v.isEmpty) return;
    if (districts.length >= 10) { toast(context, 'حتى 10 أحياء'); return; }
    setState(() { if (!districts.contains(v)) districts.add(v); district.clear(); });
  }

  // ---- التنقل
  bool get canNext => switch (step) {
        0 => category != null,
        1 => nameAr.text.trim().length >= 2,
        2 => logoUrl != null && !uploading,
        3 => point != null,
        4 => phone.text.trim().isNotEmpty,
        _ => !busy,
      };

  void _next() {
    if (step == 4 && normalizeSaudiMobile(phone.text) == null) {
      setState(() => phoneError = 'رقم جوال سعودي غير صحيح');
      return;
    }
    if (step == 5) { _submit(); return; }
    setState(() => step++);
  }

  void _back() {
    if (step == 0) { Navigator.of(context).pop(); return; }
    setState(() => step--);
  }

  Future<void> _submit() async {
    final mobile = normalizeSaudiMobile(phone.text);
    final p = point;
    if (category == null || logoUrl == null || p == null || mobile == null) return;
    setState(() => busy = true);
    final body = <String, dynamic>{
      'category': category!.key,
      'nameAr': nameAr.text.trim(),
      if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
      'logoUrl': logoUrl,
      'presence': presence,
      'lat': p.latitude,
      'lng': p.longitude,
      if (presence == 'mobile') 'radiusKm': radiusKm.round(),
      if (presence == 'mobile' && districts.isNotEmpty) 'districts': List.of(districts),
      'phone': mobile,
      'role': role,
    };
    try {
      final r = await ref.read(apiClientProvider).registerBiz(body);
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(mapBizProvider);
      ref.invalidate(bizListProvider);
      if (!mounted) return;
      setState(() { result = r; step = 6; });
    } catch (e) {
      if (!mounted) return;
      toast(context, registerErrText(e), error: true);
      final s = registerErrStep(e);
      if (s != null) setState(() => step = s);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step == 6 && result != null) return _DonePage(result: result!);
    if (step == 7) return _ClaimedPage(name: claimedName ?? '');
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        leading: IconButton(key: const Key('reg-back'), tooltip: 'رجوع', icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
        title: const Text('سجّل دائرتك'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: (step + 1) / _steps, minHeight: 6, backgroundColor: Joy.surface2, color: Joy.primary))),
              const SizedBox(width: 10),
              Text('${step + 1} من $_steps', key: const Key('reg-progress'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              key: ValueKey('reg-step-$step'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              children: switch (step) { 0 => _stepCategory(), 1 => _stepName(), 2 => _stepLogo(), 3 => _stepPresence(), 4 => _stepPhone(), _ => _stepRole() },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key(step == 5 ? 'reg-submit' : 'reg-next'),
                onPressed: canNext ? _next : null,
                icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(step == 5 ? Icons.check_rounded : Icons.arrow_forward_rounded),
                label: Text(step == 5 ? 'سجّل الدائرة' : 'التالي'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _title(String t, [String? hint]) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontFamily: AppTheme.displayFont, fontWeight: FontWeight.w700, fontSize: 22)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.5))),
        ]),
      );

  // ---- 1) نوع النشاط
  List<Widget> _stepCategory() => [
        _title('ما نوع نشاطك؟', 'يحدّد شكل الكتالوج: منتجات، مواعيد، تذاكر…'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in registerCategories)
            SizedBox(
              width: 108,
              child: _PickCard(key: Key('reg-cat-${c.key}'), selected: category == c, icon: c.icon, title: c.label, onTap: () => setState(() => category = c)),
            ),
        ]),
      ];

  // ---- 2) الاسم مع فحص التكرار
  List<Widget> _stepName() => [
        _title('ما اسم دائرتك؟', 'الاسم كما يعرفه عملاؤك. نفحص إن كانت دائرتك موجودة أصلاً حتى لا تُنشأ مرتين.'),
        TextField(key: const Key('reg-name'), controller: nameAr, autofocus: true, maxLength: 60, textInputAction: TextInputAction.next, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600), decoration: const InputDecoration(labelText: 'الاسم بالعربية', hintText: 'قهوة المرسى')),
        const SizedBox(height: 6),
        TextField(key: const Key('reg-name-latin'), controller: name, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'الاسم اللاتيني (اختياري)', hintText: 'Marsa Coffee')),
        if (checking) const Padding(padding: EdgeInsets.only(top: 12), child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('نفحص الدوائر القريبة…', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))])),
        if (dups.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionTitle('هل هذه دائرتك؟'),
          for (final d in dups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JoyCard(
                key: Key('reg-dup-${d.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(d.category.icon, color: Joy.primary)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                      Text('${d.category.label}${d.distanceLabel != null ? ' · على بعد ${d.distanceLabel}' : ''}${d.claimable ? '' : ' · لها مالك'}', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
                    ])),
                    if (!d.claimable) const Icon(Icons.lock_outline_rounded, color: Joy.textMuted, size: 18),
                  ]),
                  // زر الاستلام بعرض البطاقة: بجانب النص يسرق عرض الهاتف
                  if (d.claimable) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(key: Key('reg-claim-${d.id}'), onPressed: () => _claim(d), icon: const Icon(Icons.verified_user_outlined, size: 18), label: const Text('هذه دائرتي، استلمها')),
                  ],
                ]),
              ),
            ),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('إن لم تكن أيّاً منها تابع التسجيل بالاسم نفسه.', style: TextStyle(color: Joy.textMuted, fontSize: 12))),
        ],
      ];

  // ---- 3) الشعار الإلزامي
  List<Widget> _stepLogo() => [
        _title('شعار دائرتك', 'إلزامي: يظهر على الخريطة وفي القوائم. صورة مربعة واضحة أفضل.'),
        Center(
          child: Container(
            key: const Key('reg-logo-preview'),
            width: 132, height: 132,
            decoration: BoxDecoration(color: logoUrl == null ? Joy.surface2 : Joy.surface, borderRadius: BorderRadius.circular(36), border: Border.all(color: logoUrl == null ? Joy.line : Joy.primary, width: 2)),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: uploading
                ? const CircularProgressIndicator()
                : logoUrl == null
                    ? const Icon(Icons.add_a_photo_outlined, color: Joy.textMuted, size: 40)
                    : Image.network(thumbUrl(logoUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.check_circle_rounded, color: Joy.success, size: 48)),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const Key('reg-logo-pick'), onPressed: uploading ? null : () => _uploadLogo(camera: false), icon: const Icon(Icons.photo_library_outlined, size: 18), label: Text(logoUrl == null ? 'من الجهاز' : 'تغيير'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(key: const Key('reg-logo-camera'), onPressed: uploading ? null : () => _uploadLogo(camera: true), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('الكاميرا'))),
        ]),
        if (logoUrl == null) const Padding(padding: EdgeInsets.only(top: 10), child: Text('لا يمكن المتابعة قبل رفع الشعار.', key: Key('reg-logo-required'), style: TextStyle(color: Joy.accent, fontSize: 12.5, fontWeight: FontWeight.w600))),
      ];

  // ---- 4) الحضور: مكان ثابت أو متنقل
  List<Widget> _stepPresence() {
    final p = point;
    return [
      _title('أين يجدك العملاء؟'),
      Row(children: [
        Expanded(child: _PickCard(key: const Key('reg-presence-fixed'), selected: presence == 'fixed', icon: Icons.storefront_rounded, title: 'مكان ثابت', subtitle: 'محل أو مكتب أو عيادة بعنوان', onTap: () => setState(() => presence = 'fixed'))),
        const SizedBox(width: 10),
        Expanded(child: _PickCard(key: const Key('reg-presence-mobile'), selected: presence == 'mobile', icon: Icons.directions_car_filled_rounded, title: 'أذهب إلى العميل', subtitle: 'خدمة متنقلة ضمن نطاق', onTap: () { setState(() => presence = 'mobile'); if (point == null) _locate(browse: true); })),
      ]),
      const SizedBox(height: 14),
      if (presence == 'fixed') ...[
        FilledButton.tonalIcon(key: const Key('reg-locate'), onPressed: locating ? null : () => _locate(), icon: locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 18), label: const Text('أنا في المكان الآن')),
      ] else ...[
        FilledButton.tonalIcon(key: const Key('reg-locate'), onPressed: locating ? null : () => _locate(browse: true), icon: locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 18), label: const Text('مركز نطاقي: موقعي الآن')),
      ],
      if (locError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(locError!, key: const Key('reg-loc-error'), style: const TextStyle(color: Joy.danger, fontSize: 12.5))),
      const SizedBox(height: 10),
      // الزر تحت النص لا بجانبه: بجانبه يسرق عرض الشاشة الضيقة ويلفّ النص حرفاً حرفاً
      JoyCard(
        key: const Key('reg-point'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(p == null ? Icons.location_off_outlined : Icons.location_on_rounded, color: p == null ? Joy.textMuted : Joy.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(p == null ? 'لم يُحدَّد الموقع بعد' : '${presence == 'fixed' ? 'الموقع' : 'المركز'}: ${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}', style: const TextStyle(fontSize: 13.5))),
          ]),
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(key: const Key('reg-map-edit'), onPressed: _pickOnMap, icon: const Icon(Icons.map_outlined, size: 16), label: const Text('تعديل على الخريطة'))),
        ]),
      ),
      if (presence == 'mobile') ...[
        const SectionTitle('نطاق الخدمة'),
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${radiusKm.round()} كم حول المركز', key: const Key('reg-radius-label'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(key: const Key('reg-radius'), value: radiusKm, min: 2, max: 50, divisions: 48, label: '${radiusKm.round()} كم', onChanged: (v) => setState(() => radiusKm = v)),
          const Text('الأحياء التي تخدمها (اختياري)', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final d in districts) InputChip(key: Key('reg-district-$d'), label: Text(d, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12.5)), onDeleted: () => setState(() => districts.remove(d)))]),
          Row(children: [
            Expanded(child: TextField(key: const Key('reg-district'), controller: district, decoration: const InputDecoration(hintText: 'الروضة، الشاطئ، النزهة…'), onSubmitted: (_) => _addDistrict())),
            IconButton(key: const Key('reg-district-add'), onPressed: _addDistrict, icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.primary)),
          ]),
        ])),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('الدائرة المتنقلة بلا دبوس ثابت: تظهر لمن داخل نطاقك، وبزر «أنا هنا اليوم» تضع دبوساً مؤقتاً أينما كنت.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5))),
      ],
    ];
  }

  // ---- 5) الجوال
  List<Widget> _stepPhone() => [
        _title('رقم جوال النشاط', 'يظهر للعملاء على صفحة الدائرة ويُخزَّن بصيغة ‎+966. توثيقه برسالة نصية قريباً.'),
        TextField(
          key: const Key('reg-phone'),
          controller: phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(labelText: 'الجوال', hintText: '05XXXXXXXX', prefixIcon: const Icon(Icons.phone_android_rounded, color: Joy.textMuted), errorText: phoneError),
          onSubmitted: (_) => canNext ? _next() : null,
        ),
      ];

  // ---- 6) الصفة
  List<Widget> _stepRole() => [
        _title('ما صفتك في النشاط؟'),
        Row(children: [
          Expanded(child: _PickCard(key: const Key('reg-role-owner'), selected: role == 'owner', icon: Icons.person_rounded, title: 'صاحب النشاط', subtitle: 'المالك أو الشريك', onTap: () => setState(() => role = 'owner'))),
          const SizedBox(width: 10),
          Expanded(child: _PickCard(key: const Key('reg-role-manager'), selected: role == 'manager', icon: Icons.badge_rounded, title: 'مدير مفوض', subtitle: 'أدير النشاط نيابة عن صاحبه', onTap: () => setState(() => role = 'manager'))),
        ]),
        const SizedBox(height: 16),
        const SectionTitle('الملخص'),
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv('النوع', category?.label ?? '—'),
          _kv('الاسم', nameAr.text.trim()),
          _kv('الحضور', presence == 'fixed' ? 'مكان ثابت' : 'متنقل · ${radiusKm.round()} كم'),
          _kv('الجوال', normalizeSaudiMobile(phone.text) ?? phone.text),
        ])),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('بعد التسجيل تظهر دائرتك على الخريطة فوراً. البيع والحجز يُفتحان بعد توثيق السجل التجاري أو وثيقة العمل الحر.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5))),
      ];

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [SizedBox(width: 80, child: Text(k, style: const TextStyle(color: Joy.textMuted, fontSize: 13))), Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)))]),
      );
}

/// بطاقة اختيار (فئة، حضور، صفة).
class _PickCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _PickCard({super.key, required this.selected, required this.icon, required this.title, this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: selected ? Joy.primarySoft : Joy.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? Joy.primary : Joy.line, width: selected ? 1.5 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 22, color: selected ? Joy.primary : Joy.textMuted), const Spacer(), if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: Joy.primary)]),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? Joy.primary : Joy.text)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5, height: 1.4)),
          ]),
        ),
      );
}

/// اختيار النقطة على الخريطة (يُبنى عند الطلب فقط).
class _MapPickPage extends ConsumerStatefulWidget {
  final LatLng initial;
  const _MapPickPage({required this.initial});
  @override
  ConsumerState<_MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends ConsumerState<_MapPickPage> {
  late LatLng point = widget.initial;
  final _map = MapController();
  @override
  Widget build(BuildContext context) {
    final base = ref.read(apiClientProvider).baseUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('حدّد الموقع'), actions: [
        TextButton.icon(onPressed: () async { final g = await DeviceLocation.current(); if (g == null) { if (context.mounted) toast(context, 'لم يُسمح بالوصول إلى الموقع'); return; } setState(() => point = g); _map.move(g, 16); }, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('موقعي')),
      ]),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: point, initialZoom: 15, onTap: (_, p) => setState(() => point = p), interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
        children: [
          TileLayer(urlTemplate: '$base/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
          MarkerLayer(markers: [Marker(point: point, width: 40, height: 40, child: const Icon(Icons.location_on_rounded, color: Joy.accent, size: 40))]),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.of(context).pop(point), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.check_rounded), label: const Text('تأكيد الموقع')),
    );
  }
}

/// «دائرتك جاهزة»: الرابط ورمز QR وثلاثة مخارج.
class _DonePage extends StatelessWidget {
  final Registered result;
  const _DonePage({required this.result});
  @override
  Widget build(BuildContext context) {
    final b = result.biz;
    final url = circleLink(b.id);
    return Scaffold(
      key: const Key('reg-done'),
      backgroundColor: Joy.bg,
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('دائرتك جاهزة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
        const Center(child: Icon(Icons.check_circle_rounded, color: Joy.success, size: 64)),
        const SizedBox(height: 10),
        const Text('دائرتك جاهزة وتظهر على الخريطة الآن', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.displayFont, fontWeight: FontWeight.w700, fontSize: 21)),
        const SizedBox(height: 4),
        Text(b.title, textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 14)),
        const SizedBox(height: 16),
        Center(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Joy.line)), child: QrImageView(key: const Key('reg-qr'), data: url, size: 160))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.link_rounded, size: 18, color: Joy.textMuted),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(url, key: const Key('reg-link'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600))),
            IconButton(key: const Key('reg-share'), tooltip: 'مشاركة', icon: const Icon(Icons.ios_share_rounded, size: 20), onPressed: () => shareLink(context, title: b.title, url: url, subtitle: 'دائرة ${b.category.label} على ناس لايف', code: circleCode(b.id))),
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(key: const Key('reg-done-dashboard'), onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: b.id, initial: b))), icon: const Icon(Icons.dashboard_customize_outlined), label: const Text('أكمل بيانات الدائرة')),
        const SizedBox(height: 8),
        OutlinedButton.icon(key: const Key('reg-done-verify'), onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VerifyCirclePage(bizId: b.id, initial: b))), icon: const Icon(Icons.verified_user_outlined), label: const Text('وثّق دائرتك لتبدأ البيع')),
        const SizedBox(height: 8),
        TextButton(key: const Key('reg-done-close'), onPressed: () => Navigator.of(context).pop(), child: const Text('اكتفيت الآن')),
        const SizedBox(height: 8),
        Text('الاكتمال الآن ${result.completeness.percent}٪ · البيع والحجز يُفتحان بعد التوثيق.', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
      ]),
    );
  }
}

/// طلب استلام دائرة موجودة أُرسل من داخل المعالج.
class _ClaimedPage extends StatelessWidget {
  final String name;
  const _ClaimedPage({required this.name});
  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('reg-claimed'),
        backgroundColor: Joy.bg,
        appBar: AppBar(automaticallyImplyLeading: false, title: const Text('طلب الاستلام')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: EmptyState(
            icon: Icons.hourglass_top_rounded,
            title: 'طلبك قيد المراجعة',
            subtitle: 'سيراجع فريق ناس لايف طلب استلام «$name» ويخبرك بإشعار عند القرار.',
            action: FilledButton(key: const Key('reg-claimed-close'), onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً')),
          ),
        ),
      );
}
