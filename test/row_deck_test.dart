// «الصف» (نظام «واحد» بشكل البطاقة): الرئيسية خريطة كاملة وبطاقة مدمجة واحدة تُسحب جانبياً. يطلب /row ويعرض البطاقة
// الأولى بعدّادها، السهمان والسحب يبدّلان البطاقة حلقياً، الخريطة تتبع البطاقة المختارة ودبّوسها يُبرز، النقر على دبّوس
// يقفز بالبطاقة إليه، زر البطاقة يفتح رحلة العنصر القائمة لكل نوع، الزائر يطلب /row ولا شيء خاصاً، والحالة الفارغة،
// وشريط التنقّل ثابت بأربعة أقسام.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/row_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/nav_provider.dart';
import 'package:naslook/pages/business/offers_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/home/row_deck.dart';
import 'package:naslook/pages/jobs/job_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/market/listing_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/joy_nav_bar.dart';

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

const _pid = 'aaaaaaaa-0000-4000-8000-000000000001';
const _lid = '11111111-1111-4111-8111-111111111111';
const _eid = 'eeeeeeee-0000-4000-8000-000000000001';
const _jid = 'bbbbbbbb-0000-4000-8000-000000000001';

Map<String, dynamic> _post() => {
      'id': _pid, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': 'قهوة على الكورنيش', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment',
      'lat': 21.542, 'lng': 39.171, 'status': 'active', 'views': 3, 'likes': 12, 'liked': false, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

/// سبعة عناصر مختلطة متقاربة (ضمن مجال الرؤية عند تكبير التتبع) بالترتيب الذي يعيده الخادم.
List<Map<String, dynamic>> _items() => [
      {'kind': 'offer', 'id': 'off-1', 'refId': 'biz-cafe', 'title': 'خصم ٢٠٪ على اللاتيه', 'subtitle': 'الروضة · ينتهي الليلة', 'who': 'أوفردوز', 'logoUrl': null, 'imageUrl': null, 'lat': 21.541, 'lng': 39.171, 'distanceKm': 0.65, 'at': null, 'endsAt': null, 'act': 'استخدم', 'payload': {}},
      {'kind': 'moment', 'id': _pid, 'refId': _pid, 'title': 'قهوة على الكورنيش', 'subtitle': 'قبل 12 د · 12 إعجاباً', 'who': 'sara', 'imageUrl': null, 'lat': 21.542, 'lng': 39.171, 'distanceKm': 0.8, 'act': 'شاهد', 'payload': _post()},
      {'kind': 'event', 'id': _eid, 'refId': _eid, 'title': 'بازار الحي', 'subtitle': 'حديقة الشاطئ · اليوم 5 م', 'who': 'هاف مليون', 'lat': 21.543, 'lng': 39.172, 'distanceKm': 0.9, 'act': 'تذكرة', 'payload': {}},
      {'kind': 'job', 'id': _jid, 'refId': _jid, 'title': 'يوظّف باريستا', 'subtitle': 'دوام جزئي · 4,500 ر.س', 'who': 'ثري بروز', 'lat': 21.544, 'lng': 39.172, 'distanceKm': 2.1, 'act': 'قدّم', 'payload': {}},
      {'kind': 'listing', 'id': _lid, 'refId': _lid, 'title': 'كاميرا فوجي X-T20', 'subtitle': '2,650 ر.س · الحمراء', 'who': 'عبدالله', 'imageUrl': null, 'lat': 21.541, 'lng': 39.173, 'distanceKm': 1.4, 'act': 'اطلب', 'payload': {}},
      {'kind': 'moment', 'id': 'aaaaaaaa-0000-4000-8000-000000000002', 'title': 'نورة في التحلية', 'subtitle': 'قبل ساعة', 'who': 'nora', 'lat': 21.5425, 'lng': 39.1735, 'distanceKm': 3.4, 'act': 'شاهد', 'payload': _post()},
      {'kind': 'offer', 'id': 'off-2', 'refId': 'biz-brew', 'title': 'قهوة اليوم بنصف السعر', 'subtitle': 'التحلية · ينتهي بعد 3 س', 'who': 'بروز', 'lat': 21.5435, 'lng': 39.1705, 'distanceKm': 4.0, 'act': 'استخدم', 'payload': {}},
    ];

/// المسارات العامة الوحيدة التي يجوز أن يطلبها زائر (كما في guest_browse_test).
bool _publicRoute(Uri u) {
  final p = u.path;
  if (u.queryParameters['mine'] == '1' || p.endsWith('/mine')) return false;
  return p == '/biz' || p.startsWith('/biz/') || p.startsWith('/mapposts') || p.startsWith('/market') || p.startsWith('/events') ||
      p == '/settings/public' || p == '/safety/words' || p.startsWith('/legal/') || p == '/offers/map' || p == '/offers/near' || p == '/row' || p.startsWith('/tiles/');
}

class _Srv {
  final calls = <String>[];
  final denied = <String>[];
  /// ما يعيده /row (null = فارغ).
  List<Map<String, dynamic>>? items = _items();
  bool located = true;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (!req.headers.containsKey('x-token') && !_publicRoute(req.url)) denied.add(key);
    switch (key) {
      case 'GET /row':
        return _json({'items': items ?? [], 'located': located});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false, 'jobsEnabled': true});
      case 'GET /mapposts':
        return _json([_post()]);
      // طبقة العروض تحوي العرض الأول: دبّوس الطبقة هو الذي يُبرز (المطابقة بالمعرّف)
      case 'GET /offers/map':
        return _json({'items': [{'id': 'off-1', 'bizId': 'biz-cafe', 'bizName': 'أوفردوز', 'category': 'cafe', 'lat': 21.541, 'lng': 39.171, 'kind': 'deal', 'title': 'خصم ٢٠٪ على اللاتيه'}]});
      case 'GET /market/$_lid':
        return _json({'id': _lid, 'seller': {'id': 'SA0000003', 'nickname': 'عبدالله'}, 'kind': 'product', 'category': 'electronics', 'title': 'كاميرا فوجي X-T20', 'description': 'نظيفة', 'price': 265000, 'images': [], 'status': 'active', 'lat': 21.541, 'lng': 39.173, 'mine': false, 'createdAt': '2026-09-10T08:00:00Z'});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {bool signedIn = true, _Srv? srv, Widget? home}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = const Size(900, 1400); // عرض يتسع لسطر نسبة الخريطة بخط الاختبار
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home ?? const Scaffold(body: MapPage(home: true))),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// بعد تبديل البطاقة: انزلاق الخارجة (320 م ث) ثم تتبع الخريطة.
Future<void> _afterSwitch(WidgetTester tester) => _settle(tester, 3);

