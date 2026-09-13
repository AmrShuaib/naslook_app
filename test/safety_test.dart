// الأمان والإشراف: التطبيع والكلمات المحظورة، كتم المحادثة من قائمتها، التحقق المسبق قبل الإرسال، شارة الكتم في القائمة،
// استبعاد المكتومين من عدّاد الجرس، والإبلاغ عن منشور شخص آخر من عارض المنشورات.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/safety_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/state/safety_providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _postId = 'aaaaaaaa-0000-4000-8000-000000000077';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final mutes = <Map<String, dynamic>>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /messages/SA0000002':
        return _json([]);
      case 'POST /messages':
        return _json({'message': {'id': 'srv-1', 'sender_id': 'SA0000001', 'type': 'text', 'content': bodies[key]!['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()}});
      case 'POST /messages/SA0000002/read':
        return _json({'ok': true});
      case 'GET /chat/meta':
        return _json({});
      case 'GET /safety/mutes':
        return _json(mutes);
      case 'POST /safety/mutes':
        final m = {'peerId': bodies[key]!['peerId'], 'until': null};
        mutes.add(m);
        return _json(m);
      case 'GET /safety/words':
        return _json({'words': ['احتيال'], 'threshold': 3});
      case 'POST /safety/report':
        return _json({'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3});
      case 'GET /chats':
        return _json([
          {'id': 'SA0000002', 'nickname': 'sara', 'lastType': 'text', 'lastContent': 'هلا', 'unread': 2, 'lastAt': DateTime.now().toUtc().toIso8601String()},
          {'id': 'SA0000003', 'nickname': 'khalid', 'lastType': 'text', 'lastContent': 'مرحبا', 'unread': 1, 'lastAt': DateTime.now().toUtc().toIso8601String()},
        ]);
      case 'GET /requests':
      case 'GET /contacts':
        return _json([]);
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'POST /mapposts/$_postId/view':
        return _json({'ok': true, 'views': 3});
    }
    if (req.method == 'DELETE' && req.url.path.startsWith('/safety/mutes/')) {
      mutes.removeWhere((m) => m['peerId'] == req.url.path.split('/').last);
      return _json({'ok': true});
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv}) async {
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
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return s;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  test('bannedWordIn normalizes hamza, taa marbuta and tashkeel like the server', () {
    expect(bannedWordIn('هذا العرض إحتيالٌ واضح', ['احتيال']), 'احتيال');
    expect(bannedWordIn('عرض نظيف', ['احتيال', 'نصب']), isNull);
    expect(bannedWordIn('Big SCAM', ['scam']), 'scam');
    expect(bannedWordIn('أي نص', const []), isNull);
    expect(normalizeArabic('مَدْرَسَةٌ'), 'مدرسه');
  });

  test('unread badge count skips muted chats', () async {
    final container = ProviderContainer(overrides: [
      chatsProvider.overrideWith((ref) async => const [
            Chat(peer: Person(id: 'SA0000002', nickname: 'sara'), unread: 2),
            Chat(peer: Person(id: 'SA0000003', nickname: 'khalid'), unread: 1),
          ]),
      requestsProvider.overrideWith((ref) async => const []),
      mutesProvider.overrideWith((ref) async => const [ChatMute(peerId: 'SA0000002')]),
    ]);
    addTearDown(container.dispose);
    await container.read(chatsProvider.future);
    await container.read(requestsProvider.future);
    await container.read(mutesProvider.future);
    expect(container.read(unreadCountProvider), 1);
  });

  testWidgets('chat menu mutes the peer forever and then offers to unmute', (tester) async {
    final srv = await _pump(tester, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    await _settle(tester);
    await tester.tap(find.byTooltip('المزيد'));
    await _settle(tester);
    await tester.tap(find.text('كتم الإشعارات'));
    await _settle(tester);
    await tester.tap(find.text('دائماً'));
    await _settle(tester);
    expect(srv.bodies['POST /safety/mutes']?['peerId'], 'SA0000002');
    expect(srv.bodies['POST /safety/mutes']?.containsKey('hours'), isFalse);
    expect(find.textContaining('كُتمت إشعارات'), findsOneWidget);
    await tester.tap(find.byTooltip('المزيد'));
    await _settle(tester);
    expect(find.text('إلغاء كتم الإشعارات'), findsOneWidget);
    await tester.tap(find.text('إلغاء كتم الإشعارات'));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /safety/mutes/SA0000002'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a message containing a banned word is stopped before sending', (tester) async {
    final srv = await _pump(tester, const ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara')));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'اكتب رسالة…'), 'هذا العرض إحتيال');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester);
    expect(srv.calls.where((c) => c == 'POST /messages'), isEmpty);
    expect(find.textContaining('كلمة غير مسموحة'), findsOneWidget);
    expect(find.text('هذا العرض إحتيال'), findsOneWidget, reason: 'النص يبقى في الحقل ليعدّله');
    await tester.enterText(find.widgetWithText(TextField, 'اكتب رسالة…'), 'عرض نظيف');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester);
    expect(srv.bodies['POST /messages']?['content'], 'عرض نظيف');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chats list shows the mute icon and no unread badge for a muted chat', (tester) async {
    final srv = _Srv()..mutes.add({'peerId': 'SA0000002', 'until': null});
    await _pump(tester, const ChatsPage(), srv: srv);
    await _settle(tester);
    expect(find.text('sara'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.text('2'), findsNothing, reason: 'شارة المكتومة لا تظهر');
    expect(find.text('1'), findsWidgets, reason: 'شارة خالد تظهر');
  });

  testWidgets("viewer menu on someone else's post reports it", (tester) async {
    final post = MapPost.fromJson({
      'id': _postId, 'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'text', 'caption': 'عرض مشبوه', 'bg': '#BF3A1E', 'overlays': [], 'tag': 'offer',
      'lat': 21.5, 'lng': 39.2, 'status': 'active', 'views': 2, 'likes': 0, 'liked': false, 'mine': false, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    final srv = await _pump(tester, PostViewerPage(posts: [post]));
    await tester.tap(find.byTooltip('خيارات'));
    await _settle(tester);
    expect(find.text('حظر sara'), findsOneWidget);
    await tester.tap(find.text('إبلاغ عن المنشور'));
    await _settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'مضلل');
    await tester.tap(find.text('إرسال البلاغ'));
    await _settle(tester);
    expect(srv.bodies['POST /safety/report'], {'targetType': 'post', 'targetId': _postId, 'reason': 'مضلل'});
    expect(find.textContaining('وصل بلاغك'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
