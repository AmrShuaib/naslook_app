import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/naslife_api.dart';
import '../api/session.dart';

/// `pendingVerification`: بوابة التأكيد (قرار المالك): الحساب موجود وكلمة السر صحيحة لكن لا دخول قبل إدخال رمز البريد.
enum AuthStatus { loading, signedOut, pendingVerification, signedIn }

/// الحالة العامة للتطبيق: حالة المصادقة + الجلسة + آخر خطأ.
class AppState {
  final AuthStatus status;
  final Session? session;
  final String? error;
  final bool busy;
  /// البريد المنتظر تأكيده وهل أُرسل إليه رمز في هذه الخطوة (لعدّاد إعادة الإرسال).
  final String? pendingEmail;
  final bool pendingCodeSent;

  const AppState({
    this.status = AuthStatus.loading,
    this.session,
    this.error,
    this.busy = false,
    this.pendingEmail,
    this.pendingCodeSent = false,
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
      pendingEmail: pendingEmail,
      pendingCodeSent: pendingCodeSent,
    );
  }
}

/// عميل HTTP الوحيد للتطبيق (يحمل رمز الجلسة الحالي).
final rawApiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

/// العميل الذي تعتمد عليه مزوّدات البيانات كلها. يُعاد بناؤه كلما تغيّر صاحب الجلسة (دخول، تسجيل، خروج، أو تبديل من
/// تبويب آخر)، فتُبنى كل المزوّدات من جديد ولا تبقى بيانات حساب سابق (الملف، الأصدقاء، المحفظة…) ظاهرة تحت اسم الحساب الجديد.
final apiClientProvider = Provider<ApiClient>((ref) {
  ref.watch(appStateProvider.select((s) => s.session?.user.id));
  return ApiClient.view(ref.watch(rawApiClientProvider));
});

final sessionStoreProvider = Provider<SessionStore>((_) => SessionStore());

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(
    ref.watch(rawApiClientProvider),
    ref.watch(sessionStoreProvider),
  )..bootstrap();
});

class AppStateNotifier extends StateNotifier<AppState> {
  final ApiClient _api;
  final SessionStore _store;
  // بيانات الدخول أثناء انتظار الرمز (في الذاكرة فقط): بعد التأكيد يُعاد الدخول بها تلقائياً. وعبارة الاسترداد من رد
  // التسجيل تُعرض بعد الدخول كما كان قبل البوابة.
  String? _pendingHandle, _pendingPin, _pendingPhrase;
  bool _pendingRecoverySent = false;

  AppStateNotifier(this._api, this._store) : super(const AppState());

  /// حساب قائم لم يؤكد بريده (جلسة محفوظة أو دخول قبل تفعيل البوابة): يُطلب الرمز قبل المتابعة. أي خطأ في الفحص
  /// يُعامل كـ«لا بوابة» حتى لا يُقفل التطبيق بسبب عطل عابر.
  Future<String?> _gateEmail() async {
    try {
      final i = await _api.loginEmail();
      if (i.required && !i.verified && (i.email ?? '').isNotEmpty) return i.email;
    } catch (_) { /* لا بوابة */ }
    return null;
  }

