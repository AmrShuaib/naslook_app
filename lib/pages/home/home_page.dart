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
import '../../ui/profile_avatar.dart';
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
import '../../api/safety_api.dart';

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
    final stories = ref.watch(storiesProvider);
    final presence = ref.watch(presenceProvider);
    final vessels = ref.watch(myVesselsProvider);
    final feed = ref.watch(feedProvider);

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
          // شريط البحث الموحّد
          JoyCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
            child: const Row(children: [
              Icon(Icons.search_rounded, color: Joy.textMuted),
              SizedBox(width: 10),
              Expanded(child: Text('ابحث عن أشخاص ودوائر وأنشطة ومنتجات', style: TextStyle(color: Joy.textMuted, fontSize: 13.5))),
            ]),
          ),
          const SizedBox(height: 14),
          _StoriesRail(stories: stories, posts: ref.watch(recentPostsProvider), me: me?.nickname ?? ''),
          const SizedBox(height: 14),
          const _FeedCard(),
          const _TrendingRail(),
          const SizedBox(height: 16),
          JoyCard(
            padding: EdgeInsets.zero,
            onTap: () => ref.read(navIndexProvider.notifier).state = 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.map_rounded, color: Joy.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('حولك الآن', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    presence.when(
                      data: (p) => Text('${p.where((x) => !x.me).length} شخصاً · ${stories.value?.length ?? 0} لحظة على الخريطة', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                      loading: () => const Text('…', style: TextStyle(color: Joy.textMuted)),
                      error: (e, _) => const Text('اضغط لفتح الخريطة', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _Quick(icon: Icons.account_balance_wallet_outlined, label: 'المحفظة', color: Joy.primarySoft, fg: Joy.primary, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage()))),
            const SizedBox(width: 8),
            _Quick(icon: Icons.event_outlined, label: 'الفعاليات', color: Joy.accentSoft, fg: Joy.accent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage()))),
            const SizedBox(width: 8),
            _Quick(icon: Icons.storefront_outlined, label: 'السوق', color: Joy.sunSoft, fg: Joy.sunText, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MarketPage()))),
          ]),
          Consumer(builder: (context, ref, _) {
            final ps = ref.watch(publicSettingsProvider).valueOrNull;
            if (ps == null || (ps.announcement.isEmpty && !ps.maintenance)) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ps.maintenance ? Joy.accentSoft : Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(ps.maintenance ? Icons.build_circle_outlined : Icons.campaign_outlined, color: ps.maintenance ? Joy.accent : Joy.sunText),
                const SizedBox(width: 8),
                Expanded(child: Text(ps.maintenance && ps.announcement.isEmpty ? 'التطبيق تحت الصيانة حالياً؛ قد تتأخر بعض الخدمات.' : ps.announcement, style: TextStyle(color: ps.maintenance ? Joy.accent : Joy.sunText, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5))),
              ]),
            );
          }),
          const SizedBox(height: 10),
          JoyCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessesPage())),
            child: Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.local_mall_outlined, color: Joy.primary)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الدوائر التجارية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('براندات عالمية · سينما · فنادق · تأجير سيارات · مستشفيات · مطارات · مقاهٍ مختصة', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              ])),
              const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
            ]),
          ),
          // مفتوح الآن حولك: شريط أفقي من الأنشطة المفتوحة مرتبةً بالأقرب
          Consumer(builder: (context, ref, _) {
            final d = ref.watch(discoverProvider).valueOrNull;
            if (d == null || d.openNow.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 18),
              SectionTitle(d.located ? 'مفتوح الآن حولك' : 'مفتوح الآن', action: 'الكل', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()))),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: d.openNow.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final b = d.openNow[i];
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
              ),
            ]);
          }),
          const SizedBox(height: 18),
          SectionTitle('دوائرك', action: 'الكل', onAction: () => ref.read(navIndexProvider.notifier).state = 2),
          vessels.when(
            data: (list) => list.isEmpty
                ? JoyCard(
                    color: Joy.sunSoft,
                    child: Row(children: [
                      const Icon(Icons.groups_rounded, color: Joy.sunText),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('لم تنضم لأي دائرة بعد. اكتشف الدوائر القريبة منك.', style: TextStyle(color: Joy.sunText))),
                      TextButton(onPressed: () => ref.read(navIndexProvider.notifier).state = 2, child: const Text('اكتشف')),
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
          ),
          const SizedBox(height: 18),
          const SectionTitle('آخر ما في دوائرك'),
          feed.when(
            data: (posts) => posts.isEmpty
                ? const EmptyState(icon: Icons.forum_outlined, title: 'لا منشورات بعد', subtitle: 'انضم إلى دائرة أو انشر أول منشور فيها.')
                : Column(children: [for (final p in posts.take(20)) Padding(padding: const EdgeInsets.only(bottom: 10), child: PostCard(p))]),
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(feedProvider)),
          ),
        ],
      ),
    );
  }
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

class _Quick extends StatelessWidget {
  final IconData icon; final String label; final Color color; final Color fg; final VoidCallback onTap;
  const _Quick({required this.icon, required this.label, required this.color, required this.fg, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Container(height: 64, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: fg), const SizedBox(width: 6), Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)))])),
      ));
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
          final reason = await askText(context, title: 'إبلاغ عن المنشور', hint: 'ما المشكلة؟ (مسيء، احتيال، مضلل…)', confirm: 'إرسال البلاغ');
          if (reason == null || reason.isEmpty || !context.mounted) return;
          final r = await api.reportContent(type: 'vessel-post', id: post.id, reason: reason);
          if (r.hidden) _refresh(ref);
          if (context.mounted) toast(context, r.hidden ? 'وصل بلاغك وأُخفي المنشور للمراجعة' : 'وصل بلاغك وسنراجعه');
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
class _TrendingRail extends ConsumerWidget {
  const _TrendingRail();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(trendingPlacesProvider).valueOrNull ?? const <TrendingPlace>[];
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      const SectionTitle('الأماكن الرائجة اليوم'),
      const SizedBox(height: 6),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: places.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _TrendCard(place: places[i]),
        ),
      ),
    ]);
  }
}

class _TrendCard extends StatelessWidget {
  final TrendingPlace place;
  const _TrendCard({required this.place});

  Widget _thumb() {
    final logo = place.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      final img = logo.startsWith('asset:') ? Image.asset('assets/${logo.substring(6)}', fit: BoxFit.cover) : Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.storefront_rounded, color: Joy.primary));
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: img));
    }
    if (place.sampleKind == 'image' && place.sampleUrl != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: Image.network(place.sampleUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.place_rounded, color: Joy.primary))));
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
