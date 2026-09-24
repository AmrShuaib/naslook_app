// التصفّح بلا حساب: زر «تصفّح بدون حساب» في شاشة الدخول يفتح تبويبات الزائر (الخريطة، الأماكن، السوق، الفعاليات، حسابي)،
// وفي iOS الأصلي يبدأ التطبيق زائراً. مسارات النواة الخاصة بالحسابات (القصص، الحضور، الدبابيس، المحادثات…) لا تُطلب أبداً
// بلا جلسة (قائمة سماح بالمسارات العامة)، وتسجيل المشاهدة والنقرة لا يفتح دعوة الدخول، أما الطلب والمراسلة والتقييم
// والتذاكر والملف الشخصي فتدعو للدخول قبل أي طلب أو نموذج.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/core/require_account.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/dashboard_posts.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart';

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

/// المسارات العامة الوحيدة التي يجوز أن يطلبها زائر (قائمة سماح): أي مسار آخر يعني طلباً لمسار حساب أو نواة.
bool _publicRoute(Uri u) {
  final p = u.path;
  // ما يخص حساب الزائر حتى تحت البادئات العامة
  if (u.queryParameters['mine'] == '1' || p.endsWith('/mine') || p.startsWith('/biz/orders') || p.startsWith('/market/orders')) return false;
  return p == '/biz' || p.startsWith('/biz/') || p.startsWith('/mapposts') || p.startsWith('/market') || p.startsWith('/events') ||
      p == '/settings/public' || p == '/safety/words' || p.startsWith('/legal/');
}

const _bizId = 'biz-ikea';
Map<String, dynamic> _biz() => {
      'id': _bizId, 'name': 'IKEA', 'nameAr': 'إيكيا', 'category': 'brand', 'sector': 'أثاث', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '24 ساعة',
      'highlights': [], 'verified': false, 'official': false, 'followers': 3, 'rating': 4.5, 'ratingCount': 0, 'items': [], 'reviews': [], 'myOrders': [], 'ownerId': 'SA0000009',
      'posts': [{'id': 'bp1', 'bizId': _bizId, 'kind': 'news', 'title': 'افتتاح فرع جديد', 'body': 'تفاصيل', 'imageUrl': 'https://test.local/none.jpg', 'createdAt': '2026-09-10T08:00:00Z'}],
    };

