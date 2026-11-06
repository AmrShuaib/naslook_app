// بحث الزائر (البند 14 من تقرير النواقص): شريط البحث في خريطة الزائر يفتح البحث بلا دعوة دخول لأن الخادم يقبل /search
// و/search/discover بلا حساب. الزائر يكتب فيرى النتائج، ولا سجل بحث له ولا بحوث محفوظة (لا يُطلب /searches/saved)، و«نبّهني»
// وفتح الدائرة (مسارات النواة بجلسة) يدعوانه للدخول قبل أي طلب، والشخص يفتح ملفه ببطاقة الزائر.
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
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/search/search_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

Map<String, dynamic> _biz() => {
      'id': 'biz-brew92', 'name': 'brew92', 'nameAr': 'برو ٩٢', 'category': 'cafe', 'sector': 'قهوة مختصة', 'address': 'جدة', 'hours': 'يومياً 7:00 ص – 12:00 م',
      'lat': 21.6, 'lng': 39.2, 'followers': 12, 'rating': 4.5, 'ratingCount': 3, 'minPrice': 1800, 'openNow': true, 'distanceKm': null,
    };

/// المسارات التي يجوز لزائر طلبها (كما في guest_browse_test) ومعها البحث والاكتشاف.
bool _publicRoute(Uri u) {
  final p = u.path;
  if (u.queryParameters['mine'] == '1' || p.endsWith('/mine')) return false;
  return p == '/biz' || p.startsWith('/biz/') || p.startsWith('/mapposts') || p.startsWith('/market') || p.startsWith('/events') || p == '/settings/public' ||
      p == '/safety/words' || p.startsWith('/legal/') || p == '/offers/map' || p == '/offers/near' || p == '/row' || p == '/live/wait' || p == '/live/status' ||
      p == '/search' || p == '/search/discover' || (p.startsWith('/profiles/') && p.endsWith('/v2'));
}

class _Srv {
  final calls = <String>[];
  final denied = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    final signed = req.headers.containsKey('x-token');
    if (!signed && !_publicRoute(req.url)) denied.add(key);
    if (!signed && (!_publicRoute(req.url) || req.method != 'GET')) return _json({'error': 'auth'}, 401);
    switch (key) {
      case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false});
      case 'GET /biz': return _json([_biz()]);
      case 'GET /mapposts': return _json([]);
      case 'GET /market': return _json([]);
      case 'GET /events': return _json([]);
      case 'GET /row': return _json({'items': [], 'located': false});
      case 'GET /search/discover': return _json({'located': false, 'openNow': [], 'topRated': [], 'events': [], 'vessels': []});
      case 'GET /search':
        final q = req.url.queryParameters['q'] ?? '';
        return _json({'q': q, 'people': [{'id': 'SA0000002', 'nickname': 'sara', 'bio': 'مصورة قهوة'}], 'vessels': [{'id': 'v-coffee', 'name': 'محبو القهوة', 'topic': 'قهوة', 'members': 40, 'isPublic': true}],
          'biz': [_biz()], 'items': [], 'market': [], 'events': []});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
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

/// من خريطة الزائر إلى البحث ثم كتابة «قهوة» حتى تصل النتائج (مهلة الكتابة 300ms)
Future<void> _searchCoffee(WidgetTester tester) async {
  expect(find.byKey(const Key('guest-shell')), findsOneWidget);
  expect(find.byKey(const Key('home-search')), findsOneWidget, reason: 'خريطة الزائر تعرض شريط البحث');
  await tester.tap(find.byKey(const Key('home-search')));
  await _settle(tester);
  expect(find.byType(SearchPage), findsOneWidget);
  await tester.enterText(find.descendant(of: find.byType(SearchPage), matching: find.byType(TextField)), 'قهوة');
  await _settle(tester);
}

void main() {
  setUp(() {
    iosNativeOverride = true; // الزائر هو الافتراضي في iOS
    DeviceLocation.override = () async => null;
  });
  tearDown(() {
    iosNativeOverride = null;
    DeviceLocation.override = null;
    ApiClient.onUnauthorized = null;
    pendingLink = null;
  });

  testWidgets('a guest opens search from the map, types and sees results with no sign-in prompt and no history', (tester) async {
    final srv = await _pump(tester);
    await _searchCoffee(tester);
    expect(find.text('هذا يحتاج حساباً'), findsNothing, reason: 'البحث لا يحتاج حساباً');
    expect(srv.calls, contains('GET /search'));
    expect(find.byType(BizRow), findsOneWidget);
    expect(find.text('برو ٩٢'), findsWidgets);
    expect(find.text('sara'), findsOneWidget);
    expect(find.text('محبو القهوة'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-search')), findsOneWidget, reason: 'الزر ظاهر ويدعو للدخول عند الضغط');
    // الإرسال لا يحفظ سجلاً للزائر: بعد المسح لا «عمليات بحث سابقة»
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    await tester.tap(find.byTooltip('مسح'));
    await _settle(tester);
    expect(find.text('جرّب البحث عن'), findsOneWidget);
    expect(find.text('عمليات بحث سابقة'), findsNothing);
    expect(find.text('هذا يحتاج حساباً'), findsNothing);
    expect(srv.calls.where((c) => c.contains('/searches/saved')), isEmpty, reason: 'لا بحوث محفوظة للزائر');
    expect(srv.denied, isEmpty, reason: 'لا مسار حساب ولا نواة');
  });

  testWidgets('guest: «نبّهني» and a circle result ask to sign in before any request; a person opens the guest profile card', (tester) async {
    final srv = await _pump(tester);
    await _searchCoffee(tester);
    await tester.tap(find.byKey(const ValueKey('save-search')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.text('في أي مكان'), findsNothing, reason: 'لا ورقة نطاق قبل الدخول');
    Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
    await _settle(tester);
    await tester.tap(find.text('محبو القهوة'));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget, reason: 'صفحة الدائرة تحتاج جلسة');
    Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
    await _settle(tester);
    expect(find.byType(SearchPage), findsOneWidget, reason: 'بقي في البحث');
    await tester.tap(find.text('sara'));
    await _settle(tester);
    expect(find.byKey(const Key('guest-profile-card')), findsOneWidget);
    expect(srv.calls.where((c) => c.startsWith('POST /searches') || c.startsWith('GET /vessels')), isEmpty);
    expect(srv.denied, isEmpty);
  });
}
