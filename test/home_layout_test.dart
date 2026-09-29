// تخصيص الرئيسية: نموذج الترتيب، قائمة القسم (إخفاء/نقل) وصندوق «أقسام مخفية» في الرئيسية، شاشة التخصيص بمفاتيحها
// واختيار أقسام شريط التنقّل، والمزامنة مع /me/layout، وشريط الكبسولة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:latlong2/latlong.dart';
import 'package:naslook/core/home_layout.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/pages/home/home_layout_page.dart';
import 'package:naslook/pages/home/home_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/layout_providers.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/joy_nav_bar.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  Map<String, dynamic>? stored;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /me/layout':
        return _json({'layout': stored, 'defaults': {'order': homeDefaultOrder, 'nav': navDefault}, 'pinned': ['announce'], 'updatedAt': null});
      case 'PUT /me/layout':
        stored = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'ok': true, 'layout': stored});
      case 'DELETE /me/layout':
        stored = null;
        return _json({'ok': true});
      case 'GET /mapposts/trending':
        return _json({'hours': 24, 'places': [{'key': 'biz:biz-cafe', 'name': 'مقهى البث', 'bizId': 'biz-cafe', 'category': 'cafe', 'lat': 21.55, 'lng': 39.16, 'distanceKm': 0.3, 'posts': 4, 'authors': 3}]});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': 'تحديث الليلة', 'maintenance': false, 'jobsEnabled': true});
      case 'GET /offers/near':
        return _json({'items': [{'id': 'off-1', 'bizId': 'biz-cafe', 'bizName': 'أوفردوز', 'category': 'cafe', 'lat': 21.58, 'lng': 39.16, 'kind': 'deal', 'title': 'خصم ٢٠٪ على اللاتيه', 'endsAt': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(), 'distanceKm': 0.7}], 'located': true});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<(_Srv, ProviderContainer)> _pump(WidgetTester tester, Widget home, {double height = 1400}) async {
  SharedPreferences.setMockInitialValues({});
  // بلا مؤقّت تحديد الموقع في الاختبار
  DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return MaterialApp(locale: const Locale('ar'), home: home);
    }),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return (srv, container);
}

