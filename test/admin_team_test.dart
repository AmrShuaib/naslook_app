// فريق العمل في لوحة الإدارة: الأقسام تظهر وفق صلاحيات الدور، صفحة الفريق تعرض الأعضاء وتضيف عضواً بالبحث،
// وتبويب الأدوار يعرض الأدوار المدمجة وينشئ دوراً مخصصاً بمصفوفة الصلاحيات.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/admin/admin_team.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

const _perms = [
  {'key': 'overview.view', 'group': 'overview', 'label': 'عرض النظرة العامة'}, {'key': 'users.view', 'group': 'users', 'label': 'عرض المستخدمين'}, {'key': 'reports.view', 'group': 'reports', 'label': 'عرض البلاغات'},
  {'key': 'reports.act', 'group': 'reports', 'label': 'معالجة البلاغات'}, {'key': 'finance.view', 'group': 'finance', 'label': 'عرض المالية'}, {'key': 'team.view', 'group': 'team', 'label': 'عرض الفريق'}, {'key': 'tasks.view', 'group': 'tasks', 'label': 'عرض مهامه'},
];

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  var permissions = <String>['*'];
  var members = <Map<String, dynamic>>[
    {'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'roleId': 'owner', 'roleName': 'المالك', 'level': 100, 'permissions': ['*'], 'title': 'المؤسس', 'department': 'الإدارة', 'managerId': null, 'managerName': '', 'active': true, 'mailbox': 'amr', 'legacy': true},
    {'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'roleId': 'manager', 'roleName': 'مدير قسم', 'level': 70, 'permissions': ['users.view'], 'title': 'مديرة العمليات', 'department': 'العمليات', 'managerId': 'SA0000001', 'managerName': 'amr', 'active': true, 'mailbox': 'sara', 'legacy': false},
  ];
  final roles = <Map<String, dynamic>>[
    {'id': 'owner', 'name': 'المالك', 'description': '', 'level': 100, 'permissions': ['*'], 'builtin': true, 'members': 1},
    {'id': 'manager', 'name': 'مدير قسم', 'description': 'يدير فريقه', 'level': 70, 'permissions': ['users.view', 'team.view'], 'builtin': true, 'members': 1},
    {'id': 'support', 'name': 'دعم العملاء', 'description': '', 'level': 40, 'permissions': ['users.view', 'reports.view', 'reports.act', 'team.view'], 'builtin': true, 'members': 0},
  ];

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': true, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'admins': 1, 'role': permissions.contains('*') ? 'owner' : 'support', 'roleName': permissions.contains('*') ? 'المالك' : 'دعم العملاء', 'level': permissions.contains('*') ? 100 : 40, 'permissions': permissions, 'title': 'المؤسس'});
      case 'GET /adminapi/team':
        return _json({'members': members, 'roles': roles, 'departments': ['الإدارة', 'العمليات'], 'me': {'roleId': 'owner', 'roleName': 'المالك', 'level': 100, 'permissions': permissions, 'scopeAll': permissions.contains('*'), 'scopeIds': ['SA0000001']}});
      case 'GET /adminapi/team/permissions':
        return _json(_perms);
      case 'GET /adminapi/team/tree':
        return _json({'roots': [{...members[0], 'depth': 0, 'reports': [{...members[1], 'depth': 1, 'reports': []}]}]});
      case 'GET /adminapi/team/search':
        final q = req.url.queryParameters['q'] ?? '';
        return _json(q.length >= 2 ? [{'id': 'SA0000004', 'nickname': 'nora', 'member': false}, {'id': 'SA0000002', 'nickname': 'sara', 'member': true}] : []);
      case 'POST /adminapi/team/members':
        final b = lastBody!;
        members = [...members, {'user': {'id': b['userId'], 'nickname': 'nora'}, 'roleId': b['roleId'], 'roleName': 'دعم العملاء', 'level': 40, 'permissions': [], 'title': b['title'], 'department': b['department'], 'managerId': b['managerId'], 'managerName': 'sara', 'active': true, 'mailbox': b['mailbox'], 'legacy': false}];
        return _json(members.last);
      case 'POST /adminapi/team/roles':
        final b = lastBody!;
        roles.add({'id': 'role-x', 'name': b['name'], 'description': b['description'], 'level': b['level'], 'permissions': b['permissions'], 'builtin': false, 'members': 0});
        return _json(roles.last);
      case 'GET /adminapi/overview':
        return _json({'users': {'total': 1, 'new7': 0, 'active7': 0, 'suspended': 0, 'admins': 1}, 'orders7': {'count': 0, 'revenue': 0, 'biz': 0}, 'circles': {'active': 0, 'inactive': 0, 'owned': 0}, 'claims': 0, 'reports': {'open': 0}, 'wallet': {'accounts': 0, 'balance': 0}, 'daily': [], 'server': {}});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<void> pump(WidgetTester tester, Widget home, {double width = 1100}) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = Size(width, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: MaterialApp(locale: const Locale('ar'), home: home),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('sections follow the role permissions: owner sees all, support sees only allowed ones', (tester) async {
    permissions = ['*'];
    await pump(tester, const AdminShell());
    for (final s in adminSections) {
      expect(find.byKey(Key('admin-nav-${s.$1}')), findsOneWidget, reason: 'المالك يرى ${s.$2}');
    }
    expect(find.byKey(const Key('admin-nav-team')), findsOneWidget);
    expect(find.text('المالك · المؤسس'), findsOneWidget);
    permissions = ['users.view', 'reports.view', 'reports.act', 'team.view', 'tasks.view'];
    await pump(tester, const AdminShell(initialSection: 4));
    expect(find.byKey(const Key('admin-nav-users')), findsOneWidget);
    expect(find.byKey(const Key('admin-nav-reports')), findsOneWidget);
    expect(find.byKey(const Key('admin-nav-team')), findsOneWidget);
    expect(find.byKey(const Key('admin-nav-finance')), findsNothing, reason: 'دعم العملاء لا يرى المالية');
    expect(find.byKey(const Key('admin-nav-settings')), findsNothing);
    expect(find.byKey(const Key('admin-nav-overview')), findsNothing);
    // القسم الابتدائي (المالية) غير مسموح → يُفتح أول قسم مسموح
    expect(find.text('المستخدمون'), findsWidgets);
  });

  testWidgets('team page lists members and adds one via search with role, manager and mailbox', (tester) async {
    permissions = ['*'];
    await pump(tester, const Scaffold(body: AdminTeamPage()));
    expect(find.byKey(const Key('team-member-SA0000002')), findsOneWidget);
    expect(find.text('sara'), findsOneWidget);
    expect(find.text('مدير قسم'), findsWidgets);
    expect(find.textContaining('المدير: amr'), findsOneWidget);
    expect(find.textContaining('فريق العمل · 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-search')), 'no');
    await settle(tester);
    expect(calls, contains('GET /adminapi/team/search'));
    expect(find.byKey(const Key('team-pick-SA0000004')), findsOneWidget);
    expect(find.text('عضو'), findsOneWidget, reason: 'sara تظهر كعضو موجود');
    await tester.tap(find.byKey(const Key('team-pick-SA0000004')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دعم العملاء · مستوى 40').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-title')), 'مسؤولة دعم');
    await tester.enterText(find.byKey(const Key('team-dept')), 'العمليات');
    await tester.tap(find.byKey(const Key('team-manager')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sara · مدير قسم').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-mailbox')), 'Nora');
    await tester.tap(find.byKey(const Key('team-save')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/team/members'));
    expect(lastBody, {'userId': 'SA0000004', 'roleId': 'support', 'title': 'مسؤولة دعم', 'department': 'العمليات', 'managerId': 'SA0000002', 'mailbox': 'nora'});
    expect(find.text('أُضيف nora بدور دعم العملاء'), findsOneWidget);
    expect(find.byKey(const Key('team-member-SA0000004')), findsOneWidget);
  });

  testWidgets('roles tab shows builtin roles and creates a custom role from the permission matrix', (tester) async {
    permissions = ['*'];
    await pump(tester, const Scaffold(body: AdminTeamPage()));
    await tester.tap(find.text('الأدوار'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('role-owner')), findsOneWidget);
    expect(find.byKey(const Key('role-support')), findsOneWidget);
    expect(find.text('مدمج'), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('role-new')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('role-name')), 'مراجع بلاغات');
    await tester.pump();
    await tester.tap(find.byKey(const Key('perm-reports.view')));
    await tester.tap(find.byKey(const Key('perm-reports.act')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('role-save')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/team/roles'));
    expect(lastBody!['name'], 'مراجع بلاغات');
    expect(lastBody!['level'], 30);
    expect((lastBody!['permissions'] as List).toSet(), {'reports.view', 'reports.act'});
    expect(find.text('أُنشئ الدور مراجع بلاغات'), findsOneWidget);
    expect(find.byKey(const Key('role-role-x')), findsOneWidget);
    // الهيكل
    await tester.tap(find.text('الهيكل'));
    await settle(tester);
    expect(find.byKey(const Key('tree-SA0000001')), findsOneWidget);
    expect(find.byKey(const Key('tree-SA0000002')), findsOneWidget);
  });
}
