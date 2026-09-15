// الدخول بالبريد الإلكتروني: شاشة الدخول تقبل بريداً وترسله إلى /auth/login، والتسجيل يرفضه، وبند «بريد الدخول» في ماي سبيس
// يعرض البريد الحالي ويحفظ بريداً جديداً.
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
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA9954961', nickname: 'jeddahh')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  String? email = 'jeddahh@gmail.com';
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    if (key == 'POST /auth/login') {
      if (lastBody!['handle'] == 'jeddahh@gmail.com' && lastBody!['password'] == 'Morio@1982') return _json({'id': 'SA9954961', 'nickname': 'jeddahh', 'token': 'tok'});
      return _json({'error': 'bad-credentials'}, 401);
    }
    if (key == 'GET /me') return _json({'id': 'SA9954961', 'nickname': 'jeddahh'});
    if (key == 'GET /me/login-email') return _json({'email': email});
    if (key == 'PUT /me/login-email') { email = (lastBody!['email'] as String).toLowerCase(); return _json({'email': email}); }
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
    expect(find.text('النك نيم أو البريد'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Jeddahh@gmail.com');
    await tester.enterText(fields.at(1), 'Morio@1982');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('POST /auth/login'));
    expect(lastBody!['handle'], 'jeddahh@gmail.com', reason: 'يُرسل البريد بحروف صغيرة');
  });

  testWidgets('MySpace shows the login email and saves a new one', (tester) async {
    calls.clear();
    email = 'jeddahh@gmail.com';
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
    await tester.tap(find.byKey(const Key('login-email-save')));
    await tester.pumpAndSettle();
    expect(calls, contains('PUT /me/login-email'));
    expect(find.text('founder@naslife.app'), findsOneWidget);
  });
}
