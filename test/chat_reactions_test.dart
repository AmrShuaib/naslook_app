// تفاعلات رسائل المحادثة: نقر مزدوج على الفقاعة يعطي قلباً أحمر منبثقاً ويسجّل ❤️، والضغط المطوّل يعرض شريط الإيموجي أعلى
// الخيارات، وشرائح التفاعلات تُعرض تحت الفقاعة وتصل مع بيانات الرسائل الإضافية.
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
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _calls = <String>[];
final _bodies = <String, Map<String, dynamic>>{};
http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
Future<http.Response> _handle(http.Request req) async {
  final path = req.url.path;
  final key = '${req.method} $path';
  _calls.add(key);
  if (req.body.startsWith('{')) _bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
  if (req.method == 'GET' && path == '/messages/SA0000002') {
    return _json([
      {'id': 'm1', 'sender_id': 'SA0000002', 'type': 'text', 'content': 'صباح الخير', 'sent_at': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String()},
      {'id': 'm2', 'sender_id': 'SA0000001', 'type': 'text', 'content': 'أهلاً', 'sent_at': DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String()},
    ]);
  }
  if (req.method == 'GET' && path == '/chat/meta') return _json({'m2': {'replyTo': null, 'quote': null, 'forwardedFrom': null, 'extra': null, 'reactions': [{'emoji': '🔥', 'count': 1, 'mine': false}]}});
  if (req.method == 'POST' && path == '/chat/react') {
    final e = _bodies[key]!['emoji'] as String;
    return _json({'ok': true, 'messageId': _bodies[key]!['messageId'], 'reactions': e.isEmpty ? [] : [{'emoji': e, 'count': 1, 'mine': true}]});
  }
  if (req.method == 'GET' && path == '/notify/unread') return _json({'unread': 0});
  if (path.startsWith('/presence/')) return _json({'online': true});
  if (req.method == 'POST') return _json({'ok': true});
  return _json({'error': 'not-found'}, 404);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    _calls.clear();
    _bodies.clear();
  });

  testWidgets('reactions arrive with message meta and show as chips under the bubble', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('chip-🔥')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('double-tap on a bubble bursts a heart and sends ❤️', (tester) async {
    await _pump(tester);
    final bubble = find.text('صباح الخير');
    await tester.tap(bubble);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(bubble);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('heart-burst')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_bodies['POST /chat/react']!['messageId'], 'm1');
    expect(_bodies['POST /chat/react']!['emoji'], '❤️');
    expect(find.byKey(const Key('chip-❤️')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('long-press shows the reaction bar above the actions; picking 😂 reacts', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('صباح الخير'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('react-😂')), findsOneWidget);
    expect(find.text('رد'), findsOneWidget, reason: 'الخيارات المعتادة ما زالت تحت الشريط');
    await tester.tap(find.byKey(const Key('react-😂')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_bodies['POST /chat/react']!['emoji'], '😂');
    expect(find.byKey(const Key('chip-😂')), findsOneWidget);
  });
}
