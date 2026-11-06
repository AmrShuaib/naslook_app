// الدفع عند الاستلام في السوق (بند 10 من نواقص الإطلاق): علم العرض في النموذج، اختيار طريقة الدفع في صفحة العرض، مسار iOS بدل
// «الرصيد غير كافٍ»، بطاقات الطلب وصفحته للطرفين (القبول والاعتذار، «استلمت المبلغ»، «لم يحضر المشتري»، لا نزاع بل بلاغ)،
// وتوجيه الإشعارات الجديدة إلى الطلب؛ وقاعدة «لم يحضر» (٣ بائعين مختلفين خلال ٩٠ يوماً) ومسحها من الإدارة، ونصوص الأخطاء في iOS بلا المحفظة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/commerce_models.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/admin/admin_market.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111', _oid = '22222222-2222-4222-8222-222222222222';
final _seller = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null};
final _buyer = {'id': 'SA0000001', 'nickname': 'amr', 'avatarUrl': null};

Map<String, dynamic> _listing({bool cod = true, int price = 5000}) => {
      'id': _lid, 'seller': _seller, 'sellerRating': null, 'sellerRatingCount': 0, 'sellerBadges': [], 'kind': 'product', 'category': 'food', 'condition': 'new', 'delivery': false,
      'title': 'كيك عيد ميلاد', 'description': 'فانيلا', 'price': price, 'imageUrl': null, 'images': [], 'placeName': 'الروضة', 'city': 'جدة', 'lat': 21.5, 'lng': 39.1, 'status': 'active', 'stock': null, 'sold': 0, 'views': 1,
      'variants': [], 'availability': null, 'spotlight': false, 'mine': false, 'payOnReceipt': cod, 'createdAt': '2026-11-05T08:00:00Z',
    };
Map<String, dynamic> _order({String status = 'requested', bool asSeller = false, String payment = 'cod', String? cancelReason}) => {
      'id': _oid, 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'imageUrl': null, 'kind': 'product', 'qty': 1, 'total': 5000, 'discount': 0, 'commission': asSeller ? 0 : null, 'status': status, 'note': '', 'variant': null,
      'code': asSeller ? null : '4321', 'buyer': _buyer, 'seller': _seller, 'mineAsSeller': asSeller, 'reviewed': false, 'createdAt': '2026-11-06T10:00:00Z', 'payment': payment, 'cancelReason': cancelReason,
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  bool cod = true;
  int price = 5000;
  String status = 'requested', payment = 'cod';
  bool asSeller = false;
  /// طلب المحفظة يرد 402 (رصيد غير كافٍ)
  bool broke = false;
  /// مسح المدير «لم يحضر»
  bool cleared = false;
  String? cancelReason;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty && req.method != 'GET') { try { body = jsonDecode(req.body) as Map<String, dynamic>; (bodies[key] ??= []).add(body); } catch (_) {} }
    switch (key) {
      case 'GET /market/$_lid': return _json(_listing(cod: cod, price: price));
      case 'GET /market/$_lid/questions':
      case 'GET /market/$_lid/reviews': return _json([]);
      case 'POST /market/$_lid/view': return _json({'ok': true});
      case 'POST /market/$_lid/order':
        final isCod = body?['payment'] == 'cod';
        if (!isCod && broke) return _json({'error': 'insufficient-funds'}, 402);
        return _json({'ok': true, 'id': _oid, 'total': price, 'discount': 0, 'commission': 0, 'code': '4321', 'payment': isCod ? 'cod' : 'wallet', 'status': isCod ? 'requested' : 'paid'});
      case 'GET /market/orders': return _json([_order(status: status, asSeller: asSeller, payment: payment)]);
      case 'GET /market/orders/$_oid': return _json(_order(status: status, asSeller: asSeller, payment: payment, cancelReason: cancelReason));
      case 'POST /market/orders/$_oid/accept': status = 'paid'; return _json({'ok': true, 'status': 'paid'});
      case 'POST /market/orders/$_oid/decline': status = 'cancelled'; return _json({'ok': true, 'status': 'cancelled'});
      case 'POST /market/orders/$_oid/cash-received': status = 'completed'; return _json({'ok': true, 'status': 'completed'});
      case 'POST /market/orders/$_oid/no-show': status = 'cancelled'; return _json({'ok': true, 'status': 'cancelled', 'noShows': 1});
      case 'POST /market/orders/$_oid/cancel': status = 'cancelled'; return _json({'ok': true});
      case 'POST /market/orders/$_oid/confirm': status = 'completed'; return _json({'ok': true, 'status': 'completed'});
      case 'GET /adminapi/market/overview': return _json({'listings': {}, 'categories': [], 'topSellers': [], 'cities': [], 'pending': [], 'disputes': []});
      case 'GET /adminapi/market/no-shows': return _json({'days': 90, 'max': 3, 'items': [if (!cleared) {'order': _order(status: 'cancelled', cancelReason: 'no_show'), 'buyerNoShows': 3}]});
      case 'POST /adminapi/market/orders/$_oid/clear-no-show': cleared = true; return _json({'ok': true, 'noShows': 2});
      case 'GET /wallet': return _json({'balance': 0, 'points': 0, 'upcomingTickets': 0, 'testTopup': false, 'recent': []});
      case 'GET /wishlist/status': return _json({'saved': false});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv}) async {
  final s = srv ?? _Srv();
  tester.view.physicalSize = const Size(700, 2000); tester.view.devicePixelRatio = 1; addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), marketPosProvider.overrideWith((ref) async => (lat: 21.5, lng: 39.1))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _orderNow(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('order-btn')));
  await tester.tap(find.byKey(const Key('order-btn'))); await tester.pumpAndSettle();
  await tester.tap(find.text('تأكيد الطلب')); await tester.pumpAndSettle();
}

