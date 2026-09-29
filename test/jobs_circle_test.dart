import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/jobs_models.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/job_candidate_page.dart';
import 'package:naslook/pages/business/owner/job_candidates_page.dart';
import 'package:naslook/pages/business/owner/job_editor_page.dart';
import 'package:naslook/pages/business/owner/job_stats_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

/// اختبارات جانب الدائرة في التوظيف: تبويب اللوحة، المنشئ بالمحرك، لوحة المرشحين، صفحة المرشح، الإحصاءات، ووجهات الإشعارات.

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _job1 = 'aaaaaaaa-0000-4000-8000-00000000j001', _job2 = 'aaaaaaaa-0000-4000-8000-00000000j002';
const _mAnon = 'aaaaaaaa-0000-4000-8000-00000000m003', _mSara = 'aaaaaaaa-0000-4000-8000-00000000m001';
final _now = DateTime.now().toUtc();
String _iso(Duration d) => _now.add(d).toIso8601String();
Map<String, dynamic> _person(String id, String n) => {'id': id, 'nickname': n, 'avatarUrl': null};

Map<String, dynamic> _biz({String role = 'owner'}) => {
      'id': 'biz-cafe', 'name': 'Cafe', 'nameAr': 'مقهى عمرو', 'category': 'cafe', 'sector': 'مقهى', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2, 'address': 'الروضة، جدة', 'hours': '8-12',
      'color': '#0058A3', 'highlights': [], 'verified': false, 'official': false, 'active': true, 'ownerId': role == 'owner' ? 'SA0000001' : 'SA0000002', 'myRole': role, 'views': 7,
      'followers': 3, 'rating': 4.0, 'ratingCount': 1, 'minPrice': 1500, 'itemsCount': 0, 'items': [], 'reviews': [], 'posts': [], 'myOrders': [],
    };

Map<String, dynamic> _jobJson(String id, {required String title, String status = 'open', Map<String, dynamic>? counts, Map<String, dynamic>? assignee, Map<String, dynamic>? matched}) => {
      'id': id, 'bizId': 'biz-cafe', 'createdBy': 'SA0000001', 'assigneeId': assignee?['id'], 'title': title, 'titleEn': '', 'department': 'المبيعات', 'description': 'نبحث عن $title للانضمام إلى فريقنا في جدة بنظام الورديات.',
      'descriptionEn': '', 'requirements': {'must': ['خبرة سنة'], 'nice': ['لغة إنجليزية']}, 'skills': ['خدمة العملاء'], 'city': 'جدة', 'district': '', 'type': 'shift', 'experienceMin': 1, 'education': 'secondary',
      'salaryMin': 4500, 'salaryMax': 6000, 'salaryVisible': true, 'openings': 2, 'deadline': _iso(const Duration(days: 14)), 'status': status, 'public': true,
      'questions': [{'id': 'q1', 'text': 'كم سنة خبرة لديك؟', 'kind': 'number', 'options': [], 'required': true}], 'views': 12, 'draftSource': 'ai', 'publishedAt': status == 'open' ? _iso(const Duration(days: -3)) : null,
      'closedAt': null, 'createdAt': _iso(const Duration(days: -4)), 'updatedAt': _iso(const Duration(days: -1)), 'counts': counts ?? {'sent': 0, 'viewed': 0, 'accepted': 0, 'answered': 0, 'declined': 0, 'byStage': {}},
      'assignee': assignee, if (matched != null) 'matched': matched,
    };

Map<String, dynamic> _anon() => {
      'id': _mAnon, 'jobId': _job1, 'seq': 3, 'label': 'مرشح #3', 'anonymous': true, 'status': 'viewed', 'stage': 'new', 'stageLabel': 'جديد', 'source': 'match', 'score': .62, 'reasons': ['نفس المدينة', 'نوع الدوام مناسب'],
      'sentAt': _iso(const Duration(days: -1)), 'viewedAt': _iso(const Duration(hours: -20)), 'acceptedAt': null, 'answeredAt': null, 'declinedAt': null, 'assignee': null, 'notesCount': 0, 'rating': null, 'updatedAt': _iso(Duration.zero), 'interviews': [],
    };

