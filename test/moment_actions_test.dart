// أفعال اللحظة في العارض: عمود الحافة (إعجاب، تفاعل، حفظ، مشاركة، خريطة)، التفاعلات الأربعة (إرسال وإزالة مع العدّادات)،
// الحفظ في «محفوظاتي» عبر قائمة الأمنيات، ورقة المشاركة (محادثة بـ #post/<id>، مشاركة أصلية، نسخ الرابط)، «عرض على الخريطة»
// و«الاتجاهات»، دعوة الزائر للدخول قبل الحفظ والتفاعل، رابط اللحظة #/m/<id> وإشعار التفاعل، وشريحة «اللحظات» في المحفوظات.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/moments_api.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/nav_provider.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/core/share/share_io.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/myspace/wishlist_page.dart';
import 'package:naslook/pages/posts/moment_actions.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/biz_providers.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

const _post = 'aaaaaaaa-0000-4000-8000-000000000001';
const _mine = 'aaaaaaaa-0000-4000-8000-000000000002';
const _other = 'aaaaaaaa-0000-4000-8000-000000000003';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

Map<String, dynamic> _postJson({String id = _post, bool mine = false}) => {
      'id': id, 'user': mine ? {'id': 'SA0000001', 'nickname': 'amr'} : {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'mediaUrl': null,
      'caption': 'الكورنيش الليلة', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment', 'lat': 21.55, 'lng': 39.16, 'placeName': 'الكورنيش',
      'status': 'active', 'views': 4, 'likes': 1, 'liked': false, 'mine': mine, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

/// خادم وهمي: التفاعلات (بعدّادات تتغير)، قائمة الأمنيات، المحادثات وجهات الاتصال، الرسائل، واللحظة نفسها.
class _Srv {
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  final counts = <String, int>{'😍': 2, '🔥': 1};
  String? mine;
  final wishes = <Map<String, dynamic>>[];
  int seq = 0;
  bool postMissing = false;
  /// رد خطأ غير 404 لجلب اللحظة (انقطاع أو خطأ خادم)
  int? postError;

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> get _reactions => {'counts': counts, 'mine': mine};

  void _setMine(String? e) {
    if (mine != null) counts[mine!] = (counts[mine!] ?? 1) - 1;
    if (e != null) counts[e] = (counts[e] ?? 0) + 1;
    counts.removeWhere((_, n) => n <= 0);
    mine = e;
  }

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.startsWith('{')) (bodies[key] ??= []).add(jsonDecode(req.body) as Map<String, dynamic>);
    if (key == 'GET /moments/$_post/reactions') return _json(_reactions);
    if (key == 'POST /moments/$_post/react') {
      _setMine(bodies[key]!.last['emoji'] as String?);
      return _json(_reactions);
    }
    if (key == 'DELETE /moments/$_post/react') {
      _setMine(null);
      return _json(_reactions);
    }
    if (key == 'GET /wishlist') return _json(wishes);
    if (key == 'POST /wishlist') {
      final b = bodies[key]!.last;
      final w = {'id': 'w${++seq}', 'kind': b['kind'], 'refId': b['refId'], 'title': 'الكورنيش الليلة', 'subtitle': 'لحظة · sara', 'note': '', 'done': false, 'available': true};
      wishes.insert(0, w);
      return _json(w);
    }
    final wm = RegExp(r'^DELETE /wishlist/(w\d+)$').firstMatch(key);
    if (wm != null) {
      wishes.removeWhere((w) => w['id'] == wm.group(1));
      return _json({'ok': true});
    }
    if (key == 'GET /mapposts/$_post') {
      if (postError != null) return _json({'error': 'server'}, postError!);
      return postMissing ? _json({'error': 'not-found'}, 404) : _json(_postJson());
    }
    if (key == 'GET /chats') return _json([{'id': 'SA0000002', 'nickname': 'sara'}]);
    if (key == 'GET /contacts') return _json([{'id': 'SA0000003', 'nickname': 'khalid'}, {'id': 'SA0000001', 'nickname': 'amr'}]);
    if (key == 'POST /messages') {
      final b = bodies[key]!.last;
      return _json({'message': {'id': 'm${++seq}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()}});
    }
    if (path.endsWith('/view')) return _json({'views': 5});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<(_Srv, ProviderContainer)> _pump(WidgetTester tester, Widget home, {_Srv? srv, bool signedIn = true, Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester, 3);
  return (s, ProviderScope.containerOf(tester.element(find.byType(MaterialApp))));
}

// العارض يتقدّم تلقائياً كل سبع ثوانٍ للنص: نبضات قصيرة صريحة تبقي كل اختبار دون ذلك
Future<void> _settle(WidgetTester tester, [int n = 2]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// ثوانٍ من النبضات (نصف ثانية) تتجاوز مدة اللحظة النصية (7 ث)
Future<void> _wait(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// يفتح شريط التفاعل ويختار الرمز [i]
Future<void> _pick(WidgetTester tester, int i) async {
  await tester.tap(find.byKey(const Key('moment-react')));
  await _settle(tester);
  await tester.tap(find.byKey(Key('moment-react-$i')));
  await _settle(tester);
}

PostViewerPage _viewer({bool mine = false}) => PostViewerPage(posts: [MapPost.fromJson(_postJson(id: mine ? _mine : _post, mine: mine))]);

String _label(WidgetTester tester, String key) => tester.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))).last.data ?? '';

/// يلتقط ما يُنسخ إلى الحافظة.
List<String> _clipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  tearDown(() {
    LegalLinks.openOverride = null;
    nativeShareOverride = null;
    pendingLink = null;
  });

  test('MomentReactions parses only the four emojis, totals them and predicts a switch locally', () {
    final r = MomentReactions.fromJson({'counts': {'😍': 2, '🔥': '1', '💩': 9, '👏': 0}, 'mine': '🔥'});
    expect(r.counts, {'😍': 2, '🔥': 1});
    expect(r.total, 3);
    expect(r.mine, '🔥');
    expect(MomentReactions.fromJson({'counts': {}, 'mine': '💩'}).mine, isNull, reason: 'رمز خارج الأربعة يُتجاهل');
    final next = r.withMine('😂');
    expect(next.counts, {'😍': 2, '😂': 1});
    expect(next.mine, '😂');
    expect(next.withMine(null).counts, {'😍': 2});
    expect(momentEmojis, ['😍', '😂', '🔥', '👏']);
    expect(momentLink(_post), 'https://naslife.app/m/$_post');
  });

  testWidgets('the rail shows like, react, save, share and map; counts load when the moment is shown', (tester) async {
    final (srv, _) = await _pump(tester, _viewer());
    for (final k in ['moment-like', 'moment-react', 'moment-save', 'moment-share', 'moment-map']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(srv.calls, contains('GET /moments/$_post/reactions'));
    expect(_label(tester, 'moment-react'), '3');
    expect(_label(tester, 'moment-like'), '1');
    // «مراسلة» و«رد خاص» والخيارات باقية في الصف السفلي
    expect(find.text('مراسلة'), findsOneWidget);
    expect(find.byKey(const Key('post-reply-private')), findsOneWidget);
    expect(find.byTooltip('خيارات'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reacting sends the emoji, shows the counts and highlights mine; tapping it again removes it', (tester) async {
    final (srv, _) = await _pump(tester, _viewer());
    await tester.tap(find.byKey(const Key('moment-react')));
    await _settle(tester);
    expect(find.byKey(const Key('moment-react-bar')), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('moment-react-$i')), findsOneWidget);
    }
    expect(find.text('😍'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('👏'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('moment-react-count-0'))).data, '2');
    await tester.tap(find.byKey(const Key('moment-react-2')));
    await _settle(tester);
    expect(find.byKey(const Key('moment-react-bar')), findsNothing);
    expect(srv.bodies['POST /moments/$_post/react']!.single, {'emoji': '🔥'});
    expect(tester.widget<Text>(find.byKey(const Key('moment-react-mine'))).data, '🔥');
    expect(_label(tester, 'moment-react'), '4');

    // تغيير التفاعل: 🔥 ← 😂 بطلب واحد
    await tester.tap(find.byKey(const Key('moment-react')));
    await _settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('moment-react-count-2'))).data, '2');
    await tester.tap(find.byKey(const Key('moment-react-1')));
    await _settle(tester);
    expect(srv.bodies['POST /moments/$_post/react']!.last, {'emoji': '😂'});
    expect(tester.widget<Text>(find.byKey(const Key('moment-react-mine'))).data, '😂');

    // الضغط على تفاعلي الحالي يزيله بـ DELETE
    await tester.tap(find.byKey(const Key('moment-react')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-react-1')));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /moments/$_post/react'));
    expect(find.byKey(const Key('moment-react-mine')), findsNothing);
    expect(_label(tester, 'moment-react'), '3');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a long press on the heart opens the reaction bar too', (tester) async {
    final (srv, _) = await _pump(tester, _viewer());
    await tester.longPress(find.byKey(const Key('moment-like')));
    await _settle(tester);
    expect(find.byKey(const Key('moment-react-bar')), findsOneWidget);
    expect(srv.calls, isNot(contains('POST /mapposts/$_post/like')), reason: 'الضغطة المطوّلة لا تُعجب');
    await tester.tap(find.byKey(const Key('moment-react-3')));
    await _settle(tester);
    expect(srv.bodies['POST /moments/$_post/react']!.single, {'emoji': '👏'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed reaction rolls back and says why', (tester) async {
    await _pump(tester, _viewer(), srv: _FailingReact());
    await tester.tap(find.byKey(const Key('moment-react')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-react-0')));
    await _settle(tester);
    expect(find.byKey(const Key('moment-react-mine')), findsNothing);
    expect(_label(tester, 'moment-react'), '3');
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save adds the moment to the wishlist as kind post and a second tap removes it', (tester) async {
    final (srv, _) = await _pump(tester, _viewer());
    expect(_label(tester, 'moment-save'), 'حفظ');
    await tester.tap(find.byKey(const Key('moment-save')));
    await _settle(tester);
    expect(srv.bodies['POST /wishlist']!.single, {'kind': 'post', 'refId': _post});
    expect(find.text('حُفظت في محفوظاتي'), findsOneWidget);
    expect(_label(tester, 'moment-save'), 'محفوظة');
    await tester.tap(find.byKey(const Key('moment-save')));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /wishlist/w1'));
    expect(_label(tester, 'moment-save'), 'حفظ');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a guest sees save, react and share; save and react ask to sign in without calling the server', (tester) async {
    final (srv, _) = await _pump(tester, _viewer(), signedIn: false);
    expect(find.byKey(const Key('moment-save')), findsOneWidget);
    expect(find.byKey(const Key('moment-share')), findsOneWidget);
    expect(srv.calls, contains('GET /moments/$_post/reactions'), reason: 'العدّادات عامة');
    expect(srv.calls, isNot(contains('GET /wishlist')), reason: 'الزائر لا يطلب مسار حساب');
    expect(find.text('مراسلة'), findsNothing);
    await tester.tap(find.byKey(const Key('moment-save')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-react')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.byKey(const Key('moment-react-bar')), findsNothing);
    expect(srv.calls.where((c) => c.startsWith('POST ')).where((c) => !c.endsWith('/view')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('share sheet: copy link puts https://naslife.app/m/<id> on the clipboard', (tester) async {
    final copied = _clipboard(tester);
    await _pump(tester, _viewer());
    await tester.tap(find.byKey(const Key('moment-share')));
    await _settle(tester);
    expect(find.byKey(const Key('moment-share-chat')), findsOneWidget);
    expect(find.byKey(const Key('moment-share-native')), findsOneWidget);
    expect(find.byKey(const Key('moment-share-copy')), findsOneWidget);
    expect(find.text('إرسال في محادثة'), findsOneWidget);
    expect(find.text('مشاركة…'), findsOneWidget);
    expect(find.text('نسخ الرابط'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moment-share-copy')));
    await _settle(tester);
    expect(copied, ['https://naslife.app/m/$_post']);
    expect(find.text('نُسخ الرابط'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('share sheet: native share gets the public link; without a share sheet it falls back to copying', (tester) async {
    final copied = _clipboard(tester);
    final shared = <String>[];
    var available = true;
    nativeShareOverride = ({required String title, required String text, required String url}) async {
      shared.add(url);
      return available;
    };
    await _pump(tester, _viewer());
    await tester.tap(find.byKey(const Key('moment-share')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-share-native')));
    await _settle(tester);
    expect(shared, ['https://naslife.app/m/$_post']);
    expect(copied, isEmpty);
    available = false;
    await tester.tap(find.byKey(const Key('moment-share')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-share-native')));
    await _settle(tester);
    expect(copied, ['https://naslife.app/m/$_post']);
    expect(find.text('نُسخ الرابط'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('share sheet: «إرسال في محادثة» picks a person from chats and contacts and sends #post/<id>', (tester) async {
    final (srv, _) = await _pump(tester, _viewer());
    await tester.tap(find.byKey(const Key('moment-share')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('moment-share-chat')));
    await _settle(tester);
    expect(find.text('إرسال اللحظة إلى'), findsOneWidget);
    expect(find.byKey(const Key('moment-pick-SA0000002')), findsOneWidget);
    expect(find.byKey(const Key('moment-pick-SA0000003')), findsOneWidget);
    expect(find.byKey(const Key('moment-pick-SA0000001')), findsNothing, reason: 'لا أرسل لنفسي');
    await tester.tap(find.byKey(const Key('moment-pick-SA0000003')));
    await _settle(tester);
    expect(srv.bodies['POST /messages']!.single, containsPair('to', 'SA0000003'));
    expect(srv.bodies['POST /messages']!.single, containsPair('content', '#post/$_post'));
    expect(find.text('أُرسلت اللحظة إلى khalid'), findsOneWidget);
    expect(find.byType(PostViewerPage), findsOneWidget, reason: 'العارض باقٍ بعد الإرسال');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«عرض على الخريطة» closes the viewer back to the home map and focuses the moment', (tester) async {
    final (_, c) = await _pump(tester, Scaffold(body: Builder(builder: (ctx) => Center(child: FilledButton(key: const Key('open'), onPressed: () => PostViewerPage.open(ctx, [MapPost.fromJson(_postJson())]), child: const Text('افتح'))))));
    c.read(navIndexProvider.notifier).state = 2;
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);
    expect(find.byType(PostViewerPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('moment-map')));
    // انتقال الإغلاق يأخذ حتى 800 م.ث
    await _settle(tester, 4);
    expect(find.byType(PostViewerPage), findsNothing);
    expect(find.byKey(const Key('open')), findsOneWidget);
    expect(c.read(mapFocusProvider), (lat: 21.55, lng: 39.16));
    expect(c.read(navIndexProvider), 0);
  });

  testWidgets('«الاتجاهات» in the options menu opens Google Maps directions to the moment (others and mine)', (tester) async {
    final opened = <Uri>[];
    LegalLinks.openOverride = (u) async => opened.add(u);
    await _pump(tester, _viewer());
    await tester.tap(find.byTooltip('خيارات'));
    await _settle(tester);
    expect(find.text('الاتجاهات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moment-directions')));
    await _settle(tester);
    expect(opened.single.host, 'www.google.com');
    expect(opened.single.queryParameters['destination'], '21.55,39.16');
    await tester.pumpWidget(const SizedBox());

    await _pump(tester, _viewer(mine: true));
    await tester.tap(find.byTooltip('خيارات'));
    await _settle(tester);
    expect(find.text('الإحصاءات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moment-directions')));
    await _settle(tester);
    expect(opened, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a short phone screen (375×600) the rail goes compact and nothing overflows', (tester) async {
    final p = {..._postJson(), 'title': 'عرض القهوة', 'price': 1500, 'caption': 'سطر طويل ' * 12, 'cta': {'type': 'link', 'value': 'https://example.com', 'label': 'زر الموقع'}};
    await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(p)]), size: const Size(375, 600));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('moment-share')), findsOneWidget);
    expect(find.text('مشاركة'), findsNothing, reason: 'بلا تسميات على الشاشة القصيرة');
    await tester.pumpWidget(const SizedBox());
  });

  group('moment link', () {
    test('#/m/<id> and /m/<id> parse as a moment link; anything else does not', () {
      final a = parsePendingLink(Uri.parse('https://naslife.app/#/m/$_post'));
      expect(a?.isMoment, isTrue);
      expect(a?.value, _post);
      expect(parsePendingLink(Uri.parse('https://naslife.app/m/${_post.toUpperCase()}'))?.value, _post);
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/m/not-a-uuid')), isNull);
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/c/biz-brew92'))?.isCircle, isTrue);
      final page = pendingLinkPage(a!);
      expect(page, isA<MomentLinkPage>());
      expect((page as MomentLinkPage).id, _post);
    });

    testWidgets('the link page fetches the moment and opens it in the viewer', (tester) async {
      final (srv, _) = await _pump(tester, const MomentLinkPage(id: _post));
      expect(srv.calls, contains('GET /mapposts/$_post'));
      expect(find.byType(PostViewerPage), findsOneWidget);
      expect(find.text('الكورنيش الليلة'), findsOneWidget);
      expect(find.byKey(const Key('moment-share')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a missing moment says so with a retry', (tester) async {
      final srv = _Srv()..postMissing = true;
      await _pump(tester, const MomentLinkPage(id: _post), srv: srv);
      expect(find.byKey(const Key('moment-link-missing')), findsOneWidget);
      srv.postMissing = false;
      await tester.tap(find.byKey(const Key('moment-link-retry')));
      await _settle(tester);
      expect(find.byType(PostViewerPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a network or server error is not reported as «no longer available», and retry recovers', (tester) async {
      final srv = _Srv()..postError = 503;
      await _pump(tester, const MomentLinkPage(id: _post), srv: srv);
      expect(find.byKey(const Key('moment-link-error')), findsOneWidget);
      expect(find.byKey(const Key('moment-link-missing')), findsNothing);
      srv.postError = null;
      await tester.tap(find.byKey(const Key('moment-link-retry')));
      await _settle(tester);
      expect(find.byType(PostViewerPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('a moment_react notification opens the moment', () {
      final n = AppNotification.fromJson({'id': 'n1', 'kind': 'moment_react', 'title': 'sara تفاعل مع لحظتك 🔥', 'body': '', 'data': {'postId': _post}, 'createdAt': DateTime.now().toIso8601String()});
      final page = notificationTarget(n);
      expect(page, isA<MomentLinkPage>());
      expect((page as MomentLinkPage).id, _post);
      expect(notificationStyle('moment_react').icon, Icons.add_reaction_outlined);
    });

    testWidgets('a guest opening #/m/<id> gets the guest tabs with the viewer on top', (tester) async {
      DeviceLocation.override = () async => null;
      addTearDown(() => DeviceLocation.override = null);
      pendingLink = parsePendingLink(Uri.parse('https://naslife.app/#/m/$_post'));
      final (srv, _) = await _pump(tester, const AuthGate(), signedIn: false, size: const Size(900, 1400));
      await _settle(tester, 2);
      expect(srv.calls, contains('GET /mapposts/$_post'));
      expect(find.byType(PostViewerPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(PostViewerPage))).pop();
      await _settle(tester);
      expect(find.byKey(const Key('guest-shell')), findsOneWidget, reason: 'إغلاق العارض يعيد إلى تبويبات الزائر');
      await tester.pumpWidget(const SizedBox());
    });
  });


  // العارض مغطّى طوال سلسلة الفعل: لا تقدّم تلقائي خلف منتقي المحادثة أو دعوة الدخول، ولا يُغلق انتهاء اللحظة ما فوقها.
  group('actions hold the viewer', () {
    testWidgets('a single moment: the chat picker survives the 7 s auto-advance and the send still goes out', (tester) async {
      final (srv, _) = await _pump(tester, _viewer());
      await tester.tap(find.byKey(const Key('moment-share')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('moment-share-chat')));
      await _settle(tester);
      expect(find.byKey(const Key('moment-pick-SA0000002')), findsOneWidget);
      await _wait(tester, 10);
      expect(find.byKey(const Key('moment-pick-SA0000002')), findsOneWidget, reason: 'المنتقي لا يُغلق خلف المستخدم');
      expect(find.byType(PostViewerPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('moment-pick-SA0000002')));
      await _settle(tester);
      expect(srv.bodies['POST /messages']!.single, containsPair('content', '#post/$_post'));
      expect(find.text('أُرسلت اللحظة إلى sara'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('several moments: the viewer does not move on behind the picker, so picking a person sends it', (tester) async {
      final (srv, _) = await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(_postJson()), MapPost.fromJson({..._postJson(id: _other), 'caption': 'اللحظة الثانية'})]));
      await tester.tap(find.byKey(const Key('moment-share')).first);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('moment-share-chat')));
      await _settle(tester);
      await _wait(tester, 8);
      expect(find.byKey(const Key('moment-pick-SA0000002')), findsOneWidget);
      await tester.tap(find.byKey(const Key('moment-pick-SA0000002')));
      await _settle(tester);
      expect(srv.calls.where((c) => c == 'POST /messages'), hasLength(1));
      expect(find.text('أُرسلت اللحظة إلى sara'), findsOneWidget);
      expect(find.text('الكورنيش الليلة'), findsOneWidget, reason: 'العارض بقي على اللحظة التي شاركها');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a guest\'s sign-in sheet from the rail is not closed by the auto-advance', (tester) async {
      final (srv, _) = await _pump(tester, _viewer(), signedIn: false);
      await tester.tap(find.byKey(const Key('moment-save')));
      await _settle(tester);
      expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
      await _wait(tester, 10);
      expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
      expect(find.byType(PostViewerPage), findsOneWidget);
      expect(srv.calls.where((c) => c.startsWith('POST ')).where((c) => !c.endsWith('/view')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a guest tapping the heart is asked to sign in: no flip, no like request, no raw error', (tester) async {
      final (srv, _) = await _pump(tester, _viewer(), signedIn: false);
      await tester.tap(find.byKey(const Key('moment-like')));
      await _settle(tester);
      expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
      expect(srv.calls, isNot(contains('POST /mapposts/$_post/like')));
      expect(_label(tester, 'moment-like'), '1');
      expect(find.textContaining('ApiException'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('reaction ordering', () {
    testWidgets('a slow first pick cannot win over a later one: requests go out in order and the last pick stays', (tester) async {
      final srv = _GatedReact(afterHandling: true);
      await _pump(tester, _viewer(), srv: srv);
      await _pick(tester, 0); // 😍 ورده يتأخر
      await _pick(tester, 2); // 🔥
      expect(tester.widget<Text>(find.byKey(const Key('moment-react-mine'))).data, '🔥');
      srv.gate.complete();
      await _settle(tester);
      expect(srv.mine, '🔥');
      expect(tester.widget<Text>(find.byKey(const Key('moment-react-mine'))).data, '🔥');
      expect([for (final b in srv.bodies['POST /moments/$_post/react']!) b['emoji']], ['😍', '🔥']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the server sees picks in the order they were made even if the first request is slow to arrive', (tester) async {
      final srv = _GatedReact(afterHandling: false);
      await _pump(tester, _viewer(), srv: srv);
      await _pick(tester, 0);
      await _pick(tester, 2);
      srv.gate.complete();
      await _settle(tester);
      expect(srv.mine, '🔥', reason: 'آخر اختيار للمستخدم');
      expect(tester.widget<Text>(find.byKey(const Key('moment-react-mine'))).data, '🔥');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed reaction made before the counts loaded rolls back only my pick, not the counts', (tester) async {
      final srv = _SlowCountsFailingReact();
      await _pump(tester, _viewer(), srv: srv);
      expect(_label(tester, 'moment-react'), 'تفاعل', reason: 'العدّادات لم تصل بعد');
      await tester.tap(find.byKey(const Key('moment-react')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('moment-react-0')));
      await tester.pump();
      // العدّادات تصل والطلب ما زال معلّقاً، ثم يرفضه الخادم
      srv.countsGate.complete();
      await _settle(tester);
      srv.react.complete();
      await _settle(tester);
      expect(find.byKey(const Key('moment-react-mine')), findsNothing);
      expect(_label(tester, 'moment-react'), '3');
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed counts request is retried once instead of leaving «تفاعل» without numbers', (tester) async {
      final srv = _FlakyCounts();
      await _pump(tester, _viewer(), srv: srv);
      expect(srv.calls.where((c) => c == 'GET /moments/$_post/reactions'), hasLength(2));
      expect(_label(tester, 'moment-react'), '3');
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the reaction bar grows with large system text instead of clipping the counts', (tester) async {
    for (final scale in [1.0, 1.25, 1.6]) {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Center(child: MomentReactionBar(reactions: MomentReactions.fromJson({'counts': {'😍': 12, '🔥': 3}, 'mine': '🔥'}), onPick: (_) {}))),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      expect(find.byKey(const Key('moment-react-count-2')), findsOneWidget);
    }
  });

  testWidgets('«الخريطة» from a guest\'s shared profile link leaves the link page for the map tab', (tester) async {
    DeviceLocation.override = () async => null;
    addTearDown(() => DeviceLocation.override = null);
    final (_, c) = await _pump(tester, const GuestShell(link: PendingLink('user', 'sara')), signedIn: false, size: const Size(900, 1400));
    expect(find.byKey(const Key('guest-bar')), findsOneWidget);
    unawaited(PostViewerPage.open(tester.element(find.byKey(const Key('guest-bar'))), [MapPost.fromJson(_postJson())]));
    await _settle(tester, 3);
    await tester.tap(find.byKey(const Key('moment-map')));
    await _settle(tester, 4);
    expect(find.byType(PostViewerPage), findsNothing);
    expect(find.byKey(const Key('guest-bar')), findsNothing);
    expect(find.byKey(const Key('guest-shell')), findsOneWidget);
    expect(c.read(mapFocusProvider), isNull, reason: 'الخريطة التقطت التركيز حين جهزت');
    await tester.pumpWidget(const SizedBox());
  });

  group('saved moments', () {
    testWidgets('«اللحظات» filter lists saved moments and opens one in the viewer', (tester) async {
      final srv = _Srv()
        ..wishes.addAll([
          {'id': 'w1', 'kind': 'post', 'refId': _post, 'title': 'الكورنيش الليلة', 'subtitle': 'لحظة · sara', 'note': '', 'done': false, 'available': true},
          {'id': 'w2', 'kind': 'market', 'refId': 'bbbbbbbb-0000-4000-8000-000000000002', 'title': 'قهوة مختصة', 'subtitle': 'منتج في السوق', 'price': 4500, 'note': '', 'done': false, 'available': true},
        ]);
      await _pump(tester, const WishlistPage(), srv: srv);
      expect(find.text('محفوظاتي'), findsOneWidget);
      expect(find.text('اللحظات · 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wish-filter-post')));
      await _settle(tester);
      expect(find.text('قهوة مختصة'), findsNothing);
      await tester.tap(find.text('الكورنيش الليلة'));
      await _settle(tester);
      expect(srv.calls, contains('GET /mapposts/$_post'));
      expect(find.byType(PostViewerPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opened on «اللحظات» with nothing saved, it explains how to save one', (tester) async {
      await _pump(tester, const WishlistPage(initialFilter: 'post'));
      expect(find.text('اللحظات · 0'), findsOneWidget);
      expect(find.byKey(const Key('wish-moments-empty')), findsOneWidget);
    });
  });
}

/// يرفض التفاعل بـ 403 (محظور) ليُختبر التراجع.
class _FailingReact extends _Srv {
  @override
  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'POST' && req.url.path == '/moments/$_post/react') return _json({'error': 'blocked'}, 403);
    return super.handle(req);
  }
}

/// يمسك أول طلب تفاعل حتى يُفتح [gate]: بعد معالجته في الخادم ([afterHandling]) أو قبل وصوله إليه.
class _GatedReact extends _Srv {
  final bool afterHandling;
  final gate = Completer<void>();
  var _n = 0;
  _GatedReact({required this.afterHandling});
  @override
  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'POST' && req.url.path == '/moments/$_post/react' && ++_n == 1) {
      if (!afterHandling) await gate.future;
      final r = await super.handle(req);
      if (afterHandling) await gate.future;
      return r;
    }
    return super.handle(req);
  }
}

/// العدّادات الأولى تتأخر حتى [countsGate]، والتفاعل يُرفض (403) بعد [react].
class _SlowCountsFailingReact extends _Srv {
  final countsGate = Completer<void>();
  final react = Completer<void>();
  var _gets = 0;
  @override
  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'GET' && req.url.path == '/moments/$_post/reactions' && ++_gets == 1) await countsGate.future;
    if (req.method == 'POST' && req.url.path == '/moments/$_post/react') {
      calls.add('POST ${req.url.path}');
      await react.future;
      return _json({'error': 'blocked'}, 403);
    }
    return super.handle(req);
  }
}

/// أول جلب للعدّادات يفشل (500) ثم ينجح.
class _FlakyCounts extends _Srv {
  var _gets = 0;
  @override
  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'GET' && req.url.path == '/moments/$_post/reactions' && ++_gets == 1) {
      calls.add('GET ${req.url.path}');
      return _json({'error': 'down'}, 500);
    }
    return super.handle(req);
  }
}
