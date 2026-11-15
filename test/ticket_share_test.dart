// توزيع التذاكر (نوفمبر 2026): شاشة «وزّع التذاكر» (إرسال لصديق، رابط عبر تطبيق آخر، استرجاع، عدّاد التقدم)، «تذاكر وصلتك» في
// «تذاكري» (قبول ورفض)، عرض التوزيع بعد شراء أكثر من تذكرة، قراءة رابط /t/<رمز>، وصفحة الاستلام (نجاح، لم تعد متاحة، رابطي أنا).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/api/ticket_share_api.dart';
import 'package:naslook/app/app.dart' show pendingLinkPage;
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/core/share/share_io.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/events/ticket_claim_page.dart';
import 'package:naslook/pages/events/ticket_share_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

const _ev = 'ev-1', _token = 'AbCdEf0123456789_-xyz';
final _starts = DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String();

Map<String, dynamic> _ticket(String id, {String event = _ev, String status = 'valid', String? code}) =>
    {'id': id, 'code': code ?? 'NAS-${id.toUpperCase()}', 'status': status, 'paid': 0, 'eventId': event, 'title': 'ليلة الجاز', 'tier': 'عادي', 'startsAt': _starts, 'placeName': 'المسرح'};

/// خادم بديل بحالة: تذاكري، الإرسالات المعلّقة مني، والواردة إليّ، بسلوك العقد (معلّق واحد لكل تذكرة، الرابط نفسه يُعاد).
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  var tickets = <Map<String, dynamic>>[_ticket('k1'), _ticket('k2'), _ticket('k3'), _ticket('other', event: 'ev-2')];
  final out = <String, Map<String, dynamic>>{};
  var incoming = <Map<String, dynamic>>[];
  final friends = <Map<String, dynamic>>[{'id': 'SA0000002', 'nickname': 'sara'}, {'id': 'SA0000003', 'nickname': 'khalid'}];
  /// رفض مفروض لمسار بعينه: المفتاح «METHOD /path» والقيمة (الحالة، الرمز)
  final fail = <String, (int, String)>{};
  String claimStatus = 'pending';
  int _n = 0;

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (fail[key] case (final code, final err)) return _json({'error': err}, code);
    if (key == 'GET /tickets') return _json(tickets);
    if (key == 'GET /contacts') return _json(friends);
    if (key == 'GET /tickets/shares') return _json({'outgoing': out.values.toList(), 'incoming': incoming});
    var m = RegExp(r'^(POST|DELETE) /tickets/([^/]+)/(send|link)$').firstMatch(key);
    if (m != null) {
      final id = m.group(2)!;
      if (m.group(1) == 'DELETE') return out.remove(id) == null ? _json({'error': 'not-found'}, 404) : _json({'ok': true});
      final cur = out[id];
      if (m.group(3) == 'link') {
        if (cur != null) return cur['mode'] == 'link' ? _json(cur) : _json({'error': 'already-pending'}, 409);
        return _json(out[id] = {'ticketId': id, 'transferId': 'tr-${++_n}', 'mode': 'link', 'to': null, 'url': 'https://naslife.app/t/$_token', 'createdAt': _starts});
      }
      if (cur != null) return _json({'error': 'already-pending'}, 409);
      final to = friends.firstWhere((f) => f['id'] == bodies[key]!['userId']);
      return _json(out[id] = {'ticketId': id, 'transferId': 'tr-${++_n}', 'mode': 'user', 'to': {...to, 'avatarUrl': null}, 'url': null, 'createdAt': _starts});
    }
    m = RegExp(r'^POST /tickets/transfers/([^/]+)/(accept|decline)$').firstMatch(key);
    if (m != null) {
      final x = incoming.firstWhere((i) => i['transferId'] == m!.group(1));
      incoming = [for (final i in incoming) if (i != x) i];
      if (m.group(2) == 'decline') return _json({'ok': true});
      final t = _ticket('${(x['ticket'] as Map)['id']}', code: 'NAS-NEWCODE1');
      tickets = [...tickets, t];
      return _json(t);
    }
    if (key == 'GET /tickets/claim/$_token') return _json({'title': 'ليلة الجاز', 'startsAt': _starts, 'placeName': 'المسرح', 'tier': 'عادي', 'from': {'nickname': 'sara', 'avatarUrl': null}, 'status': claimStatus});
    if (key == 'POST /tickets/claim') {
      final t = _ticket('claimed', code: 'NAS-CLAIMED1');
      tickets = [...tickets, t];
      return _json(t);
    }
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key.startsWith('GET /wishlist')) return _json({'saved': false});
    return _json({'error': 'not-found'}, 404);
  }

  int count(String key) => calls.where((c) => c == key).length;
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _settle(tester);
}

