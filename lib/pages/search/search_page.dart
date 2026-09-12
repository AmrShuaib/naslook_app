import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/search_api.dart';
import '../../core/app_theme.dart';
import '../../state/search_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_list.dart';
import '../business/business_page.dart';
import '../circles/circle_detail_page.dart';
import '../events/events_page.dart';
import '../market/market_page.dart';
import '../profile/user_profile_page.dart';

/// البحث الموحّد: أشخاص ودوائر وأنشطة تجارية وعناصر كتالوجها والسوق والفعاليات، مع اكتشاف (مفتوح الآن، الأعلى تقييماً، فعاليات، دوائر) عند فراغ الحقل.
class SearchPage extends ConsumerStatefulWidget {
  final String initialQuery;
  const SearchPage({super.key, this.initialQuery = ''});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  late String q = widget.initialQuery.trim();
  String? type;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => q = v.trim());
    });
  }

  void _set(String v) {
    _debounce?.cancel();
    _ctl.text = v;
    _ctl.selection = TextSelection.collapsed(offset: v.length);
    setState(() => q = v.trim());
    rememberSearch(ref, v);
  }

  @override
  Widget build(BuildContext context) {
    final results = q.isEmpty ? null : ref.watch(searchProvider((q: q, type: type)));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          autofocus: widget.initialQuery.isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _set,
          decoration: InputDecoration(
            hintText: 'ابحث عن أشخاص ودوائر وأنشطة ومنتجات…',
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false,
            prefixIcon: const Icon(Icons.search_rounded, color: Joy.textMuted),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctl,
              builder: (_, v, __) => v.text.isEmpty ? const SizedBox.shrink() : IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, color: Joy.textMuted), onPressed: () => _set('')),
            ),
          ),
        ),
      ),
      body: Column(children: [
        SizedBox(
          height: 44,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [_typeChip('الكل', null), for (final (k, label) in searchTypes) _typeChip(label, k)]),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: q.isEmpty
              ? _Discover(onPick: _set)
              : results!.when(
                  skipLoadingOnReload: true,
                  data: (r) => _Results(r: r, type: type, onMore: (k) => setState(() => type = k)),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(searchProvider((q: q, type: type)))),
                ),
        ),
      ]),
    );
  }

  Widget _typeChip(String label, String? key) {
    final on = type == key;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text)),
        selected: on,
        showCheckmark: false,
        selectedColor: Joy.primary,
        onSelected: (_) => setState(() => type = key),
      ),
    );
  }
}

/// نتائج مجمّعة حسب النوع مع «عرض الكل» لكل مجموعة ممتلئة.
class _Results extends StatelessWidget {
  final SearchResults r;
  final String? type;
  final ValueChanged<String> onMore;
  const _Results({required this.r, required this.type, required this.onMore});

  @override
  Widget build(BuildContext context) {
    if (r.isEmpty) {
      return EmptyState(icon: Icons.search_off_rounded, title: 'لا نتائج لـ «${r.q}»', subtitle: 'جرّب كلمة أخرى أو اسماً أقصر، أو ابحث بالإنجليزية للبراندات.');
    }
    Widget section(String key, String title, int count, List<Widget> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(title, action: type == null && count >= 6 ? 'عرض الكل' : null, onAction: type == null && count >= 6 ? () => onMore(key) : null),
            for (final w in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
            const SizedBox(height: 8),
          ]);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        section('biz', 'أنشطة تجارية', r.biz.length, [for (final b in r.biz) BizRow(b)]),
        section('items', 'منتجات وعروض', r.items.length, [for (final i in r.items) ItemResultRow(i)]),
        section('people', 'أشخاص', r.people.length, [for (final p in r.people) PersonResultRow(p)]),
        section('vessels', 'دوائر', r.vessels.length, [for (final v in r.vessels) VesselResultRow(v)]),
        section('market', 'السوق', r.market.length, [for (final l in r.market) ListingResultRow(l)]),
        section('events', 'فعاليات', r.events.length, [for (final e in r.events) EventResultRow(e)]),
      ],
    );
  }
}

