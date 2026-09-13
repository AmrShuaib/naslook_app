import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart';
import '../../api/community_api.dart';
import '../../api/chat_tools_api.dart';
import '../../api/commerce_models.dart';
import '../../api/naslife_api.dart';
import '../../api/safety_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/pick_image.dart';
import '../../core/media/voice_player.dart';
import '../../core/media/voice_record.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/community_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';

/// محتوى مشاركة أو رد جاهز للإرسال: نص و/أو صور مرفوعة و/أو تسجيل صوتي مرفوع.
typedef CommunityDraft = ({String topic, String text, List<String> images, String? audio, int? audioMs, String? itemId});

String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// مساحة مجتمع الدائرة: خيط عام يشبه المحادثة ينشر فيه المستخدمون نصاً أو تسجيلاً صوتياً أو صوراً (حتى 10)
/// مصنّفة بمواضيع، مع ردود بالطرق نفسها وإعجابات، وتثبيت أو إخفاء من إدارة الدائرة، وبلاغات. يُحدَّث تلقائياً كل 15 ثانية.
class CommunityPage extends ConsumerStatefulWidget {
  final String bizId;
  final String title;
  final String? initialPostId;
  /// منتج يُفتح النقاش عنه: تُصفّى المساحة عليه ويُقتبس جاهزاً في المؤلّف.
  final CommunityItemRef? initialItem;
  const CommunityPage({super.key, required this.bizId, this.title = '', this.initialPostId, this.initialItem});
  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage> {
  String? _topic;
  CommunityItemRef? _filterItem;
  String _sort = 'new';
  final List<CommunityPost> _older = [];
  final Map<String, CommunityPost> _patch = {};
  final Set<String> _removed = {};
  bool _loadingMore = false, _noMore = false;
  Timer? _poll;

  CommunityFeedKey get _arg => (bizId: widget.bizId, topic: _topic, itemId: _filterItem?.id, sort: _sort);

  @override
  void initState() {
    super.initState();
    _filterItem = widget.initialItem;
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => ref.invalidate(communityFeedProvider(_arg)));
    if (widget.initialPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openThread(widget.initialPostId!);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _older.clear();
      _patch.clear();
      _removed.clear();
      _noMore = false;
    });
    ref.invalidate(communityFeedProvider(_arg));
    await ref.read(communityFeedProvider(_arg).future).catchError((_) => const CommunityFeed(posts: []));
  }

  void _setTopic(String? t) {
    if (t == _topic) return;
    setState(() {
      _topic = t;
      _older.clear();
      _noMore = false;
    });
  }

  void _setFilterItem(CommunityItemRef? it) {
    if (it?.id == _filterItem?.id) return;
    setState(() {
      _filterItem = it;
      _older.clear();
      _noMore = false;
    });
  }

  void _setSort(String v) {
    if (v == _sort) return;
    setState(() {
      _sort = v;
      _older.clear();
      _noMore = false;
    });
  }

  Future<void> _loadMore(List<CommunityPost> current) async {
    if (_loadingMore || _noMore || current.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = current.where((p) => !p.pinned).lastOrNull ?? current.last;
      final more = await ref.read(apiClientProvider).communityFeed(widget.bizId, topic: _topic, before: last.createdAt, itemId: _filterItem?.id, sort: _sort);
      if (!mounted) return;
      setState(() {
        final known = {for (final p in current) p.id};
        _older.addAll(more.posts.where((p) => !known.contains(p.id)));
        _noMore = !more.hasMore;
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر جلب المزيد', error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send(CommunityDraft d) async {
    final api = ref.read(apiClientProvider);
    final banned = bannedWordIn(d.text, ref.read(bannedWordsProvider).valueOrNull ?? const []);
    if (banned != null) {
      toast(context, 'النص يحتوي كلمة غير مسموحة: «$banned»', error: true);
      throw StateError('banned');
    }
    await api.communityPost(widget.bizId, topic: d.topic, text: d.text, images: d.images, audio: d.audio, audioMs: d.audioMs, itemId: d.itemId);
    if (!mounted) return;
    if (_topic != null && _topic != d.topic) _setTopic(null);
    if (_filterItem != null && _filterItem!.id != d.itemId) _setFilterItem(null);
    ref.invalidate(communityFeedProvider(_arg));
  }

  Future<void> _like(CommunityPost p) async {
    try {
      final r = await ref.read(apiClientProvider).communityLike(widget.bizId, p.id);
      if (mounted) setState(() => _patch[p.id] = (_patch[p.id] ?? p).copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) toast(context, 'تعذر تسجيل الإعجاب', error: true);
    }
  }

  void _openThread(String postId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityThreadPage(bizId: widget.bizId, postId: postId, title: widget.title))).then((_) {
        if (mounted) ref.invalidate(communityFeedProvider(_arg));
      });

  Future<void> _menu(CommunityPost p, bool canModerate) async {
    final choice = await showCommunityPostMenu(context, p, canModerate: canModerate);
    if (!mounted || choice == null) return;
    final api = ref.read(apiClientProvider);
    try {
      switch (choice) {
        case 'pin':
          final r = await api.communityPin(widget.bizId, p.id, !p.pinned);
          if (mounted) setState(() => _patch[p.id] = r);
          ref.invalidate(communityFeedProvider(_arg));
        case 'hide':
          final r = await api.communityHide(widget.bizId, p.id, !p.hidden);
          if (mounted) {
            setState(() => _patch[p.id] = r);
            toast(context, r.hidden ? 'أُخفي المنشور عن الزوار' : 'أُظهر المنشور');
          }
        case 'delete':
          final ok = await _confirm('حذف المنشور؟', 'يُحذف مع ردوده ولا يمكن التراجع.');
          if (!ok) return;
          await api.communityDelete(widget.bizId, p.id);
          if (mounted) setState(() => _removed.add(p.id));
        case 'report':
          if (!mounted) return;
          final reason = await askText(context, title: 'إبلاغ عن المشاركة', hint: 'ما المشكلة؟ (إساءة، احتيال، محتوى مضلل…)', confirm: 'إرسال البلاغ');
          if (reason == null || reason.isEmpty || !mounted) return;
          final r = await api.reportContent(type: 'community', id: p.id, reason: reason);
          if (mounted) toast(context, r.hidden ? 'وصل بلاغك وأُخفيت المشاركة للمراجعة' : 'وصل بلاغك وستراجعه إدارة الدائرة');
        case 'block':
          await api.blockUser(p.user.id);
          if (mounted) {
            toast(context, 'تم حظر ${p.user.nickname}');
            _refresh();
          }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(communityFeedProvider(_arg));
    final feed = feedAsync.valueOrNull;
    ref.watch(bannedWordsProvider); // تُحمَّل مبكراً حتى يعمل التحقق المسبق عند الإرسال
    final bizTitle = widget.title.isNotEmpty ? widget.title : (ref.watch(bizDetailProvider(widget.bizId)).valueOrNull?.title ?? 'الدائرة');
    final posts = [
      for (final p in [...?feed?.posts, ..._older])
        if (!_removed.contains(p.id)) _patch[p.id] ?? p,
    ];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مساحة $bizTitle', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
          if (feed != null) Text('${feed.total} مشاركة · ${feed.members} مشارك', style: const TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          PopupMenuButton<String>(
            key: const Key('community-sort'),
            tooltip: 'الترتيب',
            initialValue: _sort,
            onSelected: _setSort,
            icon: Icon(_sort == 'top' ? Icons.local_fire_department_rounded : Icons.sort_rounded, color: _sort == 'top' ? Joy.accent : null),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Row(children: [Icon(Icons.schedule_rounded, size: 18), SizedBox(width: 8), Text('الأحدث')])),
              PopupMenuItem(value: 'top', child: Row(children: [Icon(Icons.local_fire_department_rounded, size: 18, color: Joy.accent), SizedBox(width: 8), Text('الأكثر تفاعلاً')])),
            ],
          ),
          IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
          IconButton(tooltip: 'عن المساحة', icon: const Icon(Icons.info_outline_rounded), onPressed: () => _about(bizTitle)),
        ],
      ),
      body: Column(children: [
        _TopicBar(selected: _topic, onSelect: _setTopic),
        if (_filterItem != null)
          Container(
            color: Joy.surface,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(children: [
              const Icon(Icons.format_quote_rounded, size: 18, color: Joy.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('النقاش عن: ${_filterItem!.title} · ${_filterItem!.priceLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Joy.primary))),
              InkWell(key: const Key('community-filter-clear'), onTap: () => _setFilterItem(null), borderRadius: BorderRadius.circular(12), child: const Padding(padding: EdgeInsets.all(4), child: Row(mainAxisSize: MainAxisSize.min, children: [Text('كل المساحة', style: TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)), SizedBox(width: 2), Icon(Icons.close_rounded, size: 16, color: Joy.textMuted)]))),
            ]),
          )
        else if (feed != null && feed.topItems.isNotEmpty)
          Container(
            color: Joy.surface,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const Icon(Icons.local_fire_department_rounded, size: 16, color: Joy.accent),
                const SizedBox(width: 4),
                const Text('الأكثر نقاشاً', style: TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w700)),
                for (final t in feed.topItems) ...[
                  const SizedBox(width: 6),
                  ActionChip(
                    key: Key('community-top-${t.item.id}'),
                    label: Text('${t.item.title} · ${t.count}'),
                    labelStyle: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Joy.text),
                    backgroundColor: Joy.surface2,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setFilterItem(t.item),
                  ),
                ],
              ]),
            ),
          ),
        Expanded(
          child: feedAsync.when(
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: _refresh),
            data: (f) => RefreshIndicator(
              onRefresh: _refresh,
              child: posts.isEmpty
                  ? ListView(children: [
                      EmptyState(
                        icon: Icons.forum_outlined,
                        title: _topic == null ? 'المساحة هادئة الآن' : 'لا مشاركات في هذا الموضوع',
                        subtitle: 'كن أول من يشارك تجربته أو صورة أو تسجيلاً صوتياً هنا.',
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                      itemCount: posts.length + 1,
                      itemBuilder: (context, i) {
                        if (i == posts.length) {
                          if (_noMore || !f.hasMore && _older.isEmpty) return const SizedBox(height: 8);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: _loadingMore
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                  : OutlinedButton.icon(key: const Key('community-more'), onPressed: () => _loadMore(posts), icon: const Icon(Icons.history_rounded, size: 18), label: const Text('مشاركات أقدم')),
                            ),
                          );
                        }
                        final p = posts[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CommunityPostCard(
                            post: p,
                            canModerate: f.canModerate,
                            onLike: () => _like(p),
                            onOpen: () => _openThread(p.id),
                            onMenu: () => _menu(p, f.canModerate),
                            onQuote: p.item == null ? null : () => _setFilterItem(p.item),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
        CommunityComposer(bizId: widget.bizId, initialItem: widget.initialItem, onSend: _send),
      ]),
    );
  }

  void _about(String bizTitle) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مساحة $bizTitle', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('مساحة عامة لزوار الدائرة ومرتاديها: شاركوا تجاربكم وصوركم، اسألوا، وانصحوا بعضكم. المشاركات المصنّفة «سؤال» أو «تنبيه» تصل إلى فريق الدائرة للرد.',
                style: TextStyle(height: 1.6, color: Joy.text)),
            const SizedBox(height: 12),
            const _Rule(icon: Icons.mic_none_rounded, text: 'شارك بنص أو تسجيل صوتي أو صور (حتى 10 صور)، والردود بالطرق نفسها'),
            const _Rule(icon: Icons.format_quote_rounded, text: 'اقتبس أي صنف من قائمة الدائرة وعلّق عليه، واضغط الاقتباس لترى كل ما قيل عنه'),
            const _Rule(icon: Icons.favorite_border_rounded, text: 'قلب على المشاركات والردود، و«الأكثر تفاعلاً» يرتّب بحسب القلوب والردود'),
            const _Rule(icon: Icons.verified_user_outlined, text: 'تظهر شارة «فريق الدائرة» على مشاركات الإدارة والموظفين'),
            const _Rule(icon: Icons.push_pin_outlined, text: 'تثبّت الإدارة المشاركات المهمة في أعلى المساحة'),
            const _Rule(icon: Icons.flag_outlined, text: 'أبلغ عن أي مشاركة مسيئة؛ تُخفى تلقائياً بعد عدة بلاغات'),
          ]),
        ),
      );
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Icon(icon, size: 18, color: Joy.primary), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: Joy.text)))]),
      );
}

