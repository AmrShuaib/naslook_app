// التسجيل بالبريد وكلمة السر: نموذج التسجيل يرسل البريد واسم المستخدم وكلمة السر إلى /auth/register،
// نسيت كلمة السر يطلب الرمز ثم يعيّن كلمة سر جديدة ويدخل، وماي سبيس يغيّر كلمة السر ويفعّل الاستعادة بالعبارة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('Session parses recoverySent and email from the register response', () {
    final s = Session.fromJson({'id': 'SA0000009', 'nickname': 'new', 'token': 't', 'recoveryPhrase': 'a b c', 'email': 'new@example.com', 'recoverySent': true});
    expect(s.recoverySent, isTrue);
    expect(s.email, 'new@example.com');
    expect(s.copyWith(clearRecovery: true).recoveryPhrase, isNull);
    expect(s.copyWith(clearRecovery: true).recoverySent, isTrue);
    expect(Session.fromJson({'token': 't', 'id': 'SA1', 'nickname': 'x'}).recoverySent, isFalse);
  });

  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  var mailConfigured = true, recoveryEnabled = false;
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'POST /auth/register':
        if (lastBody!['email'] == 'taken@example.com') return _json({'error': 'email-taken'}, 409);
        // بوابة التأكيد: 202 بلا جلسة حتى يُدخل الرمز (test/verify_email_test.dart يغطي ما بعدها)
        return _json({'id': 'SA0000009', 'nickname': lastBody!['nickname'], 'pending': true, 'recoveryPhrase': 'كلمات ست للاسترداد', 'email': lastBody!['email'], 'verified': false, 'codeSent': mailConfigured, 'recoverySent': mailConfigured}, 202);
      case 'POST /auth/forgot':
        return mailConfigured ? _json({'ok': true}) : _json({'error': 'mail-not-configured'}, 503);
      case 'POST /auth/reset':
        if (lastBody!['code'] != '654321') return _json({'error': 'bad-code', 'attemptsLeft': 4}, 400);
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'token': 'tok-reset', 'email': lastBody!['email'], 'verified': true});
      case 'POST /auth/change-password':
        if (lastBody!['current'] != 'secret123') return _json({'error': 'bad-password'}, 403);
        return _json({'ok': true, 'token': 'tok-new'});
      case 'GET /auth/nickname-available':
        final n = req.url.queryParameters['nickname'] ?? '';
        return _json({'available': !['amr', 'sara'].contains(n), 'reason': ['amr', 'sara'].contains(n) ? 'taken' : null});
      case 'GET /me/recovery':
        return _json({'enabled': recoveryEnabled, 'email': 'amr@example.com', 'verified': true, 'mailConfigured': mailConfigured});
      case 'PUT /me/recovery':
        if (lastBody!['phrase'] != 'كلمات ست للاسترداد') return _json({'error': 'bad-phrase'}, 400);
        recoveryEnabled = true;
        return _json({'enabled': true, 'token': 'tok-rec'});
      case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
      case 'GET /me/login-email': return _json({'email': 'amr@example.com', 'verified': true, 'mailConfigured': mailConfigured});
      case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
      case 'GET /me/map-presence': return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread': return _json({'unread': 0});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<ApiClient> pumpLogin(WidgetTester tester) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => AppStateNotifier(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: LoginPage()),
    ));
    await tester.pump();
    return api;
  }

  Future<void> settle(WidgetTester tester) async { await tester.pump(); await tester.pump(const Duration(milliseconds: 300)); }

  testWidgets('register form posts email, nickname and password to /auth/register and waits for the email code', (tester) async {
    final api = await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('auth-toggle')));
    await settle(tester);
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reg-email')), 'New@Example.com');
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'newuser');
    await tester.enterText(find.byKey(const Key('reg-password')), 'Password1');
    // بدون الموافقة على الشروط لا يُرسل التسجيل
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(calls, isNot(contains('POST /auth/register')));
    expect(find.text('يلزم الموافقة على شروط الاستخدام وسياسة الخصوصية'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('reg-terms')));
    await tester.tap(find.byKey(const Key('reg-terms')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(calls, contains('POST /auth/register'));
    expect(lastBody!['acceptTerms'], isTrue, reason: 'الموافقة تُسجَّل مع التسجيل');
    expect(lastBody!['email'], 'new@example.com');
    expect(lastBody!['nickname'], 'newuser');
    expect(lastBody!['password'], 'Password1');
    expect(api.token, isNull, reason: 'لا جلسة قبل تأكيد البريد');
    final st = tester.element(find.byType(LoginPage)).findAncestorWidgetOfExactType<ProviderScope>();
    expect(st, isNotNull);
    expect(find.text('حدث خطأ غير متوقع'), findsNothing, reason: 'الرد 202 ليس خطأ');
  });

  testWidgets('register validation blocks a bad email and a short password', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('auth-toggle')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('reg-email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'ok_name');
    await tester.enterText(find.byKey(const Key('reg-password')), 'short');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(find.text('صيغة البريد غير صحيحة'), findsOneWidget);
    expect(find.text('كلمة السر يجب أن تكون 8 خانات على الأقل'), findsOneWidget);
    expect(calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  testWidgets('nickname: 3 to 25 characters, live availability check blocks a taken name', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('auth-toggle')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'abcdefghijklmnopqrstuvwxyz1234');
    await tester.pump();
    expect(tester.widget<TextFormField>(find.byKey(const Key('reg-nickname'))).controller!.text.length, 25, reason: 'الحقل يقطع عند 25 حرفاً');
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'ab');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('reg-email')), 'x@example.com');
    await tester.enterText(find.byKey(const Key('reg-password')), 'Password1');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(find.text('اسم المستخدم يجب أن يكون 3 خانات على الأقل'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'sara');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, contains('GET /auth/nickname-available'));
    expect(find.byKey(const Key('nick-taken')), findsOneWidget);
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(find.text('هذا الاسم مستخدم، اختر غيره'), findsOneWidget);
    expect(calls, isNot(contains('POST /auth/register')));
    await tester.enterText(find.byKey(const Key('reg-nickname')), 'fresh_name');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('nick-available')), findsOneWidget);
    expect(find.text('متاح'), findsOneWidget);
  });

  testWidgets('forgot password: sends the code, rejects a wrong code, then resets and signs in', (tester) async {
    final api = await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('login-forgot')));
    await settle(tester);
    expect(find.text('استعادة كلمة السر'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('forgot-email')), 'amr@example.com');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(calls, contains('POST /auth/forgot'));
    expect(lastBody!['email'], 'amr@example.com');
    expect(find.byKey(const Key('reset-code')), findsOneWidget, reason: 'ينتقل إلى خطوة الرمز');
    await tester.enterText(find.byKey(const Key('reset-code')), '111111');
    await tester.enterText(find.byKey(const Key('reset-password')), 'NewPass123');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(find.text('الرمز غير صحيح'), findsOneWidget);
    expect(api.token, isNull);
    await tester.enterText(find.byKey(const Key('reset-code')), '654321');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(lastBody!['code'], '654321');
    expect(lastBody!['password'], 'NewPass123');
    expect(api.token, 'tok-reset', reason: 'يدخل مباشرة بعد إعادة التعيين');
  });

  testWidgets('forgot password reports when the mail service is off', (tester) async {
    mailConfigured = false;
    addTearDown(() => mailConfigured = true);
    await pumpLogin(tester);
    await tester.tap(find.byKey(const Key('login-forgot')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('forgot-email')), 'amr@example.com');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await settle(tester);
    expect(find.textContaining('خدمة البريد غير مفعّلة'), findsOneWidget);
    expect(find.byKey(const Key('reset-code')), findsNothing);
  });

  Future<void> pumpMySpace(WidgetTester tester) async {
    calls.clear();
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle))..token = 't';
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: MySpacePage())),
    ));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('recovery')), 400, scrollable: find.byType(Scrollable).first);
    await settle(tester);
  }

  testWidgets('MySpace: change password adopts the new token; wrong current password is reported', (tester) async {
    await pumpMySpace(tester);
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cp-current')), 'wrong');
    await tester.enterText(find.byKey(const Key('cp-new')), 'Another123');
    await tester.tap(find.byKey(const Key('cp-save')));
    await tester.pumpAndSettle();
    expect(find.text('كلمة السر الحالية غير صحيحة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cp-current')), 'secret123');
    await tester.enterText(find.byKey(const Key('cp-new')), 'Another123');
    await tester.tap(find.byKey(const Key('cp-save')));
    await tester.pumpAndSettle();
    expect(lastBody!['current'], 'secret123');
    expect(lastBody!['password'], 'Another123');
    expect(find.text('تم تغيير كلمة السر'), findsOneWidget);
  });

  testWidgets('MySpace: recovery tile enables email recovery with the phrase', (tester) async {
    recoveryEnabled = false;
    await pumpMySpace(tester);
    expect(find.byKey(const Key('recovery-enable')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery-enable')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recovery-phrase')), 'كلمات ست للاسترداد');
    await tester.enterText(find.byKey(const Key('recovery-password')), 'secret123');
    await tester.tap(find.byKey(const Key('recovery-save')));
    await tester.pumpAndSettle();
    expect(calls, contains('PUT /me/recovery'));
    expect(find.byKey(const Key('recovery-enable')), findsNothing);
    expect(find.textContaining('مفعّلة: يصلك رمز على amr@example.com'), findsOneWidget);
  });
}
