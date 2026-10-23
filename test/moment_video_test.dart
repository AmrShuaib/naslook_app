// فيديو اللحظات كسناب (قرار المالك): في العارض يبدأ فوراً بالصوت وبلا أزرار فوق غلافه حتى أول إطار، وإن رفض المتصفح الصوت
// يعمل صامتاً برقاقة «اضغط لتشغيل الصوت»؛ شريط التقدّم يتبع المقطع وانتهاؤه ينقل إلى التالية؛ الضغط المطوّل بحسب الجهة الفعلية
// (يمين تسريع 2x، يسار ترجيع، وسط إيقاف) والنقر كما في الصور؛ اللحظة التالية تُسخَّن مسبقاً؛ وبطاقات «اللحظات» تدور على
// المعاينة الخفيفة /chat/vpreview وتعود إلى المقطع الكامل إن تعذّرت.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/video_view.dart';
import 'package:naslook/pages/posts/post_media.dart';
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

String _pid(int i) => 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}';
/// اسم ملف بصيغة /chat/upload حتى تُشتق منه روابط المصغّر والمعاينة الخفيفة
String _name(int i) => 'k9x1z$i-ab12cd34ef56ab12cd34ef5$i.mp4';
String _media(int i) => 'https://test.local/chat/media/${_name(i)}';

Map<String, dynamic> _post(int i, {String kind = 'video', String caption = ''}) => {
      'id': _pid(i), 'user': {'id': 'SA000000${i + 1}', 'nickname': 'user$i'}, 'kind': kind, 'caption': caption.isEmpty ? 'لحظة $i' : caption,
      'mediaUrl': kind == 'text' ? null : kind == 'video' ? _media(i) : 'https://test.local/chat/media/p$i.jpg', 'bg': kind == 'text' ? '#37474F' : null,
      'overlays': [], 'tag': 'moment', 'lat': 21.5, 'lng': 39.2, 'durationSec': 10, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
    };

/// مشغّل وهمي يرتبط بمتحكم العارض: يسجّل الأوامر ويبلّغ حالته كما يفعل عنصر <video>، والاختبار يحاكي الموضع والانتهاء والرفض.
class _FakeVideo extends StatefulWidget {
  final String url;
  final VideoViewController controller;
  final bool autoplay, loop, muted;
  const _FakeVideo(this.url, this.controller, {required this.autoplay, required this.loop, required this.muted});
  @override
  State<_FakeVideo> createState() => _FakeVideoState();
}

final _videos = <_FakeVideoState>[];

class _FakeVideoState extends State<_FakeVideo> implements VideoViewBackend {
  final calls = <String>[];
  bool disposed = false;
  VideoViewController get c => widget.controller;
  String get url => widget.url;

  void report(VideoPlayback Function(VideoPlayback s) f) => c.report(f(c.value));

  @override
  void initState() {
    super.initState();
    _videos.add(this);
    c.attach(this);
    if (widget.autoplay && c.wantsPlaying && !c.suspended) {
      calls.add('autoplay');
      c.report(c.value.copyWith(playing: true, muted: c.wantsMuted ?? widget.muted));
    }
  }

  @override
  void play() {
    calls.add('play');
    report((s) => s.copyWith(playing: true));
  }

  @override
  void pause() {
    calls.add('pause');
    report((s) => s.copyWith(playing: false));
  }

  @override
  void setRate(double rate) {
    calls.add('rate:$rate');
    report((s) => s.copyWith(rate: rate));
  }

  @override
  void seekBy(Duration delta) {
    calls.add('seek:${delta.inMilliseconds}');
    var p = c.value.position + delta;
    if (p < Duration.zero) p = Duration.zero;
    report((s) => s.copyWith(position: p));
  }

  @override
  void setMuted(bool muted) {
    calls.add('muted:$muted');
    report((s) => s.copyWith(muted: muted, soundBlocked: muted && s.soundBlocked));
  }

