// «أتابعهم» (7 نوفمبر 2026): رقاقة «أتابعهم» بعد «عام» في «اللحظات» تجلب /feed?scope=following وتظهر للحساب المسجّل وحده، نص الفراغ يدعو
// إلى المتابعة والانضمام بحسب العدّاد، واللحظة الحيّة ممن أتابعهم تُدرج في قائمتها (ومن غيرهم لا)؛ قائمتا «متابِعون» و«يتابع» بتبويبين
// وصفحات بالمؤشر وزر متابعة لكل شخص و«القائمة خاصة» و«لا متابِعين بعد»؛ رقما الملف يفتحان القائمتين؛ مفتاح «إشعارات من أتابعهم» في
// «التوثيق والتحكم»؛ وإشعار follow_moment يفتح اللحظة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/row_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/video_view.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/posts/moment_actions.dart';
import 'package:naslook/pages/posts/timeline_page.dart';
import 'package:naslook/pages/profile/follow_list_page.dart';
import 'package:naslook/pages/profile/privacy_control_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Guest extends AppStateNotifier {
  _Guest(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

String _pid(int i) => 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}';

Map<String, dynamic> _post(int i, {String user = 'SA0000002', String caption = '', Duration ago = const Duration(minutes: 2)}) => {
      'id': _pid(i), 'user': {'id': user, 'nickname': 'user$i'}, 'kind': 'text', 'caption': caption, 'mediaUrl': null, 'overlays': [], 'tag': 'moment', 'bg': '#0A6E78',
      'lat': 26.43, 'lng': 50.1, 'status': 'active', 'views': 0, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().subtract(ago).toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
    };

Map<String, dynamic> _moment(Map<String, dynamic> p) => {
      'kind': 'moment', 'id': p['id'], 'refId': p['id'], 'title': p['caption'], 'subtitle': 'الآن', 'who': (p['user'] as Map)['nickname'], 'logoUrl': null, 'imageUrl': null,
      'lat': p['lat'], 'lng': p['lng'], 'distanceKm': 1100.0, 'at': p['createdAt'], 'feedAt': p['createdAt'], 'endsAt': p['expiresAt'], 'act': 'شاهد', 'payload': p,
    };

Map<String, dynamic> _person(String id, String nick, {bool following = false, bool me = false}) => {'id': id, 'nickname': nick, 'displayName': '', 'avatarUrl': null, 'isFollowing': following, 'isMe': me};

