// نسخة iOS الأصلية ومفاتيح المال: ترويسة تعريف العميل x-naslife-client، إخفاء شراء سبوت لايت (إعلان رقمي) مع بقاء
// الإعلانات الجارية، محفظة بلا شحن ولا تحويل ولا دفع، وأوامر المال في المحادثة (/pay و/send و/split) غير متاحة؛
// ومقارنة بالسلوك نفسه حين لا يكون التطبيق iOS، وحين يطفئ المدير التحويلات أو الدفع في المحادثة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/market/seller_tools.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '11111111-1111-4111-8111-111111111111';
final _seller = {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null};
final _me = {'id': 'SA0000001', 'nickname': 'amr', 'avatarUrl': null};
Map<String, dynamic> _listing({bool mine = false}) => {
      'id': _lid, 'seller': mine ? _me : _seller, 'kind': 'product', 'category': 'food', 'subcategory': 'sweets', 'title': 'كيك عيد ميلاد', 'description': '', 'price': 22000, 'imageUrl': null, 'images': [], 'status': 'active',
      'lat': 21.5, 'lng': 39.1, 'mine': mine, 'spotlight': true, 'createdAt': '2026-09-10T08:00:00Z',
    };

class _Srv {
  bool spotlights = true, transfers = true, chatPay = true, testTopup = true, payEnabled = true;
  /// إعدادات عامة متعذّرة (خطأ خادم): الويب يبقي أزرار المال والخادم يفرض المفاتيح.
  bool settingsDown = false;
  final calls = <String>[];
  final headers = <Map<String, String>>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    headers.add(req.headers);
    switch (key) {
      case 'GET /settings/public' when settingsDown: return _json({'error': 'down'}, 500);
      case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false, 'testTopup': testTopup, 'transfersEnabled': transfers, 'chatPaymentsEnabled': chatPay});
      case 'GET /market/home': return _json({'spotlight': spotlights ? [{'id': 'sp1', 'endsAt': '2026-09-30T00:00:00Z', 'listing': _listing()}] : [], 'popular': [_listing()], 'nearby': [], 'bazaars': [], 'categories': {'food': 1}, 'wantedOpen': 0, 'spotlightPricePerDay': 2000, 'commissionPct': 5});
      case 'GET /market': return _json([_listing()]);
      case 'GET /market/$_lid': return _json(_listing(mine: true));
      case 'GET /market/$_lid/questions': return _json([]);
      case 'GET /market/$_lid/reviews': return _json([]);
      case 'GET /market/mine': return _json([_listing(mine: true)]);
      case 'GET /market/seller/stats': return _json({'today': {'orders': 0, 'revenue': 0}, 'week': {'orders': 0, 'revenue': 0}, 'month': {'orders': 0, 'revenue': 0, 'net': 0}, 'pending': 0, 'awaitingConfirm': 0, 'disputed': 0, 'views7': 0, 'conversionPct': 0, 'followers': 0, 'spotlightActive': 1, 'rating': {'avg': null, 'count': 0}, 'badges': [], 'listings': {'active': 1}, 'top': []});
      case 'GET /market/coupons': return _json([]);
      case 'GET /market/spotlight/mine': return _json([{'id': 'sp1', 'listingId': _lid, 'title': 'كيك عيد ميلاد', 'startsAt': '2026-09-17T00:00:00Z', 'endsAt': '2026-09-30T00:00:00Z', 'days': 8, 'paid': 16000, 'status': 'active', 'views': 120, 'clicks': 9, 'granted': false}]);
      case 'GET /market/seller/upgrade': return _json({'upgraded': null, 'eligible': false, 'listings': 1});
      case 'GET /wallet': return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': testTopup, 'recent': []});
      case 'GET /pay/config': return _json({'enabled': payEnabled, 'provider': 'moyasar', 'methods': ['creditcard'], 'min': 1000, 'max': 500000, 'currency': 'SAR'});
      case 'GET /messages/SA0000002':
        return _json([{'id': 'm3', 'sender_id': 'SA0000002', 'type': 'text', 'content': '/pay 22 قهوتك أمس', 'sent_at': DateTime.now().subtract(const Duration(minutes: 4)).toUtc().toIso8601String()}]);
      case 'GET /chat/meta':
        return _json({'m3': {'request': {'messageId': 'm3', 'kind': 'pay', 'from': 'SA0000002', 'to': 'SA0000001', 'amount': 2200, 'n': 1, 'share': 2200, 'note': 'قهوتك أمس', 'status': 'pending', 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toIso8601String()}}});
      case 'GET /contacts': return _json([]);
      case 'GET /chats': return _json([]);
      case 'GET /notify/unread': return _json({'unread': 0});
    }
    if (path.startsWith('/presence')) return _json({'online': true});
    if (req.method == 'POST') return _json({'ok': true});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv}) async {
  final s = srv ?? _Srv();
  tester.view.physicalSize = const Size(600, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      marketPosProvider.overrideWith((ref) async => (lat: 21.5, lng: 39.1)),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  tearDown(() => iosNativeOverride = null);

  group('client header', () {
    Future<Map<String, String>> sent() async {
      final srv = _Srv();
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
      await api.get('/settings/public');
      await api.post('/market/$_lid/view', const {}, prompt: false);
      expect(srv.headers.length, 2);
      // الطلبان يحملان القيمة نفسها
      expect(srv.headers[0]['x-naslife-client'], srv.headers[1]['x-naslife-client']);
      return srv.headers.first;
    }

    test('native iOS sends x-naslife-client: ios/<version>', () async {
      iosNativeOverride = true;
      expect(clientTag, 'ios/$appVersion');
      expect(ApiClient.clientHeaders(), {'x-naslife-client': 'ios/$appVersion'});
      final h = await sent();
      expect(h['x-naslife-client'], 'ios/$appVersion');
    });

    test('not iOS (and the test host, a desktop) sends no client header', () async {
      iosNativeOverride = false;
      expect(ApiClient.clientHeaders(), isEmpty);
      expect((await sent()).containsKey('x-naslife-client'), isFalse);
      iosNativeOverride = null; // الفحص الفعلي: Linux سطح مكتب
      expect(isIosNative, isFalse);
      expect(clientHeader, isNull);
      expect((await sent()).containsKey('x-naslife-client'), isFalse);
    });
  });

  group('spotlight', () {
    testWidgets('iOS: running spotlight ads still show, but no buy button or promo', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const MarketPage());
      expect(find.byKey(const Key('spot-$_lid')), findsOneWidget, reason: 'الإعلانات الجارية تبقى ظاهرة للمشترين');
      expect(find.byKey(const Key('spotlight-info')), findsNothing);
      expect(find.text('اعرض إعلانك'), findsNothing);
    });

    testWidgets('iOS: no spotlight ads means no promo card at all', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const MarketPage(), srv: _Srv()..spotlights = false);
      expect(find.byKey(const Key('spotlight-info')), findsNothing);
      expect(find.textContaining('سبوت لايت'), findsNothing);
    });

    testWidgets('web/Android: strip has the buy button and the empty state shows the promo', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const MarketPage());
      expect(find.byKey(const Key('spot-$_lid')), findsOneWidget);
      expect(find.text('اعرض إعلانك'), findsOneWidget);
      await _pump(tester, const MarketPage(), srv: _Srv()..spotlights = false);
      expect(find.byKey(const Key('spotlight-info')), findsOneWidget);
    });

    testWidgets('iOS: seller dashboard lists running spotlights without buy button or amounts', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const SellerDashboardPage());
      expect(find.byKey(const Key('spotlight-buy')), findsNothing);
      expect(find.textContaining('120 ظهور'), findsOneWidget);
      expect(find.textContaining('160 ر.س'), findsNothing, reason: 'لا مبالغ مدفوعة للإعلان في iOS');
    });

    testWidgets('web: seller dashboard offers buying spotlight and shows what was paid', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const SellerDashboardPage());
      expect(find.byKey(const Key('spotlight-buy')), findsOneWidget);
      expect(find.textContaining('120 ظهور'), findsOneWidget);
      // نظير اختبار iOS: المبلغ نفسه يظهر على الويب، فغيابه في iOS ليس تغيّراً في التنسيق
      expect(find.textContaining('160 ر.س'), findsOneWidget);
    });

    testWidgets('owner listing actions hide the spotlight button on iOS only', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const ListingPage(_lid));
      expect(find.byKey(const Key('owner-edit')), findsOneWidget);
      expect(find.byKey(const Key('owner-spotlight')), findsNothing);
      iosNativeOverride = false;
      await _pump(tester, const ListingPage(_lid));
      expect(find.byKey(const Key('owner-spotlight')), findsOneWidget);
    });
  });

  group('wallet', () {
    testWidgets('iOS: balance and history with a neutral line; no top-up, card, transfer, pay or QR', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const WalletPage());
      expect(find.text('1000 ر.س'), findsWidgets);
      expect(find.byKey(const Key('wallet-ios-note')), findsOneWidget);
      expect(find.text('رصيدك يُستخدم للشراء من البائعين والأماكن'), findsOneWidget);
      for (final k in ['wallet-transfer', 'wallet-pay', 'wallet-qr', 'wallet-test-topup', 'wallet-card-topup']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.text('تذاكري'), findsOneWidget);
    });

    testWidgets('web with transfers enabled: every action is there', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const WalletPage());
      for (final k in ['wallet-transfer', 'wallet-pay', 'wallet-qr', 'wallet-test-topup', 'wallet-card-topup']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('wallet-ios-note')), findsNothing);
    });

    testWidgets('web with /settings/public failing: transfer, pay and QR stay (the server enforces the switch)', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const WalletPage(), srv: _Srv()..settingsDown = true);
      for (final k in ['wallet-transfer', 'wallet-pay', 'wallet-qr']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('iOS with /settings/public failing: still no transfer, pay or QR', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const WalletPage(), srv: _Srv()..settingsDown = true);
      for (final k in ['wallet-transfer', 'wallet-pay', 'wallet-qr']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('web with transfers switched off by the admin: no transfer, pay or QR', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const WalletPage(), srv: _Srv()..transfers = false);
      for (final k in ['wallet-transfer', 'wallet-pay', 'wallet-qr']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.byKey(const Key('wallet-card-topup')), findsOneWidget);
    });
  });

  group('chat money commands', () {
    const peer = ChatThreadPage(peer: Person(id: 'SA0000002', nickname: 'sara'));

    testWidgets('iOS: /pay /send /split are not suggested, not in the + menu, and a typed /pay is refused', (tester) async {
      iosNativeOverride = true;
      final srv = await _pump(tester, peer);
      // طلب المبلغ الوارد يبقى مقروءاً بلا زر دفع
      expect(find.byKey(const Key('card-req-pay')), findsOneWidget);
      expect(find.byKey(const Key('card-pay')), findsNothing);
      expect(find.byKey(const Key('card-pay-off')), findsOneWidget);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(find.byKey(const Key('suggest-/meet')), findsOneWidget);
      for (final c in ['/pay', '/send', '/split']) {
        expect(find.byKey(Key('suggest-$c')), findsNothing, reason: c);
      }
      await tester.enterText(find.byType(TextField), '/pay 45 قهوة');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(find.text('غير متاح'), findsOneWidget);
      expect(srv.calls, isNot(contains('POST /messages')));
      expect(srv.calls, isNot(contains('POST /chat/requests')));
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(seconds: 5)); // يختفي التنبيه عن زر «+»
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await _settle(tester);
      expect(find.text('رموز ذكية'), findsOneWidget);
      expect(find.byKey(const Key('code-menu-insert:/meet ')), findsOneWidget);
      expect(find.byKey(const Key('code-menu-insert:/pay ')), findsNothing);
      expect(find.byKey(const Key('code-menu-insert:/send ')), findsNothing);
      expect(find.byKey(const Key('code-menu-insert:/split ')), findsNothing);
    });

    testWidgets('iOS: the guide lists no money commands', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, peer);
      await tester.enterText(find.byType(TextField), '/help');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(find.text('دليل رموز المحادثة'), findsOneWidget);
      expect(find.byKey(const Key('guide-/pay'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('guide-/send'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('guide-/split'), skipOffstage: false), findsNothing);
      // الأمثلة في آخر الدليل لا تُبنى قبل التمرير إليها
      await tester.scrollUntilVisible(find.text('أمثلة واقعية'), 300);
      await tester.scrollUntilVisible(find.text('مسافران في مساحة المطار'), 300);
      for (final c in ['/pay', '/send', '/split']) {
        expect(find.textContaining(c, skipOffstage: false), findsNothing, reason: c);
      }
      expect(find.text('بين صديقين بعد جلسة قهوة', skipOffstage: false), findsOneWidget, reason: 'مثال غرضه ليس المال يبقى بلا سطر المال');
      expect(find.text('رحلة عائلية وتقسيم الفاتورة', skipOffstage: false), findsNothing, reason: 'مثال غرضه المال يُحذف كله');
    });

    testWidgets('web with /settings/public failing: money commands are still suggested', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, peer, srv: _Srv()..settingsDown = true);
      expect(find.byKey(const Key('card-pay')), findsOneWidget);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(find.byKey(const Key('suggest-/pay')), findsOneWidget);
    });

    testWidgets('web with chat payments on: money commands are suggested and the pay button shows', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, peer);
      expect(find.byKey(const Key('card-pay')), findsOneWidget);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(find.byKey(const Key('suggest-/pay')), findsOneWidget);
    });

    testWidgets('web with chat payments switched off: no money commands and a typed /split is refused', (tester) async {
      iosNativeOverride = false;
      final srv = await _pump(tester, peer, srv: _Srv()..chatPay = false);
      expect(find.byKey(const Key('card-pay')), findsNothing);
      await tester.enterText(find.byType(TextField), '/s');
      await tester.pump();
      expect(find.byKey(const Key('suggest-/split')), findsNothing);
      expect(find.byKey(const Key('suggest-/send')), findsNothing);
      await tester.enterText(find.byType(TextField), '/split 180 4');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(find.text('غير متاح'), findsOneWidget);
      expect(srv.calls, isNot(contains('POST /messages')));
    });
  });
}
