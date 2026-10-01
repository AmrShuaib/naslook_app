import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/live_api.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../state/live_providers.dart';
import '../../state/posts_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';
import 'post_viewer.dart';

/// «الخط الزمني»: قائمة مبسّطة بكل المشاركات الموجودة على الخريطة الآن، الأحدث أولاً، تتحدّث وحدها.
/// صف واحد لكل مشاركة (صورة مصغّرة، الناشر، المكان، الوقت)، ولمسه يفتح العارض عند تلك المشاركة.
/// الجديد يصل فوراً عبر «القناة الحية» ([LiveChannel]: لحظة نُشرت تُدرج في مكانها، لحظة حُذفت تُزال)، والجلب الدوري كل
/// [refreshEvery] وعند العودة إلى التطبيق احتياط فقط؛ ما يصل أثناء التمرير يظهر في كبسولة «N جديد» بدل أن يقفز القائمة.
class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});
  static const refreshEvery = Duration(seconds: 60);
  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  Timer? _timer;
  StreamSubscription<LiveEvent>? _liveSub;
  LiveChannel? _live;
  /// المعرّفات المعروضة الآن؛ ما ليس فيها عند وصول جلب جديد يُعدّ «جديداً»
  Set<String> _shown = {};
  List<MapPost> _items = const [];
  int _pendingNew = 0;
  bool _atTop = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(TimelinePage.refreshEvery, (_) { if (mounted) ref.invalidate(timelineProvider); });
    // قائمة مخزّنة من زيارة سابقة قد تفوتها لحظات وصلت حيّةً آنذاك: جلب جديد عند كل فتح (الفتح الأول يجلب أصلاً)
    if (ref.read(timelineProvider).hasValue) Future.microtask(() { if (mounted) ref.invalidate(timelineProvider); });
    _subscribeLive(ref.read(liveChannelProvider));
    _scroll.addListener(() {
      final top = _scroll.offset < 40;
      if (top != _atTop) setState(() => _atTop = top);
      // الوصول إلى الأعلى يعتمد الجديد تلقائياً
      if (top && _pendingNew > 0) _applyPending();
    });
  }

  void _subscribeLive(LiveChannel c) {
    _liveSub?.cancel();
    _live = c;
    _liveSub = c.events.listen(_onLive);
  }

  /// حدث حيّ: لحظة جديدة تُدرج في أعلى القائمة (أو خلف الكبسولة إن كان المستخدم يتصفح)، والمحذوفة تُزال في مكانها
  void _onLive(LiveEvent e) {
    if (!mounted) return;
    if (e.isReset || e.kind == LiveEvent.postRestored) {
      ref.invalidate(timelineProvider);
    } else if (e.kind == LiveEvent.post) {
      final MapPost p;
      try {
        p = MapPost.fromJson(e.data);
      } catch (_) {
        ref.invalidate(timelineProvider);
        return;
      }
      if (ref.read(blockedIdsProvider).contains(p.user.id.toUpperCase())) return;
      _onFetched([p, ..._latest.where((x) => x.id != p.id)]);
    } else if (e.kind == LiveEvent.postRemoved) {
      final id = e.data['id']?.toString();
      if (id == null) return;
      _latest = _latest.where((x) => x.id != id).toList();
      setState(() {
        _items = _items.where((x) => x.id != id).toList();
        _shown.remove(id);
        if (_pendingNew > 0) _pendingNew = _latest.where((x) => !_shown.contains(x.id)).length;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _liveSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) ref.invalidate(timelineProvider);
  }

  List<MapPost> _latest = const [];

  /// جلب جديد: إن كان المستخدم في الأعلى نعرضه فوراً، وإلا نحتفظ به ونعدّ الجديد في الكبسولة
  void _onFetched(List<MapPost> list) {
    _latest = list;
    final fresh = list.where((p) => !_shown.contains(p.id)).length;
    if (_shown.isEmpty || _atTop || fresh == 0) {
      _applyPending();
    } else {
      setState(() => _pendingNew = fresh);
    }
  }

  void _applyPending() {
    setState(() {
      _items = _latest;
      _shown = {for (final p in _latest) p.id};
      _pendingNew = 0;
    });
  }

  void _toTop() {
    _applyPending();
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<MapPost>>>(timelineProvider, (_, next) {
      final v = next.valueOrNull;
      if (v != null) _onFetched(v);
    });
    // تغيّر الحساب يستبدل القناة: نعيد الاشتراك في الجديدة
    ref.listen<LiveChannel>(liveChannelProvider, (_, next) { if (next != _live) _subscribeLive(next); });
    final online = ref.watch(liveChannelProvider).online;
    final state = ref.watch(timelineProvider);
    if (_items.isEmpty && state.hasValue && _shown.isEmpty) {
      // أول جلب وصل قبل أن يسجّل المستمع (الصفحة بُنيت والقيمة جاهزة من ذاكرة المزوّد)
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _shown.isEmpty) _onFetched(state.value!); });
    }
    final groups = _group(_items);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الخط الزمني'),
        actions: [
          // مؤشر «مباشر» وعدد المشاركات في الإجراءات لا في العنوان حتى لا يفيض على الشاشات الضيقة
          Row(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<bool>(valueListenable: online, builder: (_, on, __) => _LiveDot(on: on)),
            const SizedBox(width: 5),
            Text(_items.isEmpty ? 'مباشر' : 'مباشر · ${_items.length}', key: const Key('tl-live'), style: const TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          ]),
          IconButton(key: const Key('tl-refresh'), tooltip: 'تحديث', onPressed: () => ref.invalidate(timelineProvider), icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Stack(children: [
        if (state.isLoading && _items.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.hasError && _items.isEmpty)
          ErrorState(state.error!, onRetry: () => ref.invalidate(timelineProvider))
        else if (_items.isEmpty)
          const EmptyState(icon: Icons.auto_awesome_outlined, title: 'لا مشاركات على الخريطة الآن', subtitle: 'كل لحظة تُنشر على الخريطة تظهر هنا في وقتها')
        else
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(timelineProvider);
              await ref.read(timelineProvider.future);
            },
            child: ListView.builder(
              key: const Key('tl-list'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
              itemCount: groups.fold<int>(0, (n, g) => n + 1 + g.items.length),
              itemBuilder: (context, i) {
                var k = i;
                for (final g in groups) {
                  if (k == 0) return Padding(key: Key('tl-group-${g.title}'), padding: const EdgeInsets.fromLTRB(2, 12, 2, 6), child: Text(g.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Joy.textMuted)));
                  k -= 1;
                  if (k < g.items.length) {
                    final p = g.items[k];
                    return _Row(post: p, onTap: () => _open(p));
                  }
                  k -= g.items.length;
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        if (_pendingNew > 0)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                key: const Key('tl-new'),
                onPressed: _toTop,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), shape: const StadiumBorder()),
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                label: Text(_pendingNew == 1 ? 'مشاركة جديدة' : '$_pendingNew جديدة'),
              ),
            ),
          ),
      ]),
    );
  }

  void _open(MapPost p) {
    final i = _items.indexWhere((x) => x.id == p.id);
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PostViewerPage(posts: _items, initial: i < 0 ? 0 : i)));
  }

  /// تجميع زمني: الآن (١٠ دقائق)، آخر ساعة، اليوم، أمس، أقدم
  static List<_Group> _group(List<MapPost> items) {
    final now = DateTime.now();
    final out = <String, List<MapPost>>{};
    for (final p in items) {
      final t = p.createdAt ?? now;
      final d = now.difference(t);
      final key = d.inMinutes < 10 ? 'الآن' : d.inHours < 1 ? 'آخر ساعة' : (t.day == now.day && t.month == now.month) ? 'اليوم' : d.inHours < 48 ? 'أمس' : 'أقدم';
      out.putIfAbsent(key, () => []).add(p);
    }
    const order = ['الآن', 'آخر ساعة', 'اليوم', 'أمس', 'أقدم'];
    return [for (final k in order) if (out.containsKey(k)) _Group(k, out[k]!)];
  }
}

