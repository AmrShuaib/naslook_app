import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/session.dart';

enum AuthStatus { loading, signedOut, signedIn }

/// الحالة العامة للتطبيق: حالة المصادقة + الجلسة + آخر خطأ.
class AppState {
  final AuthStatus status;
  final Session? session;
  final String? error;
  final bool busy;

  const AppState({
    this.status = AuthStatus.loading,
    this.session,
    this.error,
    this.busy = false,
  });

  bool get isSignedIn => status == AuthStatus.signedIn && session != null;
  SessionUser? get user => session?.user;

  AppState copyWith({
    AuthStatus? status,
    Session? session,
    String? error,
    bool? busy,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AppState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final sessionStoreProvider = Provider<SessionStore>((_) => SessionStore());

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(
    ref.watch(apiClientProvider),
    ref.watch(sessionStoreProvider),
  )..bootstrap();
});

class AppStateNotifier extends StateNotifier<AppState> {
  final ApiClient _api;
  final SessionStore _store;

  AppStateNotifier(this._api, this._store) : super(const AppState());

  /// استعادة الجلسة المحفوظة عند بدء التطبيق والتحقق منها مع الخادم.
  Future<void> bootstrap() async {
    Session? saved;
    try {
      saved = await _store.load();
    } catch (_) {
      saved = null; // تخزين محلي معطّل أو تالف: نبدأ من شاشة الدخول بدل البقاء على شاشة التحميل
    }
    if (saved == null) {
      state = const AppState(status: AuthStatus.signedOut);
      return;
    }
    _api.token = saved.token;
    try {
      final user = await _api.me();
      final session = saved.copyWith(
        user: user.id.isEmpty ? saved.user : user,
      );
      await _store.save(session);
      state = AppState(status: AuthStatus.signedIn, session: session);
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.statusCode == 404) {
        // الجلسة انتهت أو المسار غير موجود: نمسحها ونطلب الدخول مجدداً.
        await _store.clear();
        _api.token = null;
        state = const AppState(status: AuthStatus.signedOut);
      } else {
        // خطأ شبكة مؤقت: نُبقي الجلسة المحفوظة ونعمل دون اتصال.
        state = AppState(status: AuthStatus.signedIn, session: saved);
      }
    } catch (_) {
      state = AppState(status: AuthStatus.signedIn, session: saved);
    }
  }

  Future<bool> login(String nickname, String pin) =>
      _authenticate(() => _api.login(nickname: nickname, pin: pin));

  Future<bool> register(String nickname, String pin) =>
      _authenticate(() => _api.register(nickname: nickname, pin: pin));

  Future<bool> _authenticate(Future<Session> Function() action) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final session = await action();
      // عبارة الاسترداد تُعرض مرة واحدة ولا تُخزَّن على الجهاز
      await _store.save(session.copyWith(clearRecovery: true));
      state = AppState(status: AuthStatus.signedIn, session: session);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        status: AuthStatus.signedOut,
        busy: false,
        error: e.message,
        clearSession: true,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.signedOut,
        busy: false,
        error: 'حدث خطأ غير متوقع',
        clearSession: true,
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(busy: true, clearError: true);
    await _api.logout();
    await _store.clear();
    state = const AppState(status: AuthStatus.signedOut);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// بعد أن يرى المستخدم عبارة الاسترداد نزيلها من الذاكرة.
  void dismissRecoveryPhrase() {
    final s = state.session;
    if (s?.recoveryPhrase != null) {
      state = state.copyWith(session: s!.copyWith(clearRecovery: true));
    }
  }
}
