// «لحظة الألبوم» (docs/moments.md «الألبوم»): لحظة الصورة تحمل حتى 8 صور. العارض ينقطها ويُسحب بينها يميناً ويساراً والنقر
// بين اللحظات كما كان، والسحب بعد طرفيه إلى اللحظة المجاورة، ومدتها أربع ثوانٍ لكل صورة (سبع على الأقل) والشريط يقلبها،
// والطبقة الصوتية تمدّها كما كانت، والصورة التالية تُجلب مسبقاً؛ والبطاقات («اللحظات» وبطاقة الصف و«لحظات هنا») تعرض الغلاف
// وشارة العدد، واللحظة القديمة بصورة واحدة كما كانت.
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
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/row_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/pages/admin/admin_reports.dart';
import 'package:naslook/pages/home/row_deck.dart';
import 'package:naslook/pages/posts/overlay_canvas.dart';
import 'package:naslook/pages/posts/place_moments.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/pages/posts/timeline_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

String _pid(int i) => 'cccccccc-0000-4000-8000-${i.toString().padLeft(12, '0')}';
String _photo(int i, int k) => 'https://test.local/chat/media/al$i-$k.jpg';

/// لحظة بصيغة /mapposts: [photos] > 1 = ألبوم (media والغلاف أولاً)، 1 = صورة واحدة بلا media (خادم أقدم)، 0 = نص
Map<String, dynamic> _post(int i, {int photos = 1, int? audioSec, List<Map<String, dynamic>> overlays = const []}) => {
      'id': _pid(i), 'user': {'id': 'SA000000${i + 1}', 'nickname': 'user$i'}, 'kind': photos == 0 ? 'text' : 'image', 'caption': 'لحظة $i',
      'mediaUrl': photos == 0 ? null : _photo(i, 0), if (photos > 1) 'media': [for (var k = 0; k < photos; k++) _photo(i, k)], 'bg': photos == 0 ? '#37474F' : null,
      'overlays': overlays, 'tag': 'moment', 'lat': 21.54, 'lng': 39.17, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false, 'audience': 'all',
      if (audioSec != null) 'audioUrl': 'https://test.local/chat/media/voice$i.m4a',
      if (audioSec != null) 'audioSec': audioSec,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
    };

/// بطاقة لحظة كما يبنيها server/row.js (الصورة = الغلاف، والحمولة المنشور)
Map<String, dynamic> _momentItem(Map<String, dynamic> p) => {
      'kind': 'moment', 'id': p['id'], 'refId': p['id'], 'title': p['caption'], 'subtitle': 'الآن', 'who': (p['user'] as Map)['nickname'], 'logoUrl': null,
      'imageUrl': p['mediaUrl'], 'lat': p['lat'], 'lng': p['lng'], 'distanceKm': 0.4, 'at': p['createdAt'], 'feedAt': p['createdAt'], 'endsAt': p['expiresAt'], 'act': 'شاهد', 'payload': p,
    };

class _Srv {
  List<Map<String, dynamic>> feed = [];
  List<Map<String, dynamic>> place = [];
  /// طابور الإشراف (GET /adminapi/moderation)
  List<Map<String, dynamic>> moderation = [];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    if (key == 'GET /adminapi/reports') return _json({'available': true, 'items': []});
    if (key == 'GET /adminapi/moderation') {
      return _json({'status': 'open', 'open': moderation.length, 'threshold': 3, 'actions': ['dismiss', 'hide', 'restore', 'suspend-owner'], 'types': [{'id': 'post', 'name': 'منشور'}], 'items': moderation});
    }
    if (key == 'GET /feed') return _json({'items': feed, 'next': null, 'located': true});
    if (key == 'GET /mapposts/feed') return _json({'items': place, 'nextCursor': null, 'located': false, 'radiusKm': 200});
    if (req.method == 'POST' && req.url.path.endsWith('/view')) return _json({'ok': true, 'views': 2});
    if (key == 'GET /live/wait') return _json({'seq': 0, 'events': [], 'reset': false});
    if (key == 'GET /row') return _json({'items': [], 'located': true});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /settings/public') return _json({'announcement': '', 'maintenance': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _app(WidgetTester tester, Widget home, {_Srv? srv, Size size = const Size(420, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.54, 39.17);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    // التطبيق عربي من اليمين إلى اليسار كما في الإنتاج
    child: MaterialApp(locale: const Locale('ar'), builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return s;
}

Future<void> _viewer(WidgetTester tester, List<Map<String, dynamic>> posts, {int initial = 0}) =>
    _app(tester, PostViewerPage(posts: [for (final p in posts) MapPost.fromJson(p)], initial: initial));

/// نبضات متتالية بقدر [ms] (مؤقّت العارض كل 50 م.ث)
Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _progress(WidgetTester tester, [int i = 0]) => tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).elementAt(i).widthFactor!;

