import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'post_composer.dart';
import 'post_stats.dart';
import 'post_viewer.dart';
import '../../api/client.dart';

/// يفتح محرّر منشور جديد عند موقع الجهاز، أو مكان المستخدم على الخريطة، أو مركز جدة.
Future<MapPost?> composePostHere(BuildContext context, WidgetRef ref) async {
  final gps = await DeviceLocation.browse();
  final pres = ref.read(myPresenceProvider).valueOrNull;
  final at = gps ?? (pres?.lat != null && pres?.lng != null ? LatLng(pres!.lat!, pres.lng!) : const LatLng(21.5433, 39.1728));
  if (!context.mounted) return null;
  final p = await PostComposerPage.open(context, lat: at.latitude, lng: at.longitude);
  if (p != null && context.mounted) toast(context, 'نُشر منشورك على الخريطة');
  return p;
}

/// ورقة «من يراها؟» لمنشوري: الأصدقاء أو الجميع؛ الاختيار يُحفظ فوراً ويُحدَّث العرض. تعيد المنشور المحدّث أو null.
Future<MapPost?> changePostAudience(BuildContext context, WidgetRef ref, MapPost p) async {
  final v = await showModalBottomSheet<String>(
    context: context, showDragHandle: true,
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('من يرى هذا المنشور؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      for (final (v, icon, hint) in const [('friends', Icons.people_alt_outlined, 'من أضفتهم إلى جهات اتصالك فقط'), ('all', Icons.public_rounded, 'كل من يفتح الخريطة ما دام ملفك عاماً')])
        ListTile(
          key: Key('aud-set-$v'), leading: Icon(icon, color: p.audience == v ? Joy.primary : Joy.textMuted), title: Text(postAudiences[v]!, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(hint),
          trailing: p.audience == v ? const Icon(Icons.check_rounded, color: Joy.primary) : null, onTap: () => Navigator.pop(ctx, v),
        ),
      const SizedBox(height: 8),
    ])),
  );
  if (v == null || v == p.audience || !context.mounted) return null;
  try {
    final updated = await ref.read(apiClientProvider).setPostAudience(p.id, v);
    invalidatePosts(ref);
    if (context.mounted) toast(context, v == 'friends' ? 'صار للأصدقاء فقط' : 'صار للجميع');
    return updated;
  } catch (e) {
    if (context.mounted) toast(context, 'تعذر تغيير الجمهور: $e', error: true);
    return null;
  }
}

/// منشوراتي على الخريطة خلال 30 يوماً: الحالة والمدة والجمهور والمشاهدات والإعجابات، والنقر يفتح العارض حيث التعديل والإخفاء والحذف،
/// ورقاقة الجمهور تغيّر من يراه.
class MyPostsPage extends ConsumerWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myPostsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('منشوراتي على الخريطة')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => composePostHere(context, ref), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_a_photo_rounded), label: const Text('منشور جديد')),
      body: list.when(
        data: (posts) => posts.isEmpty
            ? const EmptyState(icon: Icons.auto_awesome_motion_outlined, title: 'لا منشورات بعد', subtitle: 'انشر صورة أو فيديو قصيراً أو تسجيلاً صوتياً أو نصاً على الخريطة، مع نصوص وملصقات وزر إجراء.')
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myPostsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  itemCount: posts.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => i == 0
                      ? const _MySummary()
                      : MyPostRow(posts[i - 1], onTap: () => PostViewerPage.open(context, posts, index: i - 1), onStats: () => showPostStats(context, postId: posts[i - 1].id),
                          onAudience: () => changePostAudience(context, ref, posts[i - 1])),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myPostsProvider)),
      ),
    );
  }
}

String postStatusLabel(MapPost p) => p.status == 'blocked' ? 'أخفته الإدارة' : p.status == 'hidden' ? 'مخفي' : p.expired ? 'انتهت مدته' : 'ظاهر على الخريطة';

/// ملخص 7 أيام لكل منشوراتي مع زر التفاصيل.
class _MySummary extends ConsumerWidget {
  const _MySummary();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(postStatsProvider((postId: null, bizId: null, days: 7)));
    return JoyCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('آخر 7 أيام', style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton.icon(onPressed: () => showPostStats(context), icon: const Icon(Icons.insights_outlined, size: 18), label: const Text('التفاصيل')),
        ]),
        stats.when(
          data: (s) => Row(children: [
            _SumItem('${s.totals.views}', 'مشاهدة'),
            _SumItem('${s.totals.likes}', 'إعجاب'),
            _SumItem('${s.totals.cta}', 'ضغطة إجراء'),
            _SumItem('${s.totals.contacts}', 'مراسلة'),
          ]),
          loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2)),
          error: (_, __) => const Text('تعذر جلب الإحصاءات', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
        ),
      ]),
    );
  }
}

/// رقاقة صغيرة بجمهور المنشور: «الأصدقاء» أو «الجميع»، ولمسها يفتح ورقة التغيير
class _AudienceChip extends StatelessWidget {
  final MapPost p;
  final VoidCallback? onTap;
  const _AudienceChip(this.p, {this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        key: Key('aud-chip-${p.id}'),
        color: p.friendsOnly ? Joy.primarySoft : Joy.surface2,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(p.friendsOnly ? Icons.people_alt_outlined : Icons.public_rounded, size: 13, color: p.friendsOnly ? Joy.primary : Joy.textMuted),
              const SizedBox(width: 4),
              Text(p.audienceLabel, style: TextStyle(color: p.friendsOnly ? Joy.primary : Joy.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
              if (onTap != null) Icon(Icons.expand_more_rounded, size: 14, color: p.friendsOnly ? Joy.primary : Joy.textMuted),
            ]),
          ),
        ),
      );
}

class _SumItem extends StatelessWidget {
  final String value, label;
  const _SumItem(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
      ]));
}

class MyPostRow extends StatelessWidget {
  final MapPost p;
  final VoidCallback onTap;
  final VoidCallback? onStats;
  /// رقاقة الجمهور (null = تُعرض بلا لمس)
  final VoidCallback? onAudience;
  const MyPostRow(this.p, {super.key, required this.onTap, this.onStats, this.onAudience});

  @override
  Widget build(BuildContext context) {
    final ok = p.status == 'active' && !p.expired;
    final icon = switch (p.kind) { 'image' => Icons.image_outlined, 'video' => Icons.videocam_outlined, 'audio' => Icons.mic_rounded, _ => Icons.text_fields_rounded };
    return JoyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 52, height: 52, clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
          child: p.kind == 'image' && p.mediaUrl != null ? Image.network(thumbUrl(p.mediaUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(icon, color: Joy.textMuted)) : Icon(icon, color: p.kind == 'text' ? Joy.primary : Joy.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          Text('${p.tagLabel} · ${postStatusLabel(p)}${p.expiresAt != null && ok ? ' · ينتهي ${timeAgo(p.expiresAt).replaceFirst('قبل', 'بعد')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ok ? Joy.success : Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Row(children: [
            Flexible(child: Text('${p.views} مشاهدة · ${p.likes} إعجاب · ${timeAgo(p.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
            const SizedBox(width: 6),
            _AudienceChip(p, onTap: onAudience),
          ]),
        ])),
        if (onStats != null) IconButton(tooltip: 'الإحصاءات', onPressed: onStats, icon: const Icon(Icons.insights_outlined, color: Joy.primary)) else const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
      ]),
    );
  }
}
