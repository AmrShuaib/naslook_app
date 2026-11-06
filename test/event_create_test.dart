// مكان الفعالية: موقع الجهاز افتراضياً، و«حدد على الخريطة» ينقل النقطة، والمرسل إلى POST /events هو النقطة المختارة مع اسم المكان،
// وبلا موقع للجهاز ولا حضور على الخريطة لا تُرسل إحداثيات وتُشرح أخطاء الخادم بالعربية. موقع GPS المتأخر لا يستبدل ما حدده المنشئ،
// و«إنشاء» أثناء التحديد ينتظر الموقع، والتذكرة المدفوعة تطلب إقرار 18+ قبل الإنشاء.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/map_pick_page.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _device = LatLng(21.6012, 39.1068);

class _Srv {
  final calls = <String>[];
  Map<String, dynamic>? created;
  String? failWith;
  bool adult = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> _event(Map<String, dynamic> b) => {
        'id': 'ev-1', 'host': {'id': 'SA0000001', 'nickname': 'amr'}, 'title': b['title'], 'description': b['description'] ?? '', 'startsAt': b['startsAt'], 'placeName': b['placeName'],
        'lat': b['lat'], 'lng': b['lng'], 'cancelled': false, 'isHost': true, 'going': 0, 'myTickets': 0,
        'tiers': [{'id': 't1', 'name': 'عادي', 'description': '', 'price': 0, 'quantity': 50, 'sold': 0, 'left': 50}],
      };
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (key == 'GET /events') return _json(created == null ? [] : [_event(created!)]);
    if (key == 'POST /events') {
      if (failWith != null) return _json({'error': failWith}, 400);
      created = jsonDecode(req.body) as Map<String, dynamic>;
      return _json(_event(created!));
    }
    if (key == 'GET /events/ev-1') return _json(_event(created!));
    if (key == 'GET /me/map-presence') return _json({'visible': false});
    if (key == 'GET /legal/consent') return _json({'needs': false, 'version': '2026-09-25', 'adult': adult});
    if (key == 'POST /me/adult-attest') {
      adult = true;
      return _json({'ok': true, 'adult': true});
    }
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: EventsPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('events-create')));
  await _settle(tester);
  expect(find.text('فعالية جديدة'), findsOneWidget);
}

String _source(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('ev-location-source'))).data!;

/// يضغط على الخريطة بعيداً عن مركزها ويؤكد، ويعيد النقطة المتوقعة.
Future<LatLng> _pickAway(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ev-pick-map')));
  await _settle(tester);
  expect(find.byType(MapPickPage), findsOneWidget);
  final map = find.byKey(const Key('map-pick-map'));
  final cam = MapCamera.of(tester.element(find.byType(MarkerLayer).first));
  final target = tester.getCenter(map) + const Offset(-120, -160);
  final expected = cam.screenOffsetToLatLng(target - tester.getTopLeft(map));
  await tester.tapAt(target);
  // الخريطة تنتظر مهلة النقر المزدوج قبل أن تعدّها ضغطة واحدة
  await _settle(tester);
  await tester.tap(find.byKey(const Key('map-pick-confirm')));
  await _settle(tester);
  expect(find.byType(MapPickPage), findsNothing);
  return expected;
}