/// اللحظة المعروضة: اسم ناشرها في الشريط العلوي
bool _showing(String nick) => find.text(nick).hitTestable().evaluate().isNotEmpty;

/// السحب إلى الصورة التالية: في العربية (من اليمين إلى اليسار) التالية على اليسار فيُسحب الإصبع إلى اليمين، كصفحات العارض نفسها
Future<void> _swipe(WidgetTester tester, {bool next = true}) async {
  await tester.drag(find.byKey(const Key('moment-album')), Offset(next ? 300 : -300, 0));
  await _frames(tester, 400);
}

class _FakeVoice extends VoicePlayerBase {
  static final created = <_FakeVoice>[];
  _FakeVoice() {
    created.add(this);
  }
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) => emit(const VoiceState());
  @override
  Future<void> play() async => emit(state.copyWith(playing: true, loading: false, ended: false, clearError: true));
  @override
  Future<void> pause() async => emit(state.copyWith(playing: false));
  @override
  Future<void> seek(Duration position) async => emit(state.copyWith(position: position));
  void at(int ms, {int? duration}) => emit(state.copyWith(position: Duration(milliseconds: ms), duration: duration == null ? null : Duration(milliseconds: duration)));
  void end() => emit(state.copyWith(playing: false, ended: true, position: Duration.zero));
}

