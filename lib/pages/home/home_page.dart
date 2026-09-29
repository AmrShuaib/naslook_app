import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../core/text/post_markup.dart';
import '../../core/nav_provider.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../state/posts_providers.dart';
import '../../state/search_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../circles/circle_detail_page.dart';
import '../events/events_page.dart';
import '../business/business_list.dart';
import '../business/business_page.dart';
import '../market/market_page.dart';
import '../posts/my_posts_page.dart';
import '../posts/feed_page.dart';
import '../posts/post_viewer.dart';
import '../search/search_page.dart';
import '../wallet/wallet_page.dart';
import '../../api/client.dart';
import '../../api/biz_models.dart';
import '../../core/home_layout.dart';
import '../../state/jobs_public_providers.dart';
import '../../state/layout_providers.dart';
import '../jobs/jobs_page.dart';
import '../wallet/my_offers_page.dart';
import 'home_blocks_more.dart';
import 'home_layout_page.dart';

/// الرئيسية كصفحة مستقلة (تحية وبحث ثم الأقسام القابلة للتخصيص). في نظام «الخريطة أولاً» تُعرض الأقسام نفسها
/// داخل الورقة السفلية للخريطة عبر [homeBlockWidgets].
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(storiesProvider);
    ref.invalidate(presenceProvider);
    ref.invalidate(myVesselsProvider);
    ref.invalidate(feedProvider);
    try {
      await Future.wait([ref.read(storiesProvider.future), ref.read(feedProvider.future)]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(appStateProvider.select((s) => s.user));
    final presence = ref.watch(presenceProvider);
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('يا هلا ${me?.nickname ?? ''}!', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          presence.when(
            data: (p) => Text('${p.where((x) => !x.me).length} شخصاً ظاهرون حولك الآن', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
            loading: () => const Text('نبحث عمّن حولك…', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            error: (_, __) => const Text('جدة', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          const HomeSearchBar(),
          const SizedBox(height: 14),
          ...homeBlockWidgets(context, ref),
        ],
      ),
    );
  }
}

/// شريط البحث الموحّد.
class HomeSearchBar extends StatelessWidget {
  final bool glass;
  const HomeSearchBar({super.key, this.glass = false});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        child: const Row(children: [
          Icon(Icons.search_rounded, color: Joy.textMuted),
          SizedBox(width: 10),
          Expanded(child: Text('ابحث عن أشخاص ودوائر وأنشطة ومنتجات', style: TextStyle(color: Joy.textMuted, fontSize: 13.5))),
        ]),
      );
}

/// الأقسام الظاهرة بترتيب المستخدم، ثم صندوق «أقسام مخفية» إن وُجدت. كل قسم في [HomeBlock] بقائمة «⋯».
List<Widget> homeBlockWidgets(BuildContext context, WidgetRef ref) {
  final layout = ref.watch(homeLayoutProvider);
  final out = <Widget>[];
  for (final id in layout.visible) {
    final body = homeBlockBody(context, ref, id, layout);
    if (body == null) continue;
    out.add(HomeBlock(id: id, layout: layout, child: body));
  }
  if (layout.hidden.isNotEmpty) out.add(HiddenBlocksTray(layout: layout));
  return out;
}

/// جسم القسم حسب معرّفه، أو null إن لم يكن له ما يعرضه الآن (فلا يظهر عنوانه).
Widget? homeBlockBody(BuildContext context, WidgetRef ref, String id, HomeLayout layout) {
  switch (id) {
    case 'announce':
      final ps = ref.watch(publicSettingsProvider).valueOrNull;
      if (ps == null || (ps.announcement.isEmpty && !ps.maintenance)) return null;
      return _Announce(ps.announcement, maintenance: ps.maintenance);
    case 'quick':
      return const HomeQuickGrid();
    case 'around':
      return _AroundBlock(opts: layout.opts['around'] ?? const []);
    case 'trending':
      final places = ref.watch(trendingPlacesProvider).valueOrNull ?? const <TrendingPlace>[];
      if (places.isEmpty) return null;
      return _TrendingRail(places: places);
    case 'open':
      final d = ref.watch(discoverProvider).valueOrNull;
      if (d == null || d.openNow.isEmpty) return null;
      return _OpenNowRail(d.openNow);
    case 'circles':
      return const _CirclesBlock();
    case 'feed':
      return _FeedBlock(opts: layout.opts['feed'] ?? const []);
    case 'biz':
      return const _BizCard();
    case 'jobs':
      if (!ref.watch(jobsEnabledProvider)) return null;
      return const HomeJobsBlock();
    case 'market':
      return const HomeMarketBlock();
    case 'events':
      return const HomeEventsBlock();
  }
  return null;
}

/// إطار القسم: عنوان وإجراء اختياري وزر «⋯» (نقل لأعلى/لأسفل، تثبيت، إخفاء، تخصيص الرئيسية). المثبّت بلا زر.
class HomeBlock extends ConsumerWidget {
  final String id;
  final HomeLayout layout;
  final Widget child;
  const HomeBlock({super.key, required this.id, required this.layout, required this.child});

  static String? actionOf(String id) => switch (id) { 'trending' || 'open' || 'jobs' || 'market' || 'events' || 'circles' => 'الكل', 'feed' => 'الخريطة', _ => null };

  void _action(BuildContext context, WidgetRef ref) {
    switch (id) {
      case 'trending':
      case 'open':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()));
      case 'circles':
        openNavTab(ref, 'circles');
      case 'feed':
        openNavTab(ref, 'home');
      case 'jobs':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobsPage()));
      case 'market':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MarketPage()));
      case 'events':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = homeBlockMeta(id);
    final pinned = layout.isPinned(id);
    final action = actionOf(id);
    return Padding(
      key: Key('block-$id'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(child: Text(meta?.title ?? id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              if (layout.isFresh(id))
                Container(margin: const EdgeInsetsDirectional.only(start: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.sun, borderRadius: BorderRadius.circular(999)), child: const Text('جديد', style: TextStyle(color: Joy.sunText, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
          ),
          if (action != null) TextButton(onPressed: () => _action(context, ref), child: Text(action, style: const TextStyle(fontSize: 13))),
          if (!pinned)
            IconButton(
              key: Key('block-menu-$id'),
              tooltip: 'خيارات القسم',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz_rounded, color: Joy.textMuted, size: 20),
              onPressed: () => showBlockMenu(context, ref, id),
            ),
        ]),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

/// قائمة القسم (النموذج ١: «قائمة على القسم»).
Future<void> showBlockMenu(BuildContext context, WidgetRef ref, String id) {
  final layout = ref.read(homeLayoutProvider);
  final vis = layout.visible;
  final i = vis.indexOf(id);
  final firstFree = layout.pinned.where(vis.contains).length;
  final n = ref.read(homeLayoutProvider.notifier);
  final meta = homeBlockMeta(id);
  return showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 6), child: Align(alignment: AlignmentDirectional.centerStart, child: Text(meta?.title ?? id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)))),
        ListTile(key: const Key('block-up'), enabled: i > firstFree, leading: const Icon(Icons.arrow_upward_rounded), title: const Text('نقل لأعلى'), onTap: () { Navigator.pop(ctx); n.update((l) => l.move(id, -1)); }),
        ListTile(key: const Key('block-down'), enabled: i >= 0 && i < vis.length - 1, leading: const Icon(Icons.arrow_downward_rounded), title: const Text('نقل لأسفل'), onTap: () { Navigator.pop(ctx); n.update((l) => l.move(id, 1)); }),
        ListTile(key: const Key('block-top'), enabled: i > firstFree, leading: const Icon(Icons.vertical_align_top_rounded), title: const Text('تثبيت في الأعلى'), onTap: () { Navigator.pop(ctx); n.update((l) => l.toTop(id)); }),
        ListTile(key: const Key('block-hide'), leading: const Icon(Icons.visibility_off_outlined, color: Joy.danger), title: const Text('إخفاء القسم', style: TextStyle(color: Joy.danger)), subtitle: const Text('تجده في «أقسام مخفية» أسفل الصفحة'), onTap: () { Navigator.pop(ctx); n.update((l) => l.hide(id)); }),
        const Divider(height: 1),
        ListTile(key: const Key('block-customize'), leading: const Icon(Icons.tune_rounded), title: const Text('تخصيص الرئيسية…'), subtitle: const Text('ترتيب كل الأقسام وشريط التنقّل'), onTap: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeLayoutPage())); }),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// «أقسام مخفية»: شرائح تعيد كل قسم بضغطة.
