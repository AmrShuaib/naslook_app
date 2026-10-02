import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/biz_models.dart';
import '../../api/client.dart';
import '../../api/hotel_api.dart';
import '../../core/app_theme.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../state/hotel_providers.dart';
import '../../state/providers.dart' show profileProvider;
import '../../ui/widgets.dart';
import '../business/business_page.dart' show dayLabel, shortDate;
import '../business/my_bookings_page.dart';

// رحلة «واحد» لحجز غرفة فندقية عبر Nuitee Connect (LiteAPI): بطاقة في الدائرة ← شاشة التواريخ والغرف ← تأكيد ← تذكرة.
// هادئة وقليلة العناصر: زر رئيسي واحد في كل شاشة، صفوف مفتاح/قيمة، وكتلة «تم» بعلامة صح (نموذج التدفقات المعتمد).

/// أسماء المسارات الثلاثة: «العودة إلى الدائرة» تُسقط كل ما يبدأ بـ hotel- فتعود إلى الصفحة التي بدأت الرحلة.
const _routeBook = 'hotel-book', _routeConfirm = 'hotel-confirm', _routeDone = 'hotel-done';
bool _isHotelRoute(Route r) => (r.settings.name ?? '').startsWith('hotel-');

/// يفتح رحلة الحجز لدائرة فندقية مرتبطة.
void openHotelBooking(BuildContext context, {required String bizId, required String title}) =>
    Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: _routeBook), builder: (_) => HotelBookPage(bizId: bizId, title: title)));

/// رسالة خطأ مفهومة لرحلة الحجز؛ 409 = نفد العرض أو تغيّر سعره.
String hotelErrText(Object e) {
  if (e is! ApiException) return e.toString();
  final code = e.body?['error']?.toString() ?? '';
  final msg = e.body?['message']?.toString() ?? '';
  if (e.statusCode == 409 || code == 'offer-unavailable') return 'الغرفة لم تعد متاحة، اختر غيرها';
  return switch (code) {
    'bad-guest' => 'أكمل بيانات الضيف: الاسم والبريد والجوال',
    'bad-card' => 'بيانات البطاقة غير صحيحة: تأكد من الرقم وتاريخ الانتهاء (YYYY-MM)',
    'bad-dates' => 'اختر تاريخي وصول ومغادرة صحيحين (حتى 30 ليلة ولا تاريخ مضى)',
    'bad-guests' => 'عدد البالغين والغرف من 1 إلى 9',
    'not-linked' => 'هذه الدائرة غير مرتبطة بفندق بعد',
    'hotel-disabled' => 'حجز الفنادق غير مفعّل حالياً',
    'provider-error' => msg.isNotEmpty ? 'تعذر إتمام الطلب لدى الفندق: $msg' : 'تعذر الاتصال بالفندق الآن، حاول بعد قليل',
    _ => e.message,
  };
}

String _nightsLabel(int n) => n == 1 ? 'ليلة واحدة' : n == 2 ? 'ليلتان' : '$n ليالٍ';
String _adultsLabel(int n) => n == 1 ? 'بالغ واحد' : n == 2 ? 'بالغان' : '$n بالغين';
String _roomsLabel(int n) => n == 1 ? 'غرفة واحدة' : n == 2 ? 'غرفتان' : '$n غرف';
/// «الخميس 2 أكتوبر» أو «غداً · 2 أكتوبر» من تاريخ السلك.
String _dateText(String ymd) {
  final d = parseHotelDate(ymd);
  if (d == null) return ymd;
  final day = dayLabel(d);
  return day == 'اليوم' || day == 'غداً' ? '$day · ${shortDate(d)}' : day;
}

/// شارة صغيرة «بيئة اختبار» حين يكون مفتاح المزوّد تجريبياً (لا حجز حقيقي).
class _TestChip extends StatelessWidget {
  final String text;
  const _TestChip({super.key, this.text = 'بيئة اختبار'});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(color: Joy.sunText, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// صف مفتاح/قيمة كما في نموذج التدفقات؛ الأخير (الإجمالي) بخط أعرض.
class _Kv extends StatelessWidget {
  final String k, v;
  final bool total;
  const _Kv(this.k, this.v, {this.total = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(color: Joy.textMuted, fontSize: total ? 15 : 13.5)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontWeight: total ? FontWeight.w800 : FontWeight.w600, fontSize: total ? 18 : 14, color: total ? Joy.primary : Joy.text))),
        ]),
      );
}

