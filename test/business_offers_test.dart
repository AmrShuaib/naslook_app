import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/offers_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/dashboard_offers.dart';
import 'package:naslook/pages/wallet/my_offers_page.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _in2d = DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String();
final _in90m = DateTime.now().add(const Duration(minutes: 90)).toUtc().toIso8601String();
final _ago1d = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();

Map<String, dynamic> _offer(String id, {String kind = 'coupon', String title = 'خصم 20٪ على أول طلب', Map<String, dynamic>? value, bool membersOnly = true, bool eligible = true, String? lockedReason, String state = 'active', String? endsAt, String? startsAt, bool canSend = false, bool transferable = true, Map<String, dynamic>? conditions, Map<String, dynamic>? biz, Map<String, dynamic>? loyalty, Map<String, dynamic>? stats, bool active = true}) => {
      'id': id, 'bizId': 'biz-brew92', 'kind': kind, 'title': title, 'description': '', 'value': value ?? {'type': 'percent', 'amount': 20}, 'itemId': null, 'itemTitle': null, 'itemPrice': null,
      'conditions': conditions ?? {}, 'membersOnly': membersOnly, 'transferable': transferable, 'startsAt': startsAt ?? _ago1d, 'endsAt': endsAt ?? _in2d, 'active': active, 'state': state, 'template': null,
      'eligible': eligible, 'lockedReason': lockedReason, 'note': null, 'usedByMe': false, 'via': eligible ? 'member' : null, 'grant': null, 'loyalty': loyalty, 'left': null, 'canSend': canSend, 'biz': biz, 'stats': stats,
    };

