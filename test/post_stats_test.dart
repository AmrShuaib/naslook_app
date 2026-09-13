// إحصاءات المنشورات: ملخص منشوراتي وورقة الإحصاءات، وتتبّع زر الإجراء والمراسلة من العارض.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/posts/my_posts_page.dart';
import 'package:naslook/pages/posts/post_stats.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _p1 = 'aaaaaaaa-0000-4000-8000-000000000301';
const _p2 = 'aaaaaaaa-0000-4000-8000-000000000302';

Map<String, dynamic> _stats(int days, {int posts = 1}) => {
      'days': days, 'posts': posts, 'totals': {'views': 128, 'cta': 14, 'contacts': 6, 'likes': 19}, 'uniqueViews': 97,
      'hourly': [for (var i = 0; i < 24; i++) {'at': DateTime.utc(2026, 9, 13, i).toIso8601String(), 'views': i, 'cta': i % 4 == 0 ? 1 : 0, 'contacts': 0, 'likes': 0}],
      'daily': [for (var i = 0; i < days; i++) {'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}', 'views': 10 + i, 'cta': 1, 'contacts': 0, 'likes': 2}],
      'byPost': [{'id': _p1, 'title': 'عرض القهوة', 'kind': 'text', 'tag': 'offer', 'status': 'active', 'views': 90, 'cta': 9, 'contacts': 4, 'likes': 12}],
    };

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key + (req.url.query.isEmpty ? '' : '?${req.url.query}'));
    switch (key) {
      case 'GET /mapposts/mine':
        return _json([{'id': _p1, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'kind': 'text', 'caption': 'عرض القهوة', 'bg': '#BF3A1E', 'overlays': [], 'tag': 'offer', 'lat': 21.5, 'lng': 39.2, 'status': 'active', 'views': 90, 'likes': 12, 'liked': false, 'mine': true, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String()}]);
      case 'GET /mapposts/stats/mine':
        return _json(_stats(int.parse(req.url.queryParameters['days'] ?? '7')));
      case 'GET /mapposts/$_p1/stats':
        return _json({..._stats(int.parse(req.url.queryParameters['days'] ?? '7')), 'posts': 1, 'byPost': [], 'post': {'id': _p1, 'title': 'عرض القهوة'}, 'likesTotal': 12, 'viewsTotal': 90});
      case 'POST /mapposts/$_p2/view':
        return _json({'ok': true, 'views': 3});
      case 'POST /mapposts/$_p2/cta':
      case 'POST /mapposts/$_p2/contact':
        return _json({'ok': true});
      case 'GET /messages/SA0000002':
        return _json([]);
      case 'POST /messages/SA0000002/read':
        return _json({'ok': true});
      case 'GET /chat/meta':
      case 'GET /safety/words':
        return _json({'words': []});
      case 'GET /safety/mutes':
        return _json([]);
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 900);
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
    child: MaterialApp(locale: const Locale('ar'), home: home),
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
  test('PostStats parses totals and series with Riyadh hour labels', () {
    final s = PostStats.fromJson(_stats(7));
    expect(s.totals.views, 128);
    expect(s.uniqueViews, 97);
    expect(s.hourly.length, 24);
    expect(s.hourly.first.label, '3', reason: '00:00 UTC = 3 صباحاً بتوقيت الرياض');
    expect(s.daily.length, 7);
    expect(s.daily.first.label, '1/9');
    expect(s.byPost.single.t.cta, 9);
  });

  testWidgets('my posts page shows the 7-day summary and opens the stats sheet with both ranges', (tester) async {
    final srv = await _pump(tester, const MyPostsPage());
    await _settle(tester);
    expect(find.text('آخر 7 أيام'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('ضغطة إجراء'), findsOneWidget);
    await tester.tap(find.byTooltip('الإحصاءات'));
    await _settle(tester);
    expect(find.text('إحصاءات المنشور'), findsOneWidget);
    expect(find.text('آخر 24 ساعة'), findsOneWidget);
    expect(find.textContaining('نسبة التفاعل'), findsOneWidget);
    expect(find.byType(MiniBars), findsNWidgets(2));
    expect(srv.calls, contains('GET /mapposts/$_p1/stats?days=7'));
    await tester.tap(find.text('30 يوم'));
    await _settle(tester);
    expect(srv.calls, contains('GET /mapposts/$_p1/stats?days=30'));
    expect(find.text('آخر 30 يوماً'), findsOneWidget);
  });

  testWidgets("CTA and message taps on someone else's post are tracked", (tester) async {
    final post = MapPost.fromJson({
      'id': _p2, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': 'اطلب الآن', 'bg': '#0D47A1', 'overlays': [], 'tag': 'ad',
      'cta': {'type': 'link', 'value': 'https://example.com/x', 'label': 'زر الموقع'}, 'lat': 21.5, 'lng': 39.2, 'status': 'active', 'views': 2, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    final srv = await _pump(tester, PostViewerPage(posts: [post]));
    await tester.tap(find.text('زر الموقع'));
    await _settle(tester);
    expect(srv.calls, contains('POST /mapposts/$_p2/cta'));
    await tester.tap(find.text('مراسلة'));
    await _settle(tester);
    expect(srv.calls, contains('POST /mapposts/$_p2/contact'));
    await tester.pumpWidget(const SizedBox());
  });
}
