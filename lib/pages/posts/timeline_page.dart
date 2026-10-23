import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints, SliverGridGeometry, SliverGridLayout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/client.dart';
import '../../api/live_api.dart';
import '../../api/posts_api.dart' show distanceText;
import '../../api/row_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/video_view.dart';
import '../../core/nav_provider.dart';
import '../../state/feed_providers.dart';
import '../../state/live_providers.dart';
import '../../state/safety_providers.dart';
import '../../state/search_providers.dart';
import '../../ui/widgets.dart';
import '../events/events_page.dart';
import '../home/row_deck.dart';
import '../home/row_open.dart';
import '../jobs/jobs_page.dart';
import '../market/market_page.dart';
import 'my_posts_page.dart';
import 'overlay_canvas.dart' show colorFromHex;
import 'post_media.dart' show videoPreviewUrl;

/// «اللحظات» (قرار المالك 22 أكتوبر 2026): شبكة متدرّجة بعمودين من بطاقات متوسطة تتحرك كالصور المتحركة (الفيديو يدور صامتاً بلا
/// شريط تحكم، الصورة تتقرّب ببطء، النص على تدرّج لوني) لكل ما يبثه `GET /feed` الأحدث أولاً: لحظات وعروض وفعاليات ووظائف
/// وسوق ودوائر «هنا اليوم». الرقاقة «عام» افتراضية وبقية الأنواع في الشريط العلوي. التصفح بالمؤشر عند الاقتراب من النهاية،
/// والجديد يصل فوراً عبر «القناة الحية» ([LiveChannel]) ويُدرج في الأعلى، أو خلف كبسولة «N جديدة» إن كان المستخدم يتصفح.
/// الجلب الدوري كل [refreshEvery] وعند العودة إلى التطبيق احتياط فقط.
class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});
  static const refreshEvery = Duration(seconds: 60);
  /// أقصى معاينات فيديو تدور معاً؛ ما بعدها يعرض إطاره الثابت حتى تُحرَّر فتحة
  static const maxLoopingPreviews = 4;
  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _videos = _PreviewRegistry(TimelinePage.maxLoopingPreviews);
  Timer? _timer;
  StreamSubscription<LiveEvent>? _liveSub;
  LiveChannel? _live;
  String _kind = 'all';
  /// مفاتيح البطاقات التي وصلت للتو فتدخل بحركة مرة واحدة
  final _fresh = <String>{};

  MomentsNotifier get _n => ref.read(momentsProvider(_kind).notifier);

  /// في الأعلى؟ من موضع التمرير نفسه لا من حالة محفوظة: الشبكة التي يُعاد بناؤها بعد فراغ أو تحميل تبدأ من الصفر بلا حدث تمرير،
  /// وبلا شبكة (فراغ أو تحميل) لا شيء يُخفى تحت الإصبع
  bool get _atTop => !_scroll.hasClients || _scroll.offset < 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(TimelinePage.refreshEvery, (_) { if (mounted) _n.refresh(applyNow: _atTop); });
    // قائمة مخزّنة من زيارة سابقة قد تفوتها لحظات وصلت حيّةً آنذاك: تحديث عند كل فتح (الفتح الأول يجلب أصلاً)
    if (ref.read(momentsProvider(_kind)).loaded) Future.microtask(() { if (mounted) _n.refresh(); });
    _subscribeLive(ref.read(liveChannelProvider));
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // الوصول إلى الأعلى يعتمد الجديد تلقائياً
    if (_atTop && ref.read(momentsProvider(_kind)).pending.isNotEmpty) _applyPending();
    // قرب النهاية: الصفحة الأقدم
    if (_scroll.position.extentAfter < 600) _n.loadMore();
  }

  void _subscribeLive(LiveChannel c) {
    _liveSub?.cancel();
    _live = c;
    _liveSub = c.events.listen(_onLive);
  }

  /// حدث حيّ: لحظة جديدة تُدرج في أعلى «عام» و«لحظات» المفتوحتين (المرئية خلف الكبسولة إن كان المستخدم يتصفح)، والمحذوفة تُزال
  /// في مكانها من كل قائمة مفتوحة لا من المرئية وحدها، فلا تعود عند تبديل الرقاقة.
  void _onLive(LiveEvent e) {
    if (!mounted) return;
    if (e.isReset || e.kind == LiveEvent.postRestored) {
      _n.refresh(applyNow: _atTop);
    } else if (e.kind == LiveEvent.post) {
      final RowItem it;
      final double? km;
      try {
        km = _distanceKm(e.data);
        it = RowItem.moment(e.data, distanceKm: km);
      } catch (_) {
        if (_kind == 'all' || _kind == 'moment') _n.refresh(applyNow: _atTop);
        return;
      }
      final uid = (e.data['user'] is Map ? (e.data['user'] as Map)['id'] : null)?.toString().toUpperCase() ?? '';
      if (ref.read(blockedIdsProvider).contains(uid)) return;
      for (final k in const ['all', 'moment']) {
        if (!ref.exists(momentsProvider(k))) continue;
        // قائمة رُتّبت بالموقع تقصر على نطاقه: لحظة أبعد منه تظهر ثم تختفي مع أول تحديث، فلا تُدرج أصلاً
        if (ref.read(momentsProvider(k)).located && (km == null || km > feedRadiusKm)) continue;
        // القائمة غير المرئية تُدرج فيها مباشرة: تُفتح من الأعلى عند تبديل الرقاقة
        final visible = k == _kind;
        if (ref.read(momentsProvider(k).notifier).pushLive(it, applyNow: !visible || _atTop) && visible) _fresh.add(it.pinKey);
      }
    } else if (e.kind == LiveEvent.postRemoved) {
      final id = e.data['id']?.toString();
      if (id == null) return;
      for (final n in openMoments(ref)) {
        n.removeMoment(id);
      }
    }
  }

  /// مسافة اللحظة الحيّة عن موقع المستخدم الذي رُتّبت به القائمة (حمولة البث عامة بلا مسافة)؛ null إن لم يُعرف أحدهما.
  double? _distanceKm(Map data) {
    final loc = ref.read(userLocationProvider).valueOrNull;
    final lat = (data['lat'] as num?)?.toDouble(), lng = (data['lng'] as num?)?.toDouble();
    if (loc == null || lat == null || lng == null) return null;
    return const Distance().as(LengthUnit.Meter, loc, LatLng(lat, lng)) / 1000;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _liveSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _videos.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _n.refresh(applyNow: _atTop);
  }

  void _setKind(String k) {
    if (k == _kind) return;
    setState(() {
      _kind = k;
      _fresh.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // نوع فُتح من قبل يظهر فوراً من الذاكرة ثم يتحدّث في الخلفية؛ الجديد يجلب عند إنشائه
    if (ref.read(momentsProvider(k)).loaded) ref.read(momentsProvider(k).notifier).refresh();
  }

  void _applyPending() {
    final pending = ref.read(momentsProvider(_kind)).pending;
    _fresh.addAll(pending.map((x) => x.pinKey));
    _n.applyPending();
  }

  void _toTop() {
    _applyPending();
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  Future<void> _refresh() => _n.refresh();

  void _open(RowItem it, List<RowItem> items) => openRowItem(context, it, moments: items);

  @override
  Widget build(BuildContext context) {
    // تغيّر الحساب يستبدل القناة: نعيد الاشتراك في الجديدة
    ref.listen<LiveChannel>(liveChannelProvider, (_, next) { if (next != _live) _subscribeLive(next); });
    // ناشر حُظر (من العارض أو غيره): لحظاته تُزال في مكانها من كل قائمة مفتوحة، ومنها الصفحات الأقدم التي لا يشملها التحديث
    ref.listen<Set<String>>(blockedIdsProvider, (prev, next) {
      for (final uid in next.difference(prev ?? const <String>{})) {
        for (final n in openMoments(ref)) {
          n.removeByUser(uid);
        }
      }
    });
    // ما ينتظر والمستخدم في الأعلى (تحديث بعد نشر أو حذف من العارض) يُعتمد مباشرة كما في الجلب الدوري؛ بعد الإشعار لا أثناءه
    ref.listen<MomentsState>(momentsProvider(_kind), (_, next) {
      if (next.pending.isNotEmpty && _atTop) Future.microtask(() { if (mounted && _atTop) _applyPending(); });
    });
    final online = ref.watch(liveChannelProvider).online;
    final st = ref.watch(momentsProvider(_kind));
    final items = st.items;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final noMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final heights = [for (final it in items) _mediaHeight(it) + _infoHeight(scale)];
    // موضع كل بطاقة بمفتاحها: إدراج في الأعلى أو حذف ينقل العناصر القائمة إلى مواضعها الجديدة بدل هدمها وبنائها من جديد
    // (وإلا أُعيد إنشاء كل مشغّل فيديو وفقدت المعاينات فتحاتها)
    final indexOf = {for (var i = 0; i < items.length; i++) 'tl-${items[i].pinKey}': i};
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('اللحظات'),
        actions: [
          // مؤشر «مباشر» وعدد البطاقات في الإجراءات لا في العنوان حتى لا يفيض على الشاشات الضيقة
          Row(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<bool>(valueListenable: online, builder: (_, on, __) => _LiveDot(on: on)),
            const SizedBox(width: 5),
            Text(items.isEmpty ? 'مباشر' : 'مباشر · ${items.length}', key: const Key('tl-live'), style: const TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          ]),
          IconButton(key: const Key('tl-refresh'), tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(50), child: _KindBar(kind: _kind, onKind: _setKind)),
      ),
      body: Stack(children: [
        if (st.loading && items.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (st.error != null && items.isEmpty)
          ErrorState(st.error!, onRetry: _n.load)
        else if (items.isEmpty)
          RefreshIndicator(
            onRefresh: _refresh,
            // السحب للتحديث يعمل ولو لم يملأ المحتوى الشاشة
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  kind: _kind,
                  onCompose: () async {
                    await composePostHere(context, ref);
                    if (mounted) _n.refresh();
                  },
                  onGoTab: (tab) {
                    // الصفحة فوق الشريط السفلي: نعود إليه ثم نبدّل القسم
                    Navigator.of(context).maybePop();
                    openNavTab(ref, tab);
                  },
                ),
              ),
            ]),
          )
        else
          RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              key: const Key('tl-list'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  sliver: SliverGrid(
                    gridDelegate: _MasonryDelegate(heights, gap: 12),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final it = items[i];
                        return _FeedCard(
                          key: ValueKey('tl-${it.pinKey}'),
                          item: it,
                          mediaHeight: _mediaHeight(it),
                          infoHeight: _infoHeight(scale),
                          videos: _videos,
                          noMotion: noMotion,
                          animateIn: _fresh.contains(it.pinKey),
                          onEntered: () => _fresh.remove(it.pinKey),
                          onTap: () => _open(it, items),
                        );
                      },
                      childCount: items.length,
                      findChildIndexCallback: (key) => key is ValueKey<String> ? indexOf[key.value] : null,
                    ),
                  ),
                ),
                if (st.loadingMore)
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        if (st.pending.isNotEmpty)
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
                // صفحة منفصلة عن القائمة: وراءها أكثر مما تعدّه
                label: Text(st.pending.length == 1 && !st.pendingReplaces ? 'لحظة جديدة' : '${st.pending.length}${st.pendingReplaces ? '+' : ''} جديدة'),
              ),
            ),
          ),
      ]),
    );
  }

  /// ارتفاع الوسيط بحسب النوع مع تنويع ثابت لكل عنصر (من معرّفه) حتى تتدرّج الأعمدة ولا تتساوى صفوفها.
  static double _mediaHeight(RowItem it) {
    final seed = it.id.codeUnits.fold<int>(0, (a, c) => a + c) % 3;
    return switch (it.kind) {
      'moment' => switch (it.payload['kind']?.toString()) { 'text' => 150 + seed * 10.0, 'audio' => 150, _ => 190 + seed * 20.0 },
      'listing' => 190 + seed * 20.0,
      'offer' => 170 + seed * 10.0,
      'circle' => 170,
      'event' => 150 + seed * 10.0,
      'job' => 150,
      _ => 170,
    };
  }

  /// كتلة النص تحت الوسيط بارتفاع ثابت (مع تكبير النص) حتى يُعرف ارتفاع البطاقة قبل بنائها.
  static double _infoHeight(double scale) => 27 + 75 * scale;
}