Map<String, dynamic> _mapPost(String id, Map<String, dynamic> cta) => {
      'id': id, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': 'لحظة $id', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment', 'cta': cta,
      'lat': 21.5, 'lng': 39.1, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

class _Srv {
  final calls = <String>[];
  /// طلبات خارج قائمة السماح.
  final denied = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    final signed = req.headers.containsKey('x-token');
    if (!signed && !_publicRoute(req.url)) denied.add('$key${req.url.hasQuery ? '?${req.url.query}' : ''}');
    // النواة وكل ما يخص الحساب: 401 بلا جلسة
    if (!signed && (!_publicRoute(req.url) || req.method != 'GET')) return _json({'error': 'auth'}, 401);
    switch (key) {
      case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false});
      case 'GET /biz': return _json([_biz()]);
      case 'GET /biz/$_bizId': return _json(_biz());
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

Future<void> _dismissSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
  await _settle(tester);
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

  testWidgets('guests request only public routes: tabs, post viewer, call-to-action, profile and event tickets', (tester) async {
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
    expect(find.text('هذا يحتاج حساباً'), findsNothing, reason: 'القراءات الخلفية لا تزعج الزائر');

    // الفعاليات: لا «فعالياتي»، و«تذاكري» و«فعالية» يدعوان للدخول قبل أي طلب أو نموذج
    await _tab(tester, 'guest-tab-events');
    expect(find.text('فعالياتي'), findsNothing);
    await tester.tap(find.byKey(const Key('events-tickets')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    await _dismissSheet(tester);
    await tester.tap(find.byKey(const Key('events-create')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.text('فعالية جديدة'), findsNothing, reason: 'لا نموذج قبل الدخول');
    await _dismissSheet(tester);

    // عارض منشورات الخريطة: زر «راسلني» يدعو للدخول ولا يفتح المحادثة
    await _tab(tester, 'guest-tab-map');
    unawaited(PostViewerPage.open(tester.element(find.byType(MapPage)), [MapPost.fromJson(_mapPost('p1', {'type': 'chat', 'label': 'راسلني'}))]));
    await _settle(tester);
    await tester.tap(find.text('راسلني'));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.byType(ChatThreadPage), findsNothing);
    await _dismissSheet(tester);

    // الملف الشخصي من العارض: الاسم والصورة ودعوة للدخول، بلا إبلاغ ولا مراسلة ولا طلبات نواة
    await tester.tap(find.text('sara').first);
    await _settle(tester);
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(find.byKey(const Key('guest-profile-card')), findsOneWidget);
    expect(find.text('سجّل الدخول لرؤية الملف'), findsOneWidget);
    expect(find.byKey(const Key('profile-menu')), findsNothing);
    expect(find.text('مراسلة'), findsNothing);
    expect(find.byType(ErrorState), findsNothing, reason: 'لا «تعذر جلب البيانات» بلا مخرج');
    await tester.tap(find.byKey(const Key('guest-profile-login')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);

    expect(srv.denied, isEmpty, reason: 'مسارات خارج قائمة السماح طُلبت بلا جلسة');
  });

  testWidgets("a guest's call-to-action tap is tracked silently (no sign-in sheet over it)", (tester) async {
    iosNativeOverride = true;
    final srv = await _pump(tester);
    unawaited(PostViewerPage.open(tester.element(find.byType(MapPage)), [MapPost.fromJson(_mapPost('p2', {'type': 'biz', 'value': _bizId, 'label': 'زورونا'}))]));
    await _settle(tester);
    await tester.tap(find.text('زورونا'));
    await _settle(tester);
    expect(srv.calls, contains('POST /mapposts/p2/cta'));
    expect(find.byType(BusinessPage), findsOneWidget);
    expect(find.text('هذا يحتاج حساباً'), findsNothing, reason: 'رفض تسجيل النقرة (401) لا يفتح دعوة الدخول');
    expect(srv.denied, isEmpty);
  });

  testWidgets('guest on a circle page: review asks to sign in, no bookings, «على الخريطة» switches to the map tab', (tester) async {
    iosNativeOverride = true;
    final srv = await _pump(tester);
    await _tab(tester, 'guest-tab-places');
    await tester.tap(find.byType(BizRow).first);
    await _settle(tester);
    expect(find.byType(BusinessPage), findsOneWidget);
    expect(find.byKey(const Key('biz-page-bookings')), findsNothing);
    // زر الإبلاغ عن الخبر داخل البطاقة حتى حين تفشل الصورة
    expect(find.descendant(of: find.byType(PostCard), matching: find.byKey(const Key('bizpost-bp1-menu'))), findsOneWidget);
    await tester.ensureVisible(find.text('قيّم'));
    await tester.tap(find.text('قيّم'));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.text('قيّم إيكيا'), findsNothing, reason: 'لا ورقة تقييم قبل الدخول');
    await _dismissSheet(tester);
    await tester.tap(find.byTooltip('على الخريطة'));
    await _settle(tester);
    expect(find.byType(BusinessPage), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0, reason: 'واجهة الزائر تنتقل إلى الخريطة');
    // «الدوائر التجارية» المستقلة لا تعرض «نشاطي التجاري» ولا «حجوزاتي» للزائر
    unawaited(Navigator.of(tester.element(find.byType(MapPage))).push(MaterialPageRoute(builder: (_) => const BusinessesPage())));
    await _settle(tester);
    expect(find.byKey(const Key('biz-mine')), findsNothing);
    expect(find.byKey(const Key('biz-bookings')), findsNothing);
    expect(srv.denied, isEmpty);
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
