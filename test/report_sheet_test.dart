// ورقة الإبلاغ الموحدة: سبب جاهز يكفي بلا ملاحظة، «حظر الناشر أيضاً» يرسل الحظر، أخطاء «محتواك» مفهومة،
// البلاغ عن شخص يذهب إلى /reports، وخيار الحظر لا يظهر لمحتواي أو لمن حظرته من قبل.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/state/safety_providers.dart';
import 'package:naslook/ui/report_sheet.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111';
const _sara = Person(id: 'SA0000002', nickname: 'sara');
const _me = Person(id: 'SA0000001', nickname: 'amr');

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final blocked = <Map<String, dynamic>>[];
  String? reportError;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty && req.method != 'GET') bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'POST /safety/report':
        if (reportError != null) return _json({'error': reportError}, reportError == 'not-found' ? 404 : 400);
        return _json({'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3});
      case 'POST /reports':
        return _json({'ok': true});
      case 'POST /blocks':
        blocked.add({'blockedId': bodies[key]!['blockedId'], 'nickname': 'sara'});
        return _json({'ok': true});
      case 'GET /blocks':
        return _json(blocked);
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, {required String type, required String id, Person? author, String? messageId, _Srv? srv}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(
      locale: const Locale('ar'),
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          ref.watch(blockedIdsProvider); // يحمّل قائمة المحظورين كما في الشاشات الحقيقية
          return Center(child: TextButton(key: const Key('open'), onPressed: () => showReportSheet(context, ref, type: type, id: id, author: author, messageId: messageId), child: const Text('open')));
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('a preset reason alone (no note) posts /safety/report and confirms the 24h review', (tester) async {
    final srv = await _pump(tester, type: 'listing', id: _lid, author: _sara);
    expect(find.text('محتوى مسيء أو كراهية'), findsOneWidget);
    expect(find.text('انتحال شخصية'), findsOneWidget);
    // الإرسال معطل حتى يُختار سبب
    expect(tester.widget<FilledButton>(find.byKey(const Key('report-submit'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('report-reason-5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /safety/report'], {'targetType': 'listing', 'targetId': _lid, 'reason': 'إزعاج أو سبام'});
    expect(srv.calls, isNot(contains('POST /blocks')));
    expect(find.text('وصل بلاغك وسنراجعه خلال 24 ساعة'), findsOneWidget);
  });

  testWidgets('"also block" reports then blocks the author and refreshes the blocked set', (tester) async {
    final srv = await _pump(tester, type: 'vessel-comment', id: 'c-1', author: _sara);
    expect(find.text('حظر sara أيضاً'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-reason-1')));
    await tester.enterText(find.byKey(const Key('report-note')), 'رسائل متكررة');
    await tester.tap(find.byKey(const Key('report-also-block')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /safety/report'], {'targetType': 'vessel-comment', 'targetId': 'c-1', 'reason': 'تحرش أو تنمر: رسائل متكررة'});
    expect(srv.bodies['POST /blocks']!['blockedId'], 'SA0000002');
    expect(srv.calls.where((c) => c == 'GET /blocks').length, greaterThanOrEqualTo(2), reason: 'قائمة المحظورين أعيد جلبها');
    expect(find.textContaining('وحُظر sara'), findsOneWidget);
  });

  testWidgets('own-content and not-found errors are explained, and own content is never blocked', (tester) async {
    final srv = _Srv()..reportError = 'own-content';
    await _pump(tester, type: 'post', id: _lid, author: _sara, srv: srv);
    await tester.tap(find.byKey(const Key('report-reason-7')));
    await tester.tap(find.byKey(const Key('report-also-block')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(find.text('لا يمكنك الإبلاغ عن محتواك'), findsOneWidget);
    expect(srv.calls, isNot(contains('POST /blocks')));

    srv.reportError = 'not-found';
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(find.text('لم يعد هذا المحتوى موجوداً'), findsOneWidget);
  });

  testWidgets('reporting a person goes to /reports with the message id', (tester) async {
    final srv = await _pump(tester, type: kReportUser, id: 'SA0000002', author: _sara, messageId: 'm-9');
    await tester.tap(find.byKey(const Key('report-reason-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /reports']!;
    expect(b['userId'], 'SA0000002');
    expect(b['reason'], 'احتيال أو نصب');
    expect(b['messageId'], 'm-9');
    expect(srv.calls, isNot(contains('POST /safety/report')));
  });

  testWidgets('no "also block" option for my own content or for someone already blocked', (tester) async {
    await _pump(tester, type: 'post', id: _lid, author: _me);
    expect(find.byKey(const Key('report-also-block')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final srv = _Srv()..blocked.add({'blockedId': 'SA0000002', 'nickname': 'sara'});
    await _pump(tester, type: 'post', id: _lid, author: _sara, srv: srv);
    expect(find.byKey(const Key('report-reason-0')), findsOneWidget);
    expect(find.byKey(const Key('report-also-block')), findsNothing);
  });
}