class _Srv {
  final calls = <String>[];
  final feeds = <Map<String, String>>[];
  final bodies = <String, Map<String, dynamic>>{};
  /// بطاقات «عام» و«أتابعهم»
  List<Map<String, dynamic>> all = [], following = [];
  int people = 0, circles = 0;
  List<String> ids = const [];
  final live = <Map<String, dynamic>>[];
  int liveSeq = 0;
  /// القائمتان: الصفحة الأولى ثم الثانية بالمؤشر
  List<Map<String, dynamic>> followersPage1 = [], followersPage2 = [], followingList = [];
  bool listsPrivate = false;
  Map<String, dynamic> settings = {'msgPolicy': 'all', 'showOnline': true, 'showCity': true, 'showFriends': false, 'introVisibility': 'all', 'followNotify': true};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _profile() => {
        'id': 'SA0000002', 'nickname': 'sara', 'displayName': 'سارة', 'avatarUrl': null, 'coverUrl': null, 'bio': '', 'accountType': 'personal', 'jobTitle': '', 'city': '', 'district': '', 'links': [], 'intro': null,
        'stats': {'posts': 3, 'followers': 3, 'following': 17, 'circles': 1, 'ratingAvg': null, 'ratingCount': 0, 'completedOrders': 0, 'friends': 0},
        'trust': {'emailVerified': false, 'phoneVerified': false, 'memberSince': null, 'respondsFast': null},
        'flags': {'isMe': false, 'isFollowing': false, 'isFriend': false, 'canMessage': true, 'online': false, 'isPrivate': false, 'blocked': false},
      };
  Map<String, dynamic> _mine() => {
        'id': 'SA0000001', 'nickname': 'amr', 'displayName': '', 'avatarUrl': null, 'coverUrl': null, 'bio': '', 'links': [], 'intro': null, 'stats': {}, 'trust': {}, 'flags': {'isMe': true}, 'settings': settings,
        'completion': {'pct': 0, 'steps': []},
      };

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path, key = '${req.method} $path';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if (req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    final q = req.url.queryParameters;
    switch (key) {
      case 'GET /feed':
        feeds.add(q);
        if (q['scope'] == 'following') return _json({'items': following, 'next': null, 'located': true, 'scope': 'following', 'following': {'people': people, 'circles': circles}});
        return _json({'items': all, 'next': null, 'located': true});
      case 'GET /me/following/ids':
        return _json({'ids': ids});
      case 'GET /live/wait':
        if (!q.containsKey('after')) return _json({'seq': liveSeq, 'events': [], 'reset': false});
        final evs = [for (final e in live) {'seq': ++liveSeq, 'kind': e['kind'], 'at': DateTime.now().toUtc().toIso8601String(), 'data': e['data'] ?? {}}];
        live.clear();
        return _json({'seq': liveSeq, 'events': evs, 'reset': false});
      case 'GET /profiles/SA0000002/followers':
        if (listsPrivate) return _json({'error': 'private'}, 403);
        return q['before'] == null
            ? _json({'items': followersPage1, 'next': followersPage2.isEmpty ? null : '2026-11-01T10:00:00.000000Z~SA0000004', 'total': followersPage1.length + followersPage2.length})
            : _json({'items': followersPage2, 'next': null, 'total': followersPage1.length + followersPage2.length});
      case 'GET /profiles/SA0000002/following':
        if (listsPrivate) return _json({'error': 'private'}, 403);
        return _json({'items': followingList, 'next': null, 'total': followingList.length});
      case 'POST /profiles/SA0000004/follow':
        return _json({'ok': true, 'following': true, 'followers': 1});
      case 'DELETE /profiles/SA0000003/follow':
        return _json({'ok': true, 'following': false, 'followers': 0});
      case 'GET /profiles/SA0000002/v2':
        return _json(_profile());
      case 'GET /profiles/SA0000002':
        return _json({'id': 'SA0000002', 'nickname': 'sara', 'bio': '', 'skills': [], 'hobbies': [], 'lookingFor': [], 'offerings': [], 'isPublic': true});
      case 'GET /me/profile/v2':
        return _json(_mine());
      case 'PUT /me/profile/v2':
        settings = {...settings, ...?bodies[key]};
        return _json(_mine());
      case 'GET /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
      case 'GET /mapposts/feed':
        return _json({'items': [], 'nextCursor': null, 'located': false});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false});
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': false});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv, bool guest = false}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.54, 39.17);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = guest ? null : 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), notifyPollIntervalProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => guest ? _Guest(api, SessionStore()) : _SignedIn(api, SessionStore())),
    ],
    child: MaterialApp(locale: const Locale('ar'), builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!), home: home),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tapChip(WidgetTester tester, String kind) async {
  await tester.ensureVisible(find.byKey(Key('feed-kind-$kind')));
  await tester.pump();
  await tester.tap(find.byKey(Key('feed-kind-$kind')));
}

