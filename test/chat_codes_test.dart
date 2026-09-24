// رموز الاختصار في المحادثة: المحلّل (إشارات وأوامر)، بطاقات الأصناف والدوائر والمواعيد والمبالغ، الدفع والقبول بزر واحد،
// الإكمال التلقائي بعد / و@، قائمة «+»، توسيع /me و/send قبل الإرسال، وتسجيل الطلب بعد وصول معرّف الرسالة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/chat/codes.dart';
import 'package:naslook/pages/chat/chat_cards.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

final _calls = <String>[];
final _bodies = <String, Map<String, dynamic>>{};
final _requests = <String, Map<String, dynamic>>{};
http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
String _at(int minutesAgo) => DateTime.now().subtract(Duration(minutes: minutesAgo)).toUtc().toIso8601String();

Map<String, dynamic>? _card(String ref) => switch (ref) {
      '#brew92/v60' => {'type': 'item', 'id': 'brew92-v60', 'bizId': 'biz-brew92', 'title': 'V60 تقطير', 'subtitle': 'برو 92', 'image': 'asset:biz/brew92.png', 'price': 2200, 'unit': 'item', 'kind': 'product', 'category': 'cafe', 'discussions': 3, 'link': '/c/biz-brew92'},
      '@brew92' => {'type': 'biz', 'id': 'biz-brew92', 'title': 'برو 92', 'subtitle': 'حي الروضة، جدة', 'image': 'asset:biz/brew92.png', 'category': 'cafe', 'openNow': true, 'link': '/c/biz-brew92'},
      '@sara' => {'type': 'user', 'id': 'SA0000002', 'title': 'sara', 'subtitle': '', 'image': null, 'link': '/u/sara'},
      '@amr' => {'type': 'user', 'id': 'SA0000001', 'title': 'amr', 'subtitle': '', 'image': null, 'link': '/u/amr'},
      _ => null,
    };

Future<http.Response> _handle(http.Request req) async {
  final path = req.url.path;
  final key = '${req.method} $path';
  _calls.add(key);
  if (req.body.startsWith('{')) _bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
  if (req.method == 'GET' && path == '/messages/SA0000002') {
    return _json([
      {'id': 'm1', 'sender_id': 'SA0000002', 'type': 'text', 'content': 'جرّبي #brew92/v60 حموضة فواكه واضحة', 'sent_at': _at(6)},
      {'id': 'm2', 'sender_id': 'SA0000002', 'type': 'text', 'content': '/meet 7م @brew92', 'sent_at': _at(5)},
      {'id': 'm3', 'sender_id': 'SA0000002', 'type': 'text', 'content': '/pay 22 قهوتك أمس', 'sent_at': _at(4)},
      {'id': 'm4', 'sender_id': 'SA0000001', 'type': 'text', 'content': 'راسل a@b.com أو #تاق عادي', 'sent_at': _at(3)},
    ]);
  }
  if (req.method == 'GET' && path == '/chat/meta') {
    final ids = (req.url.queryParameters['ids'] ?? '').split(',');
    final out = <String, dynamic>{};
    for (final id in ids) {
      final r = _requests[id];
      if (r != null) out[id] = {'replyTo': null, 'quote': null, 'forwardedFrom': null, 'extra': null, 'request': r};
    }
    return _json(out);
  }
  if (req.method == 'GET' && path == '/chat/cards') {
    final refs = (req.url.queryParameters['refs'] ?? '').split(',');
    return _json({'refs': {for (final r in refs) r: _card(r)}});
  }
  if (req.method == 'POST' && path == '/chat/requests') {
    final b = _bodies[key]!;
    final r = {'messageId': b['messageId'], 'kind': b['kind'], 'from': 'SA0000001', 'to': b['peerId'], 'amount': b['amount'], 'n': b['n'], 'share': b['amount'], 'note': b['note'], 'when': b['when'], 'place': b['place'], 'status': b['kind'] == 'send' ? 'paid' : 'pending', 'expiresAt': DateTime.now().add(const Duration(days: 1)).toIso8601String()};
    _requests[b['messageId'] as String] = r;
    return _json({'ok': true, 'request': r});
  }
  final act = RegExp(r'^/chat/requests/([^/]+)/(pay|accept|decline|cancel)$').firstMatch(path);
  if (req.method == 'POST' && act != null) {
    final r = Map<String, dynamic>.from(_requests[act.group(1)!]!);
    r['status'] = const {'pay': 'paid', 'accept': 'accepted', 'decline': 'declined', 'cancel': 'cancelled'}[act.group(2)];
    _requests[act.group(1)!] = r;
    return _json({'ok': true, 'request': r});
  }
  if (req.method == 'POST' && path == '/messages') {
    return _json({'message': {'id': 'srv-${_calls.where((c) => c == key).length}', 'sender_id': 'SA0000001', 'type': 'text', 'content': _bodies[key]!['content'], 'sent_at': DateTime.now().toUtc().toIso8601String()}});
  }
  // أوامر المال تظهر فقط حين يفعّل المدير التحويلات والدفع في المحادثة
  if (req.method == 'GET' && path == '/settings/public') return _json({'transfersEnabled': true, 'chatPaymentsEnabled': true});
  if (req.method == 'GET' && path == '/biz') return _json([]);
  if (req.method == 'GET' && path == '/tickets') return _json([{'id': 'tk1', 'code': 'NAS-ABCD1234', 'status': 'valid', 'paid': 5000, 'eventId': '22222222-2222-2222-2222-222222222222', 'title': 'لقاء المطورين', 'tier': 'عادي', 'startsAt': DateTime.now().add(const Duration(days: 1)).toIso8601String()}]);
  if (req.method == 'GET' && path == '/notify/unread') return _json({'unread': 0});
  if (req.method == 'GET' && path == '/contacts') return _json([{'id': 'SA0000003', 'nickname': 'khalid'}]);
  if (req.method == 'GET' && path == '/chats') return _json([]);
  if (path.startsWith('/presence/')) return _json({'online': true});
  if (req.method == 'POST') return _json({'ok': true});
  return _json({'error': 'not-found'}, 404);
}

