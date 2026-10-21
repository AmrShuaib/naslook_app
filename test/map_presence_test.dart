// حضور الدوائر على الخريطة (حزمة تسجيل الدوائر الموثّقة): الدائرة المتنقلة بمنطقة خدمة تُرسم قرصاً شفافاً بنصف قطرها
// بالأمتار بلا دبّوس، والدائرة بدبّوس «هنا اليوم» تظهر عند موقع الدبّوس بشارة ساعة وتلميح بالوقت، والدبّوس المنتهي
// يُهمل، ولمس الدبّوس أو القرص يفتح ورقة الدائرة كالمعتاد؛ وفي الرئيسية بطاقة «هنا اليوم» في الصف يفوز دبّوس الطبقة
// على دبّوسها الاحتياطي حين تكون الدائرة ضمن الحدود، ويبقى الاحتياطي بشارته حين تغيب الطبقة. القائمة والحضور يأتيان من
// طلب `/biz` واحد لكل حدود، فلا يظهر دبّوس عند مركز المتنقلة أو عند موقع الدائرة الأصلي في الإطار الذي تصل فيه الدوائر.
import 'dart:async';
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
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _until = DateTime.now().add(const Duration(hours: 3));
final _expired = DateTime.now().subtract(const Duration(hours: 1));

Map<String, dynamic> _biz(String id, String name, double lat, double lng, {String category = 'cafe', Map<String, dynamic> extra = const {}}) => {
      'id': id, 'name': id, 'nameAr': name, 'category': category, 'sector': '', 'description': '', 'lat': lat, 'lng': lng, 'hours': '', 'verified': false,
      'followers': 0, 'rating': null, 'ratingCount': 0, 'itemsCount': 0, 'active': true, ...extra,
    };

/// أربع دوائر: متنقلة بمنطقة خدمة 5 كم، ثابتة بدبّوس «هنا اليوم» ساري بعيداً عن موقعها، ثابتة بدبّوس منتهٍ، وثابتة عادية.
List<Map<String, dynamic>> _circles() => [
      _biz('biz-mobile', 'ورشة خالد المتنقلة', 21.56, 39.17, category: 'services', extra: {'presence': 'mobile', 'serviceArea': {'lat': 21.56, 'lng': 39.17, 'radiusKm': 5, 'districts': ['الزهراء']}, 'here': null}),
      _biz('biz-here', 'عربة قهوة سارة', 21.50, 39.10, extra: {'presence': 'fixed', 'serviceArea': null, 'here': {'lat': 21.545, 'lng': 39.175, 'until': _until.toUtc().toIso8601String()}}),
      _biz('biz-expired', 'بوفيه أحمد', 21.55, 39.18, extra: {'presence': 'fixed', 'here': {'lat': 21.53, 'lng': 39.16, 'until': _expired.toUtc().toIso8601String()}}),
      _biz('biz-plain', 'مطعم البيك', 21.54, 39.165),
    ];

Map<String, dynamic> _circleRow() => {
      'kind': 'circle', 'id': 'biz-here', 'refId': 'biz-here', 'title': 'عربة قهوة سارة', 'subtitle': 'هنا اليوم حتى 18:30 · مقهى', 'who': '', 'logoUrl': null, 'imageUrl': null,
      'lat': 21.545, 'lng': 39.175, 'distanceKm': 0.3, 'act': 'زيارة', 'payload': {'here': true, 'until': _until.toUtc().toIso8601String(), 'category': 'cafe'},
    };

class _Srv {
  final calls = <String>[];
  /// استعلامات `/biz` (الحدود) بترتيبها: طلب واحد لكل حدود، لا طلب للقائمة وآخر للحضور.
  final bizQueries = <String>[];
  /// إن وُجد يُحجز رد `/biz` حتى يكتمل، لفحص الإطار الذي تصل فيه الدوائر.
  Completer<void>? bizGate;
  List<Map<String, dynamic>> circles = _circles();
  List<Map<String, dynamic>> row = const [];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /biz':
        bizQueries.add(req.url.query);
        if (bizGate != null) await bizGate!.future;
        return _json(circles);
      case 'GET /row':
        return _json({'items': row, 'located': true});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false, 'jobsEnabled': false});
      case 'GET /live/wait':
        return _json({'seq': 0, 'events': [], 'reset': false});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {bool home = false, _Srv? srv}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: Scaffold(body: MapPage(home: home))),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// طبقة الدبابيس الأولى هي طبقة العناصر (طبقة الأسماء بعدها لها MarkerLayer خاصة بها).