class HiddenBlocksTray extends ConsumerWidget {
  final HomeLayout layout;
  const HiddenBlocksTray({super.key, required this.layout});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const Key('hidden-tray'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.control, width: 1.2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.visibility_off_outlined, size: 16, color: Joy.textMuted),
            const SizedBox(width: 6),
            Expanded(child: Text('أقسام مخفية (${layout.hidden.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Joy.text))),
            TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeLayoutPage())), child: const Text('تخصيص', style: TextStyle(fontSize: 12.5))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in layout.hidden)
              ActionChip(
                key: Key('show-$id'),
                avatar: const Icon(Icons.visibility_outlined, size: 15, color: Joy.primary),
                label: Text(homeBlockMeta(id)?.title ?? id, style: const TextStyle(fontSize: 12.5)),
                onPressed: () => ref.read(homeLayoutProvider.notifier).update((l) => l.show(id)),
              ),
          ]),
        ]),
      );
}

/// يفتح تبويباً في الشريط السفلي (إن كان ضمن أقسام المستخدم) وإلا يفتح صفحته المستقلة.
void openNavTab(WidgetRef ref, String tab) {
  final tabs = ref.read(homeLayoutProvider).nav;
  final i = tabs.indexOf(tab);
  if (i >= 0) ref.read(navIndexProvider.notifier).state = i;
}

