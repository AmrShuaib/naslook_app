// البريد الوارد في لوحة الإدارة: الصناديق والمجلدات، فتح محادثة والرد منها بعنوان الصندوق، إنشاء رسالة جديدة،
// وإعدادات الاستقبال (المزوّد والسر ورابط الـ Webhook).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_inbox.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/state/admin_providers.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
const _th = 'bbbbbbbb-8000-4000-8000-000000000001', _th2 = 'bbbbbbbb-8000-4000-8000-000000000002';

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  var received = 2;
  final threads = <Map<String, dynamic>>[
    {'id': _th, 'mailbox': 'admin', 'subject': 'استفسار عن الاشتراك', 'snippet': 'هل يوجد اشتراك سنوي؟', 'counterpart': 'ahmed@client.com', 'counterpartName': 'Ahmed Client', 'participants': [], 'lastAt': '2026-09-16T10:00:00Z', 'lastDirection': 'in', 'unread': 1, 'messages': 1, 'archived': false, 'starred': false, 'assignedTo': null, 'assignedName': '', 'status': 'open', 'snoozeUntil': null, 'snoozed': false, 'tags': ['اشتراك'],
      'messageList': <dynamic>[{'id': 'm1', 'direction': 'in', 'from': {'email': 'ahmed@client.com', 'name': 'Ahmed Client'}, 'to': [{'email': 'admin@naslife.app', 'name': ''}], 'cc': [], 'subject': 'استفسار عن الاشتراك', 'text': 'هل يوجد اشتراك سنوي للدوائر التجارية؟', 'html': null, 'attachments': [], 'read': false, 'sentBy': null, 'sentByName': '', 'createdAt': '2026-09-16T10:00:00Z'}]},
    {'id': _th2, 'mailbox': 'amr', 'subject': 'عرض شراكة', 'snippet': 'نود عرض شراكة', 'counterpart': 'lina@partner.com', 'counterpartName': 'Lina', 'participants': [], 'lastAt': '2026-09-16T09:00:00Z', 'lastDirection': 'out', 'unread': 0, 'messages': 2, 'archived': false, 'starred': true, 'assignedTo': 'SA0000002', 'assignedName': 'sara', 'status': 'waiting', 'snoozeUntil': null, 'snoozed': false, 'tags': [], 'messageList': <dynamic>[]},
  ];
  final templates = <Map<String, dynamic>>[{'id': 'cccccccc-8000-4000-8000-000000000001', 'title': 'ترحيب', 'body': 'أهلاً {{name}}، شكراً لتواصلك.', 'shared': true, 'ownerId': 'SA0000001'}];
  var unread = 1;
  Map<String, dynamic> settings = {'provider': 'generic', 'hasSecret': false, 'token': 'tok_1', 'resendUrl': 'https://naslife.app/inbox/webhook/resend', 'genericUrl': 'https://naslife.app/inbox/webhook/generic?token=tok_1', 'domain': 'naslife.app', 'shared': 'admin@naslife.app', 'received': 2, 'rejected': 0, 'lastReceivedAt': '2026-09-16T10:00:00Z'};

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key + (req.url.query.isNotEmpty ? '?${req.url.query}' : ''));
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /adminapi/inbox/mailboxes':
        return _json({'mailboxes': [{'alias': 'amr', 'address': 'amr@naslife.app', 'kind': 'own', 'label': 'صندوقي', 'ownerId': 'SA0000001', 'unread': 0}, {'alias': 'admin', 'address': 'admin@naslife.app', 'kind': 'shared', 'label': 'الصندوق المشترك', 'ownerId': null, 'unread': unread}], 'totalUnread': unread, 'domain': 'naslife.app', 'domainVerified': true, 'canReply': true, 'canManage': true, 'myMailbox': 'amr', 'receiving': {'provider': 'generic', 'configured': true, 'lastReceivedAt': '2026-09-16T10:00:00Z', 'received': received}});
      case 'GET /adminapi/inbox':
        final mb = req.url.queryParameters['mailbox'], folder = req.url.queryParameters['folder'];
        var l = threads.where((t) => t['mailbox'] == mb).toList();
        if (folder == 'starred') l = l.where((t) => t['starred'] == true).toList();
        return _json({'threads': [for (final t in l) {...t}..remove('messageList')], 'mailbox': mb, 'folder': folder});
      case 'GET /adminapi/inbox/threads/$_th':
        return _json({...threads[0], 'address': 'admin@naslife.app'});
      case 'PATCH /adminapi/inbox/threads/$_th':
        threads[0] = {...threads[0], ...lastBody!, if (lastBody!['snoozeUntil'] != null) 'snoozed': true};
        return _json(threads[0]);
      case 'POST /adminapi/inbox/threads/$_th/notes':
        (threads[0]['messageList'] as List).add({'id': 'n1', 'direction': 'note', 'from': {'email': '', 'name': 'amr'}, 'to': [], 'cc': [], 'subject': '', 'text': lastBody!['text'], 'html': null, 'attachments': [], 'read': true, 'sentBy': 'SA0000001', 'sentByName': 'amr', 'createdAt': '2026-09-16T11:30:00Z'});
        return _json({'id': 'n1', 'direction': 'note', 'text': lastBody!['text'], 'createdAt': '2026-09-16T11:30:00Z'});
      case 'GET /adminapi/inbox/templates':
        return _json({'templates': templates});
      case 'POST /adminapi/inbox/templates':
        templates.add({'id': 'cccccccc-8000-4000-8000-000000000002', 'title': lastBody!['title'], 'body': lastBody!['body'], 'shared': lastBody!['shared'], 'ownerId': 'SA0000001'});
        return _json(templates.last);
      case 'DELETE /adminapi/inbox/templates/cccccccc-8000-4000-8000-000000000002':
        templates.removeWhere((t) => t['id'] == 'cccccccc-8000-4000-8000-000000000002');
        return _json({'ok': true});
      case 'POST /adminapi/inbox/templates/cccccccc-8000-4000-8000-000000000001/render':
        return _json({'text': 'أهلاً Ahmed Client، شكراً لتواصلك.'});
      case 'POST /adminapi/inbox/threads/$_th/reply':
        (threads[0]['messageList'] as List).add({'id': 'm9', 'direction': 'out', 'from': {'email': 'admin@naslife.app', 'name': 'ناس لايف'}, 'to': [{'email': 'ahmed@client.com', 'name': ''}], 'cc': [], 'subject': 'Re: استفسار عن الاشتراك', 'text': lastBody!['text'], 'html': null, 'attachments': [], 'read': true, 'sentBy': 'SA0000001', 'sentByName': 'amr', 'createdAt': '2026-09-16T11:00:00Z'});
        threads[0]['status'] = 'waiting';
        return _json({'ok': true, 'threadId': _th, 'messageId': 'm9'});
      case 'POST /adminapi/inbox/compose':
        return _json({'ok': true, 'threadId': 'x'});
      case 'GET /adminapi/inbox/settings':
        return _json(settings);
      case 'PUT /adminapi/inbox/settings':
        settings = {...settings, if (lastBody!['provider'] != null) 'provider': lastBody!['provider'], if (lastBody!['webhookSecret'] != null) 'hasSecret': true};
        return _json(settings);
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': true, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'admins': 1, 'role': 'owner', 'roleName': 'المالك', 'level': 100, 'permissions': ['*'], 'title': 'المؤسس', 'department': 'الإدارة'});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Future<void> pump(WidgetTester tester, {Widget home = const Scaffold(body: AdminInboxPage())}) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null), inboxPollIntervalProvider.overrideWithValue(null)],
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

  testWidgets('mailboxes, folders and thread list; open a thread and reply from the mailbox address', (tester) async {
    await pump(tester);
    expect(calls, contains('GET /adminapi/inbox?mailbox=amr&folder=inbox'));
    expect(find.byKey(const Key('inbox-thread-$_th2')), findsOneWidget);
    expect(find.text('sara'), findsOneWidget, reason: 'شارة الإسناد');
    // الصندوق المشترك
    await tester.tap(find.byKey(const Key('inbox-mailbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('admin@naslife.app').last);
    await settle(tester);
    expect(calls, contains('GET /adminapi/inbox?mailbox=admin&folder=inbox'));
    expect(find.byKey(const Key('inbox-thread-$_th')), findsOneWidget);
    expect(find.text('Ahmed Client'), findsOneWidget);
    // المجلد المميز فارغ للمشترك
    await tester.tap(find.byKey(const Key('inbox-folder-starred')));
    await settle(tester);
    expect(calls, contains('GET /adminapi/inbox?mailbox=admin&folder=starred'));
    expect(find.text('لا رسائل'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-folder-inbox')));
    await settle(tester);
    // فتح المحادثة والرد
    await tester.tap(find.byKey(const Key('inbox-thread-$_th')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const Key('thread-subject')), findsOneWidget);
    expect(find.textContaining('عبر admin@naslife.app'), findsOneWidget);
    expect(find.byKey(const Key('msg-m1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('thread-reply-field')), 'نعم، يوجد اشتراك سنوي بخصم 20٪.');
    await tester.tap(find.byKey(const Key('thread-reply-send')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/inbox/threads/$_th/reply'));
    expect(lastBody, {'text': 'نعم، يوجد اشتراك سنوي بخصم 20٪.'});
    expect(find.byKey(const Key('msg-m9')), findsOneWidget);
    expect(find.text('أُرسل الرد'), findsOneWidget);
    // تمييز
    await tester.tap(find.byKey(const Key('thread-star')));
    await settle(tester);
    expect(lastBody, {'starred': true});
  });

  testWidgets('status chips, snooze, tags, internal note and canned reply inside a thread', (tester) async {
    threads[0] = {...threads[0], 'status': 'open', 'snoozeUntil': null, 'snoozed': false, 'tags': ['اشتراك']};
    await pump(tester);
    await tester.tap(find.byKey(const Key('inbox-mailbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('admin@naslife.app').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('inbox-thread-$_th')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('#اشتراك'), findsAtLeastNWidgets(1), reason: 'الوسوم تظهر في رأس المحادثة');
    // الحالة
    await tester.tap(find.byKey(const Key('thread-status-waiting')));
    await settle(tester);
    expect(calls, contains('PATCH /adminapi/inbox/threads/$_th'));
    expect(lastBody, {'status': 'waiting'});
    expect(find.text('المحادثة الآن بانتظار العميل'), findsOneWidget);
    // تأجيل
    await tester.tap(find.byKey(const Key('thread-snooze')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snooze-hours')));
    await settle(tester);
    expect(lastBody!.keys.toList(), ['snoozeUntil']);
    expect(DateTime.parse(lastBody!['snoozeUntil'] as String).isAfter(DateTime.now().toUtc().add(const Duration(hours: 2))), isTrue);
    expect(find.text('أُجّلت المحادثة'), findsOneWidget);
    expect(find.textContaining('مؤجلة حتى'), findsOneWidget);
    // الوسوم
    await tester.tap(find.byKey(const Key('thread-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'اشتراك، vip');
    await tester.tap(find.text('حفظ'));
    await settle(tester);
    expect(lastBody, {'tags': ['اشتراك', 'vip']});
    expect(find.text('#vip'), findsAtLeastNWidgets(1));
    // ملاحظة داخلية
    await tester.tap(find.byKey(const Key('thread-mode-note')));
    await tester.pump();
    expect(find.byKey(const Key('thread-template')), findsNothing, reason: 'القوالب للرد فقط');
    await tester.enterText(find.byKey(const Key('thread-reply-field')), 'العميل مهم، راجعوا العرض');
    await tester.tap(find.byKey(const Key('thread-reply-send')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/inbox/threads/$_th/notes'));
    expect(lastBody, {'text': 'العميل مهم، راجعوا العرض'});
    expect(find.byKey(const Key('msg-n1')), findsOneWidget);
    expect(find.textContaining('ملاحظة داخلية · amr'), findsOneWidget);
    expect(calls.where((c) => c.contains('/reply')), isEmpty, reason: 'الملاحظة لا تُرسل للعميل');
    // رد جاهز
    await tester.tap(find.byKey(const Key('thread-mode-reply')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('thread-template')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.byKey(const Key('template-cccccccc-8000-4000-8000-000000000001')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/inbox/templates/cccccccc-8000-4000-8000-000000000001/render'));
    expect(lastBody, {'threadId': _th});
    expect(tester.widget<TextField>(find.byKey(const Key('thread-reply-field'))).controller!.text, 'أهلاً Ahmed Client، شكراً لتواصلك.');
  });

  testWidgets('templates sheet: create a shared template and delete it', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('inbox-templates')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const Key('template-cccccccc-8000-4000-8000-000000000001')), findsOneWidget);
    await tester.tap(find.byKey(const Key('template-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('template-title')), 'تم الاستلام');
    await tester.enterText(find.byKey(const Key('template-body')), 'وصل طلبك يا {{name}} وسنرد خلال يوم عمل.');
    await tester.tap(find.byKey(const Key('template-save')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/inbox/templates'));
    expect(lastBody, {'title': 'تم الاستلام', 'body': 'وصل طلبك يا {{name}} وسنرد خلال يوم عمل.', 'shared': true});
    expect(find.byKey(const Key('template-cccccccc-8000-4000-8000-000000000002')), findsOneWidget);
    await tester.tap(find.byKey(const Key('template-delete-cccccccc-8000-4000-8000-000000000002')));
    await settle(tester);
    expect(calls, contains('DELETE /adminapi/inbox/templates/cccccccc-8000-4000-8000-000000000002'));
    expect(find.byKey(const Key('template-cccccccc-8000-4000-8000-000000000002')), findsNothing);
  });

  testWidgets('admin shell shows the unread badge on the inbox section and hides it at zero', (tester) async {
    unread = 3;
    await pump(tester, home: const AdminShell());
    await settle(tester);
    expect(find.byKey(const Key('inbox-badge')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('inbox-badge')), matching: find.text('3')), findsOneWidget);
    unread = 0;
    await pump(tester, home: const AdminShell());
    await settle(tester);
    expect(find.byKey(const Key('inbox-badge')), findsNothing);
  });

  testWidgets('compose a new message from a chosen mailbox', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('inbox-compose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('compose-mailbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin@naslife.app').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compose-to')), 'New@Customer.com');
    await tester.enterText(find.byKey(const Key('compose-subject')), 'ترحيب');
    await tester.enterText(find.byKey(const Key('compose-text')), 'أهلاً بك في ناس لايف.');
    await tester.tap(find.byKey(const Key('compose-send')));
    await settle(tester);
    expect(calls, contains('POST /adminapi/inbox/compose'));
    expect(lastBody, {'mailbox': 'admin', 'to': 'New@Customer.com', 'subject': 'ترحيب', 'text': 'أهلاً بك في ناس لايف.'});
    expect(find.text('أُرسلت الرسالة من admin@naslife.app'), findsOneWidget);
  });

  testWidgets('receiving settings: switch to Resend, save the signing secret, copy the webhook url', (tester) async {
    received = 0;
    await pump(tester);
    expect(find.byKey(const Key('inbox-banner')), findsOneWidget, reason: 'لم تصل رسائل بعد');
    await tester.tap(find.byKey(const Key('inbox-settings')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const Key('inbox-copy-generic')), findsOneWidget);
    expect(find.textContaining('وصل حتى الآن: 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-provider-resend')));
    await tester.pump();
    expect(find.byKey(const Key('inbox-copy-resend')), findsOneWidget);
    expect(find.text('https://naslife.app/inbox/webhook/resend'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('inbox-secret')), 'whsec_abc');
    await tester.tap(find.byKey(const Key('inbox-settings-save')));
    await settle(tester);
    expect(calls, contains('PUT /adminapi/inbox/settings'));
    expect(lastBody, {'provider': 'resend', 'webhookSecret': 'whsec_abc'});
    expect(find.text('حُفظت إعدادات الاستقبال'), findsOneWidget);
    expect(find.textContaining('محفوظ؛ اتركه فارغاً'), findsOneWidget);
  });
}
