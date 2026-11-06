// الإشعارات (البند 6 في docs/reports/naslife_gaps_2026-11-05.md):
//  - ستة أنواع كانت لا تفتح شيئاً لها وجهاتها الآن (حجز الفندق، المتابعة، قبول الموعد، الإعجاب، إخفاء مشرف الدائرة، إعادة الإظهار)،
//    ومعها أنواع أخرى بلا وجهة (الإخفاء العام، بلاغات كثيرة، ملاحظات البريد الوارد، استرداد حساب محذوف). والمجهول لا يفتح شيئاً.
//  - نقرة إشعار والتطبيق مفتوح: رابط #/n/<id> من عامل الخدمة يُحلَّل ويُبث مرة واحدة (بلا تكرار للرسالة وتغيّر الجزء معاً)،
//    وHomeShell الظاهر يفتح وجهته فوراً.
//  - خطّاف الخروج من خدمة الإشعارات يُسجَّل مرة واحدة ولا يعطّل الخروج.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/push/push_service.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/community_page.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/circles/circle_detail_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/market/wanted_page.dart';
import 'package:naslook/pages/posts/moment_actions.dart';
import 'package:naslook/pages/posts/my_posts_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

const _nid = '0d6f3c1e-1111-4222-8333-444455556666';
const _post = '11111111-2222-4333-8444-555555555555';
const _vessel = '22222222-3333-4444-8555-666666666666';

AppNotification _n(String kind, [Map<String, dynamic> data = const {}, String title = '']) => AppNotification(id: 'n-$kind', kind: kind, title: title.isEmpty ? kind : title, data: data);

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /notify/$_nid':
        return _json({'id': _nid, 'kind': 'hotel_booked', 'title': 'تم حجزك في فندق البحر', 'body': '', 'data': {'bookingId': 'b1', 'bizId': 'biz-sea'}, 'readAt': null, 'createdAt': '2026-11-05T10:00:00Z'});
      case 'GET /legal/consent':
        return _json({'needs': false});
      case 'GET /notify/unread':
        return _json({'unread': 1});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false});
      case 'GET /row':
        return _json({'items': [], 'located': false});
      case 'GET /feed':
        return _json({'items': [], 'next': null, 'located': false});
      case 'GET /live/wait':
        return _json({'seq': 0, 'events': [], 'reset': false});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