/// شريط الرقاقات: «عام» ثم الأنواع الستة؛ المختارة بلون نوعها.
class _KindBar extends StatelessWidget {
  final String kind;
  final ValueChanged<String> onKind;
  const _KindBar({required this.kind, required this.onKind});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 50,
        // صف واحد لا قائمة كسولة: سبع رقاقات فقط، وكلها في الشجرة حتى تصل إليها الاختبارات وقارئ الشاشة
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            for (final k in feedKinds)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  key: Key('feed-kind-$k'),
                  label: Text(feedKindLabel(k)),
                  avatar: k == 'all' ? null : Icon(rowKindIcon(k), size: 15, color: kind == k ? Colors.white : rowKindColor(k)),
                  selected: kind == k,
                  showCheckmark: false,
                  onSelected: (_) => onKind(k),
                  selectedColor: k == 'all' ? Joy.primary : rowKindColor(k),
                  backgroundColor: Joy.surface2,
                  side: BorderSide.none,
                  labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kind == k ? Colors.white : Joy.text),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
          ]),
        ),
      );
}

/// شبكة متدرّجة بعمودين بلا حزمة خارجية: ارتفاع كل بطاقة معروف مسبقاً فتُوضع في العمود الأقصر، وتُبنى كسولاً كأي SliverGrid.
class _MasonryDelegate extends SliverGridDelegate {
  final List<double> heights;
  final double gap;
  const _MasonryDelegate(this.heights, {this.gap = 12});

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      _MasonryLayout(heights, crossAxisExtent: constraints.crossAxisExtent, gap: gap, reverse: axisDirectionIsReversed(constraints.crossAxisDirection));

