// طلبات الدوائر (نوفمبر 2026): «ادفع الآن من المحفظة» أو «احجز الآن وادفع في المكان» عند الشراء والحجز، وحوار iOS حين لا يكفي الرصيد،
// ومفتاح الصنف في المحرّر، وحالات الاستلام عند صاحب الدائرة (لم يُدفع بعد، تم الدفع، لم يحضر، المحجوز والمحرَّر)، وورقة «لدي مشكلة»
// وخيط النزاع، وقائمة نزاعات الدوائر في الإدارة، ووجهة إشعار biz_dispute.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/admin/admin_biz_disputes.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/business/biz_order_page.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/pages/business/owner/dashboard_catalog.dart';
import 'package:naslook/pages/business/owner/business_editor.dart' show ownerErrText;
import 'package:naslook/pages/business/owner/dashboard_orders.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart' show clockOf;

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _now = DateTime.now().toUtc();
final _slot = DateTime.now().add(const Duration(days: 2)).copyWith(hour: 18, minute: 0, second: 0, millisecond: 0, microsecond: 0);

Map<String, dynamic> _item(String id, {String kind = 'product', int price = 5000, bool venue = false}) => {
      'id': id, 'bizId': 'biz-shop', 'kind': kind, 'title': {'oil': 'زيت شعر', 'comb': 'مشط', 'cut': 'قص شعر'}[id] ?? id, 'description': '', 'price': price, 'unit': kind == 'clinic' ? 'visit' : 'item',
      'stock': kind == 'clinic' ? 1 : 10, 'meta': kind == 'clinic' ? {'times': ['18:00'], 'minutes': 30} : {}, 'active': true, 'payAtVenue': venue,
      if (kind == 'clinic') 'slots': [{'startsAt': _slot.toUtc().toIso8601String(), 'seatsLeft': 1}],
    };

Map<String, dynamic> _biz(String category, List<Map<String, dynamic>> items, {String role = 'none'}) => {
      'id': 'biz-shop', 'name': 'Shop', 'nameAr': 'متجر لمسة', 'category': category, 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '',
      'color': '#0058A3', 'highlights': [], 'verified': true, 'official': false, 'active': true, 'ownerId': 'SA0000009', 'myRole': role, 'followers': 0, 'itemsCount': items.length,
      'items': items, 'reviews': [], 'posts': [], 'myOrders': [], 'verificationStatus': 'approved', 'canSell': true,
    };

Map<String, dynamic> _order(String id, {String payment = 'wallet', bool paid = true, String? funds, String status = 'confirmed', DateTime? startAt, Map<String, dynamic>? dispute, bool disputable = false, String? viewer, String kind = 'product', int total = 5000, DateTime? createdAt, int? noShows}) => {
      'id': id, 'bizId': 'biz-shop', 'bizNameAr': 'متجر لمسة', 'category': 'shop', 'itemId': 'oil', 'title': 'زيت شعر', 'kind': kind, 'qty': 1, 'units': 1, 'total': total, 'status': status,
      'code': 'NAS-${id.toUpperCase()}', 'note': '', 'meta': {}, 'createdAt': (createdAt?.toUtc() ?? _now).toIso8601String(), if (noShows != null) 'noShows': noShows, 'cancellable': status == 'confirmed' && dispute == null, 'payment': payment, 'paid': paid,
      'funds': funds, 'releaseAt': _now.add(const Duration(days: 3)).toIso8601String(), if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(), 'dispute': dispute, 'disputable': disputable,
      if (viewer != null) 'viewer': viewer, 'customer': {'id': 'SA0000002', 'nickname': 'sara'},
    };

