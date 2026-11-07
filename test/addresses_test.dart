// دفتر العناوين والتوصيل في السوق (بند 13 من نواقص الإطلاق): «عناويني» (القائمة والإضافة والتحقق والحذف والافتراضي والحد)،
// مدخله في ماي سبيس، حقول رسم التوصيل وأقصى مسافة في نموذج العرض، اختيار «استلام/توصيل» والعنوان والرسم في الإجمالي عند الطلب،
// وبطاقة التوصيل في الطلب بحسب الطرف (المشتري، البائع قبل القبول، بعد المحو).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/addresses/addresses_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111', _oid = '22222222-2222-4222-8222-222222222222';
const _home = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01', _work = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02';
final _seller = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null};
final _buyer = {'id': 'SA0000001', 'nickname': 'amr', 'avatarUrl': null};
Map<String, dynamic> _addr(String id, String label, {bool def = false, double? lat = 21.55, double? lng = 39.16, String? phone = '+966551234567'}) =>
    {'id': id, 'label': label, 'district': label == 'العمل' ? 'الشاطئ' : 'الروضة', 'details': 'شارع الأمير سلطان', 'city': 'جدة', 'lat': lat, 'lng': lng, 'phone': phone, 'isDefault': def};

class _Srv {
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> book = [_addr(_home, 'البيت', def: true), _addr(_work, 'العمل', phone: null)];
  bool delivery = true, cod = false;
  int fee = 1500;
  String status = 'paid', payment = 'wallet';
  bool asSeller = false, purged = false, tooFar = false, orderDelivery = true;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> listing() => {
        'id': _lid, 'seller': _seller, 'sellerRating': null, 'sellerRatingCount': 0, 'sellerBadges': [], 'kind': 'product', 'category': 'food', 'condition': 'new', 'delivery': delivery, 'deliveryFee': fee, 'deliveryMaxKm': 20,
        'title': 'كيك عيد ميلاد', 'description': 'فانيلا', 'price': 5000, 'imageUrl': null, 'images': [], 'placeName': 'الروضة', 'city': 'جدة', 'lat': 21.5, 'lng': 39.1, 'status': 'active', 'stock': null, 'sold': 0, 'views': 1,
        'variants': [], 'availability': null, 'spotlight': false, 'mine': false, 'payOnReceipt': cod, 'createdAt': '2026-11-05T08:00:00Z',
      };
  Map<String, dynamic> order() => {
        'id': _oid, 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'imageUrl': null, 'kind': 'product', 'qty': 1, 'total': 5000 + (orderDelivery ? fee : 0), 'discount': 0, 'commission': asSeller ? 0 : null, 'status': status, 'note': '', 'variant': null,
        'code': asSeller ? null : '4321', 'buyer': _buyer, 'seller': _seller, 'mineAsSeller': asSeller, 'reviewed': false, 'createdAt': '2026-11-06T10:00:00Z', 'payment': payment,
        'fulfilment': orderDelivery ? 'delivery' : 'pickup', 'deliveryFee': orderDelivery ? fee : 0, 'deliveryKm': orderDelivery ? 1.5 : null, 'addressPurged': purged,
        'address': orderDelivery && !purged && !(asSeller && status == 'requested') ? {'label': 'البيت', 'district': 'الروضة', 'details': 'شارع الأمير سلطان', 'city': 'جدة', 'lat': 21.55, 'lng': 39.16, 'phone': '+966551234567'} : null,
      };
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty && req.method != 'GET') { try { body = jsonDecode(req.body) as Map<String, dynamic>; (bodies[key] ??= []).add(body); } catch (_) {} }
    switch (key) {
      case 'GET /me/addresses': return _json({'items': book, 'max': 10});
      case 'POST /me/addresses':
        if (book.length >= 10) return _json({'error': 'address-limit', 'max': 10}, 409);
        final a = {..._addr('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa${(10 + book.length).toString()}', body!['label'] as String, def: book.isEmpty, lat: null, lng: null, phone: null), 'district': body['district'], 'details': body['details'] ?? ''};
        book = [...book, a];
        return _json(a);
      case 'GET /market/$_lid': return _json(listing());
      case 'GET /market/$_lid/questions':
      case 'GET /market/$_lid/reviews': return _json([]);
      case 'POST /market/$_lid/view': return _json({'ok': true});
      case 'POST /market/$_lid/order':
        if (tooFar && body?['fulfilment'] == 'delivery') return _json({'error': 'too-far', 'km': 33.2, 'maxKm': 20}, 400);
        final d = body?['fulfilment'] == 'delivery';
        return _json({'ok': true, 'id': _oid, 'total': 5000 + (d ? fee : 0), 'discount': 0, 'commission': 0, 'code': '4321', 'payment': 'wallet', 'status': 'paid', 'fulfilment': d ? 'delivery' : 'pickup', 'deliveryFee': d ? fee : 0});
      case 'GET /market/orders': return _json([order()]);
      case 'GET /market/orders/$_oid': return _json(order());
      case 'GET /wallet': return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': false, 'recent': []});
      case 'GET /wishlist/status': return _json({'saved': false});
      case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
      case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
      case 'GET /me/map-presence': return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread': return _json({'unread': 0});
    }
    final m = RegExp(r'^(PATCH|DELETE|POST) /me/addresses/([0-9a-f-]{36})(/default)?$').firstMatch(key);
    if (m != null) {
      final i = book.indexWhere((a) => a['id'] == m.group(2));
      if (i < 0) return _json({'error': 'not-found'}, 404);
      if (m.group(1) == 'DELETE') { book = [...book]..removeAt(i); return _json({'ok': true}); }
      if (m.group(3) != null) { book = [for (final a in book) {...a, 'isDefault': a['id'] == m.group(2)}]; return _json(book[i]); }
      book = [...book]; book[i] = {...book[i], ...?body}; return _json(book[i]);
    }
    if (req.method == 'GET') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv, Size size = const Size(700, 2000)}) async {
  final s = srv ?? _Srv();
  tester.view.physicalSize = size; tester.view.devicePixelRatio = 1; addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      marketPosProvider.overrideWith((ref) async => (lat: 21.5, lng: 39.1)), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _orderNow(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('order-btn')));
  await tester.tap(find.byKey(const Key('order-btn'))); await tester.pumpAndSettle();
  await tester.tap(find.text('تأكيد الطلب')); await tester.pumpAndSettle();
}

