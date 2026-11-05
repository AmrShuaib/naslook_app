// الطبقة الصوتية في عارض اللحظات (بلاغ المالك): التعليق الصوتي على صورة أو نص كان لا يعمل إلا بلمسة الشريحة، فتمضي اللحظة
// بعد سبع ثوانٍ قبل أن يُسمع. الآن يبدأ وحده حين تظهر اللحظة، ومدة اللحظة مدة التسجيل (سبع ثوانٍ على الأقل) والشريط يتبعه،
// والضغط المطوّل والتغطية والخلفية توقفه؛ وإن رفض المتصفح الصوت تنتظر اللحظة لمسة «اضغط لتشغيل الصوت»، وإن تعذّر تحميله
// تعود اللحظة إلى سبع ثوانٍ. مشغّل واحد لجلسة العارض كلها (عنصر <audio> واحد مفتوح على سفاري iOS).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/video_pool.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

String _pid(int i) => 'bbbbbbbb-0000-4000-8000-${i.toString().padLeft(12, '0')}';
String _audio(int i) => 'https://test.local/chat/media/voice$i.m4a';

Map<String, dynamic> _post(int i, {String kind = 'text', String caption = '', int? audioSec}) => {
      'id': _pid(i), 'user': {'id': 'SA000000${i + 1}', 'nickname': 'user$i'}, 'kind': kind, 'caption': caption.isEmpty ? 'لحظة $i' : caption,
      'mediaUrl': kind == 'image' ? 'https://test.local/chat/media/p$i.jpg' : null, 'bg': kind == 'text' ? '#37474F' : null,
      'overlays': [], 'tag': 'moment', 'lat': 21.5, 'lng': 39.2, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      if (audioSec != null) 'audioUrl': _audio(i),
      if (audioSec != null) 'audioSec': audioSec,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
    };

/// مشغّل وهمي يسجّل الأوامر ويبلّغ حالته كعنصر <audio>؛ الاختبار يحاكي الموضع والانتهاء والرفض والتعذّر.
class _FakeVoice extends VoicePlayerBase {
  static final created = <_FakeVoice>[];
  final calls = <String>[];
  /// رفض التشغيل: NotAllowedError (سفاري بلا لمسة) أو خطأ تحميل
  Object? refuse;
  /// التشغيل لا يبدأ أبداً (شبكة بطيئة جداً)
  bool hang = false;
  bool disposed = false;
  _FakeVoice() {
    created.add(this);
  }

  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {
    calls.add('src:$url');
    emit(const VoiceState());
  }

  @override
  Future<void> play() async {
    calls.add('play');
    final r = refuse;
    if (r != null) {
      emit(state.copyWith(playing: false, error: r));
      throw r;
    }
    if (hang) return Completer<void>().future;
    emit(state.copyWith(playing: true, ended: false, clearError: true));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(state.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async => emit(state.copyWith(position: position));

  /// موضع جديد (والمدة إن عُرفت) كما يبلّغ timeupdate
  void at(int ms, {int? duration}) => emit(state.copyWith(position: Duration(milliseconds: ms), duration: duration == null ? null : Duration(milliseconds: duration)));

  void end() => emit(state.copyWith(playing: false, ended: true, position: Duration.zero));

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Srv {
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'POST' && req.url.path.endsWith('/view')) return _json({'ok': true, 'views': 2});
    if (req.url.path == '/live/wait') return _json({'seq': 0, 'events': [], 'reset': false});
    if (req.url.path == '/notify/unread') return _json({'unread': 0});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<void> _viewer(WidgetTester tester, List<Map<String, dynamic>> posts, {int initial = 0}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: PostViewerPage(posts: [for (final p in posts) MapPost.fromJson(p)], initial: initial),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// عرض شريط تقدّم اللحظة [i]
double _progress(WidgetTester tester, [int i = 0]) => tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).elementAt(i).widthFactor!;

/// نبضات متتالية بقدر [ms] (مؤقّت العارض كل 50 م.ث)
Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// يمرّر التسجيل من [from] إلى [to] م.ث مع الوقت، كما يبلّغ المتصفح موضعه أثناء التشغيل
Future<void> _play(WidgetTester tester, _FakeVoice v, int from, int to, {int? duration}) async {
  for (var t = from; t <= to; t += 250) {
    v.at(t, duration: duration);
    await _frames(tester, 250);
  }
}

_FakeVoice get _voice => _FakeVoice.created.single;

void main() {
  setUp(() {
    _FakeVoice.created.clear();
    VoicePlayer.factoryOverride = _FakeVoice.new;
  });
  tearDown(() => VoicePlayer.factoryOverride = null);

  testWidgets('a text moment with a voice layer starts its recording at once, no tap needed', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12), _post(2, kind: 'image')]);
    expect(_voice.calls, ['src:${_audio(1)}', 'play']);
    // الشريحة تبقى مرئية وتعرض التشغيل (زر الإيقاف) بلا لمسة
    expect(find.byKey(const Key('voice-chip')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('voice-chip')), matching: find.byIcon(Icons.pause_rounded)), findsOneWidget);
    expect(find.byKey(const Key('moment-voice-unmute')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(_voice.disposed, isTrue, reason: 'إغلاق العارض يحرّر المشغّل (وعنصره على الويب)');
  });