class _Group {
  final String title;
  final List<MapPost> items;
  const _Group(this.title, this.items);
}

/// صف مشاركة: مصغّرة الوسيط (أو رمز النوع)، الناشر، التعليق أو المكان، والوقت.
class _Row extends StatelessWidget {
  final MapPost post;
  final VoidCallback onTap;
  const _Row({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final icon = switch (p.kind) { 'video' => Icons.videocam_rounded, 'audio' => Icons.mic_rounded, 'text' => Icons.notes_rounded, _ => Icons.photo_camera_rounded };
    final media = p.mediaUrl;
    final line = p.caption.isNotEmpty ? p.caption : p.title.isNotEmpty ? p.title : switch (p.kind) { 'video' => 'فيديو', 'audio' => 'تسجيل صوتي', 'text' => 'لحظة نصية', _ => 'صورة' };
    final where = [if (p.placeName != null && p.placeName!.isNotEmpty) p.placeName!, timeAgo(p.createdAt)].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Joy.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('tl-post-${p.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Joy.line)),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: media != null && p.kind != 'audio'
                      ? Image.network(thumbUrl(media), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(icon))
                      : _fallback(icon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Avatar(name: p.user.nickname, url: p.user.avatarUrl, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.user.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                    Icon(icon, size: 14, color: Joy.textMuted),
                  ]),
                  const SizedBox(height: 3),
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: Joy.text)),
                  const SizedBox(height: 2),
                  Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
                ]),
              ),
              if (p.likes > 0) ...[
                const SizedBox(width: 6),
                Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.favorite_rounded, size: 14, color: Joy.accent), Text('${p.likes}', style: const TextStyle(fontSize: 11, color: Joy.textMuted))]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _fallback(IconData icon) => Container(color: Joy.primarySoft, child: Icon(icon, color: Joy.primary, size: 24));
}

/// نقطة حمراء تنبض: القناة الحية متصلة؛ رمادية ثابتة حين تنقطع (يبقى الجلب الدوري).
class _LiveDot extends StatefulWidget {
  final bool on;
  const _LiveDot({required this.on});
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return Container(key: const Key('tl-live-off'), width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF9CA3AF), shape: BoxShape.circle));
    return FadeTransition(
      key: const Key('tl-live-on'),
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle)),
    );
  }
}
