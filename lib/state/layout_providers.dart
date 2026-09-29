import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/layout_api.dart';
import '../core/home_layout.dart';
import 'app_state.dart';
import 'providers.dart';

/// تخصيص الرئيسية: يُقرأ من الجهاز فوراً ثم من الخادم (يتزامن بين الويب والآيفون)، وكل تعديل يُحفظ محلياً
/// ويُدفع إلى الخادم بعد مهلة قصيرة. الزائر يحتفظ بتخصيصه على جهازه فقط، ويُرفع عند أول دخول.
class HomeLayoutNotifier extends StateNotifier<HomeLayout> {
  final Ref ref;
  Timer? _push;
  bool _loadedRemote = false;
  static const prefKey = 'home_layout_v1';
  /// للاختبارات: تعطيل الحفظ المحلي.
  static bool persistLocal = true;

  HomeLayoutNotifier(this.ref) : super(HomeLayout.defaults) {
    _load();
    ref.listen<bool>(signedInProvider, (prev, now) {
      if (prev != now) refresh();
    });
  }

  Future<void> _load() async {
    if (persistLocal) {
      try {
        final s = (await SharedPreferences.getInstance()).getString(prefKey);
        if (s != null && !_loadedRemote) state = HomeLayout.fromJson(jsonDecode(s) as Map);
      } catch (_) {}
    }
    await refresh();
  }

  /// يقرأ الخادم: تخصيص الحساب يتقدّم على الجهاز، وإن لم يكن للحساب تخصيص يُرفع تخصيص الجهاز إن وُجد.
  Future<void> refresh() async {
    HomeLayoutRemote r;
    try {
      r = await ref.read(apiClientProvider).homeLayout();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _loadedRemote = true;
    final signedIn = ref.read(signedInProvider);
    if (r.layout != null) {
      // الأقسام التي لم تكن في ترتيب المستخدم المحفوظ هي أقسام جديدة أضافها التطبيق: تُوسم «جديد»
      final raw = {for (final e in (r.layout!['order'] as List? ?? const [])) e.toString()};
      final fresh = [for (final b in homeBlocks) if (!raw.contains(b.id)) b.id];
      state = HomeLayout.fromJson(r.layout!, pinned: r.pinned, defaultOrder: r.defaultOrder).copyWith(fresh: fresh);
    } else {
      final local = state.copyWith(pinned: r.pinned);
      state = local.isDefault ? HomeLayout.normalized(pinned: r.pinned, defaultOrder: r.defaultOrder, nav: r.defaultNav) : local;
      if (signedIn && !state.isDefault) _schedulePush();
    }
    _saveLocal();
  }

  /// يطبّق تعديلاً ويحفظه.
  void update(HomeLayout Function(HomeLayout) f) {
    state = f(state);
    _saveLocal();
    _schedulePush();
  }

  Future<void> resetAll() async {
    state = state.reset();
    _push?.cancel();
    _saveLocal();
    if (ref.read(signedInProvider)) {
      try {
        await ref.read(apiClientProvider).deleteHomeLayout();
      } catch (_) {}
    }
  }

  void _schedulePush() {
    if (!ref.read(signedInProvider)) return;
    _push?.cancel();
    _push = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ref.read(apiClientProvider).saveHomeLayout(state);
      } catch (_) {}
    });
  }

  Future<void> _saveLocal() async {
    if (!persistLocal) return;
    try {
      await (await SharedPreferences.getInstance()).setString(prefKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _push?.cancel();
    super.dispose();
  }
}

final homeLayoutProvider = StateNotifierProvider<HomeLayoutNotifier, HomeLayout>((ref) => HomeLayoutNotifier(ref));

/// أقسام شريط التنقّل الحالية (بين «الخريطة» و«ماي سبيس»).
final navTabsProvider = Provider<List<String>>((ref) => ref.watch(homeLayoutProvider.select((l) => l.nav)));
