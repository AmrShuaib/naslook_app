// «استكشف» (قسم الشريط السفلي بدل «الفعاليات»): أقسام من بيانات حقيقية فقط (الفعاليات القادمة ودوائر الأعمال مجمّعة
// بما تقدّمه)، رقائق تظهر للأقسام التي فيها بيانات وحدها، الفعالية تفتح صفحتها والدائرة صفحتها، «الكل» يفتح صفحة
// الفعاليات أو يختار قسم الدوائر، حالة فارغة وخطأ بإعادة محاولة، و«تذاكري» وإنشاء الفعالية يدعوان الزائر للدخول.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_list.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/explore/explore_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _SignedOut extends AppStateNotifier {
  _SignedOut(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedOut);
  }
}

Map<String, dynamic> _event(String id, String title, {List<int> prices = const [], String? place, bool cancelled = false}) => {
      'id': id, 'title': title, 'description': 'وصف', 'host': {'id': 'SA0000002', 'nickname': 'sara'}, 'placeName': place,
      'startsAt': '2027-01-15T17:00:00Z', 'cancelled': cancelled, 'isHost': false, 'going': 4, 'myTickets': 0,
      'tiers': [for (final (i, p) in prices.indexed) {'id': '$id-t$i', 'name': 'فئة $i', 'price': p, 'capacity': 50, 'sold': 0}],
    };

Map<String, dynamic> _biz(String id, String nameAr, String category, {bool verified = false, bool active = true}) => {
      'id': id, 'name': id, 'nameAr': nameAr, 'category': category, 'sector': '', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '',
      'highlights': [], 'verified': verified, 'official': false, 'followers': 0, 'ratingCount': 0, 'items': [], 'reviews': [], 'myOrders': [], 'posts': [], 'active': active,
    };

class _Srv {
  List<Map<String, dynamic>> events;
  List<Map<String, dynamic>> biz;
  /// رمز خطأ لمسار ('/events' أو '/biz') حتى يُمسح.
  final fail = <String>{};
  final calls = <String>[];
  _Srv({this.events = const [], this.biz = const []});
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path${req.url.hasQuery ? '?${req.url.query}' : ''}');
    if (req.method != 'GET') return _json({'ok': true});
    if (fail.contains(path)) return _json({'error': 'boom'}, 500);
    if (path == '/events') return _json(events);
    if (path == '/biz') return _json(biz);
    if (path.startsWith('/events/')) return _json(events.firstWhere((e) => e['id'] == path.split('/')[2]));
    if (path.startsWith('/biz/') && path.split('/').length == 3) return _json(biz.firstWhere((b) => b['id'] == path.split('/')[2]));
    return _json([]);
  }
}

Future<_Srv> _pump(WidgetTester tester, _Srv srv, {bool signedIn = true, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      builder: (ctx, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const ExplorePage(barActions: [Icon(Icons.search, key: Key('bar-extra'))]),
    ),
  ));
  await _settle(tester);
  return srv;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

_Srv _full() => _Srv(events: [
      _event('e1', 'أمسية جاز', prices: [9000, 4500], place: 'البلد'),
      _event('e2', 'لقاء القراء'),
      _event('e3', 'حفل ملغى', prices: [1000], cancelled: true),
    ], biz: [
      _biz('cin', 'سينما البحر', 'cinema', verified: true),
      _biz('rest', 'مطعم الميناء', 'restaurant'),
      _biz('cafe', 'مقهى الصباح', 'cafe'),
      _biz('hot', 'فندق الكورنيش', 'hotel'),
      _biz('car', 'سيارات الساحل', 'car_rental'),
      _biz('sal', 'صالون لمسة', 'salon'),
      _biz('cli', 'عيادة الأسنان', 'clinic'),
      _biz('fun', 'ملاهي المرح', 'entertainment'),
      // خارج «استكشف»: براند بلا حجز، ودائرة موقوفة
      _biz('ikea', 'إيكيا', 'brand'),
      _biz('off', 'فندق مغلق', 'hotel', active: false),
    ]);