/// شرائح المواضيع: الكل ثم كل موضوع.
class _TopicBar extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _TopicBar({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
        color: Joy.surface,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip(null, 'الكل', Icons.forum_outlined),
            for (final e in communityTopics.entries) ...[const SizedBox(width: 6), _chip(e.key, topicPlural(e.key), topicIcon(e.key))],
          ]),
        ),
      );

  Widget _chip(String? key, String label, IconData icon) {
    final on = key == selected;
    return ChoiceChip(
      key: Key('community-topic-${key ?? 'all'}'),
      avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
      label: Text(label),
      selected: on,
      showCheckmark: false,
      selectedColor: Joy.primary,
      labelStyle: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: on ? Joy.primaryOn : Joy.text),
      backgroundColor: Joy.surface2,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onSelect(key),
    );
  }
}

String topicPlural(String key) => switch (key) { 'photo' => 'صور', 'question' => 'أسئلة', 'tip' => 'نصائح', 'alert' => 'تنبيهات', _ => 'عام' };
IconData topicIcon(String key) => switch (key) {
      'photo' => Icons.photo_camera_outlined,
      'question' => Icons.help_outline_rounded,
      'tip' => Icons.lightbulb_outline_rounded,
      'alert' => Icons.campaign_outlined,
      _ => Icons.chat_bubble_outline_rounded,
    };
