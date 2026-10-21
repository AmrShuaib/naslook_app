// معالج تسجيل الدائرة الموثّق: ست خطوات (النوع، الاسم مع فحص التكرار، الشعار الإلزامي، الحضور الثابت أو المتنقل، الجوال، الصفة)
// ثم «دائرتك جاهزة» بالرابط ورمز QR، ومسار استلام دائرة موجودة، وتحويل أخطاء الخادم، ولافتة «سجّل دائرتك» في الدوائر.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/my_businesses_page.dart';
import 'package:naslook/pages/business/owner/verify_circle_page.dart';
import 'package:naslook/pages/business/register_circle_page.dart';
import 'package:naslook/pages/circles/circles_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final queries = <String, Map<String, String>>{};
  List<Map<String, dynamic>> dups = const [];
  String? registerError;
  int registerErrorCode = 400;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _registered(Map<String, dynamic> b) => {
        'id': 'biz-new', 'name': b['name'] ?? b['nameAr'], 'nameAr': b['nameAr'], 'category': b['category'], 'sector': '', 'description': '', 'lat': b['lat'], 'lng': b['lng'], 'address': '', 'hours': '', 'phone': b['phone'],
        'color': '#0A6E78', 'highlights': [], 'verified': false, 'official': false, 'active': true, 'ownerId': 'SA0000001', 'myRole': 'owner', 'views': 0, 'followers': 0, 'ratingCount': 0, 'itemsCount': 0, 'items': [], 'reviews': [], 'posts': [], 'myOrders': [],
        'logoUrl': b['logoUrl'], 'presence': b['presence'], 'serviceArea': b['presence'] == 'mobile' ? {'lat': b['lat'], 'lng': b['lng'], 'radiusKm': b['radiusKm'], 'districts': b['districts'] ?? []} : null, 'here': null,
        'verificationStatus': 'none', 'canSell': false, 'tier': 'published', 'entityKind': null, 'phoneVerified': false,
      };

  Map<String, dynamic> get _completeness => {
        'tier': 'published', 'percent': 30, 'canSell': false,
        'checks': {'logo': true, 'location': true, 'phone': true, 'hours': false, 'description': false, 'photos': {'have': 1, 'need': 3}, 'catalog': {'have': 0, 'need': 3}, 'entity': {'status': 'none'}, 'phoneVerified': false, 'offer30d': false, 'post30d': false},
        'next': {'key': 'hours', 'title': 'أضف ساعات العمل', 'hint': 'متى يجدك العملاء؟', 'minutes': 1, 'tab': 'profile'},
        'verification': {'status': 'none'},
      };

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    queries[key] = req.url.queryParameters;
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /biz/register/check':
        return _json({'duplicates': dups});
      case 'POST /chat/upload':
        return _json({'url': '/chat/media/logo.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': 3});
      case 'POST /biz/register':
        if (registerError != null) return _json({'error': registerError}, registerErrorCode);
        return _json({'biz': _registered(bodies[key]!), 'completeness': _completeness});
      case 'POST /biz/biz-dup/claim':
        return _json({'ok': true, 'status': 'pending'});
      case 'GET /biz/biz-new':
        return _json(_registered(bodies['POST /biz/register'] ?? {'nameAr': 'قهوة المرسى', 'category': 'cafe', 'lat': 21.5, 'lng': 39.2, 'phone': '+966551234567', 'logoUrl': '/chat/media/logo.jpg', 'presence': 'fixed'}));
      case 'GET /biz/biz-new/completeness':
        return _json(_completeness);
      case 'GET /biz/biz-new/stats':
        return _json({'orders': {}, 'revenue': {}, 'byKind': [], 'daily': [], 'topItems': []});
      case 'GET /biz/mine':
        return _json({'circles': [], 'claims': [], 'admin': false});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv, Size size = const Size(390, 844)}) async {
  SharedPreferences.setMockInitialValues({});
  // مقاس آيفون: المعالج يجب أن يبقى قابلاً للتمرير بحجم هاتف
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return s;
}

bool _nextEnabled(WidgetTester tester, [String key = 'reg-next']) => tester.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;

Future<void> _next(WidgetTester tester) async {
  // إطار واحد بعد الكتابة حتى يُعاد بناء زر «التالي» بحالته الجديدة قبل الضغط
  await tester.pump();
  await tester.tap(find.byKey(const Key('reg-next')));
  await tester.pumpAndSettle();
}