Finder _in(String rowKey, String text) => find.descendant(of: find.byKey(Key(rowKey)), matching: find.text(text));

void main() {
  // الحافظة: ما نُسخ يُقرأ من هنا
  String? clip;
  setUp(() {
    clip = null;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
  });
  tearDown(() {
    nativeShareOverride = null;
    pendingLink = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('models and links', () {
    test('shares parse outgoing (user and link) and incoming, and find the pending transfer of a ticket', () {
      final s = TicketShares.fromJson({
        'outgoing': [
          {'ticketId': 'k2', 'transferId': 'tr-1', 'mode': 'user', 'to': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'url': null, 'createdAt': _starts},
          {'ticketId': 'k3', 'transferId': 'tr-2', 'mode': 'link', 'to': null, 'url': 'https://naslife.app/t/$_token', 'createdAt': _starts},
        ],
        'incoming': [
          {'transferId': 'tr-9', 'from': {'id': 'SA0000003', 'nickname': 'khalid', 'avatarUrl': null}, 'ticket': {'id': 'x1', 'eventId': 'ev-9', 'title': 'معرض', 'startsAt': _starts, 'placeName': 'الواجهة', 'tier': 'كبار الزوار'}, 'createdAt': _starts},
        ],
      });
      expect(s.pendingOf('k2')?.to?.nickname, 'sara');
      expect(s.pendingOf('k2')?.isLink, isFalse);
      expect(s.pendingOf('k3')?.url, 'https://naslife.app/t/$_token');
      expect(s.pendingOf('k3')?.isLink, isTrue);
      expect(s.pendingOf('k1'), isNull);
      final i = s.incoming.single;
      expect((i.transferId, i.from.nickname, i.ticketId, i.eventId, i.title, i.tier, i.placeName), ('tr-9', 'khalid', 'x1', 'ev-9', 'معرض', 'كبار الزوار', 'الواجهة'));
      expect(const TicketShares().outgoing, isEmpty);
    });

    test('/t/<token> is a ticket link by path or fragment, needs an account, and keeps the token case', () {
      final a = parsePendingLink(Uri.parse('https://naslife.app/t/$_token'));
      expect(a?.toString(), 'ticket:$_token');
      expect(a?.isTicket, isTrue);
      expect(a?.needsAccount, isTrue);
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/t/$_token'))?.toString(), 'ticket:$_token');
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/t/$_token/'))?.value, _token);
      expect(parsePendingLink(Uri.parse('https://naslife.app/t/short')), isNull, reason: 'أقصر من 16');
      expect(parsePendingLink(Uri.parse('https://naslife.app/t/${'a' * 65}')), isNull, reason: 'أطول من 64');
      expect(parsePendingLink(Uri.parse('https://naslife.app/t/bad.token.with.dots.0000')), isNull);
      // الأنواع الأخرى كما كانت
      expect(parsePendingLink(Uri.parse('https://naslife.app/#/manage'))?.needsAccount, isTrue);
      expect(parsePendingLink(Uri.parse('https://naslife.app/c/biz-brew92'))?.needsAccount, isFalse);
      final page = pendingLinkPage(a!);
      expect(page, isA<TicketClaimPage>());
      expect((page as TicketClaimPage).token, _token);
    });

    test('ticket notifications open «تذاكري»', () {
      for (final k in ['ticket_gift', 'ticket_accepted', 'ticket_declined']) {
        final n = AppNotification(id: 'n-$k', kind: k, title: 't', data: const {'eventId': _ev, 'transferId': 'tr-1'});
        expect(notificationTarget(n), isA<MyTicketsPage>(), reason: k);
      }
    });

    test('every contract error code has its own Arabic message', () {
      String msg(String code, [int status = 409]) => ticketShareErrText(ApiException(status, 'x', body: {'error': code}));
      final codes = ['not-found', 'not-transferable', 'already-pending', 'bad-user', 'self', 'blocked', 'gone'];
      final texts = {for (final c in codes) msg(c)};
      expect(texts.length, codes.length, reason: 'رسالة لكل رمز');
      final fallback = msg('something-else');
      expect(texts.contains(fallback), isFalse);
      for (final t in [...texts, fallback]) {
        expect(RegExp(r'[a-zA-Z—]').hasMatch(t), isFalse, reason: t);
      }
    });
  });

  group('«وزّع التذاكر»', () {
    testWidgets('lists only this event\'s valid tickets, the first one stays mine, progress starts at zero', (tester) async {
      final srv = _Srv()..tickets.add(_ticket('used', status: 'used'));
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      expect(find.text('وُزّع 0 من 3'), findsOneWidget);
      expect(_in('share-row-k1', 'تذكرتي'), findsOneWidget);
      expect(find.text('تذكرتي'), findsOneWidget);
      expect(find.byKey(const Key('share-row-k2')), findsOneWidget);
      expect(find.byKey(const Key('share-row-k3')), findsOneWidget);
      expect(find.byKey(const Key('share-row-other')), findsNothing, reason: 'تذكرة فعالية أخرى');
      expect(find.byKey(const Key('share-row-used')), findsNothing, reason: 'المستخدمة لا تُوزّع');
      expect(_in('share-row-k2', 'أرسل'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0);
    });

    testWidgets('send to a friend: row shows the friend waiting, progress moves, and that friend is not offered again', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      await _tap(tester, find.byKey(const Key('ticket-send-k2')));
      expect(find.byKey(const Key('share-friend-SA0000002')), findsOneWidget);
      expect(find.byKey(const Key('share-friend-SA0000003')), findsOneWidget);
      expect(find.byKey(const Key('share-link')), findsOneWidget);
      expect(find.byKey(const Key('share-copy')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('share-friend-SA0000002')));
      expect(srv.bodies['POST /tickets/k2/send'], {'userId': 'SA0000002'});
      expect(find.text('وُزّع 1 من 3'), findsOneWidget);
      expect(_in('share-row-k2', 'sara'), findsOneWidget);
      expect(_in('share-row-k2', 'بانتظار القبول'), findsOneWidget);
      expect(find.byKey(const Key('ticket-undo-k2')), findsOneWidget);
      expect(find.byKey(const Key('ticket-send-k2')), findsNothing);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(1 / 3, 1e-9));
      // التذكرة الثالثة: sara خرجت من القائمة
      await _tap(tester, find.byKey(const Key('ticket-send-k3')));
      expect(find.byKey(const Key('share-friend-SA0000002')), findsNothing);
      expect(find.byKey(const Key('share-friend-SA0000003')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('share-friend-SA0000003')));
      expect(srv.bodies['POST /tickets/k3/send'], {'userId': 'SA0000003'});
      expect(find.text('وُزّع 2 من 3'), findsOneWidget);
      expect(_in('share-row-k1', 'تذكرتي'), findsOneWidget, reason: 'الأولى بقيت لي');
    });

    testWidgets('send through another app: creates the one-person link and hands it to the native share sheet', (tester) async {
      final shared = <({String title, String text, String url})>[];
      nativeShareOverride = ({required title, required text, required url}) async {
        shared.add((title: title, text: text, url: url));
        return true;
      };
      final srv = _Srv();
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      await _tap(tester, find.byKey(const Key('ticket-send-k2')));
      await _tap(tester, find.byKey(const Key('share-link')));
      expect(srv.count('POST /tickets/k2/link'), 1);
      expect(shared.single.url, 'https://naslife.app/t/$_token');
      expect(shared.single.text, contains('ليلة الجاز'));
      expect(shared.single.text, contains('لشخص واحد'));
      expect(shared.single.text.contains('—'), isFalse);
      expect(clip, isNull, reason: 'ورقة النظام عملت فلا نسخ');
      expect(find.text('وُزّع 1 من 3'), findsOneWidget);
      expect(_in('share-row-k2', 'رابط · بانتظار من يستلمه'), findsOneWidget);
      expect(find.byKey(const Key('ticket-undo-k2')), findsOneWidget);
      // إعادة إرسال الرابط نفسه بلا طلب جديد
      await _tap(tester, find.byKey(const Key('ticket-reshare-k2')));
      expect(shared.length, 2);
      expect(shared.last.url, shared.first.url);
      expect(srv.count('POST /tickets/k2/link'), 1);
    });

    testWidgets('no native share sheet: the link is copied instead; «نسخ الرابط» copies it too', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      await _tap(tester, find.byKey(const Key('ticket-send-k2')));
      await _tap(tester, find.byKey(const Key('share-link')));
      expect(clip, 'https://naslife.app/t/$_token');
      expect(find.text('نُسخ الرابط، الصقه حيث تريد'), findsOneWidget);
      clip = null;
      await _tap(tester, find.byKey(const Key('ticket-send-k3')));
      await _tap(tester, find.byKey(const Key('share-copy')));
      expect(srv.count('POST /tickets/k3/link'), 1);
      expect(clip, 'https://naslife.app/t/$_token');
      expect(find.text('وُزّع 2 من 3'), findsOneWidget);
    });

    testWidgets('undo returns the ticket: DELETE is sent, the row can be sent again and progress goes back', (tester) async {
      final srv = _Srv();
      srv.out['k2'] = {'ticketId': 'k2', 'transferId': 'tr-1', 'mode': 'user', 'to': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'url': null, 'createdAt': _starts};
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      expect(find.text('وُزّع 1 من 3'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('ticket-undo-k2')));
      expect(srv.count('DELETE /tickets/k2/send'), 1);
      expect(find.text('وُزّع 0 من 3'), findsOneWidget);
      expect(find.byKey(const Key('ticket-undo-k2')), findsNothing);
      expect(find.byKey(const Key('ticket-send-k2')), findsOneWidget);
      expect(find.text('استُرجعت التذكرة'), findsOneWidget);
    });

    testWidgets('a refused send shows the reason in Arabic and leaves the ticket unsent', (tester) async {
      final srv = _Srv()..fail['POST /tickets/k2/send'] = (403, 'blocked');
      await _pump(tester, srv, const TicketSharePage(eventId: _ev, title: 'ليلة الجاز'));
      await _tap(tester, find.byKey(const Key('ticket-send-k2')));
      await _tap(tester, find.byKey(const Key('share-friend-SA0000002')));
      expect(find.text('لا يمكن الإرسال إلى هذا المستخدم'), findsOneWidget);
      expect(find.text('وُزّع 0 من 3'), findsOneWidget);
      expect(find.byKey(const Key('ticket-send-k2')), findsOneWidget);
      srv.fail['POST /tickets/k2/send'] = (409, 'not-transferable');
      await _tap(tester, find.byKey(const Key('ticket-send-k2')));
      await _tap(tester, find.byKey(const Key('share-friend-SA0000002')));
      expect(find.textContaining('لا يمكن إرسالها'), findsOneWidget);
    });
  });

  group('«تذاكري»', () {
    Map<String, dynamic> gift(String id, String from) => {
          'transferId': id,
          'from': {'id': 'SA00000$from', 'nickname': from == '02' ? 'sara' : 'khalid', 'avatarUrl': null},
          'ticket': {'id': 'g-$id', 'eventId': 'ev-9', 'title': 'معرض الكتاب', 'startsAt': _starts, 'placeName': 'الواجهة', 'tier': 'عادي'},
          'createdAt': _starts,
        };

    testWidgets('incoming tickets on top: accept moves it into my tickets, decline removes it', (tester) async {
      final srv = _Srv()..incoming = [gift('tr-7', '02'), gift('tr-8', '03')];
      await _pump(tester, srv, const MyTicketsPage());
      expect(find.text('تذاكر وصلتك'), findsOneWidget);
      expect(find.text('sara أرسل لك تذكرة'), findsOneWidget);
      expect(find.text('khalid أرسل لك تذكرة'), findsOneWidget);
      expect(tester.getTopLeft(find.text('تذاكر وصلتك')).dy, lessThan(tester.getTopLeft(find.text('القادمة')).dy));
      expect(find.text('معرض الكتاب'), findsNWidgets(2));
      await _tap(tester, find.byKey(const Key('ticket-accept-tr-7')));
      expect(srv.count('POST /tickets/transfers/tr-7/accept'), 1);
      expect(find.byKey(const Key('ticket-incoming-tr-7')), findsNothing);
      expect(find.byKey(const Key('ticket-incoming-tr-8')), findsOneWidget);
      expect(find.byKey(const Key('my-ticket-send-g-tr-7')), findsOneWidget, reason: 'صارت في تذاكري');
      expect(srv.count('GET /tickets'), 2, reason: 'القائمة تُحدَّث بعد القبول');
      await _tap(tester, find.byKey(const Key('ticket-decline-tr-8')));
      expect(srv.count('POST /tickets/transfers/tr-8/decline'), 1);
      expect(find.text('تذاكر وصلتك'), findsNothing);
      expect(find.byKey(const Key('my-ticket-send-g-tr-8')), findsNothing);
    });

    testWidgets('accepting a ticket that was taken back says so and drops the card', (tester) async {
      final srv = _Srv()
        ..incoming = [gift('tr-7', '02')]
        ..fail['POST /tickets/transfers/tr-7/accept'] = (409, 'gone');
      await _pump(tester, srv, const MyTicketsPage());
      srv.incoming = [];
      await _tap(tester, find.byKey(const Key('ticket-accept-tr-7')));
      expect(find.textContaining('لم تعد متاحة'), findsOneWidget);
      expect(find.byKey(const Key('ticket-incoming-tr-7')), findsNothing);
    });

    testWidgets('only gifts and no tickets yet: the gifts show instead of the empty state', (tester) async {
      final srv = _Srv()
        ..tickets = []
        ..incoming = [gift('tr-7', '02')];
      await _pump(tester, srv, const MyTicketsPage());
      expect(find.text('لا تذاكر بعد'), findsNothing);
      expect(find.byKey(const Key('ticket-accept-tr-7')), findsOneWidget);
    });

    testWidgets('my valid tickets carry «أرسل» and a chip while pending; it opens the distribute page for that event', (tester) async {
      final srv = _Srv()..tickets.add(_ticket('used', status: 'used'));
      srv.out['k2'] = {'ticketId': 'k2', 'transferId': 'tr-1', 'mode': 'user', 'to': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'url': null, 'createdAt': _starts};
      srv.out['k3'] = {'ticketId': 'k3', 'transferId': 'tr-2', 'mode': 'link', 'to': null, 'url': 'https://naslife.app/t/$_token', 'createdAt': _starts};
      await _pump(tester, srv, const MyTicketsPage());
      expect(find.byKey(const Key('ticket-pending-k1')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('ticket-pending-k2')), matching: find.text('بانتظار القبول')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('ticket-pending-k3')), matching: find.text('رابط مُرسل')), findsOneWidget);
      expect(find.byKey(const Key('my-ticket-send-used')), findsNothing, reason: 'المستخدمة لا تُرسل');
      await _tap(tester, find.byKey(const Key('my-ticket-send-k1')));
      final page = tester.widget<TicketSharePage>(find.byType(TicketSharePage));
      expect((page.eventId, page.title), (_ev, 'ليلة الجاز'));
      expect(find.text('وُزّع 2 من 3'), findsOneWidget);
    });

    testWidgets('a server without ticket sharing still shows my tickets, just without the send action', (tester) async {
      final srv = _Srv()..fail['GET /tickets/shares'] = (404, 'not-found');
      await _pump(tester, srv, const MyTicketsPage());
      expect(find.text('ليلة الجاز'), findsNWidgets(4));
      expect(find.byKey(const Key('my-ticket-send-k1')), findsNothing);
    });
  });

  group('after buying', () {
    Map<String, dynamic> event() => {
          'id': _ev, 'title': 'ليلة الجاز', 'description': '', 'host': {'id': 'SA0000002', 'nickname': 'sara'}, 'placeName': 'المسرح', 'startsAt': _starts, 'isHost': false, 'going': 0, 'myTickets': 0,
          'tiers': [{'id': 't-free', 'name': 'عادي', 'description': '', 'price': 0, 'quantity': 10, 'sold': 0, 'left': 10}],
        };

    Future<_Srv> open(WidgetTester tester, int bought) async {
      final srv = _Srv();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        if (key == 'GET /events/$_ev') return _json(event());
        if (key == 'POST /events/$_ev/tickets') {
          srv.calls.add(key);
          srv.bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'data': srv.tickets.take(bought).toList()});
        }
        return srv.handle(req);
      }));
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
        child: const MaterialApp(locale: Locale('ar'), home: EventDetailPage(eventId: _ev)),
      ));
      await _settle(tester);
      return srv;
    }

    testWidgets('more than one ticket: offers to distribute them and opens the distribute page', (tester) async {
      final srv = await open(tester, 3);
      await _tap(tester, find.byIcon(Icons.add_rounded));
      await _tap(tester, find.byIcon(Icons.add_rounded));
      await _tap(tester, find.text('احجز'));
      expect(srv.bodies['POST /events/$_ev/tickets'], {'tierId': 't-free', 'qty': 3});
      expect(find.text('وزّع التذاكر على أصحابك'), findsOneWidget);
      expect(find.text('لاحقاً'), findsOneWidget);
      expect(find.byType(MyTicketsPage), findsNothing);
      await _tap(tester, find.byKey(const Key('buy-share-now')));
      final page = tester.widget<TicketSharePage>(find.byType(TicketSharePage));
      expect((page.eventId, page.title), (_ev, 'ليلة الجاز'));
      expect(find.text('وُزّع 0 من 3'), findsOneWidget);
    });

    testWidgets('«لاحقاً» goes to my tickets as before', (tester) async {
      await open(tester, 2);
      await _tap(tester, find.byIcon(Icons.add_rounded));
      await _tap(tester, find.text('احجز'));
      await _tap(tester, find.byKey(const Key('buy-share-later')));
      expect(find.byType(MyTicketsPage), findsOneWidget);
      expect(find.byType(TicketSharePage), findsNothing);
    });

    testWidgets('a single ticket is not asked: straight to my tickets', (tester) async {
      await open(tester, 1);
      await _tap(tester, find.text('احجز'));
      expect(find.byKey(const Key('buy-share-now')), findsNothing);
      expect(find.byType(MyTicketsPage), findsOneWidget);
    });
  });

  group('claim page', () {
    testWidgets('preview then «استلم التذكرة»: success state leads to my tickets with the new ticket', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const TicketClaimPage(token: _token));
      expect(find.text('sara أرسل لك تذكرة'), findsOneWidget);
      expect(find.byKey(const Key('claim-title')), findsOneWidget);
      expect(find.textContaining('المسرح'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('claim-accept')));
      expect(srv.bodies['POST /tickets/claim'], {'token': _token});
      expect(find.byKey(const Key('claim-done')), findsOneWidget);
      expect(find.byKey(const Key('claim-accept')), findsNothing);
      await _tap(tester, find.byKey(const Key('claim-my-tickets')));
      expect(find.byType(MyTicketsPage), findsOneWidget);
      expect(find.byType(TicketClaimPage), findsNothing);
      expect(find.byKey(const Key('my-ticket-send-claimed')), findsOneWidget);
    });

    testWidgets('a link already taken shows gone and no claim button', (tester) async {
      final srv = _Srv()..claimStatus = 'gone';
      await _pump(tester, srv, const TicketClaimPage(token: _token));
      expect(find.byKey(const Key('claim-gone')), findsOneWidget);
      expect(find.text('التذكرة لم تعد متاحة'), findsOneWidget);
      expect(find.byKey(const Key('claim-accept')), findsNothing);
      expect(srv.count('POST /tickets/claim'), 0);
    });

    testWidgets('taken between preview and claim: the 409 gone turns into the gone state', (tester) async {
      final srv = _Srv()..fail['POST /tickets/claim'] = (409, 'gone');
      await _pump(tester, srv, const TicketClaimPage(token: _token));
      await _tap(tester, find.byKey(const Key('claim-accept')));
      expect(find.byKey(const Key('claim-gone')), findsOneWidget);
      expect(find.byKey(const Key('claim-done')), findsNothing);
    });

    testWidgets('the sender opening their own link is told it is theirs', (tester) async {
      final srv = _Srv()..fail['POST /tickets/claim'] = (400, 'self');
      await _pump(tester, srv, const TicketClaimPage(token: _token));
      await _tap(tester, find.byKey(const Key('claim-accept')));
      expect(find.byKey(const Key('claim-self')), findsOneWidget);
      expect(find.text('هذه تذكرتك أنت'), findsOneWidget);
    });

    testWidgets('an unknown token shows not-found', (tester) async {
      final srv = _Srv()..fail['GET /tickets/claim/$_token'] = (404, 'not-found');
      await _pump(tester, srv, const TicketClaimPage(token: _token));
      expect(find.byKey(const Key('claim-not-found')), findsOneWidget);
      expect(find.byKey(const Key('claim-accept')), findsNothing);
    });
  });
}
