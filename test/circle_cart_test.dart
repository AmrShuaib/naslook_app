// سلة الدوائر (نوفمبر 2026): محرّر خيارات الصنف عند المالك، اختيار الخيارات والإضافة إلى السلة في صفحة الدائرة، ورقة السلة
// وإتمام الطلب (الملاحظة ووقت الاستلام والدفع من المحفظة أو في المكان)، ومبلغ الإتمام من معاينة الخادم (العرض على الطلب كله وexpectTotal)،
// وحفظ السلة على الجهاز لكل حساب، وأسطر الطلب في ورقته وبطاقات المالك.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/business/biz_order_page.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/dashboard_catalog.dart';
import 'package:naslook/pages/business/owner/dashboard_orders.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/circle_cart.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart' show JoyCard;

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// حساب يتبدّل على الجهاز نفسه (خروج ثم دخول بحساب آخر).
class _Switchable extends AppStateNotifier {
  _Switchable(super.api, super.store) {
    as('SA0000001');
  }
  void as(String? id) => state = id == null ? const AppState(status: AuthStatus.signedOut) : AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: id, nickname: 'u')));
}

/// مفتاح سلة الحساب الداخل في الاختبارات (SA0000001) لدائرة المقهى.
const _key = 'naslife.cart.SA0000001.biz-cafe';

const _opts = [
  {'id': 'size', 'name': 'الحجم', 'required': true, 'multi': false, 'choices': [{'id': 'sm', 'name': 'صغير', 'delta': 0}, {'id': 'md', 'name': 'وسط', 'delta': 300}, {'id': 'lg', 'name': 'كبير', 'delta': 500}]},
  {'id': 'milk', 'name': 'الحليب', 'required': false, 'multi': false, 'choices': [{'id': 'reg', 'name': 'عادي', 'delta': 0}, {'id': 'oat', 'name': 'شوفان', 'delta': 200}]},
  {'id': 'xtra', 'name': 'إضافات', 'required': false, 'multi': true, 'choices': [{'id': 'shot', 'name': 'شوت إضافي', 'delta': 300}, {'id': 'syr', 'name': 'سيروب', 'delta': 200}]},
];

Map<String, dynamic> _item(String id, {int price = 1900, bool venue = false, bool options = false, int? stock = 10, int? dealPrice}) => {
      'id': id, 'bizId': 'biz-cafe', 'kind': 'product', 'title': {'latte': 'لاتيه', 'croissant': 'كرواسون', 'beans': 'حبوب إثيوبيا', 'water': 'ماء'}[id] ?? id, 'description': '', 'price': price, 'unit': 'item',
      'stock': stock, 'meta': options ? {'options': _opts} : {}, 'active': true, 'payAtVenue': venue,
      if (dealPrice != null) 'deal': {'id': 'deal-$id', 'title': 'عرض $id', 'price': dealPrice, 'membersOnly': false},
    };

final _now = DateTime.now();
// وقتا استلام اليوم بعد ساعة وساعتين (بالدقيقة صفر) كما يعيدهما الخادم بتوقيت UTC
final _t1 = DateTime(_now.year, _now.month, _now.day, _now.hour).add(const Duration(hours: 1));
final _t2 = _t1.add(const Duration(minutes: 30));
String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Map<String, dynamic> _biz(List<Map<String, dynamic>> items, {String role = 'none', bool times = true}) => {
      'id': 'biz-cafe', 'name': 'Cup', 'nameAr': 'مقهى الفنجان', 'category': 'cafe', 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': times ? 'يومياً 6:00 ص – 11:59 م' : '',
      'color': '#5B2E1E', 'highlights': [], 'verified': true, 'official': false, 'active': true, 'ownerId': 'SA0000009', 'myRole': role, 'followers': 0, 'itemsCount': items.length,
      'items': items, 'reviews': [], 'posts': [], 'myOrders': [], 'verificationStatus': 'approved', 'canSell': true,
      'pickupTimes': times ? [_t1.toUtc().toIso8601String(), _t2.toUtc().toIso8601String()] : null,
    };

