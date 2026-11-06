// مواعيد الصالونات والخدمات والعيادات: أيام العمل يختارها المالك (السبت – الجمعة) وتُحفظ في meta.days بترقيم الخادم
// (0 = الأحد … 6 = السبت)، ونصوص الخدمة للصالون والخدمات ونصوص العيادة للعيادة والمستشفى، واختيار «منتج» أو «موعد» حيث تجمع الفئة
// بينهما، ومواعيد الجمعة والسبت تظهر للعميل ويُحجز منها.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/dashboard_catalog.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart' show clockOf;

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// أول يوم بهذا الرقم (DateTime.friday …) بعد يومين على الأقل، حتى لا يُعرض «اليوم» أو «غداً».
DateTime _next(int weekday, int hour) {
  var d = DateTime.now().add(const Duration(days: 2));
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d.copyWith(hour: hour, minute: 0, second: 0, millisecond: 0, microsecond: 0);
}

final _friday = _next(DateTime.friday, 18);
final _saturday = _next(DateTime.saturday, 19);

Map<String, dynamic> _biz(String category, {List<Map<String, dynamic>> items = const [], String role = 'owner'}) => {
      'id': 'biz-$category', 'name': category, 'nameAr': 'دائرة $category', 'category': category, 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '',
      'color': '#0058A3', 'highlights': [], 'verified': true, 'official': false, 'active': true, 'ownerId': 'SA0000001', 'myRole': role, 'followers': 0, 'itemsCount': items.length,
      'items': items, 'reviews': [], 'posts': [], 'myOrders': [], 'verificationStatus': 'approved', 'canSell': true,
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final Map<String, dynamic> biz;
  _Srv(this.biz);
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    final id = biz['id'];
    if (key == 'GET /biz/$id') return _json(biz);
    if (key == 'POST /biz/$id/items') { final b = bodies[key]!; return _json({'id': 'new-1', 'bizId': id, ...b, 'unit': b['kind'] == 'clinic' ? 'visit' : 'item', 'active': true}); }
    if (key.startsWith('PATCH /biz/$id/items/')) return _json({'id': key.split('/').last, 'bizId': id, ...bodies[key]!, 'active': true});
    if (key == 'POST /biz/$id/orders') {
      final b = bodies[key]!;
      return _json({'id': 'o1', 'bizId': id, 'itemId': b['itemId'], 'title': 'قص شعر', 'kind': 'clinic', 'category': biz['category'], 'qty': 1, 'startAt': b['startAt'], 'total': 0, 'status': 'confirmed', 'code': 'NAS-1234', 'meta': {}, 'cancellable': true, 'createdAt': DateTime.now().toUtc().toIso8601String()});
    }
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /wishlist') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Map<String, dynamic> biz, {bool catalog = true}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv(biz);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: catalog ? CatalogTab(biz: Biz.fromJson(biz)) : BusinessPage(id: biz['id'] as String)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _addTime(WidgetTester tester, String t) async {
  await tester.enterText(find.widgetWithText(TextField, 'وقت بصيغة 24 ساعة مثل 19:30'), t);
  await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
  await tester.pump();
}

bool _daySelected(WidgetTester tester, int d) => tester.widget<FilterChip>(find.byKey(Key('day-$d'))).selected;

