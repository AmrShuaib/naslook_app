// «لحظات هنا» في صفحة الدائرة: تطلب لحظات المكان من GET /mapposts/feed بمفتاح biz:<id> بلا موقع المشاهد (فلا يقصّها النطاق)،
// تعرض مصغّرات تفتح عارض اللحظات الحالي على اللحظة المختارة، وتعمل للزائر، ولا تظهر حين لا لحظات أو عند الخطأ.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

Map<String, dynamic> _biz() => {
      'id': 'biz-cafe', 'name': 'Cafe', 'nameAr': 'مقهى الشاطئ', 'category': 'cafe', 'sector': 'قهوة', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '',
      'highlights': [], 'verified': false, 'official': false, 'followers': 0, 'items': [], 'reviews': [], 'myOrders': [], 'posts': [], 'ownerId': 'SA0000009',
    };

Map<String, dynamic> _post(String id, String text) => {
      'id': id, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': text, 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment',
      'lat': 21.5001, 'lng': 39.2001, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
      'place': {'key': 'biz:biz-cafe', 'name': 'مقهى الشاطئ', 'bizId': 'biz-cafe', 'category': 'cafe', 'logoUrl': null},
    };

class _Srv {
  final calls = <String>[];
  final feedQueries = <Map<String, String>>[];
  /// طلبات الزائر لمسارات خاصة بالحساب أو النواة.
  final privateCalls = <String>[];
  List<Map<String, dynamic>>? moments;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    final public = path.startsWith('/biz/') || path.startsWith('/mapposts') || path.startsWith('/moments/') || path == '/settings/public';
    if (!public) privateCalls.add(key);
    if (key == 'GET /biz/biz-cafe') return _json(_biz());
    if (key == 'GET /mapposts/feed') {
      feedQueries.add(req.url.queryParameters);
      if (moments == null) return _json({'error': 'boom'}, 500);
      return _json({'items': moments, 'nextCursor': null, 'located': false, 'radiusKm': 200});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, List<Map<String, dynamic>>? moments) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv()..moments = moments;
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: BusinessPage(id: 'biz-cafe')),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return srv;
}

void main() {
  testWidgets('a guest sees «لحظات هنا» for the circle and opens a moment in the viewer', (tester) async {
    final srv = await _pump(tester, [_post('11111111-1111-4111-8111-000000000001', 'زحمة حلوة اليوم'), _post('11111111-1111-4111-8111-000000000002', 'أفضل كورتادو')]);
    // لحظات المكان بمفتاح الدائرة، بلا موقع المشاهد حتى لا يقصّها نطاق المسافة
    expect(srv.feedQueries.single['place'], 'biz:biz-cafe');
    expect(srv.feedQueries.single.containsKey('lat'), isFalse);
    expect(srv.feedQueries.single.containsKey('lng'), isFalse);
    expect(find.byKey(const Key('place-moments')), findsOneWidget);
    expect(find.text('لحظات هنا'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('place-moments-count'))).data, '2 لحظة');
    expect(find.text('زحمة حلوة اليوم'), findsOneWidget);
    // اللحظة الثانية تفتح العارض عليها
    await tester.tap(find.byKey(const Key('place-moment-11111111-1111-4111-8111-000000000002')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(PostViewerPage), findsOneWidget);
    expect(tester.widget<PostViewerPage>(find.byType(PostViewerPage)).initial, 1);
    expect(tester.widget<PostViewerPage>(find.byType(PostViewerPage)).posts.length, 2);
    expect(srv.privateCalls, isEmpty, reason: 'الزائر لا يطلب مسارات الحساب');
    Navigator.of(tester.element(find.byType(PostViewerPage))).pop();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });

  testWidgets('no entry when the place has no moments or the feed fails', (tester) async {
    await _pump(tester, const []);
    expect(find.text('مقهى الشاطئ'), findsWidgets);
    expect(find.byKey(const Key('place-moments')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, null);
    expect(find.text('مقهى الشاطئ'), findsWidgets);
    expect(find.byKey(const Key('place-moments')), findsNothing);
  });
}