Future<void> _pump(WidgetTester tester, {Size size = const Size(420, 1000)}) async {
  tester.view.physicalSize = size;
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
    child: const MaterialApp(locale: Locale('ar'), home: ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'))),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _settle(WidgetTester tester, [int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() {
    _calls.clear();
    _bodies.clear();
    _requests
      ..clear()
      ..['m2'] = {'messageId': 'm2', 'kind': 'meet', 'from': 'SA0000002', 'to': 'SA0000001', 'amount': 0, 'n': 1, 'share': 0, 'note': '', 'when': '7م', 'place': '@brew92', 'status': 'pending'}
      ..['m3'] = {'messageId': 'm3', 'kind': 'pay', 'from': 'SA0000002', 'to': 'SA0000001', 'amount': 2200, 'n': 1, 'share': 2200, 'note': 'قهوتك أمس', 'status': 'pending', 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toIso8601String()};
  });

  group('parser', () {
    test('refs: person, circle, item, event, space, ticket; trailing punctuation trimmed; max 4', () {
      final p = parseChatText('كلّم @sara، واطلب #brew92/v60! ثم #ev/11111111-1111-1111-1111-111111111111 و#space/kaia و#t/NAS-ABCD1234 و@khalid');
      expect(p.command, isNull);
      expect(p.refs.map((r) => r.raw), ['@sara', '#brew92/v60', '#ev/11111111-1111-1111-1111-111111111111', '#space/kaia']);
      expect(p.refs[0].kind, CodeKind.mention);
      expect(p.refs[1].kind, CodeKind.item);
      expect(p.refs[2].kind, CodeKind.event);
      expect(p.refs[3].kind, CodeKind.space);
      expect(p.commandOnly, isFalse);
    });
    test('plain hashtags, emails and URL fragments are not codes', () {
      final p = parseChatText('راسل a@b.com عن #جدة و https://naslife.app/#/c/biz-brew92 و#ev/nope');
      expect(p.hasCodes, isFalse);
    });
    test('commands: pay/send/split/meet/invite/where/loc with arabic digits', () {
      expect(parseCommand('/pay ٤٥ قهوة أمس')!.amount, 4500);
      expect(parseCommand('/pay 45 قهوة أمس')!.note, 'قهوة أمس');
      expect(parseCommand('/pay 12.5')!.amount, 1250);
      expect(parseCommand('/pay abc'), isNull);
      expect(parseCommand('/pay 0'), isNull);
      expect(parseCommand('/send 100 هدية')!.kind, CodeKind.send);
      final split = parseCommand('/split 180 4')!;
      expect((split.amount, split.n, split.share), (18000, 4, 4500));
      expect(parseCommand('/split 180 1'), isNull);
      final meet = parseCommand('/meet 7م @brew92')!;
      expect((meet.note, meet.place, meet.ref), ('7م', '@brew92', '@brew92'));
      expect(parseCommand('/meet 7م الكورنيش')!.ref, isNull);
      expect(parseCommand('/invite brew92')!.ref, '@brew92');
      expect(parseCommand('/invite ev/11111111-1111-1111-1111-111111111111')!.ref, '#ev/11111111-1111-1111-1111-111111111111');
      expect(parseCommand('/where')!.kind, CodeKind.where);
      final loc = parseCommand('/loc 21.54321,39.17654 عند البوابة')!;
      expect((loc.lat, loc.lng, loc.note), (21.54321, 39.17654, 'عند البوابة'));
      expect(parseCommand('/loc'), isNull, reason: 'يوسّعه المؤلّف قبل الإرسال');
      expect(parseCommand('/unknown x'), isNull);
      expect(parseCommand('نص /pay 5'), isNull, reason: 'الأمر في أول الرسالة فقط');
      expect(parseChatText('/pay 45 قهوة').commandOnly, isTrue);
      expect(parseChatText('/meet 7م @brew92').all.length, 1, reason: 'مكان الموعد ليس إشارة مستقلة');
    });
    test('code builders', () {
      expect(itemCode('biz-brew92', 'brew92-v60'), '#brew92/v60');
      expect(itemCode('biz-kaia', 'kaia-wifi'), '#kaia/wifi');
      expect(circleCode('biz-brew92'), '@brew92');
      expect(spaceCode('biz-kaia', 'abc'), '#space/kaia/abc');
      expect(currentCodeToken('hello @sa', 9), (start: 6, token: '@sa'));
      expect(currentCodeToken('/pa', 3), (start: 0, token: '/pa'));
      expect(currentCodeToken('x /pa', 5), isNull);
      expect(currentCodeToken('/pay ', 5), isNull);
    });
  });

  testWidgets('item ref renders a product card with price, discussions and order button; inline ref styled', (tester) async {
    await _pump(tester);
    expect(_calls.where((c) => c == 'GET /chat/cards').length, 1, reason: 'الإشارات تُحلّ دفعة واحدة');
    expect(find.byKey(const Key('card-item-brew92-v60')), findsOneWidget);
    expect(find.text('V60 تقطير'), findsOneWidget);
    expect(find.text('22 ر.س'), findsWidgets);
    expect(find.text('3 نقاش في مساحة الدائرة'), findsOneWidget);
    expect(find.text('اطلب'), findsOneWidget);
    expect(find.textContaining('جرّبي', findRichText: true), findsOneWidget, reason: 'النص يبقى مع الرمز مميّزاً');
    expect(find.textContaining('a@b.com', findRichText: true), findsOneWidget);
    expect(find.byType(ChatCodeCard), findsNWidgets(3));
  });

  testWidgets('pay request from the peer: pay button → confirm → POST pay → paid chip', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('card-pay')), findsOneWidget);
    expect(find.text('sara يطلب 22 ر.س'), findsOneWidget);
    expect(find.textContaining('قهوتك أمس'), findsWidgets);
    expect(find.text('/pay 22 قهوتك أمس'), findsNothing, reason: 'الأمر وحده لا يُعرض نصاً');
    await tester.tap(find.byKey(const Key('card-pay')));
    await _settle(tester);
    expect(find.byKey(const Key('pay-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay-confirm')));
    await _settle(tester);
    expect(_calls, contains('POST /chat/requests/m3/pay'));
    expect(find.text('مدفوع'), findsOneWidget);
    expect(find.byKey(const Key('card-pay')), findsNothing);
  });

  testWidgets('meet proposal resolves the circle as place; accept posts accept', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('card-req-meet')), findsOneWidget);
    expect(find.text('موعد 7م'), findsOneWidget);
    expect(find.textContaining('برو 92'), findsWidgets);
    await tester.tap(find.byKey(const Key('card-accept')));
    await _settle(tester);
    expect(_calls, contains('POST /chat/requests/m2/accept'));
    expect(find.text('تمت الموافقة'), findsOneWidget);
  });

  testWidgets('typing / shows command suggestions; picking inserts the trigger', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/pa');
    await tester.pump();
    expect(find.byKey(const Key('code-suggestions')), findsOneWidget);
    expect(find.text('طلب مبلغ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggest-/pay')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '/pay ');
    expect(find.byKey(const Key('code-suggestions')), findsNothing);
  });

  testWidgets('typing @ suggests the peer and contacts', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'كلّم @kh');
    await tester.pump();
    expect(find.byKey(const Key('suggest-@khalid')), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggest-@khalid')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'كلّم @khalid ');
  });

  testWidgets('sending /pay registers the request after the server id arrives; my card shows pending', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/pay 45 قهوة');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _settle(tester, 4);
    expect(_bodies['POST /messages']!['content'], '/pay 45 قهوة');
    final r = _bodies['POST /chat/requests']!;
    expect((r['kind'], r['amount'], r['note'], r['peerId']), ('pay', 4500, 'قهوة', 'SA0000002'));
    expect(r['messageId'].toString(), startsWith('srv-'));
    expect(find.text('تطلب 45 ر.س'), findsOneWidget);
    expect(find.byKey(const Key('card-cancel')), findsOneWidget);
  });

  testWidgets('/me expands to my nickname and renders my account card', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/me');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _settle(tester, 4);
    expect(_bodies['POST /messages']!['content'], '@amr');
    expect(find.byKey(const Key('card-user-SA0000001')), findsOneWidget);
  });

  testWidgets('/send asks for confirmation, transfers, then sends and registers as paid', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/send 25 هدية');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _settle(tester);
    expect(find.byKey(const Key('send-confirm')), findsOneWidget);
    expect(find.textContaining('25 ر.س'), findsWidgets);
    await tester.tap(find.byKey(const Key('send-confirm')));
    await _settle(tester, 4);
    expect(_bodies['POST /wallet/transfer'], {'to': 'SA0000002', 'amount': 2500, 'note': 'هدية'});
    expect(_calls.indexOf('POST /wallet/transfer'), lessThan(_calls.indexOf('POST /messages')));
    expect(_bodies['POST /chat/requests']!['kind'], 'send');
    expect(find.text('تم التحويل'), findsOneWidget);
  });

  testWidgets('malformed /pay is not sent; usage hint shown', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/pay قهوة');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _settle(tester);
    expect(_calls, isNot(contains('POST /messages')));
    expect(find.textContaining('الصيغة'), findsOneWidget);
  });

  testWidgets('+ sheet shows the smart codes grid; picking a code inserts it; ticket picker inserts #t code', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await _settle(tester);
    expect(find.text('رموز ذكية'), findsOneWidget);
    await tester.tap(find.byKey(const Key('code-menu-insert:/split ')));
    await _settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '/split ');
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('code-menu-picker:ticket')));
    await _settle(tester);
    expect(find.byKey(const Key('pick-ticket-NAS-ABCD1234')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-ticket-NAS-ABCD1234')));
    await _settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '#t/NAS-ABCD1234');
  });

  testWidgets('guide page lists commands and inserts an example into the composer', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '/help');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _settle(tester);
    expect(find.text('دليل رموز المحادثة'), findsOneWidget);
    final list = find.descendant(of: find.byType(ChatCodesGuidePage), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.byKey(const Key('guide-/meet')), 300, scrollable: list);
    expect(find.byKey(const Key('guide-/meet')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('guide-/pay')), -300, scrollable: list);
    await tester.tap(find.byKey(const Key('guide-/pay')));
    await _settle(tester);
    expect(find.text('دليل رموز المحادثة'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '/pay 45 قهوة أمس');
    expect(_calls, isNot(contains('POST /messages')));
  });
}
