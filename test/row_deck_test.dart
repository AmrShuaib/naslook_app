// «الصف» (نظام «واحد» بشكل البطاقة): الرئيسية خريطة كاملة وبطاقة مدمجة واحدة تُسحب جانبياً. يطلب /row ويعرض البطاقة
// الأولى ونقاط صفحاتها، السحب والنقاط يبدّلان البطاقة حلقياً، الخريطة تتبع البطاقة المختارة ودبّوسها يُبرز، النقر على دبّوس
// يقفز بالبطاقة إليه، زر البطاقة يفتح رحلة العنصر القائمة لكل نوع، الزائر يطلب /row ولا شيء خاصاً، والحالة الفارغة،
// وشريط التنقّل ثابت بستة أقسام.
import 'dart:convert';

import 'package:flutter/gestures.dart';
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
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/offers_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/explore/explore_page.dart';
import 'package:naslook/pages/home/row_deck.dart';
import 'package:naslook/pages/jobs/job_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/market/listing_page.dart';
import 'package:naslook/pages/market/market_page.dart' show MarketPage;
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
      p == '/settings/public' || p == '/safety/words' || p.startsWith('/legal/') || p == '/offers/map' || p == '/offers/near' || p == '/row' || p.startsWith('/tiles/') || p == '/live/wait' || p == '/live/status';
}

