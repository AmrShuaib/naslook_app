// صفحة المستخدم في لوحة الإدارة تعرض بياناته الشخصية كاملة: البريد وحالة تأكيده، حقول الحساب والملف بعناوين عربية،
// الحقول غير المعروفة باسمها، عبارة الاسترداد، الجلسات، وأعداد النشاط؛ وقائمة المستخدمين تعرض البريد.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_users.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

const _user = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null, 'bio': 'أحب القهوة', 'createdAt': '2026-09-10T08:00:00Z', 'lastSeen': null, 'deleted': false, 'isAdmin': false, 'suspended': false, 'flagNote': '', 'balance': 0, 'email': 'sara@example.com', 'emailVerified': true};

Future<http.Response> _handle(http.Request req) async {
  final key = '${req.method} ${req.url.path}';
  switch (key) {
    case 'GET /adminapi/users/SA0000002':
      return _json({
        'user': _user, 'points': 0, 'transactions': [], 'orders': {'count': 0, 'total': 0}, 'circles': [], 'reportsAbout': [], 'actions': [],
        'personal': {'id': 'SA0000002', 'nickname': 'sara', 'avatar_url': null, 'created_at': '2026-09-10T08:00:00Z', 'phone': '0555555555', 'city': 'جدة', 'loyalty_tier': 'gold'},
        'profile': {'user_id': 'SA0000002', 'bio': 'أحب القهوة', 'is_public': false, 'account_type': 'business', 'skills': ['قهوة', 'تحميص'], 'hobbies': [], 'looking_for': ['شركاء'], 'updated_at': '2026-09-12T10:00:00Z'},
        'emails': [{'email': 'sara@example.com', 'verified': true, 'verifiedAt': '2026-09-11T09:00:00Z', 'createdAt': '2026-09-10T08:05:00Z'}],
        'recovery': {'hasPhrase': true, 'source': 'register'},
        'sessions': {'count': 2, 'last': '2026-09-17T20:00:00Z', 'agents': ['Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)']},
        'counts': {'listings': 3, 'bizOrders': 1, 'contacts': 5, 'communityPosts': null},
      });
    case 'GET /adminapi/users':
      return _json([_user, {..._user, 'id': 'SA0000003', 'nickname': 'khalid', 'email': null, 'emailVerified': false}]);
    case 'GET /adminapi/status':
      return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': true, 'admins': 1});
  }
  return _json({'error': 'not-found'}, 404);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin user page shows email, every personal field, unknown columns, recovery, sessions and counts', (tester) async {
    await _pump(tester, const AdminUserPage(id: 'SA0000002'));
    expect(find.byKey(const Key('user-email')), findsOneWidget);
    expect(find.byKey(const Key('personal-email')), findsOneWidget);
    expect(find.text('مؤكَّد'), findsOneWidget);
    expect(find.byKey(const Key('personal-phone')), findsOneWidget);
    expect(find.text('0555555555'), findsOneWidget);
    expect(find.text('جدة'), findsOneWidget);
    expect(find.text('تجاري'), findsOneWidget); // account_type: business
    expect(find.text('لا'), findsOneWidget); // is_public: false
    expect(find.text('قهوة، تحميص'), findsOneWidget);
    expect(find.text('شركاء'), findsOneWidget);
    expect(find.text('loyalty_tier'), findsOneWidget); // حقل غير معروف يظهر باسمه
    expect(find.text('gold'), findsOneWidget);
    expect(find.textContaining('محفوظة'), findsOneWidget);
    expect(find.textContaining('2 · آخرها'), findsOneWidget);
    expect(find.text('آيفون'), findsOneWidget);
    expect(find.text('عروض في السوق 3'), findsOneWidget);
    expect(find.text('جهات اتصال 5'), findsOneWidget);
    expect(find.textContaining('منشورات مجتمع'), findsNothing); // null لا يُعرض
  });

  testWidgets('admin users list shows the login email next to the id', (tester) async {
    await _pump(tester, const Scaffold(body: AdminUsersPage()));
    expect(find.textContaining('sara@example.com'), findsOneWidget);
    expect(find.textContaining('SA0000003 · انضم'), findsOneWidget);
  });
}
