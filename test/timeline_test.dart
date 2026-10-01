// الخط الزمني: قائمة حيّة بكل مشاركات الخريطة الأحدث أولاً بتجميع زمني، تفتح العارض، وتتحدّث كل ٢٠ ثانية،
// وما يصل أثناء التمرير يظهر في كبسولة «جديد» بدل أن يقفز القائمة. والدخول إليه من زر في شريط الرئيسية.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/pages/posts/timeline_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _post(int i, {Duration ago = const Duration(minutes: 2), String kind = 'image', String caption = ''}) => {
      'id': 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}', 'user': {'id': 'SA000000$i', 'nickname': 'user$i'}, 'kind': kind, 'caption': caption,
      'mediaUrl': kind == 'text' ? null : 'https://test.local/chat/media/p$i.jpg', 'overlays': [], 'tag': 'moment', 'placeName': i == 1 ? 'الكورنيش' : null,
      'lat': 21.54, 'lng': 39.17, 'status': 'active', 'views': 0, 'likes': i == 1 ? 7 : 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

class _Srv {
  final calls = <String>[];
  List<Map<String, dynamic>> posts = [];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (key == 'GET /mapposts') return _json(posts);
    if (key == 'GET /row') return _json({'items': [], 'located': true});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /settings/public') return _json({'announcement': '', 'maintenance': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {Widget home = const TimelinePage(), _Srv? srv, Size size = const Size(420, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.54, 39.17);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

int _fetches(_Srv s) => s.calls.where((c) => c == 'GET /mapposts').length;

void main() {
  tearDown(() => ApiClient.onUnauthorized = null);

  testWidgets('lists every map post newest first with time groups, and a row opens the viewer at that post', (tester) async {
    final srv = _Srv()..posts = [_post(1), _post(2, ago: const Duration(hours: 5), kind: 'text', caption: 'مساء جدة'), _post(3, ago: const Duration(hours: 30))];
    await _pump(tester, srv: srv);
    expect(find.byKey(const Key('tl-group-الآن')), findsOneWidget);
    expect(find.byKey(const Key('tl-group-اليوم')), findsOneWidget);
    expect(find.byKey(const Key('tl-group-أمس')), findsOneWidget);
    expect(find.byKey(Key('tl-post-${_post(1)['id']}')), findsOneWidget);
    expect(find.text('مساء جدة'), findsOneWidget);
    expect(find.text('الكورنيش · قبل 2 د'), findsOneWidget);
    expect(find.text('مباشر · 3'), findsOneWidget);
    await tester.tap(find.text('مساء جدة'));
    await _settle(tester, 4);
    expect(find.byType(PostViewerPage), findsOneWidget);
    expect(tester.widget<PostViewerPage>(find.byType(PostViewerPage)).initial, 1);
  });

  testWidgets('refetches every 20 seconds; at the top new posts appear directly', (tester) async {
    final srv = _Srv()..posts = [_post(1)];
    await _pump(tester, srv: srv);
    expect(_fetches(srv), 1);
    srv.posts = [_post(9, caption: 'وصلت الآن'), _post(1)];
    await tester.pump(TimelinePage.refreshEvery + const Duration(seconds: 1));
    await _settle(tester);
    expect(_fetches(srv), 2);
    expect(find.text('وصلت الآن'), findsOneWidget);
    expect(find.byKey(const Key('tl-new')), findsNothing);
  });

  testWidgets('while scrolled down, new posts wait behind a «جديد» pill that scrolls to the top', (tester) async {
    final srv = _Srv()..posts = [for (var i = 1; i <= 25; i++) _post(i, ago: Duration(minutes: 20 + i))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -900));
    await _settle(tester, 2);
    srv.posts = [_post(99, caption: 'جديدة جداً'), ...srv.posts];
    await tester.pump(TimelinePage.refreshEvery + const Duration(seconds: 1));
    await _settle(tester);
    expect(find.byKey(const Key('tl-new')), findsOneWidget);
    expect(find.text('مشاركة جديدة'), findsOneWidget);
    expect(find.text('جديدة جداً'), findsNothing);
    await tester.tap(find.byKey(const Key('tl-new')));
    await _settle(tester, 3);
    expect(find.byKey(const Key('tl-new')), findsNothing);
    expect(find.text('جديدة جداً'), findsOneWidget);
  });

  testWidgets('the home top bar opens the timeline', (tester) async {
    final srv = _Srv()..posts = [_post(1)];
    await _pump(tester, home: const Scaffold(body: MapPage(home: true)), srv: srv, size: const Size(900, 1400));
    await tester.tap(find.byKey(const Key('home-timeline')));
    await _settle(tester, 4);
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(Key('tl-post-${_post(1)['id']}')), findsOneWidget);
  });
}
