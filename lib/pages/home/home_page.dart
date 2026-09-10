import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../core/nav_provider.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../circles/circle_detail_page.dart';

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
          const SizedBox(height: 16),
          _StoriesRail(stories: stories, me: me?.nickname ?? ''),
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
  final String me;
  const _StoriesRail({required this.stories, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = stories.value ?? const <Story>[];
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
          for (final s in byUser.values)
            _RailItem(
              label: s.nickname,
              child: InkWell(
                onTap: () => _showStory(context, s),
                borderRadius: BorderRadius.circular(34),
                child: Avatar(name: s.nickname, url: s.avatarUrl, size: 52, ring: true),
              ),
            ),
          if (list.isEmpty && !stories.isLoading)
            const Padding(padding: EdgeInsets.only(right: 8, top: 18), child: Text('لا لحظات حولك الآن\nكن أول من يشارك', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        ],
      ),
    );
  }

  Future<void> _newStory(BuildContext context, WidgetRef ref) async {
    final text = await askText(context, title: 'لحظة جديدة', hint: 'ماذا يحدث حولك الآن؟ تظهر 24 ساعة لمن حولك', confirm: 'نشر');
    if (text == null || text.isEmpty) return;
    // موقع اللحظة: GPS الجهاز أولاً، ثم مكانك المحدد على الخريطة، وإلا نطلب تحديده
    final gps = await DeviceLocation.current();
    final pres = ref.read(myPresenceProvider).value;
    final lat = gps?.latitude ?? pres?.lat, lng = gps?.longitude ?? pres?.lng;
    if (lat == null || lng == null) {
      if (context.mounted) toast(context, 'فعّل الموقع أو اضغط مطوّلاً على الخريطة لتحديد مكان اللحظة');
      if (context.mounted) ref.read(navIndexProvider.notifier).state = 1;
      return;
    }
    try {
      await ref.read(apiClientProvider).postStory(text: text, lat: lat, lng: lng);
      ref.invalidate(storiesProvider);
      if (context.mounted) toast(context, 'نُشرت لحظتك');
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  void _showStory(BuildContext context, Story s) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(name: s.nickname, url: s.avatarUrl, size: 44, ring: true),
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
  const PostCard(this.post, {super.key, this.showVessel = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnnouncement = post.kind == 'announcement';
    return JoyCard(
      color: isAnnouncement ? Joy.sunSoft : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: post.vesselId, focusPostId: post.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: post.author.nickname, url: post.author.avatarUrl, size: 36),
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
        ]),
        const SizedBox(height: 10),
        if (post.type == 'text') Text(post.content, style: const TextStyle(fontSize: 14.5, height: 1.6))
        else if (post.type == 'image') ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(post.content, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))
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
