import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/biz_models.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/require_account.dart';
import '../../state/biz_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';
import '../business/business_list.dart';
import '../business/business_page.dart';
import '../events/event_create_page.dart';
import '../events/events_page.dart';

/// قسم من «استكشف»: معرّفه (في المفاتيح)، اسمه، أيقونته، وفئات الدوائر التي يجمعها (فارغة = قسم الفعاليات).
class ExploreSection {
  final String id, label;
  final IconData icon;
  final Set<BizCategory> cats;
  const ExploreSection(this.id, this.label, this.icon, [this.cats = const {}]);
}

/// الأقسام بترتيب ظهورها. لا قسم للطيران ولا لتذاكر الجهات الخارجية: لا مزوّد لهما، والصفحة لا تعرض إلا بيانات حقيقية.
const exploreSections = <ExploreSection>[
  ExploreSection('events', 'الفعاليات', Icons.event_rounded),
  ExploreSection('cinema', 'سينما', Icons.local_movies_rounded, {BizCategory.cinema}),
  ExploreSection('food', 'مطاعم ومقاهٍ', Icons.restaurant_rounded, {BizCategory.restaurant, BizCategory.cafe}),
  ExploreSection('hotels', 'فنادق', Icons.hotel_rounded, {BizCategory.hotel}),
  ExploreSection('cars', 'سيارات', Icons.directions_car_rounded, {BizCategory.carRental}),
  ExploreSection('appointments', 'مواعيد', Icons.event_available_rounded, {BizCategory.salon, BizCategory.clinic, BizCategory.hospital, BizCategory.services}),
  ExploreSection('fun', 'ترفيه', Icons.attractions_rounded, {BizCategory.entertainment}),
];

/// «استكشف»: مكان واحد لكل ما يُحجز لدى الأنشطة (فعاليات، سينما، مطاعم، فنادق، سيارات، مواعيد، ترفيه).
/// البيانات من مزوّدي الفعاليات والدوائر الموجودين؛ القسم الذي لا بيانات له لا يظهر.
class ExplorePage extends ConsumerStatefulWidget {
  /// أفعال تُلحق بآخر الشريط العلوي: البحث والجرس حين تكون الصفحة قسماً في الشريط السفلي (HomeShell).
  final List<Widget> barActions;
  const ExplorePage({super.key, this.barActions = const []});
  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  /// الرقاقة المختارة: 'all' أو معرّف قسم.
  String chip = 'all';

  void _refresh() {
    ref.invalidate(eventsProvider);
    ref.invalidate(bizListProvider(bizQueryAll));
  }