void main() {
  final warmed = <String>[];
  setUp(() {
    warmed.clear();
    PostViewerPage.warmPhotoOverride = warmed.add;
    _FakeVoice.created.clear();
    VoicePlayer.factoryOverride = _FakeVoice.new;
  });
  tearDown(() {
    PostViewerPage.warmPhotoOverride = null;
    VoicePlayer.factoryOverride = null;
  });

  test('the model: media is the album with the cover first; an older server (no media) is the cover alone; labels', () {
    final a = MapPost.fromJson(_post(1, photos: 3));
    expect(a.isAlbum, isTrue);
    expect(a.album, [_photo(1, 0), _photo(1, 1), _photo(1, 2)]);
    final one = MapPost.fromJson(_post(2));
    expect(one.isAlbum, isFalse);
    expect(one.album, [_photo(2, 0)]);
    expect(MapPost.fromJson(_post(3, photos: 0)).album, isEmpty);
    // الغلاف هو mediaUrl دائماً ولو جاء غيره أول media
    final odd = MapPost.fromJson({..._post(4, photos: 3), 'mediaUrl': _photo(4, 2)});
    expect(odd.album.first, _photo(4, 2));
    expect(odd.album.length, 3);
    expect(albumCountLabel(2), 'صورتان');
    expect(albumCountLabel(3), '3 صور');
    expect(albumCountOf(_post(5, photos: 4)), 4);
    expect(albumCountOf(_post(6)), 1);
    expect(albumCountOf(_post(7, photos: 0)), 1);
  });

  testWidgets('an album shows page dots; a swipe moves to the next photo and the bar jumps to its share, the moment stays', (tester) async {
    await _viewer(tester, [_post(1, photos: 3), _post(2)]);
    expect(find.byKey(const Key('moment-album')), findsOneWidget);
    expect(find.byKey(const Key('album-dots')), findsOneWidget);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
    expect(find.byKey(const Key('album-dot-1')), findsOneWidget);
    expect(find.byKey(const Key('album-dot-2')), findsOneWidget);
    await _swipe(tester);
    expect(find.byKey(const Key('album-dot-on-1')), findsOneWidget);
    expect(_showing('user1'), isTrue, reason: 'السحب بين صور الألبوم لا ينقل إلى لحظة أخرى');
    expect(_progress(tester), closeTo(1 / 3, .05), reason: 'لكل صورة بعدها حصتها من الوقت');
    await _swipe(tester, next: false);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
    expect(_progress(tester), lessThan(.1));
    expect(_showing('user1'), isTrue);
  });

  testWidgets('taps still move between moments, not photos', (tester) async {
    await _viewer(tester, [_post(1, photos: 3), _post(2)]);
    // في العربية: النصف الأيمن للتالية
    await tester.tapAt(const Offset(380, 200));
    await _frames(tester, 400);
    expect(_showing('user2'), isTrue);
    expect(find.byKey(const Key('album-dots')), findsNothing, reason: 'اللحظة التالية صورة واحدة');
  });

  testWidgets('the album lasts 4 s per photo (12 s for three): the bar flips the photos and the moment ends after the last', (tester) async {
    await _viewer(tester, [_post(1, photos: 3), _post(2)]);
    await _frames(tester, 3900);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
    await _frames(tester, 400);
    expect(find.byKey(const Key('album-dot-on-1')), findsOneWidget, reason: 'بعد أربع ثوانٍ الصورة الثانية');
    await _frames(tester, 3000);
    expect(_showing('user1'), isTrue, reason: 'لا انتقال بعد سبع ثوانٍ: الألبوم أطول');
    await _frames(tester, 1000);
    expect(find.byKey(const Key('album-dot-on-2')), findsOneWidget);
    await _frames(tester, 3600);
    await _frames(tester, 400);
    expect(_showing('user2'), isTrue, reason: 'بعد 12 ثانية اللحظة التالية');
  });

  testWidgets('two photos: 8 s (4 s each, above the 7 s floor), the second photo at 4 s', (tester) async {
    await _viewer(tester, [_post(1, photos: 2), _post(2)]);
    await _frames(tester, 3800);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
    await _frames(tester, 300);
    expect(find.byKey(const Key('album-dot-on-1')), findsOneWidget);
    await _frames(tester, 3500);
    expect(_showing('user1'), isTrue, reason: 'لا انتقال بعد سبع ثوانٍ');
    await _frames(tester, 700);
    expect(_showing('user2'), isTrue);
  });

  testWidgets('swiping past the last photo goes to the next moment, and before the first to the previous one', (tester) async {
    await _viewer(tester, [_post(0), _post(1, photos: 2), _post(2)], initial: 1);
    await _swipe(tester);
    expect(find.byKey(const Key('album-dot-on-1')), findsOneWidget);
    await _swipe(tester);
    expect(_showing('user2'), isTrue, reason: 'بعد آخر صورة: اللحظة التالية');
    // رجوع إلى الألبوم يبدأ من غلافه، والسحب قبله إلى السابقة
    await tester.tapAt(const Offset(40, 200));
    await _frames(tester, 400);
    expect(_showing('user1'), isTrue);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
    await _swipe(tester, next: false);
    expect(_showing('user0'), isTrue, reason: 'قبل أول صورة: اللحظة السابقة');
  });

  testWidgets('the next photo is fetched ahead: photo 2 on show, photo 3 once photo 2 is shown', (tester) async {
    await _viewer(tester, [_post(1, photos: 3)]);
    await tester.pump();
    expect(warmed, [mediaUrl(_photo(1, 1))]);
    await _swipe(tester);
    expect(warmed, [mediaUrl(_photo(1, 1)), mediaUrl(_photo(1, 2))]);
  });

  testWidgets('a single-photo moment from before albums looks as before: no dots, no album pager', (tester) async {
    await _viewer(tester, [_post(1), _post(2)]);
    expect(find.byKey(const Key('moment-album')), findsNothing);
    expect(find.byKey(const Key('album-dots')), findsNothing);
    expect(warmed, isEmpty);
    await _frames(tester, 6800);
    expect(_showing('user1'), isTrue);
    await _frames(tester, 600);
    expect(_showing('user2'), isTrue, reason: 'سبع ثوانٍ كما كانت');
  });

  testWidgets('the text and stickers drawn on the cover show with the cover only', (tester) async {
    await _viewer(tester, [_post(1, photos: 3, overlays: [{'type': 'text', 'text': 'على الغلاف', 'x': .5, 'y': .4}])]);
    double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: find.byType(OverlayCanvas), matching: find.byType(AnimatedOpacity)).first).opacity;
    expect(opacity(), 1);
    await _swipe(tester);
    expect(opacity(), 0);
    await _swipe(tester, next: false);
    expect(opacity(), 1);
  });

  testWidgets('voice rules unchanged: a 20 s recording on a 3-photo album holds it 20 s and the photos follow the recording', (tester) async {
    await _viewer(tester, [_post(1, photos: 3, audioSec: 20), _post(2)]);
    final v = _FakeVoice.created.single;
    for (var t = 0; t <= 12000; t += 250) {
      v.at(t, duration: 20000);
      await _frames(tester, 250);
    }
    expect(_showing('user1'), isTrue, reason: 'التسجيل أطول من 12 ثانية الألبوم');
    expect(find.byKey(const Key('album-dot-on-1')), findsOneWidget, reason: 'ثلث العشرين ≈ 6.7 ث: الثانية');
    for (var t = 12250; t <= 14000; t += 250) {
      v.at(t, duration: 20000);
      await _frames(tester, 250);
    }
    expect(find.byKey(const Key('album-dot-on-2')), findsOneWidget);
    v.end();
    await _frames(tester, 400);
    expect(_showing('user2'), isTrue, reason: 'انتهى التسجيل بعد مدة الألبوم: التالية');
  });

  testWidgets('voice rules unchanged: a 3 s recording on a 3-photo album keeps the album its 12 s', (tester) async {
    await _viewer(tester, [_post(1, photos: 3, audioSec: 3), _post(2)]);
    final v = _FakeVoice.created.single;
    for (var t = 0; t <= 3000; t += 250) {
      v.at(t, duration: 3000);
      await _frames(tester, 250);
    }
    v.end();
    await _frames(tester, 6000);
    expect(_showing('user1'), isTrue, reason: 'لا انتقال بعد سبع ثوانٍ');
    expect(find.byKey(const Key('album-dot-on-2')), findsOneWidget);
    await _frames(tester, 3400);
    expect(_showing('user2'), isTrue);
  });

  testWidgets('cards: the home row card shows the cover with «3 صور», a single photo has no badge', (tester) async {
    Future<void> deck(RowItem it) async {
      await tester.pumpWidget(MaterialApp(locale: const Locale('ar'), home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: RowDeck(key: ValueKey(it.id), items: [it], index: 0, onIndex: (_) {}, onAct: (_) {})))));
      await tester.pump();
    }
    await deck(RowItem.fromJson(_momentItem(_post(1, photos: 3))));
    expect(find.byKey(const Key('row-album')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('row-album')), matching: find.text('3 صور')), findsOneWidget);
    await deck(RowItem.fromJson(_momentItem(_post(2))));
    expect(find.byKey(const Key('row-album')), findsNothing);
  });

  testWidgets('cards: «اللحظات» shows the album cover with its count, a single photo none', (tester) async {
    final srv = _Srv()..feed = [_momentItem(_post(1, photos: 4)), _momentItem(_post(2))];
    await _app(tester, const TimelinePage(), srv: srv);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(Key('tl-post-${_pid(1)}')), findsOneWidget);
    expect(find.byKey(Key('tl-album-${_pid(1)}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('tl-album-${_pid(1)}')), matching: find.text('4 صور')), findsOneWidget);
    expect(find.byKey(Key('tl-album-${_pid(2)}')), findsNothing);
  });

  testWidgets('cards: «لحظات هنا» shows «صورتان» on a two-photo album, and opening it shows its dots', (tester) async {
    final srv = _Srv()..place = [_post(1, photos: 2), _post(2)];
    await _app(tester, const Scaffold(body: SingleChildScrollView(child: PlaceMomentsEntry(bizId: 'biz-cafe'))), srv: srv);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(Key('place-moment-album-${_pid(1)}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('place-moment-album-${_pid(1)}')), matching: find.text('صورتان')), findsOneWidget);
    expect(find.byKey(Key('place-moment-album-${_pid(2)}')), findsNothing);
    await tester.tap(find.byKey(Key('place-moment-${_pid(1)}')));
    await _frames(tester, 600);
    expect(find.byKey(const Key('album-dots')), findsOneWidget);
    expect(find.byKey(const Key('album-dot-on-0')), findsOneWidget);
  });

  testWidgets('moderation: a reported album shows every photo to the moderator, a single photo only its cover', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    Map<String, dynamic> item(int i, List<String> photos) => {
          'targetType': 'post', 'targetId': _pid(i), 'typeName': 'منشور', 'reports': 2, 'reasons': ['مسيء'], 'firstAt': now, 'lastAt': now,
          'owner': {'id': 'SA0000002', 'nickname': 'sara'}, 'title': 'لحظة $i', 'text': '', 'mediaUrl': photos.first, if (photos.length > 1) 'mediaUrls': photos, 'status': 'visible', 'hidden': false,
        };
    final srv = _Srv()..moderation = [item(1, [_photo(1, 0), _photo(1, 1), _photo(1, 2)]), item(2, [_photo(2, 0)])];
    await _app(tester, const Scaffold(body: AdminReportsPage()), srv: srv, size: const Size(700, 1400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('reports-tab-content')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final strip = find.byKey(Key('mod-album-post-${_pid(1)}'));
    expect(strip, findsOneWidget);
    expect(find.descendant(of: strip, matching: find.byType(Image)), findsNWidgets(3));
    expect(find.byKey(Key('mod-album-post-${_pid(2)}')), findsNothing);
  });
}
