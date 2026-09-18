// المرحلة (ب) من السوق: مندوب التوصيل على صفحة الطلب (تعيين من البائع، وأزرار المندوب)، شريط البازارات وصفحة البازار
// مع إضافة عروضي، شحن المحفظة بالبطاقة عند تفعيل البوابة، وبطاقة ترقية البائع إلى دائرة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/market/seller_tools.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111', _oid = '22222222-2222-4222-8222-222222222222', _bid = '44444444-4444-4444-8444-444444444444';
final _seller = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null};
final _buyer = {'id': 'SA0000001', 'nickname': 'amr', 'avatarUrl': null};
final _rider = {'id': 'SA0000004', 'nickname': 'rider', 'avatarUrl': null};

Map<String, dynamic> _listing({bool mine = false}) => {
      'id': _lid, 'seller': mine ? _buyer : _seller, 'kind': 'product', 'category': 'food', 'subcategory': 'sweets', 'title': 'كيك عيد ميلاد', 'description': '', 'price': 22000, 'imageUrl': null, 'images': [], 'status': 'active',
      'lat': 21.5, 'lng': 39.1, 'mine': mine, 'createdAt': '2026-09-10T08:00:00Z',
    };
Map<String, dynamic> _bazaar({int listings = 1, int mine = 0, bool withItems = false}) => {
      'id': _bid, 'title': 'بازار الحلويات', 'description': 'أسبوع الحلا', 'city': 'جدة', 'category': 'food', 'state': 'live', 'active': true, 'startsAt': '2026-09-17T00:00:00Z', 'endsAt': '2026-09-25T00:00:00Z', 'listings': listings, 'mine': mine,
      if (withItems) 'items': [for (var i = 0; i < listings; i++) _listing()],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String orderStatus = 'paid'; String role = 'buyer'; bool courier = false; bool payEnabled = false; bool upgraded = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> _order() => {
        'id': _oid, 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'imageUrl': null, 'kind': 'product', 'qty': 1, 'total': 22000, 'status': orderStatus, 'note': '', 'code': role == 'buyer' ? '4321' : null, 'buyer': _buyer, 'seller': _seller,
        'mineAsSeller': role == 'seller', 'mineAsCourier': role == 'courier', 'courier': courier ? _rider : null, 'courierNote': courier ? 'يتصل قبل الوصول' : '', 'reviewed': false, 'createdAt': '2026-09-17T10:00:00Z',
      };
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path; final key = '${req.method} $path'; calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if (req.body.isNotEmpty && req.method != 'GET') { try { bodies[key] = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /market/home': return _json({'spotlight': [], 'popular': [_listing()], 'nearby': [], 'bazaars': [_bazaar()], 'categories': {'food': 3}, 'wantedOpen': 0, 'spotlightPricePerDay': 2000, 'commissionPct': 5});
      case 'GET /market': return _json([_listing()]);
      case 'GET /market/mine': return _json([_listing(mine: true)]);
      case 'GET /market/bazaars/$_bid': return _json(_bazaar(withItems: true));
      case 'POST /market/bazaars/$_bid/join': return _json({'ok': true});
      case 'GET /market/orders/$_oid': return _json(_order());
      case 'GET /market/orders': return _json([_order()]);
      case 'POST /market/orders/$_oid/courier': courier = true; return _json(_order());
      case 'DELETE /market/orders/$_oid/courier': courier = false; return _json(_order());
      case 'POST /market/orders/$_oid/stage': orderStatus = bodies[key]!['stage'] as String; return _json({'ok': true});
      case 'GET /wallet': return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': false, 'recent': []});
      case 'GET /pay/config': return _json({'enabled': payEnabled, 'provider': 'moyasar', 'methods': ['creditcard', 'applepay'], 'min': 1000, 'max': 500000, 'currency': 'SAR'});
      case 'POST /pay/topup': return _json({'id': 'p1', 'amount': bodies[key]!['amount'], 'currency': 'SAR', 'checkoutUrl': 'https://test.local/pay/checkout/p1?t=abc'});
      case 'GET /market/seller/stats': return _json({'today': {'orders': 0, 'revenue': 0}, 'week': {'orders': 0, 'revenue': 0}, 'month': {'orders': 0, 'revenue': 0, 'net': 0}, 'pending': 0, 'awaitingConfirm': 0, 'disputed': 0, 'views7': 0, 'conversionPct': 0, 'followers': 0, 'spotlightActive': 0, 'rating': {'avg': null, 'count': 0}, 'badges': [], 'listings': {'active': 2}, 'top': []});
      case 'GET /market/coupons': return _json([]);
      case 'GET /market/spotlight/mine': return _json([]);
      case 'GET /market/seller/upgrade': return _json(upgraded ? {'upgraded': {'bizId': 'biz-sara-ab12', 'items': 2}, 'eligible': false, 'listings': 2} : {'upgraded': null, 'eligible': true, 'listings': 2, 'completed': 3, 'suggestedName': 'sara', 'suggestedCategory': 'restaurant', 'city': 'جدة'});
      case 'POST /market/seller/upgrade': upgraded = true; return _json({'ok': true, 'bizId': 'biz-sara-ab12', 'items': 2});
      case 'GET /biz/biz-sara-ab12': return _json({'id': 'biz-sara-ab12', 'name': 'sara', 'nameAr': 'مطبخ سارة', 'category': 'restaurant', 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.1, 'address': '', 'hours': '', 'highlights': [], 'followers': 0, 'ratingCount': 0, 'itemsCount': 2, 'items': [], 'reviews': [], 'myOrders': [], 'posts': [], 'active': true, 'views': 0, 'ownerId': 'SA0000001', 'myRole': 'owner'});
    }
    if (path.startsWith('/presence')) return _json({'lat': 21.5, 'lng': 39.1, 'hideAfterHours': 0});
    if (path.startsWith('/biz/')) return _json({'error': 'not-found'}, 404);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv}) async {
  final s = srv ?? _Srv();
  tester.view.physicalSize = const Size(600, 1500); tester.view.devicePixelRatio = 1; addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), marketPosProvider.overrideWith((ref) async => (lat: 21.5, lng: 39.1))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('seller assigns a courier from the order page and can remove him', (tester) async {
    final srv = _Srv()..role = 'seller';
    await _pump(tester, const OrderPage(_oid), srv: srv);
    expect(find.byKey(const Key('order-courier')), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-courier'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('courier-nick')), '@rider');
    await tester.enterText(find.byKey(const Key('courier-note')), 'يتصل قبل الوصول');
    await tester.tap(find.byKey(const Key('courier-save'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/orders/$_oid/courier']!['nickname'], '@rider');
    expect(find.byKey(const Key('order-courier-name')), findsOneWidget);
    expect(find.text('مندوب التوصيل: rider'), findsOneWidget);
    expect(find.byKey(const Key('order-courier')), findsNothing); // لا زر تعيين وهناك مندوب
    await tester.tap(find.byKey(const Key('order-courier-clear'))); await tester.pumpAndSettle();
    expect(srv.calls, contains('DELETE /market/orders/$_oid/courier'));
    expect(find.byKey(const Key('order-courier-name')), findsNothing);
  });

  testWidgets('courier sees only his stage buttons and no buyer code, and marks the order delivered', (tester) async {
    final srv = _Srv()..role = 'courier'..courier = true..orderStatus = 'preparing';
    await _pump(tester, const OrderPage(_oid), srv: srv);
    expect(find.text('أنت مندوب التوصيل'), findsOneWidget);
    expect(find.byKey(const Key('order-code')), findsNothing);
    expect(find.byKey(const Key('order-confirm')), findsNothing);
    expect(find.byKey(const Key('seller-code')), findsNothing);
    expect(find.byKey(const Key('stage-on_the_way')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stage-delivered'))); await tester.pumpAndSettle();
    expect(srv.orderStatus, 'delivered');
    expect(find.byKey(const Key('stage-delivered')), findsNothing);
  });

  testWidgets('market home shows the bazaar strip and the bazaar page lets a seller add his listing', (tester) async {
    final srv = await _pump(tester, const MarketPage());
    expect(find.byKey(const Key('bazaar-$_bid')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-info')), findsOneWidget); // لا سبوت لايت: سطر التعريف
    await tester.tap(find.byKey(const Key('bazaar-$_bid'))); await tester.pumpAndSettle();
    expect(find.text('أسبوع الحلا'), findsOneWidget);
    expect(find.byType(ListingCard), findsOneWidget);
    await tester.tap(find.byKey(const Key('bazaar-join'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bz-add-$_lid'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/bazaars/$_bid/join']!['listingId'], _lid);
  });

  testWidgets('wallet shows the card top-up only when the gateway is enabled and starts a payment', (tester) async {
    await _pump(tester, const WalletPage());
    expect(find.byKey(const Key('wallet-card-topup')), findsNothing);
    final srv = _Srv()..payEnabled = true;
    await _pump(tester, const WalletPage(), srv: srv);
    expect(find.byKey(const Key('wallet-card-topup')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wallet-card-topup'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.tap(find.text('متابعة للدفع')); await tester.pumpAndSettle();
    expect(srv.bodies['POST /pay/topup']!['amount'], 15000);
  });

  testWidgets('seller dashboard offers the circle upgrade and creates it', (tester) async {
    final srv = await _pump(tester, const SellerDashboardPage());
    expect(find.byKey(const Key('seller-upgrade')), findsOneWidget);
    await tester.tap(find.byKey(const Key('seller-upgrade'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('upgrade-name')), 'مطبخ سارة');
    await tester.tap(find.byKey(const Key('upgrade-go'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/seller/upgrade']!['nameAr'], 'مطبخ سارة');
    expect(srv.calls, contains('GET /biz/biz-sara-ab12'));
  });
}