  Future<void> _create() async {
    // الزائر يُدعى للدخول قبل النموذج، وإلا ملأه كله ثم رفضه الخادم وضاع
    if (!requireAccount(context)) return;
    final ev = await EventCreatePage.open(context);
    if (ev == null || !mounted) return;
    ref.invalidate(eventsProvider);
    ref.invalidate(myEventsProvider);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: ev.id)));
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventsProvider);
    final biz = ref.watch(bizListProvider(bizQueryAll));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('استكشف'), actions: [
        IconButton(key: const Key('explore-tickets'), icon: const Icon(Icons.confirmation_number_outlined), tooltip: 'تذاكري', onPressed: () {
          // التذاكر تخص الحساب: الزائر يُدعى للدخول بدل صفحة خطأ
          if (requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage()));
        }),
        ...widget.barActions,
      ]),
      // إنشاء الفعالية يبقى على بعد ضغطة من القسم كما كان في صفحة الفعاليات
      floatingActionButton: FloatingActionButton.extended(key: const Key('events-create'), onPressed: _create, backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: const Text('فعالية')),
      body: _body(ev, biz),
    );
  }

  Widget _body(AsyncValue<List<Event>> ev, AsyncValue<List<Biz>> biz) {
    // أول تحميل فقط: عند السحب للتحديث تبقى البيانات السابقة ظاهرة
    if ((ev.isLoading && !ev.hasValue && !ev.hasError) || (biz.isLoading && !biz.hasValue && !biz.hasError)) {
      return const Center(child: CircularProgressIndicator());
    }
    final evFailed = ev.hasError && !ev.hasValue, bizFailed = biz.hasError && !biz.hasValue;
    if (evFailed && bizFailed) return ErrorState(ev.error!, onRetry: _refresh);

    final blocked = ref.watch(blockedIdsProvider);
    final events = [for (final e in ev.valueOrNull ?? const <Event>[]) if (!e.cancelled && !isBlockedId(blocked, e.host.id)) e];
    final circles = [for (final b in biz.valueOrNull ?? const <Biz>[]) if (b.active) b];
    final groups = <String, List<Biz>>{
      for (final s in exploreSections)
        if (s.cats.isNotEmpty) s.id: [for (final b in circles) if (s.cats.contains(b.category)) b],
    };
    bool has(ExploreSection s) => s.id == 'events' ? events.isNotEmpty : groups[s.id]!.isNotEmpty;
    final shown = [for (final s in exploreSections) if (has(s)) s];
    // القسم المختار فرغ بعد تحديث: نعود إلى «الكل» بدل صفحة فارغة برقاقة مختفية
    final current = shown.any((s) => s.id == chip) ? chip : 'all';
    final failed = evFailed ? ev.error : (bizFailed ? biz.error : null);

    return Column(children: [
      SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _chip('all', 'الكل', Icons.apps_rounded, current),
            // الرقاقة تحمل اسم الجمع المختصر: «فعاليات» لا «الفعاليات»
            for (final s in shown) _chip(s.id, s.id == 'events' ? 'فعاليات' : s.label, s.icon, current),
          ]),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async {
            _refresh();
            // ننتظر الطلبين حتى يختفي مؤشر السحب مع وصول البيانات، والخطأ يُعرض في مكانه
            await Future.wait([ref.read(eventsProvider.future), ref.read(bizListProvider(bizQueryAll).future)]).then((_) {}, onError: (_) {});
          },
          child: ListView(
            key: const Key('explore-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            // أسفل القائمة يُترك للزر العائم (حجز الكبسولة يأتي من الغلاف)
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
            children: [
              if (failed != null) _partialError(failed),
              if (shown.isEmpty && failed == null)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(key: Key('explore-empty'), icon: Icons.explore_outlined, title: 'لا شيء للحجز الآن', subtitle: 'استكشف يجمع ما يُحجز حولك في مكان واحد: فعاليات وسينما ومطاعم وفنادق ومواعيد. يظهر هنا فور توفره، واسحب للتحديث.'),
                )
              else if (current == 'all')
                for (final s in shown) ...[
                  _header(s, onAll: s.id == 'events' ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage())) : () => setState(() => chip = s.id)),
                  s.id == 'events' ? _eventRail(events) : _bizRail(groups[s.id]!),
                  const SizedBox(height: 18),
                ]
              else if (current == 'events') ...[
                for (final e in events) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: _EventTile(e)),
              ] else ...[
                for (final b in groups[current]!) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: KeyedSubtree(key: Key('explore-biz-${b.id}'), child: BizRow(b))),
              ],
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _chip(String id, String label, IconData icon, String current) {
    final on = current == id;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        key: Key('explore-chip-$id'),
        avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
        label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text)),
        selected: on,
        showCheckmark: false,
        selectedColor: Joy.primary,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => chip = id),
      ),
    );
  }

  Widget _header(ExploreSection s, {required VoidCallback onAll}) {
    final color = Joy.kindColor(s.id == 'events' ? 'event' : 'business');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 8, 4),
      child: Row(children: [
        Icon(s.icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(s.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
        TextButton(key: Key('explore-all-${s.id}'), onPressed: onAll, child: const Text('الكل', style: TextStyle(fontSize: 13))),
      ]),
    );
  }

  /// ارتفاع الشريط الأفقي يكبر مع تكبير النص حتى لا تُقصّ السطور.
  double _railHeight(double fixed, double text) => fixed + MediaQuery.textScalerOf(context).scale(text);

  Widget _eventRail(List<Event> events) => SizedBox(
        height: _railHeight(46, 92),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 280, child: _EventTile(events[i])),
        ),
      );

  Widget _bizRail(List<Biz> list) => SizedBox(
        height: _railHeight(100, 56),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _BizTile(list[i]),
        ),
      );

  /// أحد المصدرين تعذّر والآخر وصل: نعرض ما وصل مع سطر لإعادة المحاولة.
  Widget _partialError(Object error) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: JoyCard(
          key: const Key('explore-partial-error'),
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, size: 18, color: Joy.textMuted),
            const SizedBox(width: 8),
            const Expanded(child: Text('تعذر جلب بعض الأقسام', style: TextStyle(color: Joy.textMuted, fontSize: 13))),
            TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

/// بطاقة فعالية: التاريخ، العنوان، الموعد والمكان، وأدنى سعر تذكرة أو «مجاناً».
class _EventTile extends StatelessWidget {
  final Event e;
  const _EventTile(this.e);
  static const _months = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];
  @override
  Widget build(BuildContext context) {
    final d = e.startsAt;
    final place = e.placeName ?? '';
    final free = e.minPrice == 0;
    return JoyCard(
      key: Key('explore-event-${e.id}'),
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: e.id))),
      child: Row(children: [
        Container(
          width: 54,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${d?.day ?? ''}', maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: Joy.accent, height: 1.1)),
            Text(d == null ? '' : _months[d.month - 1], maxLines: 1, style: const TextStyle(fontSize: 11, color: Joy.accent, fontWeight: FontWeight.w600, height: 1.2)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.3)),
            Text(when(e.startsAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.4)),
            if (place.isNotEmpty) Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: free ? Joy.primarySoft : Joy.sunSoft, borderRadius: BorderRadius.circular(999)),
              child: Text(free ? 'مجاناً' : 'من ${money(e.minPrice)}', maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.3, color: free ? Joy.primary : Joy.sunText)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// بطاقة دائرة في الشريط الأفقي: الشعار، الاسم مع علامة التوثيق، ونوع النشاط.
class _BizTile extends StatelessWidget {
  final Biz b;
  const _BizTile(this.b);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: JoyCard(
          key: Key('explore-biz-${b.id}'),
          padding: const EdgeInsets.all(12),
          onTap: () => openBusiness(context, b.id, initial: b),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BizLogo(biz: b, size: 56),
            const SizedBox(height: 10),
            Row(children: [
              Flexible(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3))),
              if (b.verified) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.verified_rounded, key: Key('explore-verified'), size: 15, color: Joy.primary)),
            ]),
            Text(b.category.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.4)),
          ]),
        ),
      );
}
