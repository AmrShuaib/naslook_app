// «عرّف بنفسك بالصوت» في تعديل الملف (lib/pages/profile/voice_fill_sheet.dart، server/profile_voice.js): الزر يختفي حين لا يتاح
// المساعد، الموافقة مرة واحدة، كتابة النص وتوزيعه على الحقول بشارة زرقاء «من كلامك» وصفراء «تأكّد من الكتابة»، ما لم يُذكر
// لا يُمس، لا PUT قبل «حفظ»، الميكروفون حيث يُدعم الإملاء فقط، رسائل الأخطاء، ولا تجاوز في شاشة صغيرة بخط كبير.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/profile_voice_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/speech/dictation.dart';
import 'package:naslook/pages/profile/edit_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _FakeDictation implements Dictation {
  static _FakeDictation? last;
  DictationText? onText;
  void Function()? onEnd;
  int starts = 0, stops = 0;
  _FakeDictation() {
    last = this;
  }
  @override
  bool get active => onText != null;
  @override
  Future<void> start({required DictationText onText, void Function(Object error)? onError, void Function()? onEnd}) async {
    starts++;
    this.onText = onText;
    this.onEnd = onEnd;
  }

  @override
  Future<void> stop() async {
    stops++;
    onText = null;
    onEnd?.call();
  }

  @override
  void dispose() {}
}

const _speech = 'أنا فهد الغامدي مصوّر منتجات، وحسابي في انستقرام fahad.shots';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool available = true, consented = false, statusFails = false;
  String accountType = 'personal';
  List<Map<String, dynamic>> links = [];

  /// رد POST /me/profile/voice: (رمز الحالة، الجسم)
  (int, Map<String, dynamic>) voice = (200, {
    'fields': {
      'displayName': 'فهد الغامدي',
      'jobTitle': 'مصوّر',
      'skills': ['تصوير منتجات', 'مونتاج'],
      'links': [{'kind': 'instagram', 'value': 'fahad.shots'}],
    },
    'unsure': ['links.instagram'],
  });
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Iterable<String> get writes => calls.where((c) => c.startsWith('PUT ') || c.startsWith('PATCH '));

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /me/profile/voice/status':
        if (statusFails) return _json({'error': 'not-found'}, 404);
        return _json({'available': available, 'consented': consented, 'limits': {'minChars': 20, 'maxChars': 1500, 'maxSec': 60, 'perHour': 6, 'perDay': 20}});
      case 'POST /me/ai-consent':
        consented = true;
        return _json({'ok': true, 'feature': 'profile_voice', 'consented': true});
      case 'DELETE /me/ai-consent':
        consented = false;
        return _json({'ok': true, 'consented': false});
      case 'POST /me/profile/voice':
        return _json(voice.$2, voice.$1);
      case 'GET /me/profile/v2':
        return _json({
          'id': 'SA0000001', 'nickname': 'amr', 'displayName': 'عمرو', 'avatarUrl': null, 'coverUrl': null, 'bio': 'نبذة', 'accountType': accountType, 'jobTitle': '', 'city': 'جدة', 'district': 'الشاطئ',
          'links': links, 'intro': null, 'stats': {}, 'trust': {}, 'flags': {'isMe': true}, 'settings': {}, 'completion': {'pct': 60, 'steps': []},
        });
      case 'PUT /me/profile/v2':
        return _json({'ok': true});
      case 'GET /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'bio': 'نبذة', 'skills': ['مونتاج'], 'hobbies': ['قهوة'], 'lookingFor': [], 'accountType': 'personal', 'isPublic': true});
      case 'PUT /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr'});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {_Srv? srv, Size size = const Size(420, 2200), double scale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
      home: const EditProfilePage(),
    ),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// يفتح ورقة الكلام (مع الموافقة إن لزمت).
Future<void> _open(WidgetTester tester, {bool consent = true}) async {
  await tester.ensureVisible(find.byKey(const Key('voice-fill')));
  await tester.tap(find.byKey(const Key('voice-fill')));
  await _settle(tester);
  if (consent) {
    await tester.tap(find.byKey(const Key('voice-consent-ok')));
    await _settle(tester);
  }
}