void main() {
  setUp(() => VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false, controls = true}) => const SizedBox(key: Key('fake-video')));
  tearDown(() {
    VideoView.factoryOverride = null;
    ApiClient.onUnauthorized = null;
  });

  group('«أتابعهم» في اللحظات', () {
    testWidgets('the chip sits right after «عام» and fetches scope=following (kind=all), showing far-away moments', (tester) async {
      final srv = _Srv()
        ..all = [_moment(_post(1, user: 'SA0000009', caption: 'لحظة عامة'))]
        ..following = [_moment(_post(2, caption: 'لحظة صديقتي في الدمام'))]
        ..people = 3;
      await _pump(tester, const TimelinePage(), srv: srv);
      final all = tester.getTopLeft(find.byKey(const Key('feed-kind-all'))), fol = tester.getTopLeft(find.byKey(const Key('feed-kind-following'))), mom = tester.getTopLeft(find.byKey(const Key('feed-kind-moment')));
      // العربية من اليمين: «عام» ثم «أتابعهم» ثم «لحظات»
      expect(all.dx, greaterThan(fol.dx));
      expect(fol.dx, greaterThan(mom.dx));
      expect(find.text('أتابعهم'), findsOneWidget);
      expect(srv.feeds.single['scope'], isNull, reason: '«عام» افتراضياً بلا نطاق');
      await _tapChip(tester, 'following');
      await _settle(tester);
      expect(srv.feeds.last['scope'], 'following');
      expect(srv.feeds.last['kind'], 'all');
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('feed-kind-following'))).selected, isTrue);
      expect(find.text('لحظة صديقتي في الدمام'), findsOneWidget);
      expect(find.text('لحظة عامة'), findsNothing);
      expect(srv.calls, contains('GET /me/following/ids'), reason: 'معرّفات من أتابعهم للإدراج الحيّ');
    });

    testWidgets('empty with nobody followed invites following people and joining circles', (tester) async {
      final srv = _Srv();
      await _pump(tester, const TimelinePage(), srv: srv);
      await _tapChip(tester, 'following');
      await _settle(tester);
      expect(find.byKey(const Key('tl-following-empty')), findsOneWidget);
      expect(find.text('لا أحد تتابعه بعد'), findsOneWidget);
      expect(find.textContaining('تابع أشخاصاً من ملفاتهم وانضم إلى دوائر'), findsOneWidget);
      expect(find.byKey(const Key('tl-follow-people')), findsOneWidget);
      expect(find.byKey(const Key('tl-follow-circles')), findsOneWidget);
    });

    testWidgets('empty while following people: «لا جديد ممن تتابعهم»', (tester) async {
      final srv = _Srv()
        ..people = 4
        ..circles = 1;
      await _pump(tester, const TimelinePage(), srv: srv);
      await _tapChip(tester, 'following');
      await _settle(tester);
      expect(find.text('لا جديد ممن تتابعهم'), findsOneWidget);
      expect(find.text('لا أحد تتابعه بعد'), findsNothing);
    });

    testWidgets('a guest sees no «أتابعهم» chip', (tester) async {
      await _pump(tester, const TimelinePage(), guest: true);
      expect(find.byKey(const Key('feed-kind-all')), findsOneWidget);
      expect(find.byKey(const Key('feed-kind-following')), findsNothing);
    });

    testWidgets('a live moment from someone I follow is inserted into «أتابعهم» (whatever the distance); a stranger\'s is not', (tester) async {
      final srv = _Srv()
        ..following = [_moment(_post(1, caption: 'قديمة', ago: const Duration(hours: 1)))]
        ..people = 1
        ..ids = ['SA0000002'];
      await _pump(tester, const TimelinePage(), srv: srv);
      await _tapChip(tester, 'following');
      await _settle(tester);
      final fetches = srv.feeds.length;
      srv.live.add({'kind': 'post', 'data': _post(7, caption: 'من أتابعها الآن')});
      srv.live.add({'kind': 'post', 'data': _post(8, user: 'SA0000009', caption: 'من غريب')});
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('من أتابعها الآن'), findsOneWidget);
      expect(find.text('من غريب'), findsNothing);
      expect(srv.feeds.length, fetches, reason: 'الحمولة تأتي مع الحدث فلا جلب');
    });

    testWidgets('a contact change refetches the ids: a new friend\'s live moment is inserted, a removed friend\'s is not and their card leaves in place', (tester) async {
      final srv = _Srv()
        ..following = [_moment(_post(1, user: 'SA0000003', caption: 'من صديق قديم', ago: const Duration(hours: 1)))]
        ..people = 1
        ..ids = ['SA0000003'];
      await _pump(tester, const TimelinePage(), srv: srv);
      await _tapChip(tester, 'following');
      await _settle(tester);
      expect(find.text('من صديق قديم'), findsOneWidget);
      int idsCalls() => srv.calls.where((c) => c == 'GET /me/following/ids').length;
      expect(idsCalls(), 1, reason: 'أول وصول لجهات الاتصال والمحظورين لا يعيد الجلب');
      expect(srv.feeds.length, 2, reason: 'ولا يحدّث القائمة: «عام» ثم «أتابعهم» فقط');
      // قبلتُ طلب سارة وأزلتُ خالداً: كل مسار يضيف صديقاً أو يقبله أو يزيله يُبطل contactsProvider
      srv
        ..ids = ['SA0000002']
        ..following = [];
      ProviderScope.containerOf(tester.element(find.byType(TimelinePage))).invalidate(contactsProvider);
      await _settle(tester);
      expect(idsCalls(), 2);
      expect(find.text('من صديق قديم'), findsNothing, reason: 'البث خلا منه فتزول بطاقته في مكانها');
      srv.live.add({'kind': 'post', 'data': _post(7, caption: 'من صديقة جديدة')});
      srv.live.add({'kind': 'post', 'data': _post(8, user: 'SA0000003', caption: 'من صديق أُزيل')});
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('من صديقة جديدة'), findsOneWidget);
      expect(find.text('من صديق أُزيل'), findsNothing);
    });

    testWidgets('unfollowing the only person I follow empties «أتابعهم» in place and invites following again', (tester) async {
      final srv = _Srv()
        ..following = [_moment(_post(1, user: 'SA0000003', caption: 'لحظة خالد'))]
        ..people = 1
        ..ids = ['SA0000003']
        ..followersPage1 = [_person('SA0000003', 'khalid', following: true)];
      await _pump(tester, const TimelinePage(), srv: srv);
      await _tapChip(tester, 'following');
      await _settle(tester);
      expect(find.text('لحظة خالد'), findsOneWidget);
      srv
        ..following = []
        ..people = 0
        ..ids = [];
      Navigator.of(tester.element(find.byType(TimelinePage))).push(MaterialPageRoute<void>(builder: (_) => const FollowListPage(userId: 'SA0000002', name: 'سارة')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('follow-row-btn-SA0000003')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /profiles/SA0000003/follow'));
      Navigator.of(tester.element(find.byType(FollowListPage))).pop();
      await _settle(tester);
      expect(find.text('لحظة خالد'), findsNothing, reason: 'الصفحة الأولى الفارغة بلا مؤشر تعني أن البث خلا');
      expect(find.byKey(const Key('tl-following-empty')), findsOneWidget);
      expect(find.text('لا أحد تتابعه بعد'), findsOneWidget);
    });
  });

  group('قائمتا «متابِعون» و«يتابع»', () {
    testWidgets('pages with the cursor, opens on the chosen tab, and follows from the row', (tester) async {
      final srv = _Srv()
        ..followersPage1 = [_person('SA0000003', 'khalid', following: true), _person('SA0000001', 'amr', me: true)]
        ..followersPage2 = [_person('SA0000004', 'nora')]
        ..followingList = [_person('SA0000005', 'lina')];
      await _pump(tester, const FollowListPage(userId: 'SA0000002', name: 'سارة'), srv: srv);
      expect(find.text('سارة'), findsOneWidget);
      expect(find.byKey(const Key('follow-row-SA0000003')), findsOneWidget);
      expect(find.text('@khalid'), findsOneWidget);
      // صفّي أنا بلا زر متابعة، ومن أتابعه «تتابعه»
      expect(find.byKey(const Key('follow-row-btn-SA0000001')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('follow-row-btn-SA0000003')), matching: find.text('تتابعه')), findsOneWidget);
      // الصفحة الأولى قصيرة: «عرض المزيد» يطلب before=المؤشر كما هو
      await tester.tap(find.byKey(const Key('follow-more')));
      await _settle(tester);
      expect(srv.calls.where((c) => c.startsWith('GET /profiles/SA0000002/followers')).last, contains('before=2026-11-01T10%3A00%3A00.000000Z~SA0000004'));
      expect(find.byKey(const Key('follow-row-SA0000004')), findsOneWidget);
      expect(find.byKey(const Key('follow-more')), findsNothing);
      await tester.tap(find.byKey(const Key('follow-row-btn-SA0000004')));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const Key('follow-row-btn-SA0000004')), matching: find.text('تتابعه')), findsOneWidget, reason: 'متفائل');
      await _settle(tester);
      expect(srv.calls, contains('POST /profiles/SA0000004/follow'));
      await tester.tap(find.byKey(const Key('follow-row-btn-SA0000003')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /profiles/SA0000003/follow'));
      expect(find.descendant(of: find.byKey(const Key('follow-row-btn-SA0000003')), matching: find.text('متابعة')), findsOneWidget);
      // تبويب «يتابع»
      await tester.tap(find.byKey(const Key('follow-tab-following')));
      await _settle(tester);
      expect(find.byKey(const Key('follow-row-SA0000005')), findsOneWidget);
    });

    testWidgets('a private profile\'s lists show «القائمة خاصة»', (tester) async {
      final srv = _Srv()..listsPrivate = true;
      await _pump(tester, const FollowListPage(userId: 'SA0000002', name: 'سارة', followers: false), srv: srv);
      expect(find.byKey(const Key('follow-private')), findsOneWidget);
      expect(find.text('القائمة خاصة'), findsOneWidget);
    });

    testWidgets('an empty list says «لا متابِعين بعد»', (tester) async {
      await _pump(tester, const FollowListPage(userId: 'SA0000002', name: 'سارة'));
      expect(find.byKey(const Key('follow-empty')), findsOneWidget);
      expect(find.text('لا متابِعين بعد'), findsOneWidget);
    });

    testWidgets('the profile shows «متابِعون» and «يتابع» counts that open the lists', (tester) async {
      final srv = _Srv()..followingList = [_person('SA0000005', 'lina')];
      await _pump(tester, const UserProfilePage(person: Person(id: 'SA0000002', nickname: 'sara')), srv: srv);
      expect(find.text('متابِعون'), findsOneWidget);
      expect(find.text('يتابع'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stat-following')));
      await _settle(tester);
      expect(find.byType(FollowListPage), findsOneWidget);
      expect(find.byKey(const Key('follow-row-SA0000005')), findsOneWidget, reason: 'يفتح على تبويب «يتابع»');
    });
  });

  testWidgets('«إشعارات من أتابعهم» in privacy control sends followNotify', (tester) async {
    final srv = _Srv();
    await _pump(tester, const PrivacyControlPage(), srv: srv);
    await tester.scrollUntilVisible(find.byKey(const Key('follow-notify')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('إشعارات من أتابعهم'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('follow-notify'))).value, isTrue);
    await tester.tap(find.byKey(const Key('follow-notify')));
    await _settle(tester);
    expect(srv.bodies['PUT /me/profile/v2'], {'followNotify': false});
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('follow-notify'))).value, isFalse);
    expect(find.textContaining('متوقفة'), findsOneWidget);
  });

  test('follow_moment opens the moment (or the author without a postId) and has its own icon', () {
    final open = notificationTarget(const AppNotification(id: 'n1', kind: 'follow_moment', title: 'لحظة جديدة من sara', data: {'postId': 'aaaaaaaa-0000-4000-8000-000000000001', 'userId': 'SA0000002', 'nickname': 'sara'}));
    expect(open, isA<MomentLinkPage>());
    expect((open as MomentLinkPage).id, 'aaaaaaaa-0000-4000-8000-000000000001');
    final author = notificationTarget(const AppNotification(id: 'n2', kind: 'follow_moment', title: 'x', data: {'userId': 'SA0000002', 'nickname': 'sara'}));
    expect(author, isA<UserProfilePage>());
    expect((author as UserProfilePage).person.nickname, 'sara');
    expect(notificationStyle('follow_moment').icon, isNot(Icons.notifications_outlined));
  });

  test('FeedPage reads the following counts; other scopes have none', () {
    final p = FeedPage.fromJson({'items': [], 'next': null, 'scope': 'following', 'following': {'people': 4, 'circles': 2}});
    expect((p.followPeople, p.followCircles), (4, 2));
    final q = FeedPage.fromJson({'items': [], 'next': null});
    expect((q.followPeople, q.followCircles), (null, null));
  });
}
