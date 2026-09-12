import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/commerce_models.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import '../market/market_page.dart';
import 'overlay_canvas.dart';
import 'post_composer.dart';
import 'post_media.dart';

/// ينفّذ زر الإجراء في المنشور: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة صاحب المنشور.
Future<void> runPostCta(BuildContext context, MapPost p) async {
  final c = p.cta;
  if (c == null) return;
  switch (c.type) {
    case 'link':
      await launchUrl(Uri.parse(c.value), mode: LaunchMode.externalApplication);
    case 'whatsapp':
      final d = c.value.replaceAll(RegExp(r'\D'), '');
      final intl = d.startsWith('0') ? '966${d.substring(1)}' : d;
      await launchUrl(Uri.parse('https://wa.me/$intl'), mode: LaunchMode.externalApplication);
    case 'call':
      await launchUrl(Uri.parse('tel:${c.value}'));
    case 'biz':
      if (context.mounted) openBusiness(context, c.value);
    case 'market':
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(c.value)));
    case 'chat':
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)));
  }
}

/// عارض منشورات الخريطة بملء الشاشة: تمرير بين المنشورات، تقدّم تلقائي للصور والنصوص، إعجاب ومشاهدات، زر الإجراء، وأدوات صاحب المنشور.
class PostViewerPage extends ConsumerStatefulWidget {
  final List<MapPost> posts;
  final int initial;
  const PostViewerPage({super.key, required this.posts, this.initial = 0});

  static Future<void> open(BuildContext context, List<MapPost> posts, {int index = 0}) {
    if (posts.isEmpty) return Future.value();
    return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PostViewerPage(posts: posts, initial: index.clamp(0, posts.length - 1))));
  }

  @override
  ConsumerState<PostViewerPage> createState() => _PostViewerPageState();
}

class _PostViewerPageState extends ConsumerState<PostViewerPage> {
  static const _autoMs = 7000;
  late final PageController _ctl = PageController(initialPage: widget.initial);
  late List<MapPost> posts = List.of(widget.posts);
  late int index = widget.initial;
  Timer? _auto;
  double progress = 0;
  bool paused = false;
  final _viewed = <String>{};

  @override
  void initState() {
    super.initState();
    _onShown();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onShown() {
    _markViewed();
    _auto?.cancel();
    progress = 0;
    final p = posts[index];
    if (p.kind == 'image' || p.kind == 'text') {
      _auto = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || paused) return;
        setState(() => progress += 50 / _autoMs);
        if (progress >= 1) _next();
      });
    }
  }

  void _markViewed() {
    final p = posts[index];
    if (p.mine || !_viewed.add(p.id)) return;
    ref.read(apiClientProvider).viewPost(p.id).then((v) {
      if (mounted) setState(() => posts[index] = posts[index].copyWith(views: v));
    }).catchError((_) {});
  }

  void _next() {
    if (index + 1 < posts.length) {
      _ctl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _auto?.cancel();
      if (mounted) Navigator.pop(context);
    }
  }

  void _prev() {
    if (index > 0) _ctl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _like(int i) async {
    final p = posts[i];
    setState(() => posts[i] = p.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)));
    try {
      final r = await ref.read(apiClientProvider).likePost(p.id);
      if (mounted) setState(() => posts[i] = posts[i].copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) {
        setState(() => posts[i] = p);
        toast(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _menu(int i) async {
    final p = posts[i];
    paused = true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1F24),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined, color: Colors.white), title: const Text('تعديل المنشور', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: Icon(p.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white), title: Text(p.status == 'active' ? 'إخفاء من الخريطة' : 'إظهار على الخريطة', style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'toggle')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف المنشور', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    paused = false;
    if (!mounted || choice == null) return;
    final api = ref.read(apiClientProvider);
    try {
      if (choice == 'edit') {
        final updated = await PostComposerPage.open(context, lat: p.lat, lng: p.lng, placeName: p.placeName, edit: p);
        if (updated != null && mounted) setState(() => posts[i] = updated);
      } else if (choice == 'toggle') {
        if (p.status == 'blocked') {
          toast(context, 'أخفته الإدارة؛ تواصل مع الدعم', error: true);
          return;
        }
        final updated = await api.updatePost(p.id, {'status': p.status == 'active' ? 'hidden' : 'active'});
        invalidatePosts(ref);
        if (mounted) setState(() => posts[i] = updated);
      } else if (choice == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('حذف المنشور'),
            content: const Text('سيُزال من الخريطة نهائياً.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
          ),
        );
        if (ok != true || !mounted) return;
        await api.deletePost(p.id);
        invalidatePosts(ref);
        if (!mounted) return;
        if (posts.length == 1) return Navigator.pop(context);
        setState(() {
          posts.removeAt(i);
          index = index.clamp(0, posts.length - 1);
        });
        _onShown();
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: PageView.builder(
              controller: _ctl,
              itemCount: posts.length,
              onPageChanged: (i) {
                setState(() => index = i);
                _onShown();
              },
              itemBuilder: (_, i) => PostView(
                post: posts[i],
                active: i == index,
                progress: i == index ? progress : 0,
                total: posts.length,
                position: i,
                onPrev: _prev,
                onNext: _next,
                onLike: () => _like(i),
                onMenu: posts[i].mine ? () => _menu(i) : null,
                onHold: (h) => paused = h,
              ),
            ),
          ),
        ),
      );
}