void main() {
  test('categories, work days and labels', () {
    expect(BizCategory.salon.itemKinds, ['clinic', 'product']);
    expect(BizCategory.services.itemKinds, ['product', 'clinic']);
    expect(BizCategory.clinic.itemKinds, ['clinic']);
    expect(BizCategory.cafe.itemKinds, ['product']);
    expect(BizCategory.hospital.clinicWords, isTrue);
    expect(BizCategory.clinic.clinicWords, isTrue);
    expect(BizCategory.salon.clinicWords, isFalse);
    expect(BizCategory.services.clinicWords, isFalse);
    // ترقيم الخادم: 0 = الأحد … 6 = السبت، والعرض من السبت إلى الجمعة
    expect(appointmentWeekdays.map((d) => d.$1).toList(), [6, 0, 1, 2, 3, 4, 5]);
    expect(appointmentWeekdays.first.$2, 'السبت');
    expect(appointmentWeekdays.last.$2, 'الجمعة');
    expect(workDaysLabel(null), 'كل الأيام');
    expect(workDaysLabel([0, 1, 2, 3, 4, 5, 6]), 'كل الأيام');
    expect(workDaysLabel([0, 1, 2, 3, 4]), 'الأحد – الخميس');
    expect(workDaysLabel([6, 0, 1, 2, 3, 4]), 'السبت – الخميس');
    expect(workDaysLabel([5, 6]), 'السبت، الجمعة');
    expect(BizItem.fromJson({'id': 'x', 'kind': 'clinic', 'title': 't', 'price': 0, 'meta': {'days': [5, 6, 9]}}).workDays, [5, 6]);
    expect(BizItem.fromJson({'id': 'x', 'kind': 'clinic', 'title': 't', 'price': 0, 'meta': {}}).workDays, isNull);
    Map<String, dynamic> order(String cat) => {'id': 'o', 'kind': 'clinic', 'qty': 1, 'units': 1, 'total': 0, 'status': 'confirmed', 'code': 'X', 'category': cat};
    expect(BizOrder.fromJson(order('hospital')).kindLabel, 'موعد عيادة');
    expect(BizOrder.fromJson(order('salon')).kindLabel, 'موعد خدمة');
  });

  testWidgets('salon: a service appointment uses service words, all seven days by default, and saves the chosen days', (tester) async {
    final srv = await _pump(tester, _biz('salon'));
    await tester.tap(find.text('إضافة خدمة'));
    await _settle(tester);
    // الصالون يجمع الموعد والمنتج، والموعد أولاً
    expect(find.byKey(const Key('item-kind')), findsOneWidget);
    expect(tester.widget<SegmentedButton<String>>(find.byKey(const Key('item-kind'))).selected, {'clinic'});
    expect(find.widgetWithText(TextField, 'اسم الخدمة'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'عملاء لكل موعد'), findsOneWidget);
    expect(find.text('مواعيد الخدمة اليومية'), findsOneWidget);
    expect(find.text('اسم العيادة'), findsNothing);
    expect(find.text('مرضى لكل موعد'), findsNothing);
    expect(find.textContaining('مواعيد العيادة'), findsNothing);
    // أيام العمل السبعة من السبت إلى الجمعة، كلها محددة للخدمة الجديدة
    expect(find.text('أيام العمل'), findsOneWidget);
    for (final d in [0, 1, 2, 3, 4, 5, 6]) {
      expect(_daySelected(tester, d), isTrue, reason: 'day $d');
    }
    final order = tester.widgetList<FilterChip>(find.byType(FilterChip)).map((c) => c.key).toList();
    expect(order, [for (final d in [6, 0, 1, 2, 3, 4, 5]) Key('day-$d')], reason: 'السبت أولاً والجمعة آخراً');
    // إيقاف الأحد، ووقت مسائي
    await tester.tap(find.byKey(const Key('day-0')));
    await tester.pump();
    expect(_daySelected(tester, 0), isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'اسم الخدمة'), 'قص شعر');
    await tester.enterText(find.widgetWithText(TextField, 'سعر الخدمة (0 = مجاني)'), '60');
    await _addTime(tester, '18:00');
    await tester.tap(find.text('إضافة').last);
    await _settle(tester);
    final b = srv.bodies['POST /biz/biz-salon/items']!;
    expect(b['kind'], 'clinic');
    expect(b['title'], 'قص شعر');
    expect(b['price'], 6000);
    expect(b['stock'], 1, reason: 'عميل واحد لكل موعد افتراضياً للخدمة');
    expect((b['meta'] as Map)['days'], [1, 2, 3, 4, 5, 6], reason: 'الجمعة (5) والسبت (6) محفوظان، والأحد (0) موقوف');
    expect((b['meta'] as Map)['times'], ['18:00']);
    expect((b['meta'] as Map)['minutes'], 30);
  });

  testWidgets('appointment needs at least one work day', (tester) async {
    final srv = await _pump(tester, _biz('salon'));
    await tester.tap(find.text('إضافة خدمة'));
    await _settle(tester);
    for (final d in [0, 1, 2, 3, 4, 5, 6]) {
      await tester.tap(find.byKey(Key('day-$d')));
      await tester.pump();
    }
    await tester.enterText(find.widgetWithText(TextField, 'اسم الخدمة'), 'صبغة');
    await _addTime(tester, '17:00');
    await tester.tap(find.text('إضافة').last);
    await _settle(tester);
    expect(find.text('اختر يوم عمل واحداً على الأقل'), findsOneWidget);
    expect(srv.calls.where((c) => c.startsWith('POST')), isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('services: product by default, switching to «موعد» adds a bookable service with days', (tester) async {
    final srv = await _pump(tester, _biz('services'));
    await tester.tap(find.text('إضافة خدمة'));
    await _settle(tester);
    expect(tester.widget<SegmentedButton<String>>(find.byKey(const Key('item-kind'))).selected, {'product'});
    expect(find.widgetWithText(TextField, 'اسم المنتج'), findsOneWidget);
    expect(find.text('أيام العمل'), findsNothing);
    await tester.tap(find.byKey(const Key('item-kind-clinic')));
    await _settle(tester);
    expect(find.widgetWithText(TextField, 'اسم الخدمة'), findsOneWidget);
    expect(find.text('مواعيد الخدمة اليومية'), findsOneWidget);
    expect(find.text('أيام العمل'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'اسم الخدمة'), 'صيانة مكيف');
    await _addTime(tester, '10:00');
    await tester.tap(find.text('إضافة').last);
    await _settle(tester);
    final b = srv.bodies['POST /biz/biz-services/items']!;
    expect(b['kind'], 'clinic');
    expect((b['meta'] as Map)['days'], [0, 1, 2, 3, 4, 5, 6]);
  });

  testWidgets('services: a plain product still saves as a product', (tester) async {
    final srv = await _pump(tester, _biz('services'));
    await tester.tap(find.text('إضافة خدمة'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'اسم المنتج'), 'فلتر مكيف');
    await tester.enterText(find.widgetWithText(TextField, 'السعر (ر.س)'), '25');
    await tester.tap(find.text('إضافة').last);
    await _settle(tester);
    final b = srv.bodies['POST /biz/biz-services/items']!;
    expect(b['kind'], 'product');
    expect((b['meta'] as Map).containsKey('days'), isFalse);
  });

  testWidgets('clinic keeps clinic words, Sunday–Thursday by default, no kind choice', (tester) async {
    final srv = await _pump(tester, _biz('clinic'));
    await tester.tap(find.text('إضافة عيادة أو خدمة'));
    await _settle(tester);
    expect(find.byKey(const Key('item-kind')), findsNothing);
    expect(find.widgetWithText(TextField, 'اسم العيادة'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'مرضى لكل موعد'), findsOneWidget);
    expect(find.text('مواعيد العيادة اليومية'), findsOneWidget);
    expect(_daySelected(tester, 6), isFalse, reason: 'السبت');
    expect(_daySelected(tester, 5), isFalse, reason: 'الجمعة');
    for (final d in [0, 1, 2, 3, 4]) {
      expect(_daySelected(tester, d), isTrue);
    }
    // العيادة تفتح السبت أيضاً
    await tester.tap(find.byKey(const Key('day-6')));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'اسم العيادة'), 'عيادة الجلدية');
    await _addTime(tester, '09:00');
    await tester.tap(find.text('إضافة').last);
    await _settle(tester);
    final b = srv.bodies['POST /biz/biz-clinic/items']!;
    expect(b['kind'], 'clinic');
    expect((b['meta'] as Map)['days'], [0, 1, 2, 3, 4, 6]);
    expect((b['meta'] as Map)['minutes'], 20);
  });

  testWidgets('editing an appointment shows its saved days and the catalog line names them', (tester) async {
    final item = {'id': 'salon-cut', 'bizId': 'biz-salon', 'kind': 'clinic', 'title': 'قص شعر', 'description': '', 'price': 6000, 'unit': 'visit', 'stock': 1, 'meta': {'times': ['18:00'], 'days': [5, 6], 'minutes': 30}, 'active': true};
    final srv = await _pump(tester, _biz('salon', items: [item]));
    expect(tester.widget<Text>(find.byKey(const Key('catalog-line-salon-cut'))).data, contains('السبت، الجمعة'));
    expect(find.textContaining('عملاء/موعد'), findsOneWidget);
    await tester.tap(find.text('قص شعر'));
    await _settle(tester);
    expect(find.byKey(const Key('item-kind')), findsNothing, reason: 'النوع لا يتغير بعد الإضافة');
    expect(_daySelected(tester, 5), isTrue);
    expect(_daySelected(tester, 6), isTrue);
    expect(_daySelected(tester, 0), isFalse);
    await tester.tap(find.byKey(const Key('day-4')));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await _settle(tester);
    final b = srv.bodies['PATCH /biz/biz-salon/items/salon-cut']!;
    expect((b['meta'] as Map)['days'], [4, 5, 6]);
  });

  testWidgets('customer sees Friday and Saturday salon slots and books one', (tester) async {
    final item = {
      'id': 'salon-cut', 'bizId': 'biz-salon', 'kind': 'clinic', 'title': 'قص شعر', 'description': 'قص وتصفيف', 'price': 0, 'unit': 'visit', 'stock': 1, 'meta': {'times': ['18:00', '19:00'], 'days': [5, 6], 'minutes': 30},
      'slots': [for (final t in [_friday, _saturday]..sort()) {'startsAt': t.toUtc().toIso8601String(), 'seatsLeft': 1}], 'active': true,
    };
    final srv = await _pump(tester, _biz('salon', items: [item], role: 'none'), catalog: false);
    await _settle(tester);
    expect(find.text('قص شعر'), findsOneWidget);
    expect(find.textContaining('الجمعة'), findsWidgets);
    expect(find.textContaining('السبت'), findsWidgets);
    expect(find.byIcon(Icons.content_cut_rounded), findsWidgets, reason: 'أيقونة الصالون لا العيادة');
    expect(find.byIcon(Icons.medical_services_outlined), findsNothing);
    await tester.tap(find.ancestor(of: find.textContaining(clockOf(_friday)), matching: find.byType(ChoiceChip)));
    await _settle(tester);
    await tester.tap(find.text('احجز الموعد'));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-salon/orders']!;
    expect(body['itemId'], 'salon-cut');
    expect(DateTime.parse(body['startAt'] as String).toUtc(), _friday.toUtc());
  });
}
