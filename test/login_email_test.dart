// الدخول بالبريد الإلكتروني: شاشة الدخول تقبل بريداً وترسله إلى /auth/login، والتسجيل يرفضه، وبند «بريد الدخول» في ماي سبيس
// يعرض البريد الحالي وحالة تأكيده، يحفظ بريداً جديداً ويفتح مربع الرمز عند إرساله، ويؤكد البريد بالرمز الصحيح.
// تغيير البريد المؤكد أو إزالته يتطلب كلمة السر الحالية (أخطاء واضحة داخل المربع) ويُعتمد رمز الجلسة الجديد.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA9954961', nickname: 'jeddahh')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  String? email = 'jeddahh@gmail.com';
  var verified = true, mailConfigured = false, codePending = false, gate = false;
  Map<String, dynamic> info({bool codeSent = false}) => {'email': email, 'verified': verified, 'mailConfigured': mailConfigured, 'codePending': codePending, 'codeSent': codeSent, 'required': gate};
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    if (key == 'POST /auth/login') {
      if (lastBody!['handle'] == 'jeddahh@gmail.com' && lastBody!['password'] == 'Morio@1982') return _json({'id': 'SA9954961', 'nickname': 'jeddahh', 'token': 'tok'});
      return _json({'error': 'bad-credentials'}, 401);
    }
    if (key == 'GET /me') return _json({'id': 'SA9954961', 'nickname': 'jeddahh'});
    if (key == 'GET /me/login-email') return _json(info());
    if (key == 'PUT /me/login-email') {
      // كخادم auth_alias.js: البريد المؤكد لا يتغير بلا كلمة السر الحالية
      // والاستثناء: بريد غير مؤكد والبوابة مفعّلة يُستبدل بلا كلمة سر (شاشة التأكيد بجلسة محفوظة)
      final needsProof = !(email != null && !verified && gate);
      if (needsProof && lastBody!['password'] == null) return _json({'error': 'password-required'}, 403);
      if (lastBody!['password'] == 'rate-limited') return _json({'error': 'too-many-attempts'}, 429);
      if (verified && lastBody!['password'] != 'Morio@1982') return _json({'error': 'bad-password'}, 403);
      email = (lastBody!['email'] as String).toLowerCase(); verified = false; codePending = mailConfigured;
      return _json({...info(codeSent: mailConfigured), if (lastBody!['password'] != null) 'token': 'tok-fresh'});
    }
    if (key == 'DELETE /me/login-email') {
      if (verified && lastBody?['password'] != 'Morio@1982') return _json({'error': lastBody?['password'] == null ? 'password-required' : 'bad-password'}, 403);
      email = null; verified = false;
      return _json({'ok': true, 'token': 'tok-after-remove'});
    }
    if (key == 'POST /me/login-email/send-code') { codePending = true; return _json({'ok': true, 'expiresIn': 900}); }
    if (key == 'POST /me/login-email/verify') { if (lastBody!['code'] == '123456') { verified = true; codePending = false; return _json({'ok': true, ...info()}); } return _json({'error': 'bad-code', 'attemptsLeft': 4}, 400); }
    if (key == 'GET /me/profile') return _json({'id': 'SA9954961', 'nickname': 'jeddahh', 'isPublic': true});
    if (key == 'GET /me/map-presence') return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  testWidgets('login page accepts an email and posts it to /auth/login', (tester) async {
    calls.clear();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    final store = SessionStore();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => AppStateNotifier(api, store)), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: LoginPage()),
    ));
    await tester.pump();
    expect(find.text('البريد أو اسم المستخدم'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Jeddahh@gmail.com');
    await tester.enterText(fields.at(1), 'Morio@1982');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('POST /auth/login'));
    expect(lastBody!['handle'], 'jeddahh@gmail.com', reason: 'يُرسل البريد بحروف صغيرة');
  });

  Future<void> pumpMySpace(WidgetTester tester) async {
    calls.clear();
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: MySpacePage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.byKey(const Key('login-email')), 400, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('unverified email with mail enabled: verify button, code dialog, verified badge', (tester) async {
    email = 'jeddahh@gmail.com'; verified = false; mailConfigured = true; codePending = false;
    await pumpMySpace(tester);
    expect(find.byKey(const Key('login-email-unverified')), findsOneWidget);
    expect(find.byKey(const Key('login-email-verify')), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-email-verify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('POST /me/login-email/send-code'));
    expect(find.byKey(const Key('login-email-code')), findsOneWidget, reason: 'مربع الرمز يُفتح بعد الإرسال');
    await tester.enterText(find.byKey(const Key('login-email-code')), '999999');
    await tester.tap(find.byKey(const Key('login-email-code-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('الرمز غير صحيح'), findsOneWidget);
    expect(find.byKey(const Key('login-email-code')), findsOneWidget, reason: 'يعاد فتح المربع بعد رمز خاطئ');
    await tester.enterText(find.byKey(const Key('login-email-code')), '123456');
    await tester.tap(find.byKey(const Key('login-email-code-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastBody!['code'], '123456');
    expect(find.byKey(const Key('login-email-verified')), findsOneWidget);
    expect(find.byKey(const Key('login-email-verify')), findsNothing);
  });

  testWidgets('MySpace shows the login email and saves a new one with the current password', (tester) async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    email = 'jeddahh@gmail.com'; verified = true; mailConfigured = false;
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: MySpacePage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.byKey(const Key('login-email')), 400, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('jeddahh@gmail.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email-field')), 'Founder@Naslife.app');
    // بلا كلمة سر: لا طلب، ورسالة تحت الحقل
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('PUT /me/login-email')));
    expect(find.text('أدخل كلمة السر الحالية لتأكيد أنك صاحب الحساب'), findsOneWidget);
    // كلمة سر خاطئة: رد الخادم يظهر داخل المربع ويبقى ما كُتب
    await tester.enterText(find.byKey(const Key('login-email-password')), 'wrong');
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(calls, contains('PUT /me/login-email'));
    expect(lastBody!['password'], 'wrong');
    expect(find.text('كلمة السر غير صحيحة'), findsOneWidget);
    expect(find.byKey(const Key('login-email-field')), findsOneWidget, reason: 'المربع يبقى مفتوحاً بعد الخطأ');
    // كلمة السر الصحيحة: يُحفظ البريد ويُعتمد رمز الجلسة الجديد
    await tester.enterText(find.byKey(const Key('login-email-password')), 'Morio@1982');
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(lastBody!['password'], 'Morio@1982');
    expect(find.byKey(const Key('login-email-field')), findsNothing);
    expect(find.text('founder@naslife.app'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(MySpacePage)));
    expect(container.read(appStateProvider).session?.token, 'tok-fresh');
    expect(api.token, 'tok-fresh');
  });

  testWidgets('removing a verified login email asks for the password', (tester) async {
    SharedPreferences.setMockInitialValues({});
    email = 'jeddahh@gmail.com'; verified = true; mailConfigured = true; codePending = false;
    await pumpMySpace(tester);
    await tester.tap(find.byKey(const Key('login-email')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-email-notice-hint')), findsOneWidget, reason: 'يُخبر أن البريد الحالي سيصله تنبيه');
    await tester.tap(find.byKey(const Key('login-email-clear')));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('DELETE /me/login-email')));
    expect(find.text('أدخل كلمة السر الحالية لتأكيد أنك صاحب الحساب'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-email-password')), 'Morio@1982');
    await tester.tap(find.byKey(const Key('login-email-clear')));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /me/login-email'));
    expect(lastBody!['password'], 'Morio@1982');
    expect(find.text('أضف بريداً لتدخل به بدل النك نيم'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(MySpacePage)));
    expect(container.read(appStateProvider).session?.token, 'tok-after-remove');
  });

  testWidgets('an unverified email behind the gate is replaced without the password (verification screen case)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    email = 'typo@example.con'; verified = false; mailConfigured = true; codePending = false; gate = true;
    addTearDown(() => gate = false);
    await pumpMySpace(tester);
    await tester.tap(find.byKey(const Key('login-email')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-email-notice-hint')), findsNothing, reason: 'لا تنبيه لبريد لم تثبت ملكيته');
    expect(find.byKey(const Key('login-email-password')), findsNothing, reason: 'لا حقل كلمة سر حين لا يُطلب');
    await tester.enterText(find.byKey(const Key('login-email-field')), 'fixed@example.com');
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(calls, contains('PUT /me/login-email'));
    expect(lastBody!.containsKey('password'), isFalse, reason: 'لا يُطلب حقل كلمة السر هنا');
    expect(find.text('أدخل كلمة السر الحالية لتأكيد أنك صاحب الحساب'), findsNothing);
    expect(find.byKey(const Key('login-email-code')), findsOneWidget, reason: 'وصل الرمز إلى البريد الجديد فيُفتح مربعه');
    final container = ProviderScope.containerOf(tester.element(find.byType(MySpacePage)));
    expect(container.read(appStateProvider).session?.token, 't', reason: 'لا جلسة جديدة بلا كلمة سر');
  });

  testWidgets('too many password attempts show a clear wait message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    email = 'jeddahh@gmail.com'; verified = true; mailConfigured = false;
    await pumpMySpace(tester);
    await tester.tap(find.byKey(const Key('login-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email-field')), 'other@example.com');
    await tester.enterText(find.byKey(const Key('login-email-password')), 'rate-limited');
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(find.text('محاولات كثيرة؛ انتظر ربع ساعة ثم حاول مجدداً'), findsOneWidget);
  });
}
