// الإبلاغ والحظر على كل محتوى المستخدمين (قاعدة أبل 1.2): «حظر» في قائمة منشور الدائرة، الإبلاغ عن التعليقات وتصفية المخفي
// منها والمحظورين، أسئلة العرض وتقييماته، تقييمات الدائرة التجارية، شارة «محظور · إلغاء الحظر» في الملف، peerId في
// بيانات الدردشة، وطابور الإشراف وإعدادات الإدارة الجديدة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/chat_tools_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_reports.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/circles/circle_detail_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/market/listing_page.dart';
import 'package:naslook/pages/market/seller_tools.dart';
import 'package:naslook/pages/market/wanted_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

typedef _Route = Object? Function(http.Request req, Map<String, dynamic>? body);

/// خادم وهمي عام: مسارات صريحة، والباقي قائمة فارغة لطلبات GET و{ok} لغيرها.
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final routes = <String, _Route>{};
  final blocked = <Map<String, dynamic>>[];
  _Srv() {
    routes['GET /blocks'] = (_, __) => blocked;
    routes['POST /blocks'] = (_, b) {
      blocked.add({'blockedId': b!['blockedId'], 'nickname': 'x'});
      return {'ok': true};
    };
    routes['POST /safety/report'] = (_, __) => {'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3};
    routes['GET /notify/unread'] = (_, __) => {'unread': 0};
  }
  http.Response _json(Object? body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty && req.method != 'GET') {
      try {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies[key] = body;
      } catch (_) {}
    }
    final r = routes[key];
    if (r != null) return _json(r(req, body));
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return req.method == 'GET' ? _json([]) : _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(480, 1400)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return srv;
}

Future<void> _pickReasonAndSend(WidgetTester tester, {int reason = 0}) async {
  await tester.tap(find.byKey(Key('report-reason-$reason')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('report-submit')));
  await tester.pumpAndSettle();
}

// ---- الدوائر
const _v = '11111111-1111-1111-1111-111111111111';
final _now = DateTime.now().toUtc().toIso8601String();
Map<String, dynamic> _vpost(String id, String authorId, String nick, String text, {int comments = 0}) => {
      'id': id, 'vesselId': _v, 'vesselName': 'دائرة الحي', 'type': 'text', 'content': text, 'caption': '', 'kind': 'discussion',
      'author': {'id': authorId, 'nickname': nick}, 'createdAt': _now, 'supports': 0, 'comments': comments, 'supported': false, 'unread': false,
    };

_Srv _circleSrv() {
  final srv = _Srv();
  srv.routes['GET /vessels/$_v'] = (_, __) => {
        'id': _v, 'name': 'دائرة الحي', 'topic': 'الجيران', 'ownerId': 'SA0000009', 'isPublic': true, 'members': 5, 'role': 'member', 'joined': true,
        'postsPage': [_vpost('p-sara', 'SA0000002', 'sara', 'منشور سارة', comments: 3), _vpost('p-lina', 'SA0000006', 'lina', 'منشور لينا')],
      };
  srv.routes['GET /posts/hidden'] = (req, _) => req.url.queryParameters['kind'] == 'comment' ? {'kind': 'comment', 'ids': ['c-hidden']} : {'ids': []};
  srv.routes['GET /posts/p-sara/comments'] = (_, __) => [
        {'id': 'c-1', 'author': {'id': 'SA0000006', 'nickname': 'lina'}, 'text': 'تعليق لينا', 'createdAt': _now},
        {'id': 'c-hidden', 'author': {'id': 'SA0000007', 'nickname': 'noura'}, 'text': 'تعليق مخفي بالبلاغات', 'createdAt': _now},
        {'id': 'c-mine', 'author': {'id': 'SA0000001', 'nickname': 'amr'}, 'text': 'تعليقي', 'createdAt': _now},
      ];
  return srv;
}

// ---- السوق
const _lid = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> _listing() => {
      'id': _lid, 'seller': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'product', 'category': 'food', 'condition': 'new', 'delivery': true,
      'title': 'كيك عيد ميلاد', 'description': 'كيك فانيلا', 'price': 22000, 'images': [], 'status': 'active', 'variants': [], 'mine': false, 'createdAt': '2026-09-10T08:00:00Z',
    };

