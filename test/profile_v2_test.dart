// الملف الشخصي v2: شاشة الزائر (الغلاف والاسم والمسمى والروابط والتعريف والأرقام وشارات الثقة والتبويبات والمتابعة
// و«مراسلة» حسب السياسة والملف الخاص)، شاشة التعديل (الحفظ وفحص اسم المستخدم والتسجيل الصوتي إلى /me/profile/intro)،
// شاشة التوثيق والتحكم (المفاتيح تُرسل PUT بالمفتاح الصحيح)، وبطاقات صاحب الحساب في ماي سبيس.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/profile_v2_models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/media/video_view.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/core/media/voice_record.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/market/listing_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/pages/profile/edit_profile_page.dart';
import 'package:naslook/pages/profile/privacy_control_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _FakeRecorder implements VoiceRecordSession {
  bool _on = false;
  @override
  bool get recording => _on;
  @override
  Duration get elapsed => const Duration(seconds: 3);
  @override
  Future<void> start() async => _on = true;
  @override
  Future<RecordedVoice?> stop() async {
    _on = false;
    return (bytes: Uint8List.fromList([9, 9, 9]), mime: 'audio/webm', name: 'voice.weba', duration: const Duration(seconds: 3));
  }
  @override
  Future<void> cancel() async => _on = false;
  @override
  void dispose() {}
}

class _FakePlayer extends VoicePlayerBase {
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {}
  @override
  Future<void> play() async => emit(const VoiceState(playing: true, duration: Duration(seconds: 42)));
  @override
  Future<void> pause() async => emit(const VoiceState(playing: false, duration: Duration(seconds: 42)));
  @override
  Future<void> seek(Duration position) async {}
}

