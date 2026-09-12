import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _biz(String id, String category, {List<Map<String, dynamic>> items = const []}) => {
      'id': id, 'name': 'Brand $id', 'nameAr': 'علامة $id', 'category': category, 'sector': 'قطاع', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2,
      'address': 'شارع التحلية، جدة', 'hours': '24 ساعة', 'phone': '+966500000000', 'website': 'https://example.com', 'color': '#0058A3',
      'highlights': ['توصيل'], 'verified': false, 'official': false, 'followers': 3, 'rating': 4.5, 'ratingCount': 2, 'minPrice': 1900, 'itemsCount': items.length,
      'items': items, 'reviews': [], 'myOrders': [],
    };

class _Srv {
  final calls = <String>[];
  final orders = <Map<String, dynamic>>[];
  bool broke = false;
  final slot = DateTime.now().add(const Duration(hours: 5)).toUtc();
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path${req.url.query.isNotEmpty ? '?${req.url.query}' : ''}');
    if (req.method == 'GET' && path == '/biz') {
      final cat = req.url.queryParameters['category'];
      final all = [_biz('biz-ikea', 'brand'), _biz('biz-vox', 'cinema'), _biz('biz-hilton', 'hotel'), _biz('biz-budget', 'car_rental')];
      return _json([for (final b in all) if (cat == null || b['category'] == cat) b]);
    }
    if (req.method == 'GET' && path == '/biz/biz-ikea') {
      return _json(_biz('biz-ikea', 'brand', items: [
        {'id': 'ikea-billy', 'bizId': 'biz-ikea', 'kind': 'product', 'title': 'مكتبة BILLY', 'description': 'رف', 'price': 44900, 'unit': 'item', 'stock': 5, 'meta': {'oldPrice': 49900}},
      ])..['myOrders'] = orders);
    }
    if (req.method == 'GET' && path == '/biz/biz-vox') {
      return _json(_biz('biz-vox', 'cinema', items: [
        {'id': 'vox-mission', 'bizId': 'biz-vox', 'kind': 'showtime', 'title': 'فيلم المهمة', 'description': 'أكشن', 'price': 6500, 'unit': 'ticket', 'stock': 100, 'meta': {'hall': 'MAX'}, 'slots': [{'startsAt': slot.toIso8601String(), 'seatsLeft': 100}]},
      ]));
    }
    if (req.method == 'POST' && path == '/biz/biz-ikea/orders' || req.method == 'POST' && path == '/biz/biz-vox/orders') {
      if (broke) return _json({'error': 'insufficient-funds'}, 402);
      final b = jsonDecode(req.body) as Map;
      final cinema = path.contains('vox');
      final o = {'id': 'ord-${orders.length + 1}', 'bizId': cinema ? 'biz-vox' : 'biz-ikea', 'bizNameAr': cinema ? 'فوكس' : 'إيكيا', 'category': cinema ? 'cinema' : 'brand', 'itemId': b['itemId'], 'title': cinema ? 'فيلم المهمة' : 'مكتبة BILLY', 'kind': cinema ? 'showtime' : 'product', 'qty': b['qty'], 'startAt': b['startAt'], 'units': 1, 'total': (cinema ? 6500 : 44900) * (b['qty'] as int), 'status': 'confirmed', 'code': 'NAS-TEST1', 'meta': {}, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'cancellable': true};
      orders.insert(0, o);
      return _json(o);
    }
    if (req.method == 'GET' && path == '/biz/orders/mine') return _json(orders);
    if (req.method == 'POST' && path.startsWith('/biz/orders/') && path.endsWith('/cancel')) { orders.first['status'] = 'cancelled'; orders.first['cancellable'] = false; return _json({'ok': true}); }
    if (req.method == 'POST' && path == '/biz/biz-ikea/follow') return _json({'ok': true});
    if (req.method == 'GET' && path == '/wallet') return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'recent': [], 'testTopup': true});
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/profiles/')) return _json({'id': 'SA0000001', 'nickname': 'amr'});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('Biz model parses category, color and orders', () {
    final b = Biz.fromJson(_biz('biz-hilton', 'hotel'));
    expect(b.category, BizCategory.hotel);
    expect(b.title, 'علامة biz-hilton');
    expect(b.color, const Color(0xFF0058A3));
    expect(b.toBusiness().kind, 'hotel');
    expect(b.highlights, ['توصيل']);
    final o = BizOrder.fromJson({'id': 'o', 'kind': 'room', 'qty': 2, 'units': 3, 'total': 1000, 'status': 'confirmed', 'code': 'X', 'category': 'hotel'});
    expect(o.summary, contains('غرف'));
    expect(o.kindLabel, 'حجز فندقي');
    expect(BizCategory.of('car_rental').catalogTitle, 'السيارات');
  });

  testWidgets('business list filters by category chips', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessesPage());
    expect(find.byType(BizRow), findsNWidgets(4));
    await tester.tap(find.text('فنادق'));
    await tester.pumpAndSettle();
    expect(srv.calls.last, 'GET /biz?category=hotel');
    expect(find.byType(BizRow), findsOneWidget);
  });

  testWidgets('buying a product posts an order and shows the code sheet', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: 'biz-ikea'));
    expect(find.text('مكتبة BILLY'), findsOneWidget);
    expect(find.text('عرض'), findsOneWidget);
    await tester.ensureVisible(find.text('اشترِ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اشترِ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ادفع'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-ikea/orders'));
    expect(srv.orders.single['qty'], 2);
    expect(find.text('تم الشراء'), findsOneWidget);
    expect(find.text('NAS-TEST1'), findsOneWidget);
  });

  testWidgets('cinema: pick a showtime slot and pay sends startAt', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: 'biz-vox'));
    expect(find.text('فيلم المهمة'), findsOneWidget);
    await tester.ensureVisible(find.byType(ChoiceChip).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('ادفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ادفع'));
    await tester.pumpAndSettle();
    expect(srv.orders.single['startAt'], srv.slot.toIso8601String());
    expect(srv.orders.single['qty'], 2);
    expect(find.text('تم الحجز'), findsOneWidget);
  });

  testWidgets('insufficient funds shows a wallet dialog instead of a raw error', (tester) async {
    final srv = _Srv()..broke = true;
    await _pump(tester, srv, const BusinessPage(id: 'biz-ikea'));
    await tester.ensureVisible(find.text('اشترِ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اشترِ'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ادفع'));
    await tester.pumpAndSettle();
    expect(find.text('الرصيد غير كافٍ'), findsOneWidget);
  });

  testWidgets('my bookings lists orders and cancels from the sheet', (tester) async {
    final srv = _Srv();
    srv.orders.add({'id': 'ord-9', 'bizId': 'biz-ikea', 'bizNameAr': 'إيكيا', 'category': 'brand', 'itemId': 'ikea-billy', 'title': 'مكتبة BILLY', 'kind': 'product', 'qty': 1, 'units': 1, 'total': 44900, 'status': 'confirmed', 'code': 'NAS-ABCD', 'meta': {}, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'cancellable': true});
    await _pump(tester, srv, const MyBookingsPage());
    expect(find.textContaining('مكتبة BILLY'), findsOneWidget);
    await tester.tap(find.textContaining('مكتبة BILLY'));
    await tester.pumpAndSettle();
    expect(find.text('NAS-ABCD'), findsOneWidget);
    await tester.tap(find.text('إلغاء واسترداد المبلغ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء الحجز'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/orders/ord-9/cancel'));
    expect(find.textContaining('ملغى'), findsOneWidget);
  });
}
