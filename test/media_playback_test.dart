// تشغيل الوسائط على iOS: توحيد روابط وسائطنا على أصل التطبيق (سياسة CSP تقبل الأصل ذاته فقط)،
// ومشغّل الصوت عبر VoicePlayer الذي يبدأ التشغيل داخل حدث اللمس (الرسائل الصوتية وبطاقة التسجيل في المنشور).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// مشغّل وهمي يسجّل المصدر وعدد مرات التشغيل، ويمكنه محاكاة رفض التشغيل (NotAllowedError على iOS).
class _FakePlayer extends VoicePlayerBase {
  static final created = <_FakePlayer>[];
  static bool fail = false;
  String? url;
  Uint8List? bytes;
  int plays = 0, pauses = 0;
  _FakePlayer() {
    created.add(this);
  }
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {
    this.url = url;
    this.bytes = bytes;
    emit(const VoiceState());
  }

  @override
  Future<void> play() async {
    plays++;
    if (fail) throw Exception('NotAllowedError: play() outside a user gesture');
    emit(state.copyWith(playing: true, duration: const Duration(seconds: 4)));
  }

  @override
  Future<void> pause() async {
    pauses++;
    emit(state.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async => emit(state.copyWith(position: position));
}

const _audio = 'https://www.naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a';

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

Future<http.Response> _handle(http.Request req) async {
  final path = req.url.path;
  if (req.method == 'GET' && path == '/messages/SA0000002') {
    return _json([
      {'id': 'm1', 'sender_id': 'SA0000002', 'type': 'text', 'content': _audio, 'sent_at': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String()},
    ]);
  }
  if (req.method == 'GET' && path == '/chat/meta') return _json({'m1': {'extra': {'durationMs': 4000}}});
  if (req.method == 'GET' && path == '/notify/unread') return _json({'unread': 0});
  if (req.method == 'POST' && path.startsWith('/mapposts/')) return _json({'ok': true, 'views': 1});
  if (path.startsWith('/presence/')) return _json({'online': true});
  if (req.method == 'POST') return _json({'ok': true});
  return _json({'error': 'not-found'}, 404);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    _FakePlayer.created.clear();
    _FakePlayer.fail = false;
    VoicePlayer.factoryOverride = _FakePlayer.new;
  });
  tearDown(() => VoicePlayer.factoryOverride = null);

  group('mediaUrl', () {
    const base = 'https://naslife.app';
    test('rebuilds our media paths on the app origin whatever host they were saved with', () {
      expect(mediaUrl('https://www.naslife.app/chat/media/a.mp4', base: base), 'https://naslife.app/chat/media/a.mp4');
      expect(mediaUrl('http://admin.naslife.app/files/x.jpg?v=2', base: base), 'https://naslife.app/files/x.jpg?v=2');
      expect(mediaUrl('https://naslife.app/uploads/y.png', base: 'https://www.naslife.app'), 'https://www.naslife.app/uploads/y.png');
    });
    test('resolves relative paths and leaves foreign links alone', () {
      expect(mediaUrl('/chat/media/a.m4a', base: base), 'https://naslife.app/chat/media/a.m4a');
      expect(mediaUrl('chat/media/a.m4a', base: base), 'https://naslife.app/chat/media/a.m4a');
      expect(mediaUrl('https://example.com/chat/other.jpg', base: base), 'https://example.com/chat/other.jpg');
      expect(mediaUrl('https://cdn.example.com/img.png', base: base), 'https://cdn.example.com/img.png');
      expect(mediaUrl('  ', base: base), '');
    });
    test('thumbUrl points chat uploads at /chat/thumb and leaves other links alone', () {
      expect(thumbUrl('https://www.naslife.app/chat/media/k9x1zz-ab12cd34ef56ab12cd34ef56.jpg', base: base), 'https://naslife.app/chat/thumb/k9x1zz-ab12cd34ef56ab12cd34ef56.jpg');
      expect(thumbUrl('/chat/media/k9x1zz-ab12cd34ef56ab12cd34ef56.mp4', base: base), 'https://naslife.app/chat/thumb/k9x1zz-ab12cd34ef56ab12cd34ef56.mp4');
      expect(thumbUrl('https://naslife.app/files/old.jpg', base: base), 'https://naslife.app/files/old.jpg');
      expect(thumbUrl('https://cdn.example.com/img.png', base: base), 'https://cdn.example.com/img.png');
    });
    test('defaults to the last constructed client base', () {
      ApiClient(baseUrl: 'https://test.local/', httpClient: MockClient(_handle));
      expect(ApiClient.mediaBase, 'https://test.local');
      expect(mediaUrl('https://www.naslife.app/chat/media/a.mp4'), 'https://test.local/chat/media/a.mp4');
    });
  });

  testWidgets('chat voice bubble plays through VoicePlayer with a same-origin URL, pauses, and shows its duration', (tester) async {
    await _pump(tester, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('0:00 / 0:04'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(_FakePlayer.created, hasLength(1));
    final p = _FakePlayer.created.single;
    expect(p.url, 'https://test.local/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a');
    expect(p.plays, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(p.pauses, 1);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chat voice bubble: a rejected play() shows the error state and a hint instead of hanging', (tester) async {
    _FakePlayer.fail = true;
    await _pump(tester, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.textContaining('تعذر تشغيل التسجيل'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('post viewer audio card plays the recording through VoicePlayer on the app origin', (tester) async {
    final post = MapPost.fromJson({
      'id': 'aaaaaaaa-0000-4000-8000-000000000009', 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'audio', 'mediaUrl': _audio, 'caption': 'سمعوا هذا',
      'overlays': [], 'tag': 'moment', 'lat': 21.5, 'lng': 39.2, 'durationSec': 4, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _pump(tester, PostViewerPage(posts: [post]));
    expect(find.text('تسجيل صوتي · 0:04'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    final p = _FakePlayer.created.single;
    expect(p.url, 'https://test.local/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.m4a');
    expect(p.bytes, isNull);
    expect(p.plays, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