Color topicColor(String key) => switch (key) { 'photo' => Joy.primary, 'question' => const Color(0xFF6D4CC9), 'tip' => Joy.success, 'alert' => Joy.accent, _ => Joy.textMuted };

/// بطاقة مشاركة: الكاتب وشاراته والوقت والموضوع، النص، التسجيل الصوتي، شبكة الصور، ثم الإعجاب والردود.
class CommunityPostCard extends StatelessWidget {
  final CommunityPost post;
  final bool canModerate, expanded;
  final VoidCallback? onLike, onOpen, onMenu, onQuote;
  const CommunityPostCard({super.key, required this.post, this.canModerate = false, this.expanded = false, this.onLike, this.onOpen, this.onMenu, this.onQuote});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final tc = topicColor(p.topic);
    return Semantics(
      label: 'مشاركة ${p.user.nickname}',
      child: JoyCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        color: p.hidden ? Joy.surface2 : (p.pinned ? Joy.sunSoft.withValues(alpha: .55) : null),
        onTap: expanded ? null : onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(name: p.user.nickname, url: p.user.avatarUrl, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
                  Text(p.mine ? 'أنت' : p.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  if (p.staff) const _Badge(icon: Icons.verified_rounded, text: 'فريق الدائرة', color: Joy.primary),
                  if (p.pinned) const _Badge(icon: Icons.push_pin_rounded, text: 'مثبّت', color: Joy.sunText),
                  if (p.hidden) const _Badge(icon: Icons.visibility_off_outlined, text: 'مخفي', color: Joy.danger),
                ]),
                Text(timeAgo(p.createdAt), style: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tc.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(topicIcon(p.topic), size: 13, color: tc), const SizedBox(width: 4), Text(p.topicLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tc))]),
            ),
            if (onMenu != null) SizedBox(width: 32, height: 32, child: IconButton(padding: EdgeInsets.zero, tooltip: 'خيارات', icon: const Icon(Icons.more_horiz_rounded, size: 20, color: Joy.textMuted), onPressed: onMenu)),
          ]),
          if (p.item != null) Padding(padding: const EdgeInsets.only(top: 8), child: CommunityQuoteChip(item: p.item!, onTap: onQuote)),
          if (p.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(p.text, style: const TextStyle(fontSize: 15, height: 1.55), maxLines: expanded ? null : 6, overflow: expanded ? null : TextOverflow.ellipsis),
            ),
          if (p.audio != null) Padding(padding: const EdgeInsets.only(top: 8), child: CommunityVoice(url: p.audio, ms: p.audioMs)),
          if (p.images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: CommunityImages(images: p.images)),
          const SizedBox(height: 6),
          Row(children: [
            _Action(key: Key('community-like-${p.id}'), icon: p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: p.liked ? Joy.accent : Joy.textMuted, label: p.likes == 0 ? 'إعجاب' : '${p.likes}', onTap: onLike),
            const SizedBox(width: 6),
            _Action(icon: Icons.mode_comment_outlined, color: Joy.textMuted, label: p.replies == 0 ? 'رد' : '${p.replies} ${p.replies == 1 ? 'رد' : p.replies == 2 ? 'ردّان' : p.replies <= 10 ? 'ردود' : 'رداً'}', onTap: expanded ? null : onOpen),
            const Spacer(),
            if (!expanded && p.replies > 0) Text('افتح النقاش', style: TextStyle(fontSize: 12, color: Joy.primary.withValues(alpha: .9), fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Badge({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: color), const SizedBox(width: 3), Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color))]),
      );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  const _Action({super.key, required this.icon, required this.color, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))]),
        ),
      );
}

