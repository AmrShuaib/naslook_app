import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_blog_api.dart';
import '../../api/client.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

/// مسودات المدونة الجاهزة: يقرأها المؤسس من حسابه وينشرها بضغطة واحدة بلا دخول إلى لوحة الإدارة.
final blogDraftsProvider = FutureProvider<BlogAdminList>((ref) => ref.watch(apiClientProvider).adminBlogList(status: 'draft'));
final blogRecentProvider = FutureProvider<BlogAdminList>((ref) => ref.watch(apiClientProvider).adminBlogList(status: 'published'));

class BlogDraftsPage extends ConsumerStatefulWidget {
  const BlogDraftsPage({super.key});
  @override
  ConsumerState<BlogDraftsPage> createState() => _BlogDraftsPageState();
}

class _BlogDraftsPageState extends ConsumerState<BlogDraftsPage> {
  final _busy = <String>{};

  Future<void> _publish(BlogPost p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('نشر التدوينة الآن؟'),
        content: Text('«${p.title}» تظهر فوراً في المدونة العامة وخلاصتها.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لاحقاً')), FilledButton(key: const Key('draft-publish-go'), onPressed: () => Navigator.pop(d, true), child: const Text('نشر'))],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(p.id));
    try {
      final r = await ref.read(apiClientProvider).adminBlogPublish(p.id);
      ref.invalidate(blogDraftsProvider);
      ref.invalidate(blogRecentProvider);
      ref.invalidate(adminBlogProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('نُشرت «${r.title}»'), action: SnackBarAction(label: 'نسخ الرابط', onPressed: () => Clipboard.setData(ClipboardData(text: r.url)))));
    } catch (e) {
      if (mounted) toast(context, e is ApiException ? e.message : e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _preview(BlogPost p) async {
    try {
      final full = await ref.read(apiClientProvider).adminBlogGet(p.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        builder: (_) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(full.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            if (full.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(full.summary, style: const TextStyle(color: Joy.textMuted, height: 1.6))),
            const Divider(height: 24),
            SelectableText(full.body, style: const TextStyle(height: 1.8, fontSize: 14.5)),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e is ApiException ? e.message : e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(blogDraftsProvider);
    final recent = ref.watch(blogRecentProvider).valueOrNull?.posts.take(5).toList() ?? const <BlogPost>[];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('تدوينات جاهزة للنشر')),
      body: drafts.when(
        data: (d) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(blogDraftsProvider);
            ref.invalidate(blogRecentProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text('مسودات كتبناها عن جديد ناس لايف؛ راجع أي واحدة ثم اضغط «نشر» فتظهر في المدونة فوراً.', style: TextStyle(color: Joy.textMuted, height: 1.6)),
              const SizedBox(height: 12),
              if (d.posts.isEmpty) const EmptyState(icon: Icons.article_outlined, title: 'لا مسودات بانتظار النشر', subtitle: 'كل ما كُتب نُشر. تُكتب مسودات جديدة مع كل تحديث كبير.'),
              for (final p in d.posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: JoyCard(
                    key: Key('draft-${p.slug}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(switch (p.kind) { 'news' => 'خبر', 'post' => 'تدوينة', _ => 'تحديث' }, style: const TextStyle(color: Joy.primary, fontSize: 10.5, fontWeight: FontWeight.w700))),
                        const Spacer(),
                        Text('${p.bodyLength ~/ 5} كلمة تقريباً', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                      ]),
                      const SizedBox(height: 8),
                      Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (p.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.summary, style: const TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6))),
                      const SizedBox(height: 10),
                      Row(children: [
                        OutlinedButton.icon(onPressed: () => _preview(p), icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('معاينة')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          key: Key('draft-publish-${p.slug}'),
                          onPressed: _busy.contains(p.id) ? null : () => _publish(p),
                          icon: _busy.contains(p.id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.publish_rounded, size: 18),
                          label: const Text('نشر'),
                        ),
                      ]),
                    ]),
                  ),
                ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionTitle('المنشورة مؤخراً'),
                JoyCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (i, p) in recent.indexed)
                      ListTile(
                        title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(p.publishedAt != null ? timeAgo(p.publishedAt) : '', style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: Joy.textMuted),
                        shape: i == recent.length - 1 ? null : const Border(bottom: BorderSide(color: Joy.line)),
                        onTap: () => launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication),
                      ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(blogDraftsProvider)),
      ),
    );
  }
}
