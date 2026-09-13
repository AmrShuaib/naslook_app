// الدائرة الطبية: تصنيف مستشفى، بطاقة عيادة بمواعيد مجانية وحجز لشخص واحد، وبطاقة خدمة تعريفية بلا زر طلب.
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
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _slot1 = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
final _slot2 = _slot1.add(const Duration(hours: 1));

Map<String, dynamic> _hospital() => {
      'id': 'biz-kfgh', 'name': 'King Fahd General Hospital', 'nameAr': 'مستشفى الملك فهد العام بجدة', 'category': 'hospital', 'sector': 'مستشفى عام حكومي',
      'description': 'مستشفى مرجعي', 'lat': 21.5178, 'lng': 39.1834, 'address': 'حي الأندلس، جدة', 'hours': 'الطوارئ 24 ساعة', 'phone': '937', 'color': '#1B7F5C',
      'highlights': ['طوارئ 24 ساعة', 'مركز القلب'], 'followers': 3, 'itemsCount': 3, 'active': true, 'reviews': [], 'myOrders': [], 'posts': [],
      'items': [
        {'id': 'kfgh-family', 'bizId': 'biz-kfgh', 'kind': 'clinic', 'title': 'عيادة طب الأسرة', 'description': 'الكشف العام', 'price': 0, 'unit': 'visit', 'stock': 6, 'meta': {'floor': 'الدور الأول', 'minutes': 20},
          'slots': [{'startsAt': _slot1.toUtc().toIso8601String(), 'seatsLeft': 6}, {'startsAt': _slot2.toUtc().toIso8601String(), 'seatsLeft': 1}], 'active': true},
        {'id': 'kfgh-dental', 'bizId': 'biz-kfgh', 'kind': 'clinic', 'title': 'عيادة الأسنان', 'description': '', 'price': 5000, 'unit': 'visit', 'stock': 4, 'meta': {}, 'slots': [], 'active': true},
        {'id': 'kfgh-er', 'bizId': 'biz-kfgh', 'kind': 'info', 'title': 'الطوارئ والحوادث', 'description': 'استقبال الحالات الطارئة على مدار الساعة', 'price': 0, 'unit': 'item', 'meta': {'hours': '24 ساعة', 'location': 'مدخل الطوارئ', 'phone': '997'}, 'active': true},
      ],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /biz/biz-kfgh') return _json(_hospital());
    if (key == 'POST /biz/biz-kfgh/orders') {
      final b = bodies[key]!;
      return _json({'id': 'o1', 'bizId': 'biz-kfgh', 'itemId': b['itemId'], 'title': 'عيادة طب الأسرة', 'kind': 'clinic', 'qty': 1, 'startAt': b['startAt'], 'total': 0, 'status': 'confirmed', 'code': 'NAS-1234', 'meta': {'clinic': 'عيادة طب الأسرة'}, 'cancellable': true, 'createdAt': DateTime.now().toUtc().toIso8601String()});
    }
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /wishlist') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: BusinessPage(id: 'biz-kfgh')),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  test('hospital category and clinic kind labels', () {
    expect(BizCategory.of('hospital'), BizCategory.hospital);
    expect(BizCategory.hospital.itemKind, 'clinic');
    expect(BizCategory.hospital.catalogTitle, 'العيادات والخدمات');
    expect(BizCategory.hospital.actionLabel, 'احجز موعداً');
    expect(isSlotKind('clinic'), isTrue);
    expect(isSlotKind('room'), isFalse);
    final it = BizItem.fromJson(_hospital()['items'][0] as Map);
    expect(it.isFree, isTrue);
    expect(it.unitLabel, 'للزيارة');
    expect(it.slots.length, 2);
  });

  testWidgets('hospital page shows clinics with free appointment slots and info services without a buy button', (tester) async {
    final srv = await _pump(tester);
    await _settle(tester);
    expect(find.text('مستشفى الملك فهد العام بجدة'), findsWidgets);
    expect(find.text('العيادات والخدمات'), findsOneWidget);
    expect(find.text('عيادة طب الأسرة'), findsOneWidget);
    expect(find.text('مجاني'), findsOneWidget, reason: 'العيادة المجانية تُعرض بلا سعر');
    expect(find.text('الدور الأول'), findsOneWidget);
    expect(find.text('الطوارئ والحوادث'), findsOneWidget);
    expect(find.text('24 ساعة'), findsOneWidget);
    expect(find.text('997'), findsOneWidget);
    expect(find.text('اشترِ'), findsNothing);
    expect(find.text('لا مواعيد متاحة هذا الأسبوع'), findsOneWidget, reason: 'عيادة الأسنان بلا مواعيد');
    // اختيار موعد ثم الحجز
    expect(find.textContaining('متبقٍ 1'), findsOneWidget);
    await tester.tap(find.byType(ChoiceChip).first);
    await _settle(tester);
    expect(find.textContaining('الموعد:'), findsOneWidget);
    await tester.tap(find.text('احجز الموعد'));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-kfgh/orders']!;
    expect(body['itemId'], 'kfgh-family');
    expect(body['qty'], 1);
    expect(DateTime.parse(body['startAt'] as String).toUtc(), _slot1.toUtc());
  });
}
