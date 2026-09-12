import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../wallet/wallet_page.dart';

final eventsProvider = FutureProvider<List<Event>>((ref) => ref.watch(apiClientProvider).events());
final myEventsProvider = FutureProvider<List<Event>>((ref) => ref.watch(apiClientProvider).events(mine: true));
final eventProvider = FutureProvider.family<Event, String>((ref, id) => ref.watch(apiClientProvider).event(id));
final ticketsProvider = FutureProvider<List<Ticket>>((ref) => ref.watch(apiClientProvider).tickets());

String when(DateTime? t) {
  if (t == null) return '';
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} · ${clockOf(t)}';
}

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});
  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(tab == 0 ? eventsProvider : myEventsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الفعاليات'), actions: [IconButton(icon: const Icon(Icons.confirmation_number_outlined), tooltip: 'تذاكري', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage())))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: const Text('فعالية')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(children: [for (final (i, l) in ['القادمة', 'فعالياتي'].indexed) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(l, style: TextStyle(color: tab == i ? Joy.primaryOn : Joy.text)), selected: tab == i, onSelected: (_) => setState(() => tab = i), showCheckmark: false, selectedColor: Joy.primary))]),
        ),
        Expanded(
          child: list.when(
            data: (events) => events.isEmpty
                ? EmptyState(icon: Icons.event_outlined, title: tab == 0 ? 'لا فعاليات قادمة' : 'لم تنشئ فعالية بعد', subtitle: 'أنشئ فعالية ببيع تذاكر أو مجانية وشاركها في دائرتك.')
                : RefreshIndicator(
                    onRefresh: () async { ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider); },
                    child: ListView.separated(padding: const EdgeInsets.fromLTRB(20, 0, 20, 96), itemCount: events.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => EventCard(events[i])),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(tab == 0 ? eventsProvider : myEventsProvider)),
          ),
        ),
      ]),
    );
  }

  Future<void> _create() async {
    final title = TextEditingController(), desc = TextEditingController(), place = TextEditingController();
    final tierName = TextEditingController(text: 'عادي'), tierPrice = TextEditingController(text: '0'), tierQty = TextEditingController(text: '50');
    DateTime starts = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text('فعالية جديدة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان'), autofocus: true),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
          const SizedBox(height: 10),
          TextField(controller: place, decoration: const InputDecoration(labelText: 'المكان')),
          const SizedBox(height: 10),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_rounded, color: Joy.primary), title: Text(when(starts)), onTap: () async {
            final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: starts);
            if (d == null || !ctx.mounted) return;
            final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(starts));
            if (t == null) return;
            setS(() => starts = DateTime(d.year, d.month, d.day, t.hour, t.minute));
          }),
          const Divider(),
          const Align(alignment: AlignmentDirectional.centerStart, child: Text('التذكرة', style: TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          TextField(controller: tierName, decoration: const InputDecoration(labelText: 'اسم الفئة')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: tierPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ر.س)', helperText: '0 = مجانية'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: tierQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد'))),
          ]),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء'))],
      )),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    final gps = await DeviceLocation.current(precise: false);
    final pres = ref.read(myPresenceProvider).value;
    try {
      final ev = await ref.read(apiClientProvider).createEvent({
        'title': title.text.trim(), 'description': desc.text.trim(), 'placeName': place.text.trim(), 'startsAt': starts.toUtc().toIso8601String(),
        'lat': gps?.latitude ?? pres?.lat, 'lng': gps?.longitude ?? pres?.lng,
        'tiers': [{'name': tierName.text.trim(), 'price': ((double.tryParse(tierPrice.text) ?? 0) * 100).round(), 'quantity': int.tryParse(tierQty.text) ?? 50}],
      });
      ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider);
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: ev.id)));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }
}