double _top(WidgetTester t, String key) => t.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  group('HomeLayout model', () {
    test('normalizes unknown ids, appends missing blocks, keeps pinned first and nav anchored', () {
      final l = HomeLayout.normalized(order: ['market', 'zzz', 'quick', 'market'], hidden: ['announce', 'feed', 'nope'], nav: ['chats', 'home', 'jobs', 'market', 'me']);
      expect(l.order.first, 'announce', reason: 'المثبّت أول القائمة');
      expect(l.order.sublist(1, 3), ['market', 'quick']);
      expect(l.order.toSet().length, homeBlocks.length, reason: 'كل الأقسام مرة واحدة');
      expect(l.hidden, ['feed'], reason: 'المثبّت لا يُخفى والمجهول يُحذف');
      expect(l.nav, ['home', 'chats', 'jobs', 'me'], reason: 'قسمان في الوسط فقط');
      expect(l.visible, isNot(contains('feed')));
    });

    test('move, toTop, hide/show, toggleOpt, reset and isDefault', () {
      var l = HomeLayout.defaults;
      expect(l.isDefault, isTrue);
      l = l.move('around', -1);
      expect(l.visible.indexOf('around'), 1, reason: 'فوق الاختصارات مباشرة بعد المثبّت');
      expect(l.move('announce', 1).order, l.order, reason: 'المثبّت لا يتحرك');
      l = l.toTop('events');
      expect(l.order[1], 'events');
      l = l.hide('events');
      expect(l.visible, isNot(contains('events')));
      expect(l.hide('announce').hidden, l.hidden);
      l = l.show('events');
      expect(l.isHidden('events'), isFalse);
      l = l.toggleOpt('feed', 'text');
      expect(l.opts['feed'], ['text']);
      expect(l.toggleOpt('feed', 'text').opts['feed'], isEmpty);
      expect(l.withNav(['market', 'jobs', 'events']).nav, ['home', 'market', 'jobs', 'me']);
      expect(l.reset().isDefault, isTrue);
      final back = HomeLayout.fromJson(l.toJson());
      expect(back.order, l.order);
      expect(back.opts, l.opts);
    });
  });

  testWidgets('home renders the sections in order; the section menu hides one into the tray, restores it and moves another up; changes sync to /me/layout', (tester) async {
    final (srv, container) = await _pump(tester, const Scaffold(body: HomePage()));
    expect(srv.calls, contains('GET /me/layout'));
    expect(find.text('تحديث الليلة'), findsOneWidget, reason: 'إعلان المنصة مثبّت أول الصفحة');
    expect(find.byKey(const Key('block-menu-announce')), findsNothing, reason: 'المثبّت بلا قائمة');
    expect(find.byKey(const Key('block-quick')), findsOneWidget);
    expect(find.byKey(const Key('quick-السوق')), findsOneWidget);
    expect(_top(tester, 'block-quick') < _top(tester, 'block-around'), isTrue);
    expect(find.byKey(const Key('hidden-tray')), findsNothing);

    await tester.tap(find.byKey(const Key('block-menu-quick')));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(const Key('block-up'))).enabled, isFalse, reason: 'أول قسم بعد المثبّت لا يرتفع');
    await tester.tap(find.byKey(const Key('block-hide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-quick')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('hidden-tray')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('أقسام مخفية (1)'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(srv.calls, contains('PUT /me/layout'));
    expect(srv.stored!['hidden'], ['quick']);

    await tester.tap(find.byKey(const Key('show-quick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hidden-tray')), findsNothing);
    expect(container.read(homeLayoutProvider).hidden, isEmpty);

    await tester.scrollUntilVisible(find.byKey(const Key('block-menu-around')), -300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('block-menu-around')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('block-menu-around')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-up')));
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).visible.sublist(0, 3), ['announce', 'around', 'quick']);
    expect(_top(tester, 'block-around') < _top(tester, 'block-quick'), isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    expect((srv.stored!['order'] as List).sublist(0, 3), ['announce', 'around', 'quick']);
  });

  testWidgets('offers block lists nearby offers', (tester) async {
    await _pump(tester, const Scaffold(body: HomePage()), height: 2400);
    expect(find.text('عروض اليوم'), findsOneWidget);
    expect(find.byKey(const Key('home-offer-off-1')), findsOneWidget);
    expect(find.text('خصم ٢٠٪ على اللاتيه'), findsOneWidget);
  });

  testWidgets('the in-place edit list hides a section, keeps pinned locked and reports done', (tester) async {
    var done = 0;
    final (_, container) = await _pump(tester, Scaffold(body: HomeEditList(onDone: () => done++)));
    expect(find.byKey(const Key('home-edit-list')), findsOneWidget);
    expect(find.byKey(const Key('home-edit-drag-quick')), findsOneWidget);
    expect(find.byKey(const Key('home-edit-drag-announce')), findsNothing, reason: 'المثبّت بلا مقبض');
    expect(find.byKey(const Key('home-edit-hide-announce')), findsNothing);
    await tester.tap(find.byKey(const Key('home-edit-hide-quick')));
    await tester.pump();
    expect(container.read(homeLayoutProvider).isHidden('quick'), isTrue);
    expect(find.byKey(const Key('home-edit-drag-quick')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('show-quick')), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('show-quick')));
    await tester.pump();
    expect(container.read(homeLayoutProvider).isHidden('quick'), isFalse);
    await tester.scrollUntilVisible(find.byKey(const Key('home-edit-done')), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('home-edit-done')));
    expect(done, 1);
  });

  testWidgets('a stored server layout wins over the device and new blocks are flagged', (tester) async {
    SharedPreferences.setMockInitialValues({HomeLayoutNotifier.prefKey: jsonEncode(HomeLayout.defaults.hide('feed').toJson())});
    final srv = _Srv()..stored = {'order': ['announce', 'market', 'quick'], 'hidden': ['around'], 'nav': ['home', 'jobs', 'chats', 'me'], 'opts': {}};
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))]);
    addTearDown(container.dispose);
    container.read(homeLayoutProvider);
    await tester.pump(const Duration(milliseconds: 300));
    final l = container.read(homeLayoutProvider);
    expect(l.hidden, ['around'], reason: 'تخصيص الحساب يتقدّم على الجهاز');
    expect(l.order.sublist(0, 3), ['announce', 'market', 'quick']);
    expect(l.nav, ['home', 'jobs', 'chats', 'me']);
    expect(l.isFresh('events'), isTrue, reason: 'قسم لم يكن في الترتيب المحفوظ');
    expect(l.isFresh('quick'), isFalse);
  });

  testWidgets('customization page: switches hide sections, drag handle exists, options open, nav picker limits to two, reset restores', (tester) async {
    final (srv, container) = await _pump(tester, const HomeLayoutPage());
    expect(find.byKey(const Key('layout-row-quick')), findsOneWidget);
    expect(find.byKey(const Key('layout-drag-quick')), findsOneWidget);
    expect(find.byKey(const Key('layout-drag-announce')), findsNothing, reason: 'المثبّت بلا مقبض');
    expect(tester.widget<Switch>(find.byKey(const Key('layout-switch-announce'))).onChanged, isNull);
    await tester.tap(find.byKey(const Key('layout-switch-market')));
    await tester.pump();
    expect(container.read(homeLayoutProvider).isHidden('market'), isTrue);
    expect(find.textContaining('1 مخفية'), findsOneWidget);
    await tester.tap(find.byKey(const Key('layout-row-feed')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('layout-opt-feed-text')));
    await tester.pump();
    expect(container.read(homeLayoutProvider).opts['feed'], ['text']);

    await tester.tap(find.text('شريط التنقّل'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-count')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('nav-switch-market'))).onChanged, isNull, reason: 'الشريط ممتلئ');
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('nav-switch-home'))).onChanged, isNull, reason: 'ثابت');
    await tester.tap(find.byKey(const Key('nav-switch-circles')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('nav-switch-market')));
    await tester.pump();
    expect(container.read(homeLayoutProvider).nav, ['home', 'chats', 'market', 'me']);
    await tester.pump(const Duration(milliseconds: 700));
    expect(srv.stored!['nav'], ['home', 'chats', 'market', 'me']);

    await tester.tap(find.byKey(const Key('layout-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout-reset-confirm')));
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).isDefault, isTrue);
    expect(srv.calls, contains('DELETE /me/layout'));
  });

  testWidgets('pill nav shows the chosen tabs with the camera in the middle, badges and taps', (tester) async {
    int? picked;
    var composed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: JoyNavBar(tabs: const ['home', 'circles', 'chats', 'me'], index: 0, onSelect: (i) => picked = i, onCompose: () => composed++, badges: const {'chats': 3}))));
    expect(find.text('الخريطة'), findsOneWidget);
    expect(find.text('ماي سبيس'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('nav-compose'))).dx, closeTo(400, 30), reason: 'الكاميرا في المنتصف');
    await tester.tap(find.byKey(const Key('nav-chats')));
    expect(picked, 2);
    await tester.tap(find.byKey(const Key('nav-compose')));
    expect(composed, 1);
    expect(HomeShell.pageOf('home'), isA<MapPage>().having((m) => m.home, 'home', isTrue));
    expect(HomeShell.ownBar('market'), isTrue);
    expect(HomeShell.ownBar('chats'), isFalse);
  });
}
