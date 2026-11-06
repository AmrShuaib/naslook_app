import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/chat_cards_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/jobs_models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/chat/codes.dart';
import 'package:naslook/pages/admin/admin_reports.dart';
import 'package:naslook/pages/business/owner/dashboard_jobs.dart';
import 'package:naslook/pages/business/owner/dashboard_orders.dart';
import 'package:naslook/pages/business/owner/job_actions.dart';
import 'package:naslook/pages/chat/chat_cards.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/jobs/job_offer_page.dart';
import 'package:naslook/pages/jobs/job_offers_page.dart';
import 'package:naslook/pages/jobs/job_page.dart';
import 'package:naslook/pages/jobs/jobs_page.dart';
import 'package:naslook/pages/market/listing_page.dart' show BadgeChip;
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

/// الثقة في الوظائف والشارات الصادقة (فجوتا 7 و8 وأخطاء 6-8 من تقرير النواقص 5 نوفمبر):
/// «دائرة غير موثّقة» وسطر الأمان على الوظيفة وبطاقتها وصفحة العرض، البلاغ بنوع job، الوظيفة في «بلاغات المحتوى»،
/// لوحة التوظيف لدائرة غير موثّقة، «بريد مؤكد» بأيقونة بريد في السوق، وأيقونات الإدخال اليدوي بدل ماسح QR.

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _jobId = 'cccccccc-0000-4000-8000-0000000000c1';
const _matchId = 'dddddddd-0000-4000-8000-0000000000d1';
const _safety = 'لا تدفع أي رسوم ولا ترسل صورة هويتك قبل المقابلة. ناس لايف لا تطلب رسوماً للتوظيف.';
final _now = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _bizSummary({bool verified = false}) => {'id': 'biz-x', 'name': 'X Jobs', 'nameAr': 'وظائف إكس', 'category': 'other', 'address': 'جدة', 'city': 'جدة', 'logoUrl': null, 'verified': verified};

Map<String, dynamic> _job({bool verified = false, String status = 'open'}) => {
      'id': _jobId, 'bizId': 'biz-x', 'title': 'مدخل بيانات من المنزل', 'department': '', 'description': 'عمل من المنزل بدخل يومي، التواصل عبر المحادثة.', 'requirements': {'must': [], 'nice': []}, 'skills': [],
      'city': 'جدة', 'district': '', 'type': 'remote', 'experienceMin': 0, 'education': 'none', 'salaryVisible': false, 'openings': 1, 'status': status, 'public': true, 'publishedAt': _now,
      'biz': _bizSummary(verified: verified), 'bizVerified': verified, 'mine': null,
    };

Map<String, dynamic> _match({bool verified = false}) => {
      'id': _matchId, 'jobId': _jobId, 'bizId': 'biz-x', 'status': 'sent', 'stage': 'new', 'stageLabel': 'جديد', 'source': 'match', 'score': .7, 'reasons': ['عن بُعد'], 'sentAt': _now,
      'job': _job(verified: verified), 'questions': [], 'assignee': {'id': 'SA0000002', 'nickname': 'sara'}, 'interview': null,
    };

