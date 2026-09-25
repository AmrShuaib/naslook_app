// بوابة تأكيد البريد قبل الدخول: التسجيل يعرض شاشة الرمز بلا جلسة، الرمز الصحيح يؤكد ثم يدخل تلقائياً بكلمة السر،
// الدخول بحساب غير مؤكد يعرض الشاشة نفسها، الجلسة المحفوظة لحساب غير مؤكد تقف عند الشاشة، وإعادة الإرسال بعد دقيقة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/screens/verify_email_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

/// بوابة مصغّرة بمنطق AuthGate نفسه لكن بلا HomeShell (التي تبدأ مؤقتات لا تخص هذا الاختبار): الدخول = نص ثابت.
class _Gate extends ConsumerWidget {
  const _Gate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (ref.watch(appStateProvider.select((s) => s.status))) {
      case AuthStatus.loading: return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut: return const LoginPage();
      case AuthStatus.pendingVerification: return const VerifyEmailPage();
      case AuthStatus.signedIn: return const Scaffold(body: Center(child: Text('signed-in', key: Key('signed-in'))));
    }
  }
}

/// خادم وهمي: حساب newuser غير مؤكد حتى يُرسل الرمز 654321، وحساب amr مؤكد.
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool verified = false;
  bool gateOn = true;
  int resendCount = 0;
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    Map<String, dynamic> b = const {};
    if (req.body.isNotEmpty) { try { b = jsonDecode(req.body) as Map<String, dynamic>; bodies[key] = b; } catch (_) {} }
    switch (key) {
      case 'POST /auth/register':
        return _json({'id': 'SA0000009', 'nickname': b['nickname'], 'pending': true, 'recoveryPhrase': 'كلمات ست للاسترداد', 'email': b['email'], 'verified': false, 'codeSent': true, 'recoverySent': true}, 202);
      case 'POST /auth/login':
        if (b['password'] != 'Password1') return _json({'error': 'bad-credentials'}, 401);
        if (b['handle'] == 'amr') return _json({'id': 'SA0000001', 'nickname': 'amr', 'token': 'tok-amr'});
        if (!verified && gateOn) return _json({'error': 'email-unverified', 'email': 'new@example.com', 'codeSent': false, 'retryIn': 40}, 403);
        return _json({'id': 'SA0000009', 'nickname': 'newuser', 'token': 'tok9'});
      case 'POST /auth/change-email':
        if (b['password'] != 'Password1') return _json({'error': 'bad-credentials'}, 401);
        return _json({'pending': true, 'email': b['email'], 'codeSent': true}, 202);
      case 'POST /auth/verify':
        if (b['code'] != '654321') return _json({'error': 'bad-code', 'attemptsLeft': 4}, 400);
        verified = true;
        return _json({'ok': true, 'verified': true});
      case 'POST /auth/resend':
        resendCount++;
        return _json({'ok': true, 'expiresIn': 900});
      case 'GET /me':
        return _json({'id': 'SA0000009', 'nickname': 'newuser'});
      case 'GET /me/login-email':
        return _json({'email': 'new@example.com', 'verified': verified, 'mailConfigured': true, 'required': gateOn});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false});
      case 'POST /logout':
        return _json({'ok': true});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {AppStateNotifier Function(ApiClient api)? notifier}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => notifier != null ? notifier(api) : (AppStateNotifier(api, SessionStore())..bootstrap())),
      notifyPollIntervalProvider.overrideWithValue(null),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: _Gate()),
  ));
  await _settle(tester);
  return srv;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _register(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('auth-toggle')));
  await _settle(tester);
  await tester.enterText(find.byKey(const Key('reg-email')), 'new@example.com');
  await tester.enterText(find.byKey(const Key('reg-nickname')), 'newuser');
  await tester.enterText(find.byKey(const Key('reg-password')), 'Password1');
  await tester.ensureVisible(find.byKey(const Key('reg-terms')));
  await tester.tap(find.byKey(const Key('reg-terms')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('auth-submit')));
  await _settle(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    iosNativeOverride = false;
  });
  tearDown(() => iosNativeOverride = null);

  testWidgets('register shows the verification screen with no session; the right code verifies then signs in automatically', (tester) async {
    final srv = await _pump(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    await _register(tester);
    expect(find.byType(VerifyEmailPage), findsOneWidget, reason: 'لا دخول قبل الرمز');
    expect(find.textContaining('new@example.com'), findsOneWidget);
    expect(srv.calls, isNot(contains('POST /auth/login')));
    // أُرسل رمز للتو: إعادة الإرسال معطلة مع عدّاد
    expect(tester.widget<TextButton>(find.byKey(const Key('verify-resend'))).onPressed, isNull);
    expect(find.textContaining('إعادة الإرسال بعد'), findsOneWidget);
    // رمز خاطئ
    await tester.enterText(find.byKey(const Key('verify-code')), '000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-submit')));
    await _settle(tester);
    expect(find.text('الرمز غير صحيح'), findsOneWidget);
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    // الرمز الصحيح: /auth/verify ثم /auth/login بالبيانات نفسها ثم الواجهة
    await tester.enterText(find.byKey(const Key('verify-code')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-submit')));
    await _settle(tester, 8);
    expect(srv.bodies['POST /auth/verify'], {'email': 'new@example.com', 'code': '654321'});
    expect(srv.bodies['POST /auth/login'], {'handle': 'newuser', 'password': 'Password1'});
    expect(find.byType(VerifyEmailPage), findsNothing);
    final st = ProviderScope.containerOf(tester.element(find.byType(_Gate))).read(appStateProvider);
    expect(st.status, AuthStatus.signedIn);
    expect(st.session?.token, 'tok9');
    expect(st.session?.recoveryPhrase, isNull, reason: 'العبارة لا تُسلَّم قبل التأكيد (هي بيانات دخول لدى النواة)؛ وصلت بالبريد');
    expect(st.session?.recoverySent, isTrue, reason: 'رسالة الترحيب بعد الدخول الأول');
    expect(find.byKey(const Key('signed-in')), findsOneWidget);
  });

  testWidgets('login with an unverified account shows the verification screen; back returns to login', (tester) async {
    final srv = await _pump(tester);
    await tester.enterText(find.byKey(const Key('login-handle')), 'newuser');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password1');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await _settle(tester);
    expect(srv.calls, contains('POST /auth/login'));
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    // الخادم لم يرسل رمزاً (أُرسل قبل أقل من دقيقة) وأخبرنا بالثواني المتبقية: العدّاد يبدأ منها ولا يُدعى المستخدم لطلب سيُرفض
    expect(find.byKey(const Key('verify-not-sent')), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('verify-resend'))).onPressed, isNull);
    expect(find.text('إعادة الإرسال بعد 40 ث'), findsOneWidget);
    for (var i = 0; i < 41; i++) { await tester.pump(const Duration(seconds: 1)); }
    expect(tester.widget<TextButton>(find.byKey(const Key('verify-resend'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('verify-resend')));
    await _settle(tester);
    expect(srv.bodies['POST /auth/resend'], {'email': 'new@example.com'});
    expect(find.textContaining('إعادة الإرسال بعد'), findsOneWidget, reason: 'يبدأ العدّاد بعد الإرسال');
    // بعد دقيقة يعود الزر
    for (var i = 0; i < 61; i++) { await tester.pump(const Duration(seconds: 1)); }
    expect(tester.widget<TextButton>(find.byKey(const Key('verify-resend'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('verify-back')));
    await _settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(srv.calls.where((c) => c == 'POST /logout'), isEmpty, reason: 'لا جلسة فلا خروج');
  });

  testWidgets('a cancelled registration leaves nothing behind for the next account on the same device', (tester) async {
    final srv = await _pump(tester);
    await _register(tester);
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify-back')));
    await _settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-handle')), 'amr');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password1');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await _settle(tester, 6);
    expect(srv.bodies['POST /auth/login']?['handle'], 'amr');
    final st = ProviderScope.containerOf(tester.element(find.byType(_Gate))).read(appStateProvider);
    expect(st.status, AuthStatus.signedIn);
    expect(st.session?.user.id, 'SA0000001');
    expect(st.session?.recoverySent, isFalse, reason: 'ترحيب التسجيل الملغى لا يظهر لحساب آخر');
    expect(st.session?.recoveryPhrase, isNull);
  });

  testWidgets('a wrong email can be replaced from the verification screen with the password kept in memory', (tester) async {
    final srv = await _pump(tester);
    await _register(tester);
    await tester.tap(find.byKey(const Key('verify-change-email')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('verify-new-email')), 'Fixed@Example.com');
    await tester.tap(find.byKey(const Key('verify-new-email-ok')));
    await _settle(tester, 6);
    expect(srv.bodies['POST /auth/change-email'], {'handle': 'newuser', 'password': 'Password1', 'email': 'fixed@example.com'});
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    expect(find.textContaining('fixed@example.com'), findsOneWidget, reason: 'الشاشة تعرض البريد الجديد');
    expect(find.textContaining('new@example.com'), findsNothing);
  });

  testWidgets('a saved session of an unverified account stops at the verification screen and continues with the same session', (tester) async {
    await SessionStore().save(const Session(token: 'tok-old', user: SessionUser(id: 'SA0000009', nickname: 'newuser')));
    final srv = await _pump(tester);
    await _settle(tester, 6);
    expect(find.byType(VerifyEmailPage), findsOneWidget, reason: 'الحساب القائم غير المؤكد يُطلب منه الرمز عند فتح التطبيق');
    expect(srv.calls, contains('GET /me/login-email'));
    await tester.enterText(find.byKey(const Key('verify-code')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-submit')));
    await _settle(tester, 8);
    expect(find.byType(VerifyEmailPage), findsNothing);
    expect(srv.calls, isNot(contains('POST /auth/login')), reason: 'الجلسة القائمة تكفي بعد التأكيد');
    final st = ProviderScope.containerOf(tester.element(find.byType(_Gate))).read(appStateProvider);
    expect(st.status, AuthStatus.signedIn);
    expect(st.session?.token, 'tok-old');
  });

  testWidgets('a saved session with the gate off on the server signs in directly', (tester) async {
    await SessionStore().save(const Session(token: 'tok-old', user: SessionUser(id: 'SA0000009', nickname: 'newuser')));
    final srv = await _pump(tester, notifier: (api) => AppStateNotifier(api, SessionStore())..bootstrap());
    // الخادم يقول required=false (المدير أطفأ البوابة أو البريد غير مضبوط)
    srv.gateOn = false;
    await _settle(tester, 6);
    // الفحص جرى قبل تغيير المفتاح في هذا الاختبار، فنعيد التشغيل بحالة الخادم الجديدة
    final container = ProviderScope.containerOf(tester.element(find.byType(_Gate)));
    await container.read(appStateProvider.notifier).bootstrap();
    await _settle(tester, 6);
    expect(container.read(appStateProvider).status, AuthStatus.signedIn);
    expect(find.byType(VerifyEmailPage), findsNothing);
  });

  testWidgets('back from the verification screen with a live session logs out', (tester) async {
    await SessionStore().save(const Session(token: 'tok-old', user: SessionUser(id: 'SA0000009', nickname: 'newuser')));
    final srv = await _pump(tester);
    await _settle(tester, 6);
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify-back')));
    await _settle(tester, 6);
    expect(srv.calls, contains('POST /logout'));
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('admin settings expose the require-verification switch and save it', (tester) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? saved;
    Future<http.Response> handle(http.Request req) async {
      final key = '${req.method} ${req.url.path}';
      if (key == 'GET /adminapi/settings') return _json({'testTopup': false, 'maxTopup': 100000, 'announcement': '', 'maintenance': false, 'supportHandle': '', 'supportEmail': '', 'bannedWords': '', 'reportThreshold': 3, 'requireEmailVerification': true});
      if (key == 'POST /adminapi/settings') { saved = jsonDecode(req.body) as Map<String, dynamic>; return _json({...saved!, 'maxTopup': 100000}); }
      if (key == 'GET /adminapi/payments/config') return _json({'enabled': false, 'provider': 'moyasar'});
      if (req.method == 'GET') return _json([]);
      return _json({'ok': true});
    }
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: AdminSettingsPage())),
    ));
    await _settle(tester);
    final sw = find.byKey(const Key('set-require-verify'));
    expect(sw, findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('set-save')));
    await tester.tap(find.byKey(const Key('set-save')));
    await _settle(tester);
    expect(saved?['requireEmailVerification'], isFalse);
  });
}
