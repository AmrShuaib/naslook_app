import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/map_pick_page.dart';
import '../../ui/widgets.dart';

/// مصدر موقع الفعالية: موقع الجهاز (الافتراضي)، أو آخر موقع لك على الخريطة حين يتعذّر موقع الجهاز، أو نقطة اختارها المنشئ.
enum EventPointSource { locating, device, presence, map, none }

/// إنشاء فعالية: العنوان والوصف والموعد والمكان (اسمه ونقطته) والتذكرة. النقطة تبدأ بموقع الجهاز ويغيّرها المنشئ بـ«حدد على الخريطة»،
/// لأن الفعالية تُرسم على الخريطة وفي «الصف» بإحداثياتها لا بموقع من أنشأها لحظة النشر.
class EventCreatePage extends ConsumerStatefulWidget {
  const EventCreatePage({super.key});

  /// يفتح النموذج ويعيد الفعالية المنشأة، أو null إن رجع المستخدم.
  static Future<Event?> open(BuildContext context) => Navigator.of(context).push<Event>(MaterialPageRoute(builder: (_) => const EventCreatePage()));

  @override
  ConsumerState<EventCreatePage> createState() => _EventCreatePageState();
}

class _EventCreatePageState extends ConsumerState<EventCreatePage> {
  final title = TextEditingController(), desc = TextEditingController(), place = TextEditingController();
  final tierName = TextEditingController(text: 'عادي'), tierPrice = TextEditingController(text: '0'), tierQty = TextEditingController(text: '50');
  DateTime starts = DateTime.now().add(const Duration(days: 1));
  LatLng? point;
  EventPointSource source = EventPointSource.locating;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_useDevice());
  }

  @override
  void dispose() {
    for (final c in [title, desc, place, tierName, tierPrice, tierQty]) {
      c.dispose();
    }
    super.dispose();
  }

  /// موقع الجهاز الفعلي (لا مركز جدة الذي يعيده التصفح خارج منطقة الخدمة)، وإلا آخر موقع للمستخدم على الخريطة.
  Future<void> _useDevice() async {
    setState(() => source = EventPointSource.locating);
    final gps = await DeviceLocation.current();
    if (!mounted) return;
    if (gps != null) {
      setState(() { point = gps; source = EventPointSource.device; });
      return;
    }
    LatLng? fallback;
    try {
      final pres = await ref.read(myPresenceProvider.future).timeout(const Duration(seconds: 5));
      if (pres.lat != null && pres.lng != null) fallback = LatLng(pres.lat!, pres.lng!);
    } catch (_) { /* بلا حضور على الخريطة: يبقى بلا نقطة حتى يحددها على الخريطة */ }
    if (!mounted) return;
    setState(() { point = fallback; source = fallback == null ? EventPointSource.none : EventPointSource.presence; });
  }

  Future<void> _pickOnMap() async {
    final p = await MapPickPage.open(context, initial: point, title: 'مكان الفعالية');
    if (p == null || !mounted) return;
    setState(() { point = p; source = EventPointSource.map; });
  }

  String get _sourceLabel => switch (source) {
        EventPointSource.locating => 'نحدد موقعك…',
        EventPointSource.device => 'موقعك الحالي',
        EventPointSource.presence => 'آخر موقع لك على الخريطة',
        EventPointSource.map => 'نقطة حددتها على الخريطة',
        EventPointSource.none => 'لم يُحدَّد موقع بعد',
      };

  static String _errText(Object e) {
    final body = e is ApiException ? e.body : null;
    final code = body?['error']?.toString();
    return switch (code) {
      'place-required' => 'التذكرة المدفوعة لفعالية في مكان: اكتب اسم المكان أو حدده على الخريطة',
      'bad-location' => 'الموقع غير صالح؛ حدده على الخريطة مرة أخرى',
      'bad-title' => 'اكتب عنوان الفعالية',
      'bad-date' => 'اختر موعداً صحيحاً',
      'banned-words' => 'في النص كلمة غير مسموح بها',
      'suspended' => 'حسابك موقوف مؤقتاً',
      _ => e is ApiException ? e.message : e.toString(),
    };
  }

  Future<void> _submit() async {
    if (title.text.trim().isEmpty) { toast(context, 'اكتب عنوان الفعالية', error: true); return; }
    setState(() => busy = true);
    try {
      final p = point;
      final ev = await ref.read(apiClientProvider).createEvent({
        'title': title.text.trim(), 'description': desc.text.trim(), 'placeName': place.text.trim(), 'startsAt': starts.toUtc().toIso8601String(),
        if (p != null) ...{'lat': p.latitude, 'lng': p.longitude},
        'tiers': [{'name': tierName.text.trim(), 'price': ((double.tryParse(tierPrice.text) ?? 0) * 100).round(), 'quantity': int.tryParse(tierQty.text) ?? 50}],
      });
      if (mounted) Navigator.of(context).pop(ev);
    } catch (e) {
      if (mounted) toast(context, _errText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = point;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('فعالية جديدة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        TextField(key: const Key('ev-title'), controller: title, decoration: const InputDecoration(labelText: 'العنوان'), autofocus: true),
        const SizedBox(height: 10),
        TextField(key: const Key('ev-desc'), controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 10),
        ListTile(
          key: const Key('ev-when'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded, color: Joy.primary),
          title: Text(_when(starts)),
          onTap: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: starts);
            if (d == null || !context.mounted) return;
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(starts));
            if (t == null) return;
            setState(() => starts = DateTime(d.year, d.month, d.day, t.hour, t.minute));
          },
        ),
        const SizedBox(height: 6),
        // ---- المكان: اسمه كما يُعرض، ونقطته على الخريطة
        const Text('المكان', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(key: const Key('ev-place'), controller: place, decoration: const InputDecoration(labelText: 'اسم المكان', hintText: 'مثل: ممشى الكورنيش، بوابة 3')),
        const SizedBox(height: 8),
        JoyCard(
          key: const Key('ev-location'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(source == EventPointSource.map ? Icons.push_pin_rounded : Icons.my_location_rounded, color: p == null ? Joy.textMuted : Joy.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_sourceLabel, key: const Key('ev-location-source'), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p != null)
                  Text('${p.latitude.toStringAsFixed(5)}، ${p.longitude.toStringAsFixed(5)}', textDirection: TextDirection.ltr, style: const TextStyle(color: Joy.textMuted, fontSize: 12))
                else if (source == EventPointSource.none)
                  const Text('حدده على الخريطة ليظهر مكان الفعالية للناس', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
              ])),
              if (source == EventPointSource.locating) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonalIcon(key: const Key('ev-pick-map'), onPressed: _pickOnMap, icon: const Icon(Icons.map_outlined, size: 18), label: const Text('حدد على الخريطة')),
              if (source != EventPointSource.device && source != EventPointSource.locating)
                TextButton.icon(key: const Key('ev-use-device'), onPressed: _useDevice, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('موقعي الحالي')),
            ]),
          ]),
        ),
        const Divider(height: 28),
        const Text('التذكرة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(key: const Key('ev-tier-name'), controller: tierName, decoration: const InputDecoration(labelText: 'اسم الفئة')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(key: const Key('ev-tier-price'), controller: tierPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ر.س)', helperText: '0 = مجانية'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const Key('ev-tier-qty'), controller: tierQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد'))),
        ]),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('ev-create'),
          onPressed: busy ? null : _submit,
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
          label: const Text('إنشاء الفعالية'),
        ),
      ]),
    );
  }

  static String _when(DateTime t) {
    const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} · ${clockOf(t)}';
  }
}