/// سطر «fine» بقفل: سياسة الإلغاء وطريقة الضمان.
class _FineLine extends StatelessWidget {
  final String text;
  const _FineLine(this.text);
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline_rounded, size: 15, color: Joy.textMuted)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5))),
      ]);
}

/// الزر العريض الوحيد في أسفل الشاشة فوق منطقة الأمان.
class _Footer extends StatelessWidget {
  final Widget child;
  const _Footer({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.viewPaddingOf(context).bottom),
        child: SizedBox(width: double.infinity, child: child),
      );
}

/// عدّاد صغير (البالغون، الغرف) بمفاتيح `<prefix>-minus` و`<prefix>-plus`.
class _Stepper extends StatelessWidget {
  final String prefix, label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.prefix, required this.label, required this.value, required this.onChanged}) : min = 1, max = 9;
  @override
  Widget build(BuildContext context) => Row(key: Key(prefix), children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(key: Key('$prefix-minus'), onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded), color: Joy.primary),
        SizedBox(width: 28, child: Text('$value', key: Key('$prefix-value'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(key: Key('$prefix-plus'), onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded), color: Joy.primary),
      ]);
}

// ------------------------------------------------------------------ بطاقة الدخول في صفحة الدائرة

/// بطاقة بارزة في الدائرة الفندقية المرتبطة بفندق لدى LiteAPI؛ غير المرتبطة لا تعرض شيئاً (غرف الكتالوج تبقى كما هي).
class HotelEntryCard extends ConsumerWidget {
  final Biz biz;
  const HotelEntryCard({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (biz.category != BizCategory.hotel) return const SizedBox.shrink();
    final link = ref.watch(bizHotelProvider(biz.id)).valueOrNull;
    if (link == null || !link.linked) return const SizedBox.shrink();
    void open() => openHotelBooking(context, bizId: biz.id, title: biz.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JoyCard(
        key: const Key('hotel-entry'),
        color: Joy.primarySoft,
        onTap: open,
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.hotel_rounded, color: Joy.primary, size: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('احجز غرفة بأسعار اليوم', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Joy.primary)),
              const SizedBox(height: 2),
              const Text('أسعار وتوفر حقيقيان من الفندق · تأكيد فوري', style: TextStyle(color: Joy.text, fontSize: 12.5, height: 1.4)),
              if (link.isTest) const Padding(padding: EdgeInsets.only(top: 6), child: _TestChip(key: Key('hotel-entry-test'))),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(key: const Key('hotel-entry-book'), style: FilledButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 16)), onPressed: open, child: const Text('احجز')),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ 1) التواريخ والضيوف ثم الغرف

class HotelBookPage extends ConsumerStatefulWidget {
  final String bizId;
  final String title;
  const HotelBookPage({super.key, required this.bizId, required this.title});
  @override
  ConsumerState<HotelBookPage> createState() => _HotelBookPageState();
}

class _HotelBookPageState extends ConsumerState<HotelBookPage> {
  late DateTime checkIn, checkOut;
  int adults = 2, rooms = 1;
  HotelOffers? result;
  Object? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    // الافتراضي: الوصول غداً والمغادرة بعد ليلتين
    final now = DateTime.now();
    checkIn = DateTime(now.year, now.month, now.day + 1);
    checkOut = checkIn.add(const Duration(days: 2));
  }