void main() {
  testWidgets('circle PostCard menu offers «حظر» for another member; blocking hides their posts', (tester) async {
    final srv = await _pump(tester, _circleSrv(), const CircleDetailPage(vesselId: _v));
    expect(find.text('منشور لينا'), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-menu-p-lina')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-report-p-lina')), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-block-p-lina')));
    await tester.pumpAndSettle();
    expect(find.text('حظر lina؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000006');
    expect(find.text('تم حظر lina'), findsOneWidget);
    expect(find.text('منشور لينا'), findsNothing, reason: 'منشورات المحظور تُصفّى في التطبيق');
    expect(find.text('منشور سارة'), findsOneWidget);
  });

  testWidgets('circle comments: hidden ids are filtered, others can be reported as vessel-comment, blocked authors disappear', (tester) async {
    final srv = await _pump(tester, _circleSrv(), const CircleDetailPage(vesselId: _v, focusPostId: 'p-sara'));
    expect(srv.calls, contains('GET /posts/hidden?kind=comment&post=p-sara'));
    expect(find.text('تعليق لينا'), findsOneWidget);
    expect(find.text('تعليق مخفي بالبلاغات'), findsNothing);
    expect(find.text('تعليقي'), findsOneWidget);
    expect(find.byKey(const Key('comment-c-mine-menu')), findsNothing, reason: 'لا إبلاغ عن تعليقي');
    await tester.tap(find.byKey(const Key('comment-c-1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comment-c-1-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-also-block')));
    await _pickReasonAndSend(tester, reason: 5);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'vessel-comment', 'targetId': 'c-1', 'reason': 'إزعاج أو سبام'});
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000006');
    expect(find.text('تعليق لينا'), findsNothing, reason: 'تعليقات المحظور تختفي');
  });

  testWidgets('long-press on a comment opens the report sheet directly', (tester) async {
    final srv = await _pump(tester, _circleSrv(), const CircleDetailPage(vesselId: _v, focusPostId: 'p-sara'));
    await tester.longPress(find.text('تعليق لينا'));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 2);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'vessel-comment', 'targetId': 'c-1', 'reason': 'محتوى جنسي'});
  });

  testWidgets('listing page: report a Q&A row and a review row, and block the seller from the menu', (tester) async {
    final srv = _Srv();
    srv.routes['GET /market/$_lid'] = (_, __) => _listing();
    srv.routes['GET /market/$_lid/questions'] = (_, __) => [
          {'id': 'q1', 'listingId': _lid, 'user': {'id': 'SA0000003', 'nickname': 'khalid'}, 'text': 'سؤال مسيء', 'createdAt': '2026-09-16T10:00:00Z'},
        ];
    srv.routes['GET /market/$_lid/reviews'] = (_, __) => [
          {'orderId': 'o-9', 'listingId': _lid, 'rating': 1, 'text': 'تقييم كاذب', 'buyer': {'id': 'SA0000004', 'nickname': 'fahad'}, 'createdAt': '2026-09-15T10:00:00Z'},
        ];
    await _pump(tester, srv, const ListingPage(_lid), size: const Size(600, 2400));
    expect(find.text('سؤال مسيء'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('question-q1-menu')));
    await tester.tap(find.byKey(const Key('question-q1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question-q1-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 0);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'listing-question', 'targetId': 'q1', 'reason': 'محتوى مسيء أو كراهية'});

    await tester.ensureVisible(find.byKey(const Key('review-o-9-menu')));
    await tester.tap(find.byKey(const Key('review-o-9-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-o-9-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 7);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'listing-review', 'targetId': 'o-9', 'reason': 'أخرى'});

    await tester.tap(find.byKey(const Key('listing-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('listing-report')), findsOneWidget);
    await tester.tap(find.byKey(const Key('listing-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000002');
  });

  testWidgets('business page: report a review as biz-review with id bizId:userId, and report the circle itself', (tester) async {
    final srv = _Srv();
    srv.routes['GET /biz/biz-kaia'] = (_, __) => {
          'id': 'biz-kaia', 'name': 'Kaia', 'nameAr': 'كايا', 'category': 'cafe', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2, 'highlights': [], 'followers': 3, 'rating': 2, 'ratingCount': 2,
          'following': false, 'offers': 0, 'myRole': null, 'ownerId': 'SA0000009', 'items': [], 'myOrders': [], 'posts': [],
          'reviews': [
            {'user': {'id': 'SA0000003', 'nickname': 'khalid'}, 'rating': 1, 'text': 'مراجعة مسيئة', 'createdAt': _now, 'mine': false},
            {'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'rating': 5, 'text': 'تقييمي', 'createdAt': _now, 'mine': true},
          ],
        };
    await _pump(tester, srv, const BusinessPage(id: 'biz-kaia'), size: const Size(600, 2600));
    expect(find.text('مراجعة مسيئة · الآن'), findsOneWidget);
    expect(find.byKey(const Key('bizreview-SA0000001-menu')), findsNothing, reason: 'لا إبلاغ عن تقييمي');
    await tester.ensureVisible(find.byKey(const Key('bizreview-SA0000003-menu')));
    await tester.tap(find.byKey(const Key('bizreview-SA0000003-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bizreview-SA0000003-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 1);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'biz-review', 'targetId': 'biz-kaia:SA0000003', 'reason': 'تحرش أو تنمر'});

    await tester.tap(find.byKey(const Key('biz-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('biz-block')), findsNothing, reason: 'الدائرة نفسها بلاغ فقط');
    await tester.tap(find.byKey(const Key('biz-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 4);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'biz', 'targetId': 'biz-kaia', 'reason': 'احتيال أو نصب'});
  });

  testWidgets('wanted request and its replies can be reported; replies from blocked sellers are hidden', (tester) async {
    const wid = '33333333-3333-4333-8333-333333333333';
    final srv = _Srv()..blocked.add({'blockedId': 'SA0000005', 'nickname': 'spam'});
    srv.routes['GET /market/wanted/$wid'] = (_, __) => {
          'id': wid, 'title': 'أبحث عن مدرّس', 'description': '', 'category': 'services', 'status': 'open', 'user': {'id': 'SA0000003', 'nickname': 'khalid'}, 'mine': false, 'createdAt': _now,
          'replyList': [
            {'id': 'r-1', 'text': 'رد مزعج', 'seller': {'id': 'SA0000004', 'nickname': 'fahad'}, 'mine': false, 'createdAt': _now},
            {'id': 'r-2', 'text': 'رد من محظور', 'seller': {'id': 'SA0000005', 'nickname': 'spam'}, 'mine': false, 'createdAt': _now},
          ],
        };
    await _pump(tester, srv, const WantedDetailPage(wid));
    expect(find.text('رد مزعج'), findsOneWidget);
    expect(find.text('رد من محظور'), findsNothing);
    await tester.tap(find.byKey(const Key('wreply-r-1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wreply-r-1-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 5);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'wanted-reply', 'targetId': 'r-1', 'reason': 'إزعاج أو سبام'});
    await tester.tap(find.byKey(const Key('wanted-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wanted-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 4);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'wanted', 'targetId': wid, 'reason': 'احتيال أو نصب'});
  });

  testWidgets('event detail: report the event and block its host; seller page: report goes to user reports', (tester) async {
    const eid = '44444444-4444-4444-8444-444444444444';
    final srv = _Srv();
    srv.routes['GET /events/$eid'] = (_, __) => {'id': eid, 'title': 'فعالية مشبوهة', 'description': 'ادفع مقدماً', 'host': {'id': 'SA0000003', 'nickname': 'khalid'}, 'isHost': false, 'tiers': [], 'startsAt': _now};
    srv.routes['GET /market/sellers/SA0000002'] = (_, __) => {'seller': {'id': 'SA0000002', 'nickname': 'sara'}, 'stats': {}, 'mine': false, 'listings': [], 'reviews': []};
    srv.routes['POST /reports'] = (_, __) => {'ok': true};
    await _pump(tester, srv, const EventDetailPage(eventId: eid));
    await tester.tap(find.byKey(const Key('event-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-block')), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 4);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'event', 'targetId': eid, 'reason': 'احتيال أو نصب'});

    await _pump(tester, srv, const SellerPage('SA0000002'));
    await tester.tap(find.byKey(const Key('seller-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('seller-report')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, reason: 6);
    expect(srv.bodies['POST /reports']!['userId'], 'SA0000002');
    expect(srv.bodies['POST /reports']!['reason'], 'انتحال شخصية');
  });

  testWidgets('a blocked user profile shows «محظور · إلغاء الحظر» and unblocking removes it', (tester) async {
    final srv = _Srv()..blocked.add({'blockedId': 'SA0000002', 'nickname': 'sara'});
    srv.routes['GET /profiles/SA0000002'] = (_, __) => {'id': 'SA0000002', 'nickname': 'sara', 'bio': '', 'skills': [], 'hobbies': [], 'lookingFor': [], 'offerings': [], 'isPublic': true};
    srv.routes['DELETE /blocks/SA0000002'] = (_, __) {
      srv.blocked.clear();
      return {'ok': true};
    };
    await _pump(tester, srv, const UserProfilePage(person: Person(id: 'SA0000002', nickname: 'sara')));
    expect(find.byKey(const Key('blocked-banner')), findsOneWidget);
    expect(find.text('محظور'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-unblock')), findsOneWidget);
    expect(find.byKey(const Key('profile-block')), findsNothing);
    await tester.tapAt(const Offset(5, 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unblock-btn')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('DELETE /blocks/SA0000002'));
    expect(find.byKey(const Key('blocked-banner')), findsNothing);
    expect(find.text('أُلغي حظر sara'), findsOneWidget);
  });

  test('chat meta and reactions carry the peer id so the server can enforce blocks', () async {
    final srv = _Srv();
    srv.routes['POST /chat/react'] = (_, __) => {'reactions': []};
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
    await api.chatReact('m-1', '👍', peerId: 'SA0000002');
    await api.setMessageMeta('m-2', peerId: 'SA0000003', replyTo: 'm-1');
    expect(srv.bodies['POST /chat/react'], {'messageId': 'm-1', 'emoji': '👍', 'peerId': 'SA0000002'});
    expect(srv.bodies['POST /chat/meta'], {'messageId': 'm-2', 'peerId': 'SA0000003', 'replyTo': 'm-1'});
  });

  testWidgets('admin hide that changes nothing on a circle says so instead of claiming success', (tester) async {
    final srv = _Srv();
    const vid = 'bbbbbbbb-0000-4000-8000-000000000011';
    srv.routes['GET /adminapi/reports'] = (_, __) => {'available': true, 'items': []};
    srv.routes['GET /adminapi/moderation'] = (req, _) => {
          'status': 'open', 'open': 1, 'threshold': 3, 'actions': ['dismiss', 'hide', 'restore', 'suspend-owner'],
          'types': [{'id': 'vessel', 'name': 'دائرة'}],
          'items': [
            {'targetType': 'vessel', 'targetId': vid, 'typeName': 'دائرة', 'reports': 3, 'reasons': ['محتوى مسيء أو كراهية'], 'firstAt': _now, 'lastAt': _now,
              'owner': {'id': 'SA0000002', 'nickname': 'sara'}, 'title': 'دائرة مزعجة', 'text': '', 'mediaUrl': null, 'status': 'visible', 'hidden': false, 'action': null},
          ],
        };
    srv.routes['POST /adminapi/moderation/vessel/$vid'] = (_, b) => {'ok': true, 'action': 'hide', 'changed': false, 'status': 'visible', 'owner': 'SA0000002', 'hint': 'vessel-no-public-flag'};
    await _pump(tester, srv, const Scaffold(body: AdminReportsPage()), size: const Size(700, 1200));
    await tester.tap(find.byKey(const Key('reports-tab-content')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mod-hide-vessel-$vid')));
    await tester.pumpAndSettle();
    expect(find.textContaining('إيقاف الناشر'), findsWidgets);
    expect(find.text('أُخفي المحتوى'), findsNothing);
  });

  testWidgets('admin moderation tab lists grouped content reports and hides one with a note', (tester) async {
    final srv = _Srv();
    const pid = 'aaaaaaaa-0000-4000-8000-000000000077';
    var hidden = false;
    srv.routes['GET /adminapi/reports'] = (_, __) => {'available': true, 'items': []};
    srv.routes['GET /adminapi/moderation'] = (req, _) => {
          'status': req.url.queryParameters['status'], 'open': hidden ? 0 : 1, 'threshold': 3, 'actions': ['dismiss', 'hide', 'restore', 'suspend-owner'],
          'types': [{'id': 'post', 'name': 'منشور'}, {'id': 'listing', 'name': 'عرض'}],
          'items': [
            {
              'targetType': 'post', 'targetId': pid, 'typeName': 'منشور', 'reports': 2, 'reasons': ['احتيال أو نصب', 'إزعاج أو سبام'], 'firstAt': _now, 'lastAt': _now,
              'owner': {'id': 'SA0000002', 'nickname': 'sara'}, 'title': 'عرض مشبوه', 'text': 'حوّل لي الآن', 'mediaUrl': null,
              'status': hidden ? 'hidden' : 'visible', 'hidden': hidden,
              'action': hidden ? {'action': 'hide', 'note': 'احتيال واضح', 'by': {'id': 'SA0000001', 'nickname': 'amr'}, 'at': _now} : null,
            },
          ],
        };
    srv.routes['POST /adminapi/moderation/post/$pid'] = (_, b) {
      hidden = b!['action'] == 'hide';
      return {'ok': true, 'action': b['action'], 'changed': true, 'status': hidden ? 'hidden' : 'visible', 'owner': 'SA0000002'};
    };
    await _pump(tester, srv, const Scaffold(body: AdminReportsPage()), size: const Size(700, 1200));
    await tester.tap(find.byKey(const Key('reports-tab-content')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /adminapi/moderation?status=open'));
    expect(find.text('عرض مشبوه'), findsOneWidget);
    expect(find.text('احتيال أو نصب'), findsOneWidget);
    expect(find.text('2 مبلّغين'), findsOneWidget);
    expect(find.textContaining('sara'), findsOneWidget);
    final k = 'post-$pid';
    expect(find.byKey(Key('mod-restore-$k')), findsNothing);
    await tester.enterText(find.byKey(Key('mod-note-$k')), 'احتيال واضح');
    await tester.tap(find.byKey(Key('mod-hide-$k')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/moderation/post/$pid'], {'action': 'hide', 'note': 'احتيال واضح'});
    expect(find.byKey(Key('mod-hide-$k')), findsNothing);
    expect(find.byKey(Key('mod-restore-$k')), findsOneWidget);
    expect(find.byKey(Key('mod-last-$k')), findsOneWidget);
    // «الكل» يعيد الطلب بحالة all
    await tester.tap(find.byKey(const Key('mod-status-all')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /adminapi/moderation?status=all'));
  });

  testWidgets('admin moderation: suspending the owner asks for confirmation first', (tester) async {
    final srv = _Srv();
    srv.routes['GET /adminapi/reports'] = (_, __) => {'available': true, 'items': []};
    srv.routes['GET /adminapi/moderation'] = (_, __) => {
          'status': 'open', 'open': 1, 'threshold': 3, 'types': [],
          'items': [{'targetType': 'biz-review', 'targetId': 'biz-kaia:SA0000003', 'typeName': 'تقييم دائرة', 'reports': 1, 'reasons': [], 'owner': {'id': 'SA0000003', 'nickname': 'khalid'}, 'title': 'مراجعة', 'status': 'visible'}],
        };
    await _pump(tester, srv, const Scaffold(body: AdminReportsPage()), size: const Size(700, 1200));
    await tester.tap(find.byKey(const Key('reports-tab-content')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mod-suspend-biz-review-biz-kaia:SA0000003')));
    await tester.pumpAndSettle();
    expect(find.text('إيقاف khalid؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mod-suspend-confirm')));
    await tester.pumpAndSettle();
    // المعرّف المركّب يُرمَّز في المسار (يفكّه Fastify)
    expect(srv.bodies['POST /adminapi/moderation/biz-review/biz-kaia%3ASA0000003'], {'action': 'suspend-owner', 'note': ''});
  });

  testWidgets('admin settings save the support email, money switches and the default banned words switch', (tester) async {
    final srv = _Srv();
    srv.routes['GET /adminapi/settings'] = (_, __) => {'testTopup': false, 'maxTopup': 100000, 'announcement': '', 'maintenance': false, 'supportHandle': '', 'supportEmail': '', 'bannedWords': '', 'reportThreshold': 3,
          'transfersEnabled': true, 'chatPaymentsEnabled': true, 'bannedWordsDefault': true};
    srv.routes['POST /adminapi/settings'] = (_, b) => b;
    srv.routes['GET /adminapi/payments/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar'};
    await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()), size: const Size(600, 3000));
    await tester.enterText(find.byKey(const Key('set-support-email')), 'support@areebd.sa');
    await tester.tap(find.byKey(const Key('set-transfers')));
    await tester.tap(find.byKey(const Key('set-banned-default')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('set-save')));
    await tester.tap(find.byKey(const Key('set-save')));
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /adminapi/settings']!;
    expect(b['supportEmail'], 'support@areebd.sa');
    expect(b['transfersEnabled'], isFalse);
    expect(b['chatPaymentsEnabled'], isTrue);
    expect(b['bannedWordsDefault'], isFalse);
    expect(find.text('حُفظت الإعدادات'), findsOneWidget);
  });
}
