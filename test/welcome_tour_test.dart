// جولة الترحيب: ثلاث صفحات تظهر مرة واحدة لزائر بلا جلسة قبل واجهة الزائر أو شاشة الدخول. تنتهي بـ«ابدأ» أو «تخطي»
// فتُحفظ «رآها» ويكمل المسار المعتاد؛ لا تظهر لمن رآها ولا للقادم برابط مشترك؛ لا تطفح عند أكبر تكبير للنص على شاشة
// صغيرة؛ وتُعاد من «عن ناس لايف» في ماي سبيس.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/pages/welcome/welcome_seen.dart';
import 'package:naslook/pages/welcome/welcome_tour_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _Auth extends AppStateNotifier {
  _Auth(super.api, super.store, bool signedIn) {
    state = signedIn
        ? const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')))
        : const AppState(status: AuthStatus.signedOut);
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

Future<http.Response> _handle(http.Request req) async {
  switch ('${req.method} ${req.url.path}') {
    case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false});
    case 'GET /row': return _json({'items': [], 'located': false});
    case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
    case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
    case 'GET /me/map-presence': return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
    case 'GET /me/recovery': return _json({'enabled': true, 'email': 'amr@example.com', 'verified': true, 'mailConfigured': true});
    case 'GET /me/login-email': return _json({'email': 'amr@example.com', 'verified': true, 'mailConfigured': true});
    case 'GET /notify/unread': return _json({'unread': 0});
  }
  if (req.method == 'GET') return _json([]);
  return _json({'ok': true});
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _pump(WidgetTester tester, {Widget home = const AuthGate(), bool signedIn = false, Size size = const Size(900, 1400), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _Auth(api, SessionStore(), signedIn)),
      notifyPollIntervalProvider.overrideWithValue(null),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: home,
    ),
  ));
  await _settle(tester);
}

