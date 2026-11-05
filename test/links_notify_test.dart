// روابط ووجهات كانت تفتح خطأً أو لا شيء: زر «قدّم» في بطاقة الوظيفة يفتح الوظيفة بمعرّفها (لا بمعرّف الدائرة)، رابط مشاركة
// العرض /l/<id> و#/l/<id> يفتح صفحة العرض (مسجّلاً وزائراً)، إشعارات السوق والمحفظة والترقية تفتح شاشتها من حمولتها
// والنوع المجهول لا يفعل شيئاً، وتسجيل الخروج يوقف مشاركات الموقع المباشر على الخادم أولاً بمهلة قصيرة ثم مؤقّتاتها المحلية
// (فلا قراءة GPS ولا دفع بلا رمز يفتح دعوة الدخول وحده بعد الخروج).
import 'dart:async';
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
import 'package:naslook/api/row_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/chat/live_share.dart';
import 'package:naslook/pages/home/row_open.dart';
import 'package:naslook/pages/jobs/job_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/market/wanted_page.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

const _job = '11111111-1111-4111-8111-111111111101';
const _lid = '22222222-2222-4222-8222-222222222202';
const _order = '33333333-3333-4333-8333-333333333303';
const _live = '44444444-4444-4444-8444-444444444404';

Map<String, dynamic> _jobJson() => {
      'id': _job, 'bizId': 'biz-brew92', 'title': 'باريستا', 'titleEn': '', 'department': '', 'description': 'تحضير القهوة', 'descriptionEn': '', 'requirements': {'must': [], 'nice': []}, 'skills': [],
      'city': 'جدة', 'district': 'الروضة', 'type': 'shift', 'experienceMin': 0, 'education': 'any', 'salaryMin': null, 'salaryMax': null, 'salaryVisible': false, 'openings': 1, 'deadline': null,
      'status': 'open', 'public': true, 'views': 3, 'publishedAt': '2026-11-01T08:00:00Z', 'closedAt': null, 'createdAt': '2026-11-01T08:00:00Z', 'updatedAt': '2026-11-01T08:00:00Z',
      'biz': {'id': 'biz-brew92', 'name': 'Brew92', 'nameAr': 'برو 92', 'category': 'cafe', 'address': 'جدة', 'city': 'جدة', 'logoUrl': null, 'verified': true}, 'mine': null,
    };

Map<String, dynamic> _listingJson() => {
      'id': _lid, 'seller': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'kind': 'product', 'category': 'food', 'subcategory': 'sweets', 'title': 'كيك الليمون', 'description': 'طازج',
      'price': 4500, 'imageUrl': null, 'images': [], 'status': 'active', 'lat': 21.5, 'lng': 39.1, 'mine': false, 'createdAt': '2026-11-01T08:00:00Z',
    };

