// السوق v2: الرئيسية (سبوت لايت، التصنيفات، الترتيب والفلاتر)، صفحة العرض (خيار وكوبون وطلب برمز)، الطلبات (المراحل والتأكيد
// بالرمز والتقييم)، طلبات المشترين، ولوحة البائع مع شراء سبوت لايت.
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
import 'package:naslook/pages/market/wanted_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111', _oid = '22222222-2222-4222-8222-222222222222', _wid = '33333333-3333-4333-8333-333333333333';
final _seller = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null};
final _buyer = {'id': 'SA0000001', 'nickname': 'amr', 'avatarUrl': null};

Map<String, dynamic> _listing({bool mine = false, String status = 'active'}) => {
      'id': _lid, 'seller': _seller, 'sellerRating': 4.5, 'sellerRatingCount': 12, 'sellerBadges': ['trusted', 'fast'], 'kind': 'product', 'category': 'food', 'subcategory': 'sweets', 'condition': 'new', 'delivery': true,
      'title': 'كيك عيد ميلاد', 'description': 'كيك فانيلا بتصميم خاص', 'price': 22000, 'imageUrl': null, 'images': [], 'placeName': 'الروضة', 'city': 'جدة', 'lat': 21.5, 'lng': 39.1, 'status': status, 'stock': null, 'sold': 3, 'views': 40,
      'variants': [{'name': 'صغير', 'price': 22000, 'stock': null}, {'name': 'كبير', 'price': 30000, 'stock': 0}], 'availability': null, 'spotlight': true, 'ratingAvg': 4.8, 'ratingCount': 5, 'distanceKm': 1.2, 'mine': mine, 'createdAt': '2026-09-10T08:00:00Z',
    };