  @override
  bool shouldRelayout(_MasonryDelegate old) => old.gap != gap || !listEquals(old.heights, heights);
}

class _MasonryLayout extends SliverGridLayout {
  final List<double> _tops, _starts, _heights;
  final double _colW, _total;

  factory _MasonryLayout(List<double> heights, {required double crossAxisExtent, required double gap, required bool reverse}) {
    final colW = math.max(0.0, (crossAxisExtent - gap) / 2);
    final tops = <double>[], starts = <double>[];
    final colH = [0.0, 0.0];
    for (final h in heights) {
      final c = colH[0] <= colH[1] ? 0 : 1;
      tops.add(colH[c]);
      final s = c * (colW + gap);
      // في العربية العمود الأول في البداية (اليمين): إزاحة المحور العرضي تُعكس
      starts.add(reverse ? crossAxisExtent - s - colW : s);
      colH[c] += h + gap;
    }
    final total = heights.isEmpty ? 0.0 : math.max(colH[0], colH[1]) - gap;
    return _MasonryLayout._(tops, starts, List.of(heights), colW, total);
  }
  const _MasonryLayout._(this._tops, this._starts, this._heights, this._colW, this._total);

  /// RenderSliverGrid يطلب هندسة أول فهرس حتى بلا أطفال: خارج النطاق هندسة صفرية بدل خطأ
  @override
  SliverGridGeometry getGeometryForChildIndex(int index) => index < 0 || index >= _tops.length
      ? SliverGridGeometry(scrollOffset: _total, crossAxisOffset: 0, mainAxisExtent: 0, crossAxisExtent: _colW)
      : SliverGridGeometry(scrollOffset: _tops[index], crossAxisOffset: _starts[index], mainAxisExtent: _heights[index], crossAxisExtent: _colW);

