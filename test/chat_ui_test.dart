// تجربة المحادثة (docs/chat-ui.md): جهتا الفقاعات وصورة المرسل على أول فقاعة في مجموعته، الذيل على آخرها فقط،
// علامة «شوهدت»، زر «إلى الأحدث» بعد الابتعاد عن النهاية، السحب للرد (LTR وRTL)، زر الإملاء، صندوق الصادر المحفوظ
// محلياً بلا تكرار، موجة الرسالة الصوتية من القمم الحقيقية أو الزائفة والسحب عليها في الاتجاهين، مشغّلات الصوت لكل
// صفحة، التسجيل بالإمساك (رفع مبكر، فشل، سحب للإلغاء، قفل)، «يكتب…» عبر المقبس، وحركة الدخول للجديد فقط.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/api/ws.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/core/media/voice_record.dart';
import 'package:naslook/core/speech/dictation.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/chat/widgets/audio_bubble.dart';
import 'package:naslook/pages/chat/widgets/bubble.dart';
import 'package:naslook/pages/chat/widgets/jump_to_latest.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _FakeServer {
  final List<Map<String, dynamic>> messages = [];
  final Map<String, Map<String, dynamic>> meta = {};
  bool failSend = false;
  /// يحفظ الرسالة ثم يرد 500 (يعادل مهلة بعد الحفظ): نسخة على الخادم لم يصل ردّها للعميل.
  bool storeThenFail = false;
  int counter = 0;
  final calls = <String>[];
  /// أجسام POST /messages وPOST /chat/meta كما وصلت.
  final bodies = <Map>[];
  final metaPosts = <Map>[];
  /// عدد طلبات الصفحات الأقدم (مع before).
  int olderLoads = 0;

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.method == 'GET' && path == '/messages/SA0000002') {
      final before = req.url.queryParameters['before'];
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 50;
      if (before != null) olderLoads++;
      final sorted = [...messages]..sort((a, b) => (a['sent_at'] as String).compareTo(b['sent_at'] as String));
      final list = before == null ? sorted : sorted.where((m) => DateTime.parse(m['sent_at'] as String).isBefore(DateTime.parse(before))).toList();
      return _json(list.length > limit ? list.sublist(list.length - limit) : list);
    }
    if (req.method == 'GET' && path.startsWith('/messages/')) return _json(const []);
    if (req.method == 'POST' && path == '/messages') {
      final b = jsonDecode(req.body) as Map;
      bodies.add(b);
      if (failSend) return _json({'error': 'boom'}, 500);
      final m = {'id': 'srv-${++counter}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      messages.add(m);
      if (storeThenFail) return _json({'error': 'timeout-after-insert'}, 500);
      return _json({'message': m});
    }
    if (req.method == 'POST' && path == '/chat/meta') {
      final b = jsonDecode(req.body) as Map;
      metaPosts.add(b);
      meta[b['messageId'].toString()] = {
        if (b['quote'] != null) 'quote': b['quote'],
        if (b['replyTo'] != null) 'replyTo': b['replyTo'],
        if (b['forwardedFrom'] != null) 'forwardedFrom': b['forwardedFrom'],
        if (b['extra'] != null) 'extra': b['extra'],
      };
      return _json({'ok': true});
    }
    if (req.method == 'POST' && path == '/chat/upload') {
      return _json({'url': '/chat/media/k9x1-cccccccccccccccccccccccc.m4a', 'kind': 'audio', 'peaks': List.generate(48, (i) => 0.3 + (i % 5) / 10)});
    }
    if (req.method == 'GET' && path == '/chat/meta') {
      final ids = (req.url.queryParameters['ids'] ?? '').split(',');
      return _json({for (final id in ids) if (meta.containsKey(id)) id: meta[id]});
    }
    if (req.method == 'GET' && path == '/notify/unread') return _json({'unread': 0});
    if (path.startsWith('/presence/')) return _json({'online': true});
    if (req.method == 'POST') return _json({'ok': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Map<String, dynamic> _msg(String id, String from, String text, Duration ago, {String? readAt}) => {
      'id': id, 'sender_id': from, 'type': 'text', 'content': text, 'sent_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
      if (readAt != null) 'read_at': readAt,
    };

Map<String, dynamic> _audio(String id, String from, String file, Duration ago) => {
      'id': id, 'sender_id': from, 'type': 'audio', 'content': '/chat/media/$file.m4a', 'sent_at': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

/// مقبس وهمي: يبث ما نضيفه إلى [ctl] ويسجّل إشعارات «يكتب» الصادرة.
class _FakeSocket extends NaslifeSocket {
  final ctl = StreamController<Map<String, dynamic>>.broadcast();
  final typed = <String>[];
  _FakeSocket() : super(url: 'ws://test.local/ws', token: 't');
  @override
  Stream<Map<String, dynamic>> get events => ctl.stream;
  @override
  bool get connected => true;
  @override
  void typing(String to) => typed.add(to);
  @override
  void close() => ctl.close();
}

/// [rtl] يلفّ الصفحة بـ Directionality RTL كما تعمل في الإنتاج (اللغة العربية).
Future<void> _pumpThread(WidgetTester tester, _FakeServer srv, {bool rtl = false, NaslifeSocket? socket}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  const page = ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(home: rtl ? const Directionality(textDirection: TextDirection.rtl, child: page) : page),
  ));
  await tester.pumpAndSettle();
}

/// الفقاعة التي تحتوي النص.
ChatBubble _bubbleOf(WidgetTester tester, String text) => tester.widget<ChatBubble>(find.ancestor(of: find.text(text), matching: find.byType(ChatBubble)).first);

/// نصف قطر زاوية الذيل (بداية الأسفل للواردة) من صندوق الفقاعة.
Radius _bottomStartOf(WidgetTester tester, String id) {
  final box = tester.widget<AnimatedContainer>(find.byKey(Key('bubble-$id')));
  return (box.decoration as BoxDecoration).borderRadius!.resolve(TextDirection.ltr).bottomLeft;
}

/// زاوية النهاية السفلية: ذيل فقاعة الطرف الآخر بعد قلب الجهتين (هو في جهة النهاية).
Radius _bottomEndOf(WidgetTester tester, String id) {
  final box = tester.widget<AnimatedContainer>(find.byKey(Key('bubble-$id')));
  return (box.decoration as BoxDecoration).borderRadius!.resolve(TextDirection.ltr).bottomRight;
}

/// ضغط مطوّل على زر الميكروفون: يبقى الإصبع نازلاً ويُعاد اللمس للتحريك أو الرفع.
Future<TestGesture> _holdMic(WidgetTester tester) async {
  final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('composer-main'))));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return g;
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

