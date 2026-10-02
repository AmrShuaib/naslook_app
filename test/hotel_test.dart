// حجز الفنادق عبر Nuitee Connect (LiteAPI): بطاقة الدخول في الدائرة الفندقية المرتبطة، رحلة الحجز الثلاثية (التواريخ والغرف ←
// التأكيد بلا بطاقة ضيف ← تم الحجز)، قسم «حجوزات الفنادق» في حجوزاتي، وبطاقة LiteAPI في إعدادات الإدارة (المفتاح والربط).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/hotel_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/pages/hotels/hotel_book_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _bizId = 'biz-hilton';
const _hotelId = 'HLJED123';

Map<String, dynamic> _biz() => {
      'id': _bizId, 'name': 'Hilton Jeddah', 'nameAr': 'هيلتون جدة', 'category': 'hotel', 'sector': 'فندق', 'description': 'على الكورنيش', 'lat': 21.6, 'lng': 39.1,
      'address': 'الكورنيش، جدة', 'hours': '24 ساعة', 'color': '#0058A3', 'highlights': [], 'verified': true, 'official': false, 'followers': 10, 'rating': 4.6, 'ratingCount': 5, 'minPrice': 60000, 'itemsCount': 1,
      'items': [{'id': 'hilton-std', 'bizId': _bizId, 'kind': 'room', 'title': 'غرفة قياسية', 'description': '', 'price': 60000, 'unit': 'night', 'stock': 5, 'meta': {'beds': 'سرير كينغ', 'guests': 2}}],
      'reviews': [], 'myOrders': [], 'posts': [],
    };

Map<String, dynamic> _offer() => {
      'id': 'OFF1', 'roomName': 'غرفة ديلوكس', 'roomCode': 'DLX', 'bedType': 'سرير كينغ', 'beds': 1, 'description': 'إطلالة على البحر', 'boardType': 'إفطار', 'total': 125000, 'currency': 'SAR',
      'totalText': '1,250 ر.س', 'perNightText': '625 ر.س/ليلة', 'refundable': true, 'cancelBy': '2026-10-12T00:00:00Z', 'cancelText': 'إلغاء مجاني حتى 12 أكتوبر', 'paymentType': 'guarantee', 'paymentText': 'بطاقة ضمان؛ الدفع في الفندق',
    };