const _sara = Person(id: 'SA0000002', nickname: 'fahad.shots');
const _lid = '11111111-1111-4111-8111-111111111111';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final puts = <Map<String, dynamic>>[];
  bool following = false, canMessage = true, private = false, v2 = true;
  int followers = 1212;
  Map<String, dynamic>? intro = {'kind': 'voice', 'url': 'https://test.local/chat/media/intro.m4a', 'sec': 42, 'at': '2026-09-20T10:00:00Z'};
  Map<String, dynamic> settings = {'msgPolicy': 'all', 'showOnline': true, 'showCity': true, 'showFriends': false, 'introVisibility': 'all'};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> _visitor() => {
        'id': 'SA0000002', 'nickname': 'fahad.shots', 'displayName': 'فهد الغامدي', 'avatarUrl': null, 'coverUrl': null, 'bio': 'أصوّر البحر والمقاهي في جدة', 'accountType': 'pro', 'jobTitle': 'مصوّر',
        'city': 'جدة', 'district': 'الشاطئ',
        'links': [{'kind': 'instagram', 'value': 'fahad.shots', 'url': 'https://instagram.com/fahad.shots'}, {'kind': 'website', 'value': 'fahadshots.sa', 'url': 'https://fahadshots.sa'}],
        'intro': intro,
        'stats': {'posts': 128, 'followers': followers, 'following': 40, 'circles': 6, 'ratingAvg': 4.9, 'ratingCount': 47, 'completedOrders': 31, 'friends': 12},
        'trust': {'emailVerified': true, 'phoneVerified': false, 'memberSince': '2025-03-05T00:00:00Z', 'respondsFast': true},
        'flags': {'isMe': false, 'isFollowing': following, 'isFriend': false, 'canMessage': canMessage, 'online': true, 'isPrivate': false, 'blocked': false},
        'memberSince': '2025-03-05T00:00:00Z',
      };
  Map<String, dynamic> _privateVisitor() => {'id': 'SA0000002', 'nickname': 'fahad.shots', 'displayName': 'فهد الغامدي', 'avatarUrl': null, 'coverUrl': null, 'flags': {'isPrivate': true, 'isMe': false, 'isFriend': false, 'canMessage': true}, 'stats': {}};
  Map<String, dynamic> _mine() => {
        'id': 'SA0000001', 'nickname': 'amr', 'displayName': 'عمرو', 'avatarUrl': null, 'coverUrl': null, 'bio': 'نبذة', 'accountType': 'personal', 'jobTitle': '', 'city': 'جدة', 'district': 'الروضة',
        'links': [], 'intro': intro, 'stats': {'posts': 3, 'followers': 10, 'following': 4, 'circles': 2, 'ratingAvg': null, 'ratingCount': 0, 'completedOrders': 0, 'friends': 1},
        'trust': {'emailVerified': true, 'phoneVerified': false, 'memberSince': '2025-03-05T00:00:00Z', 'respondsFast': null},
        'flags': {'isMe': true, 'isFollowing': false, 'isFriend': false, 'canMessage': true, 'online': true, 'isPrivate': false, 'blocked': false},
        'settings': settings,
        'completion': {'pct': 60, 'steps': [
          {'id': 'avatar', 'done': false, 'label': 'أضف صورة'}, {'id': 'cover', 'done': false, 'label': 'أضف غلافاً'}, {'id': 'bio', 'done': true, 'label': 'اكتب نبذة'},
          {'id': 'links', 'done': false, 'label': 'أضف رابطاً واحداً على الأقل'}, {'id': 'intro', 'done': intro != null, 'label': 'عرّف بنفسك'}, {'id': 'email', 'done': true, 'label': 'وثّق بريدك'}, {'id': 'skills', 'done': true, 'label': 'أضف مهاراتك'},
        ]},
      };
  Map<String, dynamic> _post() => {
        'id': 'aaaaaaaa-0000-4000-8000-000000000031', 'user': {'id': 'SA0000002', 'nickname': 'fahad.shots'}, 'kind': 'text', 'caption': 'غروب أبحر', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment', 'cta': null,
        'lat': 21.5, 'lng': 39.1, 'status': 'active', 'views': 12, 'likes': 0, 'liked': false, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
  Map<String, dynamic> _listing() => {'id': _lid, 'seller': {'id': 'SA0000002', 'nickname': 'fahad.shots'}, 'kind': 'product', 'category': 'electronics', 'title': 'كاميرا فوجي X-T20', 'description': 'مستعمل', 'price': 265000, 'imageUrl': null, 'status': 'active', 'mine': false};

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    final ct = req.headers['content-type'] ?? '';
    Map<String, dynamic>? body;
    if (ct.contains('json') && req.body.startsWith('{')) {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      bodies[key] = body;
    }
    switch (key) {
      case 'GET /profiles/SA0000002/v2':
        if (!v2) return _json({'error': 'not-found'}, 404);
        return _json(private ? _privateVisitor() : _visitor());
      case 'GET /profiles/SA0000002':
        return _json({'id': 'SA0000002', 'nickname': 'fahad.shots', 'bio': 'أصوّر البحر والمقاهي في جدة', 'skills': ['تصوير بورتريه', 'درون'], 'hobbies': ['غوص'], 'lookingFor': [], 'offerings': [{'name': 'جلسة تصوير شخصية', 'description': 'ساعة'}], 'isPublic': true, 'createdAt': '2025-03-05T00:00:00Z'});
      case 'POST /profiles/SA0000002/follow':
        following = true;
        followers++;
        return _json({'ok': true, 'following': true, 'followers': followers});
      case 'DELETE /profiles/SA0000002/follow':
        following = false;
        followers--;
        return _json({'ok': true, 'following': false, 'followers': followers});
      case 'POST /profiles/SA0000002/event':
        return _json({'ok': true});
      case 'GET /mapposts/feed':
        return _json({'items': [_post()], 'nextCursor': null, 'located': false});
      case 'GET /market':
        return _json([_listing()]);
      case 'GET /market/$_lid':
        return _json(_listing());
      case 'GET /me/profile/v2':
        if (!v2) return _json({'error': 'not-found'}, 404);
        return _json(_mine());
      case 'PUT /me/profile/v2':
        puts.add(body!);
        for (final k in ['msgPolicy', 'showOnline', 'showCity', 'showFriends', 'introVisibility']) {
          if (body.containsKey(k)) settings[k] = body[k];
        }
        return _json(_mine());
      case 'PUT /me/profile/intro':
        intro = {'kind': body!['kind'], 'url': 'https://test.local${body['url']}', 'sec': body['sec'], 'at': DateTime.now().toUtc().toIso8601String()};
        return _json({'ok': true, 'intro': intro});
      case 'DELETE /me/profile/intro':
        intro = null;
        return _json({'ok': true});
      case 'GET /me/profile/stats':
        return _json({'visits7': 312, 'visits7Prev': 220, 'messages7': 27, 'follows7': 9, 'shares7': 2, 'series': []});
      case 'GET /handles/check':
        final n = req.url.queryParameters['nickname'] ?? '';
        if (n.length < 3) return _json({'valid': false, 'available': false, 'reason': 'short'});
        return _json(n == 'sara' ? {'valid': true, 'available': false, 'reason': 'taken'} : {'valid': true, 'available': true, 'reason': null});
      case 'POST /chat/upload':
        return _json({'url': ct.startsWith('audio') ? '/chat/media/voice1.weba' : ct.startsWith('video') ? '/chat/media/clip1.webm' : '/chat/media/img1.jpg', 'type': ct, 'kind': ct.split('/').first, 'size': req.bodyBytes.length});
      case 'GET /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'bio': 'نبذة', 'skills': ['مونتاج'], 'hobbies': ['قهوة'], 'lookingFor': [], 'accountType': 'personal', 'isPublic': true});
      case 'PUT /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', ...?body});
      case 'PATCH /me':
        return _json({'ok': true});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false});
      case 'GET /wallet':
        return _json({'balance': 0, 'points': 0, 'upcomingTickets': 0, 'recent': [], 'testTopup': false});
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': false});
    }
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<(_Srv, ProviderContainer)> _pump(WidgetTester tester, Widget home, {_Srv? srv, double height = 1600}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return MaterialApp(locale: const Locale('ar'), home: home);
    }),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return (s, container);
}