Map<String, dynamic> _bizFull() => {
      'id': 'biz-x', 'name': 'X Jobs', 'nameAr': 'وظائف إكس', 'category': 'other', 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '', 'color': '#0058A3', 'highlights': [],
      'verified': false, 'official': false, 'active': true, 'ownerId': 'SA0000001', 'myRole': 'owner', 'views': 0, 'followers': 0, 'items': [], 'reviews': [], 'posts': [], 'myOrders': [],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool verified = false;
  bool reportHides = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(req.url.query.isEmpty ? key : '$key?${req.url.query}');
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /settings/public') return _json({'jobsEnabled': true});
    if (key == 'GET /jobs/profile') return _json({'profile': {'userId': 'SA0000001', 'active': true, 'titles': ['مدخل بيانات'], 'city': 'جدة'}, 'pending': 1, 'total': 1});
    if (key == 'GET /jobs') return _json({'items': [_job(verified: verified)], 'types': [], 'cities': ['جدة']});
    if (key == 'GET /jobs/$_jobId') return _json(_job(verified: verified));
    if (key == 'GET /jobs/inbox') return _json({'items': [_match(verified: verified)], 'pending': 1});
    if (key == 'GET /jobs/mine') return _json({'items': [], 'active': [], 'history': []});
    if (key == 'GET /jobs/offers/$_matchId') return _json(_match(verified: verified));
    if (key == 'GET /blocks') return _json({'data': []});
    if (key == 'POST /safety/report') return _json({'ok': true, 'reports': reportHides ? 3 : 1, 'hidden': reportHides, 'threshold': 3});
    if (key == 'GET /biz/biz-x/manage/jobs') {
      return _json({
        'items': [{..._job(status: 'blocked'), 'createdBy': 'SA0000001', 'counts': {'sent': 0, 'viewed': 0, 'accepted': 0, 'answered': 0, 'declined': 0, 'byStage': {}}}],
        'plan': {'plan': 'free', 'until': null, 'freeActive': 3, 'active': 0}, 'team': [{'id': 'SA0000001', 'nickname': 'amr'}], 'role': 'owner', 'enabled': true, 'requireApproval': false,
        'upcomingInterviews': 0, 'aiAvailable': false, 'verified': verified,
      });
    }
    if (key == 'GET /biz/biz-x/manage/jobs/stats') return _json({'open': 0, 'filled': 0, 'candidates': 0, 'answered': 0, 'hired': 0, 'upcomingInterviews': 0, 'plan': {'plan': 'free', 'freeActive': 3}});
    if (key == 'GET /biz/biz-x/orders') return _json([]);
    if (key == 'GET /adminapi/moderation') {
      return _json({
        'status': 'open', 'open': 1, 'threshold': 3, 'actions': ['dismiss', 'hide', 'restore', 'suspend-owner'], 'types': [{'id': 'job', 'name': 'عرض وظيفي'}],
        'items': [
          {'targetType': 'job', 'targetId': _jobId, 'typeName': 'عرض وظيفي', 'reports': 3, 'reasons': ['احتيال أو نصب: يطلب رسوم تسجيل'], 'firstAt': _now, 'lastAt': _now, 'owner': {'id': 'SA0000002', 'nickname': 'sara'},
            'title': 'مدخل بيانات من المنزل', 'text': 'عمل من المنزل', 'mediaUrl': null, 'status': 'hidden', 'hidden': true, 'bizId': 'biz-x', 'jobId': _jobId, 'action': null},
        ],
      });
    }
    if (key == 'GET /events/ev-1') return _json({'id': 'ev-1', 'title': 'أمسية القهوة', 'description': '', 'host': {'id': 'SA0000001', 'nickname': 'amr'}, 'isHost': true, 'cancelled': false, 'going': 3, 'myTickets': 0, 'tiers': []});
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/wishlist')) return _json({'items': []});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {double height = 1800}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('models: bizVerified flag, not-verified publish text, blocked label, board and preview flags', () {
    expect(Job.fromJson(_job()).unverifiedCircle, isTrue);
    expect(Job.fromJson(_job(verified: true)).unverifiedCircle, isFalse);
    // بلا bizVerified يُقرأ من biz.verified، وبلا الاثنين (إخراج لوحة الدائرة) لا يُعرض شيء
    expect(Job.fromJson({..._job(), 'bizVerified': null}).unverifiedCircle, isTrue);
    expect(Job.fromJson({'id': _jobId, 'bizId': 'biz-x', 'title': 'x'}).unverifiedCircle, isFalse);
    expect(jobStatusLabel('blocked'), 'مخفي بالإشراف');
    final pub = Job.fromJson({..._job(), 'matched': {'sent': 0, 'considered': 0, 'skipped': 'not-verified'}});
    expect(pub.matched!.notVerified, isTrue);
    expect(jobPublishedText(pub), 'نُشر العرض في قائمة الوظائف؛ يصل للمرشحين المطابقين بعد توثيق الدائرة');
    expect(jobActionsFor(Job.fromJson(_job(status: 'blocked'))).map((a) => a.id), isNot(contains('duplicate')));
    expect(jobActionsFor(Job.fromJson(_job(status: 'blocked'))).map((a) => a.id), isNot(contains('publish')));
    expect(JobsBoard.fromJson({'verified': false}).verified, isFalse);
    expect(JobsBoard.fromJson({}).verified, isTrue, reason: 'خادم قديم بلا الحقل: لا لافتة');
    expect(JobPreview.fromJson({'autoMatch': false}).autoMatch, isFalse);
    expect(jobSafetyLine, _safety);
  });

  testWidgets('job page: unverified tag, fixed safety line, and «إبلاغ عن الوظيفة» posts a job report', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobPage(id: _jobId));
    expect(find.byKey(const Key('job-unverified')), findsOneWidget);
    expect(find.text('دائرة غير موثّقة'), findsOneWidget);
    expect(find.byKey(const Key('job-safety')), findsOneWidget);
    expect(find.text(_safety), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-report-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('job-report-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /safety/report'], {'targetType': 'job', 'targetId': _jobId, 'reason': 'احتيال أو نصب'});
    expect(find.text('وصل بلاغك وسنراجعه خلال 24 ساعة'), findsOneWidget);
  });

  testWidgets('job page of a verified circle: no unverified tag, safety line stays', (tester) async {
    final srv = _Srv()..verified = true;
    await _pump(tester, srv, const JobPage(id: _jobId));
    expect(find.byKey(const Key('job-unverified')), findsNothing);
    expect(find.text(_safety), findsOneWidget);
  });

  testWidgets('jobs list card carries the unverified tag', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobsPage());
    expect(find.byKey(const Key('job-$_jobId')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('job-$_jobId')), matching: find.byKey(const Key('job-unverified'))), findsOneWidget);
  });

  testWidgets('offer card in the inbox and the offer page show the safety line; the offer page reports the job', (tester) async {
    final srv = _Srv()..reportHides = true;
    await _pump(tester, srv, const JobOffersPage());
    final card = find.byKey(const Key('job-card-$_matchId'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const Key('job-safety'))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const Key('job-unverified'))), findsOneWidget);
    await tester.tap(find.text('مدخل بيانات من المنزل'));
    await tester.pumpAndSettle();
    expect(find.byType(JobOfferPage), findsOneWidget);
    expect(find.text(_safety), findsOneWidget);
    expect(find.byKey(const Key('job-unverified')), findsOneWidget);
    await tester.tap(find.byKey(const Key('offer-report-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-report-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-reason-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /safety/report']?['targetType'], 'job');
    expect(srv.bodies['POST /safety/report']?['targetId'], _jobId);
    expect(find.text('وصل بلاغك وأُخفي المحتوى للمراجعة'), findsOneWidget);
    // الإخفاء يحدّث صندوق الواردة
    expect(srv.calls.where((c) => c == 'GET /jobs/inbox').length, greaterThanOrEqualTo(2));
  });

  testWidgets('the #job card inside a chat thread carries the safety line', (tester) async {
    final code = parseRef(jobCode(_jobId))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatCodeCard(
      code: code, resolved: true, mine: false, peerName: 'sara', onAction: (_, __) {},
      card: ChatCard.fromJson({'type': 'job', 'id': _jobId, 'bizId': 'biz-x', 'title': 'مدخل بيانات من المنزل', 'subtitle': 'وظائف إكس · جدة', 'status': 'open', 'link': '/jobs/$_jobId'}),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('مدخل بيانات من المنزل'), findsOneWidget);
    expect(find.byKey(const Key('job-safety')), findsOneWidget);
    expect(find.text(_safety), findsOneWidget);
  });

  testWidgets('owner jobs tab: unverified banner with a verify action, blocked job without duplicate', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, Scaffold(body: JobsTab(biz: Biz.fromJson(_bizFull()))));
    expect(find.byKey(const Key('jobs-unverified')), findsOneWidget);
    expect(find.byKey(const Key('jobs-verify')), findsOneWidget);
    expect(find.text('مخفي بالإشراف'), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-menu-$_jobId')));
    await tester.pumpAndSettle();
    expect(find.text('تكرار كمسودة'), findsNothing);
    expect(find.text('تعديل'), findsOneWidget);
  });

  testWidgets('owner jobs tab of a verified circle: no banner', (tester) async {
    final srv = _Srv()..verified = true;
    await _pump(tester, srv, Scaffold(body: JobsTab(biz: Biz.fromJson({..._bizFull(), 'verified': true}))));
    expect(find.byKey(const Key('jobs-unverified')), findsNothing);
  });

  testWidgets('admin content reports: a job target opens the job page', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: AdminModerationTab()));
    expect(find.text('عرض وظيفي'), findsWidgets);
    final open = find.byKey(const Key('mod-open-job-$_jobId'));
    expect(open, findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(JobPage), findsOneWidget);
    expect(srv.calls, contains('GET /jobs/$_jobId'));
  });

  testWidgets('market seller badge "verified" reads «بريد مؤكد» with a mail icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BadgeChip('verified'))));
    expect(find.text('بريد مؤكد'), findsOneWidget);
    expect(find.text('موثّق'), findsNothing);
    expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);
  });

  testWidgets('manual code entry is not dressed as a camera scanner (orders tab and event host)', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(_bizFull()))));
    expect(find.byKey(const Key('orders-checkin-code')), findsOneWidget);
    expect(find.text('إدخال رمز الاستلام'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    await _pump(tester, srv, const EventDetailPage(eventId: 'ev-1'));
    expect(find.byKey(const Key('event-checkin-code')), findsOneWidget);
    expect(find.text('تسجيل دخول برمز التذكرة'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
  });
}