Map<String, dynamic> _dispute({bool open = true}) => {
      'status': open ? 'open' : 'resolved', 'reason': 'وصل المنتج مكسوراً', 'photos': ['/chat/media/a1b2c3-0123456789abcdef01234567.jpg'], 'resolution': open ? null : 'split', 'note': null,
      'messages': [{'by': 'team', 'text': 'نعتذر، نرسل بديلاً', 'at': _now.toIso8601String()}], 'createdAt': _now.toIso8601String(),
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic> biz;
  bool broke = false;
  List<Map<String, dynamic>> ownerOrders = [];
  List<Map<String, dynamic>> mine = [];
  Map<String, dynamic>? single;
  Map<String, dynamic> money = {'held': 5000, 'disputed': 0, 'released': 12000, 'venueDue': 5000, 'venuePaid': 0, 'disputesOpen': 0, 'noShows': 0, 'holdDays': 3};
  Map<String, dynamic> settings = {'testTopup': false, 'maxTopup': 100000, 'minTopup': 10000, 'maxCardTopup': 500000};
  _Srv(this.biz);
  Map<String, dynamic>? last(String key) => bodies[key]?.last;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.startsWith('{')) (bodies[key] ??= []).add(jsonDecode(req.body) as Map<String, dynamic>);
    if (key == 'GET /biz/biz-shop') return _json(biz);
    if (key == 'POST /biz/biz-shop/orders') {
      final b = last(key)!;
      if (broke && b['payment'] != 'at_venue') return _json({'error': 'insufficient-funds'}, 402);
      final venue = b['payment'] == 'at_venue';
      return _json(_order('o1', payment: venue ? 'at_venue' : 'wallet', paid: !venue, funds: venue ? null : 'held'));
    }
    if (key.startsWith('PATCH /biz/biz-shop/items/')) return _json({..._item(key.split('/').last), ...last(key)!});
    if (key == 'GET /biz/biz-shop/orders') return _json(ownerOrders);
    if (key == 'GET /biz/biz-shop/stats') {
      return _json({'orders': {'total': 2}, 'revenue': {'total': 10000}, 'byKind': [], 'daily': [], 'topItems': [], 'money': money});
    }
    if (key == 'POST /biz/biz-shop/checkin') return _json(_order('o2', payment: 'at_venue', paid: false, status: 'used'));
    if (key == 'POST /biz/biz-shop/orders/o2/paid') return _json(_order('o2', payment: 'at_venue', paid: true, status: 'used'));
    if (key == 'POST /biz/biz-shop/orders/o2/no-show') return _json({..._order('o2', payment: 'at_venue', paid: false, status: 'no_show'), 'noShows': 1});
    if (key == 'GET /biz/orders/mine') return _json(mine);
    if (key == 'GET /biz/orders/o1') return _json(single ?? _order('o1'));
    if (key == 'POST /biz/orders/o1/dispute') return _json(_order('o1', funds: 'held', dispute: {..._dispute(), 'reason': last(key)!['reason'], 'messages': []}, viewer: 'customer'));
    if (key == 'POST /biz/orders/o1/dispute/reply') return _json(single ?? _order('o1'));
    if (key == 'POST /chat/upload') return _json({'url': '/chat/media/p1abc2-0123456789abcdef01234567.jpg', 'type': 'image/jpeg', 'kind': 'image'});
    if (key == 'GET /adminapi/biz/disputes') return _json([{..._order('o1', funds: 'held', dispute: _dispute(), viewer: 'admin'), 'owner': {'id': 'SA0000009', 'nickname': 'lamsa'}}]);
    if (key == 'POST /adminapi/biz/disputes/o1') return _json({'ok': true});
    if (key == 'GET /adminapi/settings') return _json(settings);
    if (key == 'POST /adminapi/settings') return _json({...last(key)!});
    if (key == 'GET /adminapi/admins') return _json([]);
    if (key == 'GET /adminapi/payments/config') return _json({'enabled': false, 'provider': 'moyasar'});
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /wishlist') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? '';

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  tearDown(() {
    iosNativeOverride = null;
    pickImageOverride = null;
  });

  test('order money labels for the customer and the owner', () {
    final venue = BizOrder.fromJson(_order('a', payment: 'at_venue', paid: false));
    expect(venue.venueUnpaid, isTrue);
    expect(venue.paymentLabel, 'الدفع في المكان: لم يُدفع بعد');
    expect(BizOrder.fromJson(_order('a', payment: 'at_venue', paid: true)).paymentLabel, 'دُفع في المكان');
    expect(BizOrder.fromJson(_order('a', funds: 'held')).paymentLabel, 'من المحفظة · المبلغ محجوز حتى الاستلام');
    expect(BizOrder.fromJson(_order('a', funds: 'held', dispute: _dispute())).paymentLabel, contains('مجمّد'));
    expect(BizOrder.fromJson(_order('a', funds: 'credited')).ownerMoneyLabel, 'في محفظتك');
    expect(BizOrder.fromJson(_order('a', status: 'no_show')).statusLabel, 'لم يحضر');
    // طلب قديم بلا حقل payment: المدفوع من المحفظة، والمجاني مجاني
    expect(BizOrder.fromJson({'id': 'x', 'kind': 'product', 'total': 300, 'status': 'confirmed', 'code': 'C'}).payment, 'wallet');
    expect(BizOrder.fromJson({'id': 'x', 'kind': 'product', 'total': 0, 'status': 'confirmed', 'code': 'C'}).payment, 'free');
    expect(BizItem.fromJson(_item('oil', venue: true)).venueOk, isTrue);
    expect(BizItem.fromJson(_item('oil', venue: true, price: 0)).venueOk, isFalse);
    final d = BizOrder.fromJson(_order('a', dispute: _dispute(open: false))).dispute!;
    expect(d.open, isFalse);
    expect(d.resolutionLabel, 'قُسم المبلغ بين الطرفين');
    expect(d.messages.single.byLabel, 'الدائرة');
  });

  test('Arabic counts, admin money label, and when the team may cancel or mark a no-show', () {
    String days(int n) => arCount(n, one: 'يوم واحد', two: 'يومين', few: 'أيام', many: 'يوماً');
    expect([days(1), days(2), days(3), days(10), days(11), days(30)], ['يوم واحد', 'يومين', '3 أيام', '10 أيام', '11 يوماً', '30 يوماً']);
    // الإدارة لا تملك محفظة الدائرة
    expect(BizOrder.fromJson(_order('a', funds: 'released', viewer: 'admin')).ownerMoneyLabel, 'وصل محفظة الدائرة');
    expect(BizOrder.fromJson(_order('a', funds: 'released', viewer: 'team')).ownerMoneyLabel, 'في محفظتك');
    // بعد قرار النزاع لا إلغاء من الدائرة
    expect(BizOrder.fromJson(_order('a', funds: 'held')).ownerCancellable, isTrue);
    expect(BizOrder.fromJson(_order('a', funds: 'held', dispute: _dispute())).ownerCancellable, isTrue);
    expect(BizOrder.fromJson(_order('a', funds: 'split', dispute: _dispute(open: false))).ownerCancellable, isFalse);
    expect(BizOrder.fromJson(_order('a', funds: 'released', dispute: {..._dispute(open: false), 'resolution': 'release'})).ownerCancellable, isFalse);
    // «لم يحضر» للمنتج بعد يوم من الطلب، وللموعد بعد حلوله
    final now = DateTime.now();
    expect(BizOrder.fromJson(_order('a', payment: 'at_venue', paid: false, createdAt: now)).canNoShowAt(now), isFalse);
    expect(BizOrder.fromJson(_order('a', payment: 'at_venue', paid: false, createdAt: now.subtract(const Duration(hours: 25)))).canNoShowAt(now), isTrue);
    expect(BizOrder.fromJson(_order('a', payment: 'at_venue', paid: false, kind: 'clinic', startAt: now.add(const Duration(hours: 1)))).canNoShowAt(now), isFalse);
    expect(BizOrder.fromJson(_order('a', payment: 'at_venue', paid: false, kind: 'clinic', startAt: now.subtract(const Duration(minutes: 5)))).canNoShowAt(now), isTrue);
    // مسح رمز حجز سُجّل «لم يحضر»
    expect(ownerErrText(const ApiException(409, 'already-no_show')), 'سُجّل هذا الحجز: لم يحضر');
  });

  testWidgets('checkout: an item that allows it offers «احجز الآن وادفع في المكان» and books without the wallet', (tester) async {
    final srv = await _pump(tester, _Srv(_biz('shop', [_item('oil', venue: true)])), const BusinessPage(id: 'biz-shop'));
    await _tap(tester, find.widgetWithText(FilledButton, 'اشترِ'));
    expect(find.byKey(const Key('pay-wallet')), findsOneWidget);
    expect(find.textContaining('ادفع الآن من المحفظة'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('pay-venue')));
    expect(srv.last('POST /biz/biz-shop/orders')!['payment'], 'at_venue');
    expect(find.text('تم الحجز · الدفع في المكان'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('order-payment')), matching: find.text('الدفع في المكان: لم يُدفع بعد')), findsOneWidget);
    expect(find.textContaining('وادفع 50 ر.س للدائرة'), findsOneWidget);
  });

  testWidgets('checkout: an item without the flag keeps the single wallet button', (tester) async {
    final srv = await _pump(tester, _Srv(_biz('shop', [_item('comb', price: 2000)])), const BusinessPage(id: 'biz-shop'));
    await _tap(tester, find.widgetWithText(FilledButton, 'اشترِ'));
    expect(find.byKey(const Key('pay-venue')), findsNothing);
    expect(find.text('ادفع 20 ر.س من المحفظة'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('pay-wallet')));
    expect(srv.last('POST /biz/biz-shop/orders')!.containsKey('payment'), isFalse);
    expect(find.descendant(of: find.byKey(const Key('order-payment')), matching: find.text('من المحفظة · المبلغ محجوز حتى الاستلام')), findsOneWidget);
  });

  testWidgets('appointment: picking a slot asks how to pay', (tester) async {
    final srv = await _pump(tester, _Srv(_biz('salon', [_item('cut', kind: 'clinic', price: 6000, venue: true)])), const BusinessPage(id: 'biz-shop'));
    await _tap(tester, find.ancestor(of: find.textContaining(clockOf(_slot)), matching: find.byType(ChoiceChip)));
    await _tap(tester, find.textContaining('احجز · 60 ر.س'));
    expect(find.byKey(const Key('pay-choice')), findsOneWidget);
    expect(find.byKey(const Key('pay-venue')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('pay-venue')));
    final body = srv.last('POST /biz/biz-shop/orders')!;
    expect(body['payment'], 'at_venue');
    expect(DateTime.parse(body['startAt'] as String).toUtc(), _slot.toUtc());
  });

  testWidgets('iOS: insufficient funds offers pay at the venue and retries the order that way', (tester) async {
    iosNativeOverride = true;
    final srv = _Srv(_biz('shop', [_item('oil', venue: true)]))..broke = true;
    await _pump(tester, srv, const BusinessPage(id: 'biz-shop'));
    await _tap(tester, find.widgetWithText(FilledButton, 'اشترِ'));
    await _tap(tester, find.byKey(const Key('pay-wallet')));
    expect(find.byKey(const Key('biz-funds-ios')), findsOneWidget);
    expect(find.textContaining('اشحن'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'المحفظة'), findsNothing);
    await _tap(tester, find.byKey(const Key('biz-funds-venue')));
    expect(srv.bodies['POST /biz/biz-shop/orders']!.length, 2);
    expect(srv.last('POST /biz/biz-shop/orders')!['payment'], 'at_venue');
    expect(find.text('تم الحجز · الدفع في المكان'), findsOneWidget);
  });

  testWidgets('iOS: a wallet-only item keeps the plain insufficient-funds dialog', (tester) async {
    iosNativeOverride = true;
    final srv = _Srv(_biz('shop', [_item('comb', price: 2000)]))..broke = true;
    await _pump(tester, srv, const BusinessPage(id: 'biz-shop'));
    await _tap(tester, find.widgetWithText(FilledButton, 'اشترِ'));
    await _tap(tester, find.byKey(const Key('pay-wallet')));
    expect(find.byKey(const Key('biz-funds-ios')), findsOneWidget);
    expect(find.text('رصيد محفظتك لا يغطي هذا المبلغ'), findsOneWidget);
    expect(find.byKey(const Key('biz-funds-venue')), findsNothing);
  });

  testWidgets('item editor: «الدفع في المكان» is off by default and saves the flag', (tester) async {
    final srv = _Srv(_biz('shop', [_item('comb', price: 2000), _item('oil', venue: true)], role: 'owner'));
    await _pump(tester, srv, CatalogTab(biz: Biz.fromJson(srv.biz)));
    expect(_text(tester, 'catalog-line-oil'), contains('يُدفع في المكان'));
    expect(_text(tester, 'catalog-line-comb'), isNot(contains('يُدفع في المكان')));
    await _tap(tester, find.text('مشط'));
    final sw = find.byKey(const Key('item-pay-venue'));
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await _tap(tester, sw);
    await _tap(tester, find.widgetWithText(FilledButton, 'حفظ'));
    expect(srv.last('PATCH /biz/biz-shop/items/comb')!['payAtVenue'], isTrue);
  });

  testWidgets('owner: held vs released strip, venue booking «تم الدفع» and «لم يحضر»', (tester) async {
    final srv = _Srv(_biz('shop', [_item('oil', venue: true)], role: 'owner'))
      ..ownerOrders = [
        _order('o2', payment: 'at_venue', paid: false, startAt: DateTime.now().subtract(const Duration(hours: 1)), kind: 'clinic'),
        _order('o3', funds: 'held'),
        _order('o4', funds: 'held', dispute: _dispute()),
      ];
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv.biz))));
    expect(find.byKey(const Key('orders-money')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('orders-money-held')), matching: find.text('50 ر.س')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('orders-money-released')), matching: find.text('120 ر.س')), findsOneWidget);
    expect(_text(tester, 'owner-order-money-o2'), 'الدفع في المكان: لم يُدفع بعد');
    expect(_text(tester, 'owner-order-money-o3'), 'محجوز حتى الاستلام');
    expect(_text(tester, 'owner-order-money-o4'), contains('مجمّد'));
    // ورقة الطلب: «لم يُدفع بعد» مع «تم الدفع»
    await _tap(tester, find.textContaining('NAS-O2').first);
    expect(find.byKey(const Key('venue-unpaid-banner')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('owner-money-line')), matching: find.text('الدفع في المكان: لم يُدفع بعد')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('owner-venue-paid')));
    expect(srv.calls, contains('POST /biz/biz-shop/orders/o2/paid'));
    // «لم يحضر» بعد حلول الموعد، بعد تأكيد
    await _tap(tester, find.textContaining('NAS-O2').first);
    await _tap(tester, find.byKey(const Key('owner-no-show')));
    await _tap(tester, find.widgetWithText(FilledButton, 'لم يحضر'));
    expect(srv.calls, contains('POST /biz/biz-shop/orders/o2/no-show'));
    // الطلب المحجوز: الإلغاء يعيد من المحجوز بلا خصم من المحفظة
    await _tap(tester, find.textContaining('NAS-O3').first);
    await _tap(tester, find.text('إلغاء واسترداد المبلغ للعميل'));
    expect(find.descendant(of: find.byKey(const Key('owner-cancel-dialog')), matching: find.textContaining('ولا يُخصم شيء من محفظتك')), findsOneWidget);
  });

  testWidgets('owner: strip counts days in Arabic and shows «تجمّد» only when held money is frozen', (tester) async {
    final srv = _Srv(_biz('shop', [], role: 'owner'))..money = {'held': 0, 'disputed': 0, 'released': 9000, 'venueDue': 0, 'venuePaid': 0, 'disputesOpen': 1, 'noShows': 0, 'holdDays': 1};
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv.biz))));
    final note = _text(tester, 'orders-money-note');
    expect(note, contains('بعد يوم واحد من الموعد'));
    expect(note, contains('مشكلة مفتوحة'));
    expect(note, isNot(contains('تجمّد')));
    expect(note, isNot(contains('أيام')));
    final srv2 = _Srv(_biz('shop', [], role: 'owner'))..money = {'held': 5000, 'disputed': 5000, 'released': 0, 'venueDue': 0, 'venuePaid': 0, 'disputesOpen': 2, 'noShows': 0, 'holdDays': 14};
    await _pump(tester, srv2, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv2.biz))));
    expect(_text(tester, 'orders-money-note'), allOf(contains('بعد 14 يوماً'), contains('مشكلتان مفتوحتان تجمّد 50 ر.س')));
  });

  testWidgets('owner: no cancel after a dispute decision; a product booked at the venue gets «لم يحضر» only after a day', (tester) async {
    final srv = _Srv(_biz('shop', [_item('oil', venue: true)], role: 'owner'))
      ..ownerOrders = [
        _order('o5', funds: 'split', dispute: _dispute(open: false)),
        _order('o6', funds: 'held'),
        _order('o7', payment: 'at_venue', paid: false),
        _order('o8', payment: 'at_venue', paid: false, createdAt: DateTime.now().subtract(const Duration(hours: 25))),
      ];
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv.biz))));
    await _tap(tester, find.textContaining('NAS-O5').first);
    expect(find.byKey(const Key('owner-open-dispute')), findsOneWidget);
    expect(find.byKey(const Key('owner-cancel-order')), findsNothing);
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);
    await _tap(tester, find.textContaining('NAS-O6').first);
    expect(find.byKey(const Key('owner-cancel-order')), findsOneWidget);
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);
    await _tap(tester, find.textContaining('NAS-O7').first);
    expect(find.byKey(const Key('venue-unpaid-banner')), findsOneWidget);
    expect(find.byKey(const Key('owner-no-show')), findsNothing);
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);
    await _tap(tester, find.textContaining('NAS-O8').first);
    expect(find.byKey(const Key('owner-no-show')), findsOneWidget);
  });

  testWidgets('order page: no-show count in Arabic for the team, and the admin sees the circle wallet', (tester) async {
    final srv = _Srv(_biz('shop', []))..single = _order('o1', payment: 'at_venue', paid: false, viewer: 'team', noShows: 2);
    await _pump(tester, srv, const BizOrderPage(orderId: 'o1'));
    expect(find.descendant(of: find.byKey(const Key('order-no-shows')), matching: find.text('مرتان')), findsOneWidget);
    final srv2 = _Srv(_biz('shop', []))..single = _order('o1', funds: 'released', viewer: 'admin');
    await _pump(tester, srv2, const BizOrderPage(orderId: 'o1'));
    expect(find.descendant(of: find.byKey(const Key('order-payment-line')), matching: find.text('وصل محفظة الدائرة')), findsOneWidget);
    expect(find.text('في محفظتك'), findsNothing);
  });

  testWidgets('admin settings: «أيام حجز المبلغ» shows the default and saves within 1..30', (tester) async {
    final srv = _Srv(_biz('shop', []));
    await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
    // الصفحة طويلة: شاشة أطول حتى يُبنى قسم «طلبات الدوائر» وزر الحفظ
    tester.view.physicalSize = const Size(600, 3600);
    await _settle(tester);
    final field = find.byKey(const Key('set-biz-hold-days'));
    await tester.scrollUntilVisible(field, 300, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextField>(field).controller!.text, '3');
    await tester.enterText(field, '7');
    Future<void> save() async {
      await tester.scrollUntilVisible(find.byKey(const Key('set-save')), 400, scrollable: find.byType(Scrollable).first);
      await _tap(tester, find.byKey(const Key('set-save')));
    }
    await save();
    expect(srv.last('POST /adminapi/settings')!['bizHoldDays'], 7);
    await tester.scrollUntilVisible(field, -300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(field, '45');
    await save();
    expect(srv.last('POST /adminapi/settings')!['bizHoldDays'], 30);
  });

  testWidgets('owner: checking in a venue booking by code asks to confirm the payment', (tester) async {
    final srv = _Srv(_biz('shop', [_item('oil', venue: true)], role: 'owner'));
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv.biz))));
    await _tap(tester, find.byKey(const Key('orders-checkin-code')));
    await tester.enterText(find.byType(TextField).last, 'NAS-O2');
    await _tap(tester, find.widgetWithText(FilledButton, 'تأكيد'));
    expect(srv.calls, contains('POST /biz/biz-shop/checkin'));
    expect(find.byKey(const Key('checkin-venue-dialog')), findsOneWidget);
    expect(find.text('الدفع في المكان: لم يُدفع بعد'), findsWidgets);
    await _tap(tester, find.byKey(const Key('checkin-venue-paid')));
    expect(srv.calls, contains('POST /biz/biz-shop/orders/o2/paid'));
  });

  testWidgets('customer: «لدي مشكلة» sends the reason and a photo', (tester) async {
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'p.jpg');
    final srv = _Srv(_biz('shop', []))..mine = [_order('o1', funds: 'held', disputable: true)];
    await _pump(tester, srv, const MyBookingsPage());
    await _tap(tester, find.textContaining('زيت شعر').first);
    expect(find.descendant(of: find.byKey(const Key('order-payment')), matching: find.text('من المحفظة · المبلغ محجوز حتى الاستلام')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('order-dispute')));
    expect(find.textContaining('يتجمد المبلغ المحجوز'), findsOneWidget);
    // سبب قصير يُرفض محلياً بلا طلب
    await tester.enterText(find.byKey(const Key('dispute-reason')), 'سيء');
    await _tap(tester, find.byKey(const Key('dispute-submit')));
    expect(srv.calls.where((c) => c == 'POST /biz/orders/o1/dispute'), isEmpty);
    await tester.enterText(find.byKey(const Key('dispute-reason')), 'وصل المنتج مكسوراً');
    await _tap(tester, find.byKey(const Key('dispute-photo')));
    expect(srv.calls, contains('POST /chat/upload'));
    await _tap(tester, find.byKey(const Key('dispute-submit')));
    final body = srv.last('POST /biz/orders/o1/dispute')!;
    expect(body['reason'], 'وصل المنتج مكسوراً');
    expect(body['photos'], ['/chat/media/p1abc2-0123456789abcdef01234567.jpg']);
  });

  testWidgets('order page: the team sees the dispute thread and replies', (tester) async {
    final srv = _Srv(_biz('shop', []))..single = _order('o1', funds: 'held', dispute: _dispute(), viewer: 'team');
    await _pump(tester, srv, const BizOrderPage(orderId: 'o1'));
    expect(find.byKey(const Key('dispute-thread')), findsOneWidget);
    expect(find.text('وصل المنتج مكسوراً'), findsOneWidget);
    expect(find.text('نعتذر، نرسل بديلاً'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('order-payment-line')), matching: find.text('محجوز ومجمّد بنزاع')), findsOneWidget);
    // الفريق لا يحسم: أزرار الحسم للإدارة فقط
    expect(find.byKey(const Key('order-resolve-refund')), findsNothing);
    await tester.enterText(find.byKey(const Key('dispute-reply-field')), 'أرسلنا البديل اليوم');
    await _tap(tester, find.byKey(const Key('dispute-reply-send')));
    expect(srv.last('POST /biz/orders/o1/dispute/reply')!['text'], 'أرسلنا البديل اليوم');
  });

  testWidgets('order page: the admin resolves from the order', (tester) async {
    final srv = _Srv(_biz('shop', []))..single = _order('o1', funds: 'held', dispute: _dispute(), viewer: 'admin');
    await _pump(tester, srv, const BizOrderPage(orderId: 'o1'));
    await _tap(tester, find.byKey(const Key('order-resolve-split')));
    await _tap(tester, find.widgetWithText(FilledButton, 'تنفيذ'));
    expect(srv.last('POST /adminapi/biz/disputes/o1')!['resolution'], 'split');
  });

  testWidgets('admin: circle disputes list with both parties and resolve buttons', (tester) async {
    final srv = _Srv(_biz('shop', []));
    await _pump(tester, srv, const Scaffold(body: SingleChildScrollView(child: BizDisputesAdmin())));
    expect(find.text('نزاعات الدوائر (1)'), findsOneWidget);
    expect(find.textContaining('صاحب الدائرة lamsa'), findsOneWidget);
    expect(find.textContaining('المبلغ محجوز لدى المنصة'), findsOneWidget);
    expect(find.text('السبب: وصل المنتج مكسوراً'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('cd-refund-o1')));
    await tester.enterText(find.byType(TextField).last, 'المنتج تالف');
    await _tap(tester, find.widgetWithText(FilledButton, 'تنفيذ'));
    final body = srv.last('POST /adminapi/biz/disputes/o1')!;
    expect(body['resolution'], 'refund');
    expect(body['note'], 'المنتج تالف');
  });

  test('biz_dispute notifications open the order (or the right list without it)', () {
    AppNotification n(Map<String, dynamic> data) => AppNotification(id: '1', kind: 'biz_dispute', title: 't', data: data);
    final page = notificationTarget(n({'orderId': 'o1', 'bizId': 'biz-shop', 'side': 'team'}));
    expect(page, isA<BizOrderPage>());
    expect((page as BizOrderPage).orderId, 'o1');
    expect(notificationTarget(n({'side': 'admin'})), isA<AdminShell>());
    expect(notificationTarget(n({'side': 'customer'})), isA<MyBookingsPage>());
    expect(notificationStyle('biz_dispute').icon, Icons.gavel_rounded);
  });
}
