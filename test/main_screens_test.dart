// الشاشات الرئيسية بنظام «الخريطة أولاً»: الدوائر بحلقات وموجز واكتشف، والمحادثات بصف الطلبات والعرض الوظيفي المثبّت.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/circles/circles_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _job1 = 'bbbbbbbb-0000-4000-8000-000000000001';
const _m1 = 'cccccccc-0000-4000-8000-000000000001';

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> _vessel(String id, String name, {bool member = true, DateTime? last, int members = 12}) =>
      {'id': id, 'name': name, 'topic': 'حي', 'kind': 'general', 'isPublic': true, 'members': members, 'member': member, 'lastPostAt': last?.toUtc().toIso8601String()};

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /vessels/mine':
        return _json([_vessel('v-fresh', 'جيران الشاطئ', last: DateTime.now().subtract(const Duration(hours: 2))), _vessel('v-old', 'مصوّرو جدة', last: DateTime.now().subtract(const Duration(days: 3)))]);
      case 'GET /vessels':
        return _json([_vessel('v-fresh', 'جيران الشاطئ'), _vessel('v-new', 'عشّاق القهوة', member: false, members: 430)]);
      case 'POST /vessels/v-new/join':
        return _json({'ok': true});
      case 'GET /vessels/feed':
        return _json([{'id': 'p1', 'vesselId': 'v-fresh', 'vesselName': 'جيران الشاطئ', 'author': {'id': 'SA0000002', 'nickname': 'sara'}, 'type': 'text', 'content': 'بازار الحي الجمعة', 'kind': 'text', 'comments': 2, 'supports': 5, 'supported': false, 'createdAt': DateTime.now().toUtc().toIso8601String()}]);
      case 'GET /chats':
        return _json([{'id': 'SA0000002', 'nickname': 'sara', 'lastType': 'text', 'lastContent': 'الصور جاهزة؟', 'lastAt': DateTime.now().toUtc().toIso8601String(), 'lastMine': false, 'unread': 2}]);
      case 'GET /requests':
        return _json([{'id': 'r1', 'from': {'id': 'SA0000009', 'nickname': 'nora'}, 'lastContent': 'أبي أسألك عن الجلسة', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'unread': 1}]);
      case 'GET /jobs/inbox':
        return _json({'items': [{'id': _m1, 'jobId': _job1, 'userId': 'SA0000001', 'status': 'sent', 'stage': 'offered', 'score': .87, 'seq': 3, 'reasons': [], 'sentAt': DateTime.now().toUtc().toIso8601String(), 'answers': [], 'job': {'id': _job1, 'bizId': 'biz-cafe', 'title': 'باريستا', 'type': 'part', 'city': 'جدة', 'status': 'open', 'requirements': {}, 'questions': []}, 'questions': []}], 'pending': 1});
      case 'GET /contacts':
        return _json([]);
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

void main() {
  testWidgets('circles: rings with a fresh ring, latest posts, discover cards that join', (tester) async {
    final srv = await _pump(tester, const CirclesPage());
    expect(find.byKey(const Key('circle-ring-v-fresh')), findsOneWidget);
    expect(find.byKey(const Key('circle-ring-v-old')), findsOneWidget);
    expect(find.byKey(const Key('circle-ring-new')), findsOneWidget);
    expect(find.text('آخر ما في دوائرك'), findsOneWidget);
    expect(find.text('بازار الحي الجمعة'), findsOneWidget);
    expect(find.text('اكتشف حولك'), findsOneWidget);
    expect(find.byKey(const Key('discover-v-new')), findsOneWidget, reason: 'غير العضو فقط يُقترح');
    expect(find.byKey(const Key('discover-v-fresh')), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const Key('discover-v-new')), matching: find.text('انضم')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(srv.calls, contains('POST /vessels/v-new/join'));
    // تبويب «اكتشف» ما زال قائمة كاملة
    await tester.tap(find.text('اكتشف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('عشّاق القهوة'), findsWidgets);
  });

  testWidgets('chats: pinned job offer and the message-requests row open the requests tab', (tester) async {
    await _pump(tester, const Scaffold(body: ChatsPage()));
    expect(find.text('sara'), findsOneWidget);
    expect(find.byKey(const Key('chat-job-pinned')), findsOneWidget);
    expect(find.textContaining('عرض وظيفي: باريستا'), findsOneWidget);
    expect(find.byKey(const Key('chat-requests-row')), findsOneWidget);
    expect(find.text('طلب مراسلة واحد'), findsOneWidget);
    expect(find.byKey(const Key('chat-chip-jobs')), findsOneWidget);
    expect(find.text('الطلبات · 2'), findsOneWidget, reason: 'طلب مراسلة + عرض وظيفي');
    await tester.tap(find.byKey(const Key('chat-requests-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('قبول'), findsOneWidget);
    expect(find.text('nora'), findsOneWidget);
  });
}