void main() {
  testWidgets('sections and chips come from the real events and circles, grouped by what they offer', (tester) async {
    final srv = await _pump(tester, _full(), size: const Size(390, 2400));
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(AppBar, 'استكشف'), findsOneWidget);
    expect(find.byKey(const Key('bar-extra')), findsOneWidget, reason: 'أفعال الغلاف تُلحق بالشريط');
    expect(srv.calls, containsAll(['GET /events', 'GET /biz']));
    for (final id in ['all', 'events', 'cinema', 'food', 'hotels', 'cars', 'appointments', 'fun']) {
      expect(find.byKey(Key('explore-chip-$id')), findsOneWidget, reason: id);
      if (id != 'all') expect(find.byKey(Key('explore-all-$id')), findsOneWidget, reason: id);
    }
    for (final l in ['الكل', 'فعاليات', 'سينما', 'مطاعم ومقاهٍ', 'فنادق', 'سيارات', 'مواعيد', 'ترفيه']) {
      expect(find.widgetWithText(ChoiceChip, l), findsOneWidget, reason: l);
    }
    // الفعاليات: العنوان والمكان وأدنى سعر أو «مجاناً»؛ الملغاة لا تظهر
    final e1 = find.byKey(const Key('explore-event-e1'));
    expect(find.descendant(of: e1, matching: find.text('أمسية جاز')), findsOneWidget);
    expect(find.descendant(of: e1, matching: find.text('البلد')), findsOneWidget);
    expect(find.descendant(of: e1, matching: find.text('من 45 ر.س')), findsOneWidget, reason: 'أدنى فئة');
    expect(find.descendant(of: e1, matching: find.textContaining('15 يناير')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('explore-event-e2')), matching: find.text('مجاناً')), findsOneWidget);
    expect(find.byKey(const Key('explore-event-e3')), findsNothing);
    // الدوائر: كل واحدة في قسمها باسمها ونوعها، والموثّقة بعلامتها
    for (final id in ['cin', 'rest', 'cafe', 'hot', 'car', 'sal', 'cli', 'fun']) {
      expect(find.byKey(Key('explore-biz-$id')), findsOneWidget, reason: id);
    }
    final cin = find.byKey(const Key('explore-biz-cin'));
    expect(find.descendant(of: cin, matching: find.text('سينما البحر')), findsOneWidget);
    expect(find.descendant(of: cin, matching: find.byIcon(Icons.verified_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('explore-biz-rest')), matching: find.text('مطعم')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('explore-biz-rest')), matching: find.byIcon(Icons.verified_rounded)), findsNothing);
    expect(find.byKey(const Key('explore-biz-ikea')), findsNothing, reason: 'فئة بلا قسم حجز');
    expect(find.byKey(const Key('explore-biz-off')), findsNothing, reason: 'دائرة موقوفة');
    expect(find.textContaining('طيران'), findsNothing);
  });

  testWidgets('a chip shows only its section as a vertical list; «الكل» on a rail selects its chip', (tester) async {
    await _pump(tester, _full(), size: const Size(900, 2400));
    await tester.tap(find.byKey(const Key('explore-chip-food')));
    await _settle(tester);
    expect(find.byType(BizRow), findsNWidgets(2));
    expect(find.byKey(const Key('explore-biz-rest')), findsOneWidget);
    expect(find.byKey(const Key('explore-biz-cafe')), findsOneWidget);
    expect(find.byKey(const Key('explore-biz-hot')), findsNothing);
    expect(find.byKey(const Key('explore-event-e1')), findsNothing);

    await tester.tap(find.byKey(const Key('explore-chip-events')));
    await _settle(tester);
    expect(find.byKey(const Key('explore-event-e1')), findsOneWidget);
    expect(find.byKey(const Key('explore-event-e2')), findsOneWidget);
    expect(find.byType(BizRow), findsNothing);

    await tester.tap(find.byKey(const Key('explore-chip-all')));
    await _settle(tester);
    expect(find.byKey(const Key('explore-biz-hot')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-all-appointments')));
    await _settle(tester);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('explore-chip-appointments'))).selected, isTrue);
    expect(find.byType(BizRow), findsNWidgets(2));
    expect(find.byKey(const Key('explore-biz-sal')), findsOneWidget);
    expect(find.byKey(const Key('explore-biz-cli')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips and sections appear only where there is data', (tester) async {
    await _pump(tester, _Srv(events: [_event('e1', 'أمسية جاز')], biz: [_biz('hot', 'فندق الكورنيش', 'hotel'), _biz('ikea', 'إيكيا', 'brand')]));
    expect(find.byKey(const Key('explore-chip-all')), findsOneWidget);
    expect(find.byKey(const Key('explore-chip-events')), findsOneWidget);
    expect(find.byKey(const Key('explore-chip-hotels')), findsOneWidget);
    for (final id in ['cinema', 'food', 'cars', 'appointments', 'fun']) {
      expect(find.byKey(Key('explore-chip-$id')), findsNothing, reason: id);
      expect(find.byKey(Key('explore-all-$id')), findsNothing, reason: id);
    }
  });

  testWidgets('tapping an event opens its detail page; «الكل» opens the events page with its create button', (tester) async {
    // عرض يتسع لبطاقة صفحة الفعاليات بخط الاختبار (كل حرف مربع)
    final srv = await _pump(tester, _full(), size: const Size(900, 1400));
    await tester.tap(find.byKey(const Key('explore-event-e1')));
    await _settle(tester);
    expect(tester.widget<EventDetailPage>(find.byType(EventDetailPage)).eventId, 'e1');
    expect(srv.calls, contains('GET /events/e1'));
    Navigator.of(tester.element(find.byType(EventDetailPage))).pop();
    await _settle(tester);

    await tester.tap(find.byKey(const Key('explore-all-events')));
    await _settle(tester);
    expect(find.byType(EventsPage), findsOneWidget);
    expect(find.byKey(const Key('events-create')).hitTestable(), findsOneWidget);
    expect(find.byType(EventCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a circle opens its public page', (tester) async {
    final srv = await _pump(tester, _full());
    await tester.tap(find.byKey(const Key('explore-biz-cin')));
    await _settle(tester);
    expect(tester.widget<BusinessPage>(find.byType(BusinessPage)).id, 'cin');
    expect(srv.calls, contains('GET /biz/cin'));
  });

  testWidgets('empty state when nothing is bookable; the create button and «تذاكري» stay', (tester) async {
    await _pump(tester, _Srv(biz: [_biz('ikea', 'إيكيا', 'brand')]));
    expect(find.byKey(const Key('explore-empty')), findsOneWidget);
    expect(find.text('لا شيء للحجز الآن'), findsOneWidget);
    expect(find.byKey(const Key('explore-chip-all')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget, reason: '«الكل» وحدها');
    expect(find.byKey(const Key('events-create')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-tickets')));
    await _settle(tester);
    expect(find.byType(MyTicketsPage), findsOneWidget);
  });

  testWidgets('both sources failing shows an error with retry; one failing keeps the other and offers retry', (tester) async {
    final srv = _full()..fail.addAll(['/events', '/biz']);
    await _pump(tester, srv);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byKey(const Key('explore-empty')), findsNothing);
    // الدوائر تعود والفعاليات ما زالت متعذّرة: يظهر ما وصل مع سطر إعادة المحاولة
    srv.fail.remove('/biz');
    await tester.tap(find.text('إعادة المحاولة'));
    await _settle(tester);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.byKey(const Key('explore-partial-error')), findsOneWidget);
    expect(find.byKey(const Key('explore-biz-cin')), findsOneWidget);
    expect(find.byKey(const Key('explore-chip-events')), findsNothing);
    srv.fail.clear();
    await tester.tap(find.text('إعادة المحاولة'));
    await _settle(tester);
    expect(find.byKey(const Key('explore-partial-error')), findsNothing);
    expect(find.byKey(const Key('explore-event-e1')), findsOneWidget);
  });

  testWidgets('pull to refresh reloads events and circles', (tester) async {
    final srv = await _pump(tester, _full());
    int n(String c) => srv.calls.where((x) => x == c).length;
    expect((n('GET /events'), n('GET /biz')), (1, 1));
    srv.events = [_event('e9', 'فعالية جديدة')];
    await tester.fling(find.byKey(const Key('explore-list')), const Offset(0, 400), 1200);
    await _settle(tester, 8);
    expect((n('GET /events'), n('GET /biz')), (2, 2));
    expect(find.byKey(const Key('explore-event-e9')), findsOneWidget);
    expect(find.byKey(const Key('explore-event-e1')), findsNothing);
  });

  testWidgets('a guest sees the sections; «تذاكري» and creating an event ask to sign in first', (tester) async {
    final srv = await _pump(tester, _full(), signedIn: false);
    expect(find.byKey(const Key('explore-event-e1')), findsOneWidget);
    expect(find.byKey(const Key('explore-biz-cin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-tickets')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.byType(MyTicketsPage), findsNothing);
    Navigator.of(tester.element(find.byKey(const Key('guest-login-sheet')))).pop();
    await _settle(tester);
    await tester.tap(find.byKey(const Key('events-create')));
    await _settle(tester);
    expect(find.byKey(const Key('guest-login-sheet')), findsOneWidget);
    expect(find.text('فعالية جديدة'), findsNothing, reason: 'لا نموذج قبل الدخول');
    expect(srv.calls.where((c) => c.contains('mine') || c.contains('/tickets')), isEmpty);
  });

  testWidgets('rails do not overflow on a 360 px phone at 1.6x text', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final srv = _full();
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
      child: MaterialApp(
        locale: const Locale('ar'),
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.6)), child: Directionality(textDirection: TextDirection.rtl, child: child!)),
        home: const ExplorePage(),
      ),
    ));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('explore-event-e1')), findsOneWidget);
  });
}
