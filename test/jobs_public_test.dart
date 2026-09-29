import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/jobs_models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_jobs.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/jobs/job_offer_page.dart';
import 'package:naslook/pages/jobs/job_page.dart';
import 'package:naslook/pages/jobs/jobs_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _j1 = '11111111-1111-4111-8111-111111111101', _j2 = '11111111-1111-4111-8111-111111111102', _j3 = '11111111-1111-4111-8111-111111111103';
final _ago1d = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
final _in14d = DateTime.now().add(const Duration(days: 14)).toUtc().toIso8601String();

Map<String, dynamic> _bizSummary(String id) => switch (id) {
      'biz-ikea' => {'id': 'biz-ikea', 'name': 'IKEA', 'nameAr': 'ايكيا', 'category': 'retail', 'address': 'طريق الملك عبدالله، جدة', 'city': 'جدة', 'logoUrl': null, 'verified': true},
      'biz-dmm-clinic' => {'id': 'biz-dmm-clinic', 'name': 'Noor Clinic', 'nameAr': 'عيادة نور', 'category': 'clinic', 'address': 'الدمام', 'city': 'الدمام', 'logoUrl': null, 'verified': false},
      _ => {'id': 'biz-brew92', 'name': 'Brew92', 'nameAr': 'برو 92', 'category': 'cafe', 'address': 'شارع الأمير سلطان، جدة', 'city': 'جدة', 'logoUrl': null, 'verified': true},
    };

Map<String, dynamic> _job(String id, {String bizId = 'biz-brew92', String title = 'باريستا', String city = 'جدة', String type = 'shift', String status = 'open', bool salaryVisible = true, List<Map<String, dynamic>> questions = const [], Map<String, dynamic>? mine, bool pub = true}) => {
      'id': id, 'bizId': bizId, 'title': title, 'titleEn': '', 'department': 'التشغيل', 'description': 'تحضير القهوة المختصة وخدمة الزبائن في فرع الأمير سلطان.', 'descriptionEn': '',
      'requirements': {'must': ['خبرة سنة في القهوة المختصة'], 'nice': ['شهادة SCA']}, 'skills': ['لاتيه آرت', 'إسبريسو'], 'city': city, 'district': 'الروضة', 'type': type, 'experienceMin': 1, 'education': 'secondary',
      'salaryMin': salaryVisible ? 4500 : null, 'salaryMax': salaryVisible ? 6000 : null, 'salaryVisible': salaryVisible, 'openings': 2, 'deadline': _in14d, 'status': status, 'public': true, 'views': 48,
      'publishedAt': status == 'open' ? _ago1d : null, 'closedAt': null, 'createdAt': _ago1d, 'updatedAt': _ago1d,
      if (pub) 'biz': _bizSummary(bizId), if (pub) 'mine': mine, if (!pub) 'questions': questions,
    };