String _count(WidgetTester t) => t.widget<Text>(find.byKey(const Key('row-count'))).data!;

MapCamera _camera(WidgetTester t) => MapCamera.of(t.element(find.byType(MarkerLayer).first));

/// نسبة موضع الدبّوس من ارتفاع الخريطة (المطلوب نحو 42٪ حتى يبقى فوق البطاقة).
double _pinY(WidgetTester t, double lat, double lng) {
  final cam = _camera(t);
  return cam.latLngToScreenOffset(LatLng(lat, lng)).dy / cam.nonRotatedSize.height;
}

void main() {
  tearDown(() {
    ApiClient.onUnauthorized = null;
  });

  group('RowItem', () {
    test('parses tolerantly with defaults per kind and pin keys', () {
      final r = RowItem.fromJson({'kind': 'job', 'id': 'j1', 'title': 'باريستا'});
      expect(r.refId, 'j1');
      expect(r.act, 'قدّم');
      expect(r.kindLabel, 'وظيفة');
      expect(r.pinKey, 'job:j1');
      expect(r.distanceKm, isNull);
      expect(RowItem.fromJson({'kind': 'moment', 'id': 'p', 'refId': ''}).pinKey, 'post:p');
      expect(RowItem.fromJson({'kind': 'offer', 'id': 'o', 'refId': 'biz', 'act': ''}).act, 'استخدم');
      final f = RowFeed.fromJson({'items': [{'kind': 'listing', 'id': 'l'}, 'junk'], 'located': true});
      expect(f.items.length, 1);
      expect(f.located, isTrue);
    });
  });

  testWidgets('home map requests /row and shows the first compact card with its counter; no sheet, chips or blocks', (tester) async {
    final srv = await _pump(tester);
    expect(srv.calls, contains('GET /row'));
    expect(find.byKey(const Key('row-card')), findsOneWidget);
    expect(find.text('خصم ٢٠٪ على اللاتيه'), findsOneWidget);
    expect(find.text('عرض · أوفردوز'), findsOneWidget);
    expect(find.text('الروضة · ينتهي الليلة'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('row-dist'))).data, '650 م');
    expect(find.descendant(of: find.byKey(const Key('row-act')), matching: find.text('استخدم')), findsOneWidget);
    expect(_count(tester), '1 من 7 · الأقرب أولاً');
    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.byKey(const Key('home-bell')), findsOneWidget);
    // لا رقائق ولا ورقة ولا أقسام ولا تحرير
    expect(find.byKey(const Key('map-chip-offers')), findsNothing);
    expect(find.text('لحظات'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('حولك الآن'), findsNothing);
    expect(find.byKey(const Key('home-edit')), findsNothing);
    // الخريطة تتبع البطاقة: تكبير التتبع والمركز أسفل الدبّوس قليلاً (الدبّوس عند نحو 42٪ من الارتفاع)
    final cam = _camera(tester);
    expect(cam.zoom, kRowFollowZoom);
    expect(cam.center.longitude, closeTo(39.171, 1e-6));
    expect(cam.center.latitude, lessThan(21.541));
    expect(_pinY(tester, 21.541, 39.171), closeTo(.42, .02));
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    expect(find.byIcon(Icons.event_rounded), findsOneWidget, reason: 'دبّوس الفعالية من الصف');
    expect(find.byIcon(Icons.work_rounded), findsOneWidget, reason: 'دبّوس الوظيفة من الصف');
  });

  testWidgets('arrows move forward and back with wrap-around, the map follows and the highlighted pin changes', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('row-next')));
    await _afterSwitch(tester);
    expect(_count(tester), '2 من 7 · الأقرب أولاً');
    expect(find.text('قهوة على الكورنيش'), findsOneWidget);
    expect(_pinY(tester, 21.542, 39.171), closeTo(.42, .02), reason: 'الخريطة تبعت البطاقة الثانية');
    await tester.tap(find.byKey(const Key('row-prev')));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً');
    await tester.tap(find.byKey(const Key('row-prev')));
    await _afterSwitch(tester);
    expect(_count(tester), '7 من 7 · الأقرب أولاً', reason: 'قبل الأولى تأتي الأخيرة');
    expect(find.text('قهوة اليوم بنصف السعر'), findsOneWidget);
    expect(_pinY(tester, 21.5435, 39.1705), closeTo(.42, .02));
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-next')));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً', reason: 'بعد الأخيرة تعود الأولى');
  });

  testWidgets('a horizontal swipe past 60 px changes the card; a short one does not', (tester) async {
    await _pump(tester);
    await tester.drag(find.byKey(const Key('row-card')), const Offset(-30, 0));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً');
    expect(find.byKey(const Key('row-card')), findsOneWidget);
    await tester.drag(find.byKey(const Key('row-card')), const Offset(-140, 0));
    await _afterSwitch(tester);
    expect(_count(tester), '2 من 7 · الأقرب أولاً', reason: 'سحب لليسار = التالي');
    expect(find.byKey(const Key('row-card')), findsOneWidget, reason: 'بطاقة واحدة بعد انتهاء الانزلاق');
    await tester.drag(find.byKey(const Key('row-card')), const Offset(140, 0));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً', reason: 'سحب لليمين = السابق');
  });

  testWidgets('tapping a row pin on the map jumps the deck to it', (tester) async {
    await _pump(tester);
    // دبّوس الوظيفة (لا بطاقة وظيفة ظاهرة الآن فالرمز وحيد على الشاشة)
    expect(find.byIcon(Icons.work_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.work_rounded));
    await _afterSwitch(tester);
    expect(_count(tester), '4 من 7 · الأقرب أولاً');
    expect(find.text('يوظّف باريستا'), findsOneWidget);
    expect(_pinY(tester, 21.544, 39.172), closeTo(.42, .02));
  });

  testWidgets('the card button opens the existing journey for each of the five kinds', (tester) async {
    await _pump(tester);
    Future<void> act() async {
      await tester.tap(find.byKey(const Key('row-act')));
      await _settle(tester, 3);
    }

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await _settle(tester, 3);
    }

    Future<void> next() async {
      await tester.tap(find.byKey(const Key('row-next')));
      await _afterSwitch(tester);
    }

    // 1 عرض → عروض الدائرة
    await act();
    expect(tester.widget<CircleOffersPage>(find.byType(CircleOffersPage)).bizId, 'biz-cafe');
    await back();
    // 2 لحظة → العارض على المنشور من الحمولة بلا طلب آخر
    await next();
    await act();
    expect(tester.widget<PostViewerPage>(find.byType(PostViewerPage)).posts.single.id, _pid);
    await back();
    // 3 فعالية → تفاصيل الفعالية
    await next();
    await act();
    expect(tester.widget<EventDetailPage>(find.byType(EventDetailPage)).eventId, _eid);
    await back();
    // 4 وظيفة → صفحة الوظيفة
    await next();
    await act();
    expect(tester.widget<JobPage>(find.byType(JobPage)).id, _jid);
    await back();
    // 5 سوق → صفحة الإعلان
    await next();
    await act();
    expect(tester.widget<ListingPage>(find.byType(ListingPage)).id, _lid);
    expect(find.text('كاميرا فوجي X-T20'), findsWidgets);
  });

  testWidgets('a guest home map requests /row and nothing private, sees the deck, and the bell asks to sign in', (tester) async {
    final srv = await _pump(tester, signedIn: false);
    expect(srv.calls, contains('GET /row'));
    expect(srv.calls, contains('GET /mapposts'));
    expect(srv.denied, isEmpty, reason: 'مسارات حساب طُلبت بلا جلسة: ${srv.denied}');
    expect(find.byKey(const Key('row-card')), findsOneWidget);
    expect(find.text('خصم ٢٠٪ على اللاتيه'), findsOneWidget);
    expect(find.byTooltip('إظهار موقعي'), findsNothing);
    await tester.tap(find.byKey(const Key('home-bell')));
    await _settle(tester, 2);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(srv.denied, isEmpty);
  });

  testWidgets('an empty row shows the empty card, and «newest first» when not located', (tester) async {
    final srv = await _pump(tester, srv: _Srv()..items = null);
    expect(srv.calls, contains('GET /row'));
    expect(find.byKey(const Key('row-empty')), findsOneWidget);
    expect(find.text('لا شيء حولك الآن… جرّب أن تنشر لحظة'), findsOneWidget);
    expect(find.byKey(const Key('row-card')), findsNothing);
    expect(find.byKey(const Key('row-count')), findsNothing);
    // تحديث يعيد الجلب: الصف صار فيه عناصر بلا موقع
    srv.items = _items().sublist(0, 2);
    srv.located = false;
    await tester.tap(find.byTooltip('تحديث'));
    await _settle(tester, 3);
    expect(_count(tester), '1 من 2 · الأحدث أولاً');
  });

  testWidgets('deck widget alone: loading skeleton, then cards driven by the parent index', (tester) async {
    var index = 0;
    RowItem? acted;
    final items = [for (final m in _items()) RowItem.fromJson(m)];
    Widget build() => StatefulBuilder(builder: (context, setState) => Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: RowDeck(items: items, index: index, onIndex: (i) => setState(() => index = i), onAct: (it) => acted = it))));
    await tester.pumpWidget(MaterialApp(locale: const Locale('ar'), home: const Scaffold(body: RowDeck(items: [], index: 0, loading: true, onIndex: _noop, onAct: _noopItem))));
    expect(find.byKey(const Key('row-skeleton')), findsOneWidget);
    await tester.pumpWidget(MaterialApp(locale: const Locale('ar'), home: build()));
    await tester.pump();
    expect(_count(tester), '1 من 7 · الأقرب أولاً');
    await tester.tap(find.byKey(const Key('row-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(index, 1);
    expect(find.byKey(const Key('row-card')), findsOneWidget, reason: 'بطاقة واحدة بعد انتهاء الانزلاق');
    await tester.tap(find.byKey(const Key('row-act')));
    expect(acted?.id, _pid);
  });

  testWidgets('the pill nav is fixed to four tabs with the camera in the middle; HomeShell maps them', (tester) async {
    int? picked;
    var composed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: JoyNavBar(tabs: navTabIds, index: 0, onSelect: (i) => picked = i, onCompose: () => composed++, badges: const {'chats': 3}))));
    expect(navTabIds, ['home', 'circles', 'chats', 'me']);
    expect(find.text('الخريطة'), findsOneWidget);
    expect(find.text('الدوائر'), findsOneWidget);
    expect(find.text('المحادثات'), findsOneWidget);
    expect(find.text('ماي سبيس'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('nav-compose'))).dx, closeTo(400, 30), reason: 'الكاميرا في المنتصف');
    await tester.tap(find.byKey(const Key('nav-chats')));
    expect(picked, 2);
    await tester.tap(find.byKey(const Key('nav-compose')));
    expect(composed, 1);
    expect(HomeShell.pageOf('home'), isA<MapPage>().having((m) => m.home, 'home', isTrue));
    expect(HomeShell.ownBar('home'), isTrue);
    expect(HomeShell.ownBar('chats'), isFalse);
  });
}

void _noop(int _) {}
void _noopItem(RowItem _) {}