Map<String, dynamic> _order({String status = 'paid', bool asSeller = false, bool reviewed = false}) => {
      'id': _oid, 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'imageUrl': null, 'kind': 'product', 'qty': 2, 'total': 39600, 'discount': 4400, 'coupon': 'WELCOME10', 'commission': asSeller ? 3960 : null, 'status': status, 'note': 'بعد المغرب', 'variant': 'صغير',
      'code': asSeller ? null : '4321', 'buyer': _buyer, 'seller': _seller, 'mineAsSeller': asSeller, 'reviewed': reviewed, 'createdAt': '2026-09-17T10:00:00Z',
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String orderStatus = 'paid'; bool asSeller = false; bool reviewed = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path; final key = '${req.method} $path'; calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if (req.body.isNotEmpty && req.method != 'GET') { try { bodies[key] = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /market/home':
        return _json({'spotlight': [{'id': 'sp1', 'endsAt': '2026-09-25T00:00:00Z', 'listing': _listing()}], 'popular': [_listing()], 'nearby': [], 'categories': {'food': 3, 'services': 5}, 'wantedOpen': 2, 'spotlightPricePerDay': 2000, 'commissionPct': 5});
      case 'GET /market':
        final q = req.url.queryParameters;
        if (q['category'] == 'services') return _json([]);
        return _json([_listing(), {..._listing(), 'id': '44444444-4444-4444-8444-444444444444', 'title': 'كوكيز', 'price': 9000, 'spotlight': false, 'distanceKm': 3.4, 'variants': []}]);
      case 'GET /market/$_lid': return _json(_listing());
      case 'GET /market/$_lid/questions': return _json([{'id': 'q1', 'listingId': _lid, 'user': _buyer, 'text': 'هل يتوفر بدون سكر؟', 'answer': 'نعم', 'createdAt': '2026-09-16T10:00:00Z'}]);
      case 'GET /market/$_lid/reviews': return _json([{'orderId': 'o0', 'listingId': _lid, 'rating': 5, 'text': 'رائع', 'reply': 'شكراً', 'buyer': _buyer, 'createdAt': '2026-09-15T10:00:00Z'}]);
      case 'POST /market/$_lid/view': return _json({'ok': true});
      case 'GET /market/coupons/check': return _json({'valid': true, 'discount': 2200, 'total': 19800});
      case 'POST /market/$_lid/order': return _json({'ok': true, 'id': _oid, 'total': 19800, 'discount': 2200, 'commission': 0, 'code': '4321'});
      case 'GET /market/orders': return _json([_order(status: orderStatus, asSeller: asSeller, reviewed: reviewed)]);
      case 'GET /market/orders/$_oid': return _json(_order(status: orderStatus, asSeller: asSeller, reviewed: reviewed));
      case 'POST /market/orders/$_oid/stage': orderStatus = bodies[key]!['stage'] as String; return _json({'ok': true});
      case 'POST /market/orders/$_oid/confirm': if (asSeller && bodies[key]?['code'] != '4321') return _json({'error': 'bad-code'}, 400); orderStatus = 'completed'; return _json({'ok': true});
      case 'POST /market/orders/$_oid/review': reviewed = true; return _json({'ok': true});
      case 'GET /market/wanted': return _json([{'id': _wid, 'user': _seller, 'title': 'أبحث عن كيك تخرج', 'description': '', 'category': 'food', 'budgetMax': 30000, 'status': 'open', 'replies': 1, 'distanceKm': 2, 'mine': false, 'createdAt': '2026-09-17T09:00:00Z'}]);
      case 'GET /market/wanted/$_wid': return _json({'id': _wid, 'user': _seller, 'title': 'أبحث عن كيك تخرج', 'description': 'لـ ٢٠ شخصاً', 'category': 'food', 'budgetMax': 30000, 'status': 'open', 'replies': 1, 'mine': false, 'createdAt': '2026-09-17T09:00:00Z', 'replyList': [{'id': 'r1', 'seller': _buyer, 'text': 'عندي', 'price': 25000, 'listingId': _lid, 'listingTitle': 'كيك عيد ميلاد', 'mine': true, 'createdAt': '2026-09-17T10:00:00Z'}]});
      case 'POST /market/wanted': return _json({'id': 'w2', 'user': _buyer, 'title': bodies[key]!['title'], 'description': '', 'category': 'services', 'status': 'open', 'replies': 0, 'mine': true});
      case 'GET /market/seller/stats': return _json({'today': {'orders': 1, 'revenue': 22000}, 'week': {'orders': 4, 'revenue': 90000}, 'month': {'orders': 9, 'revenue': 200000, 'net': 190000}, 'pending': 2, 'awaitingConfirm': 1, 'disputed': 0, 'views7': 80, 'conversionPct': 5, 'followers': 7, 'spotlightActive': 1, 'rating': {'avg': 4.5, 'count': 12}, 'badges': ['trusted'], 'responseHours': 1.5, 'listings': {'active': 5}, 'top': [{'id': _lid, 'title': 'كيك عيد ميلاد', 'views': 40, 'views7': 20, 'sold': 3, 'revenue': 66000, 'status': 'active'}]});
      case 'GET /market/coupons': return _json([{'code': 'WELCOME10', 'percent': 10, 'amount': null, 'minTotal': 10000, 'maxUses': 20, 'used': 3, 'active': true}]);
      case 'GET /market/spotlight/mine': return _json([{'id': 'sp1', 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'startsAt': '2026-09-17T00:00:00Z', 'endsAt': '2026-09-25T00:00:00Z', 'days': 8, 'paid': 16000, 'status': 'active', 'views': 120, 'clicks': 9, 'granted': false}]);
      case 'GET /market/spotlight/price': return _json({'perDay': 2000, 'maxDays': 30});
      case 'GET /market/mine': return _json([_listing(mine: true)]);
      case 'POST /market/$_lid/spotlight': return _json({'ok': true, 'id': 'sp2', 'endsAt': '2026-09-30T00:00:00Z', 'paid': (bodies[key]!['days'] as int) * 2000});
      case 'GET /wallet': return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': false, 'recent': []});
      case 'GET /wishlist/status': return _json({'saved': false});
    }
    if (path.startsWith('/presence')) return _json({'lat': 21.5, 'lng': 39.1, 'hideAfterHours': 0});
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

/// يمرّر صف الرقائق الأفقي حتى تظهر الرقاقة المطلوبة (الصف كسول ولا يبني ما خرج عن الشاشة)
Future<void> _reveal(WidgetTester tester, Key target, Key row) async {
  for (final dx in [-260.0, 260.0]) {
    for (var i = 0; i < 8 && find.byKey(target).evaluate().isEmpty; i++) { await tester.drag(find.byKey(row), Offset(dx, 0)); await tester.pumpAndSettle(); }
    if (find.byKey(target).evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('market home shows the spotlight strip, categories, sort and filters, and searches by proximity', (tester) async {
    final srv = await _pump(tester, const MarketPage());
    expect(find.text('سبوت لايت'), findsOneWidget);
    expect(find.byKey(const Key('spot-$_lid')), findsOneWidget);
    expect(find.text('كوكيز'), findsOneWidget);
    expect(srv.calls.any((c) => c.startsWith('GET /market') && c.contains('lat=21.5')), isTrue);
    // ترتيب
    await tester.tap(find.byKey(const Key('market-sort'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-cheap'))); await tester.pumpAndSettle();
    expect(srv.calls.any((c) => c.contains('sort=cheap')), isTrue);
    // تصنيف بلا نتائج
    await _reveal(tester, const Key('cat-services'), const Key('cat-row')); await tester.tap(find.byKey(const Key('cat-services'))); await tester.pumpAndSettle();
    expect(find.text('لا نتائج'), findsOneWidget);
    await _reveal(tester, const Key('sub-education'), const Key('sub-row'));
    expect(find.byKey(const Key('sub-education')), findsOneWidget);
    // فلاتر: توصيل ونطاق
    await _reveal(tester, const Key('cat-all'), const Key('cat-row')); await tester.tap(find.byKey(const Key('cat-all'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-filters'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('f-delivery'))); await tester.tap(find.byKey(const Key('f-radius-5'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('f-apply'))); await tester.pumpAndSettle();
    expect(srv.calls.last, allOf(contains('delivery=1'), contains('radius=5')));
    expect(find.text('فلاتر · 2'), findsOneWidget);
  });

  testWidgets('listing page: seller badges, variant selection, coupon check, order with code dialog', (tester) async {
    final srv = await _pump(tester, const ListingPage(_lid));
    expect(find.text('كيك عيد ميلاد'), findsOneWidget);
    expect(find.text('بائع موثوق'), findsOneWidget);
    expect(find.text('هل يتوفر بدون سكر؟'), findsOneWidget);
    expect(find.text('رائع'), findsOneWidget);
    expect(find.text('اختر الخيار أولاً'), findsOneWidget);
    await tester.tap(find.byKey(const Key('variant-صغير'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('coupon')), 'welcome10');
    await tester.tap(find.text('تحقق')); await tester.pumpAndSettle();
    expect(find.text('خصم 22 ر.س'), findsOneWidget);
    expect(find.text('اطلب بالمحفظة · 198 ر.س'), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-btn'))); await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الطلب')); await tester.pumpAndSettle();
    final body = srv.bodies['POST /market/$_lid/order']!;
    expect(body['variant'], 'صغير'); expect(body['coupon'], 'WELCOME10'); expect(body['qty'], 1);
    expect(find.byKey(const Key('order-code')), findsOneWidget);
    expect(find.text('4321'), findsOneWidget);
  });

  testWidgets('order page for the buyer: code, stages, confirm receipt then review', (tester) async {
    final srv = await _pump(tester, const OrderPage(_oid));
    expect(find.text('4321'), findsOneWidget);
    expect(find.text('قيد التحضير'), findsOneWidget); // على الخط الزمني
    await tester.tap(find.byKey(const Key('order-confirm'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-go'))); await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /market/orders/$_oid/confirm'));
    expect(find.byKey(const Key('order-review')), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-review'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('star-4'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-send'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/orders/$_oid/review']!['rating'], 4);
  });

  testWidgets('order page for the seller: advance stages and confirm with the buyer code', (tester) async {
    final srv = _Srv()..asSeller = true;
    await _pump(tester, const OrderPage(_oid), srv: srv);
    expect(find.byKey(const Key('order-code')), findsNothing);
    expect(find.textContaining('عمولة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stage-preparing'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/orders/$_oid/stage']!['stage'], 'preparing');
    await tester.tap(find.byKey(const Key('stage-delivered'))); await tester.pumpAndSettle();
    expect(srv.orderStatus, 'delivered');
    await tester.tap(find.byKey(const Key('seller-code'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0000');
    await tester.tap(find.text('تأكيد')); await tester.pumpAndSettle();
    expect(find.text('الرمز غير صحيح'), findsOneWidget);
    await tester.tap(find.byKey(const Key('seller-code'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '4321');
    await tester.tap(find.text('تأكيد')); await tester.pumpAndSettle();
    expect(srv.orderStatus, 'completed');
  });

  testWidgets('wanted requests: list, detail with replies, and posting a new request', (tester) async {
    final srv = await _pump(tester, const WantedPage());
    expect(find.text('أبحث عن كيك تخرج'), findsOneWidget);
    await tester.tap(find.text('أبحث عن كيك تخرج')); await tester.pumpAndSettle();
    expect(find.text('لـ ٢٠ شخصاً'), findsOneWidget);
    expect(find.text('250 ر.س'), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wanted-new'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wanted-title')), 'مدرّس فيزياء');
    await tester.enterText(find.byKey(const Key('wanted-budget')), '200');
    await tester.tap(find.byKey(const Key('wanted-send'))); await tester.pumpAndSettle();
    final b = srv.bodies['POST /market/wanted']!;
    expect(b['title'], 'مدرّس فيزياء'); expect(b['budgetMax'], 20000); expect(b['lat'], 21.5);
  });

  testWidgets('seller dashboard shows numbers, coupons and spotlight, and buys spotlight days from the wallet', (tester) async {
    final srv = await _pump(tester, const SellerDashboardPage());
    expect(find.text('220 ر.س'), findsOneWidget);
    expect(find.text('WELCOME10 · 10٪'), findsOneWidget);
    expect(find.textContaining('120 ظهور'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-buy'))); await tester.pumpAndSettle();
    expect(find.text('3 يوم'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded).last); await tester.pumpAndSettle();
    expect(find.text('ادفع 80 ر.س من المحفظة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spot-pay'))); await tester.pumpAndSettle();
    expect(srv.bodies['POST /market/$_lid/spotlight']!['days'], 4);
    expect(find.textContaining('صار عرضك في سبوت لايت'), findsOneWidget);
  });
}