/// انتقالات الصفحات في Material 3 تستغرق 800ms، فنضخّ أكثر من ذلك حتى تكتمل الدفعات والإزالات.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(() {
    VoiceRecordSession.factoryOverride = () => _FakeRecorder();
    VoicePlayer.factoryOverride = () => _FakePlayer();
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false}) => Text('video:$url', key: const Key('fake-video'));
  });
  tearDown(() {
    VoiceRecordSession.factoryOverride = null;
    VoicePlayer.factoryOverride = null;
    VideoView.factoryOverride = null;
    profileLinkOpenOverride = null;
  });

  group('models', () {
    test('ProfileV2.fromJson tolerates missing fields and builds link hrefs', () {
      final p = ProfileV2.fromJson({'id': 'SA1', 'nickname': 'x', 'links': [{'kind': 'x', 'value': '@amr'}, {'kind': 'bogus', 'value': 'example.com'}], 'intro': {'kind': 'video', 'url': '/chat/media/a.mp4', 'sec': 28}});
      expect(p.name, 'x');
      expect(p.links.first.href, 'https://x.com/amr');
      expect(p.links[1].kind, 'other');
      expect(p.links[1].href, 'https://example.com');
      expect(p.intro!.isVideo, isTrue);
      expect(p.intro!.durationText, '0:28');
      expect(p.stats.followers, 0);
      expect(p.flags.canMessage, isTrue, reason: 'الافتراضي مسموح');
      expect(ProfileV2.fromJson({'data': []}).id, '');
      expect(const HandleCheck(valid: true, available: false, reason: 'taken').text, 'الاسم محجوز');
      expect(monthYear(DateTime(2025, 3, 5)), 'مارس 2025');
      expect(const ProfileStats7(visits7: 312, visits7Prev: 220).visitsDeltaPct, 42);
    });
  });

  group('visitor', () {
    testWidgets('renders cover, name, tag, links, intro, stats, trust chips and tabs; follow toggles via POST/DELETE', (tester) async {
      final (srv, _) = await _pump(tester, const UserProfilePage(person: _sara));
      expect(srv.calls, contains('GET /profiles/SA0000002/v2'));
      expect(find.byKey(const Key('profile-cover')), findsOneWidget);
      expect(find.text('فهد الغامدي'), findsOneWidget);
      expect(find.byKey(const Key('verified-mark')), findsOneWidget);
      expect(find.byKey(const Key('job-tag')), findsOneWidget);
      expect(find.text('مصوّر'), findsOneWidget);
      expect(find.textContaining('@fahad.shots'), findsOneWidget);
      expect(find.textContaining('جدة · الشاطئ'), findsOneWidget);
      expect(find.text('أصوّر البحر والمقاهي في جدة'), findsOneWidget);
      expect(find.byKey(const Key('profile-link-0')), findsOneWidget);
      expect(find.text('fahadshots.sa'), findsOneWidget);
      expect(find.byKey(const Key('intro-card')), findsOneWidget);
      expect(find.text('فهد الغامدي يعرّف بنفسه'), findsOneWidget);
      expect(find.textContaining('0:42'), findsWidgets);
      expect(find.byKey(const Key('stats-row')), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('1212'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('بريد موثّق'), findsOneWidget);
      expect(find.text('يرد سريعاً'), findsOneWidget);
      expect(find.text('31 طلباً مكتملاً'), findsOneWidget);
      expect(find.text('عضو منذ مارس 2025'), findsOneWidget);
      expect(find.byKey(const Key('profile-tabs')), findsOneWidget);
      expect(find.text('مراسلة'), findsOneWidget);
      expect(find.text('إضافة صديق'), findsOneWidget);

      // المتابعة متفائلة ثم تُثبَّت من ردّ الخادم
      await tester.tap(find.byKey(const Key('follow-btn')));
      await tester.pump();
      expect(find.text('تتابعه'), findsOneWidget);
      await _settle(tester);
      expect(srv.calls, contains('POST /profiles/SA0000002/follow'));
      expect(find.text('1213'), findsOneWidget);
      await tester.tap(find.byKey(const Key('follow-btn')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /profiles/SA0000002/follow'));
      expect(find.text('متابعة'), findsOneWidget);
      expect(find.text('1212'), findsOneWidget);

      // الرابط يفتح خارجياً ويسجّل حدثاً
      final opened = <Uri>[];
      profileLinkOpenOverride = (u) async => opened.add(u);
      await tester.tap(find.byKey(const Key('profile-link-0')));
      await _settle(tester);
      expect(opened.single.toString(), 'https://instagram.com/fahad.shots');
      expect(srv.bodies['POST /profiles/SA0000002/event']?['kind'], 'link');

      // تشغيل التعريف الصوتي
      await tester.tap(find.byKey(const Key('intro-play')));
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('tabs: posts grid opens the viewer, market grid opens the listing, services from the core profile, about hides the SA id', (tester) async {
      await _pump(tester, const UserProfilePage(person: _sara), height: 1800);
      expect(find.byKey(const Key('posts-grid')), findsOneWidget);
      expect(find.text('غروب أبحر'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-market')));
      await _settle(tester);
      expect(find.byKey(const Key('market-grid')), findsOneWidget);
      await tester.tap(find.text('كاميرا فوجي X-T20'));
      await _settle(tester);
      expect(find.byType(ListingPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(ListingPage))).pop();
      await _settle(tester);
      expect(find.byType(ListingPage, skipOffstage: false), findsNothing);

      await tester.tap(find.byKey(const Key('tab-services')));
      await _settle(tester);
      expect(find.text('جلسة تصوير شخصية'), findsOneWidget);

      // الرقائق الأخيرة خارج عرض الشريط الأفقي في الاختبار (خط Ahem عريض) فنُظهرها أولاً
      await tester.ensureVisible(find.byKey(const Key('tab-reviews')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tab-reviews')));
      await _settle(tester);
      expect(find.text('47 تقييماً'), findsWidgets);

      await tester.ensureVisible(find.byKey(const Key('tab-about')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tab-about')));
      await _settle(tester);
      expect(find.text('تصوير بورتريه'), findsOneWidget);
      expect(find.text('يظهر للأصدقاء فقط'), findsOneWidget, reason: 'الرقم SA لغير الأصدقاء مخفي');
      expect(find.text('SA0000002'), findsNothing);
    });

    testWidgets('message button records an event and opens the chat; canMessage=false hides it with a hint', (tester) async {
      final (srv, _) = await _pump(tester, const UserProfilePage(person: _sara));
      await tester.tap(find.byKey(const Key('message-btn')));
      await _settle(tester);
      expect(find.byType(ChatThreadPage), findsOneWidget);
      expect(srv.bodies['POST /profiles/SA0000002/event']?['kind'], 'message');
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, const UserProfilePage(person: _sara), srv: _Srv()..canMessage = false);
      expect(find.text('مراسلة'), findsNothing);
      expect(find.byKey(const Key('message-off')), findsOneWidget);
      expect(find.text('لا يستقبل رسائل من غير الأصدقاء'), findsOneWidget);
      expect(find.byKey(const Key('follow-btn')), findsOneWidget, reason: 'المتابعة تبقى متاحة');
    });

    testWidgets('a private profile shows the header and a locked state without tabs', (tester) async {
      await _pump(tester, const UserProfilePage(person: _sara), srv: _Srv()..private = true);
      expect(find.text('فهد الغامدي'), findsOneWidget);
      expect(find.byKey(const Key('private-state')), findsOneWidget);
      expect(find.text('ملف خاص'), findsOneWidget);
      expect(find.byKey(const Key('profile-tabs')), findsNothing);
      expect(find.byKey(const Key('stats-row')), findsNothing);
    });

    testWidgets('without v2 on the server the page still works from the core profile', (tester) async {
      await _pump(tester, const UserProfilePage(person: _sara), srv: _Srv()..v2 = false);
      expect(find.text('fahad.shots'), findsOneWidget, reason: 'الاسم من النك نيم');
      expect(find.text('أصوّر البحر والمقاهي في جدة'), findsOneWidget);
      expect(find.byKey(const Key('follow-btn')), findsNothing);
      expect(find.byKey(const Key('stats-row')), findsNothing);
      expect(find.byKey(const Key('profile-tabs')), findsOneWidget);
    });

    testWidgets('my own profile offers «تعديل الملف» which opens the edit page', (tester) async {
      await _pump(tester, const UserProfilePage(person: Person(id: 'SA0000001', nickname: 'amr')));
      expect(find.textContaining('هذا ملفك'), findsOneWidget);
      expect(find.byKey(const Key('follow-btn')), findsNothing);
      await tester.tap(find.byKey(const Key('edit-profile-btn')));
      await _settle(tester);
      expect(find.byType(EditProfilePage), findsOneWidget);
    });
  });

  group('edit', () {
    testWidgets('loads current values and saves core + v2 fields (PUT bodies)', (tester) async {
      final (srv, _) = await _pump(tester, const EditProfilePage(), height: 2200);
      expect(tester.widget<TextField>(find.byKey(const Key('edit-name'))).controller!.text, 'عمرو');
      expect(tester.widget<TextField>(find.byKey(const Key('edit-bio'))).controller!.text, 'نبذة');
      expect(find.text('مونتاج'), findsOneWidget, reason: 'مهارات النواة');
      await tester.enterText(find.byKey(const Key('edit-name')), 'عمرو شعيب');
      await tester.enterText(find.byKey(const Key('edit-bio')), 'أبني ناس لايف');
      await tester.tap(find.byKey(const Key('acct-pro')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('edit-job')), 'مؤسس');
      await tester.ensureVisible(find.byKey(const Key('link-add')));
      await tester.tap(find.byKey(const Key('link-add')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('link-value-0')), '@amr');
      await tester.tap(find.byKey(const Key('edit-save')));
      await _settle(tester);
      final core = srv.bodies['PUT /me/profile']!;
      expect(core['bio'], 'أبني ناس لايف');
      expect(core['accountType'], 'pro');
      expect(core['skills'], ['مونتاج']);
      final v2 = srv.puts.single;
      expect(v2['displayName'], 'عمرو شعيب');
      expect(v2['jobTitle'], 'مؤسس');
      expect(v2['city'], 'جدة');
      expect(v2['district'], 'الروضة');
      expect(v2['links'], [{'kind': 'instagram', 'value': '@amr'}]);
      expect(find.byType(EditProfilePage), findsNothing, reason: 'يُغلق بعد الحفظ');
    });

    testWidgets('handle availability is checked after a 400ms debounce', (tester) async {
      final (srv, _) = await _pump(tester, const EditProfilePage(), height: 2200);
      await tester.enterText(find.byKey(const Key('edit-handle')), 'sara');
      await tester.pump(const Duration(milliseconds: 200));
      expect(srv.calls.where((c) => c.startsWith('GET /handles/check')), isEmpty, reason: 'قبل انتهاء المهلة');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(srv.calls, contains('GET /handles/check?nickname=sara'));
      expect(find.text('الاسم محجوز'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('edit-handle')), 'fahad.new');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('متاح'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('edit-handle')), 'amr');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('handle-status')), findsNothing, reason: 'الاسم الحالي بلا فحص');
    });

    testWidgets('voice intro: record, stop, listen, then upload and PUT /me/profile/intro with kind voice', (tester) async {
      final (srv, _) = await _pump(tester, const EditProfilePage(), srv: _Srv()..intro = null, height: 2200);
      await tester.tap(find.byKey(const Key('intro-voice')));
      await tester.pump();
      expect(find.text('اضغط للتسجيل'), findsOneWidget);
      await tester.tap(find.byKey(const Key('intro-record')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('intro-stop')), findsOneWidget);
      expect(find.textContaining('0:03'), findsOneWidget, reason: 'المؤقّت الحي');
      await tester.tap(find.byKey(const Key('intro-stop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('intro-preview-play')), findsOneWidget);
      await tester.tap(find.byKey(const Key('intro-preview-play')));
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('intro-use')));
      await _settle(tester);
      expect(srv.calls, containsAllInOrder(['POST /chat/upload', 'PUT /me/profile/intro']));
      final b = srv.bodies['PUT /me/profile/intro']!;
      expect(b['kind'], 'voice');
      expect(b['url'], '/chat/media/voice1.weba');
      expect(b['sec'], 3);
      expect(find.byKey(const Key('intro-card')), findsOneWidget, reason: 'التعريف المحفوظ يظهر مع إعادة التسجيل والحذف');
      await tester.tap(find.byKey(const Key('intro-delete')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /me/profile/intro'));
      expect(find.byKey(const Key('intro-card')), findsNothing);
    });

    testWidgets('avatar upload sets the session picture and can be removed', (tester) async {
      final (srv, container) = await _pump(tester, const EditProfilePage(), height: 2200);
      expect(find.text('إضافة صورة'), findsOneWidget);
      expect(find.text('تعديل الملف'), findsOneWidget);
      // منتقي الصور بديل
      pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'a.jpg');
      addTearDown(() => pickImageOverride = null);
      await tester.tap(find.byKey(const Key('edit-avatar')));
      await _settle(tester);
      expect(srv.calls, containsAllInOrder(['POST /chat/upload', 'POST /profile/avatar']));
      expect(container.read(appStateProvider).user?.avatarUrl, isNotNull);
      expect(find.text('تغيير الصورة'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-avatar-remove')));
      await _settle(tester);
      expect(srv.calls, contains('DELETE /profile/avatar'));
      expect(find.text('إضافة صورة'), findsOneWidget);
    });
  });

  group('privacy & control', () {
    testWidgets('segments and switches PUT the right keys; «ملف عام» goes to the core profile', (tester) async {
      final (srv, _) = await _pump(tester, const PrivacyControlPage(), height: 1800);
      expect(find.text('موثّق'), findsOneWidget);
      expect(find.text('قريباً'), findsNWidgets(3));
      await tester.tap(find.text('الأصدقاء'));
      await _settle(tester);
      expect(srv.puts.last, {'msgPolicy': 'friends'});
      await tester.tap(find.byKey(const Key('show-city')));
      await _settle(tester);
      expect(srv.puts.last, {'showCity': false});
      await tester.tap(find.byKey(const Key('intro-visibility')));
      await _settle(tester);
      expect(srv.puts.last, {'introVisibility': 'friends'});
      await tester.tap(find.byKey(const Key('show-friends')));
      await _settle(tester);
      expect(srv.puts.last, {'showFriends': true});
      await tester.tap(find.byKey(const Key('show-online')));
      await _settle(tester);
      expect(srv.puts.last, {'showOnline': false});
      await tester.ensureVisible(find.byKey(const Key('profile-public')));
      await tester.tap(find.byKey(const Key('profile-public')));
      await _settle(tester);
      expect(srv.bodies['PUT /me/profile'], {'isPublic': false});
      expect(find.byKey(const Key('safety-blocked')), findsOneWidget);
    });
  });

  group('myspace', () {
    testWidgets('shows the intro card, completion percentage with steps and the 7-day row; rows open the new pages', (tester) async {
      await _pump(tester, const Scaffold(body: MySpacePage()), height: 2400);
      expect(find.byKey(const Key('owner-cards')), findsOneWidget);
      expect(find.byKey(const Key('intro-card')), findsOneWidget);
      expect(find.byKey(const Key('intro-change')), findsOneWidget);
      expect(find.text('اكتمال الملف 60٪'), findsOneWidget);
      expect(find.text('3 خطوات متبقية'), findsOneWidget);
      expect(find.byKey(const Key('stats7-row')), findsOneWidget);
      expect(find.text('312'), findsOneWidget);
      expect(find.text('زيارات الملف'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('+42٪'), findsOneWidget);
      await tester.tap(find.byKey(const Key('completion-avatar')));
      await _settle(tester);
      expect(find.byType(EditProfilePage), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-cancel')));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('view-public-profile')));
      await tester.tap(find.byKey(const Key('view-public-profile')));
      await _settle(tester);
      expect(find.byType(UserProfilePage), findsOneWidget);
      Navigator.of(tester.element(find.byType(UserProfilePage))).pop();
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('privacy-control')));
      await tester.tap(find.byKey(const Key('privacy-control')));
      await _settle(tester);
      expect(find.byType(PrivacyControlPage), findsOneWidget);
    });

    testWidgets('without an intro the dashed call-to-action opens the edit page; without v2 nothing extra is shown', (tester) async {
      await _pump(tester, const Scaffold(body: MySpacePage()), srv: _Srv()..intro = null, height: 2400);
      expect(find.byKey(const Key('intro-cta')), findsOneWidget);
      await tester.tap(find.byKey(const Key('intro-cta')));
      await _settle(tester);
      expect(find.byType(EditProfilePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, const Scaffold(body: MySpacePage()), srv: _Srv()..v2 = false, height: 2400);
      expect(find.byKey(const Key('owner-cards')), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget, reason: 'زر التعديل يبقى');
    });
  });
}