/// الاكتشاف عند فراغ الحقل: عمليات سابقة، اقتراحات، المفتوح الآن قريباً، الأعلى تقييماً، فعاليات قادمة، دوائر نشطة.
class _Discover extends ConsumerWidget {
  final ValueChanged<String> onPick;
  const _Discover({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    final d = ref.watch(discoverProvider);
    const suggestions = ['سينما', 'فندق', 'تأجير سيارات', 'قهوة', 'إيكيا', 'فعاليات'];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(discoverProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (recents.isNotEmpty) ...[
            SectionTitle('عمليات بحث سابقة', action: 'مسح', onAction: () => ref.read(recentSearchesProvider.notifier).state = const []),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in recents) ActionChip(avatar: const Icon(Icons.history_rounded, size: 16, color: Joy.textMuted), label: Text(s), onPressed: () => onPick(s))]),
            const SizedBox(height: 14),
          ],
          const SectionTitle('جرّب البحث عن'),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in suggestions) ActionChip(label: Text(s), onPressed: () => onPick(s))]),
          const SizedBox(height: 14),
          d.when(
            skipLoadingOnReload: true,
            data: (x) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (x.openNow.isNotEmpty) ...[
                SectionTitle(x.located ? 'مفتوح الآن قريب منك' : 'مفتوح الآن'),
                if (!x.located) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('اسمح بالوصول إلى موقعك لترتيبها بالأقرب إليك', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
                for (final b in x.openNow.take(5)) Padding(padding: const EdgeInsets.only(bottom: 8), child: BizRow(b)),
                const SizedBox(height: 8),
              ],
              if (x.topRated.isNotEmpty) ...[
                const SectionTitle('الأعلى تقييماً'),
                for (final b in x.topRated.take(4)) Padding(padding: const EdgeInsets.only(bottom: 8), child: BizRow(b)),
                const SizedBox(height: 8),
              ],
              if (x.events.isNotEmpty) ...[
                const SectionTitle('فعاليات قادمة'),
                for (final e in x.events.take(4)) Padding(padding: const EdgeInsets.only(bottom: 8), child: EventResultRow(e)),
                const SizedBox(height: 8),
              ],
              if (x.vessels.isNotEmpty) ...[
                const SectionTitle('دوائر نشطة'),
                for (final v in x.vessels.take(4)) Padding(padding: const EdgeInsets.only(bottom: 8), child: VesselResultRow(v)),
              ],
            ]),
            loading: () => const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(discoverProvider)),
          ),
        ],
      ),
    );
  }
}

class PersonResultRow extends StatelessWidget {
  final SearchPerson p;
  const PersonResultRow(this.p, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(person: p.person))),
        child: Row(children: [
          ProfileAvatar(person: p.person, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.person.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (p.bio.isNotEmpty) Text(p.bio, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        ]),
      );
}

class VesselResultRow extends StatelessWidget {
  final Vessel v;
  const VesselResultRow(this.v, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v))),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.groups_rounded, color: Joy.sunText)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('${v.topic.isNotEmpty ? '${v.topic} · ' : ''}${v.members} عضو${v.member ? ' · أنت عضو' : ''}${v.isPublic ? '' : ' · خاصة'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        ]),
      );
}

class ItemResultRow extends StatelessWidget {
  final SearchItem i;
  const ItemResultRow(this.i, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => openBusiness(context, i.bizId),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)), child: Icon(i.category.icon, color: Joy.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('${i.bizName}${i.distanceKm != null ? ' · ${_km(i.distanceKm!)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          Text(money(i.price), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

class ListingResultRow extends StatelessWidget {
  final Listing l;
  const ListingResultRow(this.l, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.storefront_outlined, color: Joy.sunText)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('${l.seller.nickname}${l.placeName != null && l.placeName!.isNotEmpty ? ' · ${l.placeName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          Text(money(l.price), style: const TextStyle(color: Joy.sunText, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

class EventResultRow extends StatelessWidget {
  final Event e;
  const EventResultRow(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = e.startsAt;
    return JoyCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: e.id))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: d == null ? const Icon(Icons.event_outlined, color: Joy.accent) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${d.day}', style: const TextStyle(color: Joy.accent, fontWeight: FontWeight.w800, fontSize: 15, height: 1)),
            Text(_month(d.month), style: const TextStyle(color: Joy.accent, fontSize: 10, height: 1.2)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          Text('${e.placeName ?? ''}${e.placeName != null && e.placeName!.isNotEmpty ? ' · ' : ''}${e.host.nickname}${e.going > 0 ? ' · ${e.going} ذاهبون' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ])),
        Text(e.minPrice == 0 ? 'مجاناً' : money(e.minPrice), style: const TextStyle(color: Joy.accent, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

String _km(double d) => d < 1 ? '${(d * 1000).round()} م' : '${d.toStringAsFixed(d < 10 ? 1 : 0)} كم';
String _month(int m) => const ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'][m - 1];