  int get nights => checkOut.difference(checkIn).inDays;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: checkIn, end: checkOut),
      helpText: 'تاريخا الوصول والمغادرة',
      saveText: 'اعتماد',
    );
    if (range == null || !mounted) return;
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    var e = DateTime(range.end.year, range.end.month, range.end.day);
    if (!e.isAfter(s)) e = s.add(const Duration(days: 1)); // ليلة واحدة على الأقل
    // تواريخ جديدة تُلغي نتائج قديمة حتى لا تُحجز غرفة بتواريخ غير التي تُعرض
    setState(() { checkIn = s; checkOut = e; result = null; error = null; });
  }

  Future<void> _search() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await ref.read(apiClientProvider).hotelOffers(widget.bizId, checkIn: hotelDate(checkIn), checkOut: hotelDate(checkOut), adults: adults, rooms: rooms);
      if (mounted) setState(() => result = r);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _pick(HotelOffer o) {
    final r = result;
    if (r == null) return;
    Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: _routeConfirm), builder: (_) => _ConfirmPage(bizId: widget.bizId, title: widget.title, search: r, offer: o)));
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(bizHotelProvider(widget.bizId)).valueOrNull;
    final hotelName = (link?.hotelName.isNotEmpty ?? false) ? link!.hotelName : widget.title;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text('احجز غرفة · ${widget.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        // الترويسة: الفندق وسطر الثقة
        Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.hotel_rounded, color: Joy.primary, size: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hotelName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const Text('أسعار وتوفر حقيقيان من الفندق · لا يُخصم شيء الآن', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          if (link?.isTest ?? false) const _TestChip(key: Key('hotel-page-test')),
        ]),
        const SizedBox(height: 14),
        JoyCard(child: Column(children: [
          InkWell(
            key: const Key('hotel-dates'),
            borderRadius: BorderRadius.circular(12),
            onTap: _pickDates,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: _DateCol(label: 'الوصول', t: checkIn)),
                Column(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(_nightsLabel(nights), key: const Key('hotel-nights'), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12))),
                  const SizedBox(height: 4),
                  const Icon(Icons.arrow_back_rounded, size: 16, color: Joy.textMuted),
                ]),
                Expanded(child: _DateCol(label: 'المغادرة', t: checkOut, end: true)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_calendar_outlined, size: 18, color: Joy.primary),
              ]),
            ),
          ),
          const Divider(height: 18),
          _Stepper(prefix: 'hotel-adults', label: 'البالغون', value: adults, onChanged: (v) => setState(() { adults = v; result = null; })),
          _Stepper(prefix: 'hotel-rooms', label: 'الغرف', value: rooms, onChanged: (v) => setState(() { rooms = v; result = null; })),
        ])),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('hotel-search'), onPressed: loading ? null : _search, icon: const Icon(Icons.search_rounded, size: 20), label: Text(loading ? 'جارٍ البحث…' : 'اعرض الغرف')),
        const SizedBox(height: 16),
        if (loading) ..._skeleton() else if (error != null) _ErrorCard(text: hotelErrText(error!), onRetry: _search) else if (result != null) ..._results(result!),
      ]),
    );
  }

  List<Widget> _skeleton() => [
        for (var i = 0; i < 3; i++)
          Container(key: i == 0 ? const Key('hotel-loading') : null, height: 108, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(16))),
      ];

  List<Widget> _results(HotelOffers r) {
    if (!r.available || r.offers.isEmpty) {
      return const [EmptyState(key: Key('hotel-empty'), icon: Icons.bedtime_off_outlined, title: 'لا غرف متاحة في هذه التواريخ', subtitle: 'جرّب تواريخ أخرى أو عدداً مختلفاً من الضيوف.')];
    }
    return [
      SectionTitle('الغرف المتاحة · ${r.offers.length}'),
      const SizedBox(height: 4),
      for (final o in r.offers) Padding(padding: const EdgeInsets.only(bottom: 10), child: _OfferCard(offer: o, onPick: () => _pick(o))),
    ];
  }
}

/// عمود تاريخ: اليوم الكبير والشهر ثم «غداً» أو اسم اليوم.
class _DateCol extends StatelessWidget {
  final String label;
  final DateTime t;
  final bool end;
  const _DateCol({required this.label, required this.t, this.end = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(shortDate(t), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(dayLabel(t).split(' ').first, style: const TextStyle(color: Joy.primary, fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}

class _ErrorCard extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _ErrorCard({required this.text, required this.onRetry});
  @override
  Widget build(BuildContext context) => JoyCard(
        key: const Key('hotel-error'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.error_outline_rounded, color: Joy.danger, size: 20), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.5)))]),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة'))),
        ]),
      );
}

