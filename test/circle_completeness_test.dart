// اكتمال الدائرة في لوحة التحكم (الدرجة والنسبة والخطوة التالية التي تفتح تبويبها)، صفحة التوثيق بحالاتها الثلاث،
// ورقة «أنا هنا اليوم»، شارات الصفحة العامة (موثّق، متنقل، هنا اليوم)، وخطأ «لم تُوثَّق بعد» عند الطلب، وتوجيه إشعارات التوثيق.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/verify_circle_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _id = 'biz-cafe';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool verified = false;
  String presence = 'fixed';
  Map<String, dynamic>? serviceArea, here;
  Map<String, dynamic> verification = {'status': 'none'};
  Map<String, dynamic>? next = {'key': 'catalog', 'title': 'أضف 3 عناصر إلى الكتالوج', 'hint': 'منتجات أو خدمات أو مواعيد', 'minutes': 5, 'tab': 'catalog'};
  int percent = 40;
  String tier = 'published';
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _biz() => {
        'id': _id, 'name': 'Cafe', 'nameAr': 'مقهى عمرو', 'category': 'cafe', 'sector': 'مقهى', 'description': 'قهوة مختصة على الكورنيش', 'lat': 21.5, 'lng': 39.2, 'address': 'الروضة، جدة', 'hours': '8-12', 'phone': '+966551234567',
        'color': '#0058A3', 'highlights': [], 'verified': verified, 'official': false, 'active': true, 'ownerId': 'SA0000001', 'myRole': 'owner', 'views': 7, 'followers': 3, 'rating': 4.0, 'ratingCount': 1, 'minPrice': 1500, 'itemsCount': 1,
        'items': [{'id': 'cafe-latte', 'bizId': _id, 'kind': 'product', 'title': 'لاتيه', 'price': 1500, 'unit': 'item', 'stock': 10, 'meta': {}, 'active': true}], 'reviews': [], 'posts': [], 'myOrders': [],
        'presence': presence, 'serviceArea': serviceArea, 'here': here, 'verificationStatus': verification['status'], 'canSell': verification['status'] == 'approved', 'tier': tier, 'entityKind': verification['entityKind'], 'phoneVerified': false,
      };

  Map<String, dynamic> _completeness() => {
        'tier': tier, 'percent': percent, 'canSell': verification['status'] == 'approved',
        'checks': {'logo': false, 'location': true, 'phone': true, 'hours': true, 'description': true, 'photos': {'have': 1, 'need': 3}, 'catalog': {'have': 1, 'need': 3}, 'entity': {'status': verification['status']}, 'phoneVerified': false, 'offer30d': false, 'post30d': false},
        'next': next, 'verification': verification,
      };

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /biz/$_id':
        return _json(_biz());
      case 'GET /biz/$_id/completeness':
        return _json(_completeness());
      case 'GET /biz/$_id/stats':
        return _json({'orders': {'total': 1, 'last7': 1}, 'revenue': {'total': 1500, 'last7': 1500}, 'byKind': [], 'daily': [], 'topItems': [], 'followers': 3, 'reviews': 0, 'unanswered': 0, 'views': 7});
      case 'POST /biz/$_id/verification':
        final b = bodies[key]!;
        verification = {'status': 'pending', 'entityKind': b['entityKind'], 'submittedAt': DateTime.now().toUtc().toIso8601String()};
        return _json({'status': 'pending', 'verification': verification});
      case 'POST /biz/$_id/here':
        final b = bodies[key]!;
        here = {'lat': b['lat'], 'lng': b['lng'], 'until': DateTime.now().add(Duration(hours: (b['hours'] as num).toInt())).toUtc().toIso8601String()};
        return _json({'here': here});
      case 'DELETE /biz/$_id/here':
        here = null;
        return _json({'ok': true});
      case 'POST /chat/upload':
        return _json({'url': '/chat/media/doc.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': 3});
      case 'GET /biz/$_id/orders':
        return _json([]);
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json({});
    return _json({'ok': true});
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(420, 1400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

int _tabIndex(WidgetTester tester) => DefaultTabController.of(tester.element(find.byType(TabBarView))).index;

void main() {
  setUp(() {
    DeviceLocation.resetForTest();
    DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'cr.jpg');
  });
  tearDown(() {
    DeviceLocation.override = null;
    DeviceLocation.last = null;
    pickImageOverride = null;
  });

  testWidgets('completeness card: tier, percent, locked line, checklist, and the next step switches to its tab', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: _id));
    expect(srv.calls, contains('GET /biz/$_id/completeness'));
    expect(find.byKey(const Key('completeness-card')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('completeness-tier')), matching: find.text('منشورة')), findsOneWidget);
    expect(find.text('40٪'), findsOneWidget);
    expect(find.byKey(const Key('completeness-locked')), findsOneWidget);
    expect(find.text('البيع والحجز مقفلان حتى التوثيق'), findsOneWidget);
    expect(find.text('الخطوة التالية: أضف 3 عناصر إلى الكتالوج · 5 دقيقة'), findsOneWidget);
    expect(find.text('الصور 1/3'), findsOneWidget);
    expect(find.text('الكتالوج 1/3'), findsOneWidget);
    expect(find.text('ساعات العمل'), findsOneWidget);
    expect(_tabIndex(tester), 0);
    await tester.tap(find.byKey(const Key('completeness-go')));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), BusinessDashboardPage.tabIndexFor('catalog'), reason: 'الزر يفتح تبويب الكتالوج');
  });

  testWidgets('completeness: verified+complete circle shows the tier without the locked line; next=verify opens the verify page', (tester) async {
    final srv = _Srv()
      ..verified = true
      ..tier = 'verified'
      ..percent = 100
      ..verification = {'status': 'approved', 'entityKind': 'cr', 'reviewedAt': '2026-10-20T08:00:00Z'}
      ..next = null;
    await _pump(tester, srv, const BusinessDashboardPage(id: _id));
    expect(find.text('موثّقة'), findsWidgets);
    expect(find.byKey(const Key('completeness-locked')), findsNothing);
    expect(find.byKey(const Key('completeness-next')), findsNothing);
    expect(find.text('التوثيق ✓'), findsOneWidget);
    // الخطوة التالية = التوثيق: الزر يفتح صفحة التوثيق لا تبويباً
    final srv2 = _Srv()..next = {'key': 'entity', 'title': 'وثّق دائرتك', 'hint': 'سجل تجاري أو وثيقة عمل حر', 'minutes': 3, 'tab': 'verify'};
    await _pump(tester, srv2, const BusinessDashboardPage(id: _id));
    await tester.tap(find.byKey(const Key('completeness-go')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyCirclePage), findsOneWidget);
    expect(find.byKey(const Key('verify-kind-cr')), findsOneWidget);
  });

  testWidgets('verify page: number and document gate submit; submit posts the payload and shows pending', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const VerifyCirclePage(bizId: _id));
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-submit'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('verify-number')), '1010123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-submit'))).onPressed, isNull, reason: 'المستند مطلوب');
    await tester.tap(find.byKey(const Key('verify-doc-pick')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /chat/upload'));
    expect(find.byKey(const Key('verify-doc-preview')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-submit'))).onPressed, isNotNull);
    // وثيقة العمل الحر: رقم قصير يُرفض وطويل يُقبل
    await tester.tap(find.byKey(const Key('verify-kind-freelance')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('verify-number')), 'abc');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-submit'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('verify-number')), 'FL12345678');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-submit'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('verify-kind-cr')));
    await tester.enterText(find.byKey(const Key('verify-number')), '١٠١٠١٢٣٤٥٦');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify-submit')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/$_id/verification']!;
    expect(body['entityKind'], 'cr');
    expect(body['entityNumber'], '1010123456', reason: 'الأرقام العربية تُحوَّل');
    expect(body['docUrl'], '/chat/media/doc.jpg');
    expect(find.byKey(const Key('verify-pending')), findsOneWidget);
    expect(find.text('قيد المراجعة من الإدارة، عادةً خلال يوم عمل'), findsOneWidget);
  });

  testWidgets('verify page: approved and rejected states; rejected shows the reason and «أعد الإرسال» reveals the form', (tester) async {
    final approved = _Srv()..verified = true..verification = {'status': 'approved', 'entityKind': 'freelance', 'reviewedAt': '2026-10-20T08:00:00Z'};
    await _pump(tester, approved, const VerifyCirclePage(bizId: _id));
    expect(find.byKey(const Key('verify-approved')), findsOneWidget);
    expect(find.text('دائرتك موثّقة'), findsOneWidget);
    expect(find.textContaining('وثيقة العمل الحر'), findsWidgets);
    expect(find.byKey(const Key('verify-submit')), findsNothing);
    final rejected = _Srv()..verification = {'status': 'rejected', 'entityKind': 'cr', 'reason': 'الصورة غير واضحة', 'reviewedAt': '2026-10-20T08:00:00Z'};
    await _pump(tester, rejected, const VerifyCirclePage(bizId: _id));
    expect(find.byKey(const Key('verify-rejected')), findsOneWidget);
    expect(find.text('السبب: الصورة غير واضحة'), findsOneWidget);
    expect(find.byKey(const Key('verify-submit')), findsNothing);
    await tester.tap(find.byKey(const Key('verify-resubmit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verify-number')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('verify-submit')), matching: find.text('أعد الإرسال')), findsOneWidget);
    expect(verifyErrText(const ApiException(409, 'x', body: {'error': 'already-approved'})), 'الدائرة موثّقة بالفعل');
  });

  testWidgets('here today: the sheet posts hours and the device location; the active state shows «حتى» and ends', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: _id));
    expect(find.byKey(const Key('here-active')), findsNothing);
    await tester.tap(find.byKey(const Key('here-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('here-h-2')), findsOneWidget);
    expect(find.byKey(const Key('here-end')), findsNothing, reason: 'لا دبوس سارياً بعد');
    await tester.tap(find.byKey(const Key('here-h-6')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('here-set')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/$_id/here']!;
    expect(body['hours'], 6);
    expect(body['lat'], 21.5433);
    expect(body['lng'], 39.1728);
    final until = DateTime.parse(srv.here!['until'] as String).toLocal();
    expect(find.byKey(const Key('here-active')), findsOneWidget, reason: 'اللوحة تُحدَّث وتعرض الدبوس الساري');
    expect(find.text('أنت هنا حتى ${clockLabel(until)}'), findsWidgets);
    // رسالة التأكيد (SnackBar) تغطي الإجراءات السريعة أسفل الشاشة؛ ننتظر زوالها قبل الضغط
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('here-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('here-until')), findsOneWidget);
    await tester.tap(find.byKey(const Key('here-end')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('DELETE /biz/$_id/here'));
    expect(find.byKey(const Key('here-active')), findsNothing);
  });

  testWidgets('public page: verified, mobile and here-today badges; service area replaces the address; not-verified maps to Arabic', (tester) async {
    final until = DateTime.now().add(const Duration(hours: 3));
    final srv = _Srv()
      ..verified = true
      ..presence = 'mobile'
      ..serviceArea = {'lat': 21.5, 'lng': 39.2, 'radiusKm': 12, 'districts': ['الروضة', 'الشاطئ']}
      ..here = {'lat': 21.6, 'lng': 39.1, 'until': until.toUtc().toIso8601String()};
    await _pump(tester, srv, const BusinessPage(id: _id), size: const Size(800, 2400));
    expect(find.byKey(const Key('badge-verified')), findsOneWidget);
    expect(find.text('موثّق'), findsOneWidget);
    expect(find.byKey(const Key('badge-mobile')), findsOneWidget);
    expect(find.text('متنقل · يخدم ضمن 12 كم'), findsOneWidget);
    expect(find.byKey(const Key('badge-here')), findsOneWidget);
    expect(find.text('هنا اليوم حتى ${clockLabel(until)}'), findsWidgets);
    expect(find.byKey(const Key('info-service-area')), findsOneWidget);
    expect(find.text('يخدم ضمن 12 كم · الروضة، الشاطئ'), findsOneWidget);
    expect(find.text('الروضة، جدة'), findsNothing, reason: 'المتنقلة بلا سطر عنوان');
    expect(bizErrText(const ApiException(403, 'رفض الخادم الطلب (not-verified)', body: {'error': 'not-verified'})), 'هذه الدائرة لم تُوثَّق بعد فلا يمكن الطلب منها الآن');
    // دائرة ثابتة غير موثّقة: لا شارات، والعنوان يظهر
    final plain = _Srv();
    await _pump(tester, plain, const BusinessPage(id: _id), size: const Size(800, 2400));
    expect(find.byKey(const Key('badge-verified')), findsNothing);
    expect(find.byKey(const Key('badge-mobile')), findsNothing);
    expect(find.text('الروضة، جدة'), findsOneWidget);
  });

  test('notifications: verification decisions open the verify page of that circle', () {
    final ok = notificationTarget(const AppNotification(id: '1', kind: 'biz_verified', title: 'وُثّقت', data: {'bizId': _id}));
    expect(ok, isA<VerifyCirclePage>());
    expect((ok as VerifyCirclePage).bizId, _id);
    final no = notificationTarget(const AppNotification(id: '2', kind: 'biz_verification_rejected', title: 'رُفض', data: {'bizId': _id, 'reason': 'x'}));
    expect(no, isA<VerifyCirclePage>());
    expect(notificationTarget(const AppNotification(id: '3', kind: 'biz_verified', title: 'بلا دائرة')), isNull);
    expect(notificationStyle('biz_verified').icon, Icons.verified_rounded);
    expect(notificationStyle('biz_verification_rejected').icon, Icons.gpp_bad_outlined);
  });
}