void main() {
  tearDown(() {
    DeviceLocation.override = null;
    DeviceLocation.last = null;
    DeviceLocation.resetForTest();
  });

  testWidgets('device location is the default point and is sent with the place name', (tester) async {
    DeviceLocation.override = () async => _device;
    final srv = await _pump(tester);
    await _openForm(tester);
    expect(_source(tester), 'موقعك الحالي');
    expect(find.byKey(const Key('ev-pick-map')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ev-title')), 'أمسية شعرية');
    await tester.enterText(find.byKey(const Key('ev-place')), 'ممشى الكورنيش');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(srv.created!['lat'], _device.latitude);
    expect(srv.created!['lng'], _device.longitude);
    expect(srv.created!['placeName'], 'ممشى الكورنيش');
    // بعد الإنشاء تُفتح صفحة الفعالية
    expect(find.text('الفعالية'), findsOneWidget);
    expect(srv.calls, contains('GET /events/ev-1'));
    expect(srv.calls, isNot(contains('GET /legal/consent')), reason: 'الفعالية المجانية لا تطلب إقرار العمر');
  });

  testWidgets('«حدد على الخريطة» moves the point away from the device location', (tester) async {
    DeviceLocation.override = () async => _device;
    final srv = await _pump(tester);
    await _openForm(tester);
    await tester.tap(find.byKey(const Key('ev-pick-map')));
    await _settle(tester);
    expect(find.byType(MapPickPage), findsOneWidget);
    expect(find.text('مكان الفعالية'), findsOneWidget);
    // ضغطة على الخريطة بعيداً عن المركز تضع الدبوس هناك
    final map = find.byKey(const Key('map-pick-map'));
    final cam = MapCamera.of(tester.element(find.byType(MarkerLayer).first));
    final target = tester.getCenter(map) + const Offset(-120, -160);
    final expected = cam.screenOffsetToLatLng(target - tester.getTopLeft(map));
    await tester.tapAt(target);
    // الخريطة تنتظر مهلة النقر المزدوج قبل أن تعدّها ضغطة واحدة
    await _settle(tester);
    await tester.tap(find.byKey(const Key('map-pick-confirm')));
    await _settle(tester);
    expect(find.byType(MapPickPage), findsNothing);
    expect(_source(tester), 'نقطة حددتها على الخريطة');
    // «موقعي الحالي» يظهر للعودة إلى موقع الجهاز
    expect(find.byKey(const Key('ev-use-device')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ev-title')), 'سوق ليلي');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    final lat = srv.created!['lat'] as double, lng = srv.created!['lng'] as double;
    expect(lat, isNot(_device.latitude));
    expect(lat, closeTo(expected.latitude, 1e-6));
    expect(lng, closeTo(expected.longitude, 1e-6));
  });

  testWidgets('without device location or presence no coordinates are sent and errors read in Arabic', (tester) async {
    DeviceLocation.override = () async => null;
    final srv = await _pump(tester);
    await _openForm(tester);
    await _settle(tester);
    expect(_source(tester), 'لم يُحدَّد موقع بعد');
    expect(find.text('حدده على الخريطة ليظهر مكان الفعالية للناس'), findsOneWidget);
    srv.failWith = 'place-required';
    srv.adult = true; // أقرّ بعمره من قبل: يصل الطلب إلى الخادم
    await tester.enterText(find.byKey(const Key('ev-title')), 'ورشة');
    await tester.enterText(find.byKey(const Key('ev-tier-price')), '50');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(find.text('التذكرة المدفوعة لفعالية في مكان: اكتب اسم المكان أو حدده على الخريطة'), findsOneWidget);
    expect(find.text('فعالية جديدة'), findsOneWidget, reason: 'النموذج يبقى مفتوحاً بما كُتب فيه');
    srv.failWith = null;
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(srv.created!.containsKey('lat'), isFalse);
    expect(srv.created!.containsKey('lng'), isFalse);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a late GPS fix never replaces the point the creator picked on the map', (tester) async {
    final gps = Completer<LatLng?>();
    DeviceLocation.override = () => gps.future;
    final srv = await _pump(tester);
    await _openForm(tester);
    expect(_source(tester), 'نحدد موقعك…');
    final expected = await _pickAway(tester);
    expect(_source(tester), 'نقطة حددتها على الخريطة');
    // موقع الجهاز يصل بعد الاختيار (إذن متأخر أو تحديد بطيء)
    gps.complete(_device);
    await _settle(tester);
    expect(_source(tester), 'نقطة حددتها على الخريطة');
    await tester.enterText(find.byKey(const Key('ev-title')), 'سوق ليلي');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(srv.created!['lat'], closeTo(expected.latitude, 1e-6));
    expect(srv.created!['lng'], closeTo(expected.longitude, 1e-6));
  });

  testWidgets('«إنشاء» while still locating waits for the device point instead of sending none', (tester) async {
    final gps = Completer<LatLng?>();
    DeviceLocation.override = () => gps.future;
    final srv = await _pump(tester);
    await _openForm(tester);
    await tester.enterText(find.byKey(const Key('ev-title')), 'أمسية');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(srv.calls, isNot(contains('POST /events')), reason: 'ينتظر الموقع الجاري');
    expect(tester.widget<FilledButton>(find.byKey(const Key('ev-pick-map'))).onPressed, isNull, reason: 'لا منتقي فوق النموذج أثناء الإرسال');
    gps.complete(_device);
    await _settle(tester);
    expect(srv.created!['lat'], _device.latitude);
    expect(srv.created!['lng'], _device.longitude);
  });

  testWidgets('«موقعي الحالي» with location denied and no presence keeps the earlier map pick', (tester) async {
    DeviceLocation.override = () async => null;
    final srv = await _pump(tester);
    await _openForm(tester);
    await _settle(tester);
    expect(_source(tester), 'لم يُحدَّد موقع بعد');
    final expected = await _pickAway(tester);
    await tester.tap(find.byKey(const Key('ev-use-device')));
    await _settle(tester);
    expect(_source(tester), 'نقطة حددتها على الخريطة');
    expect(find.text('تعذّر الوصول إلى موقعك؛ بقيت النقطة السابقة'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ev-title')), 'ورشة');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(srv.created!['lat'], closeTo(expected.latitude, 1e-6));
    expect(srv.created!['lng'], closeTo(expected.longitude, 1e-6));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('paid tickets ask for the 18+ declaration first; declining creates nothing', (tester) async {
    DeviceLocation.override = () async => _device;
    final srv = await _pump(tester);
    await _openForm(tester);
    await tester.enterText(find.byKey(const Key('ev-title')), 'حفلة');
    await tester.enterText(find.byKey(const Key('ev-place')), 'المسرح');
    await tester.enterText(find.byKey(const Key('ev-tier-price')), '50');
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('adult-cancel')));
    await _settle(tester);
    expect(srv.calls, isNot(contains('POST /events')));
    expect(find.text('فعالية جديدة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ev-create')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('adult-confirm')));
    await _settle(tester);
    expect(srv.calls.indexOf('POST /me/adult-attest'), lessThan(srv.calls.indexOf('POST /events')));
    expect((srv.created!['tiers'] as List).first['price'], 5000);
  });
}