  /// استعادة الجلسة المحفوظة عند بدء التطبيق والتحقق منها مع الخادم.
  Future<void> bootstrap() async {
    // على الويب: إن بدّل تبويب آخر الحساب أو خرج، يتبعه هذا التبويب فوراً بدل أن يظل على جلسة قديمة
    _store.watch(() => unawaited(syncFromStore()));
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
      final gate = await _gateEmail();
      state = gate != null
          ? AppState(status: AuthStatus.pendingVerification, session: session, pendingEmail: gate)
          : AppState(status: AuthStatus.signedIn, session: session);
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

  Future<bool> login(String nickname, String pin) {
    _pendingHandle = nickname; _pendingPin = pin;
    return _authenticate(() => _api.login(nickname: nickname, pin: pin));
  }

  Future<bool> register(String nickname, String pin, {String? email, bool acceptTerms = false}) {
    _pendingHandle = nickname; _pendingPin = pin;
    return _authenticate(() => _api.register(nickname: nickname, pin: pin, email: email, acceptTerms: acceptTerms));
  }

  /// تعيين كلمة سر جديدة بالرمز الذي وصل بالبريد ثم الدخول مباشرة (الرمز يؤكد البريد أيضاً فلا بوابة بعده).
  Future<bool> resetPassword({required String email, required String code, required String password}) =>
      _authenticate(() async => AuthOutcome.signedIn(await _api.resetPassword(email: email, code: code, password: password)));

  /// إدخال رمز التأكيد من شاشة البوابة: يؤكد البريد ثم يدخل بالبيانات المحفوظة في الذاكرة، أو يكمل بالجلسة القائمة.
  Future<bool> verifyPending(String code) async {
    final email = state.pendingEmail;
    if (email == null || state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.verifyEmailCode(email: email, code: code);
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(busy: false, error: 'حدث خطأ غير متوقع');
      return false;
    }
    final session = state.session;
    if (session != null) {
      _clearPending();
      state = AppState(status: AuthStatus.signedIn, session: session);
      return true;
    }
    final h = _pendingHandle, p = _pendingPin;
    state = state.copyWith(busy: false);
    if (h == null || p == null) {
      // لا بيانات دخول في الذاكرة (أُعيد فتح التطبيق): يدخل المستخدم بكلمة سره الآن والبريد مؤكد
      state = const AppState(status: AuthStatus.signedOut);
      return true;
    }
    return _authenticate(() => _api.login(nickname: h, pin: p));
  }

  /// إعادة إرسال الرمز للبريد المنتظر؛ يعيد نص الخطأ إن فشل.
  Future<String?> resendPending() async {
    final email = state.pendingEmail;
    if (email == null) return 'لا بريد بانتظار التأكيد';
    try {
      await _api.resendVerification(email);
      state = AppState(status: AuthStatus.pendingVerification, session: state.session, pendingEmail: email, pendingCodeSent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر إرسال الرمز الآن';
    }
  }

  /// الرجوع من شاشة التأكيد: خروج من الجلسة القائمة إن وُجدت، وإلا العودة إلى شاشة الدخول.
  Future<void> cancelPending() async {
    _clearPending();
    if (state.session != null) { await logout(); return; }
    state = const AppState(status: AuthStatus.signedOut);
  }

  void _clearPending() { _pendingHandle = null; _pendingPin = null; }

  Future<bool> _authenticate(Future<AuthOutcome> Function() action) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final out = await action();
      if (out.isPending) {
        // لا جلسة قبل تأكيد البريد: تُعرض شاشة الرمز وتبقى بيانات الدخول في الذاكرة للدخول التلقائي بعده
        if (out.recoveryPhrase != null) _pendingPhrase = out.recoveryPhrase;
        _pendingRecoverySent = _pendingRecoverySent || out.recoverySent;
        state = AppState(status: AuthStatus.pendingVerification, pendingEmail: out.pendingEmail, pendingCodeSent: out.codeSent);
        return true;
      }
      var session = out.session!;
      if (_pendingPhrase != null || _pendingRecoverySent) {
        session = Session(token: session.token, user: session.user, recoveryPhrase: session.recoveryPhrase ?? _pendingPhrase, recoverySent: session.recoverySent || _pendingRecoverySent, email: session.email);
        _pendingPhrase = null; _pendingRecoverySent = false;
      }
      _clearPending();
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

  /// يطابق الجلسة الحالية مع المحفوظة (كتبها تبويب آخر): خروج هناك = خروج هنا، ودخول بحساب آخر هناك = تبديل هنا.
  Future<void> syncFromStore() async {
    Session? saved;
    try {
      saved = await _store.load();
    } catch (_) {
      return;
    }
    final current = state.session;
    if (saved == null) {
      if (current != null) {
        _api.token = null;
        state = const AppState(status: AuthStatus.signedOut);
      }
      return;
    }
    if (current == null || saved.token != current.token || saved.user.id != current.user.id) {
      _api.token = saved.token;
      state = AppState(status: AuthStatus.signedIn, session: saved);
    }
  }

  Future<void> logout() async {
    _clearPending();
    state = state.copyWith(busy: true, clearError: true);
    await _api.logout();
    await _store.clear();
    state = const AppState(status: AuthStatus.signedOut);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// بعد أن يرى المستخدم عبارة الاسترداد نزيلها من الذاكرة.
  /// يحدّث بيانات المستخدم في الجلسة (مثل صورة الحساب) ويحفظها محلياً.
  Future<void> updateUser(SessionUser user) async {
    final s = state.session;
    if (s == null) return;
    final next = s.copyWith(user: user);
    state = state.copyWith(session: next);
    // الحفظ المحلي لا يوقف الواجهة: إن تعذّر تبقى الجلسة المحدّثة في الذاكرة
    unawaited(_store.save(next).catchError((_) {}));
  }

  /// تعتمد رمز جلسة جديداً أصدرته النواة (بعد تغيير كلمة السر مثلاً) وتحفظه محلياً.
  Future<void> adoptToken(String? token) async {
    final s = state.session;
    if (token == null || token.isEmpty || s == null) return;
    _api.token = token;
    final next = s.copyWith(token: token, clearRecovery: true);
    state = state.copyWith(session: next);
    unawaited(_store.save(next).catchError((_) {}));
  }

  void dismissRecoveryPhrase() {
    final s = state.session;
    if (s?.recoveryPhrase != null) {
      state = state.copyWith(session: s!.copyWith(clearRecovery: true));
    }
  }
}