List<Marker> _markers(WidgetTester t) => t.widget<MarkerLayer>(find.byType(MarkerLayer).first).markers;
int _markersAt(WidgetTester t, double lat, double lng) => _markers(t).where((m) => (m.point.latitude - lat).abs() < 1e-6 && (m.point.longitude - lng).abs() < 1e-6).length;

void main() {
  tearDown(() {
    ApiClient.onUnauthorized = null;
  });

  group('BizPresence', () {
    test('parses mobile areas and active here pins, ignores fixed circles without a pin and bad radii', () {
      final mobile = BizPresence.fromJson(_circles()[0])!;
      expect(mobile.mobile, isTrue);
      expect(mobile.area, isNotNull);
      expect(mobile.area!.radiusKm, 5);
      expect(mobile.here, isNull);
      final here = BizPresence.fromJson(_circles()[1])!;
      expect(here.mobile, isFalse);
      expect(here.here!.lat, 21.545);
      expect(here.here!.until.difference(_until).inSeconds.abs(), lessThan(1));
      expect(BizPresence.fromJson(_circles()[3]), isNull, reason: 'ثابتة بلا دبّوس مؤقت لا تُحفظ');
      expect(BizPresence.fromJson({'id': 'x', 'presence': 'mobile', 'serviceArea': {'lat': 21.5, 'lng': 39.1, 'radiusKm': 0}})!.area, isNull, reason: 'نصف قطر صفر يُهمل');
      expect(BizPresence.fromJson({'presence': 'mobile'}), isNull, reason: 'بلا معرّف');
      expect(hereUntilLabel(DateTime(2026, 10, 21, 18, 30)), 'هنا اليوم حتى 18:30');
      expect(hereUntilLabel(DateTime(2026, 10, 21, 9, 5)), 'هنا اليوم حتى 09:05');
    });
  });

  testWidgets('a mobile circle is a translucent service-area disc without a pin; a here-pinned circle sits at its pin with a clock badge; expired pins are ignored', (tester) async {
    final srv = await _pump(tester);
    expect(srv.bizQueries, isNotEmpty);
    expect(srv.bizQueries.toSet().length, srv.bizQueries.length, reason: 'طلب /biz واحد لكل حدود: القائمة والحضور من حمولة واحدة');
    // القرص: دائرة واحدة بنصف قطر 5 كم بالأمتار عند مركز المنطقة
    final layer = tester.widget<CircleLayer<String>>(find.byKey(const Key('map-service-areas')));
    expect(layer.circles.length, 1);
    expect(layer.circles.single.radius, 5000);
    expect(layer.circles.single.useRadiusInMeter, isTrue);
    expect(layer.circles.single.hitValue, 'biz-mobile');
    expect(layer.circles.single.point.latitude, closeTo(21.56, 1e-9));
    // المتنقلة بلا دبّوس، والدبّوس المؤقت عند موقعه لا موقع الدائرة، والمنتهي يُهمل فتبقى الدائرة عند موقعها
    expect(_markersAt(tester, 21.56, 39.17), 0, reason: 'المتنقلة بلا دبّوس');
    expect(_markersAt(tester, 21.545, 39.175), 1, reason: 'دبّوس «هنا اليوم» عند موقعه المؤقت');
    expect(_markersAt(tester, 21.50, 39.10), 0, reason: 'لا دبّوس عند موقع الدائرة الأصلي ما دام الدبّوس المؤقت سارياً');
    expect(_markersAt(tester, 21.53, 39.16), 0, reason: 'الدبّوس المنتهي يُهمل');
    expect(_markersAt(tester, 21.55, 39.18), 1, reason: 'الدائرة ذات الدبّوس المنتهي تعود إلى موقعها');
    expect(_markersAt(tester, 21.54, 39.165), 1);
    // شارة واحدة وتلميح بالوقت المحلي
    expect(find.byKey(const Key('map-here-badge')), findsOneWidget);
    expect(find.byTooltip(hereUntilLabel(_until)), findsOneWidget);
  });

  testWidgets('the circle list and the presence land in the same frame from one /biz payload', (tester) async {
    final srv = _Srv()..bizGate = Completer<void>();
    await _pump(tester, srv: srv);
    // الرد محجوز: طلب واحد لكل حدود (الحدود تتغيّر عند الإقلاع ثم عند الانتقال إلى موقع الجهاز) ولا دوائر ولا أقراص بعد
    expect(srv.bizQueries, isNotEmpty);
    expect(srv.bizQueries.toSet().length, srv.bizQueries.length);
    expect(find.byKey(const Key('map-service-areas')), findsNothing);
    expect(_markersAt(tester, 21.545, 39.175), 0);
    expect(_markersAt(tester, 21.54, 39.165), 0);
    srv.bizGate!.complete();
    // الرد يمرّ بعدة خطوات غير متزامنة، فنلتقط أول إطار تظهر فيه أي دائرة ونفحصه
    const spots = [(21.56, 39.17), (21.50, 39.10), (21.545, 39.175), (21.54, 39.165)];
    bool anyCircle() => find.byKey(const Key('map-service-areas')).evaluate().isNotEmpty || spots.any((s) => _markersAt(tester, s.$1, s.$2) > 0);
    for (var i = 0; i < 20 && !anyCircle(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // الإطار الذي تصل فيه الدوائر يحمل القرص والدبّوس المؤقت معاً: لا دبّوس عند مركز المتنقلة ولا عند موقع الدائرة الأصلي
    expect(find.byKey(const Key('map-service-areas')), findsOneWidget);
    expect(_markersAt(tester, 21.56, 39.17), 0, reason: 'لا دبّوس عند مركز المتنقلة قبل القرص');
    expect(_markersAt(tester, 21.50, 39.10), 0, reason: 'لا دبّوس عند موقع الدائرة الأصلي قبل القفز إلى «هنا اليوم»');
    expect(_markersAt(tester, 21.545, 39.175), 1);
    expect(_markersAt(tester, 21.54, 39.165), 1);
    expect(srv.bizQueries.toSet().length, srv.bizQueries.length, reason: 'لا طلب ثانٍ للحضور');
  });

  testWidgets('tapping the here pin opens the circle sheet like any circle pin', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip(hereUntilLabel(_until)));
    await _settle(tester, 3);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('دخول الدائرة والشراء'), findsOneWidget);
  });

  testWidgets('tapping inside the service area opens the mobile circle sheet', (tester) async {
    await _pump(tester);
    final cam = MapCamera.of(tester.element(find.byType(MarkerLayer).first));
    final at = tester.getTopLeft(find.byType(FlutterMap)) + cam.latLngToScreenOffset(const LatLng(21.56, 39.17));
    await tester.tapAt(at);
    await _settle(tester, 3);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('ورشة خالد المتنقلة')), findsOneWidget);
    expect(find.text('دخول الدائرة والشراء'), findsOneWidget);
  });

  testWidgets('home: the row «here today» card highlights the layer pin (no duplicate) and keeps a fallback pin with the badge when the layer lacks the circle', (tester) async {
    await _pump(tester, home: true, srv: _Srv()..row = [_circleRow()]);
    expect(find.text('هنا اليوم'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('row-act')), matching: find.text('زيارة')), findsOneWidget);
    expect(_markersAt(tester, 21.545, 39.175), 1, reason: 'دبّوس الطبقة والاحتياطي بمفتاح واحد فلا تكرار');
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    expect(find.byKey(const Key('map-here-badge')), findsOneWidget);
    // بلا طبقة دوائر: الدبّوس الاحتياطي من الصف يحمل الشارة من الحمولة
    await _pump(tester, home: true, srv: _Srv()..row = [_circleRow()]..circles = []);
    expect(_markersAt(tester, 21.545, 39.175), 1);
    expect(find.byKey(const Key('map-pin-selected')), findsOneWidget);
    expect(find.byKey(const Key('map-here-badge')), findsOneWidget);
    expect(find.byKey(const Key('map-service-areas')), findsNothing);
  });
}