Map<String, dynamic> _sara({String stage = 'answered', bool full = false}) => {
      'id': _mSara, 'jobId': _job1, 'seq': 1, 'label': 'مرشح #1', 'anonymous': false, 'status': 'answered', 'stage': stage, 'stageLabel': jobStages[stage], 'source': 'match', 'score': .82, 'reasons': ['المسمّى مطابق', 'نفس المدينة'],
      'sentAt': _iso(const Duration(days: -3)), 'viewedAt': _iso(const Duration(days: -3)), 'acceptedAt': _iso(const Duration(days: -2)), 'answeredAt': _iso(const Duration(days: -2)), 'declinedAt': null,
      'assignee': _person('SA0000003', 'khalid'), 'notesCount': 1, 'rating': 4.0, 'updatedAt': _iso(Duration.zero),
      'interviews': [{'id': 'aaaaaaaa-0000-4000-8000-00000000i001', 'at': _iso(const Duration(days: 2)), 'mode': 'onsite', 'place': 'فرع الروضة', 'note': '', 'status': 'scheduled'}],
      'user': _person('SA0000002', 'sara'),
      'profile': {'userId': 'SA0000002', 'active': true, 'titles': ['خدمة عملاء'], 'fields': ['تجزئة'], 'city': 'جدة', 'districts': ['الروضة'], 'types': ['full', 'shift'], 'experienceYears': 3, 'education': 'diploma', 'skills': ['خدمة العملاء', 'نقاط البيع'], 'languages': ['العربية'], 'salaryMin': 5000, 'salaryMax': 6500, 'availability': 'now', 'summary': 'ثلاث سنوات في خدمة العملاء.', 'cvUrl': 'https://naslife.app/cv/sara.pdf', 'cvName': 'sara-cv.pdf'},
      'answers': [{'id': 'q1', 'text': 'كم سنة خبرة لديك؟', 'kind': 'number', 'value': 3}],
      if (full) 'notes': [{'id': 'aaaaaaaa-0000-4000-8000-00000000n001', 'author': _person('SA0000001', 'amr'), 'text': 'مرشحة ممتازة', 'rating': 4, 'createdAt': _iso(const Duration(hours: -5))}],
      if (full) 'events': [{'kind': 'match.answered', 'actorId': 'SA0000002', 'data': {}, 'at': _iso(const Duration(days: -2))}, {'kind': 'match.sent', 'actorId': null, 'data': {}, 'at': _iso(const Duration(days: -3))}],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String role = 'owner';
  String plan = 'free';
  bool aiAvailable = true;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    const m = '/biz/biz-cafe/manage/jobs';
    if (key == 'GET /biz/biz-cafe') return _json(_biz(role: role));
    if (key == 'GET /biz/biz-cafe/team') return _json({'owner': _person('SA0000001', 'amr'), 'staff': [{'user': _person('SA0000003', 'khalid'), 'role': 'hr', 'since': _iso(const Duration(days: -9))}]});
    if (key == 'GET $m') {
      return _json({
        'items': [
          _jobJson(_job1, title: 'موظف خدمة عملاء', counts: {'sent': 5, 'viewed': 4, 'accepted': 2, 'answered': 1, 'declined': 1, 'byStage': {'new': 2, 'screening': 1, 'answered': 1, 'rejected': 1}}, assignee: _person('SA0000003', 'khalid')),
          _jobJson(_job2, title: 'مصمم جرافيك', status: 'draft'),
        ],
        'plan': {'plan': plan, 'until': plan == 'pro' ? _iso(const Duration(days: 30)) : null, 'freeActive': 3, 'active': 1},
        'team': [_person('SA0000001', 'amr'), _person('SA0000003', 'khalid')],
        'role': role, 'enabled': true, 'requireApproval': false, 'upcomingInterviews': 1, 'aiAvailable': aiAvailable,
      });
    }
    if (key == 'GET $m/stats') return _json({'open': 1, 'filled': 0, 'candidates': 5, 'answered': 1, 'hired': 0, 'upcomingInterviews': 1, 'plan': {'plan': plan, 'until': null, 'freeActive': 3}});
    if (key == 'POST $m/draft') {
      final b = bodies[key]!;
      return _json({
        'source': 'template', 'title': b['title'], 'titleEn': '', 'description': 'نبحث عن ${b['title']} في جدة بنظام دوام كامل.\n\nالمهام:\n• ${(b['bullets'] as List).join('\n• ')}\n\nنقدّم بيئة عمل محترمة.', 'descriptionEn': '',
        'requirements': {'must': ['خبرة في: ${(b['bullets'] as List).first}'], 'nice': ['التواصل الجيد مع العملاء']}, 'skills': ['العملاء'],
        'questions': [
          {'id': 'avail', 'text': 'متى تستطيع البدء؟', 'kind': 'choice', 'options': ['فوراً', 'خلال أسبوعين'], 'required': true},
          {'id': 'exp', 'text': 'كم سنة خبرة لديك في هذا المجال؟', 'kind': 'number', 'required': true},
          {'id': 'why', 'text': 'صف بإيجاز خبرة تشبه هذه الوظيفة.', 'kind': 'text', 'required': true},
        ],
        'aiError': null,
      });
    }
    if (key == 'POST $m/preview-match') return _json({'strong': 2, 'good': 5, 'weak': 3, 'threshold': .45, 'profiles': 12});
    if (key == 'POST $m') {
      final b = bodies[key]!;
      if (b['title'] == 'حد الباقة') return _json({'error': 'plan-limit', 'freeActive': 3}, 402);
      return _json(_jobJson('aaaaaaaa-0000-4000-8000-00000000j009', title: b['title'] as String, status: b['publish'] == true ? 'open' : 'draft', matched: b['publish'] == true ? {'sent': 4, 'considered': 9, 'capped': false} : null));
    }
    if (key == 'PATCH $m/$_job1') return _json(_jobJson(_job1, title: bodies[key]!['title'] as String));
    if (key == 'POST $m/$_job2/publish') return _json(_jobJson(_job2, title: 'مصمم جرافيك', matched: {'sent': 2, 'considered': 3, 'capped': false}));
    if (key == 'POST $m/$_job1/pause') return _json(_jobJson(_job1, title: 'موظف خدمة عملاء', status: 'paused'));
    if (key == 'GET $m/$_job1/candidates') {
      return _json({
        'job': _jobJson(_job1, title: 'موظف خدمة عملاء'),
        'items': [_sara(), _anon()],
        'counts': {'sent': 5, 'viewed': 4, 'accepted': 2, 'answered': 1, 'declined': 1, 'byStage': {'new': 1, 'answered': 1}},
        'stages': [for (final e in jobStages.entries) {'id': e.key, 'label': e.value, 'n': e.key == 'new' || e.key == 'answered' ? 1 : 0}],
      });
    }
    if (key == 'GET $m/$_job1/candidates/$_mSara') return _json(_sara(full: true));
    if (key == 'PATCH $m/$_job1/candidates/$_mSara') return _json(_sara(stage: bodies[key]!['stage'] as String? ?? 'answered'));
    if (key == 'POST $m/$_job1/candidates/$_mSara/notes') return _json({'id': 'aaaaaaaa-0000-4000-8000-00000000n002', 'author': _person('SA0000001', 'amr'), 'text': bodies[key]!['text'], 'rating': bodies[key]!['rating'], 'createdAt': _iso(Duration.zero)});
    if (key == 'GET $m/$_job1/stats') {
      return _json({
        'job': _jobJson(_job1, title: 'موظف خدمة عملاء'),
        'funnel': [{'id': 'sent', 'label': 'أُرسل', 'n': 5}, {'id': 'viewed', 'label': 'شاهد', 'n': 4}, {'id': 'accepted', 'label': 'قبِل', 'n': 2}, {'id': 'answered', 'label': 'أجاب', 'n': 1}, {'id': 'interview', 'label': 'مقابلة', 'n': 1}, {'id': 'hired', 'label': 'تعيين', 'n': 0}],
        'avgDaysToAnswer': 1.5, 'avgHoursToView': 3.2, 'views': 12, 'declines': [{'reason': 'الراتب', 'n': 1}], 'byStage': {'new': 2, 'answered': 1},
      });
    }
    if (key == 'GET $m/$_job1/export') return plan == 'pro' ? http.Response('"المرشح","الرقم"\n"sara","SA0000002"', 200, headers: {'content-type': 'text/csv; charset=utf-8'}) : _json({'error': 'pro-required'}, 402);
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/notify')) return _json({'items': [], 'unread': 0});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {double height = 1600}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

JobsBoard _board({bool ai = true}) => JobsBoard(team: [const Person(id: 'SA0000001', nickname: 'amr'), const Person(id: 'SA0000003', nickname: 'khalid')], aiAvailable: ai, plan: const JobPlan(active: 1));

void main() {
  testWidgets('dashboard shows the jobs tab with plan card, overview and jobs list', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: BusinessDashboardPage.jobsTab));
    expect(find.text('التوظيف'), findsOneWidget);
    expect(srv.calls, contains('GET /biz/biz-cafe/manage/jobs'));
    expect(find.text('1 من 3 عروض نشطة'), findsOneWidget);
    expect(find.text('موظف خدمة عملاء'), findsOneWidget);
    expect(find.text('مصمم جرافيك'), findsOneWidget);
    expect(find.text('أُرسل 5 · قبِل 2 · أجاب 1'), findsOneWidget);
    expect(find.text('khalid'), findsOneWidget);
    expect(find.byKey(const Key('job-new')), findsOneWidget);
    // قائمة الإجراءات على المسودة: نشر
    await tester.tap(find.byKey(const Key('job-menu-$_job2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نشر الآن'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-cafe/manage/jobs/$_job2/publish'));
    expect(find.text('وصل العرض إلى 2 مرشحاً'), findsOneWidget);
    // فتح المرشحين بالضغط على العرض
    await tester.tap(find.text('موظف خدمة عملاء'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /biz/biz-cafe/manage/jobs/$_job1/candidates'));
  });

  testWidgets('jobs tab is locked for a plain staff member and shown for hr', (tester) async {
    final srv = _Srv()..role = 'staff';
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: BusinessDashboardPage.jobsTab));
    expect(find.byKey(const Key('jobs-locked')), findsOneWidget);
    expect(srv.calls, isNot(contains('GET /biz/biz-cafe/manage/jobs')));
    final hr = _Srv()..role = 'hr';
    await _pump(tester, hr, const BusinessDashboardPage(id: 'biz-cafe', initialTab: BusinessDashboardPage.jobsTab));
    expect(find.byKey(const Key('jobs-locked')), findsNothing);
    expect(find.text('موظف خدمة عملاء'), findsOneWidget);
  });

  testWidgets('editor: the engine drafts the job and publishing posts publish=true with the matched snack', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, JobEditorPage(bizId: 'biz-cafe', board: _board()), height: 3200);
    expect(find.byKey(const Key('job-ai-hint')), findsNothing);
    await tester.enterText(find.byKey(const Key('job-title')), 'موظف استقبال');
    await tester.enterText(find.byKey(const Key('job-bullet-0')), 'استقبال العملاء');
    await tester.enterText(find.byKey(const Key('job-bullet-1')), 'الرد على الهاتف');
    await tester.tap(find.byKey(const Key('job-draft')));
    await tester.pumpAndSettle();
    final d = srv.bodies['POST /biz/biz-cafe/manage/jobs/draft']!;
    expect(d['title'], 'موظف استقبال');
    expect(d['bullets'], ['استقبال العملاء', 'الرد على الهاتف']);
    expect(find.text('قالب'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('job-desc'))).controller!.text, contains('نبحث عن موظف استقبال'));
    expect(find.text('أسئلة الفرز · 3/10'), findsOneWidget);
    expect(find.text('متى تستطيع البدء؟'), findsOneWidget);
    // معاينة المطابقة بأعداد فقط
    await tester.tap(find.byKey(const Key('job-preview')));
    await tester.pumpAndSettle();
    expect(find.text('2 مطابق قوي · 5 جيد · من 12 ملف نشط'), findsOneWidget);
    // النشر
    await tester.tap(find.byKey(const Key('job-publish')));
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /biz/biz-cafe/manage/jobs']!;
    expect(b['publish'], true);
    expect(b['title'], 'موظف استقبال');
    expect(b['draftSource'], 'template');
    expect((b['questions'] as List).length, 3);
    expect(b['requirements']['must'], ['خبرة في: استقبال العملاء']);
    expect(find.text('وصل العرض إلى 4 مرشحاً'), findsOneWidget);
  });

  testWidgets('editor: no-AI hint, plan-limit message on publish, and save as draft', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, JobEditorPage(bizId: 'biz-cafe', board: _board(ai: false)), height: 3200);
    expect(find.byKey(const Key('job-ai-hint')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('job-title')), 'حد الباقة');
    await tester.enterText(find.byKey(const Key('job-desc')), 'وصف طويل بما يكفي للنشر: نبحث عن موظف للانضمام إلى الفريق فوراً.');
    await tester.tap(find.byKey(const Key('job-publish')));
    await tester.pumpAndSettle();
    expect(find.textContaining('حد العروض النشطة'), findsOneWidget);
    expect(find.text('الباقة'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('job-title')), 'مسودة فقط');
    await tester.tap(find.byKey(const Key('job-save')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /biz/biz-cafe/manage/jobs']!['publish'], false);
    expect(find.text('حُفظت المسودة'), findsOneWidget);
  });

  testWidgets('editor: editing an existing job patches it and shows its questions', (tester) async {
    final srv = _Srv();
    final job = Job.fromJson(_jobJson(_job1, title: 'موظف خدمة عملاء'));
    await _pump(tester, srv, JobEditorPage(bizId: 'biz-cafe', board: _board(), initial: job), height: 3200);
    expect(find.text('تعديل العرض'), findsOneWidget);
    expect(find.text('كم سنة خبرة لديك؟'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('job-title')), 'موظف خدمة عملاء أول');
    await tester.tap(find.byKey(const Key('job-save')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PATCH /biz/biz-cafe/manage/jobs/$_job1']!['title'], 'موظف خدمة عملاء أول');
  });

  testWidgets('candidates page renders anonymous and revealed candidates and filters by stage', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobCandidatesPage(bizId: 'biz-cafe', jobId: _job1), height: 2400);
    expect(find.text('موظف خدمة عملاء'), findsOneWidget);
    // المجهول: رقم ودرجة وأسباب بلا هوية
    expect(find.text('مرشح #3'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('نفس المدينة'), findsWidgets);
    // المكشوف: الاسم والمدينة والخبرة والمسؤول والمقابلة
    expect(find.text('sara'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('جدة · خبرة 3 سنوات · خدمة عملاء'), findsOneWidget);
    expect(find.text('المسؤول: khalid'), findsOneWidget);
    // موعد المقابلة القادمة (يوم ووقت) وليس رقاقة مرحلة «مقابلة 0»
    expect(find.textContaining(RegExp(r'^مقابلة .+ [صم]$')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stage-filter-new')));
    await tester.pumpAndSettle();
    expect(find.text('مرشح #3'), findsOneWidget);
    expect(find.text('sara'), findsNothing);
    // فتح المرشح
    await tester.tap(find.byKey(const Key('stage-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cand-$_mSara')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /biz/biz-cafe/manage/jobs/$_job1/candidates/$_mSara'));
  });

  testWidgets('candidate page: profile, answers, stage patch, note post and own-note delete', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobCandidatePage(bizId: 'biz-cafe', jobId: _job1, matchId: _mSara), height: 3600);
    expect(find.byKey(const Key('cand-profile')), findsOneWidget);
    expect(find.text('ثلاث سنوات في خدمة العملاء.'), findsOneWidget);
    expect(find.text('sara-cv.pdf'), findsOneWidget);
    expect(find.text('كم سنة خبرة لديك؟'), findsOneWidget);
    expect(find.text('مرشحة ممتازة'), findsOneWidget);
    expect(find.byKey(const Key('cand-chat')), findsOneWidget);
    expect(find.byKey(const Key('cand-anon-note')), findsNothing);
    await tester.tap(find.byKey(const Key('stage-interview')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PATCH /biz/biz-cafe/manage/jobs/$_job1/candidates/$_mSara']!['stage'], 'interview');
    await tester.enterText(find.byKey(const Key('note-text')), 'نرتب مقابلة الأسبوع القادم');
    await tester.tap(find.byKey(const Key('note-star-5')));
    await tester.tap(find.byKey(const Key('note-add')));
    await tester.pumpAndSettle();
    final n = srv.bodies['POST /biz/biz-cafe/manage/jobs/$_job1/candidates/$_mSara/notes']!;
    expect(n['text'], 'نرتب مقابلة الأسبوع القادم');
    expect(n['rating'], 5);
    expect(find.byKey(const Key('note-del-aaaaaaaa-0000-4000-8000-00000000n001')), findsOneWidget);
    // فتح السيرة الذاتية عبر البديل
    Uri? opened;
    openCvOverride = (u) async => opened = u;
    addTearDown(() => openCvOverride = null);
    await tester.tap(find.byKey(const Key('cand-cv')));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://naslife.app/cv/sara.pdf');
  });

  testWidgets('stats page draws the funnel and exports CSV on pro', (tester) async {
    final srv = _Srv()..plan = 'pro';
    await _pump(tester, srv, const JobStatsPage(bizId: 'biz-cafe', jobId: _job1, pro: true), height: 2400);
    expect(find.byKey(const Key('stats-funnel')), findsOneWidget);
    expect(find.text('أُرسل'), findsOneWidget);
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('الراتب'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stats-export')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /biz/biz-cafe/manage/jobs/$_job1/export'));
    expect(find.byKey(const Key('csv-text')), findsOneWidget);
    expect(find.textContaining('sara'), findsOneWidget);
  });

  testWidgets('team tab offers the hr role', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
    expect(find.textContaining('توظيف · منذ'), findsOneWidget);
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'توظيف'), findsOneWidget);
  });

  test('notification targets for circle-side job kinds', () {
    Widget? t(String kind, Map<String, dynamic> data) => notificationTarget(AppNotification(id: 'n', kind: kind, title: '', data: data));
    expect(t('job_answers', {'bizId': 'biz-cafe', 'jobId': _job1, 'matchId': _mSara, 'manage': true}), isA<JobCandidatePage>());
    expect(t('job_apply', {'bizId': 'biz-cafe', 'jobId': _job1, 'manage': true}), isA<JobCandidatesPage>());
    expect(t('job_interview', {'bizId': 'biz-cafe', 'jobId': _job1, 'matchId': _mSara, 'interviewId': 'i', 'manage': true}), isA<JobCandidatePage>());
    final review = t('job_review', {'bizId': 'biz-cafe', 'jobId': _job1});
    expect(review, isA<BusinessDashboardPage>());
    expect((review as BusinessDashboardPage).initialTab, BusinessDashboardPage.jobsTab);
    // بلا manage: ليست وجهة الدائرة (يعالجها جانب الباحث عن عمل)
    expect(t('job_answers', {'bizId': 'biz-cafe', 'jobId': _job1, 'matchId': _mSara}), isNot(isA<JobCandidatePage>()));
  });
}