/// دائرة كاملة لصفحة الدائرة (كما في business_offers_test).
Map<String, dynamic> _biz() => {
      'id': 'biz-brew92', 'name': 'Brew92', 'nameAr': 'برو 92', 'category': 'cafe', 'sector': 'قهوة مختصة', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2,
      'address': 'شارع الأمير سلطان، جدة', 'hours': '24 ساعة', 'phone': null, 'website': null, 'color': '#3A2E2A', 'highlights': [], 'verified': true, 'official': false,
      'followers': 128, 'rating': 4.7, 'ratingCount': 40, 'minPrice': 1500, 'itemsCount': 0, 'following': false, 'offers': 0, 'offerEndsAt': null, 'myRole': null, 'ownerId': null,
      'items': [], 'reviews': [], 'myOrders': [], 'posts': [],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  /// حالتي على الوظيفة الأولى (null = لم أتقدّم) وأسئلتها، وهل لديّ ملف توظيف.
  Map<String, dynamic>? mine;
  List<Map<String, dynamic>> questions = [
    {'id': 'q1', 'text': 'هل لديك خبرة في ماكينات الإسبريسو؟', 'kind': 'yesno', 'options': [], 'required': true},
  ];
  bool hasProfile = true;
  String pendingStatus = 'pending';
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(req.url.query.isEmpty ? key : '$key?${req.url.query}');
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /settings/public') return _json({'announcement': '', 'maintenance': false, 'jobsEnabled': true});
    if (key == 'GET /jobs/profile') return _json({'profile': hasProfile ? {'userId': 'SA0000001', 'active': true, 'titles': ['باريستا'], 'city': 'جدة'} : null, 'pending': 0, 'total': 0});
    if (key == 'GET /jobs') {
      final type = req.url.queryParameters['type'] ?? '', city = req.url.queryParameters['city'] ?? '', bizId = req.url.queryParameters['bizId'] ?? '';
      final all = [
        _job(_j1, mine: mine),
        _job(_j2, bizId: 'biz-ikea', title: 'مستشار مبيعات', type: 'full', salaryVisible: false),
        _job(_j3, bizId: 'biz-dmm-clinic', title: 'موظف استقبال', city: 'الدمام', type: 'part', salaryVisible: false, mine: {'matchId': 'm-3', 'status': 'answered', 'stage': 'interview'}),
      ];
      final items = all.where((j) => (type.isEmpty || j['type'] == type) && (city.isEmpty || j['city'] == city) && (bizId.isEmpty || j['bizId'] == bizId)).toList();
      return _json({'items': items, 'types': [], 'cities': ['جدة', 'الدمام']});
    }
    if (key == 'GET /jobs/hiring') return _json({'items': [{'bizId': 'biz-brew92', 'open': 2}]});
    if (key == 'GET /biz/biz-brew92/jobs') return _json({'items': [_job(_j1), _job('11111111-1111-4111-8111-111111111104', title: 'مشرف فرع', type: 'full')]});
    if (key == 'GET /jobs/$_j1') { final j = _job(_j1, mine: mine, questions: questions); if (mine != null) j['questions'] = questions; return _json(j); }
    if (key == 'POST /jobs/$_j1/apply') {
      if (!hasProfile) return _json({'error': 'profile-required'}, 409);
      final answered = questions.isEmpty;
      mine = {'matchId': 'm-1', 'status': answered ? 'answered' : 'accepted', 'stage': answered ? 'answered' : 'screening'};
      return _json({'ok': true, 'matchId': 'm-1', 'status': mine!['status'], 'questions': questions, 'chatWith': answered ? {'id': 'SA0000002', 'nickname': 'sara'} : null});
    }
    if (key == 'GET /biz/biz-brew92') return _json(_biz());
    if (key == 'GET /biz/biz-brew92/community') return _json({'posts': [], 'total': 0, 'members': 0, 'canModerate': false, 'hasMore': false, 'topItems': []});
    // الإدارة
    if (key == 'GET /adminapi/status') return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': true, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'admins': 1});
    if (key == 'GET /adminapi/jobs') {
      final status = req.url.queryParameters['status'] ?? '';
      final all = [
        {..._job(_j3, bizId: 'biz-dmm-clinic', title: 'موظف استقبال', city: 'الدمام', type: 'part', status: pendingStatus, pub: false), 'bizName': 'عيادة نور', 'counts': {'sent': 0, 'viewed': 0, 'accepted': 0, 'answered': 0, 'declined': 0, 'byStage': {}}, 'plan': 'free'},
        {..._job(_j1, pub: false), 'bizName': 'برو 92', 'counts': {'sent': 5, 'viewed': 4, 'accepted': 2, 'answered': 1, 'declined': 1, 'byStage': {'hired': 0}}, 'plan': 'pro'},
      ];
      return _json({'items': all.where((j) => status.isEmpty || j['status'] == status).toList(), 'totals': {'open': 1, 'pending': pendingStatus == 'pending' ? 1 : 0, 'seekers': 37, 'hired': 4}, 'settings': {'jobsEnabled': true, 'jobsFreeActive': 3, 'jobsWeeklyCap': 5, 'jobsMinScore': .45, 'jobsRequireApproval': true}});
    }
    if (key == 'POST /adminapi/jobs/$_j3/approve') { pendingStatus = 'open'; return _json({..._job(_j3, status: 'open', pub: false), 'matched': {'sent': 3, 'considered': 9, 'capped': false}}); }
    if (key == 'POST /adminapi/jobs/$_j1/close') return _json({'ok': true});
    if (key == 'PUT /adminapi/jobs/plans/biz-brew92') return _json({'plan': bodies[key]!['plan'], 'until': null, 'freeActive': 3, 'active': 1});
    if (key == 'GET /adminapi/settings') return _json({'testTopup': false, 'maxTopup': 100000, 'announcement': '', 'maintenance': false, 'supportHandle': '', 'supportEmail': '', 'bannedWords': '', 'reportThreshold': 3, 'jobsEnabled': true, 'jobsFreeActive': 3, 'jobsWeeklyCap': 5, 'jobsMinScore': .45, 'jobsRequireApproval': false});
    if (key == 'POST /adminapi/settings') return _json({...bodies[key]!});
    if (key == 'GET /adminapi/admins') return _json([]);
    if (key == 'GET /adminapi/payments/config') return _json({'enabled': false, 'provider': 'moyasar', 'mode': null, 'source': null, 'envPresent': false, 'publishableKey': null, 'secretKeySet': false, 'secretKeyHint': '', 'webhookSecretSet': false, 'panelKeysSet': false, 'webhookUrl': '', 'returnUrl': ''});
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/wishlist')) return _json({'items': []});
    if (path == '/contacts') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(800, 2400)}) async {
  tester.view.physicalSize = size;
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
  test('Job model: salary text, applied state and labels', () {
    final j = Job.fromJson(_job(_j1, mine: {'matchId': 'm', 'status': 'answered', 'stage': 'screening'}));
    expect(j.salaryText, '4500 – 6000 ر.س');
    expect(j.mine!.applied, isTrue);
    expect(j.typeLabel, 'ورديات');
    expect(j.biz!.title, 'برو 92');
    expect(Job.fromJson(_job(_j2, salaryVisible: false)).salaryText, '');
    expect(JobMine.fromJson({'status': 'sent', 'stage': 'new'}).applied, isFalse);
    expect(adminSections.last.$1, 'jobs');
  });

  testWidgets('jobs list renders items and filters by type chip', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobsPage());
    expect(find.text('باريستا'), findsOneWidget);
    expect(find.text('مستشار مبيعات'), findsOneWidget);
    expect(find.text('موظف استقبال'), findsOneWidget);
    // الراتب يظهر فقط حين يسمح صاحب العرض، وشارة «تقدّمت» على وظيفة تقدّمت عليها
    expect(find.text('4500 – 6000 ر.س'), findsOneWidget);
    expect(find.byKey(const Key('job-applied-badge')), findsOneWidget);
    expect(find.byKey(const Key('jobs-city-الدمام')), findsOneWidget);
    await tester.tap(find.byKey(const Key('jobs-type-part')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /jobs?type=part'));
    expect(find.text('موظف استقبال'), findsOneWidget);
    expect(find.text('باريستا'), findsNothing);
    // فتح الوظيفة من البطاقة
    await tester.tap(find.byKey(const Key('jobs-type-part')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('job-$_j1')));
    await tester.pumpAndSettle();
    expect(find.byType(JobPage), findsOneWidget);
    expect(find.byKey(const Key('job-apply')), findsOneWidget);
  });

  testWidgets('jobs list empty state invites to create the job profile', (tester) async {
    final srv = _Srv()..hasProfile = false;
    await _pump(tester, srv, const JobsPage(bizId: 'biz-none', title: 'دائرة'));
    expect(find.text('لا وظائف شاغرة الآن'), findsOneWidget);
    expect(find.byKey(const Key('jobs-profile-cta')), findsOneWidget);
  });

  testWidgets('job page applies, pushes the offer page when questions are returned', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobPage(id: _j1));
    expect(find.text('باريستا'), findsOneWidget);
    expect(find.byKey(const Key('job-biz')), findsOneWidget);
    expect(find.byKey(const Key('job-salary')), findsOneWidget);
    expect(find.text('خبرة سنة في القهوة المختصة'), findsOneWidget);
    expect(find.byKey(const Key('job-share')), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-apply')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /jobs/$_j1/apply'));
    expect(find.byType(JobOfferPage), findsOneWidget);
    // العودة: الشريط السفلي يعرض حالتي بدل زر التقديم
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('job-apply')), findsNothing);
    expect(find.textContaining('تقدّمت'), findsWidgets);
  });

  testWidgets('job page without questions opens the chat with the hiring contact', (tester) async {
    final srv = _Srv()..questions = [];
    await _pump(tester, srv, const JobPage(id: _j1));
    await tester.tap(find.byKey(const Key('job-apply')));
    await tester.pumpAndSettle();
    expect(find.byType(JobOfferPage), findsNothing);
    // فُتحت المحادثة مع المسؤول (تطلب الرسائل)
    expect(srv.calls.any((c) => c.startsWith('GET /messages/SA0000002')), isTrue);
  });

  testWidgets('job page: profile-required shows the profile dialog', (tester) async {
    final srv = _Srv()..hasProfile = false;
    await _pump(tester, srv, const JobPage(id: _j1));
    await tester.tap(find.byKey(const Key('job-apply')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /jobs/$_j1/apply'));
    expect(find.text('أكمل ملفك أولاً'), findsOneWidget);
    expect(find.byKey(const Key('job-go-profile')), findsOneWidget);
  });

  testWidgets('job page shows the invitation when a card was sent to me', (tester) async {
    final srv = _Srv()..mine = {'matchId': 'm-9', 'status': 'sent', 'stage': 'new'};
    await _pump(tester, srv, const JobPage(id: _j1));
    expect(find.byKey(const Key('job-invited')), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-open-offer')));
    await tester.pumpAndSettle();
    expect(find.byType(JobOfferPage), findsOneWidget);
  });

  testWidgets('business page shows the jobs entry when the circle has open jobs', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: 'biz-brew92'));
    expect(srv.calls, contains('GET /biz/biz-brew92/jobs'));
    expect(find.byKey(const Key('jobs-entry')), findsOneWidget);
    expect(find.text('وظيفتان شاغرتان'), findsOneWidget);
    await tester.tap(find.byKey(const Key('jobs-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    expect(srv.calls, contains('GET /jobs?bizId=biz-brew92'));
  });

  testWidgets('admin jobs page approves a pending job and filters by status', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: AdminJobsPage()));
    expect(find.text('موظف استقبال'), findsOneWidget);
    expect(find.text('بانتظار الموافقة'), findsWidgets);
    await tester.tap(find.byKey(const Key('admin-job-approve-$_j3')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /adminapi/jobs/$_j3/approve'));
    expect(find.byKey(const Key('admin-job-approve-$_j3')), findsNothing);
    await tester.tap(find.byKey(const Key('admin-jobs-filter-open')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('GET /adminapi/jobs?status=open'));
    // الإغلاق بسبب
    await tester.tap(find.byKey(const Key('admin-job-close-$_j1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'مخالف للسياسة');
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/jobs/$_j1/close']!['reason'], 'مخالف للسياسة');
    // الباقة
    await tester.tap(find.byKey(const Key('admin-job-plan-$_j1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-job-plan-pro')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-job-plan-months')), '3');
    await tester.tap(find.byKey(const Key('admin-job-plan-save')));
    await tester.pumpAndSettle();
    expect(srv.bodies['PUT /adminapi/jobs/plans/biz-brew92'], {'plan': 'pro', 'months': 3});
  });

  testWidgets('admin settings saves the jobs keys', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()), size: const Size(600, 3600));
    expect(find.byKey(const Key('set-jobs-enabled')), findsOneWidget);
    await tester.tap(find.byKey(const Key('set-jobs-approval')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('set-jobs-free')), '5');
    await tester.tap(find.byKey(const Key('set-save')));
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /adminapi/settings']!;
    expect(b['jobsEnabled'], isTrue);
    expect(b['jobsRequireApproval'], isTrue);
    expect(b['jobsFreeActive'], 5);
    expect(b['jobsWeeklyCap'], 5);
    expect(b['jobsMinScore'], closeTo(.45, .001));
  });
}
