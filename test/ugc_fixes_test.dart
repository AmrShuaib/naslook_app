// إصلاحات مراجعة الإبلاغ والحظر: الإبلاغ عن الدائرة نفسها وحظر مالكها، ورقة الإبلاغ للزائر ولمن حُظر قبل تحميل القائمة،
// رسالة واحدة للبلاغ والحظر، قائمة المحظورين لكل حساب، تحديث المحظورين بعد الحظر من المحادثة، تحديث التعليقات المخفية بالسحب،
// التحقق المسبق من الكلمات المحظورة (قائمة الإدارة والافتراضية) قبل التعليق، وعدّاد طابور الإشراف،
// وأن كل نوع بلاغ يرسله التطبيق معروف في server/safety.js.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/safety_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_reports.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/circles/circle_detail_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/state/safety_providers.dart';
import 'package:naslook/ui/report_sheet.dart';

const _me = 'SA0000001';

/// حالة تطبيق يمكن تبديل حسابها (أو الخروج) أثناء الاختبار.
class _Auth extends AppStateNotifier {
  _Auth(super.api, super.store, {String? user = _me}) {
    setUser(user);
  }
  void setUser(String? id) => state = id == null
      ? const AppState(status: AuthStatus.signedOut)
      : AppState(status: AuthStatus.signedIn, session: Session(token: 't-$id', user: SessionUser(id: id, nickname: id == _me ? 'amr' : 'other')));
}

typedef _Route = Object? Function(http.Request req, Map<String, dynamic>? body);

/// خادم وهمي: مسارات صريحة (الرد قد يكون (رمز, جسم))، والباقي قائمة فارغة لـ GET و{ok} لغيرها.
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final routes = <String, _Route>{};
  final blocked = <Map<String, dynamic>>[];
  _Srv() {
    routes['GET /blocks'] = (_, __) => blocked;
    routes['POST /blocks'] = (_, b) {
      blocked.add({'blockedId': b!['blockedId'], 'nickname': 'x'});
      return {'ok': true};
    };
    routes['POST /safety/report'] = (_, __) => {'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3};
    routes['GET /notify/unread'] = (_, __) => {'unread': 0};
  }
  http.Response _json(Object? body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty && req.method != 'GET') {
      try {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies[key] = body;
      } catch (_) {}
    }
    final r = routes[key];
    if (r != null) {
      final out = r(req, body);
      if (out is (int, Object)) return _json(out.$2, out.$1);
      return _json(out);
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return req.method == 'GET' ? _json([]) : _json({'ok': true});
  }

  int count(String key) => calls.where((c) => c == key || c.startsWith('$key?')).length;
}

Future<_Srv> _pump(WidgetTester tester, _Srv srv, Widget home, {String? user = _me, Size size = const Size(480, 1400)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _Auth(api, SessionStore(), user: user)),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return srv;
}

/// زر يفتح ورقة الإبلاغ مباشرة، بلا أي ودجة تحمّل قائمة المحظورين (كالخلاصة والمحادثة والروابط المباشرة).
Widget _opener({required String type, required String id, Person? author}) => Scaffold(
      body: Consumer(builder: (context, ref, _) => Center(child: TextButton(key: const Key('open'), onPressed: () => showReportSheet(context, ref, type: type, id: id, author: author), child: const Text('open')))),
    );

Future<void> _pickReasonAndSend(WidgetTester tester, {int reason = 0, bool alsoBlock = false}) async {
  await tester.tap(find.byKey(Key('report-reason-$reason')));
  if (alsoBlock) await tester.tap(find.byKey(const Key('report-also-block')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('report-submit')));
  await tester.pumpAndSettle();
}

// معرّفات بشكل UUID كما يتطلب الخادم الحقيقي
const _pid = 'aaaaaaaa-0000-4000-8000-000000000001';
const _sara = Person(id: 'SA0000002', nickname: 'sara');
const _v = '11111111-1111-4111-8111-111111111111';
const _vp = '22222222-2222-4222-8222-222222222222';
const _c1 = '33333333-3333-4333-8333-333333333331';
const _c2 = '33333333-3333-4333-8333-333333333332';
final _now = DateTime.now().toUtc().toIso8601String();

