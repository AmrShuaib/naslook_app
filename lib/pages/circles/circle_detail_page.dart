import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../home/home_page.dart';

final vesselDetailProvider = FutureProvider.family<(Vessel, List<Post>), String>((ref, id) => ref.watch(apiClientProvider).vessel(id));
final vesselMembersProvider = FutureProvider.family<List<Person>, String>((ref, id) => ref.watch(apiClientProvider).vesselMembers(id));
final commentsProvider = FutureProvider.family<List<Comment>, String>((ref, id) => ref.watch(apiClientProvider).comments(id));

class CircleDetailPage extends ConsumerStatefulWidget {
  final String vesselId;
  final Vessel? initial;
  final String? focusPostId;
  const CircleDetailPage({super.key, required this.vesselId, this.initial, this.focusPostId});
  @override
  ConsumerState<CircleDetailPage> createState() => _CircleDetailPageState();
}

class _CircleDetailPageState extends ConsumerState<CircleDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(apiClientProvider).seenVessel(widget.vesselId).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(vesselDetailProvider(widget.vesselId));
    final v = detail.value?.$1 ?? widget.initial;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(v?.name ?? 'الدائرة'),
        actions: [
          IconButton(tooltip: 'الأعضاء', icon: const Icon(Icons.people_alt_outlined), onPressed: () => _members(context)),
          if (v != null && v.member && v.role != 'owner')
            IconButton(tooltip: 'مغادرة', icon: const Icon(Icons.logout_rounded), onPressed: () => _leave(v)),
        ],
      ),
      floatingActionButton: v != null && v.member
          ? FloatingActionButton.extended(onPressed: _newPost, backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.edit_rounded), label: const Text('منشور'))
          : null,
      body: detail.when(
        data: (d) {
          final (vessel, posts) = d;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vesselDetailProvider(widget.vesselId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
              children: [
                JoyCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(name: vessel.name, size: 56, radius: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(vessel.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                        Text('${vessel.members} عضواً · ${vessel.isPublic ? 'عامة' : 'خاصة'}${vessel.role != null ? ' · أنت ${_roleName(vessel.role!)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                      ])),
                      if (!vessel.member)
                        FilledButton(onPressed: () => _join(vessel), child: const Text('انضم')),
                    ]),
                    if (vessel.topic.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(vessel.topic, style: const TextStyle(height: 1.6))),
                  ]),
                ),
                const SizedBox(height: 16),
                const SectionTitle('المنشورات'),
                if (posts.isEmpty)
                  EmptyState(icon: Icons.forum_outlined, title: 'لا منشورات بعد', subtitle: vessel.member ? 'كن أول من يكتب في هذه الدائرة.' : 'انضم لتشارك.'),
                for (final p in posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PostWithComments(p, expanded: p.id == widget.focusPostId),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(vesselDetailProvider(widget.vesselId))),
      ),
    );
  }

  String _roleName(String r) => switch (r) { 'owner' => 'المالك', 'moderator' => 'مشرف', 'admin' => 'مشرف', _ => 'عضو' };

  Future<void> _join(Vessel v) async {
    try {
      await ref.read(apiClientProvider).joinVessel(v.id);
      ref.invalidate(vesselDetailProvider(v.id));
      ref.invalidate(myVesselsProvider);
      ref.invalidate(feedProvider);
      if (mounted) toast(context, 'انضممت إلى ${v.name}');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _leave(Vessel v) async {
    try {
      await ref.read(apiClientProvider).leaveVessel(v.id);
      ref.invalidate(myVesselsProvider);
      ref.invalidate(feedProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _newPost() async {
    final text = await askText(context, title: 'منشور جديد', hint: 'اكتب للدائرة…', confirm: 'نشر', maxLines: 5);
    if (text == null || text.isEmpty) return;
    try {
      await ref.read(apiClientProvider).createPost(widget.vesselId, text);
      ref.invalidate(vesselDetailProvider(widget.vesselId));
      ref.invalidate(feedProvider);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  void _members(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Consumer(builder: (ctx, ref, _) {
        final m = ref.watch(vesselMembersProvider(widget.vesselId));
        return SafeArea(
          child: m.when(
            data: (list) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                Text('الأعضاء · ${list.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 8),
                for (final p in list)
                  ListTile(contentPadding: EdgeInsets.zero, leading: ProfileAvatar(person: p, size: 40), title: Text(p.nickname), onTap: () => openProfile(context, p)),
              ],
            ),
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(e),
          ),
        );
      }),
    );
  }
}

class _PostWithComments extends ConsumerStatefulWidget {
  final Post post;
  final bool expanded;
  const _PostWithComments(this.post, {this.expanded = false});
  @override
  ConsumerState<_PostWithComments> createState() => _PostWithCommentsState();
}

class _PostWithCommentsState extends ConsumerState<_PostWithComments> {
  late bool open = widget.expanded;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PostCard(widget.post, showVessel: false),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => open = !open),
          icon: Icon(open ? Icons.expand_less_rounded : Icons.mode_comment_outlined, size: 18),
          label: Text(open ? 'إخفاء التعليقات' : 'التعليقات (${widget.post.comments})'),
        ),
      ),
      if (open) _Comments(widget.post.id),
    ]);
  }
}

class _Comments extends ConsumerWidget {
  final String postId;
  const _Comments(this.postId);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(commentsProvider(postId));
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16),
      child: Column(children: [
        c.when(
          data: (list) => Column(children: [
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ProfileAvatar(person: x.author, size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Text(x.author.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), const Spacer(), Text(timeAgo(x.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11))]),
                      Text(x.text, style: const TextStyle(fontSize: 13.5, height: 1.5)),
                    ]),
                  )),
                ]),
              ),
          ]),
          loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          error: (e, _) => Text(e.toString(), style: const TextStyle(color: Joy.danger, fontSize: 12)),
        ),
        Row(children: [
          Expanded(child: TextField(
            decoration: const InputDecoration(hintText: 'اكتب تعليقاً…', isDense: true),
            onSubmitted: (t) async {
              if (t.trim().isEmpty) return;
              try {
                await ref.read(apiClientProvider).addComment(postId, t.trim());
                ref.invalidate(commentsProvider(postId));
              } catch (e) {
                if (context.mounted) toast(context, e.toString(), error: true);
              }
            },
          )),
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }
}