  @override
  void dispose() {
    disposed = true;
    c.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(key: const Key('fake-moment-video'), color: Colors.black);
}

class _Srv {
  final calls = <String>[];
  /// طلبات الوسائط بترويسة Range (التسخين المسبق)
  final ranges = <String>[];
  List<Map<String, dynamic>> feed = [];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.url.path.startsWith('/chat/media/')) {
      ranges.add('${req.url.path} ${req.headers['Range'] ?? req.headers['range'] ?? '-'}');
      return http.Response.bytes(List.filled(16, 0), 206, headers: {'content-type': 'video/mp4'});
    }
    if (req.method == 'POST' && req.url.path.endsWith('/view')) return _json({'ok': true, 'views': 2});
    if (key == 'GET /feed') return _json({'items': feed, 'next': null, 'located': true});
    if (key == 'GET /live/wait') return _json({'seq': 0, 'events': [], 'reset': false});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {bool noAnimations = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    // التطبيق عربي من اليمين إلى اليسار: الجهات الفعلية للضغط المطوّل يجب ألا تنعكس
    child: MaterialApp(
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: noAnimations ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!) : child!,
      ),
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return srv;
}

Future<_Srv> _viewer(WidgetTester tester, List<Map<String, dynamic>> posts, {int initial = 0, bool noAnimations = false}) =>
    _pump(tester, PostViewerPage(posts: [for (final p in posts) MapPost.fromJson(p)], initial: initial), noAnimations: noAnimations);

/// عرض شريط تقدّم اللحظة الأولى في الصفحة الظاهرة
double _progress(WidgetTester tester, [int i = 0]) => tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).elementAt(i).widthFactor!;

Rect _zone(WidgetTester tester) => tester.getRect(find.byKey(const Key('moment-video-zone')));

/// إطارات متتالية تكفي لاكتمال حركة الانتقال بين اللحظات (220 م.ث)
Future<void> _frames(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// ضغطة مطوّلة عند [at] تبقى مضغوطة حتى يُستدعى up على الإيماءة المعادة
Future<TestGesture> _hold(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 600));
  return g;
}

