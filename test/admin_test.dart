import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/admin/admin_users.dart';
import 'package:naslook/state/admin_providers.dart';
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
  bool setupRequired = false, isAdmin = true;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  List<Map<String, dynamic>> _daily() => [for (var i = 13; i >= 0; i--) {'day': DateTime.now().subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'users': i % 3, 'orders': i % 4, 'revenue': (i % 4) * 1000, 'topups': 500, 'purchases': 300, 'refunds': 0}];

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /adminapi/status':
        return _json({'hasAdmin': !setupRequired, 'setupRequired': setupRequired, 'isAdmin': !setupRequired && isAdmin, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'admins': setupRequired ? 0 : 1});
      case 'POST /adminapi/setup':
        if (bodies[key]!['code'] == 'NL-OK') { setupRequired = false; return _json({'ok': true}); }
        return _json({'error': 'bad-code'}, 400);
      case 'GET /adminapi/overview':
        return _json({'users': {'total': 120, 'new7': 9, 'suspended': 1, 'admins': 1}, 'orders7': {'count': 14, 'revenue': 250000}, 'circles': {'active': 22, 'inactive': 0, 'owned': 2, 'claims': 1}, 'reports': {'open': 2, 'available': true}, 'wallets': {'accounts': 40, 'balance': 990000}, 'daily': _daily(), 'server': {'node': 'v22', 'uptimeSec': 600, 'tables': ['users']}});
      case 'GET /adminapi/users':
        return _json([{'id': 'SA0000002', 'nickname': 'sara', 'isAdmin': false, 'suspended': false, 'balance': 25000, 'createdAt': DateTime.now().toUtc().toIso8601String()}]);
      case 'GET /adminapi/users/SA0000002':
        return _json({'user': {'id': 'SA0000002', 'nickname': 'sara', 'balance': 25000}, 'points': 1, 'transactions': [], 'orders': {'count': 0, 'total': 0}, 'circles': [], 'reportsAbout': [], 'actions': []});
      case 'POST /adminapi/users/SA0000002/credit':
        return _json({'ok': true, 'balance': 25000 + (bodies[key]!['amount'] as int)});
      case 'POST /adminapi/users/SA0000002/suspend':
        return _json({'ok': true, 'suspended': true});
      case 'GET /adminapi/settings':
        return _json({'testTopup': true, 'maxTopup': 10000000, 'announcement': '', 'maintenance': false, 'supportHandle': ''});
      case 'POST /adminapi/settings':
        return _json({...bodies[key]!});
      case 'GET /adminapi/admins':
        return _json([{'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'grantedBy': 'setup', 'since': DateTime.now().toUtc().toIso8601String()}]);
      case 'GET /adminapi/reports':
        return _json({'available': true, 'table': 'reports', 'items': [{'id': 'r1', 'reporterId': 'SA0000002', 'targetId': 'SA0000003', 'reason': 'إزعاج', 'reporter': {'id': 'SA0000002', 'nickname': 'sara'}, 'target': {'id': 'SA0000003', 'nickname': 'khalid'}}], 'blocks': 2});
      case 'POST /adminapi/reports/r1/action':
        return _json({'ok': true});
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {double width = 420}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('detectAdminMode recognises host, path, hash and query', () {
    expect(detectAdminMode(Uri.parse('https://admin.naslife.app/')), isTrue);
    expect(detectAdminMode(Uri.parse('https://naslife.app/admin')), isTrue);
    expect(detectAdminMode(Uri.parse('https://naslife.app/admin/users')), isTrue);
    expect(detectAdminMode(Uri.parse('https://naslife.app/#/admin')), isTrue);
    expect(detectAdminMode(Uri.parse('https://naslife.app/?admin=1')), isTrue);
    expect(detectAdminMode(Uri.parse('https://naslife.app/')), isFalse);
    expect(detectAdminMode(Uri.parse('https://naslife.app/administrator')), isFalse);
  });

  testWidgets('setup screen accepts the setup code and opens the panel', (tester) async {
    final srv = _Srv()..setupRequired = true;
    await _pump(tester, srv, const AdminShell());
    expect(find.text('لا يوجد مدير بعد'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'NL-WRONG');
    await tester.tap(find.text('تفعيل حسابي كمدير'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/setup']!['code'], 'NL-WRONG');
    await tester.enterText(find.byType(TextField), 'NL-OK');
    await tester.tap(find.text('تفعيل حسابي كمدير'));
    await tester.pumpAndSettle();
    expect(find.text('المستخدمون'), findsWidgets);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('non-admin sees the forbidden screen', (tester) async {
    final srv = _Srv()..isAdmin = false;
    await _pump(tester, srv, const AdminShell());
    expect(find.text('هذه اللوحة لمديري النظام'), findsOneWidget);
  });

  testWidgets('wide layout shows the side navigation and overview tiles', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const AdminShell(), width: 1200);
    expect(find.text('إدارة Naslife'), findsOneWidget);
    expect(find.text('سجل الإجراءات'), findsOneWidget);
    expect(find.text('طلبات ملكية'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('narrow layout uses a drawer to switch sections', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const AdminShell());
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('البلاغات'));
    await tester.pumpAndSettle();
    expect(find.text('بلاغ ضد khalid'), findsOneWidget);
    expect(srv.calls, contains('GET /adminapi/reports'));
  });

  testWidgets('crediting a user posts halalas and a note', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const AdminUserPage(id: 'SA0000002'));
    await tester.tap(find.text('إضافة رصيد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'المبلغ بالريال'), '٥٠');
    await tester.enterText(find.widgetWithText(TextField, 'ملاحظة تظهر للمستخدم'), 'هدية');
    await tester.tap(find.text('إضافة').last);
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /adminapi/users/SA0000002/credit']!;
    expect(b['amount'], 5000);
    expect(b['note'], 'هدية');
  });

  testWidgets('report action posts the decision with target', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const AdminShell(), width: 1200);
    await tester.tap(find.text('البلاغات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحذير'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'أول تحذير');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /adminapi/reports/r1/action']!;
    expect(b['action'], 'warn');
    expect(b['targetId'], 'SA0000003');
  });
}