  /// أول بطاقة قد تكون مرئية: أول عنصر ينتهي بعد الإزاحة (الأعمدة شبه مرتّبة فالمسح الخطي يكفي لقوائم بمئات العناصر)
  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    for (var i = 0; i < _tops.length; i++) {
      if (_tops[i] + _heights[i] >= scrollOffset) return i;
    }
    return _tops.isEmpty ? 0 : _tops.length - 1;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    for (var i = _tops.length - 1; i >= 0; i--) {
      if (_tops[i] <= scrollOffset) return i;
    }
    return 0;
  }

  @override
  double computeMaxScrollOffset(int childCount) => _total;
}

/// فتحات المعاينات الدائرة: أول أربع بطاقات فيديو مرئية تدور، وما بعدها يعرض إطاره الثابت حتى تُحرَّر فتحة (بطاقة خرجت من الشاشة
/// أو حُذفت)، فيُخبر السجلّ المنتظرين فتأخذها أولاها.
class _PreviewRegistry extends ChangeNotifier {
  final int max;
  int _active = 0;
  bool _notifying = false, _disposed = false;
  _PreviewRegistry(this.max);

  bool acquire() {
    if (_active >= max) return false;
    _active++;
    return true;
  }

  /// التحرير يقع أثناء البناء أو التفكيك حيث لا يجوز setState على بطاقة أخرى: الإخبار بعد انتهاء الإطار
  void release() {
    if (_active == 0) return;
    _active--;
    if (_notifying) return;
    _notifying = true;
    scheduleMicrotask(() {
      _notifying = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// البطاقة: وسيط متحرك بارتفاع ثابت (فيديو يدور، صورة تتقرّب، نص على تدرّج) فوقه رقاقة النوع، ثم الناشر والعنوان وسطر الوقت
/// والمسافة، وفعل البطاقة لغير اللحظات.
class _FeedCard extends StatelessWidget {
  final RowItem item;
  final double mediaHeight, infoHeight;
  final _PreviewRegistry videos;
  final bool noMotion, animateIn;
  final VoidCallback onEntered, onTap;
  const _FeedCard({super.key, required this.item, required this.mediaHeight, required this.infoHeight, required this.videos, required this.noMotion, required this.animateIn, required this.onEntered, required this.onTap});

  bool get _isMoment => item.kind == 'moment';
  String get _postKind => item.payload['kind']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final color = rowKindColor(item.kind);
    final it = item;
    final isText = _isMoment && _postKind == 'text';
    final place = _isMoment ? (it.payload['placeName']?.toString().trim() ?? '') : '';
    // اللحظة النصية تعرض نصها كبيراً في الوسيط فلا يُكرَّر في العنوان: مكانها بدله
    final title = isText ? (place.isNotEmpty ? place : 'لحظة نصية') : it.title;
    final meta = _isMoment
        ? [timeAgo(it.at), if (it.distanceKm != null) distanceText(it.distanceKm), if (place.isNotEmpty && !isText) place].where((s) => s.isNotEmpty).join(' · ')
        : [it.subtitle, if (it.distanceKm != null) distanceText(it.distanceKm)].where((s) => s.isNotEmpty).join(' · ');
    return _EnterIn(
      enabled: animateIn && !noMotion,
      onDone: onEntered,
      child: Material(
        color: Joy.surface,
        elevation: 1.5,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: _isMoment ? Key('tl-post-${it.id}') : Key('tl-card-${it.kind}-${it.id}'),
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: mediaHeight,
              child: Stack(fit: StackFit.expand, children: [
                _Media(item: it, videos: videos, noMotion: noMotion),
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(rowKindIcon(it.kind), size: 12, color: color),
                      const SizedBox(width: 4),
                      Text(it.kindLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
                    ]),
                  ),
                ),
              ]),
            ),
            SizedBox(
              height: infoHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Avatar(name: it.who.isEmpty ? it.kindLabel : it.who, url: it.logoUrl, size: 20),
                    const SizedBox(width: 6),
                    Expanded(child: Text(it.who.isEmpty ? it.kindLabel : it.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Joy.textMuted))),
                  ]),
                  const SizedBox(height: 5),
                  Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.3, color: Joy.text))),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
                    if (!_isMoment)
                      Container(
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                        child: Text(it.act, key: Key('tl-act-${it.kind}-${it.id}'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                      ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// وسيط البطاقة بحسب النوع: فيديو يدور صامتاً، صورة تتقرّب ببطء، وإلا لوحة تدرّج لوني برمز النوع ونص.
class _Media extends StatelessWidget {
  final RowItem item;
  final _PreviewRegistry videos;
  final bool noMotion;
  const _Media({required this.item, required this.videos, required this.noMotion});

  @override
  Widget build(BuildContext context) {
    final it = item;
    final postKind = it.payload['kind']?.toString() ?? '';
    final url = it.imageUrl ?? (it.kind == 'circle' ? it.logoUrl : null);
    if (it.kind == 'moment' && postKind == 'video' && url != null) {
      return _VideoPreview(media: url, videos: videos, noMotion: noMotion);
    }
    if (url != null && postKind != 'audio') {
      return _KenBurns(
        seed: it.id,
        enabled: !noMotion,
        // صورة تعذّر تحميلها: اللوحة المطبعية بلا حركتها الخاصة (الحركة من الغلاف الخارجي)
        child: Image.network(thumbUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _Typographic(item: it, noMotion: true)),
      );
    }
    return _Typographic(item: it, noMotion: noMotion);
  }
}

/// بطاقة مطبعية: تدرّج بلون النوع (أو لون خلفية اللحظة النصية) ونصها أو رمز النوع واسمه، يتقرّب ببطء كالصورة.
class _Typographic extends StatelessWidget {
  final RowItem item;
  final bool noMotion;
  const _Typographic({required this.item, required this.noMotion});

  @override
  Widget build(BuildContext context) {
    final it = item;
    final postKind = it.payload['kind']?.toString() ?? '';
    final isText = it.kind == 'moment' && postKind == 'text';
    final bgHex = it.payload['bg']?.toString();
    Color base = isText && bgHex != null && bgHex.isNotEmpty ? colorFromHex(bgHex, Joy.accent) : _baseColor(it.kind, postKind);
    if (isText && (bgHex == null || bgHex.isEmpty)) base = Joy.accent;
    final dark = base.computeLuminance() < .45;
    final fg = dark ? Colors.white : Joy.text;
    final end = Color.lerp(base, dark ? Colors.black : Colors.white, dark ? .35 : .18)!;
    final text = isText ? it.title : (it.who.isNotEmpty ? it.who : it.title);
    final icon = postKind == 'audio' ? Icons.mic_rounded : rowKindIcon(it.kind);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [base, end])),
      child: _KenBurns(
        seed: it.id,
        enabled: !noMotion,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 34, 14, 14),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (!isText) ...[Icon(icon, size: 34, color: fg.withValues(alpha: .9)), const SizedBox(height: 8)],
            // النص يأخذ ما بقي من ارتفاع اللوحة وأسطره بقدر ما يتسع: مع تكبير النص يُختصر بنقاط بدل أن يفيض
            Flexible(
              child: LayoutBuilder(builder: (context, c) {
                final style = TextStyle(fontFamily: AppTheme.displayFont, fontSize: isText ? 19 : 15, fontWeight: FontWeight.w800, height: 1.35, color: fg);
                final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
                final room = c.maxHeight.isFinite ? (c.maxHeight / line).floor() : 4;
                return Text(text, textAlign: TextAlign.center, maxLines: room.clamp(1, isText ? 4 : 2), overflow: TextOverflow.ellipsis, style: style);
              }),
            ),
          ]),
        ),
      ),
    );
  }

  static Color _baseColor(String kind, String postKind) => switch (kind) {
        'offer' => const Color(0xFFFFD66B),
        'event' => const Color(0xFF6A1B9A),
        'job' => const Color(0xFF1565C0),
        'listing' => const Color(0xFF00897B),
        'circle' => Joy.primary,
        _ => postKind == 'audio' ? const Color(0xFF0A6E78) : Joy.accent,
      };
}