_Srv _circleSrv({String role = 'member', String? ownerId = 'SA0000009', List<String> hiddenComments = const []}) {
  final srv = _Srv();
  final hidden = [...hiddenComments];
  srv.routes['GET /vessels/$_v'] = (_, __) => {
        'id': _v, 'name': 'دائرة الحي', 'topic': 'الجيران', 'ownerId': ownerId, 'isPublic': true, 'members': 5, 'role': role, 'joined': true,
        'postsPage': [
          {
            'id': _vp, 'vesselId': _v, 'vesselName': 'دائرة الحي', 'type': 'text', 'content': 'منشور سارة', 'caption': '', 'kind': 'discussion',
            'author': {'id': 'SA0000002', 'nickname': 'sara'}, 'createdAt': _now, 'supports': 0, 'comments': 2, 'supported': false, 'unread': false,
          },
        ],
      };
  srv.routes['GET /posts/hidden'] = (req, _) => req.url.queryParameters['kind'] == 'comment' ? {'kind': 'comment', 'ids': hidden} : {'ids': []};
  srv.routes['GET /posts/$_vp/comments'] = (_, __) => [
        {'id': _c1, 'author': {'id': 'SA0000006', 'nickname': 'lina'}, 'text': 'تعليق لينا', 'createdAt': _now},
        {'id': _c2, 'author': {'id': 'SA0000007', 'nickname': 'noura'}, 'text': 'تعليق نورة', 'createdAt': _now},
      ];
  return srv;
}

Future<void> _openComments(WidgetTester tester) async {
  await tester.tap(find.text('التعليقات (2)'));
  await tester.pumpAndSettle();
}

