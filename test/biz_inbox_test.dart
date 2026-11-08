// رسائل الدوائر الخاصة (lib/pages/business/inbox/، server/biz_inbox.js): «راسل الدائرة» في الصفحة العامة (يخفى للفريق ولدائرة
// بلا مالك، والزائر يرى دعوة الدخول)، صفحة المحادثة للعميل (تنبيه «دائرة غير موثّقة»، صورة ومرجع طلب في أول رسالة، رد الدائرة
// باسمها، البلاغ بنوع biz-msg، الرسالة المخفية، سبب منع الإرسال) وللفريق (اسم الزميل الكاتب، الإسناد، الإغلاق، الرد)،
// شريحة «الدوائر» في قائمة المحادثات، تبويب «الرسائل» في لوحة الدائرة (الشارة، الفلاتر، الإسناد، المنع لدور hr)، ووجهات الإشعارات.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/inbox/biz_thread_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _As extends AppStateNotifier {
  _As(super.api, super.store, {bool guest = false}) {
    state = guest ? const AppState(status: AuthStatus.signedOut) : const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _now = DateTime.now().toUtc();
String _ago(int min) => _now.subtract(Duration(minutes: min)).toIso8601String();

Map<String, dynamic> _biz(String id, {String? owner = 'SA0000009', String? role, bool verified = false}) => {
      'id': id, 'name': 'Cafe $id', 'nameAr': 'مقهى الورد', 'category': 'cafe', 'sector': 'قهوة', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '24 ساعة',
      'verified': verified, 'followers': 3, 'items': [], 'reviews': [], 'myOrders': [], if (owner != null) 'ownerId': owner, if (role != null) 'myRole': role,
    };

const _circle = {'id': 'biz-cafe', 'name': 'مقهى الورد', 'logoUrl': null, 'category': 'cafe', 'verified': false, 'ownerId': 'SA0000009'};
const _order = {'kind': 'order', 'id': '11111111-1111-4111-8111-111111111111', 'title': 'قهوة مختصة', 'code': 'NAS-ORD1', 'status': 'confirmed', 'total': 1500};

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map>{};
  bool threadExists = false;
  String role = 'owner';
  String reason = '';
  bool hiddenMsg = false;
  /// المحادثة أطول من صفحة: الصفحة الأقدم رسالة في الميلي ثانية نفسها لأقدم رسالة محمّلة
  bool olderPage = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _thread({bool team = false, String status = 'open', Map? assignee}) => {
        'id': 't1', 'bizId': 'biz-cafe', 'status': status, 'lastAt': _ago(1), 'lastText': 'أهلاً بك', 'lastSide': 'team', 'createdAt': _ago(30), 'unread': team ? 0 : 1,
        if (team) 'customer': {'id': 'SA0000005', 'nickname': 'cust'} else 'biz': _circle,
        if (team && assignee != null) 'assignee': assignee,
      };
  List<Map<String, dynamic>> _msgs({bool team = false}) => [
        {'id': 'm1', 'threadId': 't1', 'side': 'customer', 'mine': !team, 'text': 'هل الطلب جاهز؟', 'photos': [], 'ref': _order, 'hidden': false, 'createdAt': _ago(20)},
        {'id': 'm2', 'threadId': 't1', 'side': 'team', 'mine': false, 'text': hiddenMsg ? '' : 'أهلاً بك، جاهز بعد ربع ساعة', 'photos': [], 'hidden': hiddenMsg, 'createdAt': _ago(1),
          if (team) 'sender': {'id': 'SA0000003', 'nickname': 'sara'}},
      ];

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add('$key${req.url.query.isNotEmpty ? '?${req.url.query}' : ''}');
    if (req.method != 'GET' && req.body.isNotEmpty && !path.startsWith('/chat/upload')) bodies[key] = jsonDecode(req.body) as Map;
    switch (key) {
      case 'GET /biz/biz-cafe':
        return _json(_biz('biz-cafe'));
      case 'GET /biz/biz-seed':
        return _json(_biz('biz-seed', owner: null));
      case 'GET /biz/biz-own':
        return _json(_biz('biz-own', owner: 'SA0000001', role: role, verified: true));
      case 'GET /biz/biz-cafe/thread':
        return _json({'biz': _circle, 'thread': threadExists ? _thread() : null, 'messages': threadExists ? _msgs() : [], 'hasMore': false, 'canSend': true, 'reason': null, 'orders': [_order]});
      case 'POST /biz/biz-cafe/thread':
        final b = jsonDecode(req.body) as Map;
        return _json({
          'thread': {..._thread(), 'lastSide': 'customer', 'lastText': b['text'], 'unread': 0},
          'message': {'id': 'm9', 'threadId': 't1', 'side': 'customer', 'mine': true, 'text': b['text'], 'photos': b['photos'], 'ref': b['ref'] == null ? null : _order, 'hidden': false, 'clientId': b['clientId'], 'createdAt': _now.toIso8601String()},
        });
      case 'POST /chat/upload':
        return _json({'url': '/chat/media/k9x1zz-abcdef0123456789abcdef01.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': 3});
      case 'GET /bizinbox/threads':
        return _json({'threads': threadExists ? [_thread()] : [], 'unread': threadExists ? 1 : 0});
      case 'GET /bizinbox/threads/t1':
        final team = role != 'customer';
        final older = olderPage && req.url.queryParameters.containsKey('before');
        return _json({
          'viewer': team ? 'team' : 'customer', 'role': team ? role : null, 'biz': _circle, 'thread': _thread(team: team), 'hasMore': olderPage && !older,
          'messages': older ? [{'id': 'm0', 'threadId': 't1', 'side': 'customer', 'mine': !team, 'text': 'رسالة أقدم في الميلي ثانية نفسها', 'photos': [], 'hidden': false, 'createdAt': _ago(20)}] : _msgs(team: team),
          'canSend': reason.isEmpty, 'reason': reason.isEmpty ? null : reason, 'orders': [_order],
          if (team) 'team': [{'id': 'SA0000001', 'nickname': 'amr', 'role': 'owner'}, {'id': 'SA0000003', 'nickname': 'sara', 'role': 'staff'}],
          if (team) 'canAssignOthers': role == 'owner' || role == 'manager',
        });
      case 'POST /bizinbox/threads/t1/read':
        return _json({'ok': true});
      case 'POST /bizinbox/threads/t1/messages':
        final b = jsonDecode(req.body) as Map;
        return _json({'thread': _thread(team: true), 'message': {'id': 'm10', 'threadId': 't1', 'side': 'team', 'mine': true, 'text': b['text'], 'photos': [], 'hidden': false, 'createdAt': _now.toIso8601String(), 'sender': {'id': 'SA0000001', 'nickname': 'amr'}}});
      case 'POST /bizinbox/threads/t1/assign':
        final to = (jsonDecode(req.body) as Map)['userId'];
        return _json({'thread': _thread(team: true, assignee: to == null ? null : {'id': to, 'nickname': to == 'SA0000003' ? 'sara' : 'amr'})});
      case 'POST /bizinbox/threads/t1/close':
        return _json({'thread': _thread(team: true, status: 'closed')});
      case 'GET /biz/biz-own/inbox':
        if (role == 'hr') return _json({'error': 'forbidden'}, 403);
        final f = req.url.queryParameters['filter'] ?? 'open';
        return _json({
          'filter': f, 'role': role, 'canAssignOthers': role == 'owner', 'counts': {'open': 1, 'closed': 0, 'mine': 0, 'unread': 1},
          'threads': f == 'mine' || f == 'closed' ? [] : [{..._thread(team: true), 'unread': 2, 'lastSide': 'customer', 'lastText': 'هل الطلب جاهز؟'}],
          'team': [{'id': 'SA0000001', 'nickname': 'amr', 'role': 'owner'}, {'id': 'SA0000003', 'nickname': 'sara', 'role': 'staff'}],
        });
      case 'GET /biz/biz-own/inbox/unread':
        if (role == 'hr') return _json({'error': 'forbidden'}, 403);
        return _json({'unread': 2, 'open': 1, 'mine': 0});
      case 'POST /safety/report':
        return _json({'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3});
      case 'GET /chats':
        return _json([{'id': 'SA0000002', 'nickname': 'sara', 'lastType': 'text', 'lastContent': 'هلا', 'lastAt': _ago(5), 'lastMine': false, 'unread': 0}]);
      case 'GET /requests':
      case 'GET /contacts':
      case 'GET /safety/mutes':
      case 'GET /blocks':
        return _json([]);
      case 'GET /jobs/inbox':
        return _json({'items': [], 'pending': 0});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv, bool guest = false, Duration? poll}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  BizThreadPage.pollEvery = poll;
  addTearDown(() => BizThreadPage.pollEvery = null);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  // مفتاح جديد لكل ضخ: حاوية Riverpod جديدة (التجاوز بـ overrideWith لا يتبدّل في الحاوية نفسها)
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _As(api, SessionStore(), guest: guest)),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  tearDown(() => pickImageOverride = null);

  testWidgets('«راسل الدائرة» opens the thread: unverified warning, first message with a photo and an order reference', (tester) async {
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'a.jpg');
    final srv = await _pump(tester, const BusinessPage(id: 'biz-cafe'));
    await tester.scrollUntilVisible(find.byKey(const Key('biz-message')), 200);
    expect(find.text('راسل الدائرة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('biz-message')));
    await tester.pumpAndSettle();
    expect(find.byType(BizThreadPage), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-unverified')), findsOneWidget);
    expect(find.textContaining('دائرة غير موثّقة'), findsWidgets);
    expect(find.byKey(const Key('biz-thread-empty')), findsOneWidget);
    expect(srv.calls, contains('GET /biz/biz-cafe/thread'));

    await tester.tap(find.byKey(const Key('biz-thread-photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('biz-thread-pending-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('biz-thread-ref')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('biz-ref-option-${_order['id']}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('biz-thread-ref-chip')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('biz-thread-input')), 'هل الطلب جاهز؟');
    await tester.tap(find.byKey(const Key('biz-thread-send')));
    await tester.pumpAndSettle();

    final body = srv.bodies['POST /biz/biz-cafe/thread']!;
    expect(body['text'], 'هل الطلب جاهز؟');
    expect(body['photos'], ['/chat/media/k9x1zz-abcdef0123456789abcdef01.jpg']);
    expect(body['ref'], {'kind': 'order', 'id': _order['id']});
    expect((body['clientId'] as String).length, greaterThanOrEqualTo(4));
    expect(find.byKey(const Key('biz-msg-m9')), findsOneWidget);
    expect(find.byKey(Key('biz-ref-${_order['id']}')), findsOneWidget);
    expect(find.text('NAS-ORD1 · مؤكد · 15 ر.س'), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-empty')), findsNothing);
    // أُفرغ المؤلّف بعد الإرسال
    expect(find.byKey(const Key('biz-thread-ref-chip')), findsNothing);
    expect(find.byKey(const Key('biz-thread-pending-0')), findsNothing);
  });

  testWidgets('the button is hidden for the circle team and for a circle without an owner; a guest gets the sign-in prompt', (tester) async {
    await _pump(tester, const BusinessPage(id: 'biz-own'));
    expect(find.byKey(const Key('biz-message')), findsNothing);
    await _pump(tester, const BusinessPage(id: 'biz-seed'));
    expect(find.byKey(const Key('biz-message')), findsNothing);
    final srv = await _pump(tester, const BusinessPage(id: 'biz-cafe'), guest: true);
    await tester.scrollUntilVisible(find.byKey(const Key('biz-message')), 200);
    await tester.tap(find.byKey(const Key('biz-message')));
    await tester.pumpAndSettle();
    expect(find.text('هذا يحتاج حساباً'), findsOneWidget);
    expect(find.byType(BizThreadPage), findsNothing);
    expect(srv.calls.where((c) => c.contains('/thread')), isEmpty);
  });

  testWidgets('customer thread: the reply shows under the circle name, long-press reports it as biz-msg, read is marked', (tester) async {
    final srv = _Srv()..role = 'customer';
    await _pump(tester, const BizThreadPage(threadId: 't1'), srv: srv);
    expect(find.text('أهلاً بك، جاهز بعد ربع ساعة'), findsOneWidget);
    expect(find.text('مقهى الورد'), findsWidgets);
    expect(find.textContaining('كتبها'), findsNothing); // العميل لا يرى من كتب من الفريق
    expect(srv.calls, contains('POST /bizinbox/threads/t1/read'));
    await tester.longPress(find.byKey(const Key('biz-msg-m2')));
    await tester.pumpAndSettle();
    expect(find.text('إبلاغ عن رسالة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-reason-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /safety/report'], {'targetType': 'biz-msg', 'targetId': 'm2', 'reason': 'تحرش أو تنمر'});
  });

  testWidgets('customer thread: a hidden message keeps its place and a blocked reason replaces the composer', (tester) async {
    final srv = _Srv()
      ..role = 'customer'
      ..hiddenMsg = true
      ..reason = 'blocked';
    await _pump(tester, const BizThreadPage(threadId: 't1'), srv: srv);
    expect(find.byKey(const Key('biz-msg-hidden-m2')), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-reason')), findsOneWidget);
    expect(find.text('لا يمكن المراسلة بسبب الحظر.'), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-input')), findsNothing);
  });

  testWidgets('older messages page by message id and survive the poll even in the same millisecond', (tester) async {
    final srv = _Srv()
      ..role = 'customer'
      ..olderPage = true;
    await _pump(tester, const BizThreadPage(threadId: 't1'), srv: srv, poll: const Duration(seconds: 15));
    await tester.tap(find.byKey(const Key('biz-thread-older')));
    await tester.pumpAndSettle();
    // المؤشر معرّف أقدم رسالة محمّلة لا وقتها (الوقت في JSON مقطوع إلى الميلي ثانية)
    expect(srv.calls, contains('GET /bizinbox/threads/t1?before=m1'));
    expect(find.byKey(const Key('biz-msg-m0')), findsOneWidget);
    srv.calls.clear();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /bizinbox/threads/t1'));
    // m0 في الميلي ثانية نفسها لأقدم رسالة في آخر صفحة: الجلب الدوري لا يسقطها
    expect(find.byKey(const Key('biz-msg-m0')), findsOneWidget);
    expect(find.byKey(const Key('biz-msg-m1')), findsOneWidget);
  });

  testWidgets('team thread: teammate label, assign sheet, close and reply as the circle', (tester) async {
    final srv = await _pump(tester, const BizThreadPage(threadId: 't1'));
    expect(find.text('cust'), findsOneWidget);
    expect(find.text('كتبها sara'), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-unverified')), findsNothing); // التنبيه للعميل فقط
    await tester.tap(find.byKey(const Key('biz-thread-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('biz-thread-assign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-SA0000003')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /bizinbox/threads/t1/assign'], {'userId': 'SA0000003'});
    expect(find.byKey(const Key('biz-thread-assignee')), findsOneWidget);
    await tester.tap(find.byKey(const Key('biz-thread-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('biz-thread-close')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /bizinbox/threads/t1/close'));
    expect(find.byKey(const Key('biz-thread-closed')), findsOneWidget);
    // التنبيه السفلي يغطي المؤلّف حتى يختفي
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('biz-thread-input')), 'جاهز الآن');
    await tester.tap(find.byKey(const Key('biz-thread-send')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /bizinbox/threads/t1/messages']?['text'], 'جاهز الآن');
    expect(find.byKey(const Key('biz-msg-m10')), findsOneWidget);
  });

  testWidgets('chats list: «الدوائر» chip with the unread count opens circle threads; hidden without threads', (tester) async {
    await _pump(tester, const Scaffold(body: ChatsPage()));
    expect(find.byKey(const Key('chat-chip-biz')), findsNothing);
    expect(find.byKey(const Key('chat-row-SA0000002')), findsOneWidget);

    final srv = _Srv()..threadExists = true;
    await _pump(tester, const Scaffold(body: ChatsPage()), srv: srv);
    expect(find.text('الدوائر · 1'), findsOneWidget);
    expect(find.byKey(const Key('chat-row-SA0000002')), findsOneWidget); // قائمة المحادثات كما هي
    await tester.tap(find.byKey(const Key('chat-chip-biz')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('biz-thread-row-t1')), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-unverified-t1')), findsOneWidget);
    expect(find.byKey(const Key('biz-thread-unread-t1')), findsOneWidget);
    expect(find.text('مقهى الورد'), findsOneWidget);
    expect(find.byKey(const Key('chat-row-SA0000002')), findsNothing);
  });

  testWidgets('dashboard «الرسائل» tab: unread badge, filters and assignment from the row', (tester) async {
    final srv = await _pump(tester, const BusinessDashboardPage(id: 'biz-own', initialTab: BusinessDashboardPage.inboxTab));
    expect(find.byKey(const Key('inbox-tab-badge')), findsOneWidget);
    expect(find.byKey(const Key('inbox-row-t1')), findsOneWidget);
    expect(find.byKey(const Key('inbox-unread-t1')), findsOneWidget);
    expect(find.text('مفتوحة · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-assign-t1-SA0000003')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /bizinbox/threads/t1/assign'], {'userId': 'SA0000003'});
    await tester.tap(find.byKey(const Key('inbox-filter-mine')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /biz/biz-own/inbox?filter=mine'));
    expect(find.text('لا محادثات مسندة إليك'), findsOneWidget);
  });

  testWidgets('dashboard «الرسائل» tab is closed to the hr role', (tester) async {
    final srv = _Srv()..role = 'hr';
    await _pump(tester, const BusinessDashboardPage(id: 'biz-own', initialTab: BusinessDashboardPage.inboxTab), srv: srv);
    expect(find.byKey(const Key('inbox-forbidden')), findsOneWidget);
    expect(find.byKey(const Key('inbox-tab-badge')), findsNothing);
  });

  test('notifications open the thread', () {
    final msg = notificationTarget(const AppNotification(id: 'n1', kind: 'biz_inbox_message', title: 't', data: {'bizId': 'biz-own', 'threadId': 't1', 'manage': true}));
    expect(msg, isA<BizThreadPage>());
    expect((msg as BizThreadPage).threadId, 't1');
    expect((notificationTarget(const AppNotification(id: 'n2', kind: 'biz_inbox_reply', title: 't', data: {'bizId': 'biz-cafe', 'threadId': 't1'})) as BizThreadPage).threadId, 't1');
    expect((notificationTarget(const AppNotification(id: 'n3', kind: 'biz_inbox_assigned', title: 't', data: {'bizId': 'biz-own', 'threadId': 't1'})) as BizThreadPage).threadId, 't1');
    final noThread = notificationTarget(const AppNotification(id: 'n4', kind: 'biz_inbox_message', title: 't', data: {'bizId': 'biz-own'}));
    expect(noThread, isA<BusinessDashboardPage>());
    expect((noThread as BusinessDashboardPage).initialTab, BusinessDashboardPage.inboxTab);
    final hidden = notificationTarget(const AppNotification(id: 'n5', kind: 'content_hidden', title: 't', data: {'targetType': 'biz-msg', 'targetId': 'm2', 'threadId': 't1', 'bizId': 'biz-cafe'}));
    expect((hidden as BizThreadPage).threadId, 't1');
    expect(notificationStyle('biz_inbox_message').icon, Icons.forum_outlined);
  });
}