void main() {
  group('notification destinations', () {
    test('the six kinds that opened nothing now open their screen', () {
      expect(notificationTarget(_n('hotel_booked', {'bookingId': 'b1', 'bizId': 'biz-sea'})), isA<MyBookingsPage>());
      final follow = notificationTarget(_n('profile_follow', {'userId': 'SA0000002', 'nickname': 'sara'}));
      expect(follow, isA<UserProfilePage>());
      expect((follow as UserProfilePage).person.id, 'SA0000002');
      expect(follow.person.nickname, 'sara');
      final meet = notificationTarget(_n('meet_accepted', {'peerId': 'SA0000003', 'peerNickname': 'khalid', 'messageId': 'm-9'}));
      expect(meet, isA<ChatThreadPage>());
      expect((meet as ChatThreadPage).peer.id, 'SA0000003');
      expect(meet.peer.nickname, 'khalid');
      expect(meet.initialMessageId, 'm-9', reason: 'تقفز المحادثة إلى بطاقة الموعد');
      final like = notificationTarget(_n('post_like', {'postId': _post}));
      expect(like, isA<MomentLinkPage>());
      expect((like as MomentLinkPage).id, _post);
      final hidden = notificationTarget(_n('vessel_post_hidden', {'vesselId': _vessel, 'postId': _post, 'reason': 'moderation'}));
      expect(hidden, isA<CircleDetailPage>());
      expect((hidden as CircleDetailPage).vesselId, _vessel);
      final restored = notificationTarget(_n('content_restored', {'targetType': 'post', 'targetId': _post, 'postId': _post, 'reason': 'moderation'}));
      expect(restored, isA<MomentLinkPage>());
      expect((restored as MomentLinkPage).id, _post);
    });

    test('older payloads without the new names still open (name from the title, or the id)', () {
      final follow = notificationTarget(_n('profile_follow', {'userId': 'SA0000002'}, 'sara يتابعك')) as UserProfilePage;
      expect(follow.person.nickname, 'sara');
      final meet = notificationTarget(_n('meet_accepted', {'peerId': 'SA0000003', 'messageId': 'm-9'})) as ChatThreadPage;
      expect(meet.peer.nickname, 'SA0000003');
      expect(notificationTarget(_n('post_like')), isA<MyPostsPage>());
      expect(notificationTarget(_n('vessel_post_hidden')), isNull);
    });

    test('content restored (or hidden) opens the item or its place by target type', () {
      Widget? t(String type, Map<String, dynamic> extra, [String kind = 'content_restored']) => notificationTarget(_n(kind, {'targetType': type, 'targetId': 'x-1', ...extra}));
      expect(t('listing', {'listingId': 'L1'}), isA<ListingPage>());
      expect(t('listing-review', {'listingId': 'L1'}), isA<ListingPage>());
      final c = t('community', {'bizId': 'biz-1', 'postId': 'cp-1'}) as CommunityPage;
      expect(c.bizId, 'biz-1');
      expect(c.initialPostId, 'cp-1');
      expect((t('community-reply', {'bizId': 'biz-1', 'parentId': 'cp-2'}) as CommunityPage).initialPostId, 'cp-2');
      final v = t('vessel-post', {'vesselId': _vessel, 'postId': _post}) as CircleDetailPage;
      expect(v.vesselId, _vessel);
      expect(v.focusPostId, _post);
      expect((t('vessel', {}) as CircleDetailPage).vesselId, 'x-1');
      expect(t('wanted', {}), isA<WantedDetailPage>());
      expect(t('wanted-reply', {'wantedId': 'w-1'}), isA<WantedDetailPage>());
      expect((t('biz', {}) as BusinessPage).id, 'x-1');
      expect((t('biz-review', {'bizId': 'biz-2'}) as BusinessPage).id, 'biz-2');
      expect((t('event', {}) as EventDetailPage).eventId, 'x-1');
      expect(t('biz-post', {'bizId': 'biz-3'}, 'content_hidden'), isA<BusinessPage>(), reason: 'الإخفاء العام لنوع بلا إشعار خاص يفتح موضعه');
      expect(t('nonsense', {}), isNull);
    });

    test('other kinds that opened nothing: admin queues for reports, inbox notes and refunds', () {
      for (final k in ['content_reported_many', 'inbox_note', 'inbox_send_failed', 'inbox_unsnoozed', 'account_refund']) {
        expect(notificationTarget(_n(k)), isA<AdminShell>(), reason: k);
      }
      // الإخفاء التلقائي وبلاغات المحتوى الجديدة: قسم البلاغات (كان content_autohidden يفتح المالية بفهرس قديم)
      final reports = adminSections.indexWhere((s) => s.$1 == 'reports');
      for (final k in ['content_autohidden', 'content_reports_new', 'content_reported_many']) {
        expect((notificationTarget(_n(k)) as AdminShell).initialSection, reports, reason: k);
      }
      expect(notificationTarget(_n('test')), isNull, reason: 'الإشعار التجريبي لا وجهة له');
      expect(notificationTarget(_n('something_new')), isNull);
    });
  });

  group('push click while the app is open', () {
    setUp(PushService.resetOpensForTest);

    test('a notification link is parsed once; other links are not ours', () async {
      final got = <String>[];
      final sub = PushService.openRequests.listen(got.add);
      expect(PushService.handleOpenUrl('https://naslife.app/#/n/$_nid'), isTrue);
      // رسالة عامل الخدمة وتغيّر الجزء للنقرة نفسها: بث واحد
      expect(PushService.handleOpenUrl('https://naslife.app/?open=1#/n/$_nid'), isTrue);
      expect(PushService.handleOpenUrl('https://naslife.app/#/'), isFalse);
      expect(PushService.handleOpenUrl('https://naslife.app/#/n/not-a-uuid'), isFalse);
      expect(PushService.handleOpenUrl('https://naslife.app/#/m/$_post'), isFalse);
      expect(PushService.handleOpenUrl('#/n/$_post'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(got, [_nid, _post]);
      await sub.cancel();
    });

    testWidgets('the visible shell opens the target right away and marks it read', (tester) async {
      SharedPreferences.setMockInitialValues({});
      DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
      addTearDown(() => DeviceLocation.override = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = _Srv();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          socketProvider.overrideWithValue(null),
          appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
          notifyPollIntervalProvider.overrideWithValue(null),
          marketPosProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: AuthGate()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(MyBookingsPage), findsNothing);
      expect(PushService.handleOpenUrl('https://naslife.app/#/n/$_nid'), isTrue);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(s.calls, contains('GET /notify/$_nid'));
      expect(s.calls, contains('POST /notify/read'));
      expect(find.byType(MyBookingsPage), findsOneWidget);
      expect(pendingNotificationId, isNull, reason: 'فُتح مرة واحدة ولا يعود عند إقلاع لاحق');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('sign-out hook', () {
    tearDown(PushService.resetForTest);
    const endpoint = 'https://push.example/ep-1';
    ({ApiClient api, List<String> calls, List<Map<String, dynamic>> bodies, List<String?> tokens}) server() {
      final calls = <String>[], tokens = <String?>[];
      final bodies = <Map<String, dynamic>>[];
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        tokens.add(req.headers['x-token']);
        bodies.add(req.body.isEmpty ? const {} : Map<String, dynamic>.from(jsonDecode(req.body) as Map));
        return http.Response(jsonEncode({'ok': true, 'stopped': 0}), 200, headers: {'content-type': 'application/json'});
      }))..token = 'tok';
      return (api: api, calls: calls, bodies: bodies, tokens: tokens);
    }

    test('logout unsubscribes this browser and deletes the subscription on the server before the token is cleared', () async {
      SharedPreferences.setMockInitialValues({PushService.ownerKey: 'SA0000001'});
      final s = server();
      var dropped = 0;
      PushService.subscriptionOverride = () async => {'endpoint': endpoint, 'keys': {'p256dh': 'k', 'auth': 'a'}};
      PushService.dropLocalOverride = () async { dropped++; return (endpoint: endpoint, dropped: true); };
      await PushService.resubscribeIfGranted(s.api, userId: 'SA0000001');
      final n = _SignedIn(s.api, SessionStore());
      await n.logout().timeout(const Duration(seconds: 5));
      expect(dropped, 1, reason: 'الإلغاء المحلي هو الضمان: خدمة الدفع ترد 410 بعده');
      final del = s.calls.indexOf('DELETE /push/subscribe');
      expect(del, greaterThanOrEqualTo(0));
      expect(s.bodies[del]['endpoint'], endpoint);
      expect(s.tokens[del], 'tok', reason: 'يُحذف برمز الجلسة قبل مسحه');
      expect(del, lessThan(s.calls.indexOf('POST /logout')));
      expect(n.state.status, AuthStatus.signedOut);
      expect((await SharedPreferences.getInstance()).getString(PushService.ownerKey), isNull);
    });

    test('a subscription left by another account (its session expired, no logout) is dropped, not moved to the new account', () async {
      SharedPreferences.setMockInitialValues({PushService.ownerKey: 'SA0000009'});
      final s = server();
      var dropped = 0;
      PushService.subscriptionOverride = () async => {'endpoint': endpoint};
      PushService.dropLocalOverride = () async { dropped++; return (endpoint: endpoint, dropped: true); };
      await PushService.resubscribeIfGranted(s.api, userId: 'SA0000001');
      expect(dropped, 1);
      expect(s.calls, isNot(contains('POST /push/subscribe')), reason: 'لا يُنسب اشتراك الحساب السابق إلى الحساب الداخل');
      expect((await SharedPreferences.getInstance()).getString(PushService.ownerKey), isNull);
    });

    test('the same account (or a subscription saved before owners were kept) is re-sent and recorded', () async {
      SharedPreferences.setMockInitialValues({});
      final s = server();
      var dropped = 0;
      PushService.subscriptionOverride = () async => {'endpoint': endpoint};
      PushService.dropLocalOverride = () async { dropped++; return (endpoint: endpoint, dropped: true); };
      await PushService.resubscribeIfGranted(s.api, userId: 'SA0000001');
      expect(s.calls, contains('POST /push/subscribe'));
      expect((await SharedPreferences.getInstance()).getString(PushService.ownerKey), 'SA0000001');
      await PushService.resubscribeIfGranted(s.api, userId: 'SA0000001');
      expect(s.calls.where((c) => c == 'POST /push/subscribe').length, 2);
      expect(dropped, 0);
    });

    test('a failed local unsubscribe keeps the owner so the next sign-in still catches it', () async {
      SharedPreferences.setMockInitialValues({PushService.ownerKey: 'SA0000001'});
      final s = server();
      PushService.subscriptionOverride = () async => {'endpoint': endpoint};
      PushService.dropLocalOverride = () async => (endpoint: endpoint, dropped: false);
      await PushService.resubscribeIfGranted(s.api, userId: 'SA0000001');
      await _SignedIn(s.api, SessionStore()).logout().timeout(const Duration(seconds: 5));
      expect(s.calls, contains('DELETE /push/subscribe'), reason: 'الحذف من الخادم أهم حين يتعذر الإلغاء المحلي');
      expect((await SharedPreferences.getInstance()).getString(PushService.ownerKey), 'SA0000001');
    });

    test('the push service registers one sign-out hook, and logout still completes', () async {
      final before = AppStateNotifier.signOutHooks.length;
      final calls = <String>[];
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode({'ok': true, 'stopped': 0}), 200, headers: {'content-type': 'application/json'});
      }))..token = 'tok';
      await PushService.resubscribeIfGranted(api);
      await PushService.resubscribeIfGranted(api);
      final after = AppStateNotifier.signOutHooks.length;
      expect(after - before, lessThanOrEqualTo(1), reason: 'المجموعة تمنع التكرار');
      expect(after, greaterThanOrEqualTo(1));
      final n = _SignedIn(api, SessionStore());
      SharedPreferences.setMockInitialValues({});
      await n.logout().timeout(const Duration(seconds: 5));
      expect(n.state.status, AuthStatus.signedOut);
      expect(calls.last, 'POST /logout');
      expect(api.token, isNull);
    });
  });
}
