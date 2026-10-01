import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/text/post_markup.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import 'circle_detail_page.dart';

/// بطاقة منشور دائرة: في صفحة الدوائر («آخر ما في دوائرك») وتفاصيل الدائرة.
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
