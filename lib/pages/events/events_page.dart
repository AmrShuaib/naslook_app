import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/require_account.dart';
import '../../core/require_adult.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../api/event_attendees_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/qr_scanner.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../wallet/wallet_page.dart';
import 'event_create_page.dart';

final eventsProvider = FutureProvider<List<Event>>((ref) => ref.watch(apiClientProvider).events());
final myEventsProvider = FutureProvider<List<Event>>((ref) => ref.watch(apiClientProvider).events(mine: true));
final eventProvider = FutureProvider.family<Event, String>((ref, id) => ref.watch(apiClientProvider).event(id));
final ticketsProvider = FutureProvider<List<Ticket>>((ref) => ref.watch(apiClientProvider).tickets());
/// الصفحة الأولى من قائمة الحضور للمضيف بحسب الفلتر ('' الكل، 'in' دخلوا، 'out' لم يدخلوا)؛ «عرض المزيد» يكمل بالمؤشر.
final eventAttendeesProvider = FutureProvider.autoDispose.family<AttendeePage, ({String id, String status})>((ref, a) => ref.watch(apiClientProvider).eventAttendees(a.id, status: a.status, limit: 20));

String when(DateTime? t) {
  if (t == null) return '';
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} · ${clockOf(t)}';
}

class EventsPage extends ConsumerStatefulWidget {
  /// أفعال تُلحق بآخر الشريط العلوي: البحث والجرس حين تكون الصفحة قسماً في الشريط السفلي (HomeShell).
  final List<Widget> barActions;
  const EventsPage({super.key, this.barActions = const []});
  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    // «فعالياتي» تطلب ?mine=1 وترفض بلا جلسة (401)، فلا تظهر للزائر
    final signed = ref.watch(signedInProvider);
    final shown = signed ? tab : 0;
    final list = ref.watch(shown == 0 ? eventsProvider : myEventsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الفعاليات'), actions: [
        IconButton(key: const Key('events-tickets'), icon: const Icon(Icons.confirmation_number_outlined), tooltip: 'تذاكري', onPressed: () {
          // التذاكر تخص الحساب: الزائر يُدعى للدخول بدل صفحة خطأ
          if (requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage()));
        }),
        ...widget.barActions,
      ]),
      floatingActionButton: FloatingActionButton.extended(key: const Key('events-create'), onPressed: _create, backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: const Text('فعالية')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(children: [for (final (i, l) in ['القادمة', if (signed) 'فعالياتي'].indexed) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(l, style: TextStyle(color: shown == i ? Joy.primaryOn : Joy.text)), selected: shown == i, onSelected: (_) => setState(() => tab = i), showCheckmark: false, selectedColor: Joy.primary))]),
        ),
        Expanded(
          child: list.when(
            data: (all) => switch ([for (final e in all) if (!isBlockedId(ref.watch(blockedIdsProvider), e.host.id)) e]) { final events => events.isEmpty
                ? EmptyState(icon: Icons.event_outlined, title: shown == 0 ? 'لا فعاليات قادمة' : 'لم تنشئ فعالية بعد', subtitle: 'أنشئ فعالية ببيع تذاكر أو مجانية وشاركها في دائرتك.')
                : RefreshIndicator(
                    onRefresh: () async { ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider); },
                    child: ListView.separated(padding: const EdgeInsets.fromLTRB(20, 0, 20, 96), itemCount: events.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => EventCard(events[i])),
                  ) },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(shown == 0 ? eventsProvider : myEventsProvider)),
          ),
        ),
      ]),
    );
  }

  Future<void> _create() async {
    // الزائر يُدعى للدخول قبل النموذج، وإلا ملأه كله ثم رفضه الخادم وضاع
    if (!requireAccount(context)) return;
    // المكان يحدده المنشئ (موقع جهازه افتراضياً أو نقطة على الخريطة)، لا موقع جهازه لحظة الضغط على «إنشاء»
    final ev = await EventCreatePage.open(context);
    if (ev == null || !mounted) return;
    ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: ev.id)));
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
      appBar: AppBar(title: const Text('الفعالية'), actions: [
        IconButton(
          key: const Key('copy-event-code'),
          tooltip: 'انسخ رمز المحادثة',
          icon: const Icon(Icons.bolt_rounded),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: eventCode(eventId)));
            if (context.mounted) toast(context, 'نُسخ الرمز ${eventCode(eventId)}، الصقه في أي محادثة');
          },
        ),
        // أي مستخدم ينشئ فعالية فتُتاح لغير المضيف: إبلاغ عنها وحظر مضيفها
        if (ev.valueOrNull case final e? when !e.isHost)
          ReportMenuButton(type: 'event', id: e.id, author: e.host, keyPrefix: 'event', iconSize: 24, color: Joy.text, reportLabel: 'إبلاغ عن الفعالية',
            onReported: (r) { if (r.hidden || r.blocked) { ref.invalidate(eventsProvider); if (context.mounted) Navigator.of(context).maybePop(); } },
            onBlocked: () { ref.invalidate(eventsProvider); if (context.mounted) Navigator.of(context).maybePop(); }),
      ]),
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
              // مسح رمز التذكرة بالكاميرا، والإدخال اليدوي في الورقة نفسها
              Expanded(child: FilledButton.icon(key: const Key('event-checkin-code'), onPressed: () => _checkin(context, ref, e), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('مسح التذاكر عند الدخول'))),
              const SizedBox(width: 8),
              if (!e.cancelled) OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: () => _cancel(context, ref, e), child: const Text('إلغاء')),
            ]),
            const SizedBox(height: 14),
            EventAttendeesSection(event: e),
          ],
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(eventProvider(eventId))),
      ),
    );
  }

  Widget _row(IconData i, String a, String? b) => Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(i, size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), if (b != null) Text(b, style: const TextStyle(color: Joy.textMuted, fontSize: 12))]))]);

  /// بوابة الفعالية: مسح رمز التذكرة (أو كتابته) ثم ملخصها (الحاضر، الفئة، دخل أم لا) ثم «تأكيد الدخول» بطلب الخادم نفسه،
  /// و«امسح التالي» يعيد الكاميرا للحاضر التالي.
  Future<void> _checkin(BuildContext context, WidgetRef ref, Event e) async {
    final api = ref.read(apiClientProvider);
    for (;;) {
      if (!context.mounted) return;
      final code = await showQrScanSheet(context, title: 'مسح التذاكر', help: 'وجّه الكاميرا إلى رمز التذكرة على جوال الحاضر', manualHint: 'NAS-XXXXXXXX', check: checkVenueCode);
      if (code == null || !context.mounted) return;
      EventAttendee? t;
      Object? lookupErr;
      try {
        t = (await api.eventAttendees(e.id, code: code, limit: 1)).items.firstOrNull;
      } catch (err) {
        lookupErr = err;
      }
      if (!context.mounted) return;
      final step = await showScanSummary(
        context,
        code: code,
        header: Row(key: const Key('ticket-summary'), children: [
          if (t != null) ProfileAvatar(person: t.holder, size: 46) else const Icon(Icons.confirmation_number_outlined, size: 40, color: Joy.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t?.name ?? 'تذكرة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
        ]),
        rows: [
          if (t != null) ('الفئة', t.tier),
          if (t != null && t.paid > 0) ('المدفوع', money(t.paid)),
          if (t != null) ('الحالة', t.checkedIn ? 'دخل' : t.refunded ? 'مستردّة' : 'لم يدخل بعد'),
        ],
        // تعذر الجلب لا يمنع الدخول: الخادم يتحقق من الرمز عند التأكيد كما في الإدخال اليدوي
        warning: lookupErr != null
            ? 'تعذر جلب تفاصيل التذكرة. يمكنك التأكيد والخادم يتحقق من الرمز.'
            : t == null
                ? 'لا تذكرة بهذا الرمز في هذه الفعالية'
                : t.checkedIn
                    ? 'دخل بهذه التذكرة من قبل${t.checkedInAt != null ? ' · ${when(t.checkedInAt)}' : ''}'
                    : t.refunded
                        ? 'تذكرة مستردّة، لا تصلح للدخول'
                        : null,
        blocked: lookupErr == null && (t == null || t.checkedIn || t.refunded),
        confirmLabel: 'تأكيد الدخول',
        onConfirm: (_) async {
          final r = await api.checkin(e.id, code);
          ref.invalidate(eventAttendeesProvider);
          final who = asMapName(r);
          return 'تذكرة صالحة · ${who.isNotEmpty ? who : t?.name ?? ''}';
        },
        errText: (err) => err.toString().contains('ticket-invalid') ? 'تذكرة غير صالحة أو مستخدمة' : err.toString(),
      );
      if (step == ScanStep.done) return;
    }
  }
  String asMapName(Map<String, dynamic> r) => (r['holder'] is Map ? (r['holder']['nickname']?.toString() ?? '') : '');

  Future<void> _cancel(BuildContext context, WidgetRef ref, Event e) async {
    try {
      await ref.read(apiClientProvider).cancelEvent(e.id);
      ref.invalidate(eventProvider(e.id)); ref.invalidate(eventsProvider); ref.invalidate(myEventsProvider); ref.invalidate(walletProvider);
    } catch (err) {
      // الإلغاء يردّ ثمن التذاكر من محفظة المضيف؛ الخادم يرفضه برصيد لا يكفي
      final s = err.toString();
      if (context.mounted) toast(context, s.contains('insufficient-funds') ? 'رصيد محفظتك لا يكفي لاسترداد التذاكر للمشترين؛ اشحن المحفظة ثم أعد المحاولة' : s, error: true);
    }
  }
}

