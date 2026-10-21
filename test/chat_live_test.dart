// ميزات المحادثة بنكهة ناس لايف (server/chat_live.js): بطاقة الموقع المباشر (خريطة، عدّ تنازلي، اتجاهات، قراءة كل عشر ثوانٍ
// والتوقف بعد الانتهاء)، ورقة المشاركة (تنشئ الجلسة وترسل "/live <id>" وتدفع الموقع)، الردود المقترحة فوق الحقل،
// «رد خاص» من عارض اللحظات، وزر «الاتجاهات» في بطاقة الموعد.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/chat/codes.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/chat/live_share.dart';
import 'package:naslook/pages/chat/widgets/suggestion_chips.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart';

const _live = 'b1b1b1b1-0000-4000-8000-000000000001';
const _newLive = 'cccccccc-0000-4000-8000-000000000002';
const _post = 'aaaaaaaa-0000-4000-8000-000000000001';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// خادم وهمي: رسائل المحادثة، حلّ @brew92، GET /biz، جلسة الموقع المباشر (مع عدّ القراءات)، والاقتراحات.
class _FakeServer {
  final List<Map<String, dynamic>> messages = [];
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  /// حالة GET /chat/live/:id كما يراها العميل؛ null = لا جلسة.
  Map<String, dynamic>? live;
  int liveGets = 0;
  int counter = 0;
  List<String> suggestions = const ['كم السعر؟', 'فيه خصم؟', 'تمام، أبغى واحد'];

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.startsWith('{')) (bodies[key] ??= []).add(jsonDecode(req.body) as Map<String, dynamic>);
    if (req.method == 'GET' && path == '/messages/SA0000002') return _json(messages);
    if (req.method == 'GET' && path.startsWith('/messages/')) return _json([]);
    if (req.method == 'POST' && path == '/messages') {
      final b = bodies[key]!.last;
      final m = {'id': 'srv-${++counter}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      messages.add(m);
      return _json({'message': m});
    }
    if (path == '/chat/meta') return _json(req.method == 'GET' ? {} : {'ok': true});
    if (req.method == 'GET' && path == '/chat/requests') return _json({});
    if (req.method == 'GET' && path == '/chat/cards') {
      final refs = (req.url.queryParameters['refs'] ?? '').split(',');
      return _json({'refs': {for (final r in refs) r: r == '@brew92' ? {'type': 'biz', 'id': 'biz-brew92', 'title': 'برو 92', 'subtitle': 'حي الروضة، جدة', 'image': null, 'category': 'cafe', 'openNow': true, 'link': '/c/biz-brew92'} : null}});
    }
    if (req.method == 'GET' && path == '/biz/biz-brew92') return _json({'id': 'biz-brew92', 'name': 'Brew 92', 'nameAr': 'برو 92', 'category': 'cafe', 'lat': 21.54, 'lng': 39.17, 'address': 'حي الروضة'});
    final lm = RegExp(r'^/chat/live/([0-9a-f-]{36})$').firstMatch(path);
    if (lm != null) {
      if (req.method == 'GET') {
        liveGets++;
        final l = live;
        if (l == null || l['id'] != lm.group(1)) return _json({'error': 'not-found'}, 404);
        return _json(l);
      }
      if (req.method == 'DELETE' && live != null) live!['active'] = false;
      return _json({'ok': true});
    }
    if (req.method == 'POST' && path == '/chat/live') {
      final b = bodies[key]!.last;
      live = {'id': _newLive, 'from': 'SA0000001', 'to': b['peerId'], 'lat': null, 'lng': null, 'accuracy': null, 'at': null, 'until': DateTime.now().add(Duration(minutes: b['minutes'] as int)).toUtc().toIso8601String(), 'active': true};
      return _json(live!);
    }
    if (req.method == 'POST' && path == '/chat/suggest') return _json({'suggestions': suggestions, 'source': 'rules'});
    if (req.method == 'GET' && path == '/settings/public') return _json({});
    if (req.method == 'GET' && (path == '/contacts' || path == '/chats' || path == '/requests')) return _json([]);
    if (req.method == 'GET' && path == '/notify/unread') return _json({'unread': 0});
    if (path.startsWith('/presence/')) return _json({'online': true});
    if (req.method == 'POST') return _json({'ok': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Map<String, dynamic> _msg(String id, String from, String text, Duration ago) => {
      'id': id, 'sender_id': from, 'type': 'text', 'content': text, 'sent_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

Map<String, dynamic> _postJson() => {
      'id': _post, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'mediaUrl': null, 'caption': 'الكورنيش الليلة', 'bg': '#BF3A1E', 'overlays': [],
      'tag': 'moment', 'lat': 21.55, 'lng': 39.16, 'placeName': 'الكورنيش', 'status': 'active', 'views': 4, 'likes': 1, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

/// يضخّ شاشة بحالة دخول وخادم وهمي؛ نبضات صريحة لا pumpAndSettle (بطاقة الموقع فيها نبض متكرر).
Future<void> _pump(WidgetTester tester, _FakeServer srv, Widget home, {Size size = const Size(480, 1000), bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  if (settle) await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('card-live-status'))).data ?? '';

void main() {
  group('/live code', () {
    test('parses only a uuid, keeps the id in liveId; other text is not a command', () {
      final c = parseCommand('/live $_live');
      expect(c?.kind, CodeKind.live);
      expect(c?.liveId, _live);
      expect(c?.kind.isRef, isFalse);
      expect(c?.kind.needsRequest, isFalse);
      expect(parseCommand('/live'), isNull);
      expect(parseCommand('/live abc'), isNull);
      expect(parseChatText('/live $_live').commandOnly, isTrue);
      expect(parseChatText('/live $_live').refKeys, isEmpty, reason: 'المعرّف ليس إشارة تُطلب من /chat/cards');
      expect(liveCode(_live), '/live $_live');
    });
  });

  testWidgets('live card: map, countdown, directions; polls every 10 s and stops after active:false', (tester) async {
    final until = DateTime.now().add(const Duration(minutes: 30));
    final srv = _FakeServer()
      ..messages.add(_msg('m1', 'SA0000002', '/live $_live', const Duration(minutes: 1)))
      ..live = {'id': _live, 'from': 'SA0000002', 'to': 'SA0000001', 'lat': 21.5433, 'lng': 39.1728, 'accuracy': 10, 'at': DateTime.now().subtract(const Duration(seconds: 5)).toUtc().toIso8601String(), 'until': until.toUtc().toIso8601String(), 'active': true};
    final opened = <Uri>[];
    LegalLinks.openOverride = (u) async => opened.add(u);
    addTearDown(() => LegalLinks.openOverride = null);
    await _pump(tester, srv, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    expect(find.byKey(const Key('card-live-$_live')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('حتى ${clockOf(until)}'), findsOneWidget);
    expect(_status(tester), startsWith('يتحرك الآن · آخر تحديث قبل'));
    expect(find.text('موقع sara المباشر'), findsOneWidget);
    expect(find.byKey(const Key('card-live-stop')), findsNothing, reason: 'الإيقاف لصاحب المشاركة فقط');
    expect(srv.liveGets, 1);
    await tester.tap(find.byKey(const Key('card-live-directions')));
    await tester.pump();
    expect(opened.single.toString(), 'https://www.google.com/maps/dir/?api=1&destination=21.5433,39.1728');
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(srv.liveGets, 2, reason: 'قراءة كل عشر ثوانٍ');
    srv.live!['active'] = false;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(srv.liveGets, 3);
    expect(_status(tester), 'انتهت المشاركة');
    expect(find.byKey(const Key('card-live-directions')), findsNothing);
    expect(find.byKey(const Key('card-live-until')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(srv.liveGets, 3, reason: 'لا قراءة بعد الانتهاء');
  });

  testWidgets('live card for the sharer: «إيقاف المشاركة» deletes the session and ends the card', (tester) async {
    final srv = _FakeServer()
      ..messages.add(_msg('m1', 'SA0000001', '/live $_live', const Duration(minutes: 1)))
      ..live = {'id': _live, 'from': 'SA0000001', 'to': 'SA0000002', 'lat': 21.5, 'lng': 39.2, 'accuracy': null, 'at': DateTime.now().toUtc().toIso8601String(), 'until': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(), 'active': true};
    addTearDown(LiveShareController.resetForTests);
    await _pump(tester, srv, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    expect(find.text('موقعي المباشر'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card-live-stop')));
    await _settle(tester, 2);
    expect(srv.calls, contains('DELETE /chat/live/$_live'));
    expect(_status(tester), 'انتهت المشاركة');
    expect(find.byKey(const Key('card-live-stop')), findsNothing);
  });

  testWidgets('share sheet: duration chips with the privacy note, creates the session, sends /live, pushes every 10 s, stop deletes', (tester) async {
    DeviceLocation.override = () async => const LatLng(21.5, 39.2);
    addTearDown(() { DeviceLocation.override = null; LiveShareController.resetForTests(); });
    final srv = _FakeServer();
    await _pump(tester, srv, Scaffold(body: Consumer(builder: (context, ref, _) => Center(child: FilledButton(key: const Key('open'), onPressed: () => showLiveShareSheet(context, ref, 'SA0000002'), child: const Text('شارك'))))));
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);
    expect(find.textContaining('سيرى الطرف الآخر موقعك لمدة ساعة ثم يتوقف تلقائياً'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-min-15')));
    await tester.pump();
    expect(find.textContaining('لمدة 15 دقيقة ثم يتوقف تلقائياً'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-start')));
    await _settle(tester);
    expect(srv.bodies['POST /chat/live']!.single, {'peerId': 'SA0000002', 'minutes': 15});
    expect(srv.bodies['POST /messages']!.single['content'], '/live $_newLive');
    expect(srv.bodies['PUT /chat/live/$_newLive']!.single, {'lat': 21.5, 'lng': 39.2});
    expect(find.byKey(const Key('live-start')), findsNothing, reason: 'الورقة تُغلق بعد البدء');
    expect(find.textContaining('بدأت مشاركة موقعك حتى'), findsOneWidget);
    final ctl = LiveShareController.activeFor('SA0000002');
    expect(ctl, isNotNull);
    expect(identical(ctl, LiveShareController.of('SA0000002')), isTrue, reason: 'متحكّم واحد لكل طرف');
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester, 2);
    expect(srv.bodies['PUT /chat/live/$_newLive']!.length, 2, reason: 'دفعة كل عشر ثوانٍ');
    // إعادة الفتح: الحالة النشطة وزر الإيقاف
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);
    expect(find.byKey(const Key('live-active-note')), findsOneWidget);
    expect(find.byKey(const Key('live-start')), findsNothing);
    await tester.tap(find.byKey(const Key('live-stop')));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /chat/live/$_newLive'));
    expect(LiveShareController.activeFor('SA0000002'), isNull);
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester, 2);
    expect(srv.bodies['PUT /chat/live/$_newLive']!.length, 2, reason: 'لا دفع بعد الإيقاف');
  });

  testWidgets('share sheet: no location → error line, nothing created', (tester) async {
    DeviceLocation.override = () async => null;
    addTearDown(() { DeviceLocation.override = null; LiveShareController.resetForTests(); });
    final srv = _FakeServer();
    await _pump(tester, srv, Scaffold(body: Consumer(builder: (context, ref, _) => Center(child: FilledButton(key: const Key('open'), onPressed: () => showLiveShareSheet(context, ref, 'SA0000002'), child: const Text('شارك'))))));
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('live-start')));
    await _settle(tester);
    expect(find.byKey(const Key('live-error')), findsOneWidget);
    expect(srv.calls.where((c) => c == 'POST /chat/live'), isEmpty);
    expect(LiveShareController.activeFor('SA0000002'), isNull);
  });

  testWidgets('suggestion chips: 600 ms after a peer message, pick inserts the text; hidden when the last message is mine', (tester) async {
    final srv = _FakeServer();
    String? picked;
    Widget chips(List<Message> msgs) => Scaffold(body: Column(children: [SuggestionChips(peerId: 'SA0000002', messages: msgs, onPick: (t) => picked = t)]));
    final peer1 = Message(id: '1', senderId: 'SA0000002', type: 'text', content: 'بكم القهوة؟');
    await _pump(tester, srv, chips([peer1]), settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(srv.calls.where((c) => c == 'POST /chat/suggest'), isEmpty, reason: 'مهلة هدوء قبل الطلب');
    expect(find.byKey(const Key('suggestion-chips')), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(srv.calls.where((c) => c == 'POST /chat/suggest').length, 1);
    expect(srv.bodies['POST /chat/suggest']!.single, {'peerId': 'SA0000002', 'messages': [{'mine': false, 'text': 'بكم القهوة؟'}]});
    expect(find.byKey(const Key('suggestion-chips')), findsOneWidget);
    expect(find.text('كم السعر؟'), findsOneWidget);
    expect(find.text('فيه خصم؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggest-chip-0')));
    await tester.pump();
    expect(picked, 'كم السعر؟');
    expect(find.byKey(const Key('suggestion-chips')), findsNothing, reason: 'تختفي بعد الاختيار');
    // رددتُ: لا طلب ولا رقائق
    final mine = Message(id: '2', senderId: 'SA0000001', type: 'text', content: 'كم السعر؟');
    await tester.pumpWidget(tester.widget(find.byType(ProviderScope)));
    await _pumpInto(tester, srv, chips([peer1, mine]));
    await tester.pump(const Duration(milliseconds: 800));
    expect(srv.calls.where((c) => c == 'POST /chat/suggest').length, 1);
    expect(find.byKey(const Key('suggestion-chips')), findsNothing);
    // رسالة واردة جديدة: طلب جديد يحمل الأدوار كلها
    final peer2 = Message(id: '3', senderId: 'SA0000002', type: 'text', content: 'السلام عليكم');
    srv.suggestions = const ['وعليكم السلام ورحمة الله', 'هلا والله', 'أهلاً، كيف الحال؟'];
    await _pumpInto(tester, srv, chips([peer1, mine, peer2]));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(srv.calls.where((c) => c == 'POST /chat/suggest').length, 2);
    expect((srv.bodies['POST /chat/suggest']!.last['messages'] as List).map((m) => m['mine']).toList(), [false, true, false]);
    expect(find.text('هلا والله'), findsOneWidget);
  });

  testWidgets('«رد خاص» in the moment viewer opens the thread prefilled with #post/<id>', (tester) async {
    final srv = _FakeServer();
    await _pump(tester, srv, PostViewerPage(posts: [MapPost.fromJson(_postJson())]), size: const Size(480, 900));
    expect(find.byKey(const Key('post-reply-private')), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-reply-private')));
    await _settle(tester, 3);
    expect(find.byType(ChatThreadPage), findsOneWidget);
    final texts = tester.widgetList<TextField>(find.byType(TextField)).map((f) => f.controller?.text).toList();
    expect(texts, contains('#post/$_post '));
    expect(srv.calls, contains('POST /mapposts/$_post/contact'));
  });

  testWidgets('meet card gets «الاتجاهات» from the circle coordinates and opens Google Maps directions', (tester) async {
    final srv = _FakeServer()..messages.add(_msg('m2', 'SA0000002', '/meet 7م @brew92', const Duration(minutes: 3)));
    final opened = <Uri>[];
    LegalLinks.openOverride = (u) async => opened.add(u);
    addTearDown(() => LegalLinks.openOverride = null);
    await _pump(tester, srv, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    expect(find.byKey(const Key('card-req-meet')), findsOneWidget);
    expect(srv.calls, contains('GET /biz/biz-brew92'));
    expect(find.byKey(const Key('card-meet-directions')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card-meet-directions')));
    await tester.pump();
    expect(opened.single.host, 'www.google.com');
    expect(opened.single.queryParameters['destination'], '21.54,39.17');
  });
}

/// يعيد بناء الشاشة نفسها بمحتوى جديد مع إبقاء المزوّدات (didUpdateWidget لا initState).
Future<void> _pumpInto(WidgetTester tester, _FakeServer srv, Widget home) async {
  final scope = tester.widget<ProviderScope>(find.byType(ProviderScope));
  await tester.pumpWidget(ProviderScope(overrides: scope.overrides, child: MaterialApp(locale: const Locale('ar'), home: home)));
}
