import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/media.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/owner/job_candidate_page.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/jobs/job_offer_page.dart';
import 'package:naslook/pages/jobs/job_offers_page.dart';
import 'package:naslook/pages/jobs/job_profile_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

/// اختبارات التوظيف من جهة الباحث عن عمل: ملف «أبحث عن عمل»، بطاقة العرض في تبويب «الطلبات»، أسئلة الفرز وفتح المحادثة،
/// ووجهات الإشعارات.

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _m1 = 'aaaaaaaa-0000-4000-8000-0000000000a1';
const _job1 = 'bbbbbbbb-0000-4000-8000-0000000000b1';
final _now = DateTime.now().toUtc().toIso8601String();

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String status = 'sent';
  String stage = 'new';
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>>? answers;
  final questions = <Map<String, dynamic>>[
    {'id': 'q1', 'text': 'كم سنة خبرتك في المقاهي؟', 'kind': 'text', 'options': [], 'required': true},
    {'id': 'q2', 'text': 'هل تستطيع العمل في الورديات المسائية؟', 'kind': 'yesno', 'options': [], 'required': true},
    {'id': 'q3', 'text': 'الفترة المفضلة', 'kind': 'choice', 'options': ['صباحي', 'مسائي'], 'required': false},
  ];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _job() => {
        'id': _job1, 'bizId': 'biz-brew92', 'title': 'باريستا', 'description': 'نبحث عن باريستا شغوف بالقهوة المختصة.', 'requirements': {'must': ['خبرة سنة في مقهى'], 'nice': ['لاتيه آرت']}, 'skills': ['قهوة مختصة'],
        'city': 'جدة', 'district': 'الحمراء', 'type': 'full', 'experienceMin': 1, 'education': 'none', 'salaryMin': 4000, 'salaryMax': 5500, 'salaryVisible': true, 'openings': 1, 'deadline': null, 'status': 'open', 'public': true,
        'biz': {'id': 'biz-brew92', 'name': 'Brew92', 'nameAr': 'برو 92', 'category': 'cafe', 'logoUrl': null, 'verified': true, 'address': 'شارع الأمير سلطان، جدة', 'city': 'جدة'},
      };
  Map<String, dynamic> _match() => {
        'id': _m1, 'jobId': _job1, 'bizId': 'biz-brew92', 'status': status, 'stage': stage, 'stageLabel': stage == 'screening' ? 'فرز' : stage == 'answered' ? 'أجاب' : 'جديد', 'source': 'match', 'score': .8,
        'reasons': ['المسمّى يطابق', 'نفس المدينة'], 'sentAt': _now, 'answers': answers, 'job': _job(), 'questions': questions, 'assignee': {'id': 'SA0000002', 'nickname': 'sara'}, 'interview': null,
      };
  bool get _inInbox => const ['sent', 'viewed', 'later'].contains(status);
  bool get _active => const ['accepted', 'answered'].contains(status);

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /jobs/profile':
        return _json({'profile': profile, 'pending': status == 'sent' ? 1 : 0, 'total': 1});
      case 'PUT /jobs/profile':
        final b = bodies[key]!;
        if ((b['titles'] as List?)?.isEmpty ?? true) return _json({'error': 'titles-required'}, 400);
        profile = {...b, 'userId': 'SA0000001', 'updatedAt': _now, 'createdAt': _now};
        return _json({'profile': profile});
      case 'DELETE /jobs/profile':
        profile = null;
        return _json({'ok': true});
      case 'GET /jobs/inbox':
        final items = _inInbox ? [_match()] : const [];
        return _json({'items': items, 'pending': _inInbox && status != 'later' ? 1 : 0});
      case 'GET /jobs/mine':
        return _json({'items': [_match()], 'active': _active ? [_match()] : const [], 'history': _active || _inInbox ? const [] : [_match()]});
      case 'GET /jobs/offers/$_m1':
        if (status == 'sent') status = 'viewed';
        return _json(_match());
      case 'POST /jobs/offers/$_m1/accept':
        status = 'accepted';
        stage = 'screening';
        return _json({'ok': true, 'status': 'accepted', 'questions': questions, 'chatWith': null});
      case 'POST /jobs/offers/$_m1/answers':
        status = 'answered';
        stage = 'answered';
        return _json({'ok': true, 'chatWith': {'id': 'SA0000002', 'nickname': 'sara'}});
      case 'POST /jobs/offers/$_m1/later':
        status = 'later';
        return _json({'ok': true});
      case 'POST /jobs/offers/$_m1/decline':
        status = 'declined';
        return _json({'ok': true});
      case 'POST /jobs/offers/$_m1/withdraw':
        status = 'withdrawn';
        stage = 'rejected';
        return _json({'ok': true});
      case 'POST /chat/upload':
        return _json({'url': '/chat/media/cv-abc.pdf', 'type': 'application/pdf', 'kind': 'file', 'size': req.bodyBytes.length});
      case 'GET /requests':
      case 'GET /chats':
      case 'GET /contacts':
      case 'GET /vessels/mine':
      case 'GET /vessels/feed':
      case 'GET /messages/SA0000002':
        return _json([]);
      case 'POST /messages/SA0000002/read':
        return _json({'ok': true});
      case 'GET /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'bio': '', 'avatarUrl': null});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': false, 'admins': 1});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.startsWith('/chat/meta')) return _json({});
    if (path.startsWith('/chat/cards')) return _json({'refs': {}});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home, {double height = 2400}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
}

