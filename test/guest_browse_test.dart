// التصفّح بلا حساب: زر «تصفّح بدون حساب» في شاشة الدخول يفتح تبويبات الزائر (الخريطة، الأماكن، السوق، الفعاليات، حسابي)،
// وفي iOS الأصلي يبدأ التطبيق زائراً. مسارات النواة الخاصة بالحسابات (القصص، الحضور، الدبابيس، المحادثات…) لا تُطلب أبداً
// بلا جلسة، وتسجيل المشاهدة لا يفتح دعوة الدخول، أما الطلب من عرض في السوق فيدعو للدخول قبل أي طلب.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/core/require_account.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

const _lid = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> _listing() => {
      'id': _lid, 'seller': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'kind': 'product', 'category': 'food', 'subcategory': 'sweets', 'title': 'كيك عيد ميلاد', 'description': 'طازج', 'price': 22000,
      'imageUrl': null, 'images': [], 'status': 'active', 'lat': 21.5, 'lng': 39.1, 'mine': false, 'createdAt': '2026-09-10T08:00:00Z',
    };

/// مسارات النواة التي لا يجوز أن يطلبها زائر.
const _coreOnly = ['/stories', '/map/presence', '/map/pins', '/businesses', '/me/map-presence', '/vessels/mine', '/vessels/feed', '/posts/hidden', '/contacts', '/requests', '/chats', '/chat/mutes', '/mapposts/mine'];

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    final signed = req.headers.containsKey('x-token');
    // النواة وكل ما يخص الحساب: 401 بلا جلسة
    if (!signed && (_coreOnly.contains(path) || req.method != 'GET')) return _json({'error': 'auth'}, 401);
    switch (key) {
      case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false});
      case 'GET /biz': return _json([]);
      case 'GET /mapposts': return _json([]);
      case 'GET /market/home': return _json({'spotlight': [], 'popular': [_listing()], 'nearby': [], 'bazaars': [], 'categories': {'food': 1}, 'wantedOpen': 0, 'spotlightPricePerDay': 2000, 'commissionPct': 5});
      case 'GET /market': return _json([_listing()]);
      case 'GET /market/$_lid': return _json(_listing());
      case 'GET /market/$_lid/questions': return _json([]);
      case 'GET /market/$_lid/reviews': return _json([]);
      case 'GET /events': return _json([]);
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400); // عرض يتسع لسطر نسبة الخريطة بخط الاختبار
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: AuthGate()),
  ));
  await _settle(tester);
  return srv;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tab(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await _settle(tester);
}