/// قائمة الحضور للمضيف: من حجز، والفئة، ودخل أم لا ومتى، بفلتر وصفحات («عرض المزيد»). الخادم يقصرها على المضيف والإدارة.
class EventAttendeesSection extends ConsumerStatefulWidget {
  final Event event;
  const EventAttendeesSection({super.key, required this.event});
  @override
  ConsumerState<EventAttendeesSection> createState() => _EventAttendeesSectionState();
}

class _EventAttendeesSectionState extends ConsumerState<EventAttendeesSection> {
  String status = '';
  // صفحات «عرض المزيد» تتبع الصفحة الأولى التي جاءت بعدها؛ إن أعيد جلب الأولى (بعد دخول أو تحديث) تبدأ من جديد
  AttendeePage? _base;
  final _more = <EventAttendee>[];
  String? _cursor;
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    final c = _cursor;
    if (c == null || _loadingMore) return;
    final base = _base;
    setState(() => _loadingMore = true);
    try {
      final p = await ref.read(apiClientProvider).eventAttendees(widget.event.id, status: status, cursor: c, limit: 20);
      if (!mounted || !identical(base, _base)) return;
      setState(() { _more.addAll(p.items); _cursor = p.next; });
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (id: widget.event.id, status: status);
    final first = ref.watch(eventAttendeesProvider(key));
    final page = first.valueOrNull;
    if (page != null && !identical(page, _base)) {
      _base = page;
      _more.clear();
      _cursor = page.next;
    }
    Widget chip(String k, String label) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            key: Key('att-filter-${k.isEmpty ? 'all' : k}'),
            label: Text(label, style: TextStyle(color: status == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)),
            selected: status == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => status = k),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionTitle('الحضور')),
        if (page != null) Text('دخل ${page.checkedIn} من ${page.total}', key: const Key('attendees-count'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
      Row(children: [chip('', 'الكل'), chip('in', 'دخلوا'), chip('out', 'لم يدخلوا')]),
      const SizedBox(height: 8),
      first.when(
        data: (p) {
          final items = [...p.items, ..._more];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(status == 'in' ? 'لم يدخل أحد بعد' : status == 'out' ? 'دخل كل من حجز' : 'لم يحجز أحد بعد', key: const Key('attendees-empty'), style: const TextStyle(color: Joy.textMuted)),
            );
          }
          return JoyCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(children: [
              for (final (i, a) in items.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  key: Key('attendee-${a.ticketId}'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    ProfileAvatar(person: a.holder, size: 36),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${a.tier}${a.checkedIn ? ' · دخل ${clockOf(a.checkedInAt)}' : a.refunded ? ' · مستردّة' : ' · لم يدخل بعد'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    ])),
                    Icon(a.checkedIn ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 20, color: a.checkedIn ? Joy.success : Joy.textMuted),
                  ]),
                ),
              ],
              if (_cursor != null)
                TextButton(key: const Key('attendees-more'), onPressed: _loadingMore ? null : _loadMore, child: Text(_loadingMore ? 'جارٍ التحميل…' : 'عرض المزيد')),
            ]),
          );
        },
        loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(eventAttendeesProvider(key))),
      ),
    ]);
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
    if (!requireAccount(context)) return;
    if (widget.t.price > 0 && (!await requireAdult(context, ref) || !mounted)) return;
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
