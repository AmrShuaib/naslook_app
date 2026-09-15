// قسم البريد في لوحة الإدارة: شارة الحالة، اختيار المزوّد، الإعداد السريع لـ Gmail، حفظ الإعدادات بالحقول الصحيحة،
// الإبقاء على القناع للسر المحفوظ، الرسالة التجريبية، وسجل الإرسال بعدّاداته.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_mail.dart';
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
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  var settings = <String, dynamic>{'provider': 'off', 'host': '', 'port': 587, 'secure': false, 'user': '', 'pass': '', 'apiKey': '', 'from': '', 'fromName': 'ناس لايف', 'replyTo': '', 'hasPass': false, 'hasApiKey': false, 'configured': false};
  final log = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    if (key == 'GET /adminapi/mail') return _json(settings);
    if (key == 'PUT /adminapi/mail') {
      final b = lastBody!;
      final pass = b['pass'] == '••••••••' ? (settings['hasPass'] == true ? 'kept' : '') : (b['pass'] ?? '');
      settings = {...settings, ...b, 'pass': pass.isEmpty ? '' : '••••••••', 'hasPass': pass.isNotEmpty, 'configured': b['provider'] != 'off' && (b['from'] as String).contains('@') && (b['provider'] == 'smtp' ? (b['host'] as String).isNotEmpty : (b['apiKey'] as String).isNotEmpty)};
      return _json(settings);
    }
    if (key == 'POST /adminapi/mail/test') {
      final to = lastBody!['to'] as String;
      if (to.endsWith('@bounce.test')) { log.insert(0, {'id': 'm${log.length + 1}', 'to': to, 'subject': 'تجربة', 'tag': 'test', 'status': 'failed', 'error': 'smtp: RCPT failed: 550', 'provider': 'smtp', 'at': '2026-09-15T08:00:00Z'}); return _json({'error': 'send-failed', 'detail': 'smtp: RCPT failed: 550'}, 502); }
      log.insert(0, {'id': 'm${log.length + 1}', 'to': to, 'subject': 'تجربة البريد · ناس لايف', 'tag': 'test', 'status': 'sent', 'error': null, 'provider': 'smtp', 'at': '2026-09-15T08:00:00Z'});
      return _json({'ok': true, 'id': 'x'});
    }
    if (key == 'GET /adminapi/mail/log') return _json({'log': log, 'sent30d': log.where((l) => l['status'] == 'sent').length, 'failed30d': log.where((l) => l['status'] == 'failed').length});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<void> pump(WidgetTester tester) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        socketProvider.overrideWithValue(null),
        appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
        notifyPollIntervalProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: AdminMailPage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
  }

  testWidgets('off by default: banner warns, SMTP fields hidden, test send disabled', (tester) async {
    await pump(tester);
    expect(find.text('خدمة البريد غير مفعّلة'), findsOneWidget);
    expect(find.byKey(const Key('mail-host')), findsNothing);
    expect(find.byKey(const Key('mail-apikey')), findsNothing);
    await scrollTo(tester, const Key('mail-test-send'));
    expect(tester.widget<FilledButton>(find.byKey(const Key('mail-test-send'))).onPressed, isNull);
  });

  testWidgets('Gmail preset fills SMTP fields and save sends the full settings', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('mail-provider-smtp')));
    await tester.pump();
    expect(find.byKey(const Key('mail-host')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mail-preset-gmail')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('mail-host'))).controller!.text, 'smtp.gmail.com');
    expect(tester.widget<TextField>(find.byKey(const Key('mail-port'))).controller!.text, '465');
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('mail-secure'))).value, isTrue);
    await tester.enterText(find.byKey(const Key('mail-user')), 'founder@gmail.com');
    await tester.enterText(find.byKey(const Key('mail-pass')), 'abcd efgh ijkl mnop');
    await scrollTo(tester, const Key('mail-from'));
    await tester.enterText(find.byKey(const Key('mail-from')), 'founder@gmail.com');
    await scrollTo(tester, const Key('mail-save'));
    await tester.tap(find.byKey(const Key('mail-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('PUT /adminapi/mail'));
    expect(lastBody!['provider'], 'smtp');
    expect(lastBody!['host'], 'smtp.gmail.com');
    expect(lastBody!['port'], 465);
    expect(lastBody!['secure'], isTrue);
    expect(lastBody!['pass'], 'abcd efgh ijkl mnop');
    expect(lastBody!['from'], 'founder@gmail.com');
    expect(find.text('خدمة البريد مفعّلة'), findsOneWidget, reason: 'الشارة تتحدث بعد الحفظ');
  });

  testWidgets('saved secret stays masked on resave; test send logs the result', (tester) async {
    await pump(tester);
    expect(find.text('خدمة البريد مفعّلة'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('mail-pass'))).controller!.text, '••••••••');
    await scrollTo(tester, const Key('mail-save'));
    await tester.tap(find.byKey(const Key('mail-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(lastBody!['pass'], '••••••••', reason: 'القناع يُعاد كما هو فيبقى السر المحفوظ');
    await scrollTo(tester, const Key('mail-test-to'));
    await tester.enterText(find.byKey(const Key('mail-test-to')), 'me@example.com');
    await tester.tap(find.byKey(const Key('mail-test-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('POST /adminapi/mail/test'));
    expect(lastBody!['to'], 'me@example.com');
    await scrollTo(tester, const Key('mail-stat-sent'));
    expect(find.text('me@example.com'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    await scrollTo(tester, const Key('mail-test-to'));
    await tester.enterText(find.byKey(const Key('mail-test-to')), 'x@bounce.test');
    await tester.tap(find.byKey(const Key('mail-test-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('فشل الإرسال'), findsOneWidget);
    await scrollTo(tester, const Key('mail-stat-failed'));
    expect(find.byKey(const Key('mail-log-m2')), findsOneWidget);
    expect(find.textContaining('550'), findsWidgets);
  });
}