  testWidgets('a 12 s recording stretches the moment: no advance at 7 s, the bar follows the audio, and the end moves on', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12), _post(2, kind: 'image', caption: 'التالية')]);
    final v = _voice;
    await _play(tester, v, 0, 6000, duration: 12000);
    expect(_progress(tester), closeTo(.5, .03), reason: 'الشريط على مدة التسجيل (6 من 12 ث)');
    await _play(tester, v, 6250, 9000, duration: 12000);
    expect(find.text('التالية'), findsNothing, reason: 'لا انتقال عند سبع ثوانٍ والتسجيل لم ينتهِ');
    expect(_progress(tester), closeTo(.75, .03));
    await _play(tester, v, 9250, 12000, duration: 12000);
    expect(find.text('التالية'), findsNothing);
    expect(_progress(tester), lessThan(1), reason: 'لا يمتلئ قبل الانتهاء');
    v.end();
    await tester.pump();
    await _frames(tester, 600);
    expect(find.text('التالية'), findsOneWidget);
    // اللحظة التالية بلا تسجيل: يتوقف المشغّل ولا يُعاد إنشاؤه
    expect(v.calls.last, 'pause');
    expect(_FakeVoice.created, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a recording that never reports progress still holds the moment until it ends', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 20), _post(2, kind: 'image', caption: 'التالية')]);
    await _frames(tester, 9000);
    expect(find.text('التالية'), findsNothing);
    _voice.end();
    await tester.pump();
    await _frames(tester, 600);
    expect(find.text('التالية'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 3 s recording keeps the normal 7 s: after it ends the moment finishes its time', (tester) async {
    await _viewer(tester, [_post(1, kind: 'image', audioSec: 3), _post(2, kind: 'image', caption: 'التالية')]);
    final v = _voice;
    await _play(tester, v, 0, 3000, duration: 3000);
    v.end();
    await tester.pump();
    final at = _progress(tester);
    expect(at, closeTo(3 / 7, .05), reason: 'ثلاث من سبع ثوانٍ');
    await _frames(tester, 3000);
    expect(find.text('التالية'), findsNothing);
    expect(_progress(tester), greaterThan(at));
    await _frames(tester, 1800);
    expect(find.text('التالية'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a long-press pauses the recording and the bar together; release resumes both', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12), _post(2, kind: 'image')]);
    final v = _voice;
    await _play(tester, v, 0, 2000, duration: 12000);
    final g = await tester.startGesture(const Offset(210, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(v.calls.last, 'pause');
    expect(v.state.playing, isFalse);
    final held = _progress(tester);
    await _frames(tester, 3000);
    expect(_progress(tester), held, reason: 'الشريط واقف مع التسجيل');
    await g.up();
    await tester.pump();
    expect(v.calls.last, 'play');
    await _play(tester, v, 2250, 4000, duration: 12000);
    expect(_progress(tester), greaterThan(held));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blocked autoplay (iOS Safari) holds the moment with «اضغط لتشغيل الصوت» until a tap plays it', (tester) async {
    VoicePlayer.factoryOverride = () => _FakeVoice()..refuse = Exception('NotAllowedError: play() can only be initiated by a user gesture');
    await _viewer(tester, [_post(1, audioSec: 5), _post(2, kind: 'image', caption: 'التالية')]);
    final v = _voice;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('🔇 اضغط لتشغيل الصوت'), findsOneWidget);
    await _frames(tester, 10000);
    expect(find.text('التالية'), findsNothing, reason: 'لا تمضي اللحظة صامتة قبل أن يُسمع التسجيل');
    expect(_progress(tester), 0);
    // اللمسة تشغّل داخل حدث اللمس
    v.refuse = null;
    await tester.tap(find.byKey(const Key('moment-voice-unmute')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(v.calls.where((c) => c == 'play'), hasLength(2));
    expect(v.state.playing, isTrue);
    expect(find.text('🔇 اضغط لتشغيل الصوت'), findsNothing);
    await _play(tester, v, 0, 2500, duration: 5000);
    expect(_progress(tester), closeTo(2.5 / 7, .05));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a recording that fails to load falls back to the normal 7 s', (tester) async {
    VoicePlayer.factoryOverride = () => _FakeVoice()..refuse = Exception('MEDIA_ERR_SRC_NOT_SUPPORTED');
    await _viewer(tester, [_post(1, audioSec: 30), _post(2, kind: 'image', caption: 'التالية')]);
    await _frames(tester, 6000);
    expect(find.text('التالية'), findsNothing);
    await _frames(tester, 1500);
    expect(find.text('التالية'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a recording that never starts falls back after the load wait (8 s) plus the normal 7 s', (tester) async {
    VoicePlayer.factoryOverride = () => _FakeVoice()..hang = true;
    await _viewer(tester, [_post(1, audioSec: 30), _post(2, kind: 'image', caption: 'التالية')]);
    final v = _voice;
    await _frames(tester, 7900);
    expect(find.text('التالية'), findsNothing);
    expect(_progress(tester), 0, reason: 'الشريط ينتظر التحميل');
    await _frames(tester, 300);
    expect(v.calls.last, 'pause', reason: 'لا يبدأ صوت متأخر فوق اللحظات التالية');
    await _frames(tester, 7400);
    expect(find.text('التالية'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one player for the whole session: the next voiced moment reuses it with its own source', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 4), _post(2, kind: 'image'), _post(3, kind: 'image', audioSec: 4, caption: 'الثالثة')]);
    final v = _voice;
    // التالية بلمسة يمين الشاشة (عربي: اليمين الفعلي للتالية)
    await tester.tapAt(const Offset(380, 200));
    await tester.pump();
    await _frames(tester, 400);
    expect(v.calls.last, 'pause', reason: 'مغادرة اللحظة توقف تسجيلها');
    await tester.tapAt(const Offset(380, 200));
    await tester.pump();
    await _frames(tester, 400);
    expect(find.text('الثالثة'), findsOneWidget);
    expect(_FakeVoice.created, hasLength(1));
    expect(v.calls.sublist(v.calls.length - 2), ['src:${_audio(3)}', 'play']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a route covering the viewer pauses the recording and returning resumes it', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12)]);
    final v = _voice;
    await _play(tester, v, 0, 1000, duration: 12000);
    unawaited(Navigator.of(tester.element(find.byType(PostViewerPage))).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('فوق العارض')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(v.calls.last, 'pause');
    Navigator.of(tester.element(find.text('فوق العارض'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(v.calls.last, 'play');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app going to the background pauses the recording and coming back plays it', (tester) async {
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await _viewer(tester, [_post(1, audioSec: 12)]);
    final v = _voice;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(milliseconds: 100));
    expect(v.calls.last, 'pause');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(v.calls.last, 'play');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the chip pauses the recording and holds the moment; tapping again resumes', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12), _post(2, kind: 'image', caption: 'التالية')]);
    final v = _voice;
    await _play(tester, v, 0, 1000, duration: 12000);
    await tester.tap(find.byKey(const Key('voice-chip')));
    await tester.pump();
    expect(v.calls.last, 'pause');
    final held = _progress(tester);
    await _frames(tester, 9000);
    expect(_progress(tester), held);
    expect(find.text('التالية'), findsNothing);
    await tester.tap(find.byKey(const Key('voice-chip')));
    await tester.pump();
    expect(v.calls.last, 'play');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a recording the browser stopped on its own shows «اضغط للمتابعة», and a tap resumes it', (tester) async {
    await _viewer(tester, [_post(1, audioSec: 12)]);
    final v = _voice;
    await _play(tester, v, 0, 1000, duration: 12000);
    // مكالمة أو فصل السماعة: المتصفح أوقفه بلا أمر منّا
    v.emit(v.state.copyWith(playing: false));
    await _frames(tester, 1300);
    expect(find.text('▶ اضغط للمتابعة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moment-voice-resume')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(v.calls.last, 'play');
    expect(find.text('▶ اضغط للمتابعة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('a pool primed outside a sure gesture is preferred over a locked element and re-opened by the next real gesture', () {
    var made = 0;
    final blessed = <int>[];
    final pool = MediaSlotPool<int>(create: () => made++, bless: blessed.add, spare: 1);
    // فتح العارض: فتح مبدئي (قد لا يكون داخل لمسة)
    pool.prime();
    expect(blessed, [0]);
    expect(pool.slots.single.primed, isTrue);
    expect(pool.slots.single.blessed, isFalse);
    pool.prime();
    expect(blessed, [0], reason: 'لا يُعاد الفتح المبدئي');
    // اللمسة الحقيقية التالية تفتحه من جديد وتعلّمه مفتوحاً
    pool.userGesture();
    expect(blessed, [0, 0]);
    expect(pool.slots.single.blessed, isTrue);

    // المفتوح مبدئياً يسبق المغلق عند الأخذ
    final p2 = MediaSlotPool<int>(create: () => made++, bless: (_) {}, spare: 1);
    final locked = p2.acquire();
    p2.prime();
    p2.release(locked);
    final primed = p2.slots.firstWhere((s) => s.primed);
    expect(identical(primed, locked), isFalse, reason: 'المشغول لا يُلمس');
    expect(p2.acquire(), same(primed));
  });
}