class _Announce extends StatelessWidget {
  final String text;
  final bool maintenance;
  const _Announce(this.text, {required this.maintenance});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: maintenance ? Joy.accentSoft : Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(maintenance ? Icons.build_circle_outlined : Icons.campaign_outlined, color: maintenance ? Joy.accent : Joy.sunText),
          const SizedBox(width: 8),
          Expanded(child: Text(maintenance && text.isEmpty ? 'التطبيق تحت الصيانة حالياً؛ قد تتأخر بعض الخدمات.' : text, style: TextStyle(color: maintenance ? Joy.accent : Joy.sunText, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5))),
        ]),
      );
}

/// الاختصارات: شبكة ٤×٢ إلى الأقسام الكبيرة.
class HomeQuickGrid extends ConsumerWidget {
  const HomeQuickGrid({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.groups_rounded, 'الدوائر', () => openNavTab(ref, 'circles')),
      (Icons.storefront_outlined, 'السوق', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MarketPage()))),
      (Icons.local_offer_outlined, 'العروض', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyOffersPage()))),
      if (ref.watch(jobsEnabledProvider)) (Icons.work_outline_rounded, 'الوظائف', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobsPage()))),
      (Icons.event_outlined, 'الفعاليات', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage()))),
      (Icons.account_balance_wallet_outlined, 'المحفظة', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage()))),
      (Icons.local_mall_outlined, 'براندات', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessesPage()))),
      (Icons.auto_awesome_rounded, 'بث المدينة', () => FeedPage.open(context)),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: .98,
      children: [
        for (final (icon, label, onTap) in items)
          InkWell(
            key: Key('quick-$label'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 50, height: 50, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: Joy.primary)),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
            ]),
          ),
      ],
    );
  }
}

/// «لحظات حولك»: شريط اللحظات وبطاقة بث المدينة. الخيار «الأصدقاء فقط» يحصر الشريط في جهات الاتصال.
class _AroundBlock extends ConsumerWidget {
  final List<String> opts;
  const _AroundBlock({required this.opts});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(appStateProvider.select((s) => s.user));
    var posts = ref.watch(recentPostsProvider);
    if (opts.contains('friends')) {
      final friends = {for (final p in ref.watch(contactsProvider).valueOrNull ?? const <Person>[]) p.id};
      posts = posts.whenData((l) => [for (final p in l) if (friends.contains(p.user.id)) p]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StoriesRail(stories: ref.watch(storiesProvider), posts: posts, me: me?.nickname ?? ''),
      const SizedBox(height: 12),
      const _FeedCard(),
    ]);
  }
}

class _OpenNowRail extends StatelessWidget {
  final List<Biz> list;
  const _OpenNowRail(this.list);
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final b = list[i];
            return JoyCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onTap: () => openBusiness(context, b.id, initial: b),
              child: Row(children: [
                BizLogo(biz: b, size: 40),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(b.distanceLabel ?? (b.sector.isNotEmpty ? b.sector : b.category.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.success, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            );
          },
        ),
      );
}

class _CirclesBlock extends ConsumerWidget {
  const _CirclesBlock();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(myVesselsProvider).when(
        data: (list) => list.isEmpty
            ? JoyCard(
                color: Joy.sunSoft,
                child: Row(children: [
                  const Icon(Icons.groups_rounded, color: Joy.sunText),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('لم تنضم لأي دائرة بعد. اكتشف الدوائر القريبة منك.', style: TextStyle(color: Joy.sunText))),
                  TextButton(onPressed: () => openNavTab(ref, 'circles'), child: const Text('اكتشف')),
                ]),
              )
            : SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _VesselTile(list[i]),
                ),
              ),
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myVesselsProvider)),
      );
}

