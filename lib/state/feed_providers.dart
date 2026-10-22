import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/row_api.dart';
import 'app_state.dart';
import 'search_providers.dart';

/// حالة «اللحظات» لنوع واحد: العناصر المعروضة الأحدث أولاً، ما ينتظر خلف كبسولة «جديد» (وصل حيّاً أو بتحديث أثناء التصفح)،
/// ومؤشر الصفحة التالية (null = لا أقدم).
class MomentsState {
  final List<RowItem> items;
  final List<RowItem> pending;
  /// ما ينتظر صفحةٌ أولى كاملة لا تلتقي بالقائمة (بينهما عناصر لم تُجلب): اعتماده يستبدل القائمة ويأخذ [pendingNext] مؤشراً
  /// بدل الإلحاق فوقها، وإلا بقيت فجوة لا تُجلب أبداً
  final bool pendingReplaces;
  final String? pendingNext;
  /// مؤشر الخادم كما هو (نص معتم يُعاد في `before=` حرفياً ولا يُحلَّل)
  final String? next;
  /// جلب الصفحة الأولى جارٍ والقائمة فارغة (هيكل التحميل)
  final bool loading;
  final bool loadingMore;
  /// نجح جلب واحد على الأقل (حتى لو عادت القائمة فارغة)
  final bool loaded;
  /// رُتّبت الصفحة بموقع المستخدم (ضمن النطاق) لا بالأحدث فقط
  final bool located;
  final Object? error;
  const MomentsState({this.items = const [], this.pending = const [], this.pendingReplaces = false, this.pendingNext, this.next, this.loading = false, this.loadingMore = false, this.loaded = false, this.located = false, this.error});

  MomentsState copyWith({List<RowItem>? items, List<RowItem>? pending, bool? pendingReplaces, String? pendingNext, bool clearPendingNext = false, String? next, bool clearNext = false, bool? loading, bool? loadingMore, bool? loaded, bool? located, Object? error, bool clearError = false}) => MomentsState(
        items: items ?? this.items,
        pending: pending ?? this.pending,
        pendingReplaces: pendingReplaces ?? this.pendingReplaces,
        pendingNext: clearPendingNext ? null : (pendingNext ?? this.pendingNext),
        next: clearNext ? null : (next ?? this.next),
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        loaded: loaded ?? this.loaded,
        located: located ?? this.located,
        error: clearError ? null : (error ?? this.error),
      );

  bool get hasMore => next != null;
}

/// جلب «اللحظات» لنوع واحد مع التصفح بالمؤشر (`before`)، والتحديث، وإدراج ما يصل من القناة الحية.
/// الموقع من [userLocationProvider] كما في الصف؛ بلا موقع يعيد الخادم الأحدث بلا نطاق.
class MomentsNotifier extends StateNotifier<MomentsState> {
  MomentsNotifier(this._ref, this.kind) : super(const MomentsState()) {
    load();
  }
  final Ref _ref;
  final String kind;
  /// جيل طلبات الصفحة الأولى: ردّ أقدم من آخر تحديث يُهمل حتى لا يستبدل قائمة أحدث
  int _gen = 0;
  /// رمز التصفح: يتغيّر فقط حين تُستبدل القائمة كلها. صفحة طُلبت بمؤشر القائمة السابقة تُهمل (وإلا أُلحقت بقائمة لا تتصل بها
  /// فبقيت فجوة)، أما تحديث يضع الجديد خلف الكبسولة فلا يمسّ القائمة فلا يُسقط الصفحة الجارية ولا يعلّق التصفح
  int _list = 0;

  Future<FeedPage> _fetch({String? before}) async {
    double? lat, lng;
    try {
      final loc = await _ref.read(userLocationProvider.future);
      lat = loc?.latitude;
      lng = loc?.longitude;
    } catch (_) {
      // بلا موقع: الأحدث بلا نطاق
    }
    return _ref.read(apiClientProvider).feedItems(kind: kind, lat: lat, lng: lng, before: before);
  }