/// اقتباس منتج من قائمة الدائرة داخل مشاركة أو رد: أيقونة الصنف واسمه وسعره؛ اللمس يصفّي المساحة عليه.
class CommunityQuoteChip extends StatelessWidget {
  final CommunityItemRef item;
  final VoidCallback? onTap, onRemove;
  const CommunityQuoteChip({super.key, required this.item, this.onTap, this.onRemove});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(color: Joy.primarySoft.withValues(alpha: .6), borderRadius: BorderRadius.circular(12), border: Border(right: BorderSide(color: Joy.primary.withValues(alpha: .6), width: 3))),
          child: Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(9)), child: Icon(item.kind == 'product' ? Icons.local_cafe_outlined : Icons.sell_outlined, size: 17, color: Joy.primary)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('من القائمة', style: TextStyle(fontSize: 10.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 6),
            Text(item.priceLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Joy.primary)),
            if (onRemove != null) SizedBox(width: 28, height: 28, child: IconButton(padding: EdgeInsets.zero, tooltip: 'إزالة الاقتباس', icon: const Icon(Icons.close_rounded, size: 16, color: Joy.textMuted), onPressed: onRemove)),
          ]),
        ),
      );
}

/// اختيار صنف من قائمة الدائرة لاقتباسه: بحث بالاسم وقائمة بالأسعار.
Future<CommunityItemRef?> showCommunityItemPicker(BuildContext context, String bizId) => showModalBottomSheet<CommunityItemRef>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ItemPicker(bizId: bizId),
    );

class _ItemPicker extends ConsumerStatefulWidget {
  final String bizId;
  const _ItemPicker({required this.bizId});
  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final biz = ref.watch(bizDetailProvider(widget.bizId));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(children: [Icon(Icons.format_quote_rounded, color: Joy.primary), SizedBox(width: 8), Expanded(child: Text('اقتبس صنفاً من القائمة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))])),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(key: const Key('item-picker-search'), autofocus: false, onChanged: (v) => setState(() => _q = v.trim()), decoration: const InputDecoration(hintText: 'ابحث في القائمة…', prefixIcon: Icon(Icons.search_rounded), isDense: true)),
        ),
        Expanded(
          child: biz.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e),
            data: (b) {
              final q = _q.toLowerCase();
              final items = b.items.where((i) => i.active && (q.isEmpty || i.title.toLowerCase().contains(q) || i.description.toLowerCase().contains(q))).toList();
              if (items.isEmpty) return const EmptyState(icon: Icons.local_cafe_outlined, title: 'لا أصناف مطابقة');
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = items[i];
                  return ListTile(
                    key: Key('pick-item-${it.id}'),
                    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.local_cafe_outlined, color: Joy.primary, size: 20)),
                    title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: it.description.isEmpty ? null : Text(it.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(it.isFree ? 'مجاني' : money(it.price), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary)),
                      if (it.discussions > 0) Padding(padding: const EdgeInsets.only(right: 8), child: Text('${it.discussions} نقاش', style: const TextStyle(fontSize: 11.5, color: Joy.textMuted))),
                    ]),
                    onTap: () => Navigator.pop(context, CommunityItemRef.of(it)),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// مشغّل تسجيل صوتي داخل مشاركة أو رد: تشغيل/إيقاف وشريط تقدّم ومدة. يعمل عبر [VoicePlayer] (play() داخل حدث اللمس لأجل iOS).
/// يقبل رابطاً مرفوعاً أو بايتات محلية (معاينة قبل الإرسال).
class CommunityVoice extends StatefulWidget {
  final String? url;
  final Uint8List? bytes;
  final String? mime;
  final int? ms;
  final bool compact;
  const CommunityVoice({super.key, this.url, this.bytes, this.mime, this.ms, this.compact = false});
  @override
  State<CommunityVoice> createState() => _CommunityVoiceState();
}

class _CommunityVoiceState extends State<CommunityVoice> {
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  Object? _err;

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_err != null && widget.url != null) {
      launchUrl(Uri.parse(mediaUrl(widget.url!)), mode: LaunchMode.externalApplication);
      return;
    }
    var p = _player;
    if (p == null) {
      p = VoicePlayer()..setSource(url: widget.url == null ? null : mediaUrl(widget.url!), bytes: widget.bytes, mime: widget.mime);
      _sub = p.changes.listen((s) {
        if (s.error != null) _fail(s.error!);
        if (mounted) setState(() {});
      });
      setState(() => _player = p);
    }
    if (p.state.playing) {
      p.pause();
    } else {
      p.play().catchError(_fail); // قبل أي await: iOS لا يقبل بدء التشغيل إلا داخل حدث المستخدم
    }
  }