/// «آخر ما في دوائرك». الخيار «بلا وسائط» يعرض المنشورات النصية فقط.
class _FeedBlock extends ConsumerWidget {
  final List<String> opts;
  const _FeedBlock({required this.opts});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedIdsProvider);
    return ref.watch(feedProvider).when(
      data: (all) {
        final posts = [for (final p in all) if (!isBlockedId(blocked, p.author.id) && (!opts.contains('text') || p.type == 'text')) p];
        return posts.isEmpty
            ? const EmptyState(icon: Icons.forum_outlined, title: 'لا منشورات بعد', subtitle: 'انضم إلى دائرة أو انشر أول منشور فيها.')
            : Column(children: [for (final p in posts.take(20)) Padding(padding: const EdgeInsets.only(bottom: 10), child: PostCard(p))]);
      },
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(feedProvider)),
    );
  }
}

class _BizCard extends StatelessWidget {
  const _BizCard();
  @override
  Widget build(BuildContext context) => JoyCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessesPage())),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.local_mall_outlined, color: Joy.primary)),
          const SizedBox(width: 12),
          const Expanded(child: Text('براندات عالمية · سينما · فنادق · تأجير سيارات · مستشفيات · مطارات · مقاهٍ مختصة', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5))),
          const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        ]),
      );
}