class EventCard extends StatelessWidget {
  final Event e;
  const EventCard(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = e.startsAt;
    return JoyCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: e.id))),
      child: Row(children: [
        Container(width: 60, height: 66, decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${d?.day ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: Joy.accent, height: 1)), Text(d == null ? '' : ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'][d.month - 1], style: const TextStyle(fontSize: 11, color: Joy.accent, fontWeight: FontWeight.w600))])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${when(e.startsAt)}${e.placeName != null && e.placeName!.isNotEmpty ? ' · ${e.placeName}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 2),
          const SizedBox(height: 6),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: e.minPrice == 0 ? Joy.primarySoft : Joy.sunSoft, borderRadius: BorderRadius.circular(999)), child: Text(e.minPrice == 0 ? 'مجانية' : 'من ${money(e.minPrice)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: e.minPrice == 0 ? Joy.primary : Joy.sunText))),
            const SizedBox(width: 8),
            Text('${e.going} قادمون', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            if (e.myTickets > 0) ...[const SizedBox(width: 8), const Icon(Icons.check_circle_rounded, size: 14, color: Joy.success), const Text(' لديك تذكرة', style: TextStyle(color: Joy.success, fontSize: 11.5))],
          ]),
        ])),
        WishButton(kind: 'event', refId: e.id, compact: true),
      ]),
    );
  }
}

class EventDetailPage extends ConsumerWidget {
  final String eventId;
  const EventDetailPage({super.key, required this.eventId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventProvider(eventId));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الفعالية')),
      body: ev.when(
        data: (e) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          Text(e.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Row(children: [ProfileAvatar(person: e.host, size: 28), const SizedBox(width: 8), Text('يستضيفها ${e.host.nickname}', style: const TextStyle(color: Joy.textMuted, fontSize: 13))]),
          const SizedBox(height: 14),
          JoyCard(child: Column(children: [
            _row(Icons.event_rounded, when(e.startsAt), e.endsAt != null ? 'تنتهي ${clockOf(e.endsAt)}' : null),
            if (e.placeName != null && e.placeName!.isNotEmpty) ...[const Divider(height: 18), _row(Icons.place_rounded, e.placeName!, null)],
            const Divider(height: 18),
            _row(Icons.people_alt_rounded, '${e.going} قادمون', e.myTickets > 0 ? 'لديك ${e.myTickets} تذكرة' : null),
          ])),
          if (e.description.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(e.description, style: const TextStyle(height: 1.65))),
          const SizedBox(height: 6),
          const SectionTitle('التذاكر'),
          if (e.cancelled) const JoyCard(color: Joy.accentSoft, child: Text('أُلغيت هذه الفعالية واستُرد ثمن التذاكر.'))
          else for (final t in e.tiers) Padding(padding: const EdgeInsets.only(bottom: 10), child: _Tier(e, t)),
          if (e.isHost) ...[
            const SizedBox(height: 10),
            const SectionTitle('للمضيف'),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _checkin(context, ref, e), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('تسجيل دخول تذكرة'))),
              const SizedBox(width: 8),
              if (!e.cancelled) OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: () => _cancel(context, ref, e), child: const Text('إلغاء')),
            ]),
          ],
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(eventProvider(eventId))),
      ),
    );
  }

  Widget _row(IconData i, String a, String? b) => Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(i, size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), if (b != null) Text(b, style: const TextStyle(color: Joy.textMuted, fontSize: 12))]))]);

  Future<void> _checkin(BuildContext context, WidgetRef ref, Event e) async {
    final code = await askText(context, title: 'رمز التذكرة', hint: 'NAS-XXXXXXXX', confirm: 'تحقق', maxLines: 1);
    if (code == null || code.isEmpty) return;
    try {
      final r = await ref.read(apiClientProvider).checkin(e.id, code);
      if (context.mounted) toast(context, 'تذكرة صالحة · ${asMapName(r)}');
    } catch (err) {
      if (context.mounted) toast(context, err.toString().contains('ticket-invalid') ? 'تذكرة غير صالحة أو مستخدمة' : err.toString(), error: true);
    }
  }
  String asMapName(Map<String, dynamic> r) => (r['holder'] is Map ? (r['holder']['nickname']?.toString() ?? '') : '');

  Future<void> _cancel(BuildContext context, WidgetRef ref, Event e) async {
    try {
      await ref.read(apiClientProvider).cancelEvent(e.id);
      ref.invalidate(eventProvider(e.id)); ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider); ref.invalidate(walletProvider);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    }
  }
}