  void _fail(Object e) {
    if (!mounted || _err != null) return;
    setState(() => _err = e);
    toast(context, 'تعذر تشغيل التسجيل على هذا الجهاز، اضغط عليه مجدداً لفتحه في المتصفح', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final s = p?.state ?? const VoiceState();
    final total = s.duration ?? (widget.ms != null ? Duration(milliseconds: widget.ms!) : Duration.zero);
    final frac = total.inMilliseconds == 0 ? 0.0 : (s.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final size = widget.compact ? 32.0 : 40.0;
    return Container(
      padding: EdgeInsets.fromLTRB(6, widget.compact ? 4 : 6, 12, widget.compact ? 4 : 6),
      decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Material(
          color: Joy.primary,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('community-voice-play'),
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: SizedBox(
              width: size,
              height: size,
              child: s.loading && !s.playing && _err == null
                  ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_err != null ? Icons.open_in_new_rounded : s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Joy.primaryOn, size: widget.compact ? 20 : 24),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: SliderComponentShape.noOverlay, activeTrackColor: Joy.primary, inactiveTrackColor: Joy.control, thumbColor: Joy.primary),
            child: Slider(value: frac, onChanged: p == null ? null : (v) => p.seek(Duration(milliseconds: (v * total.inMilliseconds).round()))),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.mic_rounded, size: 14, color: Joy.textMuted),
        const SizedBox(width: 2),
        Text(s.playing || s.position > Duration.zero ? _fmt(s.position) : _fmt(total), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// شبكة صور المشاركة (حتى 10): صورة واحدة عريضة، أو شبكة، والرابعة تحمل «+N» عند وجود أكثر من أربع. اللمس يفتح المعرض.
class CommunityImages extends StatelessWidget {
  final List<String> images;
  const CommunityImages({super.key, required this.images});
  @override
  Widget build(BuildContext context) {
    final n = images.length;
    Widget tile(int i, {double aspect = 1, int more = 0}) => GestureDetector(
          onTap: () => showCommunityGallery(context, images, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  color: Joy.surface2,
                  child: Image.network(thumbUrl(images[i]), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Joy.textMuted))),
                ),
                if (more > 0)
                  Container(
                    color: Colors.black.withValues(alpha: .45),
                    alignment: Alignment.center,
                    child: Text('+$more', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
          ),
        );
    if (n == 1) return tile(0, aspect: 16 / 10);
    if (n == 2) return Row(children: [Expanded(child: tile(0)), const SizedBox(width: 4), Expanded(child: tile(1))]);
    if (n == 3) {
      return Row(children: [
        Expanded(flex: 3, child: tile(0, aspect: 1)),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: Column(children: [tile(1, aspect: 1.5), const SizedBox(height: 4), tile(2, aspect: 1.5)])),
      ]);
    }
    return Column(children: [
      Row(children: [Expanded(child: tile(0, aspect: 1.4)), const SizedBox(width: 4), Expanded(child: tile(1, aspect: 1.4))]),
      const SizedBox(height: 4),
      Row(children: [Expanded(child: tile(2, aspect: 1.4)), const SizedBox(width: 4), Expanded(child: tile(3, aspect: 1.4, more: n - 4))]),
    ]);
  }
}

Future<void> showCommunityGallery(BuildContext context, List<String> images, int index) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(backgroundColor: Colors.black, child: _Gallery(images: images, index: index)),
    );

class _Gallery extends StatefulWidget {
  final List<String> images;
  final int index;
  const _Gallery({required this.images, required this.index});
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;
  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => Center(child: InteractiveViewer(maxScale: 5, child: Image.network(mediaUrl(widget.images[i]), errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)))),
        ),
        Positioned(top: 8, left: 8, child: SafeArea(child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context)))),
        if (widget.images.length > 1)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: SafeArea(child: Center(child: Text('${_i + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)))),
          ),
      ]);
}

