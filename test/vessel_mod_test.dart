// حذف/إخفاء/إبلاغ منشورات الدوائر: صاحب المنشور يحذفه، مالك الدائرة ومشرفوها يزيلون منشورات الآخرين (تُخفى إن رفضت
// النواة الحذف)، العضو العادي يبلّغ فقط، والمنشورات المخفية تُصفّى من البث والدائرة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/circles/circle_detail_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _v = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _post(String id, String authorId, String nick, String text) => {
      'id': id, 'vesselId': _v, 'vesselName': 'دائرة الحي', 'type': 'text', 'content': text, 'caption': '', 'kind': 'discussion',
      'author': {'id': authorId, 'nickname': nick}, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'supports': 0, 'comments': 0, 'supported': false, 'unread': false,
    };

class _Srv {
  final String role;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final hidden = <String>{};
  final posts = [_post('p-mine', 'SA0000001', 'amr', 'منشوري أنا'), _post('p-sara', 'SA0000002', 'sara', 'منشور سارة'), _post('p-lina', 'SA0000006', 'lina', 'منشور لينا')];
  _Srv({this.role = 'owner'});
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /vessels/$_v':
        return _json({'id': _v, 'name': 'دائرة الحي', 'topic': 'الجيران', 'ownerId': 'SA0000009', 'isPublic': true, 'members': 5, 'role': role, 'joined': true, 'postsPage': posts});
      case 'GET /posts/hidden':
        return _json({'ids': hidden.toList()});
      case 'GET /vessels/feed':
        return _json(posts);
      case 'DELETE /posts/p-mine':
        posts.removeWhere((p) => p['id'] == 'p-mine');
        return _json({'ok': true});
      case 'POST /posts/p-sara/remove':
        hidden.add('p-sara');
        return _json({'ok': true, 'deleted': false, 'hidden': true});
      case 'POST /safety/report':
        return _json({'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<(ApiClient, _Srv)> _pump(WidgetTester tester, {String role = 'owner'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv(role: role);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: const MaterialApp(locale: Locale('ar'), home: CircleDetailPage(vesselId: _v)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return (api, srv);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('owner: deletes own post after confirmation and removes a member post (hidden when the core refuses)', (tester) async {
    final (_, srv) = await _pump(tester);
    expect(find.text('منشوري أنا'), findsOneWidget);
    expect(find.text('منشور سارة'), findsOneWidget);
    expect(srv.calls, contains('GET /posts/hidden'));
    // قائمة منشوري: حذف فقط
    await tester.tap(find.byKey(const Key('post-menu-p-mine')));
    await tester.pumpAndSettle();
    expect(find.text('حذف المنشور'), findsOneWidget);
    expect(find.text('إزالة من الدائرة'), findsNothing);
    expect(find.text('إبلاغ عن المنشور'), findsNothing);
    await tester.tap(find.text('حذف المنشور'));
    await tester.pumpAndSettle();
    expect(find.text('حذف المنشور؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-delete-confirm')));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /posts/p-mine'));
    expect(find.text('منشوري أنا'), findsNothing, reason: 'اختفى بعد إعادة التحميل');
    expect(find.text('حُذف المنشور'), findsOneWidget);
    // قائمة منشور عضو: إزالة + إبلاغ
    await tester.tap(find.byKey(const Key('post-menu-p-sara')));
    await tester.pumpAndSettle();
    expect(find.text('إزالة من الدائرة'), findsOneWidget);
    expect(find.text('إبلاغ عن المنشور'), findsOneWidget);
    await tester.tap(find.text('إزالة من الدائرة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'خارج موضوع الدائرة');
    await tester.tap(find.widgetWithText(FilledButton, 'إزالة'));
    await _settle(tester);
    expect(srv.calls, contains('POST /posts/p-sara/remove'));
    expect(srv.bodies['POST /posts/p-sara/remove'], {'vesselId': _v, 'reason': 'خارج موضوع الدائرة'});
    expect(find.text('أُخفي المنشور عن أعضاء الدائرة'), findsOneWidget);
    expect(find.text('منشور سارة'), findsNothing, reason: 'المخفي يُصفّى من الدائرة');
    expect(find.text('منشور لينا'), findsOneWidget);
  });

  testWidgets('member: can only report another member post as vessel-post', (tester) async {
    final (_, srv) = await _pump(tester, role: 'member');
    await tester.tap(find.byKey(const Key('post-menu-p-lina')));
    await tester.pumpAndSettle();
    expect(find.text('إزالة من الدائرة'), findsNothing);
    expect(find.text('حذف المنشور'), findsNothing);
    await tester.tap(find.text('إبلاغ عن المنشور'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'محتوى مسيء');
    await tester.tap(find.widgetWithText(FilledButton, 'إرسال البلاغ'));
    await _settle(tester);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'vessel-post', 'targetId': 'p-lina', 'reason': 'محتوى مسيء'});
    expect(find.text('وصل بلاغك وسنراجعه'), findsOneWidget);
    expect(find.text('منشور لينا'), findsOneWidget);
  });

  test('feed provider filters hidden circle posts', () async {
    final srv = _Srv()..hidden.add('p-sara');
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api), signedInProvider.overrideWithValue(true)]);
    addTearDown(container.dispose);
    final feed = await container.read(feedProvider.future);
    expect(feed.map((p) => p.id), ['p-mine', 'p-lina']);
    final detail = await container.read(vesselDetailProvider(_v).future);
    expect(detail.$2.map((p) => p.id), ['p-mine', 'p-lina']);
  });
}