class _FormHost extends StatelessWidget {
  final ValueChanged<ListingDraft?> onDone;
  const _FormHost({required this.onDone});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: TextButton(key: const Key('open-form'), onPressed: () async => onDone(await showListingForm(context)), child: const Text('افتح'))));
}

void main() {
  final opened = <Uri>[];
  setUp(() { SharedPreferences.setMockInitialValues({}); opened.clear(); LegalLinks.openOverride = (u) async => opened.add(u); });
  tearDown(() => LegalLinks.openOverride = null);

  group('عناويني', () {
    testWidgets('lists my addresses with the default first and badge', (tester) async {
      await _pump(tester, const AddressesPage());
      expect(find.byKey(const Key('addr-$_home')), findsOneWidget);
      expect(find.byKey(const Key('addr-$_work')), findsOneWidget);
      expect(find.text('الافتراضي'), findsOneWidget);
      expect(find.textContaining('2 من 10'), findsOneWidget);
      expect(find.byKey(const Key('addresses-add')), findsOneWidget);
    });

    testWidgets('empty book invites to add the first address', (tester) async {
      final s = _Srv()..book = [];
      await _pump(tester, const AddressesPage(), srv: s);
      expect(find.byKey(const Key('addresses-add-first')), findsOneWidget);
      expect(find.textContaining('لا يراه إلا أنت'), findsOneWidget);
    });

    testWidgets('add: label chip, district required, phone checked before sending', (tester) async {
      final s = await _pump(tester, const AddressesPage());
      await tester.tap(find.byKey(const Key('addresses-add'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-label-العمل'))); await tester.pump();
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      expect(find.text('اكتب اسم الحي'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('addr-district')), 'الحمراء');
      await tester.enterText(find.byKey(const Key('addr-phone')), '12345');
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      expect(find.textContaining('رقم الجوال غير صحيح'), findsOneWidget);
      expect(s.bodies['POST /me/addresses'], isNull);
      await tester.enterText(find.byKey(const Key('addr-phone')), '0551234567');
      await tester.enterText(find.byKey(const Key('addr-details')), 'عمارة ٥');
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      final b = s.bodies['POST /me/addresses']!.single;
      expect(b['label'], 'العمل');
      expect(b['district'], 'الحمراء');
      expect(b['phone'], '0551234567');
      expect(b['details'], 'عمارة ٥');
      expect(b['lat'], isNull);
      expect(find.byType(AddressesPage), findsOneWidget);
      expect(s.calls.where((c) => c == 'GET /me/addresses').length, greaterThanOrEqualTo(2));
    });

    testWidgets('custom label via «أخرى»', (tester) async {
      final s = await _pump(tester, const AddressesPage());
      await tester.tap(find.byKey(const Key('addresses-add'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-label-other'))); await tester.pump();
      await tester.enterText(find.byKey(const Key('addr-label')), 'الاستراحة');
      await tester.enterText(find.byKey(const Key('addr-district')), 'أبحر');
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      expect(s.bodies['POST /me/addresses']!.single['label'], 'الاستراحة');
    });

    testWidgets('edit keeps the point, clearing it sends null', (tester) async {
      final s = await _pump(tester, const AddressesPage());
      await tester.tap(find.byKey(const Key('addr-menu-$_home'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-edit'))); await tester.pumpAndSettle();
      expect(find.text('الموقع محدد على الخريطة'), findsOneWidget);
      expect(find.text('0551234567'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addr-point-clear'))); await tester.pump();
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      final b = s.bodies['PATCH /me/addresses/$_home']!.single;
      expect(b['lat'], isNull);
      expect(b['lng'], isNull);
      expect(b['label'], 'البيت');
    });

    testWidgets('make default and delete from the menu', (tester) async {
      final s = await _pump(tester, const AddressesPage());
      await tester.tap(find.byKey(const Key('addr-menu-$_work'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-make-default'))); await tester.pumpAndSettle();
      expect(s.calls, contains('POST /me/addresses/$_work/default'));
      await tester.tap(find.byKey(const Key('addr-menu-$_home'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-delete'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addr-delete-go'))); await tester.pumpAndSettle();
      expect(s.calls, contains('DELETE /me/addresses/$_home'));
      expect(find.byKey(const Key('addr-$_home')), findsNothing);
    });

    testWidgets('ten addresses: no add button, the limit is explained', (tester) async {
      final s = _Srv()..book = [for (var i = 0; i < 10; i++) _addr('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa${(20 + i)}', 'عنوان $i', def: i == 0)];
      await _pump(tester, const AddressesPage(), srv: s);
      expect(find.byKey(const Key('addresses-add')), findsNothing);
      expect(find.textContaining('وهو الحد'), findsOneWidget);
    });

    testWidgets('My Space opens «عناويني»', (tester) async {
      await _pump(tester, const Scaffold(body: MySpacePage()), size: const Size(420, 1400));
      await tester.scrollUntilVisible(find.byKey(const Key('my-addresses')), 300);
      await tester.ensureVisible(find.byKey(const Key('my-addresses'))); await tester.pump();
      await tester.tap(find.byKey(const Key('my-addresses'))); await tester.pumpAndSettle();
      expect(find.byType(AddressesPage), findsOneWidget);
    });
  });

  group('listing form', () {
    testWidgets('delivery fee and max distance appear with delivery and go in the body', (tester) async {
      ListingDraft? got;
      await _pump(tester, _FormHost(onDone: (d) => got = d));
      await tester.tap(find.byKey(const Key('open-form'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lf-title')), 'كيك عيد ميلاد');
      await tester.enterText(find.byKey(const Key('lf-price')), '50');
      expect(find.byKey(const Key('lf-delivery-fee')), findsNothing);
      await tester.tap(find.byKey(const Key('lf-delivery'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lf-delivery-fee')), '١٥');
      await tester.enterText(find.byKey(const Key('lf-delivery-km')), '900');
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      expect(got, isNull);
      expect(find.textContaining('أقصى مسافة من ١ إلى ٥٠٠ كم'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('lf-delivery-km')), '20');
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      final b = got!.toBody();
      expect(b['delivery'], true);
      expect(b['deliveryFee'], 1500);
      expect(b['deliveryMaxKm'], 20.0);
    });

    testWidgets('without delivery the fee is not sent', (tester) async {
      ListingDraft? got;
      await _pump(tester, _FormHost(onDone: (d) => got = d));
      await tester.tap(find.byKey(const Key('open-form'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lf-title')), 'قهوة مختصة');
      await tester.ensureVisible(find.byKey(const Key('lf-submit')));
      await tester.tap(find.byKey(const Key('lf-submit'))); await tester.pumpAndSettle();
      final b = got!.toBody();
      expect(b['deliveryFee'], 0);
      expect(b['deliveryMaxKm'], isNull);
    });
  });

  group('checkout', () {
    testWidgets('pickup by default when the listing has a place; delivery picks the default address and adds the fee', (tester) async {
      final s = await _pump(tester, const ListingPage(_lid));
      expect(find.byKey(const Key('delivery-choice')), findsOneWidget);
      expect(find.textContaining('توصيل · 15 ر.س'), findsOneWidget);
      expect(find.textContaining('اطلب بالمحفظة · 50 ر.س'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('ful-delivery')));
      await tester.tap(find.byKey(const Key('ful-delivery'))); await tester.pumpAndSettle();
      expect(find.byKey(const Key('delivery-address')), findsOneWidget);
      expect(find.textContaining('الروضة'), findsWidgets);
      expect(find.textContaining('اطلب بالمحفظة · 65 ر.س'), findsOneWidget);
      expect(find.byKey(const Key('order-fee-line')), findsOneWidget);
      expect(find.byKey(const Key('delivery-range')), findsOneWidget);
      await _orderNow(tester);
      final b = s.bodies['POST /market/$_lid/order']!.single;
      expect(b['fulfilment'], 'delivery');
      expect(b['addressId'], _home);
    });

    testWidgets('pickup sends no address', (tester) async {
      final s = await _pump(tester, const ListingPage(_lid));
      await _orderNow(tester);
      final b = s.bodies['POST /market/$_lid/order']!.single;
      expect(b.containsKey('fulfilment'), false);
      expect(b.containsKey('addressId'), false);
    });

    testWidgets('change the address from the sheet', (tester) async {
      final s = await _pump(tester, const ListingPage(_lid));
      await tester.ensureVisible(find.byKey(const Key('ful-delivery')));
      await tester.tap(find.byKey(const Key('ful-delivery'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delivery-address'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-addr-$_work'))); await tester.pumpAndSettle();
      await _orderNow(tester);
      expect(s.bodies['POST /market/$_lid/order']!.single['addressId'], _work);
    });

    testWidgets('no saved address: ordering opens the sheet and an inline new address is used', (tester) async {
      final s = _Srv()..book = [];
      await _pump(tester, const ListingPage(_lid), srv: s);
      await tester.ensureVisible(find.byKey(const Key('ful-delivery')));
      await tester.tap(find.byKey(const Key('ful-delivery'))); await tester.pumpAndSettle();
      expect(find.byKey(const Key('delivery-pick')), findsOneWidget);
      expect(find.textContaining('اختر عنوان التوصيل'), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('order-btn')));
      await tester.tap(find.byKey(const Key('order-btn'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-addr-add'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('addr-district')), 'الصفا');
      await tester.tap(find.byKey(const Key('addr-save'))); await tester.pumpAndSettle();
      // يعود إلى ورقة الملاحظة مباشرة بالعنوان الجديد
      await tester.tap(find.text('تأكيد الطلب')); await tester.pumpAndSettle();
      final b = s.bodies['POST /market/$_lid/order']!.single;
      expect(b['fulfilment'], 'delivery');
      expect(b['addressId'], s.book.single['id']);
    });

    testWidgets('too far: the seller\'s range is explained', (tester) async {
      final s = _Srv()..tooFar = true;
      await _pump(tester, const ListingPage(_lid), srv: s);
      await tester.ensureVisible(find.byKey(const Key('ful-delivery')));
      await tester.tap(find.byKey(const Key('ful-delivery'))); await tester.pumpAndSettle();
      await _orderNow(tester);
      expect(find.textContaining('عنوانك أبعد من مسافة التوصيل (20 كم)'), findsOneWidget);
    });

    testWidgets('a listing without delivery shows no choice', (tester) async {
      final s = _Srv()..delivery = false;
      await _pump(tester, const ListingPage(_lid), srv: s);
      expect(find.byKey(const Key('delivery-choice')), findsNothing);
      expect(s.calls.contains('GET /me/addresses'), false);
    });

    testWidgets('free delivery is labelled free', (tester) async {
      final s = _Srv()..fee = 0;
      await _pump(tester, const ListingPage(_lid), srv: s);
      expect(find.textContaining('توصيل · مجاني'), findsOneWidget);
    });
  });

  group('order', () {
    testWidgets('buyer: delivery chip on the card, address with call and directions on the page', (tester) async {
      await _pump(tester, const OrdersPage());
      expect(find.byKey(const Key('order-ful-$_oid')), findsOneWidget);
      await tester.tap(find.text('كيك عيد ميلاد')); await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-delivery')), findsOneWidget);
      expect(find.byKey(const Key('order-address')), findsOneWidget);
      expect(find.textContaining('15 ر.س · 1.5 كم'), findsOneWidget);
      expect(find.textContaining('منها توصيل 15 ر.س'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('order-address-call')));
      await tester.tap(find.byKey(const Key('order-address-call'))); await tester.pump();
      await tester.tap(find.byKey(const Key('order-address-directions'))); await tester.pump();
      expect(opened.first.toString(), 'tel:+966551234567');
      expect(opened.last.host, 'www.google.com');
      expect(opened.last.queryParameters['destination'], '21.55,39.16');
    });

    testWidgets('seller of a pay-on-receipt order sees the address only after accepting', (tester) async {
      final s = _Srv()..asSeller = true..status = 'requested'..payment = 'cod';
      await _pump(tester, const OrderPage(_oid), srv: s);
      expect(find.byKey(const Key('order-address')), findsNothing);
      expect(find.textContaining('يظهر لك عنوان المشتري بعد قبول الطلب'), findsOneWidget);
    });

    testWidgets('accepted seller sees the address with a privacy note', (tester) async {
      final s = _Srv()..asSeller = true..status = 'paid'..payment = 'cod';
      await _pump(tester, const OrderPage(_oid), srv: s);
      expect(find.byKey(const Key('order-address')), findsOneWidget);
      expect(find.textContaining('للتوصيل فقط'), findsOneWidget);
    });

    testWidgets('purged after 30 days', (tester) async {
      final s = _Srv()..status = 'completed'..purged = true;
      await _pump(tester, const OrderPage(_oid), srv: s);
      expect(find.textContaining('حُذف العنوان من الطلب بعد ٣٠ يوماً'), findsOneWidget);
    });

    testWidgets('pickup order has no delivery card', (tester) async {
      final s = _Srv()..orderDelivery = false;
      await _pump(tester, const OrderPage(_oid), srv: s);
      expect(find.byKey(const Key('order-delivery')), findsNothing);
    });
  });
}