Map<String, dynamic> _biz({bool following = false, int offers = 2, List<Map<String, dynamic>>? items, String? myRole}) => {
      'id': 'biz-brew92', 'name': 'Brew92', 'nameAr': 'برو 92', 'category': 'cafe', 'sector': 'قهوة مختصة', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2,
      'address': 'شارع الأمير سلطان، جدة', 'hours': '24 ساعة', 'phone': null, 'website': null, 'color': '#3A2E2A', 'highlights': [], 'verified': true, 'official': false,
      'followers': 128, 'rating': 4.7, 'ratingCount': 40, 'minPrice': 1500, 'itemsCount': 1, 'following': following, 'offers': offers, 'offerEndsAt': _in2d, 'myRole': myRole, 'ownerId': myRole == null ? null : 'SA0000001',
      'items': items ??
          [
            {'id': 'brew92-v60', 'bizId': 'biz-brew92', 'kind': 'product', 'title': 'V60', 'description': 'إثيوبيا', 'price': 2000, 'unit': 'item', 'stock': 10, 'meta': {}, 'deal': {'id': 'off-3', 'title': 'V60 بسعر خاص', 'price': 1500, 'membersOnly': true, 'endsAt': _in2d}},
          ],
      'reviews': [], 'myOrders': [], 'posts': [],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool following;
  bool member;
  bool offerFails = false;
  String notify = 'near';
  _Srv({this.following = false}) : member = following;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.body.isNotEmpty && req.method != 'GET') bodies['${req.method} $path'] = jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'GET' && path == '/biz/biz-brew92') return _json(_biz(following: member));
    if (req.method == 'GET' && path == '/biz') return _json([_biz(following: member)]);
    if (req.method == 'POST' && path == '/biz/biz-brew92/follow') { member = true; return _json({'ok': true}); }
    if (req.method == 'GET' && path == '/biz/biz-brew92/offers') {
      return _json({
        'bizId': 'biz-brew92', 'member': member, 'notify': notify,
        'active': [
          _offer('off-1', eligible: member, lockedReason: member ? null : 'members', canSend: member),
          _offer('off-2', kind: 'checkin', title: 'خصم 15٪ لمن هنا الآن', value: {'type': 'percent', 'amount': 15}, endsAt: _in90m, eligible: member, lockedReason: member ? null : 'members'),
          _offer('off-4', kind: 'loyalty', title: 'مكافأة الرواد', value: {'type': 'free_item'}, endsAt: null, eligible: false, lockedReason: 'loyalty', transferable: false, conditions: {'every': 10}, loyalty: {'every': 10, 'count': 3, 'total': 3}),
        ],
        'upcoming': [_offer('off-6', kind: 'deal', title: 'ساعة هادئة', membersOnly: false, state: 'upcoming', eligible: false, lockedReason: 'upcoming', startsAt: DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String())],
        'past': [_offer('off-5', title: 'كوبون رمضان', state: 'ended', eligible: false, lockedReason: 'ended', endsAt: _ago1d)],
      });
    }
    if (req.method == 'PUT' && path == '/biz/biz-brew92/notify') { notify = (jsonDecode(req.body) as Map)['notify'] as String; return _json({'notify': notify}); }
    if (req.method == 'POST' && path == '/biz/biz-brew92/offers/off-1/send') {
      final to = (jsonDecode(req.body) as Map)['toUserId'];
      if (to == 'SA0000001') return _json({'error': 'self'}, 400);
      return _json({'ok': true});
    }
    if (req.method == 'GET' && path == '/users/sara') return _json({'id': 'SA0000002', 'nickname': 'sara'});
    if (req.method == 'GET' && path == '/offers/mine') {
      return _json({
        'active': [_offer('off-1', biz: {'id': 'biz-brew92', 'name': 'برو 92', 'logoUrl': null, 'category': 'cafe'})],
        'expired': [_offer('off-5', title: 'كوبون رمضان', state: 'ended', eligible: false, lockedReason: 'ended', endsAt: _ago1d, biz: {'id': 'biz-brew92', 'name': 'برو 92', 'logoUrl': null, 'category': 'cafe'})],
        'used': [
          {'id': 'u-1', 'offerId': 'off-3', 'title': 'V60 بسعر خاص', 'kind': 'deal', 'amount': 500, 'usedAt': _ago1d, 'orderId': 'ord-1', 'orderCode': 'NAS-AB12', 'orderTotal': 1500, 'itemTitle': 'V60', 'biz': {'id': 'biz-brew92', 'name': 'برو 92', 'logoUrl': null, 'category': 'cafe'}},
        ],
        'savings': {'month': 500, 'total': 1700, 'uses': 3},
        'counts': {'active': 1, 'used': 3, 'expired': 1},
      });
    }
    if (req.method == 'POST' && path == '/biz/biz-brew92/orders') {
      if (offerFails) return _json({'error': 'offer-unavailable', 'reason': 'near'}, 409);
      final b = jsonDecode(req.body) as Map;
      return _json({'id': 'ord-1', 'bizId': 'biz-brew92', 'bizNameAr': 'برو 92', 'category': 'cafe', 'itemId': b['itemId'], 'title': 'V60', 'kind': 'product', 'qty': b['qty'], 'units': 1, 'total': 1500, 'status': 'confirmed', 'code': 'NAS-AB12', 'meta': {}, 'cancellable': true, 'offer': {'id': 'off-3', 'kind': 'deal', 'title': 'V60 بسعر خاص', 'discount': 500, 'before': 2000}});
    }
    if (req.method == 'GET' && path == '/biz/orders/mine') return _json([]);
    if (req.method == 'GET' && path == '/wallet') return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'recent': [], 'testTopup': false});
    if (req.method == 'GET' && path == '/biz/biz-brew92/manage/offers') {
      return _json({
        'offers': [
          _offer('off-1', stats: {'views': 40, 'uses': 3, 'discount': 1200, 'revenue': 4800, 'sent': 1, 'rewards': 0}),
          _offer('off-5', title: 'كوبون رمضان', state: 'ended', endsAt: _ago1d, stats: {'views': 10, 'uses': 1, 'discount': 1000, 'revenue': 3000, 'sent': 0, 'rewards': 0}),
        ],
        'templates': [
          {'id': 'happy_hour', 'name': 'ساعة هادئة', 'kind': 'deal', 'value': {'type': 'percent', 'amount': 15}, 'hours': 3, 'membersOnly': false, 'hint': 'خصم على كل القائمة لفترة هادئة'},
          {'id': 'loyalty', 'name': 'مكافأة الرواد', 'kind': 'loyalty', 'value': {'type': 'free_item'}, 'conditions': {'every': 10}, 'needsItem': true, 'transferable': false, 'hint': 'كل 10 طلبات، منتج مجاني'},
        ],
        'members': 128,
      });
    }
    if (req.method == 'POST' && path == '/biz/biz-brew92/manage/offers') return _json(_offer('off-new', title: (jsonDecode(req.body) as Map)['title'] as String));
    if (req.method == 'PATCH' && path == '/biz/biz-brew92/manage/offers/off-1') return _json(_offer('off-1', state: 'ended'));
    if (req.method == 'GET' && path == '/biz/biz-brew92/stats') return _json({'orders': {}, 'revenue': {}, 'byKind': [], 'daily': [], 'topItems': []});
    if (req.method == 'GET' && path == '/biz/biz-brew92/community') return _json({'posts': [], 'total': 0, 'members': 0, 'canModerate': false, 'hasMore': false, 'topItems': []});
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/wishlist')) return _json({'items': []});
    if (path == '/contacts') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('BizOffer labels: value, condition, locked reason and ending soon', () {
    final o = BizOffer.fromJson(_offer('x', value: {'type': 'amount', 'amount': 1000}, conditions: {'firstOrder': true, 'minTotal': 3000}, endsAt: _in90m));
    expect(o.valueLabel, 'خصم 10 ر.س');
    expect(o.conditionLabel, 'لأول طلب · لطلب من 30 ر.س · للأعضاء');
    expect(o.endingSoon, isTrue);
    expect(BizOffer.fromJson(_offer('y', eligible: false, lockedReason: 'members')).lockedLabel, contains('انضم'));
    final deal = BizItem.fromJson(_biz()['items'][0] as Map);
    expect(deal.payPrice, 1500);
    expect(deal.oldPrice, 2000);
    expect(deal.isOffer, isTrue);
    final order = BizOrder.fromJson({'id': 'o', 'kind': 'product', 'qty': 1, 'units': 1, 'total': 1500, 'status': 'confirmed', 'code': 'X', 'category': 'cafe', 'offer': {'id': 'off-3', 'kind': 'deal', 'title': 't', 'discount': 500, 'before': 2000}});
    expect(order.offer?.discount, 500);
    expect(offerUnavailableText('near'), contains('الموقع'));
  });

  testWidgets('circle page: join button, offers entry card, deal price with members chip', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: 'biz-brew92'));
    expect(find.byKey(const Key('join-btn')), findsOneWidget);
    expect(find.text('128 عضو'), findsOneWidget);
    expect(find.byKey(const Key('offers-entry')), findsOneWidget);
    expect(find.text('3 عروض سارية'), findsOneWidget);
    // السعر الخاص مع السعر الأصلي مشطوباً وشارة الأعضاء
    expect(find.text('15 ر.س'), findsWidgets);
    expect(find.text('20 ر.س'), findsWidgets);
    expect(find.text('للأعضاء'), findsWidgets);
    // الانضمام: طلب واحد ثم سطر الإخبار بمستوى التنبيه الافتراضي مع زر تغيير
    await tester.tap(find.byKey(const Key('join-btn')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-brew92/follow'));
    expect(find.textContaining('انضممت إلى برو 92'), findsOneWidget);
    expect(find.text('تغيير'), findsOneWidget);
    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notify-all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notify-none')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PUT /biz/biz-brew92/notify']!['notify'], 'none');
    expect(find.byKey(const Key('member-btn')), findsOneWidget);
  });

  testWidgets('circle offers page: sections, join from a members-only card, notify level, send to a friend', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const CircleOffersPage(bizId: 'biz-brew92', title: 'برو 92'));
    expect(find.text('عروض برو 92'), findsOneWidget);
    expect(find.text('السارية'), findsOneWidget);
    expect(find.text('القادمة'), findsOneWidget);
    expect(find.text('المنتهية'), findsOneWidget);
    expect(find.byKey(const Key('join-circle')), findsOneWidget);
    expect(find.text('للأعضاء · انضم لتستخدمه'), findsWidgets);
    expect(find.textContaining('ينتهي بعد'), findsOneWidget); // عرض «لمن هنا الآن» ينتهي خلال 90 دقيقة
    expect(find.text('3 من 10 · بقي 7 طلبات'), findsOneWidget);
    // المنتهية مطوية حتى يُضغط «عرض 1»
    expect(find.text('كوبون رمضان'), findsNothing);
    await tester.tap(find.text('عرض 1'));
    await tester.pumpAndSettle();
    expect(find.text('كوبون رمضان'), findsOneWidget);
    // الانضمام من بطاقة عرض للأعضاء
    await tester.tap(find.byKey(const Key('offer-join-off-1')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-brew92/follow'));
    expect(find.text('أنت عضو · العروض تظهر في محفظتك'), findsOneWidget);
    expect(find.textContaining('يُطبّق تلقائياً'), findsWidgets);
    // مستوى التنبيه
    await tester.tap(find.byKey(const Key('notify-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notify-all')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PUT /biz/biz-brew92/notify']!['notify'], 'all');
    expect(find.text('كل العروض'), findsOneWidget);
    // إرسال لصديق بالنك نيم: يُحلّ إلى المعرّف ثم يُرسل
    await tester.tap(find.byKey(const Key('offer-send-off-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('send-offer-to')), 'sara');
    await tester.tap(find.byKey(const Key('send-offer-go')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /biz/biz-brew92/offers/off-1/send']!['toUserId'], 'SA0000002');
    expect(find.textContaining('أُرسل'), findsOneWidget);
  });

  testWidgets('buying with a deal: member sees the deal total, sends location, order sheet shows savings', (tester) async {
    final srv = _Srv(following: true);
    DeviceLocation.override = () async => const LatLng(21.5001, 39.2001);
    addTearDown(() => DeviceLocation.override = null);
    await _pump(tester, srv, const BusinessPage(id: 'biz-brew92'));
    await tester.tap(find.text('اطلب').first);
    await tester.pumpAndSettle();
    expect(find.text('ادفع 15 ر.س من المحفظة'), findsOneWidget);
    expect(find.textContaining('بعرض «V60 بسعر خاص»'), findsOneWidget);
    await tester.tap(find.text('ادفع 15 ر.س من المحفظة'));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/biz-brew92/orders']!;
    expect(body['lat'], closeTo(21.5001, 1e-6));
    expect(body['lng'], closeTo(39.2001, 1e-6));
    expect(body.containsKey('offerId'), isFalse); // تلقائي: الخادم يختار أفضل عرض
    expect(find.byKey(const Key('order-savings')), findsOneWidget);
    expect(find.text('وفّرت 5 ر.س بعرض «V60 بسعر خاص»'), findsOneWidget);
  });

  testWidgets('non-member sees the members-only hint in the buy sheet and offer-unavailable errors are explained', (tester) async {
    final srv = _Srv()..offerFails = true;
    DeviceLocation.override = () async => null;
    addTearDown(() => DeviceLocation.override = null);
    await _pump(tester, srv, const BusinessPage(id: 'biz-brew92'));
    await tester.tap(find.text('اطلب').first);
    await tester.pumpAndSettle();
    expect(find.text('ادفع 20 ر.س من المحفظة'), findsOneWidget);
    expect(find.textContaining('السعر الخاص للأعضاء'), findsOneWidget);
    await tester.tap(find.text('ادفع 20 ر.س من المحفظة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('فعّل الموقع'), findsOneWidget);
  });

  testWidgets('wallet: «عروضي» action opens my offers with savings, tabs and used rows', (tester) async {
    final srv = _Srv(following: true);
    await _pump(tester, srv, const WalletPage());
    await tester.tap(find.text('عروضي'));
    await tester.pumpAndSettle();
    expect(find.byType(MyOffersPage), findsOneWidget);
    expect(find.byKey(const Key('savings-month')), findsOneWidget);
    expect(find.text('5 ر.س'), findsOneWidget);
    expect(find.textContaining('الإجمالي 17 ر.س'), findsOneWidget);
    expect(find.text('برو 92'), findsWidgets); // اسم الدائرة على البطاقة
    expect(find.text('خصم 20٪ على أول طلب'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offers-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('وفّرت 5 ر.س'), findsOneWidget);
    expect(find.textContaining('NAS-AB12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offers-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('كوبون رمضان'), findsOneWidget);
  });

  testWidgets('circle list row shows the offers badge', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: BizListView(padding: EdgeInsets.all(16))));
    expect(find.text('2 عروض'), findsOneWidget);
  });

  testWidgets('owner offers tab: stats, template picker fills the editor, publish posts the offer, end now patches', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-brew92', initialTab: 3));
    // نحتاج صلاحية الإدارة: الدائرة تعود بلا myRole في هذا الخادم، فنفحص التبويب مباشرة
    final biz = Biz.fromJson(_biz(myRole: 'owner'));
    await _pump(tester, srv, Scaffold(body: OffersTab(biz: biz)));
    expect(find.text('128'), findsOneWidget);
    expect(find.text('3 استخدام'), findsOneWidget);
    expect(find.text('خصم 12 ر.س'), findsOneWidget);
    expect(find.text('المنتهية والمتوقفة'), findsOneWidget);
    // القالب يملأ النوع والقيمة والمدة
    await tester.tap(find.byKey(const Key('offer-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tpl-happy_hour')));
    await tester.pumpAndSettle();
    expect(find.text('قالب: ساعة هادئة'), findsOneWidget);
    expect(find.text('ساعة هادئة · خصم 15٪'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/biz-brew92/manage/offers']!;
    expect(body['kind'], 'deal');
    expect(body['value'], {'type': 'percent', 'amount': 15});
    expect(body['membersOnly'], isFalse);
    expect(body['template'], 'happy_hour');
    expect(body['endsAt'], isNotNull);
    expect(find.textContaining('نُشر العرض'), findsOneWidget);
    // أنهِ الآن
    await tester.tap(find.byKey(const Key('offer-menu-off-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أنهِ الآن').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أنهِ الآن').last);
    await tester.pumpAndSettle();
    expect(srv.bodies['PATCH /biz/biz-brew92/manage/offers/off-1'], {'endNow': true});
  });

  test('notification targets for offers open the circle offers or my offers', () {
    expect(notificationTarget(const AppNotification(id: '1', kind: 'biz_offer', title: 't', data: {'bizId': 'biz-brew92', 'offerId': 'x'})), isA<CircleOffersPage>());
    expect(notificationTarget(const AppNotification(id: '2', kind: 'offer_received', title: 't')), isA<MyOffersPage>());
    expect(notificationTarget(const AppNotification(id: '3', kind: 'offer_loyalty', title: 't')), isA<MyOffersPage>());
    expect(notificationTarget(const AppNotification(id: '4', kind: 'biz_update', title: 't', data: {'bizId': 'biz-brew92'})), isA<BusinessPage>());
  });
}