  /// يستبدل القائمة كلها بصفحة أولى (ومعها رمز التصفح فتُهمل أي صفحة أقدم جارية؛ الحالة الجديدة بلا loadingMore).
  void _replace(List<RowItem> items, String? next, bool located) {
    _list++;
    state = MomentsState(items: items, next: next, loaded: true, located: located);
  }

  Future<void> load() async {
    final gen = ++_gen;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _fetch();
      if (gen != _gen || !mounted) return;
      _replace(page.items, page.next, page.located);
    } catch (e) {
      if (gen != _gen || !mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// يعيد جلب الصفحة الأولى. [applyNow] يستبدل القائمة فوراً (المستخدم في الأعلى)، وإلا يذهب الجديد منها إلى [MomentsState.pending]
  /// حتى لا تقفز القائمة تحت إصبعه، وتبقى الصفحات الأقدم التي صفحها كما هي، ويُزال في مكانه ما اختفى من مدى الصفحة (حُذف أو أُخفي
  /// أو حُظر ناشره).
  Future<void> refresh({bool applyNow = true}) async {
    if (!state.loaded && state.items.isEmpty) return load();
    final gen = ++_gen;
    try {
      final page = await _fetch();
      if (gen != _gen || !mounted) return;
      if (applyNow || state.items.isEmpty) return _replace(page.items, page.next, page.located);
      final inPage = {for (final it in page.items) it.pinKey};
      final items = _withoutGone(state.items, page, inPage);
      if (items.isEmpty) return _replace(page.items, page.next, page.located);
      final keys = {for (final it in items) it.pinKey};
      final top = page.items.isEmpty ? null : page.items.first.feedTime;
      // ما وصل حيّاً بعد أن حسب الخادم ردّه (أحدث من أوله) يبقى منتظراً؛ وما سواه شمله الردّ أو زال
      final live = [for (final x in state.pending) if (!inPage.contains(x.pinKey) && !keys.contains(x.pinKey) && _newer(x, top)) x];
      // صفحة كاملة لا تلتقي بالقائمة: الجديد أكثر من صفحة فلا يُلحق فوقها بل يستبدلها عند الاعتماد
      final gap = page.next != null && page.items.isNotEmpty && !page.items.any((it) => keys.contains(it.pinKey));
      final fresh = gap ? page.items : [for (final it in page.items) if (!keys.contains(it.pinKey)) it];
      state = state.copyWith(items: items, pending: [...live, ...fresh], pendingReplaces: gap, pendingNext: gap ? page.next : null, clearPendingNext: !gap, located: page.located, clearError: true);
    } catch (e) {
      if (gen != _gen || !mounted) return;
      if (state.items.isEmpty) state = state.copyWith(loading: false, error: e);
    }
  }

  /// الصفحة التالية (الأقدم) بالمؤشر؛ لا شيء إن انتهت أو كان طلب جارياً.
  Future<void> loadMore() async {
    final cursor = state.next;
    if (cursor == null || state.loadingMore || state.loading) return;
    final token = _list;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _fetch(before: cursor);
      // القائمة استُبدلت أثناء الطلب: الصفحة تتبع مؤشراً قديماً فتُهمل، والقائمة الجديدة بدأت بلا loadingMore
      if (!mounted || token != _list) return;
      if (state.next != cursor) {
        state = state.copyWith(loadingMore: false);
        return;
      }
      final seen = {for (final it in state.items) it.pinKey};
      state = state.copyWith(items: [...state.items, ...page.items.where((it) => !seen.contains(it.pinKey))], next: page.next, clearNext: page.next == null, loadingMore: false);
    } catch (_) {
      // فقط لطلب القائمة الحالية: طلب أحدث لقائمة مستبدلة يملك loadingMore الآن
      if (mounted && token == _list) state = state.copyWith(loadingMore: false);
    }
  }

  /// لحظة وصلت حيّة: في الأعلى تُدرج فوراً، وإلا تنتظر خلف الكبسولة. المعروضة أو المنتظرة أصلاً لا تتكرر ولا تُحتسب جديدة.
  /// يعيد true إن أُدرجت أو صارت ظاهرة.
  bool pushLive(RowItem it, {required bool applyNow}) {
    bool same(RowItem x) => x.pinKey == it.pinKey;
    if (state.items.any(same)) return false;
    final waiting = state.pending.any(same);
    if (applyNow) {
      // ما كان ينتظر يُعتمد أولاً حتى لا تسبقه الحيّة إلى الأعلى (وقد يستبدل القائمة إن كان صفحة منفصلة)
      if (state.pending.isNotEmpty) applyPending();
      if (!state.items.any(same)) state = state.copyWith(items: [it, ...state.items], loaded: true);
      return true;
    }
    if (waiting) return false;
    state = state.copyWith(pending: [it, ...state.pending]);
    return true;
  }

  /// يعتمد ما ينتظر خلف الكبسولة في أعلى القائمة، أو يستبدلها به إن كان صفحة لا تتصل بها.
  void applyPending() {
    if (state.pending.isEmpty) return;
    if (state.pendingReplaces) return _replace(state.pending, state.pendingNext, state.located);
    final ids = {for (final it in state.pending) it.pinKey};
    state = state.copyWith(items: [...state.pending, ...state.items.where((x) => !ids.contains(x.pinKey))], pending: const []);
  }

  /// لحظة حُذفت أو أُخفيت: تُزال من القائمة ومن المنتظر.
  void removeMoment(String id) => _removeWhere((x) => x.kind == 'moment' && x.id == id);

  /// ناشر حُظر: لحظاته تُزال من القائمة ومن المنتظر (الصفحات الأقدم أيضاً، لا مدى الصفحة الأولى وحده).
  void removeByUser(String userId) {
    final uid = userId.toUpperCase();
    _removeWhere((x) => x.kind == 'moment' && (x.payload['user'] is Map ? (x.payload['user'] as Map)['id'] : null)?.toString().toUpperCase() == uid);
  }

  void _removeWhere(bool Function(RowItem) gone) {
    if (!state.items.any(gone) && !state.pending.any(gone)) return;
    state = state.copyWith(items: state.items.where((x) => !gone(x)).toList(), pending: state.pending.where((x) => !gone(x)).toList());
  }

  /// زمن [x] أحدث من [top] (أو لا يُعرف أحدهما فيُبقى).
  static bool _newer(RowItem x, DateTime? top) => top == null || x.feedTime == null || x.feedTime!.isAfter(top);

  /// يزيل ما زال من مدى الصفحة الأولى: عنصر معروض يقع زمنه بين آخرها وأولها ولم يرد فيها = حُذف أو أُخفي أو حُظر ناشره أو خرج
  /// من النطاق. الصفحة بلا مؤشر تحمل البث كله فمداها حتى الأقدم. ما بعد آخرها أو بلا زمن يبقى كما هو.
  static List<RowItem> _withoutGone(List<RowItem> items, FeedPage page, Set<String> inPage) {
    if (page.items.isEmpty) return items;
    final top = page.items.first.feedTime;
    final floor = page.next == null ? null : page.items.last.feedTime;
    if (top == null || (page.next != null && floor == null)) return items;
    bool gone(RowItem x) {
      final t = x.feedTime;
      return !inPage.contains(x.pinKey) && t != null && !t.isAfter(top) && (floor == null || t.isAfter(floor));
    }

    return items.any(gone) ? items.where((x) => !gone(x)).toList() : items;
  }
}

/// «اللحظات» لكل نوع (`all`، `moment`، …): يبقى بعد تبديل الرقاقة فتعود القائمة فوراً، والصفحة تحدّثه عند الفتح والعودة.
final momentsProvider = StateNotifierProvider.family<MomentsNotifier, MomentsState, String>((ref, kind) => MomentsNotifier(ref, kind));

/// قوائم «اللحظات» المفتوحة فعلاً (نوع لم يُفتح لا يُنشأ فيبدأ جلبه): لتطبيق الحذف والحظر والتحديث والحيّ عليها كلها لا المرئية وحدها.
List<MomentsNotifier> openMoments(WidgetRef ref) => [for (final k in feedKinds) if (ref.exists(momentsProvider(k))) ref.read(momentsProvider(k).notifier)];