/// معاينة فيديو تدور صامتة بلا شريط تحكم ما دامت فتحة متاحة (حد [TimelinePage.maxLoopingPreviews])، وإلا إطارها الثابت مع رمز التشغيل.
class _VideoPreview extends StatefulWidget {
  /// رابط الوسيط كما أرسله الخادم؛ المشغّل يأخذ المعاينة الخفيفة `videoPreviewUrl` (أو `mediaUrl` احتياطاً) والإطار الثابت `thumbUrl`
  final String media;
  final _PreviewRegistry videos;
  final bool noMotion;
  const _VideoPreview({required this.media, required this.videos, required this.noMotion});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

/// الفتحة تُحجز عند الإنشاء وتُحرَّر عند الخروج من الشجرة (deactivate) وتُستعاد عند العودة (activate)، والإطار الثابت يعيد المحاولة كلما
/// حُرّرت فتحة؛ فلا تتجمّد المعاينات إطارات ثابتة بعد تغيّر القائمة أو التمرير.
class _VideoPreviewState extends State<_VideoPreview> {
  bool _slot = false;
  /// المعاينة تدور على النسخة الخفيفة (/chat/vpreview: 360p، أول ست ثوانٍ، صامتة) لا المقطع الكامل؛ وإن تعذّرت (خادم بلا ffmpeg
  /// يعيد 404) تعود إلى المقطع الكامل بمتحكم ومشغّل جديدين
  VideoViewController? _player;
  bool _full = false;

