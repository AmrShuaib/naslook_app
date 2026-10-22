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
import 'package:naslook/pages/chat/chats_page.dart';
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
  /// ردّ الإرسال بلا مرسل ولا مستلم (شكل رأيناه من النواة)
  bool bareSendReply = false;
  /// إن وُجدت، يُؤخَّر الرد على الإرسال حتى تكتمل (لاختبار حالة "جارٍ الإرسال").
  Completer<void>? gate;
  int counter = 0;
  final calls = <String>[];
  final meta = <Map>[];
  final accepted = <String>[];

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
      if (bareSendReply) return _json({'id': m['id'], 'content': m['content'], 'created_at': m['sent_at']});
      return _json({'message': m});
    }
    if (req.method == 'POST' && path.endsWith('/read')) return _json({'ok': true});
    if (req.method == 'POST' && path == '/chat/meta') { meta.add(jsonDecode(req.body) as Map); return _json({'ok': true}); }
    if (req.method == 'GET' && path == '/chat/meta') {
      final ids = (req.url.queryParameters['ids'] ?? '').split(',');
      return _json({for (final m in meta) if (ids.contains(m['messageId'])) m['messageId'] as String: {'quote': m['quote'], 'replyTo': m['replyTo'], 'forwardedFrom': m['forwardedFrom'], 'extra': m['extra']}});
    }
    if (req.method == 'GET' && path == '/messages/search') {
      final q = req.url.queryParameters['q'] ?? '';
      return _json([for (final m in messages) if ((m['content'] as String).contains(q)) {...m, 'peerId': m['sender_id'] == 'SA0000001' ? 'SA0000002' : m['sender_id']}]);
    }
    if (req.method == 'GET' && path == '/chats') return _json([{'id': 'SA0000002', 'nickname': 'sara', 'lastType': 'text', 'lastContent': 'آخر رسالة', 'unread': 1}]);
    if (req.method == 'GET' && path == '/requests') return _json([{'from': {'id': 'SA0000009', 'nickname': 'newguy'}, 'lastContent': 'هلا، ممكن نتعرف؟'}]);
    if (req.method == 'GET' && path == '/contacts') return _json([]);
    if (req.method == 'POST' && path == '/contacts') { accepted.add((jsonDecode(req.body) as Map)['contactId'] as String); return _json({'ok': true}); }
    if (path.startsWith('/presence/')) return _json({'online': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Map<String, dynamic> _msg(String id, String from, String text, Duration ago) => {
      'id': id, 'sender_id': from, 'type': 'text', 'content': text, 'sent_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

Future<void> _pumpThread(WidgetTester tester, _FakeServer srv, {Widget? home}) async {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
    ],
    child: MaterialApp(home: home ?? const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Message.kindOf', () {
    test('derives media kind from a chat media URL sent as text', () {
      expect(Message.kindOf('text', 'https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a'), 'audio');
      expect(Message.kindOf('text', 'https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.jpg'), 'image');
      expect(Message.kindOf('text', 'https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.mp4'), 'video');
      expect(Message.kindOf('text', 'شوف https://naslife.app/chat/media/x.jpg'), 'text');
      expect(Message.kindOf('text', 'https://example.com/a.jpg'), 'text');
      // مسار وسائط الخادم الأساسي من النسخ القديمة
      expect(Message.kindOf('text', 'https://naslife.app/files/5320f951-254d-4498-8ec2-c25e02bffecf.jpg'), 'image');
      expect(Message.kindOf('text', '/files/abc.webm'), 'video');
      expect(Message.kindOf('image', '/chat/media/x.jpg'), 'image');
      expect(Message.previewOf('text', 'https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a'), '🎤 رسالة صوتية');
    });
  });

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

  group('Message.isMine', () {
    Message m(String from, {String? to}) => Message(id: 'x', senderId: from, recipientId: to, type: 'text', content: 't');
    test('does not depend on the sender field: me, my id, anyone but the peer, or recipient == peer', () {
      expect(m('SA0000001').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue);
      expect(m('sa0000001').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue, reason: 'حالة الأحرف لا تهم');
      expect(m('me').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue);
      expect(m('SA0000002').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isFalse);
      expect(m('SA0000009').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue, reason: 'في محادثة ثنائية من ليس الطرف الآخر فهو أنا');
      expect(m('', to: 'SA0000002').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue);
      expect(m('', to: 'SA0000001').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isFalse);
      expect(m('').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isFalse);
      expect(Message(id: 'x', localId: 'local-1', senderId: '', type: 'text', content: 't').isMine(myId: 'SA0000001', peerId: 'SA0000002'), isTrue, reason: 'المنشأة على هذا الجهاز لي');
    });
    test('fromJson reads the sender under the names the core may use', () {
      for (final k in ['sender_id', 'senderId', 'from', 'from_id', 'user_id', 'author_id']) {
        expect(Message.fromJson({'id': '1', k: 'SA0000001', 'content': 't'}).senderId, 'SA0000001', reason: k);
      }
      expect(Message.fromJson({'id': '1', 'from_id': 'SA0000001', 'to_id': 'SA0000002', 'content': 't'}).recipientId, 'SA0000002');
    });
  });

  testWidgets('bubbles keep their sides when the core names the sender from_id instead of sender_id', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([
        {'id': 'm1', 'from_id': 'SA0000002', 'to_id': 'SA0000001', 'type': 'text', 'content': 'مرحبا', 'sent_at': DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String()},
        {'id': 'm2', 'from_id': 'SA0000001', 'to_id': 'SA0000002', 'type': 'text', 'content': 'أهلاً', 'sent_at': DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String()},
      ]);
    await _pumpThread(tester, srv);
    AlignmentGeometry sideOf(String text) => tester.widgetList<Align>(find.ancestor(of: find.text(text), matching: find.byType(Align)))
        .map((a) => a.alignment).firstWhere((a) => a == AlignmentDirectional.centerEnd || a == AlignmentDirectional.centerStart);
    expect(sideOf('أهلاً'), AlignmentDirectional.centerEnd, reason: 'رسالتي في جهة النهاية');
    expect(sideOf('مرحبا'), AlignmentDirectional.centerStart, reason: 'رسالة الطرف الآخر في جهة البداية');
  });

  testWidgets('my sent message stays on my side when the send reply carries no sender or recipient', (tester) async {
    final srv = _FakeServer()
      ..bareSendReply = true
      ..messages.add(_msg('p1', 'SA0000002', 'بدي استشارة', const Duration(minutes: 1)));
    await _pumpThread(tester, srv);
    await tester.enterText(find.byType(TextField), 'تفضلي');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    AlignmentGeometry sideOf(String text) => tester.widgetList<Align>(find.ancestor(of: find.text(text), matching: find.byType(Align)))
        .map((a) => a.alignment).firstWhere((a) => a == AlignmentDirectional.centerEnd || a == AlignmentDirectional.centerStart);
    expect(sideOf('تفضلي'), AlignmentDirectional.centerEnd, reason: 'رسالتي في جهة النهاية رغم ردّ الخادم الخالي من المرسل');
    expect(sideOf('بدي استشارة'), AlignmentDirectional.centerStart);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget, reason: 'أُكّدت بمعرّف الخادم');
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
    await tester.pump();
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
    await tester.pump();
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

  testWidgets('reply: long-press → رد → send shows the quote and stores meta', (tester) async {
    final srv = _FakeServer()..messages.add(_msg('m1', 'SA0000002', 'متى نتقابل؟', const Duration(minutes: 3)));
    await _pumpThread(tester, srv);
    await tester.longPress(find.text('متى نتقابل؟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('رد'));
    await tester.pumpAndSettle();
    // شريط الرد فوق حقل الكتابة
    expect(find.text('إلغاء الرد'), findsNothing); // tooltip لا يُعرض كنص
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'الساعة 7');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('الساعة 7'), findsOneWidget);
    // الاقتباس يظهر داخل الفقاعة (باسم المرسل ونص الرسالة الأصلية)
    expect(find.text('متى نتقابل؟'), findsNWidgets(2));
    expect(srv.meta.single['quote']['content'], 'متى نتقابل؟');
    expect(srv.meta.single['messageId'], 'srv-1');
  });

  testWidgets('in-thread search counts and highlights matches', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([
        _msg('m1', 'SA0000002', 'قهوة الصباح', const Duration(minutes: 5)),
        _msg('m2', 'SA0000001', 'قهوة المساء أفضل', const Duration(minutes: 4)),
        _msg('m3', 'SA0000002', 'شاي؟', const Duration(minutes: 3)),
      ]);
    await _pumpThread(tester, srv);
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'ابحث في المحادثة…'), 'قهوة');
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('chats page: local search filters, requests tab lists and accepts', (tester) async {
    final srv = _FakeServer();
    await _pumpThread(tester, srv, home: const Scaffold(body: ChatsPage()));
    expect(find.text('sara'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('sara'), findsNothing);
    expect(find.text('لا نتائج'), findsOneWidget);
    await tester.tap(find.text('الطلبات · 1'));
    await tester.pumpAndSettle();
    expect(find.text('newguy'), findsOneWidget);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    expect(srv.accepted, ['SA0000009']);
  });
}
