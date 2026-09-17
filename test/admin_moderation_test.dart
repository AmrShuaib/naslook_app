// إدارة الحسابات من داخل التطبيق (للمديرين): زر «إدارة الحساب» في ملف أي مستخدم يفتح ورقة بتعديل الملف والإيقاف
// والحذف النهائي بتأكيد الاسم؛ وصفحة «تدوينات جاهزة للنشر» تنشر مسودة بضغطة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/blog_drafts_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool admin = true, suspended = false, published = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> get _sara => {'id': 'SA0000002', 'nickname': 'sara', 'bio': 'أحب القهوة', 'suspended': suspended, 'flagNote': suspended ? 'إزعاج' : '', 'isAdmin': false, 'balance': 12000};

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.method != 'GET') { try { bodies[key] = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /profiles/SA0000002':
        return _json({'id': 'SA0000002', 'nickname': 'sara', 'bio': 'أحب القهوة', 'skills': [], 'hobbies': [], 'lookingFor': [], 'offerings': [], 'isPublic': true});
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': admin, 'admins': 1});
      case 'GET /adminapi/users/SA0000002':
        return _json({'user': _sara, 'points': 0, 'transactions': [], 'orders': {'count': 0, 'total': 0}, 'circles': [], 'reportsAbout': [], 'actions': []});
      case 'PATCH /adminapi/users/SA0000002':
        return _json({'ok': true, 'changes': bodies[key], 'user': _sara});
      case 'POST /adminapi/users/SA0000002/suspend':
        suspended = bodies[key]!['suspended'] == true;
        return _json({'ok': true, 'suspended': suspended});
      case 'DELETE /adminapi/users/SA0000002':
        if (bodies[key]?['confirm'] != 'sara') return _json({'error': 'confirm-mismatch', 'expected': 'sara'}, 400);
        return _json({'ok': true, 'id': 'SA0000002', 'nickname': 'sara', 'report': {'users': 1, 'profiles.id': 1, 'wallet_accounts.user_id': 1}});
      case 'GET /adminapi/blog':
        final status = req.url.queryParameters['status'];
        final draft = {'id': 'b-1', 'slug': 'circle-offers', 'kind': 'update', 'title': 'عروض الدوائر', 'summary': 'ملخص', 'status': 'draft', 'effectiveStatus': 'draft', 'url': 'https://naslife.app/blog/circle-offers', 'bodyLength': 900, 'tags': [], 'pinned': false, 'views': 0};
        final pub = {'id': 'b-0', 'slug': 'whats-next', 'kind': 'post', 'title': 'ما القادم', 'summary': '', 'status': 'published', 'effectiveStatus': 'published', 'url': 'https://naslife.app/blog/whats-next', 'bodyLength': 300, 'tags': [], 'pinned': false, 'views': 3, 'publishedAt': '2026-09-15T09:00:00Z'};
        final posts = status == 'draft' ? (published ? [] : [draft]) : [pub];
        return _json({'posts': posts, 'total': posts.length, 'counts': {'all': 2, 'draft': published ? 0 : 1, 'published': 1, 'scheduled': 0, 'views': 3}});
      case 'GET /adminapi/blog/b-1':
        return _json({'id': 'b-1', 'slug': 'circle-offers', 'kind': 'update', 'title': 'عروض الدوائر', 'summary': 'ملخص', 'body': 'نص التدوينة الكامل', 'status': 'draft', 'effectiveStatus': 'draft', 'url': 'https://naslife.app/blog/circle-offers', 'tags': [], 'pinned': false, 'views': 0});
      case 'POST /adminapi/blog/b-1/publish':
        published = true;
        return _json({'id': 'b-1', 'slug': 'circle-offers', 'kind': 'update', 'title': 'عروض الدوائر', 'status': 'published', 'effectiveStatus': 'published', 'url': 'https://naslife.app/blog/circle-offers', 'tags': [], 'pinned': false, 'views': 0, 'publishedAt': '2026-09-17T12:00:00Z'});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (key == 'GET /contacts') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

const _sara = Person(id: 'SA0000002', nickname: 'sara');

void main() {
  testWidgets('admin sees the manage button on a profile; edit sends only changed fields; suspend and unsuspend', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const UserProfilePage(person: _sara));
    expect(find.byKey(const Key('admin-user')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-user')));
    await tester.pumpAndSettle();
    expect(find.text('إدارة الحساب'), findsOneWidget);
    expect(find.textContaining('الرصيد 120 ر.س'), findsOneWidget);
    // تعديل الملف: النبذة فقط تغيّرت
    await tester.tap(find.byKey(const Key('ua-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ua-bio')), 'نبذة معدّلة');
    await tester.tap(find.byKey(const Key('ua-save')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PATCH /adminapi/users/SA0000002'], {'bio': 'نبذة معدّلة'});
    expect(find.text('حُفظت التعديلات'), findsOneWidget);
    // إيقاف بملاحظة ثم إعادة تفعيل
    await tester.tap(find.byKey(const Key('ua-suspend')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'إزعاج');
    await tester.tap(find.text('إيقاف'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/users/SA0000002/suspend'], {'suspended': true, 'note': 'إزعاج'});
    expect(find.text('إعادة تفعيل الحساب'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ua-suspend')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/users/SA0000002/suspend']!['suspended'], isFalse);
  });

  testWidgets('non-admin has no manage button', (tester) async {
    final srv = _Srv()..admin = false;
    await _pump(tester, srv, const UserProfilePage(person: _sara));
    expect(find.byKey(const Key('admin-user')), findsNothing);
  });

  testWidgets('permanent delete requires typing the nickname and then leaves the profile', (tester) async {
    final srv = _Srv();
    // صفحة الملف تُدفع فوق شاشة أساسية كما في التطبيق، حتى يُختبر الرجوع بعد الحذف
    await _pump(tester, srv, Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(key: const Key('open'), onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const UserProfilePage(person: _sara))), child: const Text('open'))))));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-user')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ua-delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ua-confirm')), 'wrong');
    await tester.tap(find.byKey(const Key('ua-delete-go')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب اسم المستخدم كما هو للتأكيد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ua-delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ua-confirm')), 'sara');
    await tester.tap(find.byKey(const Key('ua-delete-go')));
    await tester.pumpAndSettle();
    expect(srv.bodies['DELETE /adminapi/users/SA0000002'], {'confirm': 'sara'});
    expect(find.textContaining('حُذف حساب «sara» نهائياً'), findsOneWidget);
    expect(find.byType(UserProfilePage), findsNothing);
  });

  testWidgets('blog drafts page previews a draft and publishes it with one tap', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BlogDraftsPage());
    expect(find.text('عروض الدوائر'), findsOneWidget);
    await tester.tap(find.text('معاينة'));
    await tester.pumpAndSettle();
    expect(find.text('نص التدوينة الكامل'), findsOneWidget);
    await tester.tapAt(const Offset(300, 40)); // إغلاق المعاينة
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('draft-publish-circle-offers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('draft-publish-go')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /adminapi/blog/b-1/publish'));
    expect(find.textContaining('نُشرت «عروض الدوائر»'), findsOneWidget);
    expect(find.text('لا مسودات بانتظار النشر'), findsOneWidget);
    expect(find.text('ما القادم'), findsOneWidget);
  });
}