class _FakePlayer extends VoicePlayerBase {
  final seeks = <Duration>[];
  bool disposed = false;
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) => emit(const VoiceState());
  @override
  Future<void> play() async => emit(state.copyWith(playing: true, duration: const Duration(seconds: 10)));
  @override
  Future<void> pause() async => emit(state.copyWith(playing: false));
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    emit(state.copyWith(position: position, duration: const Duration(seconds: 10)));
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// مسجّل وهمي: [startGate] يؤخّر البدء (انتظار إذن الميكروفون) و[failWith] يُفشله بعد البوابة.
class _FakeRecorder implements VoiceRecordSession {
  static int started = 0, stopped = 0, cancelled = 0;
  static Completer<void>? startGate;
  static Object? failWith;
  static void reset() {
    started = 0;
    stopped = 0;
    cancelled = 0;
    startGate = null;
    failWith = null;
  }

  bool _on = false;
  @override
  bool get recording => _on;
  @override
  Duration get elapsed => const Duration(seconds: 2);
  @override
  Future<void> start() async {
    final g = startGate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) throw f;
    started++;
    _on = true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    stopped++;
    _on = false;
    return (bytes: Uint8List.fromList([1, 2, 3, 4]), mime: 'audio/mp4', name: 'voice.m4a', duration: const Duration(seconds: 2));
  }

  @override
  Future<void> cancel() async {
    cancelled++;
    _on = false;
  }

  @override
  void dispose() {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _FakeRecorder.reset();
  });
  tearDown(() {
    Dictation.factoryOverride = null;
    VoicePlayer.factoryOverride = null;
    VoiceRecordSession.factoryOverride = null;
  });

  group('pseudoPeaks', () {
    test('48 bars, deterministic per seed, never flat', () {
      final a = pseudoPeaks('m1'), b = pseudoPeaks('m1'), c = pseudoPeaks('m2');
      expect(a.length, waveformBars);
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toSet().length, greaterThan(10));
      expect(a.every((v) => v >= 0.18 && v <= 1), isTrue);
    });
    test('peaksFromExtra resamples to 48 and ignores junk', () {
      expect(peaksFromExtra({'peaks': List.generate(96, (i) => (i % 10) / 10)})!.length, waveformBars);
      expect(peaksFromExtra({'peaks': [1, 2]}), isNull);
      expect(peaksFromExtra({'peaks': 'x'}), isNull);
      expect(peaksFromExtra({}), isNull);
    });
    test('waveBarX puts the first bar at the start edge: left in LTR, right in RTL', () {
      expect(waveBarX(0, 48, 240, TextDirection.ltr), closeTo(2.5, 0.001));
      expect(waveBarX(47, 48, 240, TextDirection.ltr), closeTo(237.5, 0.001));
      expect(waveBarX(0, 48, 240, TextDirection.rtl), closeTo(237.5, 0.001));
      expect(waveBarX(47, 48, 240, TextDirection.rtl), closeTo(2.5, 0.001));
    });
  });

  testWidgets('peer bubbles sit at the end with an avatar on the first of a group; mine at the start without; tail only on the last', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([
        _msg('p1', 'SA0000002', 'مرحبا', const Duration(minutes: 3)),
        _msg('p2', 'SA0000002', 'كيف الحال؟', const Duration(minutes: 2)),
        _msg('m1', 'SA0000001', 'بخير', const Duration(minutes: 1)),
      ]);
    await _pumpThread(tester, srv);
    expect(_bubbleOf(tester, 'مرحبا').mine, isFalse);
    expect(_bubbleOf(tester, 'بخير').mine, isTrue);
    // الصورة على أول فقاعة واردة في المجموعة فقط، ولا صورة على فقاعتي
    expect(find.byKey(const Key('avatar-p1')), findsOneWidget);
    expect(find.byKey(const Key('avatar-p2')), findsNothing);
    expect(find.byKey(const Key('avatar-m1')), findsNothing);
    // الذيل (زاوية 6) على آخر فقاعة في المجموعة؛ الأولى ملتصقة بما بعدها فزاويتها كاملة
    expect(_bubbleOf(tester, 'مرحبا').joinedBelow, isTrue);
    expect(_bubbleOf(tester, 'كيف الحال؟').joinedBelow, isFalse);
    expect(_bottomEndOf(tester, 'p1'), const Radius.circular(18));
    expect(_bottomEndOf(tester, 'p2'), const Radius.circular(6));
    expect(_bottomStartOf(tester, 'm1'), const Radius.circular(6), reason: 'ذيل فقاعتي في جهة البداية');
    // الجهتان كما كانتا (Align)
    AlignmentGeometry sideOf(String text) => tester.widgetList<Align>(find.ancestor(of: find.text(text), matching: find.byType(Align)))
        .map((a) => a.alignment).firstWhere((a) => a == AlignmentDirectional.centerEnd || a == AlignmentDirectional.centerStart);
    expect(sideOf('بخير'), AlignmentDirectional.centerStart, reason: 'رسالتي يميناً');
    expect(sideOf('مرحبا'), AlignmentDirectional.centerEnd, reason: 'الطرف الآخر يساراً');
    expect(find.text('اليوم'), findsOneWidget);
  });

  testWidgets('RTL: my bubbles sit at the right edge and the peer at the left (owner decision)', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([
        _msg('p1', 'SA0000002', 'مرحبا', const Duration(minutes: 3)),
        _msg('m1', 'SA0000001', 'بخير', const Duration(minutes: 1)),
      ]);
    await _pumpThread(tester, srv, rtl: true);
    final peer = tester.getRect(find.byKey(const Key('bubble-p1')));
    final mine = tester.getRect(find.byKey(const Key('bubble-m1')));
    expect(mine.center.dx, greaterThan(210), reason: 'رسالتي يميناً');
    expect(peer.center.dx, lessThan(210), reason: 'الطرف الآخر يساراً');
    // الصورة عن يسار الفقاعة الواردة (الحافة الخارجية)
    expect(tester.getRect(find.byKey(const Key('avatar-p1'))).right, lessThan(peer.left));
  });

  testWidgets('seen marker sits under my last message the peer has read, and only there', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final srv = _FakeServer()
      ..messages.addAll([
        _msg('m1', 'SA0000001', 'أول رسالة', const Duration(minutes: 9), readAt: now),
        _msg('p1', 'SA0000002', 'وصلت', const Duration(minutes: 8), readAt: now),
        _msg('m2', 'SA0000001', 'ثاني رسالة', const Duration(minutes: 2), readAt: now),
      ]);
    await _pumpThread(tester, srv);
    expect(find.byKey(const Key('seen-marker')), findsOneWidget);
    expect(find.text('شوهدت'), findsOneWidget);
    expect(_bubbleOf(tester, 'ثاني رسالة').seen, isTrue);
    expect(_bubbleOf(tester, 'أول رسالة').seen, isFalse);
    expect(_bubbleOf(tester, 'وصلت').seen, isFalse, reason: 'لا علامة تحت رسائل الطرف الآخر');
    expect(find.byIcon(Icons.done_all_rounded), findsNWidgets(2));
  });

  testWidgets('jump-to-latest fades in after scrolling far from the end and scrolls back on tap', (tester) async {
    final srv = _FakeServer();
    for (var i = 0; i < 40; i++) {
      srv.messages.add(_msg('x$i', i.isEven ? 'SA0000002' : 'SA0000001', 'رسالة رقم $i\nسطر ثانٍ\nسطر ثالث', Duration(minutes: 400 - i * 10)));
    }
    await _pumpThread(tester, srv);
    JumpToLatest jump() => tester.widget<JumpToLatest>(find.byType(JumpToLatest));
    expect(jump().visible, isFalse);
    await tester.drag(find.byType(ScrollablePositionedList), const Offset(0, 1600));
    await tester.pumpAndSettle();
    expect(jump().visible, isTrue);
    expect(find.text('رسالة رقم 39\nسطر ثانٍ\nسطر ثالث'), findsNothing, reason: 'الأحدث خارج الشاشة');
    await tester.tap(find.byKey(const Key('jump-to-latest')));
    await tester.pumpAndSettle();
    expect(jump().visible, isFalse);
    expect(find.text('رسالة رقم 39\nسطر ثانٍ\nسطر ثالث'), findsOneWidget);
  });

  testWidgets('swiping a peer bubble toward the centre sets it as the reply target', (tester) async {
    final srv = _FakeServer()..messages.add(_msg('p1', 'SA0000002', 'متى نتقابل؟', const Duration(minutes: 3)));
    await _pumpThread(tester, srv);
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    // الاختبار يعمل بالاتجاه LTR: الواردة في جهة النهاية (اليمين) والمنتصف إلى اليسار
    await tester.drag(find.text('متى نتقابل؟'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsOneWidget);
    expect(find.text('متى نتقابل؟'), findsNWidgets(2), reason: 'النص في الفقاعة وفي شريط الرد');
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    // سحبة قصيرة لا تفعل شيئاً
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    await tester.drag(find.text('متى نتقابل؟'), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    // الرد يصل مع الاقتباس
    await tester.drag(find.text('متى نتقابل؟'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الساعة 7');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('الساعة 7'), findsOneWidget);
    expect(find.byKey(const Key('reply-strip')), findsNothing);
  });

  testWidgets('RTL: swiping a peer bubble rightwards (toward the centre) sets the reply; leftwards does nothing', (tester) async {
    final srv = _FakeServer()
      ..messages.addAll([
        _msg('p1', 'SA0000002', 'متى نتقابل؟', const Duration(minutes: 3)),
        _msg('m1', 'SA0000001', 'بعد العصر', const Duration(minutes: 1)),
      ]);
    await _pumpThread(tester, srv, rtl: true);
    // الواردة عند اليسار: السحب يساراً يبتعد عن المنتصف
    await tester.drag(find.text('متى نتقابل؟'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    await tester.drag(find.text('متى نتقابل؟'), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsOneWidget);
    expect(find.text('متى نتقابل؟'), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    // فقاعتي عند اليمين: السحب يساراً نحو المنتصف
    await tester.drag(find.text('بعد العصر'), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    await tester.drag(find.text('بعد العصر'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsOneWidget);
    expect(find.text('أنت'), findsOneWidget);
  });

  testWidgets('dictation button is hidden without support and streams partial then final text with a fake', (tester) async {
    final srv = _FakeServer();
    await _pumpThread(tester, srv);
    expect(Dictation.supported, isFalse);
    expect(find.byKey(const Key('dictate')), findsNothing);

    Dictation.factoryOverride = _FakeDictation.new;
    await _pumpThread(tester, srv);
    expect(find.byKey(const Key('dictate')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'أهلاً');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dictate')));
    await tester.pump();
    final d = _FakeDictation.last!;
    expect(d.starts, 1);
    d.onText!('كيف', false);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'أهلاً كيف');
    d.onText!('كيف حالك', true);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'أهلاً كيف حالك ', reason: 'النهائي يحل محل الجزئي');
    d.onEnd!();
    await tester.pump();
    expect(find.byIcon(Icons.send_rounded), findsOneWidget, reason: 'النص المُملى يفعّل زر الإرسال');
  });

  testWidgets('a failed text survives a reload through the local outbox and is retried on open', (tester) async {
    final srv = _FakeServer()..failSend = true;
    await _pumpThread(tester, srv);
    await tester.enterText(find.byType(TextField), 'رسالة معلّقة');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('naslife.outbox.SA0000002'), contains('رسالة معلّقة'));

    // إعادة فتح المحادثة والخادم يعمل: الرسالة تظهر وتُرسل تلقائياً ويُفرَّغ الصندوق
    srv.failSend = false;
    await tester.pumpWidget(const SizedBox());
    await _pumpThread(tester, srv);
    expect(find.text('رسالة معلّقة'), findsOneWidget);
    expect(srv.messages.where((m) => m['content'] == 'رسالة معلّقة').length, 1);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(sp.getString('naslife.outbox.SA0000002'), isNull);
    // المعرّف المحلي يرافق الرسالة إلى الخادم وإلى /chat/meta حتى تُميَّز النسخ
    final body = srv.bodies.lastWhere((b) => b['content'] == 'رسالة معلّقة');
    expect(body['extra']['clientId'], startsWith('local-'));
    expect(srv.metaPosts.last['extra']['clientId'], body['extra']['clientId']);
  });

  testWidgets('outbox: a text whose POST was stored but answered 500 is not sent again on reopen', (tester) async {
    final srv = _FakeServer()..storeThenFail = true;
    await _pumpThread(tester, srv);
    await tester.enterText(find.byType(TextField), 'وصلت فعلاً');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget, reason: 'العميل يراها فاشلة');
    expect(srv.messages.where((m) => m['content'] == 'وصلت فعلاً').length, 1, reason: 'لكن الخادم حفظها');
    await tester.pump(const Duration(seconds: 5));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('naslife.outbox.SA0000002'), contains('وصلت فعلاً'));

    srv.storeThenFail = false;
    await tester.pumpWidget(const SizedBox());
    await _pumpThread(tester, srv);
    expect(find.text('وصلت فعلاً'), findsOneWidget, reason: 'فقاعة واحدة لا اثنتان');
    expect(srv.bodies.where((b) => b['content'] == 'وصلت فعلاً').length, 1, reason: 'لم يُعد الإرسال');
    expect(srv.messages.where((m) => m['content'] == 'وصلت فعلاً').length, 1);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(sp.getString('naslife.outbox.SA0000002'), isNull, reason: 'الصندوق يُفرَّغ من النسخة المكرّرة');
  });

  testWidgets('outbox: a restored entry is dropped when the history carries its clientId, and retried otherwise', (tester) async {
    final old = DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
    SharedPreferences.setMockInitialValues({
      'naslife.outbox.SA0000002': jsonEncode([
        {'localId': 'local-77', 'content': 'نص قديم', 'sentAt': old},
        {'localId': 'local-78', 'content': 'نص آخر', 'sentAt': old},
      ]),
    });
    final srv = _FakeServer()
      // النص نفسه لكن خارج النافذة الزمنية: لا يُطابق إلا بالمعرّف المحلي الذي أعاده /chat/meta
      ..messages.add(_msg('s1', 'SA0000001', 'نص قديم', const Duration(hours: 1)))
      ..meta['s1'] = {'extra': {'clientId': 'local-77'}};
    await _pumpThread(tester, srv);
    expect(find.text('نص قديم'), findsOneWidget);
    expect(srv.bodies.where((b) => b['content'] == 'نص قديم'), isEmpty, reason: 'النسخة موجودة بمعرّفها المحلي');
    expect(srv.bodies.where((b) => b['content'] == 'نص آخر').length, 1, reason: 'ما لا نسخة له يُعاد إرساله');
    expect(find.text('نص آخر'), findsOneWidget);
    expect(srv.bodies.last['extra']['clientId'], 'local-78');
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('naslife.outbox.SA0000002'), isNull);
  });

  testWidgets('audio bubble draws 48 bars from extra.peaks, pseudo bars without, and scrubbing seeks', (tester) async {
    final player = _FakePlayer();
    VoicePlayer.factoryOverride = () => player;
    final peaks = List.generate(48, (i) => i / 47);
    final srv = _FakeServer()
      ..messages.addAll([
        _audio('a1', 'SA0000002', 'k9x1-aaaaaaaaaaaaaaaaaaaaaaaa', const Duration(minutes: 3)),
        _audio('a2', 'SA0000001', 'k9x1-bbbbbbbbbbbbbbbbbbbbbbbb', const Duration(minutes: 1)),
      ])
      ..meta['a1'] = {'extra': {'durationMs': 10000, 'peaks': peaks}}
      ..meta['a2'] = {'extra': {'durationMs': 4000}};
    await _pumpThread(tester, srv);
    final bars = tester.widgetList<WaveformBars>(find.byType(WaveformBars)).toList();
    expect(bars.length, 2);
    final real = bars.firstWhere((b) => b.peaks == peaks || b.peaks.first == 0 && b.peaks.last == 1);
    final pseudo = bars.firstWhere((b) => b != real);
    expect(real.peaks.length, waveformBars);
    expect(pseudo.peaks.length, waveformBars);
    expect(pseudo.peaks.toSet().length, greaterThan(10), reason: 'موجة زائفة غير مسطّحة بلا قمم حقيقية');
    expect(pseudo.peaks, pseudoPeaks('a2'));
    expect(find.text('0:00 / 0:10'), findsOneWidget);
    expect(find.text('0:00 / 0:04'), findsOneWidget);
    // السحب على الموجة ينقل التشغيل
    final target = find.descendant(of: find.ancestor(of: find.text('0:00 / 0:10'), matching: find.byType(AudioBubble)), matching: find.byKey(const Key('audio-bars')));
    final box = tester.getRect(target);
    await tester.dragFrom(Offset(box.left + 2, box.center.dy), Offset(box.width / 2, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.seeks, isNotEmpty);
    expect(player.seeks.last.inMilliseconds, closeTo(5000, 800));
    expect(find.textContaining('−0:0'), findsOneWidget, reason: 'بعد البدء يُعرض الوقت المتبقي');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('RTL: the waveform fills from the start (right) edge, and a tap seeks to the fraction it paints', (tester) async {
    final player = _FakePlayer();
    VoicePlayer.factoryOverride = () => player;
    final srv = _FakeServer()
      ..messages.add(_audio('a1', 'SA0000002', 'k9x1-aaaaaaaaaaaaaaaaaaaaaaaa', const Duration(minutes: 3)))
      ..meta['a1'] = {'extra': {'durationMs': 10000}};
    await _pumpThread(tester, srv, rtl: true);
    final bars = find.byKey(const Key('audio-bars'));
    final box = tester.getRect(bars);
    // زر التشغيل عن يمين الموجة (جهة البداية)
    expect(tester.getRect(find.byKey(const Key('audio-play'))).left, greaterThan(box.right - 1));
    // سحب من الحافة اليمنى نحو المنتصف = النصف
    await tester.dragFrom(Offset(box.right - 2, box.center.dy), Offset(-box.width / 2, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.seeks.last.inMilliseconds, closeTo(5000, 800));
    // نقرة عند 10٪ من اليسار = 90٪ من البداية: الانتقال إلى 9 ثوانٍ والمرسوم 90٪ من اليمين حتى موضع الإصبع
    await tester.tapAt(Offset(box.left + box.width * 0.1, box.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.seeks.last.inMilliseconds, closeTo(9000, 400));
    final wave = tester.widget<WaveformBars>(find.byType(WaveformBars));
    expect(wave.progress, closeTo(0.9, 0.04));
    final playedCount = (wave.progress * waveformBars).ceil();
    final playedXs = [for (var i = 0; i < playedCount; i++) waveBarX(i, waveformBars, box.width, TextDirection.rtl)];
    final restXs = [for (var i = playedCount; i < waveformBars; i++) waveBarX(i, waveformBars, box.width, TextDirection.rtl)];
    expect(playedXs.reduce(math.max), greaterThan(box.width * 0.95), reason: 'المسموع يبدأ من حافة البداية (اليمين)');
    expect(playedXs.reduce(math.min), greaterThan(restXs.reduce(math.max)), reason: 'غير المسموع عن يسار المسموع حيث لمس المستخدم');
    expect(restXs.reduce(math.max), lessThan(box.width * 0.12));
  });

  testWidgets('popping a nested thread keeps the outer thread\'s voice player alive', (tester) async {
    final players = <_FakePlayer>[];
    VoicePlayer.factoryOverride = () {
      final p = _FakePlayer();
      players.add(p);
      return p;
    };
    final srv = _FakeServer()
      ..messages.add(_audio('a1', 'SA0000002', 'k9x1-aaaaaaaaaaaaaaaaaaaaaaaa', const Duration(minutes: 3)))
      ..meta['a1'] = {'extra': {'durationMs': 10000}};
    await _pumpThread(tester, srv);
    await tester.tap(find.byKey(const Key('audio-play')));
    await tester.pump();
    expect(players.length, 1);
    expect(players.single.state.playing, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    // محادثة متداخلة فوقها (كما من بطاقة @شخص أو «مراسلة» في الملف) ثم العودة
    final outer = tester.element(find.byType(ChatThreadPage));
    Navigator.of(outer).push(MaterialPageRoute<void>(builder: (_) => const ChatThreadPage(peer: Person(id: 'SA0000003', nickname: 'nour'))));
    await tester.pumpAndSettle();
    expect(find.text('nour'), findsOneWidget);
    Navigator.of(tester.element(find.text('nour'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('sara'), findsOneWidget);
    expect(players.single.disposed, isFalse, reason: 'المحادثة المتداخلة لا تصرف مشغّلات الخارجية');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget, reason: 'ما زال يعمل');
    await tester.tap(find.byKey(const Key('audio-play')));
    await tester.pump();
    expect(players.length, 1, reason: 'المشغّل نفسه يوقف مؤقتاً، لا مشغّل جديد ولا خطأ');
    expect(players.single.state.playing, isFalse);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    // إغلاق المحادثة الخارجية يصرف مشغّلاتها
    await tester.pumpWidget(const SizedBox());
    expect(players.single.disposed, isTrue);
  });

  group('hold-to-record', () {
    setUp(() => VoiceRecordSession.factoryOverride = _FakeRecorder.new);

    testWidgets('releasing before the recorder starts cancels it once it starts, without touching the build, and a later tap records normally', (tester) async {
      _FakeRecorder.startGate = Completer<void>();
      final srv = _FakeServer();
      await _pumpThread(tester, srv);
      final g = await _holdMic(tester);
      expect(_FakeRecorder.started, 0, reason: 'ما زال ينتظر الإذن');
      await g.up();
      await tester.pump();
      _FakeRecorder.startGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'لا setState أثناء البناء');
      expect(_FakeRecorder.started, 1);
      expect(_FakeRecorder.cancelled, 1, reason: 'الميكروفون لا يبقى مفتوحاً');
      expect(_FakeRecorder.stopped, 0);
      expect(find.byTooltip('إلغاء التسجيل'), findsNothing);
      expect(find.byKey(const Key('composer-field')), findsOneWidget);
      // النقرة التالية تسجّل عادياً ولا تُلغى ببقايا الإمساك
      _FakeRecorder.startGate = null;
      await tester.tap(find.byKey(const Key('composer-main')));
      await tester.pump();
      await tester.pump();
      expect(_FakeRecorder.started, 2);
      expect(_FakeRecorder.cancelled, 1);
      expect(find.byKey(const Key('rec-hint')), findsOneWidget);
      await tester.tap(find.byTooltip('إلغاء التسجيل'));
      await tester.pump();
      expect(_FakeRecorder.cancelled, 2);
    });

    testWidgets('a hold whose start fails after an early release does not cancel the next tap-to-record', (tester) async {
      _FakeRecorder.startGate = Completer<void>();
      _FakeRecorder.failWith = StateError('mic busy');
      final srv = _FakeServer();
      await _pumpThread(tester, srv);
      final g = await _holdMic(tester);
      await g.up();
      await tester.pump();
      _FakeRecorder.startGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_FakeRecorder.started, 0);
      expect(_FakeRecorder.cancelled, 0);
      expect(find.textContaining('تعذر بدء التسجيل'), findsOneWidget);
      _FakeRecorder.failWith = null;
      _FakeRecorder.startGate = null;
      await tester.tap(find.byKey(const Key('composer-main')));
      await tester.pump();
      await tester.pump();
      expect(_FakeRecorder.started, 1);
      expect(_FakeRecorder.cancelled, 0, reason: 'التسجيل الجديد لا يُلغى');
      expect(find.byKey(const Key('rec-hint')), findsOneWidget);
      await tester.tap(find.byTooltip('إلغاء التسجيل'));
      await tester.pump();
    });

    testWidgets('hold → release sends the note with duration, peaks and clientId', (tester) async {
      final srv = _FakeServer();
      await _pumpThread(tester, srv);
      final g = await _holdMic(tester);
      await tester.pump();
      expect(_FakeRecorder.started, 1);
      expect(find.byKey(const Key('slide-cancel')), findsOneWidget, reason: 'أثناء الإمساك يظهر «اسحب للإلغاء»');
      expect(find.byKey(const Key('rec-hint')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1500));
      await g.up();
      await tester.pumpAndSettle();
      expect(_FakeRecorder.stopped, 1);
      expect(_FakeRecorder.cancelled, 0);
      expect(find.byType(AudioBubble), findsOneWidget);
      final body = srv.bodies.last;
      expect(body['content'], endsWith('.m4a'));
      expect(body['extra']['durationMs'], greaterThanOrEqualTo(1000));
      expect((body['extra']['peaks'] as List).length, waveformBars);
      expect(body['extra']['clientId'], startsWith('local-'));
    });

    testWidgets('sliding toward the centre by 80 px cancels (LTR and RTL)', (tester) async {
      for (final rtl in [false, true]) {
        _FakeRecorder.reset();
        final srv = _FakeServer();
        await _pumpThread(tester, srv, rtl: rtl);
        final g = await _holdMic(tester);
        await tester.pump();
        expect(find.byKey(const Key('slide-cancel')), findsOneWidget);
        // المنتصف عن يمين الزر في LTR وعن يساره… لا: الزر عند النهاية، فالمنتصف يميناً في RTL ويساراً في LTR
        final toward = rtl ? 1.0 : -1.0;
        await g.moveBy(Offset(40 * toward, 0));
        await tester.pump();
        expect(_FakeRecorder.cancelled, 0, reason: 'دون العتبة (${rtl ? 'RTL' : 'LTR'})');
        expect(find.byKey(const Key('slide-cancel')), findsOneWidget);
        await g.moveBy(Offset(50 * toward, 0));
        await tester.pump();
        expect(_FakeRecorder.cancelled, 1, reason: '90 نقطة نحو المنتصف تلغي (${rtl ? 'RTL' : 'LTR'})');
        expect(find.byKey(const Key('slide-cancel')), findsNothing);
        await g.up();
        await tester.pump();
        expect(_FakeRecorder.stopped, 0);
        expect(find.byType(AudioBubble), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('sliding up by 60 px locks: release keeps recording until send', (tester) async {
      final srv = _FakeServer();
      await _pumpThread(tester, srv);
      final g = await _holdMic(tester);
      await tester.pump();
      await g.moveBy(const Offset(0, -70));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await g.up();
      await tester.pump();
      expect(_FakeRecorder.stopped, 0);
      expect(_FakeRecorder.cancelled, 0);
      expect(find.textContaining('مقفول'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('composer-main')));
      await tester.pumpAndSettle();
      expect(_FakeRecorder.stopped, 1);
      expect(find.byType(AudioBubble), findsOneWidget);
    });
  });

  testWidgets('a typing event from the peer shows the bouncing dots for three seconds, and my typing goes out', (tester) async {
    final sock = _FakeSocket();
    final srv = _FakeServer()..messages.add(_msg('p1', 'SA0000002', 'هلا', const Duration(minutes: 1)));
    await _pumpThread(tester, srv, socket: sock);
    expect(find.byKey(const Key('typing-indicator')), findsNothing);
    sock.ctl.add({'event': 'typing', 'from': 'SA0000009'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('typing-indicator')), findsNothing, reason: 'شخص آخر لا يُظهرها');
    sock.ctl.add({'event': 'typing', 'from': 'SA0000002'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('typing-indicator')), findsOneWidget);
    expect(find.text('يكتب…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('typing-indicator')), findsNothing);
    expect(find.text('يكتب…'), findsNothing);
    await tester.enterText(find.byType(TextField), 'أ');
    await tester.pump();
    expect(sock.typed, ['SA0000002']);
  });

  testWidgets('only messages that arrive while open animate in; the initial load and older pages do not', (tester) async {
    final sock = _FakeSocket();
    final srv = _FakeServer();
    for (var i = 0; i < 60; i++) {
      srv.messages.add(_msg('x$i', i.isEven ? 'SA0000002' : 'SA0000001', 'رسالة $i', Duration(minutes: 600 - i * 10)));
    }
    await _pumpThread(tester, srv, socket: sock);
    bool anyAnimated() => tester.widgetList<ChatBubble>(find.byType(ChatBubble)).any((b) => b.animateIn);
    // غلاف الدخول المتحرك (تلاشٍ وانزلاق) يوجد فقط حول الفقاعة التي دخلت بحركة
    Finder enterOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(TweenAnimationBuilder<double>));
    expect(find.byType(ChatBubble), findsWidgets);
    expect(anyAnimated(), isFalse, reason: 'التحميل الأول بلا حركة');
    expect(enterOf('رسالة 59'), findsNothing);
    sock.ctl.add({'event': 'message', 'message': {'id': 'live-1', 'sender_id': 'SA0000002', 'type': 'text', 'content': 'وصلت الآن', 'sent_at': DateTime.now().toUtc().toIso8601String()}});
    await tester.pump();
    await tester.pump();
    expect(_bubbleOf(tester, 'وصلت الآن').animateIn, isTrue, reason: 'ما يصل والمحادثة مفتوحة يدخل بحركة');
    expect(enterOf('وصلت الآن'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(srv.olderLoads, 0);
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ScrollablePositionedList), const Offset(0, 1500));
      await tester.pumpAndSettle();
    }
    expect(srv.olderLoads, greaterThanOrEqualTo(1), reason: 'الصفحة الأقدم حُمّلت');
    expect(find.text('رسالة 0'), findsOneWidget);
    expect(anyAnimated(), isFalse, reason: 'الصفحات الأقدم بلا حركة');
    expect(enterOf('رسالة 0'), findsNothing);
  });
}