/// منشور واحد داخل العارض.
class PostView extends ConsumerWidget {
  final MapPost post;
  final bool active;
  final double progress;
  final int total, position;
  final VoidCallback onPrev, onNext, onLike;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onHold;
  const PostView({super.key, required this.post, required this.active, required this.progress, required this.total, required this.position, required this.onPrev, required this.onNext, required this.onLike, this.onMenu, this.onHold});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = post;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth);
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: SizedBox(
            width: w,
            height: box.maxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(box.maxWidth > w + 8 ? 20 : 0),
              child: Stack(fit: StackFit.expand, children: [
                PostMedia(kind: p.kind, url: p.mediaUrl, bg: p.bg, durationSec: p.durationSec, play: active),
                IgnorePointer(child: OverlayCanvas(overlays: p.overlays)),
                // مناطق النقر للتنقل (النصف الأعلى فقط حتى تبقى أدوات الفيديو والأزرار متاحة)
                if (p.kind != 'video')
                  Positioned(
                    top: 0, left: 0, right: 0, height: box.maxHeight * .55,
                    child: Row(children: [
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onNext : onPrev, onLongPressStart: (_) => onHold?.call(true), onLongPressEnd: (_) => onHold?.call(false))),
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onPrev : onNext, onLongPressStart: (_) => onHold?.call(true), onLongPressEnd: (_) => onHold?.call(false))),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        // الشريط العلوي: تقدّم، إغلاق، تنقّل، صاحب المنشور
        Positioned(
          top: 6, left: 10, right: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < total; i++)
                Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: i < position ? 1 : i == position ? progress.clamp(0, 1) : 0, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              InkWell(
                onTap: () => openProfile(context, p.user),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ProfileAvatar(person: p.user, size: 38),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.user.nickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                    Text('${timeAgo(p.createdAt)}${p.placeName != null && p.placeName!.isNotEmpty ? ' · ${p.placeName}' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 11.5, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              if (p.tag != 'moment') _pill(p.tagLabel, Joy.sun, Joy.sunText),
              if (p.mine && p.status != 'active') Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: _pill(p.status == 'blocked' ? 'أخفته الإدارة' : 'مخفي', Colors.white24, Colors.white)),
              const Spacer(),
              if (total > 1) ...[
                IconButton(tooltip: 'السابق', onPressed: onPrev, icon: const Icon(Icons.chevron_right_rounded, color: Colors.white)),
                IconButton(tooltip: 'التالي', onPressed: onNext, icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
              ],
              IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ]),
        ),
        // الأسفل: العنوان والسعر، التعليق، زر الإجراء، الإعجاب والمشاهدات والمراسلة
        Positioned(
          bottom: 10, left: 12, right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (p.title.isNotEmpty || p.price != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  if (p.title.isNotEmpty) Expanded(child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                  if (p.price != null) Text(p.price == 0 ? 'مجاناً' : money(p.price!), style: const TextStyle(color: Joy.sun, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ),
            if (p.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p.caption, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))),
            if (p.cta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => runPostCta(context, p), icon: Icon(_ctaIcon(p.cta!.type)), label: Text(p.cta!.label.isNotEmpty ? p.cta!.label : postCtaTypes[p.cta!.type] ?? ''))),
              ),
            Row(children: [
              _action(p.liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded, '${p.likes}', onLike, color: p.liked ? Joy.accent : Colors.white),
              const SizedBox(width: 6),
              if (p.mine) _action(Icons.visibility_outlined, '${p.views}', null),
              if (!p.mine && me != null) ...[
                const SizedBox(width: 6),
                _action(Icons.chat_bubble_outline_rounded, 'مراسلة', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)))),
                const SizedBox(width: 2),
                WishButton(kind: 'post', refId: p.id, dark: true, compact: true),
              ],
              const Spacer(),
              if (onMenu != null) IconButton(tooltip: 'خيارات', onPressed: onMenu, icon: const Icon(Icons.more_horiz_rounded, color: Colors.white)),
            ]),
          ]),
        ),
      ]);
    });
  }

  static IconData _ctaIcon(String t) => switch (t) { 'whatsapp' => Icons.chat_rounded, 'call' => Icons.call_rounded, 'biz' => Icons.storefront_rounded, 'market' => Icons.shopping_bag_rounded, 'chat' => Icons.chat_bubble_outline_rounded, _ => Icons.open_in_new_rounded };

  Widget _pill(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)));

  Widget _action(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white}) => Material(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: color), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))]),
          ),
        ),
      );
}