  String get _src => (_full ? null : videoPreviewUrl(widget.media)) ?? mediaUrl(widget.media);

  VideoViewController _controller() => _player ??= VideoViewController()..addListener(_onPlayback);

  void _onPlayback() {
    final c = _player;
    if (c == null || !c.value.failed || _full || videoPreviewUrl(widget.media) == null) return;
    c.removeListener(_onPlayback);
    // التبليغ قد يأتي أثناء بناء المشغّل: التبديل بعده
    scheduleMicrotask(() {
      c.dispose();
      if (!mounted || !identical(_player, c)) return;
      setState(() {
        _full = true;
        _player = null;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    widget.videos.addListener(_retry);
    _take();
  }

  void _take() {
    if (!_slot && !widget.noMotion) _slot = widget.videos.acquire();
  }

  void _drop() {
    if (!_slot) return;
    _slot = false;
    widget.videos.release();
  }

  /// فتحة تحرّرت: الإطار الثابت يحاول أخذها
  void _retry() {
    if (!mounted || _slot || widget.noMotion) return;
    if (widget.videos.acquire()) setState(() => _slot = true);
  }

  @override
  void didUpdateWidget(_VideoPreview old) {
    super.didUpdateWidget(old);
    // تعطيل الحركة لا يحجز فتحة لمعاينة لن تدور
    widget.noMotion ? _drop() : _take();
  }

  @override
  void deactivate() {
    _drop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _take();
  }

  @override
  void dispose() {
    widget.videos.removeListener(_retry);
    _drop();
    _player?.removeListener(_onPlayback);
    _player?.dispose();
    super.dispose();
  }

  Widget _poster(String key) => Image.network(thumbUrl(widget.media), key: Key(key), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF14181C)));

  @override
  Widget build(BuildContext context) {
    if (_slot && !widget.noMotion) {
      return Stack(fit: StackFit.expand, children: [
        // الإطار الثابت تحت المشغّل: يظهر ريثما يجهز المقطع أو إن تعذّر أو منع المتصفح التشغيل التلقائي، بدل بطاقة فارغة
        _poster('tl-video-under'),
        // المعاينة لا تلتقط اللمس: لمسة البطاقة تفتح العارض. تبديل الرابط (العودة للمقطع الكامل) يعني مشغّلاً جديداً
        KeyedSubtree(
          key: ValueKey(_src),
          child: IgnorePointer(child: VideoView(key: const Key('tl-video-loop'), url: _src, poster: thumbUrl(widget.media), controller: _controller(), autoplay: true, loop: true, muted: true, controls: false, fit: BoxFit.cover)),
        ),
        const PositionedDirectional(bottom: 8, end: 8, child: Icon(Icons.volume_off_rounded, size: 16, color: Colors.white70)),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
      _poster('tl-video-poster'),
      const Center(child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white)),
    ]);
  }
}

/// تقرّب بطيء مع انحراف خفيف (1.0 → 1.08 خلال ~8 ثوانٍ ذهاباً وإياباً) يجعل الصورة الثابتة «تتنفس»؛ طور البداية من المعرّف حتى
/// لا تتحرك البطاقات كلها معاً. يحترم تعطيل الحركة في النظام.
class _KenBurns extends StatefulWidget {
  final String seed;
  final bool enabled;
  final Widget child;
  const _KenBurns({required this.seed, required this.enabled, required this.child});
  @override
  State<_KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<_KenBurns> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  late final _phase = (widget.seed.codeUnits.fold<int>(0, (a, c) => a + c) % 7) / 7;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _c.value = _phase;
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // الانحراف: مرساة التكبير تنتقل من ركن إلى المقابل فتبدو الصورة تنساب لا تنتفخ من مركزها
    final from = _phase < .5 ? const Alignment(-.4, -.3) : const Alignment(.4, -.2);
    final to = _phase < .5 ? const Alignment(.4, .3) : const Alignment(-.4, .3);
    return ClipRect(
      child: AnimatedBuilder(
        key: const Key('tl-kenburns'),
        animation: _curve,
        child: widget.child,
        builder: (_, child) => Transform.scale(scale: 1 + .08 * _curve.value, alignment: Alignment.lerp(from, to, _curve.value), child: child),
      ),
    );
  }
}

/// دخول البطاقة الجديدة: تلاشٍ وانزلاق 16 نقطة خلال 220 مللي ثانية مرة واحدة (نمط فقاعة المحادثة).
class _EnterIn extends StatefulWidget {
  final bool enabled;
  final VoidCallback onDone;
  final Widget child;
  const _EnterIn({required this.enabled, required this.onDone, required this.child});
  @override
  State<_EnterIn> createState() => _EnterInState();
}

class _EnterInState extends State<_EnterIn> {
  late final bool _animate = widget.enabled;

