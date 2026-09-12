import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/map/map_cluster.dart';
import 'package:naslook/pages/posts/my_posts_page.dart';
import 'package:naslook/pages/posts/overlay_canvas.dart';
import 'package:naslook/pages/posts/post_composer.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _p1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const _p2 = 'aaaaaaaa-0000-4000-8000-000000000002';

Map<String, dynamic> _post1({bool liked = false, int likes = 5}) => {
      'id': _p1, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'mediaUrl': null, 'caption': 'اليوم فقط', 'bg': '#BF3A1E',
      'overlays': [{'type': 'text', 'text': 'خصم 30٪', 'x': .5, 'y': .35, 'scale': 1.8, 'color': '#FFFFFF', 'bg': '#000000AA'}, {'type': 'sticker', 'text': '🔥', 'x': .8, 'y': .2, 'scale': 1.5}],
      'tag': 'offer', 'title': 'عرض القهوة', 'price': 1500, 'cta': {'type': 'whatsapp', 'value': '0501234567', 'label': 'اطلب عبر واتساب'}, 'lat': 21.55, 'lng': 39.16, 'placeName': 'الكورنيش',
      'status': 'active', 'views': 42, 'likes': likes, 'liked': liked, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
Map<String, dynamic> _post2() => {
      'id': _p2, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'kind': 'text', 'caption': 'منشور قديم مخفي', 'bg': '#37474F', 'overlays': [], 'tag': 'moment', 'lat': 21.5, 'lng': 39.2,
      'status': 'hidden', 'views': 3, 'likes': 0, 'liked': false, 'mine': true, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool liked = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /mapposts':
        return _json([_post1(), _post2()]);
      case 'GET /mapposts/mine':
        return _json([_post2()]);
      case 'POST /mapposts':
        final b = bodies[key]!;
        return _json({..._post2(), 'id': 'aaaaaaaa-0000-4000-8000-000000000009', 'status': 'active', ...b, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'mine': true});
      case 'POST /mapposts/$_p1/like':
        liked = !liked;
        return _json({'ok': true, 'liked': liked, 'likes': liked ? 6 : 5});
      case 'POST /mapposts/$_p1/view':
        return _json({'ok': true, 'views': 43});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {double height = 1400}) async {
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
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
  test('map item factory uses title, caption and author', () {
    final p = MapPost.fromJson(_post1());
    final item = MapItem.post(p);
    expect(item.kind, MapItemKind.post);
    expect(item.title, 'عرض القهوة');
    expect(item.subtitle, 'اليوم فقط');
    expect(item.author?.nickname, 'sara');
    expect(p.summary, 'عرض القهوة');
    expect(MapPost.fromJson(_post2()).summary, 'منشور قديم مخفي');
  });

  testWidgets('overlay canvas: dragging a layer updates its relative position', (tester) async {
    tester.view.physicalSize = const Size(300, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PostOverlay? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300, height: 500,
          child: OverlayCanvas(overlays: const [PostOverlay(type: 'text', text: 'نص')], editable: true, onChanged: (_, o) => changed = o),
        ),
      ),
    ));
    await tester.drag(find.text('نص'), const Offset(60, 100));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // مؤقّتات إيماءة النقر المزدوج
    expect(changed, isNotNull);
    // أول 20 بكسل من السحب تُستهلك عتبةَ الإيماءة، فالإزاحة الفعلية 40×80 من 300×500
    expect(changed!.x, closeTo(.633, .03));
    expect(changed!.y, closeTo(.66, .03));
  });

  testWidgets('composer publishes a text post with an overlay and pro fields', (tester) async {
    final srv = await _pump(tester, Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(onPressed: () => PostComposerPage.open(ctx, lat: 21.5, lng: 39.2, placeName: 'الكورنيش'), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('منشور جديد على الخريطة'), findsOneWidget);
    await tester.tap(find.text('نص على خلفية ملونة'));
    await _settle(tester);
    // الكتابة مباشرة على اللوحة بلا نافذة منفصلة، والنص بلا خلفية افتراضياً
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('inline-text')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('inline-text')), 'خصم 30٪');
    await tester.tap(find.text('تم'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('inline-text')), findsNothing);
    expect(find.text('خصم 30٪'), findsOneWidget);
    // لون الخلفية العامة من منتقي الألوان
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await _settle(tester);
    expect(find.text('لون الخلفية'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bg-#BF3A1E')));
    await tester.pump();
    await tester.tap(find.text('تم'));
    await _settle(tester);
    await tester.tap(find.text('خيارات احترافية'));
    await _settle(tester);
    await tester.ensureVisible(find.text('عرض'));
    await tester.tap(find.text('عرض'));
    await _settle(tester);
    await tester.ensureVisible(find.text('واتساب'));
    await tester.tap(find.text('واتساب'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'رقم واتساب مثل 05xxxxxxxx'), '0501234567');
    await tester.ensureVisible(find.text('نشر على الخريطة'));
    await tester.tap(find.text('نشر على الخريطة'));
    await _settle(tester);
    final body = srv.bodies['POST /mapposts']!;
    expect(body['kind'], 'text');
    expect(body['lat'], 21.5);
    expect((body['overlays'] as List).first['text'], 'خصم 30٪');
    expect((body['overlays'] as List).first['bg'], isNull, reason: 'النص بلا خلفية إلزامية');
    expect(body['bg'], '#BF3A1E');
    expect(body['tag'], 'offer');
    expect(body['cta']['type'], 'whatsapp');
    expect(body['cta']['value'], '0501234567');
    expect(body['ttlHours'], 24);
    expect(body['placeName'], 'الكورنيش');
    expect(find.text('open'), findsOneWidget, reason: 'يعود إلى الصفحة السابقة بعد النشر');
  });

  testWidgets('viewer renders overlays, tag, price and CTA, counts a view and toggles like', (tester) async {
    final srv = await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(_post1())]), height: 900);
    expect(find.text('خصم 30٪'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('عرض'), findsOneWidget);
    expect(find.text('عرض القهوة'), findsOneWidget);
    expect(find.text('اطلب عبر واتساب'), findsOneWidget);
    expect(srv.calls, contains('POST /mapposts/$_p1/view'));
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await _settle(tester);
    expect(srv.calls, contains('POST /mapposts/$_p1/like'));
    expect(find.text('6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // يوقف مؤقّت التقدّم التلقائي
  });

  testWidgets('my posts page lists my posts with status', (tester) async {
    await _pump(tester, const MyPostsPage());
    expect(find.text('منشور قديم مخفي'), findsOneWidget);
    expect(find.textContaining('مخفي'), findsWidgets);
    expect(find.textContaining('3 مشاهدة'), findsOneWidget);
    expect(find.text('منشور جديد'), findsOneWidget);
  });
}