void main() {
  // ================= الدائرة نفسها =================
  testWidgets('a member can report the circle itself (type vessel) and block its owner', (tester) async {
    final srv = await _pump(tester, _circleSrv(), const CircleDetailPage(vesselId: _v));
    await tester.tap(find.byKey(const Key('vessel-menu')));
    await tester.pumpAndSettle();
    expect(find.text('إبلاغ عن الدائرة'), findsOneWidget);
    expect(find.text('حظر المالك'), findsOneWidget);
    await tester.tap(find.byKey(const Key('vessel-report')));
    await tester.pumpAndSettle();
    expect(find.text('حظر المالك أيضاً'), findsOneWidget);
    await _pickReasonAndSend(tester, reason: 0);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'vessel', 'targetId': _v, 'reason': 'محتوى مسيء أو كراهية'});
    expect(find.text('وصل بلاغك وسنراجعه خلال 24 ساعة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vessel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vessel-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000009');
  });

  testWidgets('circle report menu: report only when the owner is unknown, none for the owner', (tester) async {
    await _pump(tester, _circleSrv(ownerId: null), const CircleDetailPage(vesselId: _v));
    await tester.tap(find.byKey(const Key('vessel-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vessel-report')), findsOneWidget);
    expect(find.byKey(const Key('vessel-block')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _pump(tester, _circleSrv(role: 'owner', ownerId: _me), const CircleDetailPage(vesselId: '11111111-1111-4111-8111-111111111111'));
    expect(find.byKey(const Key('vessel-menu')), findsNothing);
  });

  // ================= ورقة الإبلاغ =================
  testWidgets('a guest gets the sign-in sheet instead of a report sheet that ends in 401', (tester) async {
    final srv = await _pump(tester, _Srv(), _opener(type: 'post', id: _pid, author: _sara), user: null);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.byKey(const Key('report-submit')), findsNothing);
    expect(srv.calls, isNot(contains('POST /safety/report')));
    expect(srv.calls, isNot(contains('GET /blocks')));
  });

  testWidgets('"also block" is not offered for someone already blocked even when no screen loaded the list', (tester) async {
    final srv = _Srv()..blocked.add({'blockedId': 'SA0000002', 'nickname': 'sara'});
    await _pump(tester, srv, _opener(type: 'post', id: _pid, author: _sara));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-reason-0')), findsOneWidget);
    expect(find.byKey(const Key('report-also-block')), findsNothing);
    expect(srv.count('GET /blocks'), 1);
  });

  testWidgets('report fails but block succeeds: one combined message that says what happened', (tester) async {
    final srv = _Srv();
    srv.routes['POST /safety/report'] = (_, __) => (404, {'error': 'not-found'});
    await _pump(tester, srv, _opener(type: 'post', id: _pid, author: _sara));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, alsoBlock: true);
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000002');
    expect(find.text('تعذّر إرسال البلاغ (لم يعد هذا المحتوى موجوداً) لكن حُظر sara'), findsOneWidget);
    expect(find.textContaining('وحُظر'), findsNothing);
  });

  testWidgets('report and block both succeed: «وصل بلاغك وحُظر sara»', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, _opener(type: 'listing', id: _pid, author: _sara));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, alsoBlock: true);
    expect(find.text('وصل بلاغك وحُظر sara'), findsOneWidget);
  });

  testWidgets('report succeeds but block fails: the report is confirmed and the block error shown', (tester) async {
    final srv = _Srv();
    srv.routes['POST /blocks'] = (_, __) => (500, {'error': 'boom'});
    await _pump(tester, srv, _opener(type: 'listing', id: _pid, author: _sara));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await _pickReasonAndSend(tester, alsoBlock: true);
    expect(find.textContaining('وصل بلاغك، لكن تعذّر حظر sara'), findsOneWidget);
  });

  // ================= قائمة المحظورين لكل حساب =================
  test('blockedUsersProvider follows the signed-in account and is empty for guests', () async {
    final srv = _Srv();
    var current = _me;
    srv.routes['GET /blocks'] = (_, __) => current == _me ? [{'blockedId': 'SA0000002', 'nickname': 'sara'}] : [{'blockedId': 'SA0000005', 'nickname': 'x'}];
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
    late _Auth auth;
    final c = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => auth = _Auth(api, SessionStore())),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(blockedIdsProvider, (_, __) {});
    addTearDown(sub.close);
    expect((await c.read(blockedUsersProvider.future)).map((u) => u.id), ['SA0000002']);
    // خروج ثم دخول بحساب آخر في الجلسة نفسها
    auth.setUser(null);
    expect(await c.read(blockedUsersProvider.future), isEmpty);
    expect(c.read(blockedIdsProvider), isEmpty);
    final before = srv.count('GET /blocks');
    current = 'SA0000003';
    auth.setUser('SA0000003');
    expect((await c.read(blockedUsersProvider.future)).map((u) => u.id), ['SA0000005']);
    expect(srv.count('GET /blocks'), before + 1);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(blockedIdsProvider), {'SA0000005'});
  });

  // ================= الحظر من المحادثة يحدّث قائمة المحظورين =================
  testWidgets('blocking from a chat refreshes the blocked set used to filter circles', (tester) async {
    final srv = _Srv();
    final home = Scaffold(
      body: Consumer(builder: (context, ref, _) {
        final n = ref.watch(blockedIdsProvider).length;
        return Column(children: [
          Text('blocked:$n', key: const Key('blocked-count')),
          TextButton(
            key: const Key('open-chat'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')))),
            child: const Text('chat'),
          ),
        ]);
      }),
    );
    await _pump(tester, srv, home);
    expect(find.text('blocked:0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('المزيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حظر').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حظر'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000002');
    expect(find.text('blocked:1'), findsOneWidget, reason: 'قائمة المحظورين أعيد جلبها بعد الحظر من المحادثة');
  });

  // ================= تعليقات الدائرة =================
  testWidgets('pull-to-refresh re-fetches hidden comment ids and the comments', (tester) async {
    final hidden = <String>[];
    final srv = _circleSrv();
    srv.routes['GET /posts/hidden'] = (req, _) => req.url.queryParameters['kind'] == 'comment' ? {'kind': 'comment', 'ids': hidden} : {'ids': []};
    await _pump(tester, srv, const CircleDetailPage(vesselId: _v));
    await _openComments(tester);
    expect(find.text('تعليق نورة'), findsOneWidget);
    // الإدارة أخفت تعليق نورة بعد فتح الصفحة
    hidden.add(_c2);
    final commentsBefore = srv.count('GET /posts/$_vp/comments');
    await tester.fling(find.text('منشور سارة'), const Offset(0, 500), 1000);
    await tester.pumpAndSettle();
    expect(srv.count('GET /posts/$_vp/comments'), greaterThan(commentsBefore));
    expect(find.text('تعليق نورة'), findsNothing);
    expect(find.text('تعليق لينا'), findsOneWidget);
  });

  testWidgets('a circle comment with a banned word (admin list or default seed) is stopped before sending', (tester) async {
    final srv = _circleSrv();
    srv.routes['GET /safety/words'] = (_, __) => {'words': ['احتيال'], 'threshold': 3, 'defaults': 2, 'defaultWords': ['شرموطه', 'ابن الكلب']};
    await _pump(tester, srv, const CircleDetailPage(vesselId: _v));
    await _openComments(tester);
    final input = find.byKey(const Key('comment-input-$_vp'));
    await tester.enterText(input, 'هذا إحتيال');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('النص يحتوي كلمة غير مسموحة: «احتيال»'), findsOneWidget);
    await tester.enterText(input, 'يا شرموطة');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('النص يحتوي كلمة غير مسموحة: «شرموطه»'), findsOneWidget);
    expect(srv.calls, isNot(contains('POST /posts/$_vp/comments')));
    // كلمة عادية تحتوي الحروف نفسها تمر كما في الخادم
    await tester.enterText(input, 'كلب لطيف في الحي');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /posts/$_vp/comments'));
  });

  test('bannedWordIn matches the default list as whole words like server findDefaultBanned', () {
    final w = BannedWords(const ['احتيال'], defaults: const ['شرموطه', 'قحبه', 'fuck', 'ابن الكلب', 'زبي']);
    expect(bannedWordIn('يا شرموطة', w), 'شرموطه');
    expect(bannedWordIn('والقحبة', w), 'قحبه');
    expect(bannedWordIn('what the FUCK', w), 'fuck');
    expect(bannedWordIn('ابن الكلب هذا', w), 'ابن الكلب');
    expect(bannedWordIn('عرض إحتيالي', w), 'احتيال', reason: 'قائمة الإدارة تبقى مطابقة جزئية');
    for (final ok in ['زبدة طازجة', 'زبون', 'class pass assess', 'كلب لطيف']) {
      expect(bannedWordIn(ok, w), isNull, reason: ok);
    }
    // النسخ القديمة: قائمة عادية بلا افتراضية تعمل كما كانت
    expect(bannedWordIn('يا شرموطة', const ['احتيال']), isNull);
  });

  test('bannedWords() reads the default list and stays compatible with old responses', () async {
    var resp = <String, dynamic>{'words': ['نصب'], 'threshold': 3, 'defaults': 1, 'defaultWords': ['fuck']};
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((_) async => http.Response(jsonEncode(resp), 200, headers: {'content-type': 'application/json'})))..token = 't';
    var w = await api.bannedWords();
    expect(w, ['نصب']);
    expect(w.defaults, ['fuck']);
    resp = {'words': ['نصب'], 'threshold': 3, 'defaults': 52};
    w = await api.bannedWords();
    expect(w, ['نصب']);
    expect(w.defaults, isEmpty);
  });

  // ================= الإدارة =================
  testWidgets('moderation count is labelled as the total across types', (tester) async {
    final srv = _Srv();
    srv.routes['GET /adminapi/reports'] = (_, __) => {'available': true, 'items': []};
    srv.routes['GET /adminapi/moderation'] = (_, __) => {'status': 'open', 'open': 7, 'threshold': 3, 'types': [{'id': 'vessel', 'name': 'دائرة'}], 'items': []};
    await _pump(tester, srv, const Scaffold(body: AdminReportsPage()), size: const Size(700, 1200));
    await tester.tap(find.byKey(const Key('reports-tab-content')));
    await tester.pumpAndSettle();
    expect(find.textContaining('7 عنصراً بانتظار المراجعة (إجمالي كل الأنواع)'), findsOneWidget);
  });

  testWidgets('support email helper says where the address appears', (tester) async {
    final srv = _Srv();
    srv.routes['GET /adminapi/settings'] = (_, __) => {'testTopup': false, 'maxTopup': 100000, 'announcement': '', 'maintenance': false, 'supportHandle': '', 'supportEmail': '', 'bannedWords': '', 'reportThreshold': 3};
    srv.routes['GET /adminapi/payments/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar'};
    await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()), size: const Size(600, 3000));
    expect(find.textContaining('صفحات الدعم والخصوصية والشروط'), findsOneWidget);
    expect(find.textContaining('يظهر في «تواصل معنا» داخل التطبيق'), findsNothing);
  });

  // ================= أنواع البلاغ في التطبيق = أنواع الخادم =================
  test('every report type string used in lib/ is in server/safety.js TARGET_TYPES', () {
    final js = File('server/safety.js').readAsStringSync();
    final m = RegExp(r'export const TARGET_TYPES = \[([^\]]*)\]', dotAll: true).firstMatch(js);
    expect(m, isNotNull);
    final server = {for (final x in RegExp(r'"([^"]+)"').allMatches(m!.group(1)!)) x.group(1)!};
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final call in RegExp(r'(?:showReportSheet|ReportMenuButton)\(').allMatches(src)) {
        // وسائط النداء حتى القوس المقابل
        var depth = 0, end = src.length;
        for (var i = call.end - 1; i < src.length; i++) {
          if (src[i] == '(') depth++;
          if (src[i] == ')' && --depth == 0) {
            end = i;
            break;
          }
        }
        for (final t in RegExp(r"\btype:\s*'([^']+)'").allMatches(src.substring(call.start, end))) {
          used.add(t.group(1)!);
        }
      }
    }
    expect(used.length, greaterThanOrEqualTo(15), reason: 'used: $used');
    expect(used, contains('vessel'));
    expect(used.difference(server), isEmpty, reason: 'types unknown to the server');
  });
}
