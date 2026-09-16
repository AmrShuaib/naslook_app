// مهام العمل في لوحة الإدارة: القائمة والعدّادات والفلاتر، إنشاء مهمة مسندة بأولوية وقائمة تحقق، تغيير الحالة السريع،
// وتفاصيل المهمة مع قائمة التحقق والتعليقات.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_tasks.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
const _t1 = 'aaaaaaaa-7000-4000-8000-000000000001', _t2 = 'aaaaaaaa-7000-4000-8000-000000000002';

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  final tasks = <Map<String, dynamic>>[
    {'id': _t1, 'title': 'مراجعة بلاغات اليوم', 'description': 'كل البلاغات', 'status': 'doing', 'priority': 'high', 'assignee': {'id': 'SA0000001', 'nickname': 'amr'}, 'creator': {'id': 'SA0000002', 'nickname': 'sara'}, 'department': 'العمليات', 'dueAt': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(), 'tags': ['بلاغات'], 'checklist': [{'text': 'قراءة', 'done': true}, {'text': 'الرد', 'done': false}], 'comments': 1, 'overdue': false, 'canEdit': true, 'canUpdateStatus': true, 'mine': true,
      'commentList': [{'id': 'c1', 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'text': 'ابدأ بالعاجل', 'createdAt': '2026-09-16T10:00:00Z'}], 'events': [{'id': 'e1', 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'created', 'data': {}, 'createdAt': '2026-09-16T09:00:00Z'}]},
    {'id': _t2, 'title': 'مقال الأسبوع', 'description': '', 'status': 'todo', 'priority': 'urgent', 'assignee': {'id': 'SA0000005', 'nickname': 'fahad'}, 'creator': {'id': 'SA0000001', 'nickname': 'amr'}, 'department': 'المحتوى', 'dueAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(), 'tags': [], 'checklist': [], 'comments': 0, 'overdue': true, 'canEdit': true, 'canUpdateStatus': true, 'mine': false, 'commentList': [], 'events': []},
  ];
  Map<String, int> counts(List<Map<String, dynamic>> l) { final c = {'todo': 0, 'doing': 0, 'review': 0, 'done': 0, 'blocked': 0, 'overdue': 0}; for (final t in l) { c[t['status'] as String] = (c[t['status'] as String] ?? 0) + 1; if (t['overdue'] == true) c['overdue'] = c['overdue']! + 1; } return c; }

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key + (req.url.query.isNotEmpty ? '?${req.url.query}' : ''));
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    if (key == 'GET /adminapi/tasks') {
      final view = req.url.queryParameters['view'] ?? 'mine';
      final st = req.url.queryParameters['status'] ?? '';
      var l = tasks.where((t) => view != 'mine' || (t['assignee'] as Map?)?['id'] == 'SA0000001').toList();
      if (st == 'open') {
        l = l.where((t) => t['status'] != 'done').toList();
      } else if (st.isNotEmpty) {
        l = l.where((t) => t['status'] == st).toList();
      }
      return _json({'items': l, 'counts': counts(l), 'view': view, 'assignees': [{'id': 'SA0000001', 'nickname': 'amr', 'roleName': 'المالك', 'title': ''}, {'id': 'SA0000005', 'nickname': 'fahad', 'roleName': 'محرر', 'title': 'محرر المدونة'}], 'canAssign': true, 'canManage': true});
    }
    if (key == 'GET /adminapi/tasks/summary') return _json({'members': [{'id': 'SA0000005', 'nickname': 'fahad', 'roleName': 'محرر', 'title': '', 'department': 'المحتوى', 'open': 1, 'overdue': 1, 'review': 0, 'done30': 3}]});
    if (key == 'POST /adminapi/tasks') {
      final b = lastBody!;
      tasks.insert(0, {'id': 'aaaaaaaa-7000-4000-8000-000000000009', 'title': b['title'], 'description': b['description'], 'status': 'todo', 'priority': b['priority'], 'assignee': b['assigneeId'] == null ? null : {'id': b['assigneeId'], 'nickname': 'fahad'}, 'creator': {'id': 'SA0000001', 'nickname': 'amr'}, 'department': b['department'], 'dueAt': b['dueAt'], 'tags': b['tags'], 'checklist': b['checklist'], 'comments': 0, 'overdue': false, 'canEdit': true, 'canUpdateStatus': true, 'mine': b['assigneeId'] == 'SA0000001', 'commentList': [], 'events': []});
      return _json(tasks.first);
    }
    if (key == 'GET /adminapi/tasks/$_t1') return _json(tasks.firstWhere((t) => t['id'] == _t1));
    if (key == 'PATCH /adminapi/tasks/$_t1') {
      final t = tasks.firstWhere((t) => t['id'] == _t1); final b = lastBody!;
      if (b['status'] != null) t['status'] = b['status'];
      if (b['checklist'] != null) t['checklist'] = b['checklist'];
      return _json(t);
    }
    if (key == 'POST /adminapi/tasks/$_t1/comments') {
      final t = tasks.firstWhere((t) => t['id'] == _t1);
      final c = <String, dynamic>{'id': 'c2', 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'text': lastBody!['text'], 'createdAt': DateTime.now().toUtc().toIso8601String()};
      t['commentList'] = <dynamic>[...(t['commentList'] as List), c];
      t['comments'] = (t['commentList'] as List).length;
      return _json(c);
    }
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<void> pump(WidgetTester tester) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: AdminTasksPage())),
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

  testWidgets('my tasks list with counters, filters and team view; quick status change', (tester) async {
    await pump(tester);
    expect(calls.first, 'GET /adminapi/tasks?view=mine&status=open');
    expect(find.byKey(const Key('task-$_t1')), findsOneWidget);
    expect(find.byKey(const Key('task-$_t2')), findsNothing, reason: 'مهامي فقط');
    expect(find.text('قيد التنفيذ'), findsWidgets);
    expect(find.text('1/2 ✓'), findsOneWidget);
    // فريقي: تظهر مهمة فهد المتأخرة
    await tester.tap(find.text('فريقي'));
    await settle(tester);
    expect(calls.last, 'GET /adminapi/tasks?view=team&status=open');
    expect(find.byKey(const Key('task-$_t2')), findsOneWidget);
    expect(find.textContaining('متأخرة'), findsWidgets);
    // فلتر الحالة
    await tester.tap(find.byKey(const Key('task-filter-todo')));
    await settle(tester);
    expect(calls.last, 'GET /adminapi/tasks?view=team&status=todo');
    expect(find.byKey(const Key('task-$_t1')), findsNothing);
    // تغيير سريع: ابدأ مهمة فهد
    await tester.tap(find.byKey(const Key('task-start-$_t2')));
    await settle(tester);
    expect(calls, contains('PATCH /adminapi/tasks/$_t2'));
    expect(lastBody, {'status': 'doing'});
    expect(find.text('المهمة الآن قيد التنفيذ'), findsOneWidget);
    // ملخص الفريق
    await tester.tap(find.text('عرض'));
    await settle(tester);
    expect(find.byKey(const Key('task-summary-SA0000005')), findsOneWidget);
    expect(find.text('1 متأخرة'), findsOneWidget);
  });

  testWidgets('create an assigned task with priority, checklist and tags', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), 'تجهيز تقرير الشهر');
    await tester.enterText(find.byKey(const Key('task-desc')), 'أرقام المبيعات والبلاغات');
    await tester.tap(find.byKey(const Key('task-assignee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fahad · محرر المدونة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-priority-urgent')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('task-checklist')), 'جمع الأرقام\n\nكتابة الملخص');
    await tester.enterText(find.byKey(const Key('task-tags')), 'تقارير، شهري');
    await tester.tap(find.byKey(const Key('task-save')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/tasks'));
    expect(lastBody!['title'], 'تجهيز تقرير الشهر');
    expect(lastBody!['assigneeId'], 'SA0000005');
    expect(lastBody!['priority'], 'urgent');
    expect(lastBody!['checklist'], [{'text': 'جمع الأرقام', 'done': false}, {'text': 'كتابة الملخص', 'done': false}]);
    expect(lastBody!['tags'], ['تقارير', 'شهري']);
    expect(find.text('أُسندت المهمة إلى fahad'), findsOneWidget);
  });

  testWidgets('task detail: toggle checklist, change status, add a comment', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('task-$_t1')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const Key('task-detail-title')), findsOneWidget);
    expect(find.text('ابدأ بالعاجل'), findsOneWidget);
    expect(find.textContaining('قائمة التحقق · 1/2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-check-1')));
    await settle(tester);
    expect(lastBody, {'checklist': [{'text': 'قراءة', 'done': true}, {'text': 'الرد', 'done': true}]});
    await tester.tap(find.byKey(const Key('task-status-review')));
    await settle(tester);
    expect(lastBody, {'status': 'review'});
    expect(find.text('المهمة الآن للمراجعة'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('task-comment-field')), 'أنجزت البنود');
    await tester.tap(find.byKey(const Key('task-comment-send')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/tasks/$_t1/comments'));
    expect(find.text('أنجزت البنود'), findsOneWidget);
    expect(find.text('التعليقات (2)'), findsOneWidget);
  });
}
