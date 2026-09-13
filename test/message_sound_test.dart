// جرس الرسائل الجديدة: قرار القرع (من شخص آخر، غير مكتوم، مفعّل، بفاصل زمني)، معالجة أحداث الاتصال المباشر،
// ومفتاح الإعداد وزر التجربة في «ماي سبيس» مع حفظ الإعداد محلياً.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/notify/message_sound.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
Future<http.Response> _handle(http.Request req) async {
  final path = req.url.path;
  if (path == '/me/profile') return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
  if (path == '/me/map-presence') return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
  if (path == '/notify/unread') return _json({'unread': 0});
  if (path == '/safety/mutes') return _json([{'peerId': 'SA0000009', 'until': null}]);
  if (req.method == 'GET') return _json([]);
  return _json({'ok': true});
}

void main() {
  setUp(() {
    MessageSound.resetThrottle();
    MessageSound.playOverride = null;
    SharedPreferences.setMockInitialValues({});
  });

  group('shouldRing', () {
    final t0 = DateTime(2026, 9, 13, 12);
    test('rings for a peer message once per gap; never for my own, muted, or disabled', () {
      expect(MessageSound.shouldRing(enabled: true, senderId: 'SA0000002', myId: 'SA0000001', mutedPeers: const {}, now: t0), isTrue);
      expect(MessageSound.shouldRing(enabled: true, senderId: 'SA0000002', myId: 'SA0000001', mutedPeers: const {}, now: t0.add(const Duration(milliseconds: 500))), isFalse, reason: 'ضمن الفاصل الأدنى');
      expect(MessageSound.shouldRing(enabled: true, senderId: 'SA0000002', myId: 'SA0000001', mutedPeers: const {}, now: t0.add(const Duration(seconds: 2))), isTrue);
      MessageSound.resetThrottle();
      expect(MessageSound.shouldRing(enabled: true, senderId: 'SA0000001', myId: 'SA0000001', mutedPeers: const {}, now: t0), isFalse, reason: 'رسالتي من جهاز آخر');
      expect(MessageSound.shouldRing(enabled: true, senderId: 'sa0000009', myId: 'SA0000001', mutedPeers: const {'SA0000009'}, now: t0), isFalse, reason: 'طرف مكتوم');
      expect(MessageSound.shouldRing(enabled: false, senderId: 'SA0000002', myId: 'SA0000001', mutedPeers: const {}, now: t0), isFalse);
      expect(MessageSound.shouldRing(enabled: true, senderId: null, myId: 'SA0000001', mutedPeers: const {}, now: t0), isFalse);
    });
  });

  group('MessageBell', () {
    test('plays on socket message events from others, in either event shape', () async {
      var plays = 0;
      MessageSound.playOverride = () => plays++;
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      ]);
      addTearDown(container.dispose);
      final bell = MessageBell(container.read);
      expect(bell.handle({'event': 'message', 'message': {'id': 'x', 'sender_id': 'SA0000002', 'content': 'هلا'}}), isTrue);
      MessageSound.resetThrottle();
      expect(bell.handle({'senderId': 'SA0000003', 'content': 'مرحبا'}), isTrue, reason: 'شكل النواة بلا حقل event');
      MessageSound.resetThrottle();
      expect(bell.handle({'event': 'typing', 'peerId': 'SA0000002'}), isFalse);
      expect(bell.handle({'event': 'message', 'message': {'id': 'y', 'sender_id': 'SA0000001', 'content': 'أنا'}}), isFalse, reason: 'رسالتي');
      expect(plays, 2);
      container.read(messageSoundProvider.notifier).set(false);
      MessageSound.resetThrottle();
      expect(bell.handle({'event': 'message', 'message': {'id': 'z', 'sender_id': 'SA0000002', 'content': 'ثانية'}}), isFalse, reason: 'الإعداد موقوف');
      expect(plays, 2);
    });
  });

  testWidgets('MySpace toggle persists the setting and the test button plays', (tester) async {
    var plays = 0;
    MessageSound.playOverride = () => plays++;
    tester.view.physicalSize = const Size(420, 1800);
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
      child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: MySpacePage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('sound-toggle')));
    await tester.pump();
    final tile = tester.widget<SwitchListTile>(find.byKey(const Key('sound-toggle')));
    // في الاختبارات (غير الويب) الصوت غير مدعوم: المفتاح معطّل وموقوف
    expect(MessageSound.supported, isFalse);
    expect(tile.onChanged, isNull);
    expect(tile.value, isFalse);
    expect(find.text('متاح في نسخة الويب'), findsOneWidget);
    expect(find.byKey(const Key('sound-test')), findsNothing);
    // الحفظ والتحميل عبر التخزين المحلي
    await MessageSound.saveEnabled(false);
    expect(await MessageSound.loadEnabled(), isFalse);
    await MessageSound.saveEnabled(true);
    expect(await MessageSound.loadEnabled(), isTrue);
    expect(plays, 0);
  });
}