Map<String, dynamic> _cartOrder({String id = 'c1', String payment = 'wallet', String? pickupAt, String note = '', String status = 'confirmed'}) => {
      'id': id, 'bizId': 'biz-cafe', 'bizNameAr': 'مقهى الفنجان', 'category': 'cafe', 'itemId': 'latte', 'title': 'لاتيه وصنف آخر', 'kind': 'product', 'qty': 3, 'units': 1, 'total': 6400,
      'status': status, 'code': 'NAS-${id.toUpperCase()}', 'note': note, 'meta': {'cartTitle': 'لاتيه وصنف آخر'}, 'createdAt': _now.toUtc().toIso8601String(), 'cancellable': status == 'confirmed',
      'payment': payment, 'paid': payment != 'at_venue', 'funds': payment == 'wallet' ? 'held' : null, 'cart': true, 'pickupAt': pickupAt,
      'lines': [
        {'itemId': 'latte', 'title': 'لاتيه', 'qty': 2, 'unit': 2600, 'total': 5200, 'options': [
          {'groupId': 'size', 'group': 'الحجم', 'choiceId': 'lg', 'choice': 'كبير', 'delta': 500},
          {'groupId': 'milk', 'group': 'الحليب', 'choiceId': 'oat', 'choice': 'شوفان', 'delta': 200},
        ]},
        {'itemId': 'croissant', 'title': 'كرواسون', 'qty': 1, 'unit': 1200, 'total': 1200, 'options': []},
      ],
      'customer': {'id': 'SA0000002', 'nickname': 'sara'},
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic> biz;
  bool broke = false;
  /// معاينة يعيدها الخادم كما هي (كوبون مثلاً)؛ بدونها تُحسب من الكتالوج بقاعدة الخادم للسعر الخاص. quoteBroken: تفشل المعاينة.
  Map<String, dynamic>? quote;
  bool quoteBroken = false;
  /// رد خطأ للطلب نفسه (409) بدل نجاحه.
  Map<String, dynamic>? orderError;
  _Srv(this.biz);
  /// كالخادم: سعر الوحدة = السعر + فروق الخيارات، والسعر الخاص يخصم (السعر − سعر العرض) لكل قطعة فتبقى الفروق كاملة،
  /// والدفع في المكان حين يقبله كل سطر مدفوع.
  Map<String, dynamic> _quoteOf(Map<String, dynamic> body) {
    final items = {for (final i in biz['items'] as List) (i as Map)['id']: i};
    final lines = <Map<String, dynamic>>[];
    var venue = true, discount = 0;
    for (final l in body['lines'] as List) {
      final it = items[l['itemId']] as Map;
      final sel = (l['options'] as Map?) ?? const {};
      var unit = it['price'] as int;
      for (final g in ((it['meta'] as Map)['options'] as List?) ?? const []) {
        for (final c in g['choices'] as List) {
          if ((sel[g['id']] as List?)?.contains(c['id']) == true) unit += c['delta'] as int;
        }
      }
      final qty = l['qty'] as int;
      final deal = it['deal'] as Map?;
      final cut = deal == null ? 0 : ((it['price'] as int) - (deal['price'] as int)) * qty;
      discount += cut;
      lines.add({'itemId': it['id'], 'title': it['title'], 'qty': qty, 'unit': unit, 'total': unit * qty, 'options': [], if (cut > 0) 'offer': {'id': deal!['id'], 'kind': 'deal', 'title': deal['title'], 'discount': cut}});
      if (unit * qty > 0 && it['payAtVenue'] != true) venue = false;
    }
    final sub = lines.fold<int>(0, (n, l) => n + (l['total'] as int));
    return {'subtotal': sub, 'discount': discount, 'total': sub - discount, 'offer': discount > 0 ? {'id': 'deal', 'kind': 'deal', 'title': 'عرض', 'discount': discount, 'before': sub} : null, 'lines': lines, 'venueOk': venue};
  }
  Map<String, dynamic>? last(String key) => bodies[key]?.last;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.startsWith('{')) (bodies[key] ??= []).add(jsonDecode(req.body) as Map<String, dynamic>);
    if (key == 'GET /biz/biz-cafe') return _json(biz);
    if (key == 'POST /biz/biz-cafe/orders/quote') {
      if (quoteBroken) return _json({'error': 'boom'}, 500);
      return _json(quote ?? _quoteOf(last(key)!));
    }
    if (key == 'POST /biz/biz-cafe/orders') {
      final b = last(key)!;
      if (orderError != null) return _json(orderError!, 409);
      final venue = b['payment'] == 'at_venue';
      if (broke && !venue) return _json({'error': 'insufficient-funds'}, 402);
      return _json(_cartOrder(payment: venue ? 'at_venue' : 'wallet', pickupAt: b['pickupAt'] as String?, note: (b['note'] ?? '') as String));
    }
    if (key.startsWith('PATCH /biz/biz-cafe/items/')) return _json({..._item(key.split('/').last), ...last(key)!});
    if (key == 'GET /biz/biz-cafe/orders') return _json([_cartOrder()]);
    if (key == 'GET /biz/biz-cafe/stats') return _json({'orders': {'total': 1}, 'revenue': {'total': 6400}, 'byKind': [], 'daily': [], 'topItems': []});
    if (key == 'POST /biz/biz-cafe/checkin') return _json(_cartOrder(status: 'used'));
    if (key == 'GET /biz/orders/c1') return _json({..._cartOrder(pickupAt: _t1.toUtc().toIso8601String(), note: 'بدون سكر'), 'viewer': 'customer'});
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

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? '';