AppNotification _n(String kind, [Map<String, dynamic> data = const {}]) => AppNotification(id: 'x', kind: kind, title: 't', data: data);

void main() {
  testWidgets('job profile: validation without titles, then saves titles, type, city, experience and CV', (tester) async {
    final srv = _Srv();
    pickJobCvOverride = () async => PickedMedia(Uint8List.fromList(List.filled(32, 1)), 'application/pdf', 'cv.pdf');
    addTearDown(() => pickJobCvOverride = null);
    await _pump(tester, srv, const JobProfilePage(), height: 3000);
    expect(find.text('أبحث عن عمل'), findsOneWidget);
    expect(find.byKey(const Key('jp-delete')), findsNothing, reason: 'لا ملف بعد فلا حذف');
    // الحفظ بلا مسمّى: رسالة تحقق ولا طلب للخادم
    await tester.tap(find.byKey(const Key('jp-save')));
    await tester.pumpAndSettle();
    expect(find.text('أضف مسمّى وظيفياً واحداً على الأقل'), findsWidgets);
    expect(srv.calls.where((c) => c == 'PUT /jobs/profile'), isEmpty);
    // إضافة مسمّى بالإدخال ثم بالفاصلة
    await tester.enterText(find.byKey(const Key('jp-titles')), 'باريستا');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'باريستا'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('jp-skills')), 'قهوة مختصة، خدمة عملاء');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'خدمة عملاء'), findsOneWidget);
    await tester.tap(find.byKey(const Key('jp-type-full')));
    await tester.tap(find.byKey(const Key('jp-city-جدة')));
    await tester.tap(find.byKey(const Key('jp-exp-plus')));
    await tester.tap(find.byKey(const Key('jp-exp-plus')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jp-exp')), findsOneWidget);
    expect((tester.widget(find.byKey(const Key('jp-exp'))) as Text).data, '2');
    // السيرة الذاتية: ترفع عبر /chat/upload ويظهر اسمها مع زر إزالة
    await tester.tap(find.byKey(const Key('jp-cv-pick')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /chat/upload'));
    expect(find.byKey(const Key('jp-cv-name')), findsOneWidget);
    expect(find.byKey(const Key('jp-cv-remove')), findsOneWidget);
    await tester.tap(find.byKey(const Key('jp-save')));
    await tester.pumpAndSettle();
    final b = srv.bodies['PUT /jobs/profile']!;
    expect(b['titles'], ['باريستا']);
    expect(b['skills'], ['قهوة مختصة', 'خدمة عملاء']);
    expect(b['types'], ['full']);
    expect(b['city'], 'جدة');
    expect(b['experienceYears'], 2);
    expect(b['active'], true);
    expect(b['availability'], 'now');
    expect(b['cvUrl'], '/chat/media/cv-abc.pdf');
    expect(b['cvName'], 'cv.pdf');
    expect(find.byKey(const Key('jp-delete')), findsOneWidget, reason: 'بعد الحفظ يمكن حذف الملف');
  });

  testWidgets('requests tab: job card counted in the chip; accept posts then opens the offer page with screening questions', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: ChatsPage()));
    expect(find.text('الطلبات · 1'), findsOneWidget);
    await tester.tap(find.text('الطلبات · 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('job-card-$_m1')), findsOneWidget);
    expect(find.text('التوظيف'), findsOneWidget);
    expect(find.text('باريستا'), findsOneWidget);
    expect(find.text('برو 92 · جدة · دوام كامل'), findsOneWidget);
    expect(find.text('4000 – 5500 ر.س'), findsOneWidget);
    expect(find.text('المسمّى يطابق'), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-accept-$_m1')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /jobs/offers/$_m1/accept'));
    expect(find.byType(JobOfferPage), findsOneWidget);
    expect(find.text('أسئلة الفرز'), findsOneWidget);
    expect(find.byKey(const Key('q-q1')), findsOneWidget);
    expect(find.byKey(const Key('q-q2-yes')), findsOneWidget);
    expect(find.byKey(const Key('q-q3-1')), findsOneWidget);
    expect(find.byKey(const Key('answers-submit')), findsOneWidget);
  });

  testWidgets('offer page: answers validated, posted as {id, value} and the chat thread opens with the #job code', (tester) async {
    final srv = _Srv()
      ..status = 'accepted'
      ..stage = 'screening';
    await _pump(tester, srv, const JobOfferPage(matchId: _m1));
    expect(find.text('باريستا'), findsOneWidget);
    expect(find.byKey(const Key('offer-salary')), findsOneWidget);
    expect(find.text('خبرة سنة في مقهى'), findsOneWidget);
    expect(find.byKey(const Key('offer-accept')), findsNothing, reason: 'بعد القبول لا أزرار رد');
    await tester.tap(find.byKey(const Key('answers-submit')));
    await tester.pumpAndSettle();
    expect(find.text('هذا السؤال إلزامي'), findsNWidgets(2));
    expect(srv.calls.where((c) => c.endsWith('/answers')), isEmpty);
    await tester.enterText(find.byKey(const Key('q-q1')), 'سنتان في مقهى');
    await tester.tap(find.byKey(const Key('q-q2-yes')));
    await tester.tap(find.byKey(const Key('q-q3-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('answers-submit')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /jobs/offers/$_m1/answers'], {
      'answers': [
        {'id': 'q1', 'value': 'سنتان في مقهى'},
        {'id': 'q2', 'value': true},
        {'id': 'q3', 'value': 'مسائي'},
      ],
    });
    expect(find.byType(ChatThreadPage), findsOneWidget);
    expect(find.text('#job/$_job1'), findsOneWidget, reason: 'رمز العرض يملأ المؤلّف ولا يُرسل تلقائياً');
    expect(srv.calls.where((c) => c == 'POST /messages'), isEmpty);
  });

  testWidgets('offers page: inbox tab lists the card, decline asks a reason and posts it, my applications tab is empty', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const JobOffersPage());
    expect(find.text('الواردة · 1'), findsOneWidget);
    expect(find.text('بانتظار ردك'), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-decline-$_m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decline-reason-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decline-confirm')));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /jobs/offers/$_m1/decline'], {'reason': 'المكان بعيد'});
    expect(find.text('لا عروض واردة الآن'), findsOneWidget);
    await tester.tap(find.byKey(const Key('jobs-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('السابقة'), findsOneWidget);
    expect(find.text('اعتذرت'), findsOneWidget);
  });

  testWidgets('my space rows: job profile state and new offers count are live', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: MySpacePage()));
    expect(find.byKey(const Key('jobs-profile')), findsOneWidget);
    expect(find.text('أنشئ ملفك الخاص لتصلك عروض تناسبك'), findsOneWidget);
    expect(find.text('1 عرض جديد بانتظار ردك'), findsOneWidget);
    // ملف موقوف وبلا عروض معلّقة: العناوين الفرعية تتبع المزوّدين
    srv.profile = {'userId': 'SA0000001', 'active': false, 'titles': ['باريستا'], 'city': 'جدة'};
    srv.status = 'declined';
    await _pump(tester, srv, const Scaffold(body: MySpacePage()));
    expect(find.text('موقوف مؤقتاً عن العروض'), findsOneWidget);
    expect(find.text('الواردة وطلباتي'), findsOneWidget);
    srv.profile = {'userId': 'SA0000001', 'active': true, 'titles': ['باريستا', 'كاشير'], 'city': 'جدة'};
    await _pump(tester, srv, const Scaffold(body: MySpacePage()));
    expect(find.text('متاح للعروض · باريستا، كاشير'), findsOneWidget);
  });

  test('notificationTarget and notificationStyle map job kinds', () {
    expect(notificationTarget(_n('job_offer', {'jobId': _job1, 'matchId': _m1, 'bizId': 'biz-brew92'})), isA<JobOfferPage>().having((p) => p.matchId, 'matchId', _m1));
    expect(notificationTarget(_n('job_offer')), isA<JobOffersPage>());
    expect(notificationTarget(_n('job_stage', {'jobId': _job1, 'matchId': _m1, 'stage': 'interview'})), isA<JobOfferPage>());
    expect(notificationTarget(_n('job_interview', {'jobId': _job1})), isA<JobOffersPage>().having((p) => p.initialTab, 'applications tab', 1));
    // الأنواع نفسها موسومة manage تخص فريق التوظيف في الدائرة وتفتح المرشح
    expect(notificationTarget(_n('job_stage', {'jobId': _job1, 'matchId': _m1, 'bizId': 'biz-brew92', 'manage': true})), isA<JobCandidatePage>());
    expect(notificationTarget(_n('job_answers', {'jobId': _job1, 'matchId': _m1, 'bizId': 'biz-brew92', 'manage': true})), isA<JobCandidatePage>());
    expect(notificationStyle('job_offer').icon, Icons.work_outline_rounded);
    expect(notificationStyle('job_interview').icon, Icons.event_available_outlined);
  });
}
