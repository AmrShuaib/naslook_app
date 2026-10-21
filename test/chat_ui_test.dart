// تجربة المحادثة (docs/chat-ui.md): جهتا الفقاعات وصورة المرسل على أول فقاعة في مجموعته، الذيل على آخرها فقط،
// علامة «شوهدت»، زر «إلى الأحدث» بعد الابتعاد عن النهاية، السحب للرد، زر الإملاء، صندوق الصادر المحفوظ محلياً،
// وموجة الرسالة الصوتية من القمم الحقيقية أو الزائفة.
import 'dart:convert';
import 'dart:typed_data';

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
import 'package:naslook/core/media/voice_player.dart';
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
  int counter = 0;
  final calls = <String>[];

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.method == 'GET' && path == '/messages/SA0000002') {
      final before = req.url.queryParameters['before'];
      final list = before == null ? messages : messages.where((m) => DateTime.parse(m['sent_at'] as String).isBefore(DateTime.parse(before))).toList();
      return _json(list);
    }
    if (req.method == 'POST' && path == '/messages') {
      if (failSend) return _json({'error': 'boom'}, 500);
      final b = jsonDecode(req.body) as Map;
      final m = {'id': 'srv-${++counter}', 'sender_id': 'SA0000001', 'type': 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      messages.add(m);
      return _json({'message': m});
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

Future<void> _pumpThread(WidgetTester tester, _FakeServer srv) async {
  tester.view.physicalSize = const Size(420, 900);
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
    child: const MaterialApp(home: ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    Dictation.factoryOverride = null;
    VoicePlayer.factoryOverride = null;
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
  });

  testWidgets('peer bubbles sit at the start with an avatar on the first of a group; mine at the end without; tail only on the last', (tester) async {
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
    expect(_bottomStartOf(tester, 'p1'), const Radius.circular(18));
    expect(_bottomStartOf(tester, 'p2'), const Radius.circular(6));
    // الجهتان كما كانتا (Align)
    AlignmentGeometry sideOf(String text) => tester.widgetList<Align>(find.ancestor(of: find.text(text), matching: find.byType(Align)))
        .map((a) => a.alignment).firstWhere((a) => a == AlignmentDirectional.centerEnd || a == AlignmentDirectional.centerStart);
    expect(sideOf('بخير'), AlignmentDirectional.centerEnd);
    expect(sideOf('مرحبا'), AlignmentDirectional.centerStart);
    expect(find.text('اليوم'), findsOneWidget);
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
    // الاختبار يعمل بالاتجاه LTR: الواردة عند اليسار والمنتصف إلى اليمين
    await tester.drag(find.text('متى نتقابل؟'), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsOneWidget);
    expect(find.text('متى نتقابل؟'), findsNWidgets(2), reason: 'النص في الفقاعة وفي شريط الرد');
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    // سحبة قصيرة لا تفعل شيئاً
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    await tester.drag(find.text('متى نتقابل؟'), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-strip')), findsNothing);
    // الرد يصل مع الاقتباس
    await tester.drag(find.text('متى نتقابل؟'), const Offset(90, 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الساعة 7');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('الساعة 7'), findsOneWidget);
    expect(find.byKey(const Key('reply-strip')), findsNothing);
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
  });

  testWidgets('audio bubble draws 48 bars from extra.peaks, pseudo bars without, and scrubbing seeks', (tester) async {
    final player = _FakePlayer();
    VoicePlayer.factoryOverride = () => player;
    final peaks = List.generate(48, (i) => i / 47);
    final srv = _FakeServer()
      ..messages.addAll([
        {'id': 'a1', 'sender_id': 'SA0000002', 'type': 'audio', 'content': '/chat/media/k9x1-aaaaaaaaaaaaaaaaaaaaaaaa.m4a', 'sent_at': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String()},
        {'id': 'a2', 'sender_id': 'SA0000001', 'type': 'audio', 'content': '/chat/media/k9x1-bbbbbbbbbbbbbbbbbbbbbbbb.m4a', 'sent_at': DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String()},
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
}
