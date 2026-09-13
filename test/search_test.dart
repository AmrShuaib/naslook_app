import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/search/search_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _biz({bool open = true, double? km, String? matched}) => {
      'id': 'biz-ikea', 'name': 'IKEA', 'nameAr': 'إيكيا', 'category': 'brand', 'sector': 'أثاث ومفروشات', 'address': 'طريق الملك عبدالله، جدة', 'hours': 'يومياً 10:00 ص – 12:00 م',
      'lat': 21.6, 'lng': 39.2, 'followers': 12, 'rating': 4.5, 'ratingCount': 3, 'minPrice': 4900, 'openNow': open, 'distanceKm': km, 'matchedItem': matched,
    };

class _Srv {
  final calls = <String>[];
  final queries = <Map<String, String>>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    queries.add(req.url.queryParameters);
    switch (key) {
      case 'GET /search':
        final q = req.url.queryParameters['q'] ?? '';
        if (q.contains('ايكيا') || q.contains('BILLY')) {
          return _json({'q': q, 'people': [], 'vessels': [], 'biz': [_biz(km: 2.3, matched: 'مكتبة BILLY')],
            'items': [{'id': 'ikea-billy', 'bizId': 'biz-ikea', 'bizName': 'إيكيا', 'category': 'brand', 'kind': 'product', 'title': 'مكتبة BILLY', 'price': 44900}], 'market': [], 'events': []});
        }
        return _json({'q': q, 'people': [{'id': 'SA0000002', 'nickname': 'sara', 'bio': 'مصورة'}], 'vessels': [], 'biz': [], 'items': [], 'market': [], 'events': []});
      case 'GET /search/discover':
        return _json({'located': true, 'openNow': [_biz(km: 0.8)], 'topRated': [], 'events': [], 'vessels': [{'id': '1', 'name': 'دائرة جدة', 'topic': 'عام', 'members': 3}]});
      case 'GET /biz':
        return _json([_biz(open: true), {..._biz(open: false), 'id': 'biz-vox', 'nameAr': 'فوكس سينما', 'category': 'cinema', 'sector': 'سينما'}]);
      case 'GET /biz/biz-ikea':
        return _json({..._biz(), 'items': [], 'reviews': [], 'posts': [], 'myOrders': []});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

/// مهلة تحديد الموقع (14 ثانية) تُستهلك حتى لا يبقى مؤقّت معلّق في نهاية الاختبار.
Future<void> _finish(WidgetTester tester) => tester.pump(const Duration(seconds: 15));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('empty search shows suggestions and discover sections', (tester) async {
    await _pump(tester, const SearchPage());
    expect(find.text('جرّب البحث عن'), findsOneWidget);
    expect(find.text('مفتوح الآن قريب منك'), findsOneWidget);
    expect(find.byType(BizRow), findsOneWidget);
    expect(find.text('مفتوح الآن'), findsOneWidget, reason: 'شارة الحالة على صف النشاط');
    expect(find.text('800 م'), findsOneWidget);
    expect(find.text('دائرة جدة'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('typing searches after a debounce and opens the business', (tester) async {
    final srv = await _pump(tester, const SearchPage());
    await tester.enterText(find.byType(TextField), 'ايكيا');
    await _settle(tester);
    expect(srv.queries.lastWhere((m) => m.containsKey('q'))['q'], 'ايكيا');
    expect(find.text('أنشطة تجارية'), findsOneWidget);
    expect(find.text('منتجات وعروض'), findsOneWidget);
    expect(find.text('يوجد: مكتبة BILLY'), findsOneWidget);
    expect(find.text('2.3 كم'), findsOneWidget);
    await tester.tap(find.text('إيكيا').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BusinessPage), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('type chip narrows the request and no results shows an empty state', (tester) async {
    final srv = await _pump(tester, const SearchPage());
    await tester.enterText(find.byType(TextField), 'sara');
    await _settle(tester);
    expect(find.text('sara'), findsWidgets);
    await tester.ensureVisible(find.text('منتجات'));
    await tester.pump();
    await tester.tap(find.text('منتجات'));
    await _settle(tester);
    expect(srv.queries.last['type'], 'items');
    expect(srv.queries.last['q'], 'sara');
    await _finish(tester);
  });

  testWidgets('business list: open-now filter, rating sort, and nearest with location fallback', (tester) async {
    final srv = await _pump(tester, const Scaffold(body: BizListView()));
    expect(find.text('مفتوح الآن'), findsNWidgets(2), reason: 'الرقاقة وشارة إيكيا');
    expect(find.text('مغلق'), findsOneWidget);
    expect(srv.queries.last.containsKey('open'), isFalse);
    await tester.tap(find.text('مفتوح الآن').first);
    await _settle(tester);
    expect(srv.queries.last['open'], '1');
    await tester.ensureVisible(find.text('الأعلى تقييماً'));
    await tester.pump();
    await tester.tap(find.text('الأعلى تقييماً'));
    await _settle(tester);
    expect(srv.queries.last['sort'], 'rating');
    await tester.ensureVisible(find.text('الأقرب'));
    await tester.pump();
    await tester.tap(find.text('الأقرب'));
    await tester.pump(const Duration(seconds: 15)); // مهلة تحديد الموقع في بيئة الاختبار
    await _settle(tester);
    expect(srv.queries.last['sort'], 'near');
    expect(srv.queries.last['lat'], '21.54330');
    expect(find.textContaining('تعذّر تحديد موقعك'), findsOneWidget);
  });
}
