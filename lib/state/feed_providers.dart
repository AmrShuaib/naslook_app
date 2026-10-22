import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/row_api.dart';
import 'app_state.dart';
import 'search_providers.dart';

/// حالة «اللحظات» لنوع واحد: العناصر المعروضة الأحدث أولاً، ما ينتظر خلف كبسولة «جديد» (وصل حيّاً أو بتحديث أثناء التصفح)،
/// ومؤشر الصفحة التالية (null = لا أقدم).
class MomentsState {
  final List<RowItem> items;
  final List<RowItem> pending;
  final String? next;
  /// جلب الصفحة الأولى جارٍ والقائمة فارغة (هيكل التحميل)
  final bool loading;
  final bool loadingMore;
  /// نجح جلب واحد على الأقل (حتى لو عادت القائمة فارغة)
  final bool loaded;
  /// رُتّبت الصفحة بموقع المستخدم (ضمن النطاق) لا بالأحدث فقط
  final bool located;
  final Object? error;
  const MomentsState({this.items = const [], this.pending = const [], this.next, this.loading = false, this.loadingMore = false, this.loaded = false, this.located = false, this.error});

  MomentsState copyWith({List<RowItem>? items, List<RowItem>? pending, String? next, bool clearNext = false, bool? loading, bool? loadingMore, bool? loaded, bool? located, Object? error, bool clearError = false}) => MomentsState(
        items: items ?? this.items,
        pending: pending ?? this.pending,
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
  /// جيل الطلبات: ردّ أقدم من آخر تحديث يُهمل حتى لا يستبدل قائمة أحدث
  int _gen = 0;

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

  Future<void> load() async {
    final gen = ++_gen;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _fetch();
      if (gen != _gen || !mounted) return;
      state = MomentsState(items: page.items, next: page.next, loaded: true, located: page.located);
    } catch (e) {
      if (gen != _gen || !mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// يعيد جلب الصفحة الأولى. [applyNow] يستبدل القائمة فوراً (المستخدم في الأعلى)، وإلا يذهب الجديد منها إلى [MomentsState.pending]
  /// حتى لا تقفز القائمة تحت إصبعه، وتبقى الصفحات الأقدم التي صفحها كما هي.
  Future<void> refresh({bool applyNow = true}) async {
    if (!state.loaded && state.items.isEmpty) return load();
    final gen = ++_gen;
    try {
      final page = await _fetch();
      if (gen != _gen || !mounted) return;
      if (applyNow || state.items.isEmpty) {
        state = MomentsState(items: page.items, next: page.next, loaded: true, located: page.located);
      } else {
        final seen = {for (final it in state.items) it.pinKey, for (final it in state.pending) it.pinKey};
        final fresh = page.items.where((it) => !seen.contains(it.pinKey)).toList();
        state = state.copyWith(pending: [...fresh, ...state.pending], located: page.located, clearError: true);
      }
    } catch (e) {
      if (gen != _gen || !mounted) return;
      if (state.items.isEmpty) state = state.copyWith(loading: false, error: e);
    }
  }

  /// الصفحة التالية (الأقدم) بالمؤشر؛ لا شيء إن انتهت أو كان طلب جارياً.
  Future<void> loadMore() async {
    if (state.next == null || state.loadingMore || state.loading) return;
    final gen = _gen;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _fetch(before: state.next);
      if (gen != _gen || !mounted) return;
      final seen = {for (final it in state.items) it.pinKey};
      state = state.copyWith(items: [...state.items, ...page.items.where((it) => !seen.contains(it.pinKey))], next: page.next, clearNext: page.next == null, loadingMore: false);
    } catch (_) {
      if (gen == _gen && mounted) state = state.copyWith(loadingMore: false);
    }
  }

  /// لحظة وصلت حيّة: في الأعلى تُدرج فوراً، وإلا تنتظر خلف الكبسولة.
  void pushLive(RowItem it, {required bool applyNow}) {
    final pending = state.pending.where((x) => x.pinKey != it.pinKey).toList();
    if (applyNow) {
      state = state.copyWith(items: [it, ...state.items.where((x) => x.pinKey != it.pinKey)], pending: pending, loaded: true);
    } else {
      state = state.copyWith(pending: [it, ...pending]);
    }
  }

  /// يعتمد ما ينتظر خلف الكبسولة في أعلى القائمة.
  void applyPending() {
    if (state.pending.isEmpty) return;
    final ids = {for (final it in state.pending) it.pinKey};
    state = state.copyWith(items: [...state.pending, ...state.items.where((x) => !ids.contains(x.pinKey))], pending: const []);
  }

  /// لحظة حُذفت أو أُخفيت: تُزال من القائمة ومن المنتظر.
  void removeMoment(String id) {
    bool gone(RowItem x) => x.kind == 'moment' && x.id == id;
    if (!state.items.any(gone) && !state.pending.any(gone)) return;
    state = state.copyWith(items: state.items.where((x) => !gone(x)).toList(), pending: state.pending.where((x) => !gone(x)).toList());
  }
}

/// «اللحظات» لكل نوع (`all`، `moment`، …): يبقى بعد تبديل الرقاقة فتعود القائمة فوراً، والصفحة تحدّثه عند الفتح والعودة.
final momentsProvider = StateNotifierProvider.family<MomentsNotifier, MomentsState, String>((ref, kind) => MomentsNotifier(ref, kind));
