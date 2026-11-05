import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/profile_v2_models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/api/ws.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/posts/moment_actions.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

/// «من يراسلني»: النواة تملك POST /messages ولا تفحص السياسة، فالتطبيق يسأل GET /profiles/:id/can-message قبل أول رسالة
/// ويستبدل المؤلّف بإشعار واضح حين يُرفض، ولا يمنع الرد أبداً على من كتب لي أولاً.

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _FakeSocket extends NaslifeSocket {
  final ctl = StreamController<Map<String, dynamic>>.broadcast();
  _FakeSocket() : super(url: 'ws://test.local/ws', token: 't');
  @override
  Stream<Map<String, dynamic>> get events => ctl.stream;
  @override
  bool get connected => true;
  @override
  void typing(String to) {}
  @override
  void close() => ctl.close();
}

class _Srv {
  final messages = <Map<String, dynamic>>[];
  /// ردّ الفحص؛ null = المسار غير موجود (خادم قديم 404)
  Map<String, dynamic>? gate;
  /// إن وُجدت، يتأخر ردّ الفحص حتى تكتمل (إرسال أثناء الفحص)
  Completer<void>? gateDelay;
  /// إن وُجدت، يتأخر السجل حتى تكتمل (إرسال قبل وصول السجل)
  Completer<void>? historyDelay;
  /// رمز ردّ السجل (500 = تعذّر التحميل)
  int historyStatus = 200;
  /// فحص شخص آخر (إعادة التوجيه)
  final otherGates = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> contacts = const [];
  final sentTo = <String>[];
  final sentBodies = <String>[];
  final calls = <String>[];
  final contactsAdded = <String>[];
  int counter = 0;

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.method == 'GET' && path == '/messages/SA0000002') {
      if (historyDelay != null) await historyDelay!.future;
      return historyStatus == 200 ? _json(messages) : _json({'error': 'boom'}, historyStatus);
    }
    if (req.method == 'GET' && path == '/profiles/SA0000002/can-message') {
      if (gateDelay != null) await gateDelay!.future;
      return gate == null ? _json({'error': 'not-found'}, 404) : _json(gate!);
    }
    final other = RegExp(r'^/profiles/(SA\d{7})/can-message$').firstMatch(path);
    if (req.method == 'GET' && other != null) return _json(otherGates[other.group(1)] ?? {'ok': true, 'reason': null});
    if (req.method == 'POST' && path == '/messages') {
      final b = jsonDecode(req.body) as Map;
      sentTo.add(b['to'] as String);
      sentBodies.add(b['content'] as String);
      final m = {'id': 'srv-${++counter}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      messages.add(m);
      return _json({'message': m});
    }
    if (req.method == 'GET' && path == '/users/sara') return _json({'id': 'SA0000002', 'nickname': 'sara'});
    if (req.method == 'POST' && path == '/contacts') { contactsAdded.add((jsonDecode(req.body) as Map)['contactId'] as String); return _json({'ok': true}); }
    if (req.method == 'GET' && path == '/contacts') return _json(contacts);
    if (req.method == 'GET' && path == '/chats') return _json([]);
    if (req.method == 'GET' && path == '/requests') return _json([]);
    if (req.method == 'POST' && path.endsWith('/read')) return _json({'ok': true});
    if (path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }

  int get gateCalls => calls.where((c) => c == 'GET /profiles/SA0000002/can-message').length;
  bool get sent => calls.contains('POST /messages');
  int get sendCount => calls.where((c) => c == 'POST /messages').length;
}

Map<String, dynamic> _msg(String id, String from, String text) => {'id': id, 'sender_id': from, 'type': 'text', 'content': text, 'sent_at': DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String()};