/// يفتح النموذج من زر ويعيد المسودة عند الحفظ.
class _FormHost extends StatelessWidget {
  final ValueChanged<ListingDraft?> onDone;
  const _FormHost({required this.onDone});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: TextButton(key: const Key('open-form'), onPressed: () async => onDone(await showListingForm(context)), child: const Text('افتح'))));
}

AppNotification _n(String kind, [Map<String, dynamic> data = const {}]) => AppNotification(id: 'n-$kind', kind: kind, title: kind, data: data);

void main() {
  tearDown(() => iosNativeOverride = null);

  group('listing form', () {
    testWidgets('pay on receipt is off by default, needs delivery or a pickup place, and is sent in the body', (tester) async {
      ListingDraft? draft; var done = false;
      await _pump(tester, _FormHost(onDone: (d) { draft = d; done = true; }));
      await tester.tap(find.byKey(const Key('open-form'))); await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('lf-cod'))).value, isFalse);
      await tester.enterText(find.byKey(const Key('lf-title')), 'كيك بالطلب');
      await tester.enterText(find.byKey(const Key('lf-price')), '50');
      await tester.tap(find.byKey(const Key('lf-cod'))); await tester.pumpAndSettle();
      expect(find.text('فعّل التوصيل أو اكتب مكان الاستلام في الخيارات الإضافية'), findsOneWidget);
      // بلا توصيل ولا مكان: لا يُغلق النموذج
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      expect(done, isFalse);
      expect(find.text('للدفع عند الاستلام فعّل التوصيل أو اكتب مكان الاستلام'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('lf-place')));
      await tester.enterText(find.byKey(const Key('lf-place')), 'الروضة'); await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(draft!.toBody()['payOnReceipt'], isTrue);
      expect(draft!.toBody()['placeName'], 'الروضة');
    });

    testWidgets('delivery alone is enough, and the default body sends payOnReceipt false', (tester) async {
      ListingDraft? draft;
      await _pump(tester, _FormHost(onDone: (d) => draft = d));
      await tester.tap(find.byKey(const Key('open-form'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lf-title')), 'عسل سدر');
      await tester.enterText(find.byKey(const Key('lf-price')), '90');
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      expect(draft!.toBody()['payOnReceipt'], isFalse);
      draft = null;
      await tester.tap(find.byKey(const Key('open-form'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lf-title')), 'عسل سدر');
      await tester.enterText(find.byKey(const Key('lf-price')), '90');
      await tester.tap(find.byKey(const Key('lf-delivery'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lf-cod'))); await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      expect(draft!.toBody()['payOnReceipt'], isTrue);
      expect(draft!.toBody()['delivery'], isTrue);
    });
  });

  group('checkout', () {
    testWidgets('a listing that allows it offers both methods; wallet by default on web, cod on choice', (tester) async {
      final srv = await _pump(tester, const ListingPage(_lid));
      expect(find.byKey(const Key('chip-cod')), findsOneWidget);
      expect(find.byKey(const Key('pay-wallet')), findsOneWidget);
      expect(find.byKey(const Key('pay-cod')), findsOneWidget);
      expect(find.text('اطلب بالمحفظة · 50 ر.س'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pay-cod'))); await tester.pumpAndSettle();
      expect(find.text('اطلب وادفع عند الاستلام · 50 ر.س'), findsOneWidget);
      expect(find.textContaining('لا نزاع على هذا الطلب'), findsOneWidget);
      await _orderNow(tester);
      expect(srv.bodies['POST /market/$_lid/order']!.single['payment'], 'cod');
      expect(find.text('أُرسل طلبك'), findsOneWidget);
      expect(find.textContaining('بانتظار قبول البائع'), findsOneWidget);
      expect(find.byKey(const Key('order-code')), findsOneWidget);
    });

    testWidgets('wallet stays the plain path: no payment field and no choice when the seller does not allow it', (tester) async {
      final srv = _Srv()..cod = false;
      await _pump(tester, const ListingPage(_lid), srv: srv);
      expect(find.byKey(const Key('pay-cod')), findsNothing);
      expect(find.byKey(const Key('chip-cod')), findsNothing);
      await _orderNow(tester);
      expect(srv.bodies['POST /market/$_lid/order']!.single.containsKey('payment'), isFalse);
      expect(find.text('تم الطلب'), findsOneWidget);
    });

    testWidgets('a free listing shows no payment choice even when the flag is on', (tester) async {
      final srv = _Srv()..price = 0;
      await _pump(tester, const ListingPage(_lid), srv: srv);
      expect(find.byKey(const Key('pay-cod')), findsNothing);
    });

    testWidgets('web: not enough balance offers pay on receipt instead of a dead end', (tester) async {
      final srv = _Srv()..broke = true;
      await _pump(tester, const ListingPage(_lid), srv: srv);
      await _orderNow(tester);
      expect(find.byKey(const Key('funds-cod')), findsOneWidget);
      await tester.tap(find.byKey(const Key('funds-use-cod'))); await tester.pumpAndSettle();
      final sent = srv.bodies['POST /market/$_lid/order']!;
      expect(sent.length, 2);
      expect(sent.first.containsKey('payment'), isFalse);
      expect(sent.last['payment'], 'cod');
      expect(find.text('أُرسل طلبك'), findsOneWidget);
    });
  });

  group('iOS', () {
    testWidgets('pay on receipt is preselected when the listing allows it', (tester) async {
      iosNativeOverride = true;
      final srv = await _pump(tester, const ListingPage(_lid));
      expect(find.text('اطلب وادفع عند الاستلام · 50 ر.س'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('pay-cod'))).selected, isTrue);
      await _orderNow(tester);
      expect(srv.bodies['POST /market/$_lid/order']!.single['payment'], 'cod');
      expect(find.byKey(const Key('funds-ios')), findsNothing);
    });

    testWidgets('choosing the wallet without balance still lands on pay on receipt', (tester) async {
      iosNativeOverride = true;
      final srv = _Srv()..broke = true;
      await _pump(tester, const ListingPage(_lid), srv: srv);
      await tester.tap(find.byKey(const Key('pay-wallet'))); await tester.pumpAndSettle();
      await _orderNow(tester);
      expect(find.byKey(const Key('funds-cod')), findsOneWidget);
      await tester.tap(find.byKey(const Key('funds-use-cod'))); await tester.pumpAndSettle();
      expect(srv.bodies['POST /market/$_lid/order']!.last['payment'], 'cod');
    });

    testWidgets('a listing without the flag: neutral message, no top-up suggestion', (tester) async {
      iosNativeOverride = true;
      final srv = _Srv()..cod = false..broke = true;
      await _pump(tester, const ListingPage(_lid), srv: srv);
      await _orderNow(tester);
      expect(find.byKey(const Key('funds-ios')), findsOneWidget);
      expect(find.text('المحفظة'), findsNothing);
      expect(find.textContaining('اشحن'), findsNothing);
    });
  });

  group('order cards and page', () {
    testWidgets('seller card: awaiting acceptance, pay-on-receipt chip and a quick accept', (tester) async {
      final srv = _Srv()..asSeller = true;
      await _pump(tester, const OrdersPage(), srv: srv);
      expect(find.text('طلب جديد · اقبله أو اعتذر'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('order-pay-$_oid')), matching: find.text('الدفع عند الاستلام')), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-accept-$_oid'))); await tester.pumpAndSettle();
      expect(srv.calls, contains('POST /market/orders/$_oid/accept'));
      expect(find.text('بدء التحضير'), findsOneWidget);
    });

    testWidgets('buyer card says plainly there is no dispute; a wallet card shows the wallet', (tester) async {
      await _pump(tester, const OrdersPage());
      expect(find.text('بانتظار قبول البائع'), findsOneWidget);
      expect(find.byKey(const Key('card-cod-note')), findsOneWidget);
      expect(find.text('رمزك 4321'), findsOneWidget);
      final w = _Srv()..payment = 'wallet'..status = 'paid';
      await _pump(tester, const OrdersPage(), srv: w);
      expect(find.byKey(const Key('card-cod-note')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('order-pay-$_oid')), matching: find.text('من المحفظة')), findsOneWidget);
    });

    testWidgets('buyer page before acceptance: awaiting banner, cancel and report, no confirm or dispute', (tester) async {
      final srv = await _pump(tester, const OrderPage(_oid));
      expect(find.byKey(const Key('order-awaiting')), findsOneWidget);
      expect(find.text('الدفع: عند الاستلام للبائع مباشرة'), findsOneWidget);
      expect(find.byKey(const Key('order-confirm')), findsNothing);
      expect(find.byKey(const Key('order-dispute')), findsNothing);
      expect(find.byKey(const Key('order-cod-note')), findsOneWidget);
      expect(find.byKey(const Key('order-report-seller')), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-cancel'))); await tester.pumpAndSettle();
      expect(srv.calls, contains('POST /market/orders/$_oid/cancel'));
      expect(find.text('أُلغي الطلب. لم يُخصم شيء لأن الدفع عند الاستلام.'), findsOneWidget);
    });

    testWidgets('buyer page after acceptance: confirm receipt, no dispute, report the seller opens the report sheet', (tester) async {
      final srv = _Srv()..status = 'paid';
      await _pump(tester, const OrderPage(_oid), srv: srv);
      expect(find.byKey(const Key('order-dispute')), findsNothing);
      expect(find.textContaining('ادفع للبائع 50 ر.س'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('order-report-seller')));
      await tester.tap(find.byKey(const Key('order-report-seller'))); await tester.pumpAndSettle();
      expect(find.text('إبلاغ عن البائع'), findsWidgets);
      await tester.tapAt(const Offset(10, 10)); await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('order-confirm')));
      await tester.tap(find.byKey(const Key('order-confirm'))); await tester.pumpAndSettle();
      expect(find.textContaining('سيكتمل الطلب. الدفع (50 ر.س)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-go'))); await tester.pumpAndSettle();
      expect(srv.calls, contains('POST /market/orders/$_oid/confirm'));
    });

    testWidgets('wallet order page keeps the dispute and says the money is held', (tester) async {
      final srv = _Srv()..payment = 'wallet'..status = 'paid';
      await _pump(tester, const OrderPage(_oid), srv: srv);
      expect(find.byKey(const Key('order-dispute')), findsOneWidget);
      expect(find.byKey(const Key('order-report-seller')), findsNothing);
      expect(find.text('الدفع: من المحفظة (محجوز حتى الاستلام)'), findsOneWidget);
    });

    testWidgets('seller page: decline with a reason', (tester) async {
      final srv = _Srv()..asSeller = true;
      await _pump(tester, const OrderPage(_oid), srv: srv);
      expect(find.byKey(const Key('order-accept')), findsOneWidget);
      expect(find.byKey(const Key('seller-code')), findsNothing);
      await tester.tap(find.byKey(const Key('order-decline'))); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'نفدت المكونات');
      await tester.tap(find.text('اعتذار').last); await tester.pumpAndSettle();
      expect(srv.bodies['POST /market/orders/$_oid/decline']!.single['reason'], 'نفدت المكونات');
    });

    testWidgets('seller page after acceptance: cash received completes; no-show cancels', (tester) async {
      final srv = _Srv()..asSeller = true..status = 'paid';
      await _pump(tester, const OrderPage(_oid), srv: srv);
      expect(find.text('إلغاء الطلب'), findsOneWidget);
      expect(find.text('إلغاء وردّ المبلغ'), findsNothing);
      await tester.tap(find.byKey(const Key('order-cash-received'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cash-go'))); await tester.pumpAndSettle();
      expect(srv.calls, contains('POST /market/orders/$_oid/cash-received'));
      expect(find.byKey(const Key('order-cash-received')), findsNothing);
      srv.status = 'preparing';
      final s2 = _Srv()..asSeller = true..status = 'preparing';
      await _pump(tester, const OrderPage(_oid), srv: s2);
      await tester.ensureVisible(find.byKey(const Key('order-no-show')));
      await tester.tap(find.byKey(const Key('order-no-show'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('no-show-go'))); await tester.pumpAndSettle();
      expect(s2.calls, contains('POST /market/orders/$_oid/no-show'));
    });
  });

  group('no-show rules and admin', () {
    testWidgets('a no-show the admin cleared reads as cleared to the buyer', (tester) async {
      final srv = _Srv()..status = 'cancelled'..cancelReason = 'no_show_cleared';
      await _pump(tester, const OrderPage(_oid), srv: srv);
      expect(find.text('أزالت الإدارة تسجيل عدم حضورك عن هذا الطلب، ولا يُحسب عليك.'), findsOneWidget);
    });

    testWidgets('the no-show dialog states the rule: three different sellers within 90 days', (tester) async {
      final srv = _Srv()..asSeller = true..status = 'preparing';
      await _pump(tester, const OrderPage(_oid), srv: srv);
      await tester.ensureVisible(find.byKey(const Key('order-no-show')));
      await tester.tap(find.byKey(const Key('order-no-show'))); await tester.pumpAndSettle();
      expect(find.textContaining('٣ بائعين مختلفين خلال ٩٠ يوماً'), findsOneWidget);
    });

    testWidgets('admin lists recent no-shows with the buyer count and clears one', (tester) async {
      final srv = await _pump(tester, const Scaffold(body: AdminMarketPage()));
      expect(find.textContaining('«لم يحضر المشتري» آخر ٩٠ يوماً'), findsOneWidget);
      expect(find.textContaining('المشتري amr (3 من ٣ · موقوف)'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('am-clear-ns-$_oid')));
      await tester.tap(find.byKey(const Key('am-clear-ns-$_oid'))); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'حضر المشتري');
      await tester.tap(find.text('مسح').last); await tester.pumpAndSettle();
      expect(srv.bodies['POST /adminapi/market/orders/$_oid/clear-no-show']!.single['note'], 'حضر المشتري');
      expect(find.byKey(const Key('am-clear-ns-$_oid')), findsNothing);
    });
  });

  group('iOS error text', () {
    const limit = ApiException(429, 'cod-limit', body: {'error': 'cod-limit', 'max': 3});
    const blocked = ApiException(403, 'cod-blocked', body: {'error': 'cod-blocked', 'noShows': 3, 'days': 90});
    test('web and Android point to the wallet as the other way to pay', () {
      iosNativeOverride = false;
      expect(marketErrText(limit), contains('المحفظة'));
      expect(marketErrText(blocked), allOf(contains('المحفظة'), contains('٣ بائعين مختلفين')));
    });
    test('iOS cannot top up, so the texts leave the wallet out', () {
      iosNativeOverride = true;
      expect(marketErrText(limit), isNot(contains('المحفظة')));
      expect(marketErrText(limit), contains('أكمل أحدها أو ألغه'));
      expect(marketErrText(blocked), isNot(contains('المحفظة')));
      expect(marketErrText(blocked), contains('أبلغ عن البائع'));
    });
  });

  test('new notification kinds open the order and have their own icon', () {
    final generic = notificationStyle('something_new').icon;
    for (final k in ['market_cod_order', 'market_cod_accepted', 'market_cod_completed']) {
      expect(notificationTarget(_n(k, {'orderId': _oid, 'payment': 'cod'})), isA<OrderPage>().having((p) => p.id, 'id', _oid), reason: k);
      expect(notificationTarget(_n(k)), isA<OrdersPage>(), reason: '$k بلا طلب');
      expect(notificationStyle(k).icon, isNot(generic), reason: k);
    }
  });

  test('order model: payment, open and active states', () {
    final o = Order.fromJson(_order());
    expect(o.cod, isTrue); expect(o.open, isTrue); expect(o.active, isFalse); expect(o.awaitingSeller, isTrue);
    expect(orderPaymentLabel(o), 'الدفع عند الاستلام');
    final w = Order.fromJson({..._order(status: 'paid', payment: 'wallet')}..remove('payment'));
    expect(w.cod, isFalse); expect(w.active, isTrue); expect(orderPaymentLabel(w), 'من المحفظة');
    expect(Listing.fromJson(_listing()).payOnReceipt, isTrue);
    expect(Listing.fromJson(_listing()..remove('payOnReceipt')).payOnReceipt, isFalse);
  });
}