class _Tier extends ConsumerStatefulWidget {
  final Event e; final TicketTier t;
  const _Tier(this.e, this.t);
  @override
  ConsumerState<_Tier> createState() => _TierState();
}

class _TierState extends ConsumerState<_Tier> {
  int qty = 1;
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final soldOut = t.left <= 0;
    return JoyCard(child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), const SizedBox(width: 8), Text(soldOut ? 'نفدت' : '${t.left} متبقية', style: TextStyle(fontSize: 11, color: t.left < 10 ? Joy.accent : Joy.textMuted))]),
        if (t.description.isNotEmpty) Text(t.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        const SizedBox(height: 6),
        Text(t.price == 0 ? 'مجانية' : money(t.price), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary, fontSize: 16)),
      ])),
      if (!soldOut) Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: qty > 1 ? () => setState(() => qty--) : null, icon: const Icon(Icons.remove_rounded)),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(onPressed: qty < t.left && qty < 10 ? () => setState(() => qty++) : null, icon: const Icon(Icons.add_rounded)),
        ]),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 40)), onPressed: busy ? null : _buy, child: Text(t.price == 0 ? 'احجز' : 'ادفع ${money(t.price * qty)}')),
      ]),
    ]));
  }

  Future<void> _buy() async {
    setState(() => busy = true);
    try {
      final tickets = await ref.read(apiClientProvider).buyTickets(widget.e.id, widget.t.id, qty);
      ref.invalidate(eventProvider(widget.e.id)); ref.invalidate(ticketsProvider); ref.invalidate(walletProvider); ref.invalidate(eventsProvider);
      if (mounted) {
        toast(context, 'تم الحجز · ${tickets.length} تذكرة');
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage()));
      }
    } catch (e) {
      final s = e.toString();
      if (mounted) toast(context, s.contains('insufficient-funds') ? 'الرصيد غير كافٍ في المحفظة' : s.contains('sold-out') ? 'نفدت التذاكر' : s, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class MyTicketsPage extends ConsumerWidget {
  const MyTicketsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = ref.watch(ticketsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('تذاكري')),
      body: tk.when(
        data: (list) {
          final up = list.where((t) => t.upcoming).toList(), past = list.where((t) => !t.upcoming).toList();
          if (list.isEmpty) return const EmptyState(icon: Icons.confirmation_number_outlined, title: 'لا تذاكر بعد', subtitle: 'احجز تذكرة فعالية وستظهر هنا برمزها.');
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            if (up.isNotEmpty) const SectionTitle('القادمة'),
            for (final t in up) Padding(padding: const EdgeInsets.only(bottom: 10), child: _TicketCard(t)),
            if (past.isNotEmpty) const SectionTitle('السابقة'),
            for (final t in past) Padding(padding: const EdgeInsets.only(bottom: 10), child: Opacity(opacity: .6, child: _TicketCard(t))),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(ticketsProvider)),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Ticket t;
  const _TicketCard(this.t);
  @override
  Widget build(BuildContext context) => JoyCard(
        onTap: () => showModalBottomSheet(context: context, builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          Text('${t.tier} · ${when(t.startsAt)}', style: const TextStyle(color: Joy.textMuted)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: QrImageView(data: t.code, size: 200)),
          const SizedBox(height: 10),
          SelectableText(t.code, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 16)),
          Text(t.status == 'used' ? 'مستخدمة' : t.status == 'refunded' ? 'مستردّة' : 'أظهر الرمز عند البوابة', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ]))),
        child: Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: t.status == 'valid' ? Joy.accentSoft : Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.confirmation_number_outlined, color: t.status == 'valid' ? Joy.accent : Joy.textMuted)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${t.tier} · ${when(t.startsAt)}${t.placeName != null ? ' · ${t.placeName}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 2),
          ])),
          const Icon(Icons.qr_code_2_rounded, color: Joy.text),
        ]),
      );
}