Future<void> _pump(WidgetTester tester, _Srv srv, {Widget? home, NaslifeSocket? socket}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(home: home ?? const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  await tester.pumpAndSettle();
}

/// كـ [_pump] بلا انتظار الاستقرار: السجل المؤجَّل يبقي الصفحة في التحميل.
Future<void> _pumpLoading(WidgetTester tester, _Srv srv, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// يفتح قائمة المرفقات وينقر «موقعي الحي» (آخر عنصر في القائمة، قد يكون خارج الشاشة).
Future<void> _openAttachLive(WidgetTester tester) async {
  await tester.tap(find.byTooltip('إرفاق'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('attach-live')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('attach-live')));
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('composer-field')), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
}

void main() {
  test('MessageGate parses the reason and fails open without ok', () {
    expect(MessageGate.fromJson({'ok': false, 'reason': 'friends-only'}).notice, 'هذا الشخص يستقبل الرسائل من أصدقائه فقط');
    expect(MessageGate.fromJson({'ok': false, 'reason': 'nobody'}).notice, 'هذا الشخص لا يستقبل رسائل جديدة');
    expect(MessageGate.fromJson({'ok': false, 'reason': 'blocked'}).friendsOnly, isFalse);
    expect(MessageGate.fromJson(const {}).ok, isTrue, reason: 'رد ناقص لا يقفل المحادثة');
    expect(ProfileFlags.fromJson({'canMessage': false, 'messageReason': 'nobody'}).messageReason, 'nobody');
    expect(ProfileFlags.fromJson(const {}).messageReason, isNull);
  });

  testWidgets('friends-only blocks a stranger: notice replaces the composer, «إضافة صديق» sends a request', (tester) async {
    final srv = _Srv()..gate = {'ok': false, 'reason': 'friends-only'};
    await _pump(tester, srv);
    expect(srv.gateCalls, 1);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
    expect(find.text('هذا الشخص يستقبل الرسائل من أصدقائه فقط'), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsNothing, reason: 'المؤلّف كله (والمرفقات والتسجيل) مخفي');
    expect(find.text('لا رسائل بينكما بعد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('msg-gate-add-friend')));
    await tester.pumpAndSettle();
    expect(srv.contactsAdded, ['SA0000002']);
    expect(find.byKey(const Key('msg-gate-add-friend')), findsNothing);
    expect(find.text('أُرسل طلب الصداقة؛ تستطيع مراسلته بعد قبوله'), findsOneWidget);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget, reason: 'الطلب وحده لا يفتح المراسلة');
    expect(srv.sent, isFalse);
  });

  // قاعدة الصديق نفسها (من أضافه صاحب الحساب) يختبرها harness_profile_v2.mjs؛ هنا أن التطبيق يطيع «ok» من الخادم
  testWidgets('an ok from the server (a friend under friends-only) keeps the composer and the message goes out', (tester) async {
    final srv = _Srv()..gate = {'ok': true, 'reason': null};
    await _pump(tester, srv);
    expect(srv.gateCalls, 1);
    expect(find.byKey(const Key('msg-gate')), findsNothing);
    await _send(tester, 'هلا');
    expect(srv.sent, isTrue);
    expect(find.text('هلا'), findsOneWidget);
  });

  testWidgets('a reply is never blocked when the peer wrote first (no pre-check at all)', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'nobody'}
      ..messages.add(_msg('p1', 'SA0000002', 'مرحبا، عندي سؤال'));
    await _pump(tester, srv);
    expect(srv.gateCalls, 0, reason: 'الطرف الآخر كتب أولاً فلا حاجة للفحص');
    expect(find.byKey(const Key('msg-gate')), findsNothing);
    await _send(tester, 'تفضل');
    expect(srv.sent, isTrue);
  });

  testWidgets('a gate handed in by «محادثة جديدة» is ignored once the history shows the peer wrote to me', (tester) async {
    final srv = _Srv()..messages.add(_msg('p1', 'SA0000002', 'أهلاً'));
    await _pump(tester, srv, home: const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'), gate: MessageGate(ok: false, reason: 'friends-only')));
    expect(find.byKey(const Key('msg-gate')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
  });

  testWidgets('the composer opens when the peer writes while I am gated', (tester) async {
    final socket = _FakeSocket();
    final srv = _Srv()..gate = {'ok': false, 'reason': 'friends-only'};
    await _pump(tester, srv, socket: socket);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
    socket.ctl.add({'event': 'message', 'message': _msg('p2', 'SA0000002', 'هلا، تفضل')});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('msg-gate')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
  });

  testWidgets('a message typed while the check is still running waits for it and is not sent when refused', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'friends-only'}
      ..gateDelay = Completer<void>();
    await _pump(tester, srv);
    expect(find.byKey(const Key('composer-field')), findsOneWidget, reason: 'الفحص لم يرجع بعد');
    await tester.enterText(find.byKey(const Key('composer-field')), 'سريع');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    srv.gateDelay!.complete();
    await tester.pumpAndSettle();
    expect(srv.sent, isFalse);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
    expect(find.text('هذا الشخص يستقبل الرسائل من أصدقائه فقط'), findsWidgets, reason: 'الإشعار والتنبيه');
  });

  testWidgets('forwarding to someone who does not accept new messages is refused before sending', (tester) async {
    final srv = _Srv()
      ..messages.add(_msg('p1', 'SA0000002', 'شوف هذا'))
      ..contacts = [{'id': 'SA0000003', 'nickname': 'khalid'}, {'id': 'SA0000004', 'nickname': 'noura'}]
      ..otherGates['SA0000003'] = {'ok': false, 'reason': 'nobody'};
    await _pump(tester, srv);
    Future<void> forwardTo(String name) async {
      await tester.longPress(find.text('شوف هذا'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعادة توجيه'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    await forwardTo('khalid');
    expect(srv.sentTo, isEmpty);
    expect(find.text('هذا الشخص لا يستقبل رسائل جديدة'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await forwardTo('noura');
    expect(srv.sentTo, ['SA0000004']);
  });

  testWidgets("'none' blocks a new conversation without «إضافة صديق»", (tester) async {
    final srv = _Srv()..gate = {'ok': false, 'reason': 'nobody'};
    await _pump(tester, srv);
    expect(find.text('هذا الشخص لا يستقبل رسائل جديدة'), findsOneWidget);
    expect(find.byKey(const Key('msg-gate-add-friend')), findsNothing);
    expect(find.byKey(const Key('composer-field')), findsNothing);
  });

  testWidgets('an old server without the route (404) allows sending as before', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv);
    expect(srv.gateCalls, 1);
    expect(find.byKey(const Key('msg-gate')), findsNothing);
    await _send(tester, 'مرحبا');
    expect(srv.sent, isTrue);
  });

  testWidgets('«محادثة جديدة» checks before opening and the thread shows the reason without asking again', (tester) async {
    final srv = _Srv()..gate = {'ok': false, 'reason': 'nobody'};
    await _pump(tester, srv, home: const Scaffold(body: ChatsPage()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'sara');
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatThreadPage), findsOneWidget);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
    expect(find.text('هذا الشخص لا يستقبل رسائل جديدة'), findsOneWidget);
    expect(srv.gateCalls, 1, reason: 'الفحص مرة واحدة قبل الفتح');
  });
  testWidgets('a pre-filled message sent before the history arrives waits for it and the check (no send when refused)', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'friends-only'}
      ..historyDelay = Completer<void>();
    await _pumpLoading(tester, srv, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'), initialText: '#post/abc '));
    expect(find.byKey(const Key('composer-field')), findsOneWidget, reason: 'السجل لم يصل بعد');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(srv.sent, isFalse, reason: 'لا إرسال قبل أن يُعرف هل كتب لي');
    srv.historyDelay!.complete();
    await tester.pumpAndSettle();
    expect(srv.gateCalls, 1);
    expect(srv.sent, isFalse);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
  });

  testWidgets('a pre-filled message sent before the history arrives goes out when the peer had written (no check)', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'nobody'}
      ..historyDelay = Completer<void>()
      ..messages.add(_msg('p1', 'SA0000002', 'عندي سؤال'));
    await _pumpLoading(tester, srv, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'), initialText: 'تفضل'));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    srv.historyDelay!.complete();
    await tester.pumpAndSettle();
    expect(srv.gateCalls, 0);
    expect(srv.sentBodies, ['تفضل']);
  });

  testWidgets('a history error still runs the check: no unchecked send', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'nobody'}
      ..historyStatus = 500;
    await _pump(tester, srv, home: const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'), initialText: 'مرحبا'));
    expect(srv.gateCalls, 1, reason: 'الفحص يجري رغم تعذّر السجل');
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsNothing);
    expect(srv.sent, isFalse);
  });

  testWidgets('a history error with an ok check keeps sending as before', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': true, 'reason': null}
      ..historyStatus = 500;
    await _pump(tester, srv);
    expect(srv.gateCalls, 1);
    await _send(tester, 'هلا');
    expect(srv.sentBodies, ['هلا']);
  });

  testWidgets('two taps on send while the check is pending send the message once', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': true, 'reason': null}
      ..gateDelay = Completer<void>();
    await _pump(tester, srv);
    await tester.enterText(find.byKey(const Key('composer-field')), 'مرة');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    srv.gateDelay!.complete();
    await tester.pumpAndSettle();
    expect(srv.sentBodies, ['مرة']);
    expect(srv.sendCount, 1);
  });

  testWidgets('«موقعي الحي» waits for the check and does not open when refused', (tester) async {
    final srv = _Srv()
      ..gate = {'ok': false, 'reason': 'friends-only'}
      ..gateDelay = Completer<void>();
    await _pump(tester, srv);
    await _openAttachLive(tester);
    await tester.pump();
    srv.gateDelay!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-min-15')), findsNothing, reason: 'ورقة المشاركة لم تُفتح');
    expect(find.text('هذا الشخص يستقبل الرسائل من أصدقائه فقط'), findsNWidgets(2), reason: 'الإشعار والتنبيه بعد النقر');
    expect(srv.calls.where((c) => c.startsWith('POST /chat/live')), isEmpty);
    expect(srv.sent, isFalse);
    expect(find.byKey(const Key('msg-gate')), findsOneWidget);
  });

  testWidgets('«موقعي الحي» opens normally when the check allows', (tester) async {
    final srv = _Srv()..gate = {'ok': true, 'reason': null};
    await _pump(tester, srv);
    await _openAttachLive(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-min-15')), findsOneWidget);
  });

  testWidgets('sending a moment in chat checks the recipient first', (tester) async {
    final srv = _Srv()
      ..contacts = [{'id': 'SA0000003', 'nickname': 'khalid'}, {'id': 'SA0000004', 'nickname': 'noura'}]
      ..otherGates['SA0000003'] = {'ok': false, 'reason': 'nobody'};
    final post = MapPost.fromJson({'id': 'aaaaaaaa-0000-4000-8000-000000000001', 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': 'غروب', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment', 'lat': 21.5, 'lng': 39.1, 'status': 'active'});
    await _pump(tester, srv, home: Scaffold(body: Consumer(builder: (context, ref, _) => Center(child: TextButton(onPressed: () => sendMomentInChat(context, ref, post), child: const Text('أرسل اللحظة'))))));
    Future<void> sendTo(String name) async {
      await tester.tap(find.text('أرسل اللحظة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    await sendTo('khalid');
    expect(srv.sent, isFalse);
    expect(find.text('هذا الشخص لا يستقبل رسائل جديدة'), findsOneWidget);
    await sendTo('noura');
    expect(srv.sentTo, ['SA0000004']);
    expect(find.text('أُرسلت اللحظة إلى noura'), findsOneWidget);
  });
}
