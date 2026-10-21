// قائمة المحادثات المصقولة (lib/pages/chat/chats_page.dart): الصفوف (صورة 48 مع نقطة الحضور، معاينة بأيقونة الوسائط أو الرمز،
// «أنت:» مع علامة الإرسال لرسالتي، شارة غير المقروء بلون العلامة)، الهيكل أثناء الجلب الأول، السحب للتحديث يعيد الجلب،
// والضغط المطوّل يفتح قائمة الصف (كتم/إلغاء الكتم عبر /safety/mutes، تعليم كمقروءة عبر /messages/:peer/read).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/profile_avatar.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  final mutes = <Map<String, dynamic>>[];
  /// إن وُجدت، يُؤخَّر الرد على /chats حتى تكتمل (لاختبار الهيكل).
  Completer<void>? gate;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    final now = DateTime.now().toUtc().toIso8601String();
    switch (key) {
      case 'GET /chats':
        if (gate != null) await gate!.future;
        return _json([
          {'id': 'SA0000002', 'nickname': 'sara', 'online': true, 'lastType': 'text', 'lastContent': 'نتقابل الساعة 7؟', 'lastAt': now, 'lastMine': false, 'unread': 2},
          {'id': 'SA0000003', 'nickname': 'khalid', 'online': false, 'lastType': 'text', 'lastContent': '/chat/media/k9x1zz-abcdef0123456789abcdef02.m4a', 'lastAt': now, 'lastMine': true, 'unread': 0},
          {'id': 'SA0000004', 'nickname': 'nora', 'lastType': 'image', 'lastContent': '/chat/media/k9x1zz-abcdef0123456789abcdef03.jpg', 'lastAt': now, 'lastMine': false, 'unread': 120},
          {'id': 'SA0000005', 'nickname': 'fahad', 'lastType': 'text', 'lastContent': '/pay 45 قهوة', 'lastAt': now, 'lastMine': false, 'unread': 0},
        ]);
      case 'GET /safety/mutes':
        return _json(mutes);
      case 'POST /safety/mutes':
        final b = jsonDecode(req.body) as Map;
        final m = {'peerId': b['peerId'], 'until': null};
        mutes.add(m);
        return _json(m);
      case 'GET /requests':
      case 'GET /contacts':
        return _json([]);
      case 'GET /jobs/inbox':
        return _json({'items': [], 'pending': 0});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'POST /messages/SA0000002/read':
        return _json({'ok': true});
    }
    if (req.method == 'DELETE' && req.url.path.startsWith('/safety/mutes/')) {
      mutes.removeWhere((m) => m['peerId'] == req.url.path.split('/').last);
      return _json({'ok': true});
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, {_Srv? srv}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(locale: Locale('ar'), home: Scaffold(body: ChatsPage())),
  ));
  await tester.pump();
  return s;
}