class _StoriesRail extends ConsumerWidget {
  final AsyncValue<List<Story>> stories;
  final AsyncValue<List<MapPost>> posts;
  final String me;
  const _StoriesRail({required this.stories, required this.posts, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = stories.value ?? const <Story>[];
    final plist = posts.value ?? const <MapPost>[];
    // لحظة واحدة لكل شخص في الشريط
    final byUser = <String, Story>{};
    for (final s in list) {
      byUser.putIfAbsent(s.userId, () => s);
    }
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _RailItem(
            label: 'لحظتك',
            child: InkWell(
              onTap: () => _newStory(context, ref),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(color: Joy.surface, shape: BoxShape.circle, border: Border.all(color: Joy.textMuted, style: BorderStyle.solid)),
                child: const Icon(Icons.add_rounded, color: Joy.primary),
              ),
            ),
          ),
          // منشورات الخريطة الأحدث (صورة/فيديو/صوت/نص) ثم لحظات النواة القديمة
          for (var i = 0; i < plist.length; i++)
            _RailItem(
              label: plist[i].user.nickname,
              child: InkWell(
                onTap: () => PostViewerPage.open(context, plist, index: i),
                onLongPress: () => openProfile(context, plist[i].user),
                borderRadius: BorderRadius.circular(34),
                child: Stack(clipBehavior: Clip.none, children: [
                  Avatar(name: plist[i].user.nickname, url: plist[i].user.avatarUrl, size: 52, ring: true),
                  PositionedDirectional(
                    end: -2, bottom: -2,
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(color: plist[i].tag == 'moment' ? Joy.sun : Joy.accent, shape: BoxShape.circle, border: Border.all(color: Joy.surface, width: 2)),
                      child: Icon(switch (plist[i].kind) { 'image' => Icons.image_rounded, 'video' => Icons.videocam_rounded, 'audio' => Icons.mic_rounded, _ => Icons.text_fields_rounded }, size: 10, color: plist[i].tag == 'moment' ? Joy.sunText : Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          for (final s in byUser.values)
            _RailItem(
              label: s.nickname,
              child: InkWell(
                onTap: () => _showStory(context, s),
                onLongPress: () => openProfile(context, Person(id: s.userId, nickname: s.nickname, avatarUrl: s.avatarUrl)),
                borderRadius: BorderRadius.circular(34),
                child: Avatar(name: s.nickname, url: s.avatarUrl, size: 52, ring: true),
              ),
            ),
          if (list.isEmpty && plist.isEmpty && !stories.isLoading)
            const Padding(padding: EdgeInsets.only(right: 8, top: 18), child: Text('لا لحظات حولك الآن\nكن أول من يشارك', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        ],
      ),
    );
  }

  /// «لحظتك»: يفتح محرّر المنشور (صورة/فيديو/صوت/نص مع نصوص وملصقات) عند موقعك.
  Future<void> _newStory(BuildContext context, WidgetRef ref) => composePostHere(context, ref);

  void _showStory(BuildContext context, Story s) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProfileAvatar(person: Person(id: s.userId, nickname: s.nickname, avatarUrl: s.avatarUrl), size: 44, ring: true),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(timeAgo(s.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 14),
          Text(s.content, style: const TextStyle(fontSize: 17, height: 1.6)),
          if (s.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.caption, style: const TextStyle(color: Joy.textMuted))),
        ]),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final Widget child;
  const _RailItem({required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Column(children: [
          child,
          const SizedBox(height: 6),
          SizedBox(width: 64, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5))),
        ]),
      );
}

class _VesselTile extends StatelessWidget {
  final Vessel v;
  const _VesselTile(this.v);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 168,
        child: JoyCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Avatar(name: v.name, size: 40, radius: 13),
            Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text('${v.members} عضواً${v.lastPostAt != null ? ' · ${timeAgo(v.lastPostAt)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

/// بطاقة منشور تُستخدم في الرئيسية وتفاصيل الدائرة.
class PostCard extends ConsumerWidget {
  final Post post;
  final bool showVessel;
  /// المشاهد مالك الدائرة أو مشرف فيها: يستطيع إزالة منشورات الآخرين.
  final bool moderator;
  const PostCard(this.post, {super.key, this.showVessel = true, this.moderator = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnnouncement = post.kind == 'announcement';
    final myId = ref.watch(appStateProvider.select((s) => s.user?.id));
    final mine = myId != null && myId == post.author.id;
    return JoyCard(
      color: isAnnouncement ? Joy.sunSoft : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: post.vesselId, focusPostId: post.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProfileAvatar(person: post.author, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(post.author.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (post.unread) Container(margin: const EdgeInsets.only(right: 6), width: 8, height: 8, decoration: const BoxDecoration(color: Joy.accent, shape: BoxShape.circle)),
              ]),
              Text('${showVessel && post.vesselName != null ? '${post.vesselName} · ' : ''}${timeAgo(post.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            ]),
          ),
          if (isAnnouncement) const Icon(Icons.campaign_rounded, color: Joy.sunText, size: 20),
          if (myId != null)
            PopupMenuButton<String>(
              key: Key('post-menu-${post.id}'),
              tooltip: 'خيارات',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz_rounded, color: Joy.textMuted, size: 20),
              onSelected: (v) => _action(context, ref, v),
              itemBuilder: (_) => [
                if (mine)
                  PopupMenuItem(key: Key('post-delete-${post.id}'), value: 'delete', child: const ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded, color: Joy.danger), title: Text('حذف المنشور', style: TextStyle(color: Joy.danger)))),
                if (!mine && moderator)
                  PopupMenuItem(key: Key('post-remove-${post.id}'), value: 'remove', child: const ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.remove_circle_outline_rounded, color: Joy.danger), title: Text('إزالة من الدائرة', style: TextStyle(color: Joy.danger)))),
                if (!mine)
                  PopupMenuItem(key: Key('post-report-${post.id}'), value: 'report', child: const ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined), title: Text('إبلاغ عن المنشور'))),
                if (!mine && post.author.id.isNotEmpty)
                  PopupMenuItem(key: Key('post-block-${post.id}'), value: 'block', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${post.author.nickname}', style: const TextStyle(color: Joy.danger)))),
              ],
            ),
        ]),
        const SizedBox(height: 10),
        if (post.type == 'text') PostMarkup(post.content, fontSize: 14.5, collapsed: showVessel, onMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: post.vesselId, focusPostId: post.id))))
        else if (post.type == 'image') ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(thumbUrl(post.content), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))
        else Row(children: [const Icon(Icons.attach_file_rounded, size: 18, color: Joy.textMuted), const SizedBox(width: 6), Expanded(child: Text(post.content, style: const TextStyle(color: Joy.textMuted)))]),
        if (post.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(post.caption, style: const TextStyle(color: Joy.textMuted, fontSize: 13))),
        const SizedBox(height: 8),
        Row(children: [
          _Meta(icon: Icons.favorite_rounded, label: '${post.supports}', active: post.supported, onTap: () async {
            try {
              await ref.read(apiClientProvider).supportPost(post.id);
              ref.invalidate(feedProvider);
            } catch (e) {
              if (context.mounted) toast(context, e.toString(), error: true);
            }
          }),
          const SizedBox(width: 14),
          _Meta(icon: Icons.mode_comment_outlined, label: '${post.comments}'),
          const Spacer(),
          if (post.tag != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(post.tag!, style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
        ]),
      ]),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(hiddenPostsProvider);
    ref.invalidate(feedProvider);
    ref.invalidate(vesselDetailProvider(post.vesselId));
  }

  Future<void> _action(BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('حذف المنشور؟'),
              content: const Text('يُحذف المنشور وتعليقاته نهائياً ولا يمكن التراجع.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
                FilledButton(key: const Key('post-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
              ],
            ),
          );
          if (ok != true) return;
          await api.deleteVesselPost(post.id);
          _refresh(ref);
          if (context.mounted) toast(context, 'حُذف المنشور');
        case 'remove':
          final reason = await askText(context, title: 'إزالة منشور ${post.author.nickname}', hint: 'سبب الإزالة (اختياري، يصل لصاحب المنشور)', confirm: 'إزالة');
          if (reason == null || !context.mounted) return;
          final r = await api.removeVesselPost(post.id, vesselId: post.vesselId, reason: reason);
          _refresh(ref);
          if (context.mounted) toast(context, r.deleted ? 'حُذف المنشور من الدائرة' : 'أُخفي المنشور عن أعضاء الدائرة');
        case 'report':
          final r = await showReportSheet(context, ref, type: 'vessel-post', id: post.id, author: post.author, title: 'إبلاغ عن المنشور');
          if (r != null && (r.hidden || r.blocked)) _refresh(ref);
        case 'block':
          // الحظر يحدّث قائمة المحظورين فتختفي منشوراته من البث وصفحات الدوائر
          if (await confirmBlock(context, ref, post.author)) _refresh(ref);
      }
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _Meta({required this.icon, required this.label, this.active = false, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: active ? Joy.accent : Joy.textMuted),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12.5, color: active ? Joy.accent : Joy.textMuted, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}