/// قائمة خيارات المشاركة حسب الصلاحية: حذف للكاتب، تثبيت/إخفاء/حذف للإدارة، إبلاغ/حظر للآخرين.
Future<String?> showCommunityPostMenu(BuildContext context, CommunityPost p, {required bool canModerate}) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canModerate) ...[
            ListTile(key: const Key('community-menu-pin'), leading: Icon(p.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded), title: Text(p.pinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'), onTap: () => Navigator.pop(ctx, 'pin')),
            ListTile(key: const Key('community-menu-hide'), leading: Icon(p.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), title: Text(p.hidden ? 'إظهار المشاركة' : 'إخفاء عن الزوار'), onTap: () => Navigator.pop(ctx, 'hide')),
          ],
          if (p.mine || canModerate) ListTile(key: const Key('community-menu-delete'), leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف المشاركة', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!p.mine) ...[
            ListTile(key: const Key('community-menu-report'), leading: const Icon(Icons.flag_outlined), title: const Text('إبلاغ عن المشاركة'), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(key: const Key('community-menu-block'), leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${p.user.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );

/// مؤلّف المشاركة أو الرد: نص، صور (حتى 10 تُرفع فور اختيارها)، تسجيل صوتي (يُرفع عند إيقافه ويظهر كمرفق يمكن سماعه
/// وحذفه)، اختيار الموضوع للمشاركات، وزر إرسال. مفاتيح الاختبار تبدأ بـ [keyPrefix].
class CommunityComposer extends ConsumerStatefulWidget {
  final String bizId;
  final Future<void> Function(CommunityDraft draft) onSend;
  final bool showTopic;
  final String hint, keyPrefix;
  final int maxLength;
  final CommunityItemRef? initialItem;
  const CommunityComposer({super.key, required this.bizId, required this.onSend, this.showTopic = true, this.hint = 'شارك تجربتك أو اسأل…', this.keyPrefix = 'community', this.maxLength = 1000, this.initialItem});
  @override
  ConsumerState<CommunityComposer> createState() => _CommunityComposerState();
}

class _CommunityComposerState extends ConsumerState<CommunityComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  String _topic = 'general';
  final List<({String url, Uint8List bytes})> _images = [];
  ({String url, Uint8List bytes, String mime, Duration duration})? _voice;
  CommunityItemRef? _quote;
  VoiceRecordSession? _rec;

  @override
  void initState() {
    super.initState();
    _quote = widget.initialItem;
  }

  Future<void> _pickQuote() async {
    final it = await showCommunityItemPicker(context, widget.bizId);
    if (it != null && mounted) setState(() => _quote = it);
  }
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _uploading = false, _sending = false, _recording = false;

  @override
  void dispose() {
    _recTimer?.cancel();
    _rec?.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && !_uploading && !_recording && (_text.text.trim().isNotEmpty || _images.isNotEmpty || _voice != null);
  String get _hint => _quote != null ? 'ما رأيك في ${_quote!.title}؟' : widget.hint;
  Key _k(String s) => Key('${widget.keyPrefix}-$s');

  Future<void> _pick({bool camera = false}) async {
    if (_images.length >= communityMaxImages) {
      toast(context, 'حتى $communityMaxImages صور في المشاركة');
      return;
    }
    final img = await pickImage(camera: camera);
    if (img == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (!mounted) return;
      setState(() {
        _images.add((url: up.url, bytes: img.bytes));
        if (_topic == 'general' && _text.text.trim().isEmpty && _voice == null) _topic = 'photo';
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر رفع الصورة', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---- التسجيل الصوتي
  Future<void> _startRecording() async {
    if (_voice != null) {
      toast(context, 'احذف التسجيل الحالي أولاً');
      return;
    }
    final rec = _rec ??= VoiceRecordSession();
    try {
      await rec.start();
    } catch (e) {
      if (mounted) toast(context, 'تعذر بدء التسجيل: ${e.toString().replaceFirst('Bad state: ', '')}', error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recElapsed = Duration.zero;
    });
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recElapsed += const Duration(seconds: 1));
      if (_recElapsed >= maxVoiceRecord) _stopRecording(keep: true);
    });
  }

  Future<void> _stopRecording({required bool keep}) async {
    _recTimer?.cancel();
    final rec = _rec;
    if (!_recording || rec == null) return;
    setState(() => _recording = false);
    try {
      if (!keep) {
        await rec.cancel();
        return;
      }
      final v = await rec.stop();
      if (v == null || v.duration < const Duration(seconds: 1)) {
        if (mounted) toast(context, 'التسجيل قصير جداً');
        return;
      }
      if (!mounted) return;
      setState(() => _uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(v.bytes, contentType: v.mime, fileName: v.name);
      if (!mounted) return;
      setState(() => _voice = (url: up.url, bytes: v.bytes, mime: v.mime, duration: v.duration));
    } catch (e) {
      if (mounted) toast(context, 'تعذر حفظ التسجيل', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    try {
      final v = _voice;
      await widget.onSend((topic: _topic, text: _text.text.trim(), images: [for (final i in _images) i.url], audio: v?.url, audioMs: v?.duration.inMilliseconds, itemId: _quote?.id));
      if (!mounted) return;
      setState(() {
        _text.clear();
        _images.clear();
        _voice = null;
        _quote = null;
        _topic = 'general';
      });
    } catch (e) {
      if (mounted && e is! StateError) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = topicColor(_topic);
    final voice = _voice;
    return Container(
      decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_quote != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: CommunityQuoteChip(key: _k('quote-chip'), item: _quote!, onRemove: () => setState(() => _quote = null))),
        if (voice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: CommunityVoice(key: _k('voice-preview'), bytes: voice.bytes, mime: voice.mime, ms: voice.duration.inMilliseconds, compact: true)),
              IconButton(key: _k('voice-remove'), tooltip: 'حذف التسجيل', icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger), onPressed: () => setState(() => _voice = null)),
            ]),
          ),
        if (_images.isNotEmpty || _uploading)
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              if (_images.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 22, left: 6, right: 2), child: Text('${_images.length}/$communityMaxImages', style: const TextStyle(fontSize: 11.5, color: Joy.textMuted, fontWeight: FontWeight.w600))),
              for (final (i, im) in _images.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(im.bytes, width: 58, height: 58, fit: BoxFit.cover)),
                    Positioned(top: -6, left: -6, child: GestureDetector(onTap: () => setState(() => _images.removeAt(i)), child: Container(decoration: const BoxDecoration(color: Joy.danger, shape: BoxShape.circle), padding: const EdgeInsets.all(2), child: const Icon(Icons.close_rounded, size: 13, color: Colors.white)))),
                  ]),
                ),
              if (_uploading) const Padding(padding: EdgeInsets.all(18), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ]),
          ),
        if (_recording)
          Row(children: [
            IconButton(key: _k('rec-cancel'), tooltip: 'إلغاء التسجيل', onPressed: () => _stopRecording(keep: false), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger, size: 26)),
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Joy.danger, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('${_fmt(_recElapsed)} / ${_fmt(maxVoiceRecord)}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Expanded(child: Text('جارٍ التسجيل… اضغط ✓ عند الانتهاء', style: TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton.filled(key: _k('rec-stop'), tooltip: 'إنهاء التسجيل', style: IconButton.styleFrom(backgroundColor: Joy.primary), icon: const Icon(Icons.check_rounded, size: 22), onPressed: () => _stopRecording(keep: true)),
            ),
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (widget.showTopic) ...[
              PopupMenuButton<String>(
                key: _k('topic'),
                tooltip: 'الموضوع',
                initialValue: _topic,
                onSelected: (t) => setState(() => _topic = t),
                itemBuilder: (_) => [for (final e in communityTopics.entries) PopupMenuItem(value: e.key, child: Row(children: [Icon(topicIcon(e.key), size: 18, color: topicColor(e.key)), const SizedBox(width: 8), Text(e.value)]))],
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(color: tc.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(topicIcon(_topic), size: 17, color: tc), const SizedBox(width: 3), Text(communityTopics[_topic]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tc)), Icon(Icons.expand_more_rounded, size: 16, color: tc)]),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: TextField(
                key: _k('input'),
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                maxLength: widget.maxLength,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _hint,
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Joy.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            IconButton(key: _k('quote'), tooltip: 'اقتباس صنف من القائمة', visualDensity: VisualDensity.compact, icon: Icon(Icons.format_quote_rounded, color: _quote == null ? Joy.primary : Joy.control), onPressed: _quote != null ? null : _pickQuote),
            IconButton(key: _k('photo'), tooltip: 'إضافة صورة', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_photo_alternate_outlined, color: Joy.primary), onPressed: _uploading ? null : () => _pick()),
            IconButton(key: _k('mic'), tooltip: 'تسجيل صوتي', visualDensity: VisualDensity.compact, icon: Icon(Icons.mic_none_rounded, color: voice == null ? Joy.primary : Joy.control), onPressed: _uploading || voice != null ? null : _startRecording),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton.filled(
                key: _k('send'),
                tooltip: 'نشر',
                style: IconButton.styleFrom(backgroundColor: _canSend ? Joy.primary : Joy.control),
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 20),
                onPressed: _canSend ? _send : null,
              ),
            ),
          ]),
      ]),
    );
  }
}