class _Srv {
  final calls = <String>[];
  /// تحجز ردّ إيقاف المشاركات (خادم بطيء) حتى تُفتح
  Completer<void>? stopGate;
  int stopped = 1;
  /// خادم قديم بلا POST /chat/live/stop-all (404)
  bool noStopAll = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    switch (key) {
      case 'GET /jobs/$_job':
        return _json(_jobJson());
      case 'GET /market/$_lid':
        return _json(_listingJson());
      case 'GET /market/$_lid/questions':
      case 'GET /market/$_lid/reviews':
        return _json([]);
      case 'POST /chat/live/stop-all':
        if (noStopAll) return _json({'error': 'not-found'}, 404);
        if (stopGate != null) await stopGate!.future;
        return _json({'ok': true, 'stopped': stopped});
      case 'POST /chat/live':
        return _json({'id': _live, 'from': 'SA0000001', 'to': 'SA0000002', 'lat': null, 'lng': null, 'at': null, 'until': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(), 'active': true});
      case 'PUT /chat/live/$_live':
      case 'DELETE /chat/live/$_live':
        // كالخادم: بلا رمز جلسة 401
        if (req.headers['x-token'] == null) return _json({'error': 'auth'}, 401);
        return _json({'ok': true});
      case 'POST /logout':
        return _json({'ok': true});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/wishlist')) return _json({'items': []});
    if (req.method == 'POST') return _json({'ok': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {bool signedIn = true}) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
  return srv;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

AppNotification _n(String kind, [Map<String, dynamic> data = const {}]) => AppNotification(id: 'n-$kind', kind: kind, title: kind, data: data);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('row job card', () {
    testWidgets('«قدّم» opens the job by its id, not by the circle (refId)', (tester) async {
      // كما يبنيها server/row.js: id الوظيفة وrefId الدائرة صاحبتها
      final it = RowItem.fromJson({'kind': 'job', 'id': _job, 'refId': 'biz-brew92', 'title': 'باريستا', 'who': 'برو 92', 'lat': 21.5, 'lng': 39.2});
      expect(it.act, 'قدّم');
      expect(it.refId, 'biz-brew92', reason: 'refId يبقى الدائرة لبقية الاستعمالات');
      final srv = await _pump(tester, Scaffold(body: Builder(builder: (ctx) => TextButton(key: const Key('open-job'), onPressed: () => openRowItem(ctx, it), child: const Text('قدّم')))));
      await tester.tap(find.byKey(const Key('open-job')));
      await _settle(tester);
      expect(tester.widget<JobPage>(find.byType(JobPage)).id, _job);
      expect(srv.calls, contains('GET /jobs/$_job'));
      expect(srv.calls.where((c) => c.contains('/jobs/biz-brew92')), isEmpty, reason: 'لا طلب بمعرّف الدائرة (كان يفتح صفحة خطأ)');
      expect(find.text('باريستا'), findsWidgets);
    });
  });

  group('listing share links', () {
    test('parsePendingLink reads /l/<uuid> from the path or the #/l/ fragment the server redirects to', () {
      expect(parsePendingLink(Uri.parse('https://naslife.app/l/$_lid'))?.toString(), 'listing:$_lid');
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/l/$_lid'))?.toString(), 'listing:$_lid');
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/l/${_lid.toUpperCase()}'))?.value, _lid, reason: 'المعرّف بأحرف صغيرة');
      expect(parsePendingLink(Uri.parse('https://naslife.app/l/$_lid/'))?.isListing, isTrue);
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/l/not-a-uuid')), isNull);
      expect(parsePendingLink(Uri.parse('https://naslife.app/l/')), isNull);
      // بقية الروابط كما هي
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/m/$_lid'))?.isMoment, isTrue);
      expect(parsePendingLink(Uri.parse('https://naslife.app/c/biz-brew92'))?.isCircle, isTrue);
      expect(parsePendingLink(Uri.parse('https://naslife.app/u/sara'))?.kind, 'user');
    });

    test('pendingLinkPage maps a listing link to the listing page', () {
      final page = pendingLinkPage(const PendingLink('listing', _lid));
      expect(page, isA<ListingPage>().having((p) => p.id, 'id', _lid));
      expect(pendingLinkPage(const PendingLink('user', 'sara')).runtimeType.toString(), 'PublicProfilePage');
    });

    testWidgets('a guest opening a shared listing link sees the listing over the guest tabs and can leave it', (tester) async {
      final srv = await _pump(tester, const GuestShell(link: PendingLink('listing', _lid)), signedIn: false);
      expect(find.byType(ListingPage), findsOneWidget);
      expect(srv.calls, contains('GET /market/$_lid'));
      expect(find.text('كيك الليمون'), findsOneWidget);
      // العرض فوق تبويبات الزائر: الرجوع يفتح السوق لا صفحة بلا مخرج
      Navigator.of(tester.element(find.byType(ListingPage))).pop();
      await _settle(tester);
      expect(find.byType(ListingPage), findsNothing);
      expect(find.byKey(const Key('guest-shell')), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('market notifications', () {
    test('each market, wallet and upgrade kind opens its screen from the payload', () {
      final listing = {'listingId': _lid};
      for (final k in ['market_new', 'market_alert', 'market_question', 'market_spotlight', 'market_review_result']) {
        expect(notificationTarget(_n(k, listing)), isA<ListingPage>().having((p) => p.id, 'id', _lid), reason: k);
      }
      // التقييم: للبائع (طلب وعرض) وللمشتري حين يرد البائع (عرض فقط) → صفحة العرض حيث التقييمات
      expect(notificationTarget(_n('market_review', {'orderId': _order, 'listingId': _lid})), isA<ListingPage>());
      expect(notificationTarget(_n('market_review', {'orderId': _order})), isA<OrderPage>().having((p) => p.id, 'id', _order));
      for (final k in ['market_order', 'market_status', 'market_courier', 'market_dispute']) {
        expect(notificationTarget(_n(k, {'orderId': _order, 'status': 'completed'})), isA<OrderPage>().having((p) => p.id, 'id', _order), reason: k);
        expect(notificationTarget(_n(k)), isA<OrdersPage>(), reason: '$k بلا طلب → عروضي وطلباتي');
      }
      expect(notificationTarget(_n('market_pending', listing)), isA<AdminShell>().having((s) => s.initialSection, 'section', adminSections.indexWhere((s) => s.$1 == 'market')));
      expect(notificationTarget(_n('market_wanted', {'wantedId': 'w-1'})), isA<WantedDetailPage>().having((p) => p.id, 'id', 'w-1'));
      expect(notificationTarget(_n('market_wanted')), isA<WantedPage>());
      expect(notificationTarget(_n('market_bazaar', {'bazaarId': 'bz-1'})), isA<BazaarPage>().having((p) => p.id, 'id', 'bz-1'));
      expect(notificationTarget(_n('market_bazaar')), isA<MarketPage>());
      expect(notificationTarget(_n('wallet', {'paymentId': 'p-1'})), isA<WalletPage>());
      expect(notificationTarget(_n('biz', {'bizId': 'biz-new'})), isA<BusinessDashboardPage>().having((p) => p.id, 'id', 'biz-new'));
      expect(notificationTarget(_n('biz')), isNull, reason: 'بلا دائرة لا وجهة');
      // الأنواع القائمة لم تتغير
      expect(notificationTarget(_n('listing_hidden', listing)), isA<OrdersPage>().having((p) => p.initialTab, 'tab', 0));
      expect(notificationTarget(_n('transfer_in')), isA<WalletPage>());
    });

    test('unknown kinds have no target, and market kinds get their own icon', () {
      expect(notificationTarget(_n('something_new', {'listingId': _lid})), isNull);
      expect(notificationTarget(_n('product', {'listingId': _lid})), isNull);
      final generic = notificationStyle('something_new').icon;
      for (final k in ['market_new', 'market_alert', 'market_question', 'market_courier', 'market_dispute', 'market_review', 'market_review_result', 'market_pending', 'market_wanted', 'market_bazaar', 'market_spotlight', 'wallet', 'biz']) {
        expect(notificationStyle(k).icon, isNot(generic), reason: k);
      }
    });

    testWidgets('tapping a market question opens the listing; an unknown kind opens nothing', (tester) async {
      late WidgetRef r;
      late BuildContext c;
      final srv = await _pump(tester, Consumer(builder: (ctx, ref, _) { r = ref; c = ctx; return const Scaffold(body: SizedBox()); }));
      expect(await openNotification(c, r, _n('unknown_kind', {'listingId': _lid})), isFalse);
      await _settle(tester);
      expect(find.byType(ListingPage), findsNothing);
      unawaited(openNotification(c, r, _n('market_question', {'listingId': _lid, 'questionId': 'q1'})));
      await _settle(tester);
      expect(find.byType(ListingPage), findsOneWidget);
      expect(srv.calls, contains('GET /market/$_lid'));
    });
  });

  group('logout ends live location shares', () {
    test('logout asks the server to stop every live share before ending the session', () async {
      final srv = _Srv();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 'tok';
      final n = _SignedIn(api, SessionStore());
      await n.logout();
      expect(srv.calls, containsAllInOrder(['POST /chat/live/stop-all', 'POST /logout']));
      expect(srv.calls.indexOf('POST /chat/live/stop-all'), lessThan(srv.calls.indexOf('POST /logout')), reason: 'بالرمز الصالح قبل إبطاله');
      expect(n.state.status, AuthStatus.signedOut);
      expect(api.token, isNull);
    });

    test('a failing stop-all (old server) never blocks the logout', () async {
      final calls = <String>[];
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode({'error': 'not-found'}), 404, headers: {'content-type': 'application/json'});
      }))..token = 'tok';
      final n = _SignedIn(api, SessionStore());
      await n.logout();
      expect(calls, ['POST /chat/live/stop-all', 'POST /logout']);
      expect(n.state.status, AuthStatus.signedOut);
    });

    testWidgets('a slow server: logout waits at most the short timeout, then proceeds', (tester) async {
      final srv = _Srv()..stopGate = Completer<void>();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 'tok';
      final n = _SignedIn(api, SessionStore());
      var done = false;
      unawaited(n.logout().then((_) => done = true));
      await tester.pump(const Duration(seconds: 1));
      expect(done, isFalse);
      expect(srv.calls, ['POST /chat/live/stop-all']);
      await tester.pump(AppStateNotifier.liveStopTimeout);
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, isTrue);
      expect(srv.calls, contains('POST /logout'));
      expect(n.state.status, AuthStatus.signedOut);
      srv.stopGate!.complete();
    });

    /// يبدأ مشاركة موقع مع SA0000002 ويمرّر دفعة دورية واحدة؛ يعيد عدّاد قراءات GPS ودعوات الدخول.
    Future<({_Srv srv, ApiClient api, _SignedIn n, LiveShareController ctl, int Function() gps, int Function() prompts})> startShare(WidgetTester tester, {bool noStopAll = false}) async {
      var gps = 0, prompts = 0;
      DeviceLocation.override = () async {
        gps++;
        return const LatLng(21.5, 39.2);
      };
      final prevPrompt = ApiClient.onUnauthorized;
      ApiClient.onUnauthorized = () => prompts++;
      addTearDown(() {
        DeviceLocation.override = null;
        ApiClient.onUnauthorized = prevPrompt;
        LiveShareController.resetForTests();
      });
      final srv = _Srv()..noStopAll = noStopAll;
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 'tok';
      final n = _SignedIn(api, SessionStore());
      final ctl = LiveShareController.of('SA0000002');
      unawaited(ctl.start(api, 60, const LatLng(21.5, 39.2)));
      await _settle(tester, 2);
      expect(ctl.active, isTrue);
      await tester.pump(LiveShareController.pushEvery);
      await _settle(tester, 2);
      expect(srv.calls.where((c) => c == 'PUT /chat/live/$_live').length, 2, reason: 'الدفعة الأولى ثم دفعة المؤقّت');
      expect(gps, 1);
      return (srv: srv, api: api, n: n, ctl: ctl, gps: () => gps, prompts: () => prompts);
    }

    testWidgets('logout also stops this device\'s live-share timer: no GPS read, no tokenless push, no sign-in prompt afterwards', (tester) async {
      final s = await startShare(tester);
      unawaited(s.n.logout());
      await _settle(tester, 2);
      expect(s.n.state.status, AuthStatus.signedOut);
      expect(s.api.token, isNull);
      expect(s.ctl.active, isFalse, reason: 'خطّاف الخروج أوقف المتحكّم');
      expect(s.srv.calls, containsAllInOrder(['POST /chat/live/stop-all', 'POST /logout']));
      expect(s.srv.calls, isNot(contains('DELETE /chat/live/$_live')), reason: 'الخادم أوقفها كلها فلا إيقاف منفرد');
      for (var i = 0; i < 3; i++) {
        await tester.pump(LiveShareController.pushEvery);
        await _settle(tester, 2);
      }
      expect(s.srv.calls.where((c) => c == 'PUT /chat/live/$_live').length, 2, reason: 'لا دفع بعد الخروج');
      expect(s.gps(), 1, reason: 'لا قراءة GPS بعد الخروج');
      expect(s.prompts(), 0, reason: 'لا دعوة دخول تظهر وحدها بعد الخروج');
    });

    testWidgets('an old server without stop-all: the share this device knows is stopped by DELETE before the session ends', (tester) async {
      final s = await startShare(tester, noStopAll: true);
      unawaited(s.n.logout());
      await _settle(tester, 2);
      expect(s.ctl.active, isFalse);
      expect(s.srv.calls, containsAllInOrder(['POST /chat/live/stop-all', 'DELETE /chat/live/$_live', 'POST /logout']), reason: 'بالرمز الصالح قبل إبطاله');
      await tester.pump(LiveShareController.pushEvery * 2);
      await _settle(tester, 2);
      expect(s.srv.calls.where((c) => c == 'PUT /chat/live/$_live').length, 2);
      expect(s.prompts(), 0);
    });

    testWidgets('a slow server with an open share: the timer stops and no extra DELETE wait is added after the timeout', (tester) async {
      final s = await startShare(tester);
      s.srv.stopGate = Completer<void>();
      var done = false;
      unawaited(s.n.logout().then((_) => done = true));
      await tester.pump(const Duration(seconds: 1));
      expect(done, isFalse);
      await tester.pump(AppStateNotifier.liveStopTimeout);
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, isTrue, reason: 'المهلة القصيرة وحدها');
      expect(s.ctl.active, isFalse);
      expect(s.srv.calls, isNot(contains('DELETE /chat/live/$_live')), reason: 'خادم بطيء: لا ننتظر طلبات إيقاف أخرى');
      s.srv.stopGate!.complete();
      await tester.pump(LiveShareController.pushEvery * 2);
      await _settle(tester, 2);
      expect(s.srv.calls.where((c) => c == 'PUT /chat/live/$_live').length, 2);
      expect(s.gps(), 1);
      expect(s.prompts(), 0);
    });

    testWidgets('signed out in another tab: this tab\'s live-share timer stops without any request', (tester) async {
      final s = await startShare(tester);
      final before = s.srv.calls.length;
      unawaited(s.n.syncFromStore()); // التخزين المحلي فارغ = خرج في تبويب آخر
      await _settle(tester, 2);
      expect(s.n.state.status, AuthStatus.signedOut);
      expect(s.ctl.active, isFalse);
      await tester.pump(LiveShareController.pushEvery * 2);
      await _settle(tester, 2);
      expect(s.srv.calls.length, before, reason: 'لا دفع ولا DELETE برمز أُبطل');
      expect(s.gps(), 1);
      expect(s.prompts(), 0);
    });

    test('without a session token there is nothing to stop', () async {
      final srv = _Srv();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
      final n = _SignedOut(api, SessionStore());
      await n.logout();
      expect(srv.calls, isNot(contains('POST /chat/live/stop-all')));
    });
  });
}