void main() {
  setUp(() {
    DeviceLocation.override = () async => null;
  });
  tearDown(() {
    iosNativeOverride = null;
    DeviceLocation.override = null;
    LegalLinks.openOverride = null;
    ApiClient.onUnauthorized = null;
    pendingLink = null;
  });

  testWidgets('web: login screen offers browsing without an account, which opens the guest tabs', (tester) async {
    iosNativeOverride = false;
    await _pump(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('guest-shell')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('login-browse-guest')));
    expect(find.text('تصفّح بدون حساب'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-browse-guest')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-shell')), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(MapPage), findsOneWidget);
    // الزائر لا يرى الأشخاص ولا الدبابيس ولا زر إظهار موقعه
    expect(find.text('أشخاص'), findsNothing);
    expect(find.text('دبابيس'), findsNothing);
    expect(find.byTooltip('إظهار موقعي'), findsNothing);
    for (final k in ['guest-tab-map', 'guest-tab-places', 'guest-tab-market', 'guest-tab-events', 'guest-tab-account']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    await _tab(tester, 'guest-tab-places');
    expect(find.widgetWithText(AppBar, 'الأماكن'), findsOneWidget);
    await _tab(tester, 'guest-tab-market');
    expect(find.byType(MarketPage), findsOneWidget);
    expect(find.byType(ListingCard), findsWidgets);
    await _tab(tester, 'guest-tab-events');
    expect(find.byType(EventsPage), findsOneWidget);
  });

  testWidgets('native iOS starts as a guest; the account tab has sign-in, register and legal links', (tester) async {
    iosNativeOverride = true;
    final opened = <Uri>[];
    LegalLinks.openOverride = (u) async => opened.add(u);
    await _pump(tester);
    expect(find.byKey(const Key('guest-shell')), findsOneWidget, reason: 'أبل 5.1.1: لا تسجيل إجباري للتصفّح');
    expect(find.byType(LoginPage), findsNothing);
    await _tab(tester, 'guest-tab-account');
    expect(find.byKey(const Key('guest-account-login')), findsOneWidget);
    expect(find.byKey(const Key('guest-account-register')), findsOneWidget);
    await tester.tap(find.byKey(const Key('guest-privacy')));
    await tester.tap(find.byKey(const Key('guest-terms')));
    await tester.tap(find.byKey(const Key('guest-support')));
    await _settle(tester, 1);
    expect(opened.map((u) => u.path), ['/privacy', '/terms', '/support']);
    // «أنشئ حساباً» يفتح شاشة الدخول على التسجيل، ومنها يعود الزائر للتصفّح
    await tester.tap(find.byKey(const Key('guest-account-register')));
    await _settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('reg-email')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login-browse-guest')));
    await tester.tap(find.byKey(const Key('login-browse-guest')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-shell')), findsOneWidget);
  });

  testWidgets('guests never request core-only routes (stories, presence, pins, chats…)', (tester) async {
    iosNativeOverride = true;
    final srv = await _pump(tester);
    // الخريطة تطلب طبقاتها العامة فقط
    await tester.tap(find.byTooltip('تحديث'));
    await _settle(tester);
    for (final k in ['guest-tab-places', 'guest-tab-market', 'guest-tab-events', 'guest-tab-account', 'guest-tab-map']) {
      await _tab(tester, k);
    }
    expect(srv.calls, contains('GET /mapposts'));
    expect(srv.calls, contains('GET /market/home'));
    for (final p in _coreOnly) {
      expect(srv.calls.where((c) => c.endsWith(' $p')), isEmpty, reason: p);
    }
    expect(find.text('هذا يحتاج حساباً'), findsNothing, reason: 'القراءات الخلفية لا تزعج الزائر');
  });

  testWidgets('posting from the map asks a guest to sign in before the composer opens', (tester) async {
    iosNativeOverride = true;
    await _pump(tester);
    await tester.tap(find.byTooltip('منشور جديد'));
    await _settle(tester);
    expect(find.text('هذا يحتاج حساباً'), findsOneWidget);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
  });

  testWidgets('a guest opens a listing (view ping stays silent) and ordering shows the sign-in prompt', (tester) async {
    iosNativeOverride = true;
    final srv = await _pump(tester);
    await _tab(tester, 'guest-tab-market');
    await tester.tap(find.byType(ListingCard).first);
    await _settle(tester);
    expect(find.text('كيك عيد ميلاد'), findsWidgets);
    expect(srv.calls, contains('POST /market/$_lid/view'));
    expect(find.text('هذا يحتاج حساباً'), findsNothing, reason: 'تسجيل المشاهدة يُرفض بصمت للزائر');
    await tester.ensureVisible(find.byKey(const Key('order-btn')));
    await tester.tap(find.byKey(const Key('order-btn')));
    await _settle(tester);
    expect(find.text('هذا يحتاج حساباً'), findsOneWidget);
    expect(find.text('ملاحظة للبائع'), findsNothing, reason: 'لا نموذج قبل الدخول');
    expect(srv.calls, isNot(contains('POST /market/$_lid/order')));
    // الدخول يغلق صفحة العرض ويعرض شاشة الدخول
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('guest-login-sheet')));
    await _settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('order-btn')), findsNothing);
  });

  testWidgets('requireAccount prompts a guest even outside the guest shell', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => _SignedOut(ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((_) async => http.Response('{}', 404))), SessionStore()))],
      child: MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })),
    ));
    expect(requireAccount(ctx), isFalse);
    await _settle(tester, 2);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
  });
}