/// نقاش مشاركة: المشاركة كاملة ثم الردود بترتيب زمني، ومؤلّف رد في الأسفل (نص/صوت/صور).
class CommunityThreadPage extends ConsumerStatefulWidget {
  final String bizId, postId, title;
  const CommunityThreadPage({super.key, required this.bizId, required this.postId, this.title = ''});
  @override
  ConsumerState<CommunityThreadPage> createState() => _CommunityThreadPageState();
}

class _CommunityThreadPageState extends ConsumerState<CommunityThreadPage> {
  CommunityPost? _patched;
  final Set<String> _removedReplies = {};
  final Map<String, CommunityReply> _replyPatch = {};

  Future<void> _likeReply(CommunityReply r) async {
    try {
      final res = await ref.read(apiClientProvider).communityReplyLike(widget.bizId, widget.postId, r.id);
      if (mounted) setState(() => _replyPatch[r.id] = (_replyPatch[r.id] ?? r).copyWith(liked: res.liked, likes: res.likes));
    } catch (e) {
      if (mounted) toast(context, 'تعذر تسجيل القلب', error: true);
    }
  }

  ({String bizId, String postId}) get _arg => (bizId: widget.bizId, postId: widget.postId);

  Future<void> _reply(CommunityDraft d) async {
    final banned = bannedWordIn(d.text, ref.read(bannedWordsProvider).valueOrNull ?? const []);
    if (banned != null) {
      toast(context, 'النص يحتوي كلمة غير مسموحة: «$banned»', error: true);
      throw StateError('banned');
    }
    await ref.read(apiClientProvider).communityReply(widget.bizId, widget.postId, text: d.text, images: d.images, audio: d.audio, audioMs: d.audioMs, itemId: d.itemId);
    if (mounted) ref.invalidate(communityThreadProvider(_arg));
  }

  Future<void> _like(CommunityPost p) async {
    try {
      final r = await ref.read(apiClientProvider).communityLike(widget.bizId, p.id);
      if (mounted) setState(() => _patched = p.copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) toast(context, 'تعذر تسجيل الإعجاب', error: true);
    }
  }