class _Srv {
  final calls = <String>[];
  final denied = <String>[];
  /// ما يعيده /row (null = فارغ).
  List<Map<String, dynamic>>? items = _items();
  bool located = true;
  /// أحداث القناة الحية التي يعيدها طلب /live/wait التالي فوراً (الوهمي لا ينتظر)
  final live = <Map<String, dynamic>>[];
  int liveSeq = 0;
  /// معاملات كل طلب /row (المركز الذي جُلب له الصف)
  final rowQueries = <Map<String, String>>[];
  Map<String, dynamic> presence = {'lat': null, 'lng': null, 'visible': false, 'title': ''};
  final presencePuts = <Map<String, dynamic>>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (!req.headers.containsKey('x-token') && !_publicRoute(req.url)) denied.add(key);
    switch (key) {
      case 'GET /row':
        rowQueries.add(req.url.queryParameters);
        return _json({'items': items ?? [], 'located': located});
      case 'PUT /me/map-presence':
        presencePuts.add(jsonDecode(req.body) as Map<String, dynamic>);
        presence = {...presence, ...presencePuts.last};
        return _json(presence);
      case 'GET /live/wait':
        if (!req.url.queryParameters.containsKey('after')) return _json({'seq': liveSeq, 'events': [], 'reset': false});
        final evs = [for (final e in live) {'seq': ++liveSeq, 'kind': e['kind'], 'at': DateTime.now().toUtc().toIso8601String(), 'data': e['data'] ?? {}}];
        live.clear();
        return _json({'seq': liveSeq, 'events': evs, 'reset': false});
      case 'GET /me/map-presence':
        return _json(presence);
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

/// نقاط الصفحات تحت البطاقة حلّت محل عدّاد «N من M»: الموضع والعدد وترتيب الصف منها.
RowDots _dots(WidgetTester t) => t.widget<RowDots>(find.byKey(const Key('row-dots')));
String _count(WidgetTester t) {
  final d = _dots(t);
  return '${d.index + 1} من ${d.count} · ${d.located ? 'الأقرب أولاً' : 'الأحدث أولاً'}';
}

/// السهمان أُزيلا: التبديل بالسحب (يساراً = التالي).
Future<void> _next(WidgetTester tester) async {
  await tester.drag(find.byKey(const Key('row-card')), const Offset(-140, 0));
  await _afterSwitch(tester);
}

Future<void> _prev(WidgetTester tester) async {
  await tester.drag(find.byKey(const Key('row-card')), const Offset(140, 0));
  await _afterSwitch(tester);
}

/// دبابيس الخريطة (طبقة العناصر الأولى؛ طبقة الأسماء بعدها) ورموزها الظاهرة.
List<Marker> _markers(WidgetTester t) => t.widget<MarkerLayer>(find.byType(MarkerLayer).first).markers;
Finder _pinIcon(IconData icon) => find.descendant(of: find.byType(MarkerLayer).first, matching: find.byIcon(icon));

MapCamera _camera(WidgetTester t) => MapCamera.of(t.element(find.byType(MarkerLayer).first));

/// نسبة موضع الدبّوس من ارتفاع الخريطة (المطلوب نحو 42٪ حتى يبقى فوق البطاقة).
double _pinY(WidgetTester t, double lat, double lng) {
  final cam = _camera(t);
  return cam.latLngToScreenOffset(LatLng(lat, lng)).dy / cam.nonRotatedSize.height;
}

/// فترة التحديث الدوري للصف كما تعرّفها الرئيسية.
class _MapRefresh {
  static const every = Duration(minutes: 2, seconds: 1);
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

    test('a «here today» circle and an unknown future kind both parse with sane defaults', () {
      final c = RowItem.fromJson({'kind': 'circle', 'id': 'biz-here', 'refId': 'biz-here', 'title': 'عربة قهوة', 'payload': {'here': true, 'until': '2026-10-21T15:30:00Z'}});
      expect(c.act, 'زيارة');
      expect(c.kindLabel, 'هنا اليوم');
      expect(c.pinKey, 'business:biz-here', reason: 'مفتاح طبقة الدوائر حتى يُبرز دبّوسها');
      expect(c.hereUntil, DateTime.parse('2026-10-21T15:30:00Z'));
      expect(RowItem.fromJson({'kind': 'circle', 'id': 'b', 'endsAt': '2026-10-21T16:00:00Z'}).hereUntil, DateTime.parse('2026-10-21T16:00:00Z'), reason: 'endsAt احتياط');
      final x = RowItem.fromJson({'kind': 'hologram', 'id': 'h1', 'title': 'شيء جديد'});
      expect(x.act, 'شاهد');
      expect(x.kindLabel, 'لحظة');
      expect(x.pinKey, 'hologram:h1');
      expect(x.hereUntil, isNull);
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
    // تبسيط الخريطة: لا سهمان ولا عدّاد، وزران عائمان فقط («موقعي» و«أنا هنا»)
    for (final k in ['row-prev', 'row-next', 'row-count']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.byKey(const Key('map-locate')), findsOneWidget);
    expect(find.byTooltip('موقعي'), findsOneWidget);
    expect(find.byKey(const Key('map-here')), findsOneWidget);
    for (final t in ['تحديث', 'منشور جديد', 'إظهار موقعي', 'إخفاء موقعي']) {
      expect(find.byTooltip(t), findsNothing, reason: t);
    }
    expect(find.widgetWithText(FilledButton, 'هنا الآن'), findsNothing);
    // رقائق الأنواع السبع ثم «اللحظات»، لا رقائق الوضع القديم ولا ورقة ولا أقسام ولا تحرير
    for (final id in ['all', 'moment', 'offer', 'event', 'listing', 'circle', 'job']) {
      expect(find.byKey(Key('map-chip-$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const Key('home-timeline')), findsOneWidget);
    double fromFirst(String k) => (tester.getCenter(find.byKey(Key(k))).dx - tester.getCenter(find.byKey(const Key('map-chip-all'))).dx).abs();
    expect(fromFirst('home-timeline'), greaterThan(fromFirst('map-chip-job')), reason: '«اللحظات» آخر الصف بعد «وظائف»');
    expect(find.descendant(of: find.byKey(const Key('home-timeline')), matching: find.text('اللحظات')), findsOneWidget);
    expect(find.byKey(const Key('map-chip-offers')), findsNothing);
    expect(find.text('أشخاص'), findsNothing);
    expect(find.byKey(const Key('map-search-area')), findsNothing, reason: 'لا يظهر قبل أن يحرّك المستخدم الخريطة');
    expect(find.byKey(const Key('map-attribution')), findsOneWidget, reason: 'نسب مزوّد البلاطات باقٍ');
    expect(find.byKey(const Key('map-calm-tiles')), findsOneWidget);
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

  testWidgets('the row is refetched every two minutes and when the app resumes, keeping the selected card', (tester) async {
    final srv = await _pump(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 1);
    await _next(tester);
    expect(_count(tester), startsWith('2 من'));
    // مرور دقيقتين: جلب ثانٍ دون أن تتبدّل البطاقة المختارة
    await tester.pump(_MapRefresh.every);
    await _settle(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 2);
    expect(_count(tester), startsWith('2 من'));
    // العودة إلى التطبيق من الخلفية: جلب ثالث
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 3);
  });

  testWidgets('a moment pushed over the live channel refetches the map posts and the row within seconds', (tester) async {
    final srv = await _pump(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 1);
    final posts = srv.calls.where((c) => c == 'GET /mapposts').length;
    expect(srv.calls, contains('GET /live/wait'), reason: 'الرئيسية تفتح القناة الحية');
    srv.live.add({'kind': 'post', 'data': _post()});
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 2);
    expect(srv.calls.where((c) => c == 'GET /mapposts').length, posts + 1);
    // حدثان متتاليان = جلب واحد (تجميع)
    srv.live.add({'kind': 'post', 'data': _post()});
    srv.live.add({'kind': 'post_removed', 'data': {'id': _post()['id']}});
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(srv.calls.where((c) => c == 'GET /row').length, 3);
  });

  testWidgets('swipes move forward and back with wrap-around, the map follows and the highlighted pin changes', (tester) async {
    await _pump(tester);
    await _next(tester);
    expect(_count(tester), '2 من 7 · الأقرب أولاً');
    expect(find.text('قهوة على الكورنيش'), findsOneWidget);
    expect(_pinY(tester, 21.542, 39.171), closeTo(.42, .02), reason: 'الخريطة تبعت البطاقة الثانية');
    await _prev(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً');
    await _prev(tester);
    expect(_count(tester), '7 من 7 · الأقرب أولاً', reason: 'قبل الأولى تأتي الأخيرة');
    expect(find.text('قهوة اليوم بنصف السعر'), findsOneWidget);
    expect(_pinY(tester, 21.5435, 39.1705), closeTo(.42, .02));
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    await _next(tester);
    expect(_count(tester), '1 من 7 · الأقرب أولاً', reason: 'بعد الأخيرة تعود الأولى');
  });

  testWidgets('page dots replace the arrows and the counter: one per card, the current one elongated, and a tap jumps', (tester) async {
    await _pump(tester);
    Finder dot(int i) => find.byKey(Key('row-dot-$i'));
    double width(Finder f) => tester.getSize(find.descendant(of: f, matching: find.byType(AnimatedContainer))).width;
    for (var i = 0; i < 7; i++) {
      expect(dot(i), findsOneWidget, reason: 'نقطة لكل بطاقة');
    }
    expect(dot(7), findsNothing);
    expect(tester.getSize(find.byKey(const Key('row-dot-on'))).width, 16);
    expect(width(dot(0)), 16, reason: 'الحالية ممدودة');
    expect(width(dot(1)), 6);
    // النقاط فوق البطاقة مباشرة (تحتها يغطيها زر «+» في وسط الشريط)
    expect(tester.getBottomLeft(find.byKey(const Key('row-dots'))).dy, closeTo(tester.getTopLeft(find.byKey(const Key('row-card'))).dy, 1));
    expect(tester.getSemantics(find.byKey(const Key('row-dots'))).label, '1 من 7 · الأقرب أولاً', reason: 'قارئ الشاشة يسمع ما كان العدّاد يعرضه');
    await _next(tester);
    await _settle(tester, 1);
    expect(width(dot(1)), 16);
    expect(width(dot(0)), 6);
    // لمس نقطة يقفز إلى بطاقتها والخريطة تتبعها
    await tester.tap(dot(4));
    await _afterSwitch(tester);
    expect(_count(tester), '5 من 7 · الأقرب أولاً');
    expect(find.text('كاميرا فوجي X-T20'), findsOneWidget);
    expect(_pinY(tester, 21.541, 39.173), closeTo(.42, .02));
  });

  testWidgets('dots show at most seven with a window that slides with the current card', (tester) async {
    expect(dotWindowStart(5, 4), 0);
    expect(dotWindowStart(7, 6), 0);
    expect(dotWindowStart(12, 0), 0);
    expect(dotWindowStart(12, 3), 0);
    expect(dotWindowStart(12, 4), 1, reason: 'الحالية في الوسط');
    expect(dotWindowStart(12, 8), 5);
    expect(dotWindowStart(12, 11), 5, reason: 'آخر نافذة');
    final items = [for (var i = 0; i < 12; i++) RowItem(kind: 'moment', id: 'm$i', title: 'لحظة $i', lat: 21.5, lng: 39.1)];
    var index = 0;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(locale: const Locale('ar'), home: StatefulBuilder(builder: (context, setState) {
      set = setState;
      return Scaffold(body: RowDeck(items: items, index: index, onIndex: (i) => setState(() => index = i), onAct: _noopItem));
    })));
    int shown() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('row-dot-') && (w.key as ValueKey<String>).value != 'row-dot-on').evaluate().length;
    expect(shown(), 7);
    expect(find.byKey(const Key('row-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('row-dot-7')), findsNothing);
    set(() => index = 8);
    await tester.pump(const Duration(milliseconds: 700));
    expect(shown(), 7);
    expect(find.byKey(const Key('row-dot-4')), findsNothing);
    expect(find.byKey(const Key('row-dot-5')), findsOneWidget);
    expect(find.byKey(const Key('row-dot-11')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('row-dot-8')), matching: find.byKey(const Key('row-dot-on'))), findsOneWidget);
    // بطاقة واحدة: لا نقاط والمكان محجوز
    await tester.pumpWidget(MaterialApp(locale: const Locale('ar'), home: Scaffold(body: RowDeck(items: items.sublist(0, 1), index: 0, onIndex: _noop, onAct: _noopItem))));
    await tester.pump(const Duration(milliseconds: 700));
    expect(shown(), 0);
    expect(tester.getSize(find.byKey(const Key('row-dots'))).height, RowDeck.dotsHeight);
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

  testWidgets('tapping anywhere on the card opens its journey, and the deck sits just above the pill nav', (tester) async {
    await _pump(tester);
    // لمسة على نص البطاقة (لا على الزر)
    await tester.tap(find.byKey(const Key('row-card')));
    await _settle(tester, 3);
    expect(find.byType(CircleOffersPage), findsOneWidget);
  });

  testWidgets('JoyNavBar.inset reads the system inset, not the Scaffold padding that extendBody adds', (tester) async {
    double? inset;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(bottom: 100), viewPadding: EdgeInsets.only(bottom: 20)),
      child: Builder(builder: (context) { inset = JoyNavBar.inset(context); return const SizedBox(); }),
    ));
    expect(inset, JoyNavBar.height + JoyNavBar.margin + 20);
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

    Future<void> next() => _next(tester);

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

  testWidgets('a «here today» circle card shows its label, «زيارة» opens the business page, and an unknown kind gets the default card', (tester) async {
    final until = DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String();
    await _pump(tester, srv: _Srv()..items = [
      {'kind': 'circle', 'id': 'biz-here', 'refId': 'biz-here', 'title': 'عربة قهوة سارة', 'subtitle': 'هنا اليوم حتى 18:30 · مقهى', 'who': '', 'logoUrl': null, 'imageUrl': null, 'lat': 21.545, 'lng': 39.175, 'distanceKm': 0.3, 'act': 'زيارة', 'payload': {'here': true, 'until': until, 'category': 'cafe'}},
      {'kind': 'hologram', 'id': 'h1', 'title': 'نوع من المستقبل', 'subtitle': 'لا يعرفه التطبيق بعد', 'lat': 21.546, 'lng': 39.176, 'distanceKm': 0.5},
    ]);
    expect(_count(tester), '1 من 2 · الأقرب أولاً');
    expect(find.text('هنا اليوم'), findsOneWidget);
    expect(find.text('عربة قهوة سارة'), findsWidgets);
    expect(find.descendant(of: find.byKey(const Key('row-act')), matching: find.text('زيارة')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('row-dist'))).data, '300 م');
    // دبّوس احتياطي بمفتاح طبقة الدوائر يُبرز ويحمل شارة الساعة من الحمولة
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    expect(find.byKey(const Key('map-here-badge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-act')));
    await _settle(tester, 3);
    expect(tester.widget<BusinessPage>(find.byType(BusinessPage)).id, 'biz-here');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await _settle(tester, 3);
    // النوع غير المعروف: بطاقة افتراضية بتسمية «لحظة» وزر «شاهد» لا يفعل شيئاً، والصف لم يسقط
    await _next(tester);
    expect(_count(tester), '2 من 2 · الأقرب أولاً');
    expect(find.text('نوع من المستقبل'), findsOneWidget);
    expect(find.text('لحظة'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('row-act')), matching: find.text('شاهد')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-act')));
    await _settle(tester, 2);
    expect(find.byType(MapPage), findsOneWidget);
    expect(find.byType(BusinessPage), findsNothing);
  });

  testWidgets('a guest home map requests /row and nothing private, sees the deck, and the bell asks to sign in', (tester) async {
    final srv = await _pump(tester, signedIn: false);
    expect(srv.calls, contains('GET /row'));
    expect(srv.calls, contains('GET /mapposts'));
    expect(srv.denied, isEmpty, reason: 'مسارات حساب طُلبت بلا جلسة: ${srv.denied}');
    expect(find.byKey(const Key('row-card')), findsOneWidget);
    expect(find.text('خصم ٢٠٪ على اللاتيه'), findsOneWidget);
    // «أنا هنا» للزائر دعوة إلى الدخول، لا ورقة موقع
    await tester.tap(find.byKey(const Key('map-here')));
    await _settle(tester, 2);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.byKey(const Key('map-here-sheet')), findsNothing);
    expect(find.byKey(const Key('map-here-visibility')), findsNothing);
    Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
    await _settle(tester, 2);
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
    expect(find.byKey(const Key('row-dots')), findsNothing);
    expect(find.byKey(const Key('row-filter-empty')), findsNothing, reason: 'لا رقاقة مختارة');
    // زر «تحديث» أُزيل: العودة إلى التطبيق تعيد الجلب، والصف صار فيه عناصر بلا موقع
    srv.items = _items().sublist(0, 2);
    srv.located = false;
    final layers = srv.calls.where((c) => c == 'GET /mapposts').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, 3);
    expect(srv.calls.where((c) => c == 'GET /mapposts').length, layers + 1, reason: 'وطبقات الخريطة معه كما كان زر التحديث يفعل');
    expect(_count(tester), '1 من 2 · الأحدث أولاً');
  });

  testWidgets('a chip filters the cards and the pins together; tapping it again or «الكل» restores everything', (tester) async {
    await _pump(tester);
    expect(_markers(tester).length, 7);
    expect(tester.getSemantics(find.byKey(const Key('map-chip-all'))).flagsCollection.isSelected.toBoolOrNull(), isTrue);
    await tester.tap(find.byKey(const Key('map-chip-event')));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 1 · الأقرب أولاً');
    expect(find.descendant(of: find.byKey(const Key('row-card')), matching: find.text('بازار الحي')), findsOneWidget);
    expect(_markers(tester).length, 1, reason: 'دبابيس الفعاليات فقط');
    expect(_pinIcon(Icons.event_rounded), findsOneWidget);
    expect(_pinIcon(Icons.work_rounded), findsNothing);
    expect(_pinY(tester, 21.543, 39.172), closeTo(.42, .02), reason: 'الخريطة تبعت أول بطاقة من النوع');
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    // عروض: بطاقتان ودبّوسان (دبّوس الطبقة والصف بمفتاح واحد)
    await tester.tap(find.byKey(const Key('map-chip-offer')));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 2 · الأقرب أولاً');
    expect(_markers(tester).length, 2);
    expect(_pinIcon(Icons.local_offer_rounded), findsNWidgets(2));
    expect(_pinIcon(Icons.event_rounded), findsNothing);
    await _next(tester);
    expect(find.descendant(of: find.byKey(const Key('row-card')), matching: find.text('قهوة اليوم بنصف السعر')), findsOneWidget);
    await _next(tester);
    expect(_count(tester), '1 من 2 · الأقرب أولاً', reason: 'الدوران داخل النوع المختار');
    // لحظات: المنشور من طبقة الخريطة ومن الصف
    await tester.tap(find.byKey(const Key('map-chip-moment')));
    await _afterSwitch(tester);
    expect(_count(tester), '1 من 2 · الأقرب أولاً');
    expect(_markers(tester).length, 2);
    // لمس الرقاقة المختارة مرة ثانية يعيد «الكل»، والبطاقة المختارة تبقى
    await tester.tap(find.byKey(const Key('map-chip-moment')));
    await _afterSwitch(tester);
    expect(_count(tester), '2 من 7 · الأقرب أولاً');
    expect(_markers(tester).length, 7);
    await tester.tap(find.byKey(const Key('map-chip-job')));
    await _afterSwitch(tester);
    expect(_markers(tester).length, 1);
    expect(_pinIcon(Icons.work_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-chip-all')));
    await _afterSwitch(tester);
    expect(_count(tester), '4 من 7 · الأقرب أولاً');
    expect(_markers(tester).length, 7);
  });

  testWidgets('a chip with nothing nearby shows «لا شيء من هذا النوع قريب منك», and «وسّع البحث» clears the filter', (tester) async {
    await _pump(tester, srv: _Srv()..items = _items().sublist(0, 3));
    await tester.tap(find.byKey(const Key('map-chip-listing')));
    await _afterSwitch(tester);
    expect(find.byKey(const Key('row-filter-empty')), findsOneWidget);
    expect(find.text('لا شيء من هذا النوع قريب منك'), findsOneWidget);
    expect(find.byKey(const Key('row-card')), findsNothing);
    expect(find.byKey(const Key('row-empty')), findsNothing);
    expect(find.byKey(const Key('row-skeleton')), findsNothing);
    expect(_markers(tester), isEmpty, reason: 'لا دبابيس من هذا النوع');
    expect(find.byKey(const Key('map-pin-selected')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('row-widen')), matching: find.text('وسّع البحث')), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-widen')));
    await _afterSwitch(tester);
    expect(find.byKey(const Key('row-filter-empty')), findsNothing);
    expect(_count(tester), '1 من 3 · الأقرب أولاً');
    expect(_markers(tester).length, 3);
    expect(tester.getSemantics(find.byKey(const Key('map-chip-all'))).flagsCollection.isSelected.toBoolOrNull(), isTrue);
  });

  testWidgets('«أنا هنا» opens one sheet that reaches both «هنا الآن» and show/hide my location', (tester) async {
    final srv = await _pump(tester, srv: _Srv()..presence = {'lat': 21.54, 'lng': 39.17, 'visible': false, 'title': ''});
    await tester.tap(find.byKey(const Key('map-here')));
    await _settle(tester, 3);
    expect(find.byKey(const Key('map-here-sheet')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('map-here-now')), matching: find.text('هنا الآن')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('map-here-visibility')), matching: find.text('إظهار موقعي')), findsOneWidget);
    // إظهار موقعي: الطلب القائم نفسه
    await tester.tap(find.byKey(const Key('map-here-visibility')));
    await _settle(tester, 3);
    expect(srv.presencePuts, [{'visible': true}]);
    expect(find.text('أصبحت ظاهراً على الخريطة'), findsOneWidget);
    expect(find.byKey(const Key('map-here-sheet')), findsNothing);
    // الورقة تعكس الحالة الجديدة، وإخفاؤه من المكان نفسه
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const Key('map-here')));
    await _settle(tester, 3);
    expect(find.descendant(of: find.byKey(const Key('map-here-visibility')), matching: find.text('إخفاء موقعي')), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-here-visibility')));
    await _settle(tester, 3);
    expect(srv.presencePuts.last, {'visible': false});
    await tester.pump(const Duration(seconds: 4));
    // «هنا الآن»: الخريطة تذهب إلى موقع الجهاز وتُفتح قائمة النشر القائمة عند هذه النقطة
    await tester.tap(find.byKey(const Key('map-here')));
    await _settle(tester, 3);
    await tester.tap(find.byKey(const Key('map-here-now')));
    await _settle(tester, 4);
    expect(find.text('عند هذه النقطة'), findsOneWidget);
    expect(find.text('أنا هنا الآن'), findsOneWidget);
    expect(find.text('دبوس'), findsOneWidget);
    final cam = _camera(tester);
    expect(cam.zoom, 16);
    expect(cam.center.latitude, closeTo(21.5433, 1e-6));
    expect(cam.center.longitude, closeTo(39.1728, 1e-6));
  });

  testWidgets('«ابحث في هذه المنطقة» appears only after the user moves the map away, reloads the row for the map centre and hides', (tester) async {
    final srv = await _pump(tester);
    expect(srv.rowQueries.single['lat'], '21.5433', reason: 'الصف لموقع المستخدم افتراضياً');
    Finder area() => find.byKey(const Key('map-search-area'));
    // تتبّع البطاقة حركة برمجية: لا زر
    await _next(tester);
    expect(area(), findsNothing);
    // سحب قصير لا يُعدّ ابتعاداً
    final at = tester.getCenter(find.byType(FlutterMap)) + const Offset(0, 120);
    await tester.dragFrom(at, const Offset(0, 60));
    await _settle(tester, 2);
    expect(area(), findsNothing);
    // سحب ملحوظ: الزر يظهر تحت الرقائق
    await tester.dragFrom(at, const Offset(0, 400));
    await _settle(tester, 2);
    expect(area(), findsOneWidget);
    expect(find.descendant(of: area(), matching: find.text('ابحث في هذه المنطقة')), findsOneWidget);
    expect(tester.getTopLeft(area()).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('map-chip-all'))).dy));
    final center = _camera(tester).center;
    expect(const Distance().as(LengthUnit.Meter, const LatLng(21.5433, 39.1728), center), greaterThan(500));
    // تحديث دوري أثناء التجوّل لا يعيد الخريطة إلى البطاقة ولا يغيّر مركز الصف
    await tester.pump(_MapRefresh.every);
    await _settle(tester);
    expect(srv.rowQueries.length, 2);
    expect(srv.rowQueries.last['lat'], '21.5433');
    expect(_camera(tester).center.latitude, closeTo(center.latitude, 1e-9));
    expect(area(), findsOneWidget);
    // اللمس: جلب الصف لمركز الخريطة، والزر يختفي
    await tester.tap(area());
    await _settle(tester);
    expect(srv.rowQueries.length, 3);
    expect(double.parse(srv.rowQueries.last['lat']!), closeTo(center.latitude, 1e-9));
    expect(double.parse(srv.rowQueries.last['lng']!), closeTo(center.longitude, 1e-9));
    expect(srv.rowQueries.last['radiusKm'], '15');
    expect(area(), findsNothing);
    expect(_count(tester), '2 من 7 · الأقرب أولاً');
    // التحديث التالي يبقى على المنطقة المختارة
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(double.parse(srv.rowQueries.last['lat']!), closeTo(center.latitude, 1e-9));
    // «موقعي» يعود إلى موقع المستخدم والصف لمنطقة أخرى: الزر يظهر بلا سحب
    await tester.tap(find.byKey(const Key('map-locate')));
    await _settle(tester);
    expect(area(), findsOneWidget);
    await tester.tap(area());
    await _settle(tester);
    expect(double.parse(srv.rowQueries.last['lat']!), closeTo(21.5433, 1e-6));
    expect(area(), findsNothing);
  });

  testWidgets('zoomed out, the neighbours under the shown card pin become a «+N» badge on it; tapping the badge zooms in until they separate', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('map-cluster')), findsNothing);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(FlutterMap))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
    await _settle(tester, 3);
    // دبّوس واحد على الخريطة: المختار وعليه عدد الستة الباقين (لا دائرة تحته يغطيها)
    expect(_markers(tester).length, 1);
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('map-cluster')), matching: find.text('+6')), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-cluster')));
    await _settle(tester, 3);
    expect(find.byKey(const Key('map-cluster')), findsNothing);
    expect(_markers(tester).length, 7);
    expect(_count(tester), '1 من 7 · الأقرب أولاً', reason: 'البطاقة المعروضة لم تتغير');
  });

  testWidgets('crowded pins merge into a dark circle with the count when zoomed out; the shown card keeps its own larger pin; tapping the cluster zooms in', (tester) async {
    // البطاقة الأولى أبعد قليلاً عن البقية حتى لا يغطي دبّوسها الكبير دائرة المجموعة عند التصغير
    final items = [
      {'kind': 'listing', 'id': 'far-1', 'refId': 'far-1', 'title': 'دراجة أطفال', 'subtitle': '120 ر.س', 'who': 'خالد', 'lat': 21.561, 'lng': 39.171, 'distanceKm': 0.2, 'act': 'اطلب', 'payload': {}},
      ..._items(),
    ];
    await _pump(tester, srv: _Srv()..items = items);
    expect(find.byKey(const Key('map-cluster')), findsNothing, reason: 'عند تكبير التتبع الدبابيس متباعدة');
    // الدبّوس المختار أكبر ويُرسم آخراً (فوق البقية)
    final sel = tester.getSize(find.byKey(const Key('map-pin-selected')));
    expect(sel.width, 44);
    expect(tester.getSize(find.ancestor(of: _pinIcon(Icons.work_rounded), matching: find.byType(Container)).first).width, 32);
    expect(_markers(tester).last.point, const LatLng(21.561, 39.171));
    expect(_markers(tester).last.alignment, Alignment.topCenter, reason: 'رأس المؤشر عند الإحداثية');
    // تصغير بعجلة الفأرة ثلاثة مستويات
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final mid = tester.getCenter(find.byType(FlutterMap));
    await tester.sendEventToBinding(pointer.hover(mid));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
    await _settle(tester, 3);
    final z = _camera(tester).zoom;
    expect(z, lessThan(13.5));
    expect(find.byKey(const Key('map-cluster')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('map-cluster')), matching: find.text('7')), findsOneWidget);
    expect(_markers(tester).length, 2);
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget, reason: 'دبّوس البطاقة المعروضة لا يدخل المجموعة');
    expect(_pinIcon(Icons.work_rounded), findsNothing);
    // لمس المجموعة يقرّب عليها
    await tester.tap(find.byKey(const Key('map-cluster')));
    await _settle(tester, 3);
    expect(_camera(tester).zoom, greaterThanOrEqualTo(z + 1), reason: 'تقريب على المجموعة');
    expect(find.byKey(const Key('map-cluster')), findsNothing, reason: 'تفرّقت المجموعة من لمسة واحدة');
    expect(_markers(tester).length, 8);
    expect(_pinIcon(Icons.work_rounded), findsOneWidget);
    final b = _camera(tester).visibleBounds;
    for (final m in _items()) {
      expect(b.contains(LatLng(m['lat'] as double, m['lng'] as double)), isTrue, reason: 'عناصر المجموعة كلها ضمن الشاشة');
    }
    expect(find.byKey(const Key('map-search-area')), findsNothing, reason: 'تقريب برمجي لا يعرض زر المنطقة');
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
    await tester.drag(find.byKey(const Key('row-card')), const Offset(-140, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(index, 1);
    expect(find.byKey(const Key('row-card')), findsOneWidget, reason: 'بطاقة واحدة بعد انتهاء الانزلاق');
    await tester.tap(find.byKey(const Key('row-act')));
    expect(acted?.id, _pid);
  });

  testWidgets('the pill nav is fixed to six tabs with the camera in the middle; HomeShell maps them', (tester) async {
    int? picked;
    var composed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: JoyNavBar(tabs: navTabIds, index: 0, onSelect: (i) => picked = i, onCompose: () => composed++, badges: const {'chats': 3}))));
    expect(navTabIds, ['home', 'circles', 'market', 'events', 'chats', 'me']);
    for (final l in ['الخريطة', 'الدوائر', 'السوق', 'استكشف', 'المحادثات', 'ماي سبيس']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('3'), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('nav-compose'))).dx, closeTo(400, 0.5), reason: 'الكاميرا في المنتصف');
    await tester.tap(find.byKey(const Key('nav-chats')));
    expect(picked, 4);
    await tester.tap(find.byKey(const Key('nav-market')));
    expect(picked, 2);
    await tester.tap(find.byKey(const Key('nav-compose')));
    expect(composed, 1);
    expect(HomeShell.pageOf('home'), isA<MapPage>().having((m) => m.home, 'home', isTrue));
    expect(HomeShell.pageOf('market'), isA<MarketPage>().having((m) => m.barActions.length, 'barActions', 1));
    expect(HomeShell.pageOf('events'), isA<ExplorePage>().having((m) => m.barActions.length, 'barActions', 1));
    expect(HomeShell.ownBar('home'), isTrue);
    expect(HomeShell.ownBar('market'), isTrue, reason: 'شريط السوق وحده لا شريطان');
    expect(HomeShell.ownBar('events'), isTrue);
    expect(HomeShell.ownBar('chats'), isFalse);
  });
}

void _noop(int _) {}
void _noopItem(RowItem _) {}