final _tour = find.byKey(const Key('welcome-tour'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceLocation.override = () async => null;
    iosNativeOverride = false;
  });
  tearDown(() {
    WelcomeSeen.debugSet(true);
    iosNativeOverride = null;
    DeviceLocation.override = null;
    ApiClient.onUnauthorized = null;
    pendingLink = null;
  });

  testWidgets('first-time signed-out visitor sees the tour; «التالي» twice then «ابدأ» saves it and reveals login', (tester) async {
    // كما في main: القراءة من تخزين فارغ تعني زائراً جديداً
    await WelcomeSeen.prime();
    expect(WelcomeSeen.seen.value, isFalse);
    await _pump(tester);
    expect(_tour, findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byKey(const Key('welcome-dots')), findsOneWidget);
    expect(find.byKey(const Key('welcome-logo')), findsOneWidget, reason: 'الشعار في الصفحة الأولى');
    expect(find.text('الخريطة'), findsOneWidget);
    expect(find.byKey(const Key('welcome-skip')), findsOneWidget);
    expect(find.byKey(const Key('welcome-start')), findsNothing);

    await tester.tap(find.byKey(const Key('welcome-next')));
    await _settle(tester);
    expect(find.text('الدوائر'), findsOneWidget);
    expect(find.byKey(const Key('welcome-skip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('welcome-next')));
    await _settle(tester);
    expect(find.text('السوق والمحادثات'), findsOneWidget);
    expect(find.byKey(const Key('welcome-skip')), findsNothing, reason: 'لا «تخطي» في الصفحة الأخيرة');
    expect(find.byKey(const Key('welcome-next')), findsNothing);

    await tester.tap(find.byKey(const Key('welcome-start')));
    await _settle(tester);
    expect(_tour, findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(WelcomeSeen.seen.value, isTrue);
    expect((await SharedPreferences.getInstance()).getBool(WelcomeSeen.prefsKey), isTrue);
    // الإقلاع التالي يقرأ «رآها»
    WelcomeSeen.debugSet(false);
    await WelcomeSeen.prime();
    expect(WelcomeSeen.seen.value, isTrue);
  });

  testWidgets('«تخطي» ends the tour and reveals the guest shell where browsing starts as a guest', (tester) async {
    iosNativeOverride = true;
    WelcomeSeen.debugSet(false);
    await _pump(tester);
    expect(_tour, findsOneWidget);
    expect(find.byKey(const Key('guest-shell')), findsNothing);
    await tester.tap(find.byKey(const Key('welcome-skip')));
    await _settle(tester);
    expect(_tour, findsNothing);
    expect(find.byKey(const Key('guest-shell')), findsOneWidget);
    expect(WelcomeSeen.seen.value, isTrue);
  });

  testWidgets('swiping moves between pages', (tester) async {
    WelcomeSeen.debugSet(false);
    await _pump(tester);
    // في العربية الصفحة التالية تأتي من اليسار فالسحب نحو اليمين (والاختبار بلا مندوبي الترجمة قد يكون LTR)
    final rtl = Directionality.of(tester.element(find.byType(PageView))) == TextDirection.rtl;
    await tester.fling(find.byType(PageView), Offset(rtl ? 400 : -400, 0), 1200);
    await _settle(tester);
    expect(find.text('الدوائر'), findsOneWidget);
  });

  testWidgets('not shown when already seen (the default before main primes it, and a stored flag)', (tester) async {
    await _pump(tester);
    expect(_tour, findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    SharedPreferences.setMockInitialValues({WelcomeSeen.prefsKey: true});
    await WelcomeSeen.prime();
    expect(WelcomeSeen.seen.value, isTrue);
  });

  testWidgets('not shown when the visitor arrived by a shared link', (tester) async {
    WelcomeSeen.debugSet(false);
    pendingLink = const PendingLink('user', 'sara');
    await _pump(tester);
    expect(_tour, findsNothing);
    expect(find.byKey(const Key('guest-bar')), findsOneWidget, reason: 'الوجهة مع شريط الدخول كما كانت');
    expect(WelcomeSeen.seen.value, isFalse, reason: 'تظهر في زيارة لاحقة بلا رابط');
  });

  testWidgets('no overflow on a 360x640 screen at the largest text scale (1.6), on every page', (tester) async {
    WelcomeSeen.debugSet(false);
    await _pump(tester, size: const Size(360, 640), textScale: 1.6);
    expect(_tour, findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final k in ['welcome-next', 'welcome-next']) {
      await tester.tap(find.byKey(Key(k)));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    }
    final start = find.byKey(const Key('welcome-start'));
    expect(start, findsOneWidget);
    expect(tester.getRect(start).bottom, lessThanOrEqualTo(640));
    expect(tester.getRect(find.byKey(const Key('welcome-dots'))).top, greaterThan(0));
  });

  testWidgets('reduced motion: pages appear complete and «التالي» jumps', (tester) async {
    WelcomeSeen.debugSet(false);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('welcome-next')));
    await tester.pump();
    expect(find.text('الدوائر'), findsOneWidget);
    expect(find.text('الخريطة'), findsNothing);
  });

  testWidgets('«جولة في التطبيق» in MySpace replays the tour and closing returns', (tester) async {
    await _pump(tester, home: const Scaffold(body: MySpacePage()), signedIn: true, size: const Size(420, 1400));
    await tester.scrollUntilVisible(find.byKey(const Key('welcome-replay')), 300);
    await tester.ensureVisible(find.byKey(const Key('welcome-replay')));
    await tester.pump();
    expect(find.text('جولة في التطبيق'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-replay')));
    await _settle(tester);
    expect(find.byType(WelcomeTourPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('welcome-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('welcome-start')));
    await _settle(tester);
    expect(find.byType(WelcomeTourPage), findsNothing);
    expect(find.byType(MySpacePage), findsOneWidget);
    // والرجوع من منتصفها يغلقها كذلك
    await tester.tap(find.byKey(const Key('welcome-replay')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('welcome-skip')));
    await _settle(tester);
    expect(find.byType(WelcomeTourPage), findsNothing);
  });
}
