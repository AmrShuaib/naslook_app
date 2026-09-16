// البث العمودي «الآن حولك»: يطلب /mapposts/feed ويعرض اللحظة الأولى بمكانها ومسافتها، التمرير الرأسي ينتقل ويجلب الصفحة
// التالية بالمؤشر، الإعجاب يعمل، وبطاقة الرئيسية وشريط الأماكن الرائجة يفتحان البث (مصفّى بالمكان).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/home/home_page.dart';
import 'package:naslook/pages/posts/feed_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _ids = ['aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000003'];

Map<String, dynamic> _post(int i, {bool liked = false, int likes = 5}) => {
      'id': _ids[i], 'user': {'id': 'SA000000${i + 2}', 'nickname': ['sara', 'khalid', 'nora'][i]}, 'kind': 'text', 'mediaUrl': null, 'caption': 'لحظة رقم ${i + 1}', 'bg': '#0A6E78', 'overlays': [],
      'tag': 'moment', 'title': '', 'price': null, 'cta': null, 'lat': 21.55, 'lng': 39.16, 'placeName': null, 'status': 'active', 'views': 10 + i, 'likes': likes, 'liked': liked, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
      'distanceKm': [0.3, 2.5, 12.0][i], 'place': i == 0 ? {'key': 'biz:biz-cafe', 'name': 'مقهى البث', 'bizId': 'biz-cafe', 'category': 'cafe'} : i == 1 ? {'key': 'name:كورنيش جدة', 'name': 'كورنيش جدة'} : null,
    };

class _Srv {
  final calls = <String>[];
  final queries = <String, Map<String, String>>{};
  bool liked = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    queries[key] = req.url.queryParameters;
    switch (key) {
      case 'GET /mapposts/feed':
        final q = req.url.queryParameters;
        if (q['place'] == 'biz:biz-cafe') return _json({'items': [_post(0)], 'nextCursor': null, 'located': true});
        if (q['cursor'] == '2') return _json({'items': [_post(2)], 'nextCursor': null, 'located': true});
        return _json({'items': [_post(0), _post(1)], 'nextCursor': 2, 'located': true});
      case 'GET /mapposts/trending':
        return _json({'hours': 24, 'places': [{'key': 'biz:biz-cafe', 'name': 'مقهى البث', 'bizId': 'biz-cafe', 'category': 'cafe', 'lat': 21.55, 'lng': 39.16, 'distanceKm': 0.3, 'posts': 4, 'authors': 3}, {'key': 'name:كورنيش جدة', 'name': 'كورنيش جدة', 'lat': 21.6, 'lng': 39.1, 'distanceKm': 5.2, 'posts': 2, 'authors': 2}]});
      case 'GET /mapposts':
        return _json([_post(0), _post(1)]);
      case 'GET /contacts':
        return _json([{'id': 'SA0000002', 'nickname': 'sara'}, {'id': 'SA0000007', 'nickname': 'fahad'}]);
      case 'POST /mapposts/aaaaaaaa-0000-4000-8000-000000000001/like':
        liked = !liked;
        return _json({'ok': true, 'liked': liked, 'likes': liked ? 6 : 5});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (key.startsWith('POST /mapposts/') && key.endsWith('/view')) return _json({'ok': true, 'views': 99});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {double height = 900}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

void main() {
  testWidgets('feed loads around the user, shows place and distance, swipes vertically and pages with the cursor', (tester) async {
    final srv = await _pump(tester, const FeedPage());
    expect(srv.calls, contains('GET /mapposts/feed'));
    expect(srv.queries['GET /mapposts/feed']!['lat'], isNotNull, reason: 'يرسل موقع الأصل');
    expect(find.text('لحظة رقم 1'), findsOneWidget);
    expect(find.textContaining('مقهى البث'), findsOneWidget);
    expect(find.textContaining('300 م'), findsOneWidget);
    expect(find.text('الأقرب والأحدث أولاً'), findsOneWidget);
    expect(find.text('1 / 2+'), findsOneWidget);
    expect(srv.calls, contains('POST /mapposts/${_ids[0]}/view'));
    // إعجاب
    await tester.tap(find.byKey(Key('feed-like-${_ids[0]}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(srv.calls, contains('POST /mapposts/${_ids[0]}/like'));
    expect(find.text('6'), findsOneWidget);
    // تمرير رأسي إلى اللحظة الثانية: يقترب من النهاية فيجلب الصفحة التالية
    await tester.fling(find.byKey(const Key('feed-pages')), const Offset(0, -600), 1200);
    await tester.pumpAndSettle();
    expect(find.text('لحظة رقم 2'), findsOneWidget);
    expect(find.textContaining('كورنيش جدة'), findsOneWidget);
    expect(srv.queries['GET /mapposts/feed']!['cursor'], '2', reason: 'جلب الصفحة التالية بالمؤشر');
    await tester.fling(find.byKey(const Key('feed-pages')), const Offset(0, -600), 1200);
    await tester.pumpAndSettle();
    expect(find.text('لحظة رقم 3'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15)); // مهلة طلب موقع الجهاز في الخلفية
  });

  testWidgets('quick filters: type, radius and friends-only change the request and persist', (tester) async {
    final srv = await _pump(tester, const FeedPage());
    expect(srv.queries['GET /mapposts/feed']!['radiusKm'], '30');
    expect(srv.queries['GET /mapposts/feed']!.containsKey('tag'), isFalse);
    await tester.tap(find.byKey(const Key('feed-tag-offer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(srv.queries['GET /mapposts/feed']!['tag'], 'offer');
    await tester.tap(find.byKey(const Key('feed-radius-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(srv.queries['GET /mapposts/feed']!['radiusKm'], '2');
    await tester.ensureVisible(find.byKey(const Key('feed-friends')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('feed-friends')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(srv.calls, contains('GET /contacts'));
    expect(srv.queries['GET /mapposts/feed']!['authors'], 'SA0000002,SA0000007', reason: 'أصدقائي فقط يمرّر معرّفات جهات الاتصال');
    await tester.pump(const Duration(seconds: 15));
    // فتح البث من جديد يستعيد النطاق و«أصدقائي فقط» المحفوظين
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('feed_radius'), 2);
    expect(prefs.getBool('feed_friends'), isTrue);
  });

  testWidgets('home shows the feed card and trending places; a place opens the feed filtered by it', (tester) async {
    final srv = await _pump(tester, const Scaffold(body: HomePage()), height: 1600);
    expect(find.byKey(const Key('feed-open')), findsOneWidget);
    expect(find.text('الأماكن الرائجة اليوم'), findsOneWidget);
    expect(find.byKey(const Key('trend-biz:biz-cafe')), findsOneWidget);
    expect(find.text('4 لحظة · 3 شخص'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trend-biz:biz-cafe')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(srv.queries['GET /mapposts/feed']!['place'], 'biz:biz-cafe');
    expect(find.text('مقهى البث'), findsWidgets);
    expect(find.text('لحظات هذا المكان'), findsOneWidget);
    expect(find.text('لحظة رقم 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('feed-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feed-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('الآن حولك'), findsWidgets);
    expect(find.text('لحظة رقم 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
  });
}