/// بطاقة البث العمودي «الآن حولك»: تفتح لحظات المدينة بالتمرير الرأسي، الأقرب والأحدث أولاً.
class _FeedCard extends ConsumerWidget {
  const _FeedCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentPostsProvider).valueOrNull ?? const <MapPost>[];
    final faces = recent.take(3).toList();
    return JoyCard(
      key: const Key('feed-open'),
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF0F2D30),
      onTap: () => FeedPage.open(context),
      child: Row(children: [
        SizedBox(
          width: 64, height: 44,
          child: Stack(children: [
            for (final (i, p) in faces.indexed)
              PositionedDirectional(start: i * 14.0, top: 0, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0F2D30), width: 2)), child: Avatar(name: p.user.nickname, url: p.user.avatarUrl, size: 40))),
            if (faces.isEmpty) Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: Joy.sun)),
          ]),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الآن حولك', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          Text('لحظات المدينة بالفيديو والصورة، الأقرب والأحدث أولاً', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
        ])),
        Container(width: 40, height: 40, decoration: const BoxDecoration(color: Joy.sun, shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, color: Joy.sunText)),
      ]),
    );
  }
}

/// الأماكن الرائجة: الأكثر لحظاتٍ خلال 24 ساعة حولك؛ كل بطاقة تفتح البث مصفّى بذلك المكان.
class _TrendingRail extends StatelessWidget {
  final List<TrendingPlace> places;
  const _TrendingRail({required this.places});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: places.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _TrendCard(place: places[i]),
        ),
      );
}

class _TrendCard extends StatelessWidget {
  final TrendingPlace place;
  const _TrendCard({required this.place});

  Widget _thumb() {
    final logo = place.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      final img = logo.startsWith('asset:') ? Image.asset('assets/${logo.substring(6)}', fit: BoxFit.cover) : Image.network(thumbUrl(logo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.storefront_rounded, color: Joy.primary));
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: img));
    }
    if (place.sampleKind == 'image' && place.sampleUrl != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: Image.network(thumbUrl(place.sampleUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.place_rounded, color: Joy.primary))));
    }
    return Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(place.bizId != null ? Icons.storefront_rounded : Icons.place_rounded, color: Joy.primary));
  }

  @override
  Widget build(BuildContext context) => JoyCard(
        key: Key('trend-${place.key}'),
        padding: const EdgeInsets.all(10),
        onTap: () => FeedPage.open(context, placeKey: place.key, placeName: place.name),
        child: SizedBox(
          width: 150,
          child: Row(children: [
            _thumb(),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text('${place.posts} لحظة · ${place.authors} شخص', maxLines: 1, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
              if (place.distanceKm != null) Text(distanceText(place.distanceKm), style: const TextStyle(color: Joy.primary, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
      );
}