Future<void> _apply(WidgetTester tester, [String text = _speech]) async {
  await tester.enterText(find.byKey(const Key('voice-text')), text);
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('voice-apply')));
  await tester.tap(find.byKey(const Key('voice-apply')));
  await _settle(tester);
}

String _field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
String _tagText(WidgetTester tester, String field) => tester.widget<Text>(find.descendant(of: find.byKey(Key('voice-tag-$field')), matching: find.byType(Text))).data!;

void main() {
  tearDown(() {
    Dictation.factoryOverride = null;
    _FakeDictation.last = null;
  });

  group('models', () {
    test('VoiceFillResult.fromJson keeps only stated fields and tolerates junk', () {
      final r = VoiceFillResult.fromJson({
        'fields': {'displayName': ' فهد ', 'bio': '', 'city': 5, 'skills': ['طبخ', 3, ''], 'links': [{'kind': 'x', 'value': 'amr'}, {'kind': 'x'}, 'bad']},
        'unsure': ['links.x', 7],
      });
      expect(r.displayName, 'فهد');
      expect(r.bio, isNull);
      expect(r.city, isNull);
      expect(r.skills, ['طبخ']);
      expect(r.links.single.field, 'links.x');
      expect(r.unsure, {'links.x'});
      expect(r.isEmpty, isFalse);
      expect(VoiceFillResult.fromJson({'fields': {}, 'unsure': []}).isEmpty, isTrue);
      expect(VoiceFillResult.fromJson(const {}).isEmpty, isTrue);
      expect(VoiceFillStatus.fromJson(const {}).available, isFalse);
    });

    test('error texts are Arabic and specific', () {
      String t(int code, Map<String, dynamic> body) => profileVoiceErrText(ApiException(code, 'x', body: body));
      expect(t(429, {'error': 'rate-limited', 'scope': 'hour', 'retryAfterSec': 1500}), contains('25 دقيقة'));
      expect(t(429, {'error': 'rate-limited', 'scope': 'day'}), contains('غداً'));
      expect(t(503, {'error': 'ai-unavailable'}), contains('غير مفعّل'));
      expect(t(503, {'error': 'busy'}), contains('مشغولة'));
      expect(t(400, {'error': 'text-too-short'}), contains('قصير'));
      expect(t(403, {'error': 'ai-consent-required'}), contains('موافقتك'));
      expect(profileVoiceErrText(const ApiException(0, 'تعذر الاتصال بالخادم')), contains('الإنترنت'));
      expect(profileVoiceErrText(StateError('x')), contains('تعذّر'));
    });
  });

  group('button', () {
    testWidgets('shown above the fields when the assistant is available', (tester) async {
      final srv = await _pump(tester);
      expect(srv.calls, contains('GET /me/profile/voice/status'));
      expect(find.byKey(const Key('voice-fill')), findsOneWidget);
      expect(find.text('عرّف بنفسك بالصوت'), findsOneWidget);
      expect(find.text('تكلّم 30 ثانية ونعبّئ الحقول عنك'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('voice-fill'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('edit-name'))).dy));
    });

    testWidgets('hidden when the server says unavailable', (tester) async {
      await _pump(tester, srv: _Srv()..available = false);
      expect(find.byKey(const Key('voice-fill')), findsNothing);
      expect(find.byKey(const Key('edit-name')), findsOneWidget);
    });

    testWidgets('hidden silently when the status call fails', (tester) async {
      await _pump(tester, srv: _Srv()..statusFails = true);
      expect(find.byKey(const Key('voice-fill')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(_field(tester, 'edit-name'), 'عمرو');
    });
  });

  group('consent', () {
    testWidgets('shown once with the approved text, stored, then skipped', (tester) async {
      final srv = await _pump(tester);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsOneWidget);
      expect(find.text('قبل أن تبدأ'), findsOneWidget);
      expect(find.text('سنحوّل كلامك إلى نص، ثم يقرؤه مساعد ذكي (Claude من Anthropic) ليوزعه على حقول ملفك.'), findsOneWidget);
      expect(find.textContaining('لا يُحفظ شيء قبل أن تراجعه'), findsOneWidget);
      expect(find.textContaining('لتعبئة ملفك فقط'), findsOneWidget);
      expect(find.textContaining('التسجيل نفسه لا يُحتفظ به'), findsOneWidget);
      expect(srv.calls, isNot(contains('POST /me/ai-consent')), reason: 'لا موافقة قبل الضغط');
      await tester.tap(find.byKey(const Key('voice-consent-ok')));
      await _settle(tester);
      expect(srv.bodies['POST /me/ai-consent']!['feature'], 'profile_voice');
      expect(find.byKey(const Key('voice-consent')), findsNothing);
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
      // إغلاق الورقة ثم فتحها: لا موافقة ثانية
      Navigator.of(tester.element(find.byKey(const Key('voice-sheet')))).pop();
      await _settle(tester);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsNothing);
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
      expect(srv.calls.where((c) => c == 'POST /me/ai-consent').length, 1);
    });

    testWidgets('a user who already consented goes straight to the talk sheet', (tester) async {
      final srv = await _pump(tester, srv: _Srv()..consented = true);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsNothing);
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
      expect(srv.calls, isNot(contains('POST /me/ai-consent')));
    });

    testWidgets('declining stores nothing and opens nothing', (tester) async {
      final srv = await _pump(tester);
      await _open(tester, consent: false);
      await tester.tap(find.byKey(const Key('voice-consent-no')));
      await _settle(tester);
      expect(find.byKey(const Key('voice-sheet')), findsNothing);
      expect(srv.calls, isNot(contains('POST /me/ai-consent')));
      expect(srv.calls, isNot(contains('POST /me/profile/voice')));
      // السؤال يعود في المرة القادمة
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsOneWidget);
    });

    testWidgets('withdrawing from the talk sheet deletes the consent and asks again next time', (tester) async {
      final srv = await _pump(tester, srv: _Srv()..consented = true);
      await _open(tester, consent: false);
      await tester.ensureVisible(find.byKey(const Key('voice-consent-withdraw')));
      await tester.tap(find.byKey(const Key('voice-consent-withdraw')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /me/ai-consent?feature=profile_voice'));
      expect(find.byKey(const Key('voice-sheet')), findsNothing);
      expect(find.textContaining('سُحبت موافقتك'), findsOneWidget);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsOneWidget);
    });
  });

  group('fill', () {
    testWidgets('typed text fills the stated fields with tags, leaves the rest, and nothing is saved until save', (tester) async {
      final srv = await _pump(tester);
      await _open(tester);
      expect(find.byKey(const Key('voice-mic')), findsNothing, reason: 'لا إملاء في هذه المنصة: الكتابة وحدها');
      expect(find.text('اكتب عن نفسك'), findsOneWidget);
      await _apply(tester);
      expect(srv.bodies['POST /me/profile/voice']!['text'], _speech);
      expect(find.byKey(const Key('voice-sheet')), findsNothing, reason: 'الورقة تُغلق بعد الترتيب');
      // ما ذُكر
      expect(_field(tester, 'edit-name'), 'فهد الغامدي');
      expect(_tagText(tester, 'displayName'), 'من كلامك');
      expect(find.text('تصوير منتجات'), findsOneWidget);
      expect(find.text('مونتاج'), findsOneWidget, reason: 'المهارة الموجودة لا تتكرر');
      expect(_tagText(tester, 'skills'), 'من كلامك');
      expect(_field(tester, 'link-value-0'), 'fahad.shots');
      expect(_tagText(tester, 'links.instagram'), 'تأكّد من الكتابة', reason: 'اسم الحساب غير مؤكد: أصفر');
      final blue = tester.widget<TextField>(find.byKey(const Key('edit-name'))).decoration!;
      final yellow = tester.widget<TextField>(find.byKey(const Key('link-value-0'))).decoration!;
      expect(blue.fillColor, isNot(yellow.fillColor));
      expect(blue.fillColor, isNotNull);
      // ما لم يُذكر
      expect(_field(tester, 'edit-bio'), 'نبذة');
      expect(find.byKey(const Key('voice-tag-bio')), findsNothing);
      expect(find.byKey(const Key('voice-tag-city')), findsNothing);
      expect(find.byKey(const Key('voice-tag-district')), findsNothing);
      expect(find.byKey(const Key('edit-job')), findsNothing, reason: 'الحساب شخصي: المسمى لا يُبدّل نوع الحساب');
      expect(find.byKey(const Key('voice-tag-jobTitle')), findsNothing);
      // لا حفظ بعد
      expect(srv.writes, isEmpty, reason: 'لا شيء يُحفظ قبل زر الحفظ');
      expect(find.byType(EditProfilePage), findsOneWidget);
      // الحفظ يرسل ما في الحقول
      await tester.tap(find.byKey(const Key('edit-save')));
      await _settle(tester);
      expect(srv.bodies['PUT /me/profile']!['skills'], ['مونتاج', 'تصوير منتجات']);
      expect(srv.bodies['PUT /me/profile']!['bio'], 'نبذة');
      final v2 = srv.bodies['PUT /me/profile/v2']!;
      expect(v2['displayName'], 'فهد الغامدي');
      expect(v2['city'], 'جدة');
      expect(v2['district'], 'الشاطئ');
      expect(v2['jobTitle'], '');
      expect(v2['links'], [{'kind': 'instagram', 'value': 'fahad.shots'}]);
    });

    testWidgets('editing a filled field clears its tag only', (tester) async {
      await _pump(tester, srv: _Srv()..consented = true);
      await _open(tester, consent: false);
      await _apply(tester);
      expect(find.byKey(const Key('voice-tag-displayName')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('edit-name')), 'فهد');
      await tester.pump();
      expect(find.byKey(const Key('voice-tag-displayName')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('edit-name'))).decoration!.enabledBorder, isNull);
      expect(find.byKey(const Key('voice-tag-links.instagram')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('link-value-0')), 'fahad_shots');
      await tester.pump();
      expect(find.byKey(const Key('voice-tag-links.instagram')), findsNothing);
      expect(find.byKey(const Key('voice-tag-skills')), findsOneWidget);
    });

    testWidgets('a pro account gets the job title; a said value overwrites, an existing link of the kind is replaced, city change keeps a valid district', (tester) async {
      final srv = _Srv()
        ..consented = true
        ..accountType = 'pro'
        ..links = [{'kind': 'instagram', 'value': 'old_name'}, {'kind': 'website', 'value': 'amr.sa'}]
        ..voice = (200, {
          'fields': {'jobTitle': 'مصوّر', 'bio': 'أصوّر المنتجات والمقاهي', 'city': 'الدمام', 'links': [{'kind': 'instagram', 'value': 'fahad.shots'}, {'kind': 'x', 'value': 'fahad_x'}, {'kind': 'tiktok', 'value': 'fahad_t'}]},
          'unsure': ['links.instagram', 'links.x', 'links.tiktok', 'bio'],
        });
      await _pump(tester, srv: srv);
      await _open(tester, consent: false);
      await _apply(tester);
      expect(_field(tester, 'edit-job'), 'مصوّر');
      expect(_tagText(tester, 'jobTitle'), 'من كلامك');
      expect(_field(tester, 'edit-bio'), 'أصوّر المنتجات والمقاهي');
      expect(_tagText(tester, 'bio'), 'تأكّد من الكتابة');
      expect(_tagText(tester, 'city'), 'من كلامك');
      expect(_field(tester, 'edit-name'), 'عمرو', reason: 'الاسم لم يُذكر');
      expect(_field(tester, 'link-value-0'), 'fahad.shots', reason: 'رابط النوع نفسه يُستبدل');
      expect(_field(tester, 'link-value-1'), 'amr.sa', reason: 'رابط لم يُذكر يبقى');
      expect(_field(tester, 'link-value-2'), 'fahad_x');
      expect(find.byKey(const Key('link-value-3')), findsNothing, reason: 'ثلاثة روابط على الأكثر');
      expect(find.byKey(const Key('voice-tag-links.tiktok')), findsNothing);
      await tester.tap(find.byKey(const Key('edit-save')));
      await _settle(tester);
      final v2 = srv.bodies['PUT /me/profile/v2']!;
      expect(v2['city'], 'الدمام');
      expect(v2['district'], 'الشاطئ', reason: 'الشاطئ حي في الدمام أيضاً فيبقى');
      expect(v2['jobTitle'], 'مصوّر');
    });

    testWidgets('values equal to what is already there change nothing', (tester) async {
      final srv = _Srv()
        ..consented = true
        ..voice = (200, {'fields': {'displayName': 'عمرو', 'city': 'جدة', 'skills': ['مونتاج']}, 'unsure': []});
      await _pump(tester, srv: srv);
      await _open(tester, consent: false);
      await _apply(tester);
      expect(find.byKey(const Key('voice-tag-displayName')), findsNothing);
      expect(find.byKey(const Key('voice-tag-city')), findsNothing);
      expect(find.byKey(const Key('voice-tag-skills')), findsNothing);
      expect(find.textContaining('لم يتغيّر شيء'), findsOneWidget);
    });
  });

  group('dictation', () {
    testWidgets('mic appears only where dictation is supported, starts listening, and dictated text lands in the editable box', (tester) async {
      Dictation.factoryOverride = _FakeDictation.new;
      final srv = await _pump(tester, srv: _Srv()..consented = true);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-mic')), findsOneWidget);
      expect(find.text('تكلّم الآن'), findsOneWidget);
      expect(find.byKey(const Key('voice-bars')), findsOneWidget);
      final d = _FakeDictation.last!;
      expect(d.starts, 1, reason: 'الاستماع يبدأ مع فتح الورقة');
      expect(find.textContaining('/ 1:00'), findsOneWidget);
      d.onText!('أنا فهد', false);
      await tester.pump();
      expect(_field(tester, 'voice-text'), 'أنا فهد');
      d.onText!('أنا فهد الغامدي مصوّر', true);
      await tester.pump();
      expect(_field(tester, 'voice-text'), 'أنا فهد الغامدي مصوّر ');
      // الإيقاف ثم تعديل باليد ثم متابعة الكلام: المكتوب يبقى
      await tester.tap(find.byKey(const Key('voice-mic')));
      await tester.pump();
      expect(d.stops, 1);
      await tester.enterText(find.byKey(const Key('voice-text')), 'أنا فهد الغامدي مصوّر منتجات');
      await tester.tap(find.byKey(const Key('voice-mic')));
      await tester.pump();
      expect(d.starts, 2);
      d.onText!('من جدة', true);
      await tester.pump();
      expect(_field(tester, 'voice-text'), 'أنا فهد الغامدي مصوّر منتجات من جدة ');
      await tester.ensureVisible(find.byKey(const Key('voice-apply')));
      await tester.tap(find.byKey(const Key('voice-apply')));
      await _settle(tester);
      expect(d.stops, 2, reason: 'الترتيب يوقف الاستماع');
      expect(srv.bodies['POST /me/profile/voice']!['text'], 'أنا فهد الغامدي مصوّر منتجات من جدة');
      expect(_field(tester, 'edit-name'), 'فهد الغامدي');
    });

    testWidgets('silence ends listening; the mic stops by itself at 60 seconds and the box stays editable', (tester) async {
      Dictation.factoryOverride = _FakeDictation.new;
      await _pump(tester, srv: _Srv()..consented = true);
      await _open(tester, consent: false);
      final d = _FakeDictation.last!;
      expect(tester.widget<TextField>(find.byKey(const Key('voice-text'))).enabled, isTrue);
      d.onEnd!();
      await tester.pump();
      expect(find.text('اضغط الميكروفون لتتكلم'), findsOneWidget, reason: 'الصمت أنهى الاستماع');
      final before = tester.widget<Text>(find.byKey(const Key('voice-timer'))).data!;
      await tester.pump(const Duration(seconds: 5));
      expect(tester.widget<Text>(find.byKey(const Key('voice-timer'))).data, before, reason: 'المؤقّت يعدّ زمن الاستماع فقط');
      await tester.tap(find.byKey(const Key('voice-mic')));
      await tester.pump();
      expect(d.starts, 2);
      final stops = d.stops;
      for (var i = 0; i < 62; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(d.stops, stops + 1, reason: 'توقف تلقائياً عند الدقيقة');
      expect(find.text('1:00 / 1:00'), findsOneWidget);
      expect(find.textContaining('انتهت الدقيقة'), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-mic')));
      await tester.pump();
      expect(d.starts, 2, reason: 'لا استماع بعد الحد');
      await tester.enterText(find.byKey(const Key('voice-text')), 'أكمل كتابة');
      expect(_field(tester, 'voice-text'), 'أكمل كتابة');
    });
  });

  group('errors', () {
    Future<_Srv> open(WidgetTester tester, (int, Map<String, dynamic>) voice) async {
      final srv = _Srv()
        ..consented = true
        ..voice = voice;
      await _pump(tester, srv: srv);
      await _open(tester, consent: false);
      return srv;
    }

    String err(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('voice-error'))).data!;

    testWidgets('too short is caught before any request', (tester) async {
      final srv = await open(tester, (200, {'fields': {}, 'unsure': []}));
      await _apply(tester, 'أنا فهد');
      expect(err(tester), contains('قصير'));
      expect(srv.calls, isNot(contains('POST /me/profile/voice')));
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
      // الكتابة تمسح الخطأ
      await tester.enterText(find.byKey(const Key('voice-text')), 'أنا فهد الغامدي');
      await tester.pump();
      expect(find.byKey(const Key('voice-error')), findsNothing);
    });

    testWidgets('nothing understood keeps the sheet open with the text', (tester) async {
      final srv = await open(tester, (200, {'fields': {}, 'unsure': []}));
      await _apply(tester);
      expect(err(tester), contains('لم نفهم'));
      expect(_field(tester, 'voice-text'), _speech);
      expect(_field(tester, 'edit-name'), 'عمرو');
      expect(srv.writes, isEmpty);
    });

    testWidgets('hourly limit', (tester) async {
      await open(tester, (429, {'error': 'rate-limited', 'scope': 'hour', 'retryAfterSec': 600}));
      await _apply(tester);
      expect(err(tester), 'محاولات كثيرة. أعد المحاولة بعد 10 دقيقة.');
    });

    testWidgets('daily limit', (tester) async {
      await open(tester, (429, {'error': 'rate-limited', 'scope': 'day', 'retryAfterSec': 40000}));
      await _apply(tester);
      expect(err(tester), contains('حد اليوم'));
    });

    testWidgets('assistant unavailable', (tester) async {
      await open(tester, (503, {'error': 'ai-unavailable'}));
      await _apply(tester);
      expect(err(tester), contains('غير مفعّل'));
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
    });

    testWidgets('model failure is a plain retry message', (tester) async {
      await open(tester, (502, {'error': 'ai-failed'}));
      await _apply(tester);
      expect(err(tester), contains('أعد المحاولة'));
    });
  });

  group('layout', () {
    testWidgets('no overflow at 360x640 with text scale 1.6 through the whole flow', (tester) async {
      Dictation.factoryOverride = _FakeDictation.new;
      final srv = _Srv()
        ..accountType = 'pro'
        ..voice = (200, {
          'fields': {'displayName': 'فهد الغامدي', 'bio': 'أصوّر المنتجات والمقاهي في جدة', 'jobTitle': 'مصوّر', 'city': 'الدمام', 'district': 'الفيصلية', 'skills': ['تصوير منتجات'], 'links': [{'kind': 'instagram', 'value': 'fahad.shots'}]},
          'unsure': ['links.instagram', 'district'],
        });
      await _pump(tester, srv: srv, size: const Size(360, 640), scale: 1.6);
      expect(tester.takeException(), isNull);
      await _open(tester, consent: false);
      expect(find.byKey(const Key('voice-consent')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('voice-consent-ok')));
      await tester.tap(find.byKey(const Key('voice-consent-ok')));
      await _settle(tester);
      expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _apply(tester, 'ق');
      expect(find.byKey(const Key('voice-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _apply(tester);
      expect(find.byKey(const Key('voice-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
      // نمرّ على الشاشة كلها والعلامات ظاهرة
      for (final k in ['edit-name', 'edit-bio', 'edit-job', 'edit-city', 'edit-district', 'skill-add', 'link-value-0']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: k);
      }
      expect(_tagText(tester, 'links.instagram'), 'تأكّد من الكتابة');
    });
  });
}
