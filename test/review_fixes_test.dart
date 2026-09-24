// مراجعة التصفّح بلا حساب والأمان (حساب مسجّل): الحظر من العارض والبث يحدّث قائمة المحظورين فيختفي محتواهم من الدوائر،
// البلاغ الذي يخفي المنشور يزيله من العارض، زر الإبلاغ عن خبر الدائرة داخل البطاقة حتى حين تفشل الصورة، رسالة الرصيد
// غير الكافي في iOS بلا دعوة للشحن، وماي سبيس (وصف المحفظة في iOS وبريد الدعم من الإعدادات العامة).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/dashboard_posts.dart';
import 'package:naslook/pages/chat/chat_thread_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/pages/posts/feed_page.dart';
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

const _p1 = 'aaaaaaaa-0000-4000-8000-000000000031';
const _p2 = 'aaaaaaaa-0000-4000-8000-000000000032';

Map<String, dynamic> _post(String id, String nick, String uid) => {
      'id': id, 'user': {'id': uid, 'nickname': nick}, 'kind': 'text', 'caption': 'لحظة $nick', 'bg': '#0A6E78', 'overlays': [], 'tag': 'moment', 'cta': null,
      'lat': 21.5, 'lng': 39.1, 'status': 'active', 'views': 1, 'likes': 0, 'liked': false, 'mine': false, 'expired': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
    };

Map<String, dynamic> _biz() => {
      'id': 'biz-ikea', 'name': 'IKEA', 'nameAr': 'إيكيا', 'category': 'brand', 'sector': 'أثاث', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '24 ساعة',
      'highlights': [], 'verified': false, 'official': false, 'followers': 3, 'rating': 4.5, 'ratingCount': 0, 'reviews': [], 'myOrders': [], 'ownerId': 'SA0000009',
      'items': [{'id': 'ikea-billy', 'bizId': 'biz-ikea', 'kind': 'product', 'title': 'مكتبة BILLY', 'description': 'رف', 'price': 44900, 'unit': 'item', 'stock': 5, 'meta': {}}],
      // صورة الخبر تفشل في الاختبار (لا شبكة) فتنكمش البطاقة
      'posts': [{'id': 'bp1', 'bizId': 'biz-ikea', 'kind': 'news', 'title': 'افتتاح فرع جديد', 'body': 'تفاصيل', 'imageUrl': 'https://test.local/none.jpg', 'createdAt': '2026-09-10T08:00:00Z'}],
    };

class _Srv {
  final calls = <String>[];
  final blocked = <Map<String, dynamic>>[];
  bool hideOnReport = false;
  Map<String, dynamic> settings = {'announcement': '', 'maintenance': false};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /blocks': return _json({'data': blocked});
      case 'POST /blocks':
        final id = (jsonDecode(req.body) as Map)['userId'];
        blocked.add({'id': id, 'nickname': id == 'SA0000002' ? 'sara' : 'khalid'});
        return _json({'ok': true});
      case 'POST /safety/report': return _json({'ok': true, 'reports': 3, 'hidden': hideOnReport, 'threshold': 3});
      case 'GET /mapposts/feed': return _json({'items': [_post(_p1, 'sara', 'SA0000002'), _post(_p2, 'khalid', 'SA0000003')], 'nextCursor': null, 'located': true});
      case 'GET /biz': return _json([_biz()]);
      case 'GET /biz/biz-ikea': return _json(_biz());
      case 'POST /biz/biz-ikea/orders': return _json({'error': 'insufficient-funds'}, 402);
      case 'GET /settings/public': return _json(settings);
      case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
      case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
      case 'GET /me/map-presence': return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread': return _json({'unread': 0});
      case 'GET /wallet': return _json({'balance': 0, 'points': 0, 'upcomingTickets': 0, 'recent': [], 'testTopup': false});
    }
    if (key.startsWith('POST /mapposts/') && key.endsWith('/view')) return _json({'ok': true, 'views': 2});
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<(_Srv, ProviderContainer)> _pump(WidgetTester tester, Widget home, {_Srv? srv, Size size = const Size(420, 1000)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return MaterialApp(locale: const Locale('ar'), home: home);
    }),
  ));
  await _settle(tester);
  return (s, container);
}