/// بطاقة غرفة: الاسم، الأسرّة، الإعاشة، سياسة الإلغاء، والسعر الكبير وزر «اختر».
class _OfferCard extends StatelessWidget {
  final HotelOffer offer;
  final VoidCallback onPick;
  const _OfferCard({required this.offer, required this.onPick});
  @override
  Widget build(BuildContext context) {
    final o = offer;
    final free = o.refundable == true;
    return JoyCard(
      key: Key('hotel-offer-${o.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(o.roomName.isEmpty ? 'غرفة' : o.roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
          if (o.boardType.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(o.boardType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Joy.textMuted))),
        ]),
        if (o.bedsLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [const Icon(Icons.bed_outlined, size: 15, color: Joy.textMuted), const SizedBox(width: 4), Text(o.bedsLine, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))])),
        if (o.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.4))),
        if (o.cancelText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(free ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded, size: 15, color: free ? Joy.success : Joy.textMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(o.cancelText, style: TextStyle(color: free ? Joy.success : Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.priceText, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Joy.primary, height: 1.1)),
            if (o.perNightText.isNotEmpty) Text(o.perNightText, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
          FilledButton(key: Key('hotel-pick-${o.id}'), style: FilledButton.styleFrom(minimumSize: const Size(44, 42), padding: const EdgeInsets.symmetric(horizontal: 22)), onPressed: onPick, child: const Text('اختر')),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ 2) التأكيد: الملخص، الضيف، بطاقة الضمان

class _ConfirmPage extends ConsumerStatefulWidget {
  final String bizId, title;
  final HotelOffers search;
  final HotelOffer offer;
  const _ConfirmPage({required this.bizId, required this.title, required this.search, required this.offer});
  @override
  ConsumerState<_ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends ConsumerState<_ConfirmPage> {
  /// من `/hotel/status`؛ true افتراضياً حتى يصل الرد
  bool cardRequired = true;
  final first = TextEditingController(), last = TextEditingController(), phone = TextEditingController(), email = TextEditingController();
  final cardNumber = TextEditingController(), cardExpiry = TextEditingController(), cardHolder = TextEditingController();
  String title = 'MR', vendor = 'VI';
  bool busy = false, cardPrefilled = false, guestPrefilled = false;

  @override
  void initState() {
    super.initState();
    // ما نعرفه من الجلسة: الاسم الظاهر والبريد
    final s = ref.read(appStateProvider).session;
    _nameFrom(s?.user.displayName);
    if ((s?.email ?? '').isNotEmpty) email.text = s!.email!;
  }

  void _nameFrom(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    if (first.text.isEmpty) first.text = parts.first;
    if (last.text.isEmpty && parts.length > 1) last.text = parts.sublist(1).join(' ');
  }

  @override
  void dispose() {
    for (final c in [first, last, phone, email, cardNumber, cardExpiry, cardHolder]) { c.dispose(); }
    super.dispose();
  }

  /// فحص محلي قبل الطلب حتى لا يرفض الخادم ما يمكن تصحيحه هنا.
  String? _validate() {
    if (first.text.trim().isEmpty || last.text.trim().isEmpty) return 'اكتب الاسم الأول واسم العائلة';
    if (phone.text.trim().length < 7) return 'اكتب رقم الجوال';
    if (!email.text.contains('@')) return 'اكتب بريداً إلكترونياً صحيحاً';
    if (!cardRequired) return null;
    final n = cardNumber.text.replaceAll(RegExp(r'\s+'), '');
    if (n.length < 12 || n.length > 19 || !RegExp(r'^\d+$').hasMatch(n)) return 'رقم البطاقة غير صحيح';
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(cardExpiry.text.trim())) return 'تاريخ الانتهاء بصيغة YYYY-MM مثل 2028-08';
    if (cardHolder.text.trim().isEmpty) return 'اكتب اسم حامل البطاقة';
    return null;
  }

  Future<void> _book() async {
    // الزائر يُدعى للدخول قبل الطلب (الحجز باسم حساب)
    if (!requireAccount(context)) return;
    final bad = _validate();
    if (bad != null) { toast(context, bad, error: true); return; }
    setState(() => busy = true);
    try {
      final b = await ref.read(apiClientProvider).hotelBook(widget.bizId,
          offerId: widget.offer.id, title: title, firstName: first.text, lastName: last.text, phone: phone.text, email: email.text,
          vendorCode: cardRequired ? vendor : null, cardNumber: cardRequired ? cardNumber.text : null, expiry: cardRequired ? cardExpiry.text : null, holderName: cardRequired ? cardHolder.text : null);
      ref.invalidate(myHotelBookingsProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(settings: const RouteSettings(name: _routeDone), builder: (_) => _DonePage(booking: b, title: widget.title)));
    } catch (e) {
      if (mounted) toast(context, hotelErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.search, o = widget.offer;
    // بطاقة الاختبار من الخادم (بيئة الاختبار فقط) تُعبّأ مرة واحدة؛ ومزوّد لا يطلب بطاقة يخفي النموذج كله
    final status = ref.watch(hotelStatusProvider).valueOrNull;
    cardRequired = status?.cardRequired ?? true;
    final test = status?.testCard;
    if (test != null && !cardPrefilled) {
      cardPrefilled = true;
      vendor = test.vendorCode.isEmpty ? vendor : test.vendorCode;
      if (cardNumber.text.isEmpty) cardNumber.text = test.number;
      if (cardExpiry.text.isEmpty) cardExpiry.text = test.expiry;
      if (cardHolder.text.isEmpty) cardHolder.text = test.holderName;
    }
    // الملف الشخصي احتياطاً للاسم حين لا اسم ظاهر في الجلسة
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile != null && !guestPrefilled) {
      guestPrefilled = true;
      if (first.text.isEmpty) _nameFrom(profile.nickname);
    }
    final fine = [if (o.cancelText.isNotEmpty) o.cancelText, if (o.paymentText.isNotEmpty) o.paymentText].join(' · ');
    return Scaffold(
      key: const Key('hotel-confirm'),
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('تأكيد الحجز')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        JoyCard(child: Column(children: [
          _Kv('الفندق', s.hotel.name.isNotEmpty ? s.hotel.name : widget.title),
          _Kv('الغرفة', o.roomName.isEmpty ? 'غرفة' : o.roomName),
          _Kv('الوصول', _dateText(s.checkIn)),
          _Kv('المغادرة', _dateText(s.checkOut)),
          _Kv('الليالي', _nightsLabel(s.nights)),
          _Kv('الضيوف', '${_adultsLabel(s.adults)} · ${_roomsLabel(s.rooms)}'),
          const Divider(height: 14),
          _Kv('الإجمالي', o.priceText, total: true),
        ])),
        if (fine.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 0), child: _FineLine(fine)),
        const SizedBox(height: 16),
        const SectionTitle('الضيف الرئيسي'),
        JoyCard(child: Column(children: [
          Row(children: [
            SizedBox(
              width: 124,
              child: DropdownButtonFormField<String>(
                key: const Key('hotel-title'), initialValue: title, isExpanded: true, decoration: const InputDecoration(labelText: 'اللقب'),
                items: const [DropdownMenuItem(value: 'MR', child: Text('السيد')), DropdownMenuItem(value: 'MS', child: Text('الآنسة')), DropdownMenuItem(value: 'MRS', child: Text('السيدة'))],
                onChanged: (v) => setState(() => title = v ?? title),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(key: const Key('hotel-first'), controller: first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'الاسم الأول'))),
          ]),
          const SizedBox(height: 8),
          TextField(key: const Key('hotel-last'), controller: last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'اسم العائلة')),
          const SizedBox(height: 8),
          TextField(key: const Key('hotel-phone'), controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الجوال', hintText: '+9665…')),
          const SizedBox(height: 8),
          TextField(key: const Key('hotel-email'), controller: email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', helperText: 'يصلك عليه تأكيد الفندق')),
        ])),
        if (!cardRequired)
          // لا بطاقة ضيف: الاختبار يُحاكي الدفع، والحي يحصّل عبر ناس لايف عند التأكيد
          const Padding(key: Key('hotel-no-card'), padding: EdgeInsets.fromLTRB(4, 12, 4, 0), child: _FineLine('لا تحتاج بطاقة الآن: في بيئة الاختبار لا يُحصَّل شيء، وفي الحجز الفعلي يُطلب الدفع عبر ناس لايف عند التأكيد.')),
        if (cardRequired) ...[
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: SectionTitle('بطاقة الضمان')),
          if (test != null) const _TestChip(key: Key('hotel-test-chip'), text: 'بطاقة تجريبية (بيئة اختبار)'),
        ]),
        JoyCard(child: Column(children: [
          DropdownButtonFormField<String>(
            key: const Key('hotel-card-vendor'), initialValue: vendor, isExpanded: true, decoration: const InputDecoration(labelText: 'نوع البطاقة'),
            items: const [DropdownMenuItem(value: 'VI', child: Text('Visa')), DropdownMenuItem(value: 'MC', child: Text('Mastercard')), DropdownMenuItem(value: 'AX', child: Text('American Express')), DropdownMenuItem(value: 'CA', child: Text('Mastercard (CA)'))],
            onChanged: (v) => setState(() => vendor = v ?? vendor),
          ),
          const SizedBox(height: 8),
          TextField(key: const Key('hotel-card-number'), controller: cardNumber, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, autocorrect: false, enableSuggestions: false, style: const TextStyle(fontFamily: 'monospace', fontSize: 15), decoration: const InputDecoration(labelText: 'رقم البطاقة')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(key: const Key('hotel-card-expiry'), controller: cardExpiry, keyboardType: TextInputType.datetime, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الانتهاء', hintText: 'YYYY-MM'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(key: const Key('hotel-card-holder'), controller: cardHolder, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'اسم حامل البطاقة'))),
          ]),
        ])),
        const Padding(padding: EdgeInsets.fromLTRB(4, 10, 4, 0), child: _FineLine('لا يُخصم شيء الآن: البطاقة تُمرَّر إلى الفندق ضماناً للحجز ولا تُحفظ في ناس لايف.')),
        ],
      ]),
      bottomNavigationBar: _Footer(
        child: FilledButton(
          key: const Key('hotel-book'),
          onPressed: busy ? null : _book,
          child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('أكّد الحجز'),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 3) تم الحجز

class _DonePage extends StatelessWidget {
  final HotelBooking booking;
  final String title;
  const _DonePage({required this.booking, required this.title});

  void _backToCircle(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst || !_isHotelRoute(r));

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final confirmed = b.status == 'confirmed';
    final hotel = b.hotelName.isNotEmpty ? b.hotelName : title;
    return Scaffold(
      key: const Key('hotel-done'),
      backgroundColor: Joy.bg,
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('تم الحجز'), actions: [IconButton(key: const Key('hotel-close'), tooltip: 'إغلاق', onPressed: () => _backToCircle(context), icon: const Icon(Icons.close_rounded))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
        // كتلة «تم» بعلامة صح
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: confirmed ? const Color(0xFFE3F6EA) : Joy.sunSoft, shape: BoxShape.circle), child: Icon(confirmed ? Icons.check_rounded : Icons.hourglass_top_rounded, color: confirmed ? Joy.success : Joy.sunText, size: 38)),
          const SizedBox(height: 10),
          Text(confirmed ? 'تم الحجز' : 'استلم الفندق طلبك', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 4),
          Text('$hotel · ${_dateText(b.checkIn)} ← ${_dateText(b.checkOut)}', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.5)),
        ]),
        const SizedBox(height: 18),
        // رقم التأكيد كبيراً وسط صندوق
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            const Text('رقم التأكيد', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            const SizedBox(height: 4),
            SelectableText(b.confirmation.isNotEmpty ? b.confirmation : (b.orderId.isNotEmpty ? b.orderId : '—'), key: const Key('hotel-confirmation'), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: confirmed ? const Color(0xFFE3F6EA) : Joy.sunSoft, borderRadius: BorderRadius.circular(999)), child: Text(b.statusLabel, key: const Key('hotel-done-status'), style: TextStyle(color: confirmed ? Joy.success : Joy.sunText, fontSize: 12, fontWeight: FontWeight.w700))),
              if (b.isTest) const _TestChip(key: Key('hotel-done-test')),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        JoyCard(child: Column(children: [
          _Kv('الضيف', b.guestName),
          if (b.roomName.isNotEmpty) _Kv('الغرفة', b.roomName),
          _Kv('الضيوف', '${_adultsLabel(b.adults)} · ${_roomsLabel(b.rooms)} · ${_nightsLabel(b.nights)}'),
          _Kv('الإجمالي', b.priceText, total: true),
        ])),
        if (b.cancelText.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 0), child: _FineLine(b.cancelText)),
        const Padding(padding: EdgeInsets.fromLTRB(4, 6, 4, 0), child: Text('الدفع في الفندق عند الوصول بحسب سياسته. تجد الحجز دائماً في «حجوزاتي».', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5))),
        const SizedBox(height: 16),
        OutlinedButton.icon(key: const Key('hotel-go-bookings'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage())), icon: const Icon(Icons.receipt_long_outlined, size: 18), label: const Text('حجوزاتي')),
      ]),
      bottomNavigationBar: _Footer(child: FilledButton(key: const Key('hotel-back'), onPressed: () => _backToCircle(context), child: const Text('العودة إلى الدائرة'))),
    );
  }
}