void main() {
  test('chatPreview: media icons, command labels, whitespace collapsed, refs kept as text', () {
    expect(chatPreview('text', null).text, 'ابدأ المحادثة');
    expect(chatPreview('audio', '/chat/media/x.m4a'), (icon: Icons.mic_rounded, text: 'رسالة صوتية'));
    expect(chatPreview('text', 'https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.mp4').icon, Icons.videocam_rounded);
    expect(chatPreview('image', '/chat/media/a.jpg'), (icon: Icons.photo_camera_rounded, text: 'صورة'));
    expect(chatPreview('text', '/meet 7م @brew92').text, 'موعد');
    expect(chatPreview('text', '/split 120 3 عشاء'), (icon: Icons.call_split_rounded, text: 'تقسيم حساب'));
    expect(chatPreview('text', 'سطر\n\nثانٍ   هنا').text, 'سطر ثانٍ هنا');
    expect(chatPreview('text', '#brew92/v60 جرّبه'), (icon: null, text: '#brew92/v60 جرّبه'));
  });

  testWidgets('rows: 48 px avatar with presence dot, media icons, my tick, command label, unread pill (99+)', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-row-SA0000002')), findsOneWidget);
    final sara = tester.widget<ProfileAvatar>(find.byKey(const Key('chat-avatar-SA0000002')));
    expect(sara.size, 48);
    expect(sara.online, isTrue, reason: 'الحضور من حمولة /chats');
    expect(tester.widget<ProfileAvatar>(find.byKey(const Key('chat-avatar-SA0000003'))).online, isFalse);
    expect(find.text('sara'), findsOneWidget);
    expect(find.text('نتقابل الساعة 7؟'), findsOneWidget);
    expect(find.byKey(const Key('chat-unread-SA0000002')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget, reason: 'أكثر من 99 تُختصر');
    expect(find.byKey(const Key('chat-unread-SA0000003')), findsNothing, reason: 'لا شارة بلا غير مقروء');
    // رسالتي الصوتية: علامة الإرسال + أيقونة الميكروفون + «أنت: رسالة صوتية»
    expect(find.byKey(const Key('chat-tick-SA0000003')), findsOneWidget);
    expect(find.byKey(const Key('chat-tick-SA0000002')), findsNothing, reason: 'لا علامة على رسالة الطرف الآخر');
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('أنت: رسالة صوتية'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    expect(find.text('صورة'), findsOneWidget);
    expect(find.byIcon(Icons.payments_rounded), findsOneWidget);
    expect(find.text('طلب مبلغ'), findsOneWidget);
    expect(find.byKey(const Key('chats-skeleton')), findsNothing);
  });

  testWidgets('skeleton rows while the first fetch is pending, then the real rows', (tester) async {
    final srv = _Srv()..gate = Completer<void>();
    await _pump(tester, srv: srv);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('chats-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    srv.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chats-skeleton')), findsNothing);
    expect(find.text('sara'), findsOneWidget);
  });

  testWidgets('pull-to-refresh refetches the list', (tester) async {
    final srv = await _pump(tester);
    await tester.pumpAndSettle();
    expect(srv.calls.where((c) => c == 'GET /chats').length, 1);
    await tester.fling(find.byKey(const Key('chat-row-SA0000002')), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(srv.calls.where((c) => c == 'GET /chats').length, 2);
    expect(find.text('sara'), findsOneWidget, reason: 'القائمة تبقى ظاهرة أثناء التحديث (لا هيكل)');
  });

  testWidgets('long-press menu: mute posts and swaps the badge for the mute icon; unmute deletes', (tester) async {
    final srv = await _pump(tester);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('chat-row-SA0000002')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-menu-mute')), findsOneWidget);
    expect(find.byKey(const Key('chat-menu-read')), findsOneWidget, reason: 'فيها غير مقروء');
    expect(find.byKey(const Key('chat-menu-profile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-menu-mute')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /safety/mutes'));
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.byKey(const Key('chat-unread-SA0000002')), findsNothing, reason: 'المكتومة بلا شارة');
    expect(find.textContaining('كُتمت'), findsOneWidget);
    await tester.longPress(find.byKey(const Key('chat-row-SA0000002')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-menu-mute')), findsNothing);
    await tester.tap(find.byKey(const Key('chat-menu-unmute')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('DELETE /safety/mutes/SA0000002'));
    expect(find.byIcon(Icons.volume_off_rounded), findsNothing);
    expect(find.byKey(const Key('chat-unread-SA0000002')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-press menu: mark as read posts /messages/:peer/read; a read chat has no such item', (tester) async {
    final srv = await _pump(tester);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('chat-row-SA0000002')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-read')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /messages/SA0000002/read'));
    expect(srv.calls.where((c) => c == 'GET /chats').length, 2, reason: 'القائمة تُعاد بعد التعليم');
    await tester.longPress(find.byKey(const Key('chat-row-SA0000003')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-menu-read')), findsNothing);
    expect(find.byKey(const Key('chat-menu-mute')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
