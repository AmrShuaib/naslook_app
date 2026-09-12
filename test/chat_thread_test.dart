import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

/// حالة تطبيق مسجّل الدخول بدون الاتصال بالخادم.
class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// خادم وهمي يحاكي مسارات المحادثة.
class _FakeServer {
  final List<Map<String, dynamic>> messages = [];
  bool failSend = false;
  /// إن وُجدت، يُؤخَّر الرد على الإرسال حتى تكتمل (لاختبار حالة "جارٍ الإرسال").
  Completer<void>? gate;
  int counter = 0;
  final calls = <String>[];

  http.Response _json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.method == 'GET' && path == '/messages/SA0000002') {
      final before = req.url.queryParameters['before'];
      final list = before == null ? messages : messages.where((m) => DateTime.parse(m['sent_at'] as String).isBefore(DateTime.parse(before))).toList();
      return _json(list);
    }
    if (req.method == 'POST' && path == '/messages') {
      if (gate != null) await gate!.future;
      if (failSend) return _json({'error': 'boom'}, 500);
      final b = jsonDecode(req.body) as Map;
      final m = {'id': 'srv-${++counter}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      messages.add(m);
      return _json({'message': m});
    }
    if (req.method == 'POST' && path.endsWith('/read')) return _json({'ok': true});
    if (path.startsWith('/presence/')) return _json({'online': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Map<String, dynamic> _msg(String id, String from, String text, Duration ago) => {
      'id': id, 'sender_id': from, 'type': 'text', 'content': text, 'sent_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

Future<void> _pumpThread(WidgetTester tester, _FakeServer srv) async {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
    ],
    child: const MaterialApp(home: ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('dayLabel', () {
    final now = DateTime(2026, 9, 11, 15); // الجمعة
    test('today / yesterday / weekday / date / other year', () {
      expect(dayLabel(DateTime(2026, 9, 11, 8), now: now), 'اليوم');
      expect(dayLabel(DateTime(2026, 9, 10, 23), now: now), 'أمس');
      expect(dayLabel(DateTime(2026, 9, 8), now: now), 'الثلاثاء');
      expect(dayLabel(DateTime(2026, 8, 30), now: now), '30 أغسطس');
      expect(dayLabel(DateTime(2025, 12, 25), now: now), '25 ديسمبر 2025');
    });
  });

  testWidgets('loads messages, shows the day separator and marks them read', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([_msg('m1', 'SA0000002', 'مرحبا', const Duration(minutes: 2)), _msg('m2', 'SA0000001', 'أهلاً', const Duration(minutes: 1))]);
    await _pumpThread(tester, srv);
    expect(find.text('مرحبا'), findsOneWidget);
    expect(find.text('أهلاً'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(srv.calls, contains('POST /messages/SA0000002/read'));
  });

  testWidgets('sends optimistically then confirms with the server id', (tester) async {
    final srv = _FakeServer()..gate = Completer<void>();
    await _pumpThread(tester, srv);
    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    // تظهر فوراً بحالة "جارٍ الإرسال" وحقل الكتابة فارغ
    expect(find.text('hello there'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    srv.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(srv.messages.single['content'], 'hello there');
  });

  testWidgets('a failed send stays visible with retry, and retry succeeds once', (tester) async {
    final srv = _FakeServer()..failSend = true;
    await _pumpThread(tester, srv);
    await tester.enterText(find.byType(TextField), 'FAIL');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('FAIL'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('لم تُرسل · اضغط لإعادة المحاولة'), findsOneWidget);

    srv.failSend = false;
    await tester.tap(find.text('FAIL'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.text('FAIL'), findsOneWidget);
    expect(srv.messages.where((m) => m['content'] == 'FAIL').length, 1);
    await tester.pump(const Duration(seconds: 5)); // إخفاء رسالة الخطأ المنبثقة
  });

  testWidgets('resync after the tab becomes visible again does not duplicate messages', (tester) async {
    final srv = _FakeServer()..messages.add(_msg('m1', 'SA0000002', 'مرحبا', const Duration(minutes: 2)));
    await _pumpThread(tester, srv);
    final loads = srv.calls.where((c) => c == 'GET /messages/SA0000002').length;
    srv.messages.add(_msg('m9', 'SA0000002', 'وصلتك وأنت بعيد', const Duration(seconds: 10)));

    for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(st);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(srv.calls.where((c) => c == 'GET /messages/SA0000002').length, loads + 1);
    expect(find.text('مرحبا'), findsOneWidget);
    expect(find.text('وصلتك وأنت بعيد'), findsOneWidget);
  });
}
