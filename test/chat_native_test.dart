// المحادثة على التطبيق الأصلي: التسجيل الصوتي عبر VoiceRecordSession المشتركة (m4a على iOS)، وفقاعة الفيديو تفتح مشغّلاً
// داخل التطبيق بملء الشاشة بدل تبويب خارجي، ومشغّل الفيديو قابل للاستبدال في الاختبارات فلا يلمس قناة المنصة.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/core/media/native_io.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/permissions.dart';
import 'package:naslook/core/media/video_view.dart';
import 'package:naslook/core/media/voice_record.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _FakeRecorder implements VoiceRecordSession {
  static int started = 0, stopped = 0, cancelled = 0;
  static Object? failWith;
  bool _on = false;
  @override
  bool get recording => _on;
  @override
  Duration get elapsed => const Duration(seconds: 2);
  @override
  Future<void> start() async {
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

class _Srv {
  final messages = <Map<String, dynamic>>[];
  final uploads = <String>[];
  final sent = <Map>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/messages/SA0000002') return _json(messages);
    if (req.method == 'POST' && path == '/chat/upload') {
      final ct = req.headers['content-type'] ?? '';
      uploads.add(ct);
      return _json({'url': '/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a', 'type': ct, 'kind': 'audio', 'size': req.bodyBytes.length});
    }
    if (req.method == 'POST' && path == '/messages') {
      final b = jsonDecode(req.body) as Map;
      sent.add(b);
      final m = {'id': 'srv-${sent.length}', 'sender_id': 'SA0000001', 'type': b['type'] ?? 'text', 'content': b['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()};
      return _json({'message': m});
    }
    if (req.method == 'GET' && path == '/chat/meta') return _json({});
    if (path.startsWith('/presence/')) return _json({'online': false});
    return _json({'ok': true});
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
    ],
    child: const MaterialApp(home: ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _FakeRecorder.started = 0;
    _FakeRecorder.stopped = 0;
    _FakeRecorder.cancelled = 0;
    _FakeRecorder.failWith = null;
    VoiceRecordSession.factoryOverride = _FakeRecorder.new;
  });
  tearDown(() {
    VoiceRecordSession.factoryOverride = null;
    VideoView.factoryOverride = null;
    openAppSettingsOverride = null;
  });

  testWidgets('chat voice notes go through the shared recorder and upload as m4a', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(_FakeRecorder.started, 1);
    expect(find.text('جارٍ التسجيل… اضغط إرسال عند الانتهاء'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(_FakeRecorder.stopped, 1);
    expect(srv.uploads.single, startsWith('audio/mp4'));
    expect(srv.sent, isNotEmpty);
  });

  testWidgets('cancelling a chat recording discards it', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('إلغاء التسجيل'));
    await tester.pumpAndSettle();
    expect(_FakeRecorder.cancelled, 1);
    expect(srv.uploads, isEmpty);
  });

  testWidgets('a denied microphone offers the settings instead of a dead end', (tester) async {
    var opened = 0;
    openAppSettingsOverride = () async => opened++;
    _FakeRecorder.failWith = const MediaPermissionDenied('mic');
    await _pump(tester, _Srv());
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('perm-help')), findsOneWidget);
    expect(find.textContaining('الميكروفون'), findsWidgets);
    await tester.tap(find.byKey(const Key('perm-open-settings')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('a video bubble opens an in-app full-screen player on iOS/Android', (tester) async {
    // على الجوال يُشغَّل داخل التطبيق؛ على الويب يبقى فتحه في تبويب جديد كما كان
    nativeMobileOverride = true;
    addTearDown(() => nativeMobileOverride = null);
    final played = <String>[];
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false}) {
      played.add('$url autoplay=$autoplay');
      return const ColoredBox(key: Key('fake-video'), color: Colors.black);
    };
    final srv = _Srv()
      ..messages.add({'id': 'v1', 'sender_id': 'SA0000002', 'type': 'video', 'content': '/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.mp4', 'sent_at': DateTime.now().toUtc().toIso8601String()});
    await _pump(tester, srv);
    await tester.tap(find.byKey(const Key('chat-video')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-full')), findsOneWidget);
    expect(find.byKey(const Key('fake-video')), findsOneWidget);
    expect(played.single, 'https://test.local/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.mp4 autoplay=true');
    await tester.tap(find.byKey(const Key('video-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-full')), findsNothing);
  });

  testWidgets('without an override VideoView on the test host renders the external fallback, not a platform player', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VideoView(url: 'https://test.local/chat/media/x.mp4'))));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