Future<void> _settle(WidgetTester tester, [int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// يبقي قائمة المحظورين مستمعة (كما تفعل شاشات الدوائر) ويعيد معرّفاتها الحالية.
Set<String> Function() _watchBlocked(ProviderContainer c) {
  c.listen(blockedUsersProvider, (_, __) {}, fireImmediately: true);
  return () => c.read(blockedIdsProvider);
}

void main() {
  tearDown(() {
    iosNativeOverride = null;
    LegalLinks.openOverride = null;
  });

  group('post viewer', () {
    testWidgets('blocking from the viewer refreshes the blocked list used by circles and profiles', (tester) async {
      final (srv, c) = await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(_post(_p1, 'sara', 'SA0000002'))]));
      final blocked = _watchBlocked(c);
      await _settle(tester);
      expect(blocked(), isEmpty);
      await tester.tap(find.byTooltip('خيارات'));
      await _settle(tester);
      await tester.tap(find.text('حظر sara'));
      await _settle(tester);
      expect(srv.calls, contains('POST /blocks'));
      expect(blocked(), contains('SA0000002'), reason: 'بلا تحديث القائمة تبقى منشورات المحظور في الدوائر ظاهرة');
    });

    testWidgets('a report that auto-hides the post removes it from the viewer', (tester) async {
      final (srv, _) = await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(_post(_p1, 'sara', 'SA0000002')), MapPost.fromJson(_post(_p2, 'khalid', 'SA0000003'))]), srv: _Srv()..hideOnReport = true);
      expect(find.text('لحظة sara'), findsOneWidget);
      await tester.tap(find.byTooltip('خيارات').first);
      await _settle(tester);
      await tester.tap(find.text('إبلاغ عن المنشور'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('report-reason-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-submit')));
      await _settle(tester);
      expect(srv.calls, contains('POST /safety/report'));
      expect(find.byType(PostViewerPage), findsOneWidget, reason: 'البلاغ بلا حظر لا يغلق العارض');
      expect(find.text('لحظة sara'), findsNothing, reason: 'المنشور المخفي يختفي من العارض كما يختفي من البث');
      expect(find.text('لحظة khalid'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('signed in, «مراسلة» still opens the chat', (tester) async {
      await _pump(tester, PostViewerPage(posts: [MapPost.fromJson(_post(_p1, 'sara', 'SA0000002'))]));
      await tester.tap(find.text('مراسلة'));
      await _settle(tester);
      expect(find.byType(ChatThreadPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('blocking from the feed refreshes the blocked list', (tester) async {
    final (srv, c) = await _pump(tester, const FeedPage(), size: const Size(420, 900));
    final blocked = _watchBlocked(c);
    await _settle(tester);
    expect(find.text('لحظة sara'), findsOneWidget);
    await tester.tap(find.byKey(const Key('feed-menu-$_p1')));
    await _settle(tester);
    await tester.tap(find.text('حظر sara'));
    await _settle(tester);
    expect(srv.calls, contains('POST /blocks'));
    expect(blocked(), contains('SA0000002'));
    await tester.pump(const Duration(seconds: 15)); // مهلة طلب موقع الجهاز في الخلفية
  });

  group('circle page', () {
    testWidgets('the news report button sits inside the card and opens even when the image fails', (tester) async {
      await _pump(tester, const BusinessPage(id: 'biz-ikea'), size: const Size(800, 2400));
      final menu = find.byKey(const Key('bizpost-bp1-menu'));
      expect(find.descendant(of: find.byType(PostCard), matching: menu), findsOneWidget);
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await _settle(tester);
      expect(find.byKey(const Key('bizpost-bp1-report')), findsOneWidget);
    });

    Future<void> buy(WidgetTester tester) async {
      await tester.ensureVisible(find.text('اشترِ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اشترِ'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ادفع'));
      await tester.pumpAndSettle();
    }

    testWidgets('iOS: insufficient funds says so without a wallet or top-up button', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const BusinessPage(id: 'biz-ikea'), size: const Size(800, 2400));
      await buy(tester);
      expect(find.byKey(const Key('biz-funds-ios')), findsOneWidget);
      expect(find.text('رصيد محفظتك لا يغطي هذا المبلغ'), findsOneWidget);
      expect(find.textContaining('اشحن'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'المحفظة'), findsNothing);
    });

    testWidgets('web: insufficient funds still offers the wallet', (tester) async {
      iosNativeOverride = false;
      await _pump(tester, const BusinessPage(id: 'biz-ikea'), size: const Size(800, 2400));
      await buy(tester);
      expect(find.textContaining('اشحن المحفظة'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'المحفظة'), findsOneWidget);
    });

    testWidgets('signed in: circles list shows «نشاطي التجاري» and «حجوزاتي», the circle page shows «حجوزاتي»', (tester) async {
      await _pump(tester, const BusinessesPage());
      expect(find.byKey(const Key('biz-mine')), findsOneWidget);
      expect(find.byKey(const Key('biz-bookings')), findsOneWidget);
      await _pump(tester, const BusinessPage(id: 'biz-ikea'));
      expect(find.byKey(const Key('biz-page-bookings')), findsOneWidget);
    });
  });

  group('MySpace', () {
    testWidgets('iOS: the wallet tile reads «الرصيد والمشتريات»; web keeps transfers and payments', (tester) async {
      iosNativeOverride = true;
      await _pump(tester, const Scaffold(body: MySpacePage()));
      expect(find.text('الرصيد والمشتريات'), findsOneWidget);
      expect(find.text('الرصيد والتحويلات والدفع'), findsNothing);
      iosNativeOverride = false;
      await _pump(tester, const Scaffold(body: MySpacePage()));
      expect(find.text('الرصيد والتحويلات والدفع'), findsOneWidget);
    });

    testWidgets('contact us uses the support email from the public settings', (tester) async {
      final opened = <Uri>[];
      LegalLinks.openOverride = (u) async => opened.add(u);
      await _pump(tester, const Scaffold(body: MySpacePage()), size: const Size(420, 1400), srv: _Srv()..settings = {'announcement': '', 'supportEmail': 'help@areebd.sa'});
      await tester.scrollUntilVisible(find.byKey(const Key('contact-us')), 300);
      expect(find.descendant(of: find.byKey(const Key('contact-us')), matching: find.text('help@areebd.sa')), findsOneWidget);
      await tester.tap(find.byKey(const Key('contact-us')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('contact-email')), matching: find.text('help@areebd.sa')), findsOneWidget);
      await tester.tap(find.byKey(const Key('contact-email')));
      await tester.pumpAndSettle();
      expect(opened.single.scheme, 'mailto');
      expect(opened.single.path, 'help@areebd.sa');
    });

    testWidgets('contact us falls back to the built-in address without a configured one', (tester) async {
      await _pump(tester, const Scaffold(body: MySpacePage()), size: const Size(420, 1400));
      await tester.scrollUntilVisible(find.byKey(const Key('contact-us')), 300);
      expect(find.descendant(of: find.byKey(const Key('contact-us')), matching: find.text(LegalLinks.supportEmail)), findsOneWidget);
    });
  });
}