  Future<void> _menu(CommunityPost p, bool canModerate) async {
    final choice = await showCommunityPostMenu(context, p, canModerate: canModerate);
    if (!mounted || choice == null) return;
    final api = ref.read(apiClientProvider);
    try {
      switch (choice) {
        case 'pin':
          final r = await api.communityPin(widget.bizId, p.id, !p.pinned);
          if (mounted) setState(() => _patched = r);
        case 'hide':
          final r = await api.communityHide(widget.bizId, p.id, !p.hidden);
          if (mounted) setState(() => _patched = r);
        case 'delete':
          await api.communityDelete(widget.bizId, p.id);
          if (mounted) Navigator.pop(context);
        case 'report':
          final reason = await askText(context, title: 'إبلاغ عن المشاركة', hint: 'ما المشكلة؟', confirm: 'إرسال البلاغ');
          if (reason == null || reason.isEmpty || !mounted) return;
          final r = await api.reportContent(type: 'community', id: p.id, reason: reason);
          if (mounted) toast(context, r.hidden ? 'وصل بلاغك وأُخفيت المشاركة للمراجعة' : 'وصل بلاغك وستراجعه إدارة الدائرة');
        case 'block':
          await api.blockUser(p.user.id);
          if (mounted) {
            toast(context, 'تم حظر ${p.user.nickname}');
            Navigator.pop(context);
          }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _deleteReply(CommunityReply r) async {
    try {
      await ref.read(apiClientProvider).communityDeleteReply(widget.bizId, widget.postId, r.id);
      if (mounted) setState(() => _removedReplies.add(r.id));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = ref.watch(communityThreadProvider(_arg));
    ref.watch(bannedWordsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('النقاش')),
      body: th.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(communityThreadProvider(_arg))),
        data: (t) {
          final p = _patched ?? t.post;
          final replies = [for (final r in t.replies) if (!_removedReplies.contains(r.id)) _replyPatch[r.id] ?? r];
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 16), children: [
                CommunityPostCard(post: p.copyWith(replies: replies.length), canModerate: t.canModerate, expanded: true, onLike: () => _like(p), onMenu: () => _menu(p, t.canModerate)),
                const SizedBox(height: 14),
                if (replies.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('لا ردود بعد — كن أول من يرد', style: TextStyle(color: Joy.textMuted))))
                else
                  for (final r in replies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ReplyTile(reply: r, onLike: () => _likeReply(r), onDelete: r.mine || t.canModerate ? () => _deleteReply(r) : null),
                    ),
              ]),
            ),
            CommunityComposer(bizId: widget.bizId, keyPrefix: 'community-reply', showTopic: false, hint: 'اكتب رداً أو سجّل صوتاً…', maxLength: 500, onSend: _reply),
          ]);
        },
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  final CommunityReply reply;
  final VoidCallback? onDelete, onLike;
  const _ReplyTile({required this.reply, this.onDelete, this.onLike});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 26),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(name: reply.user.nickname, url: reply.user.avatarUrl, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: reply.mine ? Joy.bubbleOut : Joy.surface2, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(reply.mine ? 'أنت' : reply.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Text(timeAgo(reply.createdAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                  if (onDelete != null) SizedBox(width: 26, height: 22, child: IconButton(padding: EdgeInsets.zero, tooltip: 'حذف الرد', icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Joy.textMuted), onPressed: onDelete)),
                ]),
                if (reply.item != null) Padding(padding: const EdgeInsets.only(top: 6), child: CommunityQuoteChip(item: reply.item!)),
                if (reply.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(reply.text, style: const TextStyle(fontSize: 14.5, height: 1.5))),
                if (reply.audio != null) Padding(padding: const EdgeInsets.only(top: 6), child: CommunityVoice(url: reply.audio, ms: reply.audioMs, compact: true)),
                if (reply.images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: CommunityImages(images: reply.images)),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _Action(key: Key('reply-like-${reply.id}'), icon: reply.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: reply.liked ? Joy.accent : Joy.textMuted, label: reply.likes == 0 ? 'قلب' : '${reply.likes}', onTap: onLike),
                ),
              ]),
            ),
          ),
        ]),
      );
}

/// بطاقة الدخول إلى مساحة المجتمع في أعلى صفحة الدائرة: عدد المشاركات والمشاركين وآخر مشاركتين وزر الفتح.
class CommunityEntryCard extends ConsumerWidget {
  final String bizId, title;
  final bool prominent;
  const CommunityEntryCard({super.key, required this.bizId, required this.title, this.prominent = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(communityFeedProvider((bizId: bizId, topic: null, itemId: null, sort: 'new'))).valueOrNull;
    final latest = feed?.posts.where((p) => !p.hidden).take(2).toList() ?? const <CommunityPost>[];
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityPage(bizId: bizId, title: title)));
    return JoyCard(
      key: const Key('community-card'),
      color: prominent ? Joy.primarySoft.withValues(alpha: .5) : null,
      onTap: open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.forum_rounded, color: Joy.primaryOn)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مساحة المجتمع', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              Text(
                feed == null ? 'تواصل مع الزوار بنص أو صوت أو صور' : (feed.total == 0 ? 'كن أول من يشارك تجربته هنا' : '${feed.total} مشاركة من ${feed.members} مشارك'),
                style: const TextStyle(color: Joy.textMuted, fontSize: 12.5),
              ),
            ]),
          ),
          FilledButton.tonal(key: const Key('community-open'), onPressed: open, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('شارك')),
        ]),
        if (latest.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final p in latest)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Avatar(name: p.user.nickname, url: p.user.avatarUrl, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 13, color: Joy.text), children: [
                      TextSpan(text: '${p.user.nickname}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: p.preview),
                    ]),
                  ),
                ),
                const SizedBox(width: 6),
                Text(timeAgo(p.createdAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
              ]),
            ),
        ],
      ]),
    );
  }
}