void main() {
  setUp(() {
    _videos.clear();
    VideoView.controlledFactoryOverride = (url, controller, {autoplay = false, loop = false, muted = false, poster}) => _FakeVideo(url, controller, autoplay: autoplay, loop: loop, muted: muted);
  });
  tearDown(() {
    VideoView.controlledFactoryOverride = null;
    VideoView.factoryOverride = null;
    momentRangeWarmOverride = null;
    DeviceLocation.override = null;
  });

  group('VideoViewController', () {
    test('keeps wishes made before a player attaches, ignores everything after dispose, and fires ended once', () async {
      final c = VideoViewController();
      c.setRate(2);
      c.setMuted(true);
      c.pause();
      expect(c.rate, 2);
      expect(c.wantsMuted, isTrue);
      expect(c.wantsPlaying, isFalse);
      var ended = 0;
      final sub = c.onEnded.listen((_) => ended++);
      c.report(const VideoPlayback(duration: Duration(seconds: 4), position: Duration(seconds: 3), playing: true));
      expect(c.estimatedPosition, greaterThanOrEqualTo(const Duration(seconds: 3)));
      expect(c.estimatedPosition, lessThanOrEqualTo(const Duration(seconds: 4)));
      c.report(c.value.copyWith(ended: true, playing: false, position: const Duration(seconds: 4)));
      c.report(c.value.copyWith(position: const Duration(seconds: 4)));
      await Future<void>.delayed(Duration.zero);
      expect(ended, 1);
      await sub.cancel();
      c.dispose();
      c.report(const VideoPlayback(failed: true));
      c.play();
      expect(c.value.failed, isFalse);
      expect(c.disposed, isTrue);
    });

    test('the light preview URL is derived only from our uploaded file names', () {
      expect(videoPreviewUrl('https://www.naslife.app/chat/media/${_name(1)}'), endsWith('/chat/vpreview/${_name(1)}'));
      expect(videoPreviewUrl('/chat/media/${_name(2)}'), endsWith('/chat/vpreview/${_name(2)}'));
      expect(videoPreviewUrl('https://test.local/chat/media/p1.mp4'), isNull);
      expect(videoPreviewUrl('https://example.com/v.mp4'), isNull);
    });
  });

  group('moment viewer video', () {
    testWidgets('starts at once with sound and no controls, over its poster until the first frame', (tester) async {
      await _viewer(tester, [_post(1), _post(2, kind: 'image')]);
      final v = _videos.single;
      expect(v.url, _media(1));
      expect(v.calls, ['autoplay']);
      expect(v.c.value.muted, isFalse);
      expect(find.byKey(const Key('fake-moment-video')), findsOneWidget);
      // لا زر تشغيل ولا شريط تحكم فوق المقطع
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
      final poster = tester.widget<Image>(find.byKey(const Key('moment-video-poster')));
      expect((poster.image as NetworkImage).url, 'https://test.local/chat/thumb/${_name(1)}');
      v.report((s) => s.copyWith(firstFrame: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('moment-video-poster')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('when the browser refuses sound it plays muted with a chip that unmutes on tap', (tester) async {
      await _viewer(tester, [_post(1)]);
      final v = _videos.single;
      expect(find.text('🔇 اضغط لتشغيل الصوت'), findsNothing);
      v.report((s) => s.copyWith(muted: true, soundBlocked: true, playing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('🔇 اضغط لتشغيل الصوت'), findsOneWidget);
      await tester.tap(find.byKey(const Key('moment-unmute')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // رفع الكتم ثم التشغيل في حدث اللمس نفسه (شرط المتصفح للصوت)
      expect(v.calls.sublist(1), ['muted:false', 'play']);
      expect(find.text('🔇 اضغط لتشغيل الصوت'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the progress bar follows the video and its end moves on to the next moment', (tester) async {
      await _viewer(tester, [_post(1), _post(2, kind: 'image', caption: 'الصورة التالية')]);
      final v = _videos.single;
      expect(_progress(tester), 0);
      v.report((s) => s.copyWith(duration: const Duration(seconds: 10), position: const Duration(seconds: 5), playing: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_progress(tester), closeTo(.5, .001));
      v.report((s) => s.copyWith(position: const Duration(seconds: 10), ended: true));
      await tester.pump();
      await _frames(tester);
      expect(find.text('الصورة التالية'), findsOneWidget);
      // مغادرة اللحظة تحرّر مشغّلها ومتحكمها
      expect(v.disposed, isTrue);
      expect(v.c.disposed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a video that fails to play advances like an image instead of stalling the viewer', (tester) async {
      await _viewer(tester, [_post(1), _post(2, kind: 'text', caption: 'نص بعد الفيديو')]);
      _videos.single.report((s) => s.copyWith(failed: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('moment-video-failed')), findsOneWidget);
      await _frames(tester, 6000);
      expect(find.text('نص بعد الفيديو'), findsNothing, reason: 'يعرض الفيديو المتعذّر مدة الصورة (7 ث)');
      await _frames(tester, 1500);
      expect(find.text('نص بعد الفيديو'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('long-press on the physical right plays 2x with a chip; release returns to normal speed', (tester) async {
      await _viewer(tester, [_post(1)]);
      final v = _videos.single;
      final r = _zone(tester);
      final g = await _hold(tester, Offset(r.right - 12, r.center.dy));
      expect(v.calls, containsAllInOrder(['rate:2.0', 'play']));
      expect(find.text('2x ⏩'), findsOneWidget);
      expect(find.text('⏪ 2x'), findsNothing);
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(v.calls.last, 'rate:1.0');
      expect(find.text('2x ⏩'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('long-press on the physical left rewinds 2x while held (pause + 200 ms back every 100 ms), then resumes', (tester) async {
      await _viewer(tester, [_post(1)]);
      final v = _videos.single;
      v.report((s) => s.copyWith(duration: const Duration(seconds: 10), position: const Duration(seconds: 5)));
      final r = _zone(tester);
      final g = await _hold(tester, Offset(r.left + 12, r.center.dy));
      expect(v.calls, contains('pause'));
      expect(v.calls.where((c) => c == 'rate:2.0'), isEmpty);
      expect(find.text('⏪ 2x'), findsOneWidget);
      final before = v.calls.where((c) => c == 'seek:-200').length;
      await tester.pump(const Duration(milliseconds: 300));
      final seeks = v.calls.where((c) => c == 'seek:-200').length;
      expect(seeks - before, 3, reason: 'قفزة 200 م.ث للخلف كل 100 م.ث = ضعف السرعة');
      expect(v.c.value.position, Duration(milliseconds: 5000 - 200 * seeks));
      expect(v.c.wantsPlaying, isFalse);
      await g.up();
      await tester.pump();
      expect(v.calls.last, 'play');
      await tester.pump(const Duration(milliseconds: 400));
      expect(v.calls.where((c) => c == 'seek:-200').length, seeks, reason: 'الترجيع يتوقف عند الرفع');
      expect(find.text('⏪ 2x'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('long-press in the middle pauses while held; a short tap on the physical right goes to the next moment', (tester) async {
      await _viewer(tester, [_post(1, kind: 'image', caption: 'الأولى'), _post(2, caption: 'الفيديو'), _post(3, kind: 'image', caption: 'الثالثة')], initial: 1);
      final v = _videos.single;
      final r = _zone(tester);
      final g = await _hold(tester, r.center);
      expect(v.calls.last, 'pause');
      expect(find.text('2x ⏩'), findsNothing);
      expect(find.text('⏪ 2x'), findsNothing);
      await g.up();
      await tester.pump();
      expect(v.calls.last, 'play');
      // كما في الصور (منطقتاها صف ينعكس مع الاتجاه): اليمين الفعلي للتالية
      await tester.tapAt(Offset(r.right - 30, r.center.dy));
      await tester.pump();
      await _frames(tester);
      expect(find.text('الثالثة'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a short tap on the physical left goes back, the same side as on images (RTL)', (tester) async {
      await _viewer(tester, [_post(1, kind: 'image', caption: 'الأولى'), _post(2, caption: 'الفيديو')], initial: 1);
      final r = _zone(tester);
      await tester.tapAt(Offset(r.left + 30, r.center.dy));
      await tester.pump();
      await _frames(tester);
      expect(find.text('الأولى'), findsOneWidget);
      expect(find.byKey(const Key('moment-video-zone')), findsNothing);
      // على الصورة: اليمين الفعلي يعود إلى التالية (الفيديو)
      await tester.tapAt(Offset(r.right - 30, 200));
      await tester.pump();
      await _frames(tester);
      expect(find.byKey(const Key('moment-video-zone')), findsOneWidget);
      expect(_videos, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('image moments keep today\'s behaviour: long-press anywhere pauses the auto-advance', (tester) async {
      await _viewer(tester, [_post(1, kind: 'image'), _post(2, kind: 'image')]);
      expect(find.byKey(const Key('moment-video-zone')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1000));
      final before = _progress(tester);
      expect(before, greaterThan(.1));
      final g = await _hold(tester, const Offset(60, 200));
      final held = _progress(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_progress(tester), held);
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_progress(tester), greaterThan(held));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chips appear without a fade when animations are disabled', (tester) async {
      await _viewer(tester, [_post(1)], noAnimations: true);
      final r = _zone(tester);
      final g = await _hold(tester, Offset(r.right - 12, r.center.dy));
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(const Key('moment-fast')), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 1);
      await g.up();
      await tester.pump();
      expect(find.byKey(const Key('moment-fast')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with animations on, the speed chip fades in', (tester) async {
      await _viewer(tester, [_post(1)]);
      final r = _zone(tester);
      final g = await _hold(tester, Offset(r.right - 12, r.center.dy));
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(const Key('moment-fast')), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, lessThan(1));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a route covering the viewer pauses the video and returning resumes it', (tester) async {
      await _viewer(tester, [_post(1)]);
      final v = _videos.single;
      unawaited(Navigator.of(tester.element(find.byType(PostViewerPage))).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('فوق العارض')))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(v.calls.last, 'pause');
      expect(v.c.wantsPlaying, isTrue, reason: 'إيقاف مؤقت لا يغيّر رغبة التشغيل');
      Navigator.of(tester.element(find.text('فوق العارض'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(v.calls.last, 'play');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('closing the viewer mid-rewind releases the player, controller and timers', (tester) async {
      await _viewer(tester, [_post(1)]);
      final v = _videos.single;
      final r = _zone(tester);
      final g = await _hold(tester, Offset(r.left + 12, r.center.dy));
      expect(find.text('⏪ 2x'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await g.up();
      expect(v.disposed, isTrue);
      expect(v.c.disposed, isTrue);
      // لا مؤقّت ترجيع ولا مؤقّت تقدّم يبقى بعد الإغلاق (يفشل الاختبار تلقائياً إن بقي)
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('prefetch', () {
    testWidgets('the next video moment is warmed: its first 1.5 MB requested once with a Range header (web)', (tester) async {
      momentRangeWarmOverride = true;
      final srv = await _viewer(tester, [_post(1, kind: 'image'), _post(2), _post(3, kind: 'image')]);
      await tester.pump();
      expect(srv.ranges, ['/chat/media/${_name(2)} bytes=0-1572863']);
      // الوصول إلى الفيديو (والتالية صورة فلا تسخين لها) ثم العودة إلى الأولى: لا يتكرر الطلب
      await tester.tapAt(const Offset(360, 200));
      await tester.pump();
      await _frames(tester);
      expect(_videos, hasLength(1));
      final r = _zone(tester);
      await tester.tapAt(Offset(r.left + 30, r.center.dy));
      await tester.pump();
      await _frames(tester);
      expect(find.byKey(const Key('moment-video-zone')), findsNothing);
      expect(srv.ranges, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on native only the poster is precached: no Range request', (tester) async {
      momentRangeWarmOverride = false;
      final srv = await _viewer(tester, [_post(1, kind: 'image'), _post(2)]);
      await tester.pump();
      expect(srv.ranges, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('«اللحظات» cards', () {
    testWidgets('a video card loops the light /chat/vpreview muted, and falls back to the full video when it fails', (tester) async {
      DeviceLocation.override = () async => const LatLng(21.54, 39.17);
      final p = _post(1, caption: 'فيديو البطاقة');
      final item = {
        'kind': 'moment', 'id': p['id'], 'refId': p['id'], 'title': p['caption'], 'subtitle': 'الآن', 'who': 'user1', 'logoUrl': null, 'imageUrl': p['mediaUrl'],
        'lat': p['lat'], 'lng': p['lng'], 'distanceKm': 0.4, 'at': p['createdAt'], 'endsAt': null, 'act': 'شاهد', 'payload': p,
      };
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final srv = _Srv()..feed = [item];
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
      await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
        child: MaterialApp(locale: const Locale('ar'), builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!), home: const TimelinePage()),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('tl-video-loop')), findsOneWidget);
      final first = _videos.single;
      expect(first.url, 'https://test.local/chat/vpreview/${_name(1)}');
      expect(first.widget.muted, isTrue);
      expect(first.widget.loop, isTrue);
      // الخادم بلا ffmpeg يعيد 404 للمعاينة الخفيفة: يعود إلى المقطع الكامل بمشغّل جديد
      first.report((s) => s.copyWith(failed: true));
      await tester.pump();
      await tester.pump();
      expect(_videos, hasLength(2));
      expect(first.disposed, isTrue);
      expect(_videos.last.url, _media(1));
      expect(find.byKey(const Key('tl-video-loop')), findsOneWidget);
      // فشل المقطع الكامل لا يعيد المحاولة بلا نهاية
      _videos.last.report((s) => s.copyWith(failed: true));
      await tester.pump();
      await tester.pump();
      expect(_videos, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