/// زر «اطلب» في بطاقة الصنف بعنوانه.
Finder _orderBtn(String title) => find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(JoyCard)).first, matching: find.widgetWithText(FilledButton, 'اطلب'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => iosNativeOverride = null);

  test('options, selection rules, cart keys and order lines', () {
    final latte = BizItem.fromJson(_item('latte', options: true));
    expect(latte.options.map((g) => g.name), ['الحجم', 'الحليب', 'إضافات']);
    expect(latte.options.first.ruleLabel, 'إلزامي · اختر واحداً');
    expect(latte.options.last.ruleLabel, 'اختياري · اختر ما تشاء');
    expect(latte.missingGroup({})?.name, 'الحجم');
    expect(latte.missingGroup({'size': ['lg']}), isNull);
    expect(latte.optionsDelta({'size': ['lg'], 'xtra': ['shot', 'syr']}), 1000);
    expect(latte.optionsLabel({'size': ['lg'], 'xtra': ['syr', 'shot']}), 'الحجم: كبير · إضافات: شوت إضافي، سيروب');
    expect(latte.selectionValid({'size': ['sm', 'lg']}), isFalse);
    expect(latte.selectionValid({'size': ['gone']}), isFalse);
    expect(latte.selectionValid({'size': ['sm'], 'xtra': ['shot', 'syr']}), isTrue);
    // الخيارات للمنتج وحده
    expect(BizItem.fromJson({..._item('x', options: true), 'kind': 'clinic'}).options, isEmpty);
    // الصنف بالخيارات نفسها سطر واحد مهما كان ترتيبها
    expect(const CartLine(itemId: 'latte', options: {'xtra': ['syr', 'shot'], 'size': ['lg']}).key, const CartLine(itemId: 'latte', options: {'size': ['lg'], 'xtra': ['shot', 'syr'], 'milk': []}).key);
    expect(const CartLine(itemId: 'latte', options: {'size': ['lg']}).key == const CartLine(itemId: 'latte', options: {'size': ['sm']}).key, isFalse);
    final o = BizOrder.fromJson(_cartOrder(pickupAt: _t1.toUtc().toIso8601String()));
    expect(o.isCart, isTrue);
    expect(o.summary, '2 × لاتيه، 1 × كرواسون');
    expect(o.lines.first.optionsLabel, 'الحجم: كبير · الحليب: شوفان');
    expect(o.pickupLabel, 'اليوم ${_clock(_t1)}');
    expect(BizOrder.fromJson(_cartOrder()).pickupLabel, 'في أقرب وقت');
    // طلب الأمس وما قبله لا يقول «اليوم»
    final old = BizOrder.fromJson(_cartOrder(pickupAt: DateTime(2026, 11, 5, 19, 30).toUtc().toIso8601String()));
    expect(old.pickupLabelAt(DateTime(2026, 11, 5, 23, 50)), 'اليوم 19:30');
    expect(old.pickupLabelAt(DateTime(2026, 11, 6, 8)), 'أمس 19:30');
    expect(old.pickupLabelAt(DateTime(2026, 11, 8, 8)), '5/11 19:30');
    // السطر الذي تغيّرت خياراته أو نفد مخزونه لا يُطلب
    final biz = Biz.fromJson(_biz([_item('latte', options: true), _item('croissant', price: 1200, stock: 1)]));
    final r = resolveCart(biz, const [CartLine(itemId: 'latte', options: {'size': ['xl']}), CartLine(itemId: 'croissant', qty: 2), CartLine(itemId: 'gone')]);
    expect(r.map((x) => x.problem), ['تغيّرت خيارات هذا الصنف، احذفه وأضفه من جديد', 'المتبقي 1 فقط', 'لم يعد متاحاً']);
    expect(resolveCart(biz, const [CartLine(itemId: 'latte', qty: 2, options: {'size': ['lg'], 'milk': ['oat']})]).single.total, 5200);
    // السعر الخاص للوحدة ثم فروق الخيارات كاملة (قاعدة الخادم): لاتيه بـ15 كبير = 15 + 5
    final dealt = Biz.fromJson(_biz([_item('latte', options: true, dealPrice: 1500)]));
    expect(resolveCart(dealt, const [CartLine(itemId: 'latte', qty: 2, options: {'size': ['lg']})]).single.total, 2 * (1500 + 500));
    // السطر المجاني لا يمنع الدفع في المكان، والسطر المدفوع بلا المفتاح يمنعه
    final venueBiz = Biz.fromJson(_biz([_item('beans', price: 6500, venue: true), _item('water', price: 0), _item('croissant', price: 1200)]));
    expect(resolveCart(venueBiz, const [CartLine(itemId: 'beans'), CartLine(itemId: 'water')]).every((r) => r.venueOk), isTrue);
    expect(resolveCart(venueBiz, const [CartLine(itemId: 'beans'), CartLine(itemId: 'croissant')]).every((r) => r.venueOk), isFalse);
  });

  test('saved carts belong to the signed-in account: another account on the device does not see them, and they come back on sign-in', () async {
    SharedPreferences.setMockInitialValues({
      'naslife.cart.SA0000002.biz-cafe': jsonEncode([{'itemId': 'beans', 'qty': 3, 'options': {}}]),
      // مفتاح ما قبل الإصلاح بلا حساب: لا يُعرف صاحبه فلا يظهر لأحد ويُحذف
      'naslife.cart.biz-cafe': jsonEncode([{'itemId': 'croissant', 'qty': 1, 'options': {}}]),
    });
    Future<void> flush() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((_) async => http.Response('{}', 404)));
    late _Switchable auth;
    final c = ProviderContainer(overrides: [appStateProvider.overrideWith((ref) => auth = _Switchable(api, SessionStore()))]);
    addTearDown(c.dispose);
    c.listen(circleCartProvider('biz-cafe'), (_, __) {});
    List<String> cart() => [for (final l in c.read(circleCartProvider('biz-cafe'))) '${l.itemId}×${l.qty}'];
    await flush();
    expect(cart(), isEmpty);
    expect((await SharedPreferences.getInstance()).containsKey('naslife.cart.biz-cafe'), isFalse);
    c.read(circleCartProvider('biz-cafe').notifier).add(const CartLine(itemId: 'latte', qty: 2, options: {'size': ['lg']}));
    await flush();
    auth.as(null);
    await flush();
    expect(cart(), isEmpty);
    auth.as('SA0000002');
    await flush();
    expect(cart(), ['beans×3']);
    auth.as('SA0000001');
    await flush();
    expect(cart(), ['latte×2']);
    // حذف الحساب يمسح سلاله من الجهاز وحدها
    await forgetSavedCarts('SA0000001');
    expect((await SharedPreferences.getInstance()).getKeys(), {'naslife.cart.SA0000002.biz-cafe'});
  });

  testWidgets('options editor: the owner adds a required size group with a price delta', (tester) async {
    final srv = _Srv(_biz([_item('croissant', price: 1200)], role: 'owner'));
    await _pump(tester, srv, CatalogTab(biz: Biz.fromJson(srv.biz)));
    await _tap(tester, find.text('كرواسون'));
    await _tap(tester, find.byKey(const Key('opt-add-group')));
    // مجموعة بلا اسم وفيها خيار: لا يُحفظ شيء
    await tester.enterText(find.byKey(const Key('opt-choice-name-0-0')), 'صغير');
    await _tap(tester, find.widgetWithText(FilledButton, 'حفظ'));
    expect(find.text('اكتب اسم كل مجموعة خيارات'), findsOneWidget);
    expect(srv.calls.where((c) => c.startsWith('PATCH')), isEmpty);
    await tester.enterText(find.byKey(const Key('opt-group-name-0')), 'الحجم');
    await tester.enterText(find.byKey(const Key('opt-choice-name-0-1')), 'كبير');
    await tester.enterText(find.byKey(const Key('opt-choice-delta-0-1')), '5');
    await _tap(tester, find.byKey(const Key('opt-required-0')));
    await _tap(tester, find.byKey(const Key('opt-add-choice-0')));
    await tester.enterText(find.byKey(const Key('opt-choice-name-0-2')), 'عائلي');
    await tester.enterText(find.byKey(const Key('opt-choice-delta-0-2')), '٧٫٥');
    await _tap(tester, find.widgetWithText(FilledButton, 'حفظ'));
    final meta = srv.last('PATCH /biz/biz-cafe/items/croissant')!['meta'] as Map;
    expect(meta['options'], [
      {'name': 'الحجم', 'required': true, 'multi': false, 'choices': [{'name': 'صغير', 'delta': 0}, {'name': 'كبير', 'delta': 500}, {'name': 'عائلي', 'delta': 750}]},
    ]);
  });

  testWidgets('options editor: editing keeps group and choice ids, switches to multiple choice and removes a group', (tester) async {
    final srv = _Srv(_biz([_item('latte', options: true)], role: 'owner'));
    await _pump(tester, srv, CatalogTab(biz: Biz.fromJson(srv.biz)));
    expect(_text(tester, 'catalog-line-latte'), contains('الحجم، الحليب، إضافات'));
    await _tap(tester, find.text('لاتيه'));
    expect(tester.widget<TextField>(find.byKey(const Key('opt-group-name-1'))).controller!.text, 'الحليب');
    await tester.enterText(find.byKey(const Key('opt-choice-delta-0-1')), '4');
    await _tap(tester, find.byKey(const Key('opt-multi-1')));
    await _tap(tester, find.byKey(const Key('opt-remove-group-2')));
    await _tap(tester, find.widgetWithText(FilledButton, 'حفظ'));
    final opts = (srv.last('PATCH /biz/biz-cafe/items/latte')!['meta'] as Map)['options'] as List;
    expect(opts.length, 2);
    expect(opts[0]['id'], 'size');
    expect(opts[0]['choices'][1], {'id': 'md', 'name': 'وسط', 'delta': 400});
    expect(opts[1]['multi'], isTrue);
  });

  testWidgets('adding to the cart: required size first, then the bar shows pieces and total, and the cart is saved on the device', (tester) async {
    await _pump(tester, _Srv(_biz([_item('latte', options: true), _item('croissant', price: 1200)])), const BusinessPage(id: 'biz-cafe'));
    expect(find.byKey(const Key('cart-bar')), findsNothing);
    await _tap(tester, _orderBtn('لاتيه'));
    expect(find.byKey(const Key('item-options')), findsOneWidget);
    expect(find.byKey(const Key('pay-wallet')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('add-to-cart'))).onPressed, isNull);
    expect(find.text('اختر الحجم'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('opt-size-lg')));
    await _tap(tester, find.byKey(const Key('opt-milk-oat')));
    expect(find.text('أضف إلى السلة · 26 ر.س'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('add-to-cart')));
    expect(_text(tester, 'cart-bar-count'), 'السلة · قطعة واحدة');
    expect(_text(tester, 'cart-bar-total'), '26 ر.س');
    // صنف بلا خيارات: الشراء المباشر باقٍ و«أضف إلى السلة» بجانبه
    await _tap(tester, _orderBtn('كرواسون'));
    expect(find.byKey(const Key('pay-wallet')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('add-to-cart')));
    expect(_text(tester, 'cart-bar-count'), 'السلة · قطعتان');
    expect(_text(tester, 'cart-bar-total'), '38 ر.س');
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString(_key)!) as List;
    expect(saved, [
      {'itemId': 'latte', 'qty': 1, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ]);
  });

  testWidgets('cart sheet: options under each line, quantity changes the total, and a stale line blocks checkout', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([
      {'itemId': 'latte', 'qty': 1, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ])});
    await _pump(tester, _Srv(_biz([_item('latte', options: true), _item('croissant', price: 1200)])), const BusinessPage(id: 'biz-cafe'));
    expect(_text(tester, 'cart-bar-count'), 'السلة · قطعتان');
    await _tap(tester, find.byKey(const Key('cart-bar')));
    expect(find.byKey(const Key('cart-sheet')), findsOneWidget);
    expect(_text(tester, 'cart-line-options-0'), 'الحجم: كبير · الحليب: شوفان');
    await _tap(tester, find.byKey(const Key('cart-plus-0')));
    expect(_text(tester, 'cart-qty-0'), '2');
    expect(_text(tester, 'cart-total'), '64 ر.س');
    // النقص عند قطعة واحدة يحذف السطر
    await _tap(tester, find.byKey(const Key('cart-minus-1')));
    expect(find.byKey(const Key('cart-line-1')), findsNothing);
    expect(_text(tester, 'cart-total'), '52 ر.س');
  });

  testWidgets('cart sheet: a line whose options changed at the circle is flagged and checkout is disabled', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([{'itemId': 'latte', 'qty': 1, 'options': {'size': ['xl']}}])});
    await _pump(tester, _Srv(_biz([_item('latte', options: true)])), const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    expect(_text(tester, 'cart-problem-0'), contains('تغيّرت خيارات'));
    expect(find.byKey(const Key('cart-blocked')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('cart-checkout'))).onPressed, isNull);
    await _tap(tester, find.byKey(const Key('cart-clear')));
    expect(find.byKey(const Key('cart-bar')), findsNothing);
  });

  testWidgets('checkout: pickup time, note and wallet payment send one cart order; the order sheet lists the lines', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([
      {'itemId': 'latte', 'qty': 2, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ])});
    final srv = await _pump(tester, _Srv(_biz([_item('latte', options: true, venue: true), _item('croissant', price: 1200)])), const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    expect(find.byKey(const Key('checkout-sheet')), findsOneWidget);
    expect(find.text('2 × لاتيه'), findsOneWidget);
    expect(_text(tester, 'checkout-total'), '64 ر.س');
    // الكرواسون لا يقبل الدفع في المكان، فالخيار غائب عن السلة كلها
    expect(find.byKey(const Key('checkout-pay-venue')), findsNothing);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('pickup-asap'))).selected, isTrue);
    await _tap(tester, find.byKey(Key('pickup-${_clock(_t2)}')));
    await tester.enterText(find.byKey(const Key('checkout-note')), 'بدون سكر');
    await _tap(tester, find.byKey(const Key('checkout-pay-wallet')));
    final body = srv.last('POST /biz/biz-cafe/orders')!;
    expect(body['lines'], [
      {'itemId': 'latte', 'qty': 2, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ]);
    expect(body.containsKey('payment'), isFalse);
    expect(body.containsKey('itemId'), isFalse);
    // المبلغ الذي عرضته المعاينة يُرسل مع الطلب فلا يُخصم غيره
    expect(body['expectTotal'], 6400);
    expect(srv.calls.where((c) => c == 'POST /biz/biz-cafe/orders/quote'), hasLength(1));
    expect(DateTime.parse(body['pickupAt'] as String).toUtc(), _t2.toUtc());
    expect(body['note'], 'بدون سكر');
    expect(find.text('تم الطلب'), findsOneWidget);
    expect(find.byKey(const Key('order-lines')), findsOneWidget);
    expect(_text(tester, 'order-line-options-0'), 'الحجم: كبير · الحليب: شوفان');
    expect(find.descendant(of: find.byKey(const Key('order-pickup')), matching: find.text('اليوم ${_clock(_t2)}')), findsOneWidget);
    // نجح الطلب: فرغت السلة
    expect(find.byKey(const Key('cart-bar')), findsNothing);
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
  });

  testWidgets('checkout: every line allows it, so «اطلب الآن وادفع في المكان» books without the wallet; no hours means as soon as possible only', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([
      {'itemId': 'latte', 'qty': 1, 'options': {'size': ['sm']}},
      {'itemId': 'beans', 'qty': 1, 'options': {}},
    ])});
    final srv = await _pump(tester, _Srv(_biz([_item('latte', options: true, venue: true), _item('beans', price: 6500, venue: true, stock: null)], times: false)), const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    expect(find.byKey(const Key('pickup-asap-only')), findsOneWidget);
    expect(find.text('ادفع الآن من المحفظة · 84 ر.س'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('checkout-pay-venue')));
    final body = srv.last('POST /biz/biz-cafe/orders')!;
    expect(body['payment'], 'at_venue');
    expect(body.containsKey('pickupAt'), isFalse);
    expect(find.text('تم الطلب · الدفع في المكان'), findsOneWidget);
  });

  testWidgets('checkout: the server quote sets the amount: a coupon on the whole cart shows the saving, and the button and the order carry the quoted total', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([
      {'itemId': 'latte', 'qty': 2, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ])});
    final srv = _Srv(_biz([_item('latte', options: true), _item('croissant', price: 1200)]))
      ..quote = {
        'subtotal': 6400, 'discount': 1280, 'total': 5120, 'venueOk': false,
        'offer': {'id': 'o1', 'kind': 'coupon', 'title': 'أول طلب', 'discount': 1280, 'before': 6400},
        'lines': [
          {'itemId': 'latte', 'title': 'لاتيه', 'qty': 2, 'unit': 2600, 'total': 5200, 'options': [], 'offer': {'id': 'o1', 'kind': 'coupon', 'title': 'أول طلب', 'discount': 1040}},
          {'itemId': 'croissant', 'title': 'كرواسون', 'qty': 1, 'unit': 1200, 'total': 1200, 'options': [], 'offer': {'id': 'o1', 'kind': 'coupon', 'title': 'أول طلب', 'discount': 240}},
        ],
      };
    await _pump(tester, srv, const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    expect(_text(tester, 'cart-total'), '64 ر.س');
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    expect(srv.last('POST /biz/biz-cafe/orders/quote')!['lines'], [
      {'itemId': 'latte', 'qty': 2, 'options': {'size': ['lg'], 'milk': ['oat']}},
      {'itemId': 'croissant', 'qty': 1, 'options': {}},
    ]);
    expect(_text(tester, 'checkout-line-total-0'), '52 ر.س');
    expect(_text(tester, 'checkout-savings'), 'وفّرت 12.80 ر.س بعرض «أول طلب»');
    expect(_text(tester, 'checkout-total'), '51.20 ر.س');
    expect(find.text('ادفع 51.20 ر.س من المحفظة'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('checkout-pay-wallet')));
    expect(srv.last('POST /biz/biz-cafe/orders')!['expectTotal'], 5120);
    expect(find.text('تم الطلب'), findsOneWidget);
  });

  testWidgets('checkout: a price deal with a size surcharge: the cart estimate, the quoted total and the order agree', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([{'itemId': 'latte', 'qty': 2, 'options': {'size': ['lg']}}])});
    final srv = await _pump(tester, _Srv(_biz([_item('latte', options: true, dealPrice: 1500)])), const BusinessPage(id: 'biz-cafe'));
    expect(_text(tester, 'cart-bar-total'), '40 ر.س');
    await _tap(tester, find.byKey(const Key('cart-bar')));
    expect(_text(tester, 'cart-total'), '40 ر.س');
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    expect(_text(tester, 'checkout-line-total-0'), '48 ر.س');
    expect(_text(tester, 'checkout-savings'), contains('وفّرت 8 ر.س'));
    expect(_text(tester, 'checkout-total'), '40 ر.س');
    await _tap(tester, find.byKey(const Key('checkout-pay-wallet')));
    expect(srv.last('POST /biz/biz-cafe/orders')!['expectTotal'], 4000);
  });

  testWidgets('checkout: the amount changed since the quote: nothing is charged, the new amount is shown and the cart stays', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([{'itemId': 'croissant', 'qty': 2, 'options': {}}])});
    final srv = _Srv(_biz([_item('croissant', price: 1200)]))..orderError = {'error': 'total-changed', 'total': 2800};
    await _pump(tester, srv, const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    await _tap(tester, find.byKey(const Key('checkout-pay-wallet')));
    expect(srv.last('POST /biz/biz-cafe/orders')!['expectTotal'], 2400);
    expect(find.text('تغيّر مبلغ الطلب إلى 28 ر.س، راجع سلتك وأعد المحاولة'), findsOneWidget);
    expect(find.text('تم الطلب'), findsNothing);
    expect(find.byKey(const Key('cart-bar')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(_key), isNotNull);
  });

  testWidgets('checkout: without a quote (old server or offline) the estimate is shown and no expected total is sent; a free line does not block pay at venue', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode([{'itemId': 'beans', 'qty': 1, 'options': {}}, {'itemId': 'water', 'qty': 1, 'options': {}}])});
    final srv = _Srv(_biz([_item('beans', price: 6500, venue: true, stock: null), _item('water', price: 0)]))..quoteBroken = true;
    await _pump(tester, srv, const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    expect(_text(tester, 'checkout-total'), '65 ر.س');
    expect(find.byKey(const Key('checkout-savings')), findsNothing);
    await _tap(tester, find.byKey(const Key('checkout-pay-venue')));
    final body = srv.last('POST /biz/biz-cafe/orders')!;
    expect(body['payment'], 'at_venue');
    expect(body.containsKey('expectTotal'), isFalse);
  });

  testWidgets('iOS: insufficient funds on an all-venue cart offers to order and pay at the venue', (tester) async {
    iosNativeOverride = true;
    SharedPreferences.setMockInitialValues({_key: jsonEncode([{'itemId': 'beans', 'qty': 2, 'options': {}}])});
    final srv = _Srv(_biz([_item('beans', price: 6500, venue: true, stock: null)]))..broke = true;
    await _pump(tester, srv, const BusinessPage(id: 'biz-cafe'));
    await _tap(tester, find.byKey(const Key('cart-bar')));
    await _tap(tester, find.byKey(const Key('cart-checkout')));
    await _tap(tester, find.byKey(const Key('checkout-pay-wallet')));
    expect(find.byKey(const Key('cart-funds-ios')), findsOneWidget);
    expect(find.textContaining('اشحن'), findsNothing);
    await _tap(tester, find.byKey(const Key('cart-funds-venue')));
    expect(srv.bodies['POST /biz/biz-cafe/orders']!.length, 2);
    expect(srv.last('POST /biz/biz-cafe/orders')!['payment'], 'at_venue');
  });

  testWidgets('owner: order card summarises the lines, the sheet lists options, and checking in a cart by code shows what to hand over', (tester) async {
    final srv = _Srv(_biz([_item('latte', options: true)], role: 'owner'));
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(srv.biz))));
    expect(_text(tester, 'owner-order-summary-c1'), '2 × لاتيه، 1 × كرواسون');
    // السلة بلا موعد: وقت الاستلام على البطاقة نفسها
    expect(find.textContaining('الاستلام في أقرب وقت · طُلب'), findsOneWidget);
    await _tap(tester, find.textContaining('NAS-C1').first);
    expect(find.byKey(const Key('owner-order-lines')), findsOneWidget);
    expect(find.text('الحجم: كبير · الحليب: شوفان'), findsOneWidget);
    expect(find.text('في أقرب وقت'), findsOneWidget);
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);
    // الاستلام بورقة المسح (الإدخال اليدوي في الورقة نفسها) ثم ملخص الطلب ثم «تأكيد»
    await _tap(tester, find.byKey(const Key('orders-checkin-code')));
    await tester.enterText(find.byKey(const Key('qr-manual')), 'NAS-C1');
    await _tap(tester, find.byKey(const Key('qr-manual-go')));
    expect(find.byKey(const Key('scan-summary')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('scan-confirm')));
    expect(srv.last('POST /biz/biz-cafe/checkin')!['code'], 'NAS-C1');
    expect(find.byKey(const Key('checkin-lines-dialog')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('checkin-lines-dialog')), matching: find.text('كرواسون')), findsOneWidget);
  });

  testWidgets('order page: the customer sees lines, options, pickup time and note', (tester) async {
    await _pump(tester, _Srv(_biz([])), const BizOrderPage(orderId: 'c1'));
    expect(find.byKey(const Key('order-lines')), findsOneWidget);
    expect(_text(tester, 'order-line-options-0'), 'الحجم: كبير · الحليب: شوفان');
    expect(find.descendant(of: find.byKey(const Key('order-page-pickup')), matching: find.text('اليوم ${_clock(_t1)}')), findsOneWidget);
    expect(find.text('بدون سكر'), findsOneWidget);
    expect(find.text('2 × لاتيه، 1 × كرواسون'), findsNothing);
  });
}