Map<String, dynamic> _booking({String checkIn = '2026-10-10', String checkOut = '2026-10-12'}) => {
      'id': 'hb1', 'bizId': _bizId, 'bizName': 'هيلتون جدة', 'hotelId': _hotelId, 'hotelName': 'Hilton Jeddah', 'orderId': 'ORD1', 'confirmation': 'CONF-7F3K', 'status': 'confirmed', 'checkIn': checkIn, 'checkOut': checkOut,
      'nights': 2, 'adults': 2, 'rooms': 1, 'roomName': 'غرفة ديلوكس', 'total': 125000, 'currency': 'SAR', 'totalText': '1,250 ر.س', 'guestName': 'Amr Shuaib', 'guestEmail': 'amr@example.com',
      'cancelText': 'إلغاء مجاني حتى 12 أكتوبر', 'env': 'test', 'upcoming': true, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool linked = true, noOffers = false, conflict = false;
  final bookings = <Map<String, dynamic>>[];
  final links = <Map<String, dynamic>>[];
  Map<String, dynamic> hotelCfg = {'configured': false, 'env': 'test', 'source': null, 'clientIdSet': false, 'clientIdHint': '', 'secretSet': false, 'secretHint': '', 'panelSet': false, 'envPresent': false, 'linked': 0, 'bookings': 0};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add('$key${req.url.query.isNotEmpty ? '?${req.url.query}' : ''}');
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    final q = req.url.queryParameters;
    switch (key) {
      case 'GET /biz/$_bizId': return _json(_biz());
      case 'GET /biz/$_bizId/hotel': return _json(linked ? {'linked': true, 'bizId': _bizId, 'hotelId': _hotelId, 'hotelName': 'Hilton Jeddah', 'cityCode': 'JED', 'env': 'test', 'configured': true} : {'linked': false});
      case 'GET /hotel/status': return _json({'ok': true, 'provider': 'liteapi', 'configured': true, 'env': 'test', 'source': 'panel', 'linked': 1, 'cardRequired': false, 'testCard': null});
      case 'GET /biz/$_bizId/hotel/offers':
        return _json({'hotel': {'hotelId': _hotelId, 'name': 'Hilton Jeddah', 'cityCode': 'JED'}, 'checkIn': q['checkIn'], 'checkOut': q['checkOut'], 'nights': 2, 'adults': int.parse(q['adults']!), 'rooms': int.parse(q['rooms']!), 'currency': 'SAR', 'env': 'test',
          'available': !noOffers, 'offers': noOffers ? [] : [_offer()]});
      case 'POST /biz/$_bizId/hotel/book':
        if (conflict) return _json({'error': 'offer-unavailable'}, 409);
        final b = _booking();
        bookings.insert(0, b);
        return _json(b);
      case 'GET /hotel/bookings/mine': return _json(bookings);
      case 'GET /biz/orders/mine': return _json([]);
      case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr'});
      // الإدارة
      case 'GET /adminapi/settings': return _json({'testTopup': true, 'maxTopup': 10000000, 'announcement': '', 'maintenance': false, 'supportHandle': ''});
      case 'GET /adminapi/admins': return _json([]);
      case 'GET /adminapi/payments/config': return _json({'enabled': false, 'provider': 'moyasar', 'mode': null, 'source': null, 'envPresent': false, 'publishableKey': null, 'secretKeySet': false, 'secretKeyHint': '', 'webhookSecretSet': false, 'panelKeysSet': false, 'webhookUrl': 'https://test.local/pay/webhook', 'returnUrl': 'https://test.local/pay/return'});
      case 'GET /adminapi/hotels/config': return _json(hotelCfg);
      case 'PUT /adminapi/hotels/config':
        final b = bodies[key]!;
        if ('${b['apiKey'] ?? ''}'.contains('*')) return _json({'error': 'masked-key'}, 400);
        final on = (b['apiKey'] ?? '') != '';
        hotelCfg = {'configured': on, 'env': b['env'] ?? hotelCfg['env'], 'source': on ? 'panel' : null, 'secretSet': on, 'secretHint': on ? 'sEcR…7654' : '', 'panelSet': on, 'envPresent': false, 'updatedAt': DateTime.now().toUtc().toIso8601String(), 'updatedBy': 'SA0000001', 'linked': links.length, 'bookings': 0};
        return _json(hotelCfg);
      case 'POST /adminapi/hotels/test': return _json(hotelCfg['configured'] == true ? {'ok': true, 'env': hotelCfg['env'], 'source': 'panel', 'expiresIn': 1799} : {'ok': false, 'error': 'hotel-disabled', 'env': 'test', 'source': null});
      case 'GET /adminapi/hotels/search': return _json({'hotels': [{'hotelId': _hotelId, 'name': 'Hilton Jeddah', 'lat': 21.6, 'lng': 39.1, 'distanceKm': 2.3}]});
      case 'GET /adminapi/hotels/links': return _json(links);
      case 'PUT /biz/$_bizId/hotel/link':
        final b = bodies[key]!;
        links.add({'bizId': _bizId, 'bizName': 'هيلتون جدة', 'hotelId': b['hotelId'], 'hotelName': b['hotelName'] ?? '', 'cityCode': b['cityCode'] ?? 'JED', 'createdAt': DateTime.now().toUtc().toIso8601String()});
        return _json({'linked': true, 'bizId': _bizId, 'hotelId': b['hotelId'], 'hotelName': b['hotelName'] ?? '', 'cityCode': b['cityCode'] ?? 'JED', 'env': 'test', 'configured': true});
      case 'DELETE /biz/$_bizId/hotel/link':
        links.clear();
        return _json({'ok': true});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/profiles/')) return _json({'id': 'SA0000001', 'nickname': 'amr'});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(800, 2400)}) async {
  // شاشة طويلة: القوائم كسولة ولا تبني ما هو خارج العرض، والنماذج تحتاج كل حقولها مبنية
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

/// يبحث ويختار العرض الوحيد ويصل إلى شاشة التأكيد.
Future<void> _toConfirm(WidgetTester tester, _Srv srv) async {
  await _pump(tester, srv, const HotelBookPage(bizId: _bizId, title: 'هيلتون جدة'));
  await tester.tap(find.byKey(const Key('hotel-search')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hotel-pick-OFF1')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('hotel-confirm')), findsOneWidget);
}

Future<void> _fillGuest(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('hotel-first')), 'Amr');
  await tester.enterText(find.byKey(const Key('hotel-last')), 'Shuaib');
  await tester.enterText(find.byKey(const Key('hotel-phone')), '+966500000000');
  await tester.enterText(find.byKey(const Key('hotel-email')), 'amr@example.com');
}

void main() {
  test('hotel models parse tolerantly and format dates', () {
    expect(hotelDate(DateTime(2026, 10, 3)), '2026-10-03');
    expect(parseHotelDate('2026-10-03'), DateTime(2026, 10, 3));
    expect(parseHotelDate('x'), isNull);
    final o = HotelOffer.fromJson(_offer());
    expect(o.priceText, '1,250 ر.س');
    expect(o.bedsLine, 'سرير كينغ · سرير واحد');
    expect(HotelOffer.fromJson(const {'id': 'z', 'total': 100000}).priceText, '1000 ر.س');
    final b = HotelBooking.fromJson(_booking());
    expect(b.statusLabel, 'مؤكد');
    expect(b.isTest, isTrue);
    expect(HotelLink.fromJson(const {'linked': false}).linked, isFalse);
    expect(HotelStatus.fromJson(const {'ok': true, 'configured': true, 'env': 'live'}).testCard, isNull);
    expect(HotelStatus.fromJson(const {'ok': true}).cardRequired, isTrue);
    expect(HotelStatus.fromJson(const {'ok': true, 'cardRequired': false}).cardRequired, isFalse);
    expect(HotelAdminConfig.fromJson(const {}).env, 'test');
  });

  testWidgets('unlinked hotel circle shows no entry card and keeps its catalogue rooms', (tester) async {
    final srv = _Srv()..linked = false;
    await _pump(tester, srv, const BusinessPage(id: _bizId));
    expect(srv.calls, contains('GET /biz/$_bizId/hotel'));
    expect(find.byKey(const Key('hotel-entry')), findsNothing);
    expect(find.text('غرفة قياسية'), findsOneWidget);
  });

  testWidgets('linked hotel circle shows the entry card and opens the booking journey', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: _bizId));
    expect(find.byKey(const Key('hotel-entry')), findsOneWidget);
    expect(find.text('احجز غرفة بأسعار اليوم'), findsOneWidget);
    expect(find.byKey(const Key('hotel-entry-test')), findsOneWidget); // شارة بيئة الاختبار
    await tester.tap(find.byKey(const Key('hotel-entry-book')));
    await tester.pumpAndSettle();
    expect(find.byType(HotelBookPage), findsOneWidget);
    expect(find.textContaining('احجز غرفة · هيلتون جدة'), findsOneWidget);
    expect(find.byKey(const Key('hotel-dates')), findsOneWidget);
    expect(find.byKey(const Key('hotel-nights')), findsOneWidget);
    expect(find.text('ليلتان'), findsOneWidget); // الافتراضي: غداً وليلتان
  });

  testWidgets('journey: search with dates and guests, pick an offer, confirm with the test card, see the ticket', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const HotelBookPage(bizId: _bizId, title: 'هيلتون جدة'));
    await tester.tap(find.byKey(const Key('hotel-adults-plus')));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hotel-search')));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final search = srv.calls.firstWhere((c) => c.startsWith('GET /biz/$_bizId/hotel/offers'));
    expect(search, contains('checkIn=${hotelDate(tomorrow)}'));
    expect(search, contains('checkOut=${hotelDate(tomorrow.add(const Duration(days: 2)))}'));
    expect(search, contains('adults=3'));
    expect(search, contains('rooms=1'));
    expect(find.byKey(const Key('hotel-offer-OFF1')), findsOneWidget);
    expect(find.text('غرفة ديلوكس'), findsOneWidget);
    expect(find.text('1,250 ر.س'), findsOneWidget);
    expect(find.text('625 ر.س/ليلة'), findsOneWidget);
    expect(find.text('إلغاء مجاني حتى 12 أكتوبر'), findsOneWidget);
    // التأكيد: الملخص وبطاقة الاختبار معبّأة
    await tester.tap(find.byKey(const Key('hotel-pick-OFF1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hotel-confirm')), findsOneWidget);
    expect(find.text('Hilton Jeddah'), findsOneWidget);
    expect(find.text('غرفة ديلوكس'), findsOneWidget);
    expect(find.text('ليلتان'), findsOneWidget);
    expect(find.text('3 بالغين · غرفة واحدة'), findsOneWidget);
    expect(find.text('1,250 ر.س'), findsOneWidget);
    expect(find.textContaining('بطاقة ضمان؛ الدفع في الفندق'), findsOneWidget);
    // المزوّد لا يطلب بطاقة ضيف: لا نموذج بطاقة، وسطر يوضح ذلك
    expect(find.byKey(const Key('hotel-no-card')), findsOneWidget);
    expect(find.byKey(const Key('hotel-card-number')), findsNothing);
    expect(find.byKey(const Key('hotel-test-chip')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('hotel-first'))).controller!.text, 'amr'); // من الملف الشخصي
    await _fillGuest(tester);
    await tester.tap(find.byKey(const Key('hotel-book')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/$_bizId/hotel/book']!;
    expect(body['offerId'], 'OFF1');
    expect(body['guest'], {'title': 'MR', 'firstName': 'Amr', 'lastName': 'Shuaib', 'phone': '+966500000000', 'email': 'amr@example.com'});
    expect(body.containsKey('card'), isFalse, reason: 'لا بطاقة تُرسل حين لا يطلبها المزوّد');
    // تم الحجز: رقم التأكيد والحالة
    expect(find.byKey(const Key('hotel-done')), findsOneWidget);
    expect(find.byKey(const Key('hotel-confirm')), findsNothing);
    expect(find.text('تم الحجز'), findsWidgets);
    expect(find.text('CONF-7F3K'), findsOneWidget);
    expect(find.byKey(const Key('hotel-confirmation')), findsOneWidget);
    expect(find.text('مؤكد'), findsOneWidget);
    expect(find.text('Amr Shuaib'), findsOneWidget);
    expect(find.text('1,250 ر.س'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hotel-go-bookings')));
    await tester.pumpAndSettle();
    expect(find.byType(MyBookingsPage), findsOneWidget);
    expect(find.byKey(const Key('hotel-booking-hb1')), findsOneWidget);
  });

  testWidgets('no availability shows the empty state', (tester) async {
    final srv = _Srv()..noOffers = true;
    await _pump(tester, srv, const HotelBookPage(bizId: _bizId, title: 'هيلتون جدة'));
    expect(find.byKey(const Key('hotel-empty')), findsNothing);
    await tester.tap(find.byKey(const Key('hotel-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hotel-empty')), findsOneWidget);
    expect(find.text('لا غرف متاحة في هذه التواريخ'), findsOneWidget);
  });

  testWidgets('offer gone (409) shows a clear toast and stays on the confirm screen', (tester) async {
    final srv = _Srv()..conflict = true;
    await _toConfirm(tester, srv);
    await _fillGuest(tester);
    await tester.tap(find.byKey(const Key('hotel-book')));
    await tester.pumpAndSettle();
    expect(find.text('الغرفة لم تعد متاحة، اختر غيرها'), findsOneWidget);
    expect(find.byKey(const Key('hotel-confirm')), findsOneWidget);
    expect(find.byKey(const Key('hotel-done')), findsNothing);
  });

  testWidgets('local validation blocks an incomplete guest form before any request', (tester) async {
    final srv = _Srv();
    await _toConfirm(tester, srv);
    await tester.enterText(find.byKey(const Key('hotel-first')), '');
    await tester.tap(find.byKey(const Key('hotel-book')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب الاسم الأول واسم العائلة'), findsOneWidget);
    expect(srv.bodies['POST /biz/$_bizId/hotel/book'], isNull);
  });

  testWidgets('my bookings shows the hotel section above the circle orders', (tester) async {
    final srv = _Srv()..bookings.add(_booking());
    await _pump(tester, srv, const MyBookingsPage());
    expect(find.byKey(const Key('hotel-bookings')), findsOneWidget);
    expect(find.byKey(const Key('hotel-booking-hb1')), findsOneWidget);
    expect(find.text('حجوزات الفنادق'), findsOneWidget);
    expect(find.text('Hilton Jeddah'), findsOneWidget);
    expect(find.textContaining('CONF-7F3K'), findsOneWidget);
    expect(find.text('مؤكد'), findsOneWidget);
    expect(find.text('لا حجوزات بعد'), findsNothing);
    await tester.tap(find.byKey(const Key('hotel-booking-hb1')));
    await tester.pumpAndSettle();
    expect(find.text('رقم التأكيد'), findsOneWidget);
  });

  testWidgets('admin card saves keys and env, blocks masked copies, tests the connection and links a hotel', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()), size: const Size(700, 3400));
    expect(find.textContaining('غير مفعّل:'), findsOneWidget);
    expect(find.byKey(const Key('hotel-clear')), findsNothing);
    // حفظ المفتاح والبيئة الحية
    expect(find.byKey(const Key('hotel-id')), findsNothing, reason: 'مفتاح واحد فقط');
    await tester.enterText(find.byKey(const Key('hotel-secret')), ' sEcReT987654 ');
    await tester.tap(find.byKey(const Key('hotel-env-live')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hotel-save')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PUT /adminapi/hotels/config'], {'apiKey': 'sEcReT987654', 'env': 'live'});
    expect(find.textContaining('البيئة الحية'), findsWidgets);
    expect(find.textContaining('sEcR…7654'), findsOneWidget); // تلميح فقط، لا المفتاح كاملاً
    expect(find.text('sEcReT987654'), findsNothing);
    expect(find.byKey(const Key('hotel-clear')), findsOneWidget);
    // سر منسوخ مقنّعاً → يُكتشف محلياً بلا طلب
    srv.bodies.remove('PUT /adminapi/hotels/config');
    await tester.enterText(find.byKey(const Key('hotel-secret')), 'sEc**********');
    await tester.pumpAndSettle();
    expect(find.textContaining('منسوخ مقنّعاً: فيه نجوم'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hotel-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('أيقونة الإظهار'), findsOneWidget);
    expect(srv.bodies['PUT /adminapi/hotels/config'], isNull);
    // فحص الاتصال
    await tester.tap(find.byKey(const Key('hotel-test')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /adminapi/hotels/test'));
    expect(find.textContaining('الاتصال ناجح'), findsOneWidget);
    // الربط: بحث بالاسم ثم اختيار الفندق
    await tester.enterText(find.byKey(const Key('hotel-link-biz')), _bizId);
    await tester.enterText(find.byKey(const Key('hotel-link-search')), 'hilton');
    await tester.tap(find.byKey(const Key('hotel-link-go')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /adminapi/hotels/search?cityCode=JED&q=hilton'));
    await tester.tap(find.byKey(const Key('hotel-link-pick-$_hotelId')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('PUT /biz/$_bizId/hotel/link'));
    expect(srv.bodies['PUT /biz/$_bizId/hotel/link'], {'hotelId': _hotelId, 'hotelName': 'Hilton Jeddah', 'cityCode': 'JED'});
    expect(find.byKey(const Key('hotel-link-row-$_bizId')), findsOneWidget);
    // فك الربط
    await tester.tap(find.byKey(const Key('hotel-unlink-$_bizId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فك الربط'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('DELETE /biz/$_bizId/hotel/link'));
    expect(find.byKey(const Key('hotel-link-row-$_bizId')), findsNothing);
  });
}