/// يصل إلى خطوة الحضور (4 من 6) باسم وشعار جاهزين.
Future<void> _toPresence(WidgetTester tester, {String name = 'قهوة المرسى'}) async {
  await tester.tap(find.byKey(const Key('reg-cat-cafe')));
  await tester.pump();
  await _next(tester);
  await tester.enterText(find.byKey(const Key('reg-name')), name);
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  await _next(tester);
  await tester.tap(find.byKey(const Key('reg-logo-pick')));
  await tester.pumpAndSettle();
  await _next(tester);
  expect(find.text('4 من 6'), findsOneWidget);
}

void main() {
  setUp(() {
    DeviceLocation.resetForTest();
    DeviceLocation.last = null;
    DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'logo.jpg');
  });
  tearDown(() {
    DeviceLocation.override = null;
    DeviceLocation.last = null;
    pickImageOverride = null;
  });

  test('models: Saudi mobile normalisation and onboarding fields parse', () {
    expect(normalizeSaudiMobile('0551234567'), '+966551234567');
    expect(normalizeSaudiMobile('551234567'), '+966551234567');
    expect(normalizeSaudiMobile('+966 55 123 4567'), '+966551234567');
    expect(normalizeSaudiMobile('00966551234567'), '+966551234567');
    expect(normalizeSaudiMobile('٠٥٥١٢٣٤٥٦٧'), '+966551234567', reason: 'الأرقام العربية تُقبل');
    expect(normalizeSaudiMobile('0112345678'), isNull, reason: 'هاتف أرضي ليس جوالاً');
    expect(normalizeSaudiMobile('12345'), isNull);
    expect(BizCategory.of('salon').itemKind, 'clinic');
    expect(BizCategory.of('entertainment').itemKind, 'showtime');
    expect(BizCategory.of('nope'), BizCategory.brand, reason: 'المجهول يعود إلى براند');
    final b = Biz.fromJson({'id': 'x', 'name': 'X', 'category': 'services', 'lat': 21.5, 'lng': 39.2, 'presence': 'mobile', 'serviceArea': {'lat': 21.5, 'lng': 39.2, 'radiusKm': 12, 'districts': ['الروضة']}, 'here': {'lat': 21.6, 'lng': 39.1, 'until': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String()}, 'verificationStatus': 'approved', 'canSell': true, 'tier': 'verified', 'verified': true});
    expect(b.isMobile, isTrue);
    expect(b.serviceArea!.label, 'يخدم ضمن 12 كم');
    expect(b.hereActive, isTrue);
    expect(b.canSell, isTrue);
    expect(b.tierLabel, 'موثّقة');
    final c = Completeness.fromJson({'tier': 'complete', 'percent': 80, 'canSell': false, 'checks': {'logo': true, 'photos': {'have': 3, 'need': 3}, 'catalog': {'have': 1}, 'entity': {'status': 'pending'}}, 'next': {'key': 'catalog', 'title': 'أضف', 'tab': 'catalog', 'minutes': 5}, 'verification': {'status': 'pending', 'entityKind': 'cr'}});
    expect(c.checks.photos, isTrue);
    expect(c.checks.catalog, isFalse);
    expect(c.next!.tab, 'catalog');
    expect(c.verification.pending, isTrue);
    expect(registerErrText(const ApiException(409, 'رفض الخادم الطلب (too-many)', body: {'error': 'too-many'})), contains('الحد الأقصى'));
    expect(registerErrText(const ApiException(400, 'x', body: {'error': 'bad-phone'})), contains('05XXXXXXXX'), reason: 'الكود من الجسم يكفي حتى لو تُرجم النص');
    expect(registerErrStep(const ApiException(400, 'x', body: {'error': 'logo-required'})), 2);
  });

  testWidgets('fixed circle: six steps post the category, normalised phone, logo and location, then the done page', (tester) async {
    final srv = await _pump(tester, const RegisterCirclePage());
    expect(find.text('1 من 6'), findsOneWidget);
    expect(_nextEnabled(tester), isFalse, reason: 'لا متابعة قبل اختيار النوع');
    expect(find.byKey(const Key('reg-cat-clinic')), findsOneWidget);
    expect(find.text('مستشفى'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-cat-cafe')));
    await tester.pump();
    await _next(tester);
    // الاسم: فحص التكرار بعد 600 مللي ثانية بالاسم وموقع الجهاز
    expect(find.text('2 من 6'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reg-name')), 'قهوة المرسى');
    await tester.pump(const Duration(milliseconds: 300));
    expect(srv.calls, isNot(contains('GET /biz/register/check')), reason: 'المهلة لم تنقضِ بعد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /biz/register/check'));
    expect(srv.queries['GET /biz/register/check']!['name'], 'قهوة المرسى');
    expect(srv.queries['GET /biz/register/check']!['lat'], '21.54330');
    await tester.enterText(find.byKey(const Key('reg-name-latin')), 'Marsa Coffee');
    await _next(tester);
    // الشعار إلزامي
    expect(find.text('3 من 6'), findsOneWidget);
    expect(_nextEnabled(tester), isFalse);
    expect(find.byKey(const Key('reg-logo-required')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-logo-pick')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /chat/upload'));
    expect(_nextEnabled(tester), isTrue);
    await _next(tester);
    // الحضور الثابت: «أنا في المكان الآن»
    expect(find.text('4 من 6'), findsOneWidget);
    expect(_nextEnabled(tester), isFalse, reason: 'لا متابعة بلا موقع');
    await tester.tap(find.byKey(const Key('reg-locate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('21.5433'), findsOneWidget);
    await _next(tester);
    // الجوال بصيغة محلية
    expect(find.text('5 من 6'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reg-phone')), '0551234567');
    await _next(tester);
    // الصفة ثم الإرسال
    expect(find.text('6 من 6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-role-manager')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reg-submit')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/register']!;
    expect(body['category'], 'cafe');
    expect(body['nameAr'], 'قهوة المرسى');
    expect(body['name'], 'Marsa Coffee');
    expect(body['logoUrl'], '/chat/media/logo.jpg');
    expect(body['presence'], 'fixed');
    expect(body['lat'], 21.5433);
    expect(body['lng'], 39.1728);
    expect(body['phone'], '+966551234567', reason: 'الجوال يُرسل بصيغة دولية موحّدة');
    expect(body['role'], 'manager');
    expect(body.containsKey('radiusKm'), isFalse);
    // صفحة النجاح: الرابط وQR وثلاثة مخارج
    expect(find.byKey(const Key('reg-done')), findsOneWidget);
    expect(find.text('دائرتك جاهزة وتظهر على الخريطة الآن'), findsOneWidget);
    expect(find.byKey(const Key('reg-qr')), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('reg-link'))).data, endsWith('/c/biz-new'));
    expect(find.byKey(const Key('reg-done-verify')), findsOneWidget);
    expect(find.byKey(const Key('reg-done-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-done-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessDashboardPage), findsOneWidget);
    expect(find.byKey(const Key('completeness-card')), findsOneWidget);
  });

  testWidgets('mobile circle: centre from the device, radius default 15 and districts are posted', (tester) async {
    final srv = await _pump(tester, const RegisterCirclePage());
    await _toPresence(tester, name: 'سباكة الحي');
    await tester.tap(find.byKey(const Key('reg-presence-mobile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reg-radius')), findsOneWidget);
    expect(find.text('15 كم حول المركز'), findsOneWidget);
    expect(find.textContaining('المركز: 21.5433'), findsOneWidget, reason: 'المركز يُحدَّد تلقائياً من الجهاز');
    await tester.enterText(find.byKey(const Key('reg-district')), 'الروضة');
    await tester.tap(find.byKey(const Key('reg-district-add')));
    await tester.pump();
    expect(find.byKey(const Key('reg-district-الروضة')), findsOneWidget);
    await _next(tester);
    await tester.enterText(find.byKey(const Key('reg-phone')), '+966 55 123 4567');
    await _next(tester);
    await tester.tap(find.byKey(const Key('reg-submit')));
    await tester.pumpAndSettle();
    final body = srv.bodies['POST /biz/register']!;
    expect(body['presence'], 'mobile');
    expect(body['radiusKm'], 15);
    expect(body['districts'], ['الروضة']);
    expect(body['phone'], '+966551234567');
    expect(body['role'], 'owner');
    expect(find.byKey(const Key('reg-done')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-done-verify')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyCirclePage), findsOneWidget);
  });

  testWidgets('logo step: cancelling the picker keeps next disabled; no upload happens', (tester) async {
    pickImageOverride = ({bool camera = false}) async => null;
    final srv = await _pump(tester, const RegisterCirclePage());
    await tester.tap(find.byKey(const Key('reg-cat-shop')));
    await tester.pump();
    await _next(tester);
    await tester.enterText(find.byKey(const Key('reg-name')), 'متجر الهدايا');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.tap(find.byKey(const Key('reg-logo-camera')));
    await tester.pumpAndSettle();
    expect(srv.calls, isNot(contains('POST /chat/upload')));
    expect(_nextEnabled(tester), isFalse);
    expect(find.text('3 من 6'), findsOneWidget);
  });

  testWidgets('duplicate found: «هذه دائرتي، استلمها» runs the claim flow and ends the wizard pending review', (tester) async {
    final srv = _Srv()..dups = [{'id': 'biz-dup', 'name': 'Marsa', 'nameAr': 'قهوة المرسى', 'category': 'cafe', 'distanceKm': 0.4, 'ownerId': null, 'logoUrl': null}, {'id': 'biz-owned', 'name': 'Marsa 2', 'nameAr': 'قهوة المرسى ٢', 'category': 'cafe', 'distanceKm': 1.2, 'ownerId': 'SA0000009', 'logoUrl': null}];
    await _pump(tester, const RegisterCirclePage(), srv: srv);
    await tester.tap(find.byKey(const Key('reg-cat-cafe')));
    await tester.pump();
    await _next(tester);
    await tester.enterText(find.byKey(const Key('reg-name')), 'قهوة المرسى');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('هل هذه دائرتك؟'), findsOneWidget);
    expect(find.byKey(const Key('reg-dup-biz-dup')), findsOneWidget);
    expect(find.byKey(const Key('reg-claim-biz-dup')), findsOneWidget);
    expect(find.byKey(const Key('reg-claim-biz-owned')), findsNothing, reason: 'المملوكة لا تُستلم');
    expect(find.textContaining('لها مالك'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-claim-biz-dup')));
    await tester.pumpAndSettle();
    expect(find.text('إرسال الطلب'), findsOneWidget, reason: 'حوار الاستلام الموجود نفسه مع نص مسبق');
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-dup/claim'));
    expect(srv.bodies['POST /biz/biz-dup/claim']!['note'], contains('قهوة المرسى'));
    expect(find.byKey(const Key('reg-claimed')), findsOneWidget);
    expect(find.text('طلبك قيد المراجعة'), findsOneWidget);
  });

  testWidgets('validation: inline phone error, short name blocks next, server code maps to Arabic and returns to its step', (tester) async {
    final srv = _Srv()..registerError = 'bad-name';
    await _pump(tester, const RegisterCirclePage(), srv: srv);
    await tester.tap(find.byKey(const Key('reg-cat-salon')));
    await tester.pump();
    await _next(tester);
    await tester.enterText(find.byKey(const Key('reg-name')), 'أ');
    await tester.pump();
    expect(_nextEnabled(tester), isFalse, reason: 'الاسم حرفان على الأقل');
    await tester.enterText(find.byKey(const Key('reg-name')), 'صالون نور');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.tap(find.byKey(const Key('reg-logo-pick')));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.tap(find.byKey(const Key('reg-locate')));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(find.byKey(const Key('reg-phone')), '12345');
    await _next(tester);
    expect(find.text('رقم جوال سعودي غير صحيح'), findsOneWidget);
    expect(find.text('5 من 6'), findsOneWidget, reason: 'لا تقدّم برقم خاطئ');
    await tester.enterText(find.byKey(const Key('reg-phone')), '0501112222');
    await tester.pump();
    expect(find.text('رقم جوال سعودي غير صحيح'), findsNothing, reason: 'الكتابة تمسح الخطأ');
    await _next(tester);
    await tester.tap(find.byKey(const Key('reg-submit')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب اسماً عربياً من حرفين إلى 60 حرفاً'), findsOneWidget);
    expect(find.text('2 من 6'), findsOneWidget, reason: 'يعود إلى خطوة الحقل المرفوض');
    expect(find.byKey(const Key('reg-done')), findsNothing);
  });

  testWidgets('circles: the discover banner and the empty mine state open the wizard; my businesses FAB too', (tester) async {
    await _pump(tester, const CirclesPage());
    expect(find.byKey(const Key('register-mine')), findsOneWidget, reason: 'بلا دوائر: زر التسجيل في الحالة الفارغة');
    // «اكتشف» مرتان: مقطع التبويب (الأول في الشجرة) وزر الحالة الفارغة
    await tester.tap(find.text('اكتشف').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('register-banner')), findsOneWidget);
    expect(find.text('هل تملك نشاطاً؟ سجّل دائرتك في دقيقتين'), findsOneWidget);
    await tester.tap(find.byKey(const Key('register-banner')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterCirclePage), findsOneWidget);
    expect(find.text('1 من 6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-back')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterCirclePage), findsNothing, reason: 'الرجوع من الخطوة الأولى يغلق المعالج');
  });

  testWidgets('my businesses: the create button opens the wizard instead of the old editor', (tester) async {
    await _pump(tester, const MyBusinessesPage());
    expect(find.text('دائرة تجارية جديدة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-biz-register')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterCirclePage), findsOneWidget);
  });
}