  @override
  void initState() {
    super.initState();
    if (_animate) WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return TweenAnimationBuilder<double>(
      key: const Key('tl-enter'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child)),
    );
  }
}

/// الحالة الفارغة لكل نوع: اللحظات تدعو للمشاركة، وبقية الأنواع تدل على قسمها.
class _Empty extends StatelessWidget {
  final String kind;
  final VoidCallback onCompose;
  final ValueChanged<String> onGoTab;
  const _Empty({required this.kind, required this.onCompose, required this.onGoTab});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'offer':
        return EmptyState(icon: Icons.local_offer_outlined, title: 'لا عروض حولك الآن', subtitle: 'عروض الدوائر القريبة تظهر هنا فور نشرها', action: _btn('tl-go-offer', Icons.groups_rounded, 'تصفّح الدوائر', () => onGoTab('circles')));
      case 'event':
        return EmptyState(icon: Icons.event_outlined, title: 'لا فعاليات قريبة', subtitle: 'الفعاليات القادمة حولك تظهر هنا', action: _btn('tl-go-event', Icons.event_rounded, 'كل الفعاليات', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage()))));
      case 'job':
        return EmptyState(icon: Icons.work_outline_rounded, title: 'لا وظائف معلنة الآن', subtitle: 'فرص الدوائر القريبة تظهر هنا', action: _btn('tl-go-job', Icons.work_rounded, 'كل الوظائف', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobsPage()))));
      case 'listing':
        return EmptyState(icon: Icons.shopping_bag_outlined, title: 'السوق هادئ الآن', subtitle: 'إعلانات الجيران القريبة تظهر هنا', action: _btn('tl-go-listing', Icons.storefront_rounded, 'افتح السوق', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MarketPage()))));
      case 'circle':
        return EmptyState(icon: Icons.storefront_outlined, title: 'لا دوائر «هنا اليوم» حولك', subtitle: 'الدوائر المتنقلة التي تثبّت دبوسها اليوم تظهر هنا', action: _btn('tl-go-circle', Icons.groups_rounded, 'تصفّح الدوائر', () => onGoTab('circles')));
      default:
        return EmptyState(
          key: const Key('tl-empty'),
          icon: Icons.photo_camera_outlined,
          title: 'المدينة هادئة الآن',
          subtitle: 'كن أول من يشارك لحظة من مكانك. اللحظات تبقى يوماً واحداً ثم تختفي.',
          action: _btn('tl-compose', Icons.photo_camera_rounded, 'شارك لحظة الآن', onCompose),
        );
    }
  }

  static Widget _btn(String key, IconData icon, String label, VoidCallback onTap) => FilledButton.icon(
        key: Key(key),
        onPressed: onTap,
        style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
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
