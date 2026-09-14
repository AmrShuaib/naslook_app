// قسم المدونة في لوحة الإدارة: القائمة بالعدّادات والمرشّحات، إنشاء منشور بالمحرر (التنسيق والمعاينة والنشر)،
// تعديل منشور وحفظه كمسودة، والحذف بعد التأكيد.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_blog.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _post(String id, String title, {String status = 'published', String kind = 'update', String body = '', int views = 0, bool pinned = false}) => {
      'id': id, 'slug': 'p-$id', 'kind': kind, 'title': title, 'summary': 'ملخص $title', 'body': body, 'status': status, 'effectiveStatus': status, 'pinned': pinned,
      'publishedAt': status == 'published' ? '2026-09-13T06:00:00Z' : null, 'createdAt': '2026-09-13T06:00:00Z', 'updatedAt': '2026-09-13T06:00:00Z', 'views': views, 'tags': ['وسم'], 'coverUrl': null,
      'url': 'https://naslife.app/blog/p-$id', 'bodyLength': body.length,
    };

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  String? lastQuery;

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    lastQuery = req.url.query;
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    if (key == 'GET /adminapi/blog') {
      final status = req.url.queryParameters['status'] ?? 'all';
      final posts = [_post('b1', 'ناس لايف يصل إلى الدمام', kind: 'news', views: 120, pinned: true), _post('b2', 'محرر منشورات جديد', body: '- بند', views: 40), _post('b3', 'مسودة قيد الكتابة', status: 'draft')];
      final list = status == 'all' ? posts : posts.where((p) => p['effectiveStatus'] == status).toList();
      return _json({'posts': list, 'total': list.length, 'counts': {'all': 3, 'draft': 1, 'published': 2, 'scheduled': 0, 'views': 160}});
    }
    if (key == 'GET /adminapi/blog/b2') return _json(_post('b2', 'محرر منشورات جديد', body: '- بند', views: 40));
    if (key == 'POST /adminapi/blog') return _json({..._post('b9', lastBody!['title'] as String, status: lastBody!['status'] as String, kind: lastBody!['kind'] as String, body: lastBody!['body'] as String)});
    if (key == 'PATCH /adminapi/blog/b2') return _json({..._post('b2', lastBody!['title'] as String, status: lastBody!['status'] as String, body: lastBody!['body'] as String)});
    if (key == 'DELETE /adminapi/blog/b1') return _json({'ok': true});
    if (key == 'POST /adminapi/blog/b1/pin') return _json(_post('b1', 'x', pinned: false));
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<void> pump(WidgetTester tester) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        socketProvider.overrideWithValue(null),
        appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
        notifyPollIntervalProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: AdminBlogPage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('list shows posts, counters and status filter requests the server', (tester) async {
    await pump(tester);
    expect(find.text('ناس لايف يصل إلى الدمام'), findsOneWidget);
    expect(find.text('مسودة قيد الكتابة'), findsOneWidget);
    expect(find.byKey(const Key('blog-stat-views')), findsOneWidget);
    expect(find.text('160'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget, reason: 'المثبّت يحمل دبوساً');
    await tester.tap(find.byKey(const Key('blog-stat-draft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(lastQuery, contains('status=draft'));
    expect(find.text('ناس لايف يصل إلى الدمام'), findsNothing);
    expect(find.text('مسودة قيد الكتابة'), findsOneWidget);
  });

  testWidgets('new post: format with the toolbar, preview, then publish now', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('blog-new')));
    await tester.pumpAndSettle();
    expect(find.text('منشور جديد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blog-kind-news')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('blog-title')), 'ساعات رمضان');
    await tester.enterText(find.byKey(const Key('blog-summary')), 'فروعنا في رمضان');
    await tester.enterText(find.byKey(const Key('blog-body')), 'جدة\nالدمام');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tool-bullet')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('blog-body'))).controller!.text, 'جدة\n- الدمام');
    await tester.tap(find.byKey(const Key('blog-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blog-preview-pane')), findsOneWidget);
    expect(find.text('ساعات رمضان'), findsOneWidget);
    expect(find.text('الدمام'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blog-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blog-publish-now')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /adminapi/blog'));
    expect(lastBody!['title'], 'ساعات رمضان');
    expect(lastBody!['kind'], 'news');
    expect(lastBody!['status'], 'published');
    expect(lastBody!['body'], 'جدة\n- الدمام');
    expect(lastBody!['summary'], 'فروعنا في رمضان');
    expect(find.byKey(const Key('blog-body')), findsNothing, reason: 'يُغلق المحرر ويعود للقائمة');
    expect(find.text('نُشر على المدونة'), findsOneWidget);
  });

  testWidgets('edit an existing post and save it as a draft; discard guard on close', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('blog-row-b2')));
    await tester.pumpAndSettle();
    expect(find.text('تعديل المنشور'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('blog-body'))).controller!.text, '- بند');
    await tester.enterText(find.byKey(const Key('blog-title')), 'محرر منشورات جديد (محدّث)');
    await tester.tap(find.byKey(const Key('blog-close')));
    await tester.pumpAndSettle();
    expect(find.text('تجاهل التغييرات؟'), findsOneWidget);
    await tester.tap(find.text('متابعة التحرير'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blog-save-draft')));
    await tester.pumpAndSettle();
    expect(calls, contains('PATCH /adminapi/blog/b2'));
    expect(lastBody!['status'], 'draft');
    expect(lastBody!['title'], 'محرر منشورات جديد (محدّث)');
    expect(find.text('حُفظ كمسودة'), findsOneWidget);
  });

  testWidgets('row menu: delete asks for confirmation then calls the server', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('blog-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف «ناس لايف يصل إلى الدمام»؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blog-delete-confirm')));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /adminapi/blog/b1'));
    expect(find.text('حُذف المنشور'), findsOneWidget);
  });
}
