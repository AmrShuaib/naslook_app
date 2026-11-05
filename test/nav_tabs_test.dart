// الشريط السفلي بستة أقسام (قرار المالك): الخريطة، الدوائر، السوق | الكاميرا | الفعاليات، المحادثات، ماي سبيس.
// يتسع لجوال 360 و390 بخط التطبيق الحقيقي (Rubik) وتكبير النص 1.25 و1.6 بلا قصّ ولا فيض، كل قسم قابل للمس والكاميرا
// في المنتصف تماماً؛ الأقسام تُبنى عند أول زيارة (لا طلبات للسوق والفعاليات عند الإقلاع، والشارات حيّة)، السوق والفعاليات
// بشريط علوي واحد فيه أفعالهما مع البحث والجرس وزرهما العائم فوق الكبسولة، صفحة تُفتح فوق الأقسام بلا تعارض Hero،
// اختصارات «اللحظات» الفارغة تبدّل القسم (والزائر تُفتح له الصفحة)، السوق ظاهر في iOS، و«المشتريات» تفتح الطلبات.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/app_theme.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/nav_provider.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/pages/posts/timeline_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/joy_nav_bar.dart';

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

const _labels = {'home': 'الخريطة', 'circles': 'الدوائر', 'market': 'السوق', 'events': 'الفعاليات', 'chats': 'المحادثات', 'me': 'ماي سبيس'};

var _fontLoaded = false;

/// خط التطبيق الحقيقي: خط الاختبار الافتراضي يرسم كل حرف مربعاً فلا يقيس اتساع الأسماء العربية كما على الجوال.
Future<void> _loadAppFont() async {
  if (_fontLoaded) return;
  final l = FontLoader(AppTheme.bodyFont);
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Rubik-$f.ttf').readAsBytesSync();
    l.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await l.load();
  _fontLoaded = true;
}

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /legal/consent':
        return _json({'needs': false});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'GET /settings/public':
        return _json({'announcement': '', 'maintenance': false});
      case 'GET /row':
        return _json({'items': [], 'located': false});
      case 'GET /feed':
        return _json({'items': [], 'next': null, 'located': false});
      case 'GET /live/wait':
        return _json({'seq': 0, 'events': [], 'reset': false});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /market/home':
        return _json({'spotlight': [], 'popular': [], 'nearby': [], 'bazaars': [], 'categories': {}, 'wantedOpen': 0, 'spotlightPricePerDay': 2000, 'commissionPct': 5});
      case 'GET /wallet':
        return _json({'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': false, 'recent': []});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

/// [appTheme]: ثيم التطبيق بخطه الحقيقي (بعد [_loadAppFont]) لقياس الصفحات على عرض جوال فعلي.
Future<(_Srv, ProviderContainer)> _pump(WidgetTester tester, {Widget home = const AuthGate(), bool signedIn = true, Size size = const Size(390, 844), bool appTheme = false}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.5433, 39.1728);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      theme: appTheme ? AppTheme.light : null,
      locale: const Locale('ar'),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(appTheme ? 1.25 : 1)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: home,
    ),
  ));
  await _settle(tester);
  return (s, ProviderScope.containerOf(tester.element(find.byType(MaterialApp))));
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tab(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('nav-$id')));
  await _settle(tester);
}

/// شريط علوي ظاهر واحد بالعنوان المعطى (لا شريطان متراكبان).
void _oneBar(WidgetTester tester, String title) {
  expect(find.byType(AppBar), findsOneWidget);
  expect(find.descendant(of: find.byType(AppBar), matching: find.text(title)), findsOneWidget);
  expect(find.byKey(const Key('shell-search')).hitTestable(), findsOneWidget);
  expect(find.byKey(const Key('shell-bell')).hitTestable(), findsOneWidget);
}

void main() {
  tearDown(() => iosNativeOverride = null);

  testWidgets('six tabs fit 360 and 390 px phones at 1.25x and 1.6x text: full labels, all tappable, camera centred', (tester) async {
    await _loadAppFont();
    addTearDown(tester.view.reset);
    expect(navTabIds, ['home', 'circles', 'market', 'events', 'chats', 'me']);
    for (final width in [360.0, 390.0]) {
      for (final scale in [1.25, 1.6]) {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        int? picked;
        var composed = 0;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ar'),
          // كما في MainApp: النصوص مكبّرة 25% وسقف التكبير 1.6
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: TextDirection.rtl, child: child!)),
          home: Scaffold(bottomNavigationBar: JoyNavBar(tabs: navTabIds, index: 0, onSelect: (i) => picked = i, onCompose: () => composed++, badges: const {'chats': 3})),
        ));
        await tester.pump();
        final why = '$width px, ${scale}x';
        expect(tester.takeException(), isNull, reason: why);
        expect(tester.getCenter(find.byKey(const Key('nav-compose'))).dx, closeTo(width / 2, 0.5), reason: 'الكاميرا في المنتصف · $why');
        Rect? prev;
        for (final (i, id) in navTabIds.indexed) {
          final item = find.byKey(Key('nav-$id'));
          expect(item.hitTestable(), findsOneWidget, reason: '$id · $why');
          final label = find.descendant(of: item, matching: find.text(_labels[id]!));
          final p = tester.renderObject<RenderParagraph>(label);
          expect(p.didExceedMaxLines, isFalse, reason: '$id · $why');
          // الاسم كاملاً داخل قسمه بعد أي تصغير، وبحجم مقروء
          final box = tester.getRect(item), text = tester.getRect(label);
          expect(text.left, greaterThanOrEqualTo(box.left - 0.5), reason: '$id · $why');
          expect(text.right, lessThanOrEqualTo(box.right + 0.5), reason: '$id · $why');
          final shown = tester.widget<Text>(label).style!.fontSize! * scale * (text.width / p.size.width);
          expect(shown, greaterThanOrEqualTo(9), reason: 'خط $id ${shown.toStringAsFixed(1)} · $why');
          // الأقسام لا تتداخل (اتجاه من اليمين إلى اليسار: كل قسم يسار سابقه)
          if (prev != null) expect(box.right, lessThanOrEqualTo(prev.left + 0.5), reason: '$id · $why');
          prev = box;
          await tester.tap(item);
          expect(picked, i, reason: '$id · $why');
        }
        await tester.tap(find.byKey(const Key('nav-compose')));
        expect(composed, 1);
        expect(find.text('3'), findsOneWidget, reason: 'شارة المحادثات');
      }
    }
  });

  testWidgets('tabs are built on first visit; market and events get one bar with search and bell and a FAB above the capsule', (tester) async {
    await _loadAppFont();
    final (srv, _) = await _pump(tester, appTheme: true, size: const Size(360, 844));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(MapPage), findsOneWidget);
    for (final t in [MarketPage, EventsPage, ChatsPage, MySpacePage]) {
      expect(find.byType(t, skipOffstage: false), findsNothing, reason: '$t لم يُزر بعد');
    }
    // (طبقة السوق على الخريطة تطلب GET /market بنفسها؛ صفحة السوق تبدأ بـ /market/home)
    expect(srv.calls.where((c) => c == 'GET /market/home' || c == 'GET /events'), isEmpty, reason: 'لا طلبات لصفحتي السوق والفعاليات عند الإقلاع');
    // شارة المحادثات وجرس التنبيهات حيّان قبل زيارة المحادثات
    expect(srv.calls, contains('GET /chats'));
    expect(srv.calls, contains('GET /notify/unread'));

    await _tab(tester, 'market');
    expect(find.byType(MarketPage), findsOneWidget);
    expect(srv.calls, contains('GET /market/home'));
    _oneBar(tester, 'السوق');
    expect(find.byKey(const Key('market-wanted')).hitTestable(), findsOneWidget);
    // الزر العائم فوق الكبسولة بفراغه المعتاد (16)، لا خلفها ولا مرتفعاً بحافة الجهاز مرة ثانية
    final capsuleTop = 844 - JoyNavBar.inset(tester.element(find.byType(HomeShell)));
    expect(tester.getRect(find.byKey(const Key('market-sell'))).bottom, closeTo(capsuleTop - 16, 1));

    await _tab(tester, 'events');
    expect(find.byType(EventsPage), findsOneWidget);
    expect(srv.calls, contains('GET /events'));
    _oneBar(tester, 'الفعاليات');
    expect(find.byKey(const Key('events-tickets')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('events-create')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('market-sell')).hitTestable(), findsNothing, reason: 'زر السوق المخفي لا يُلمس');
    expect(tester.getRect(find.byKey(const Key('events-create'))).bottom, closeTo(capsuleTop - 16, 1));

    // صفحة تُفتح فوق الأقسام وفيها أزرار عائمة مبنية (السوق والفعاليات والمحادثات): لا تعارض Hero
    await _tab(tester, 'chats');
    expect(find.byType(ChatsPage), findsOneWidget);
    _oneBar(tester, 'المحادثات');
    await _tab(tester, 'events');
    await tester.tap(find.byKey(const Key('events-tickets')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(EventsPage), findsNothing, reason: 'صفحة التذاكر فوقها');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await _settle(tester);
    expect(tester.takeException(), isNull);

    // العودة إلى السوق: الصفحة نفسها بحالتها (لا تُبنى من جديد ولا تعيد الطلب)
    final homes = srv.calls.where((c) => c == 'GET /market/home').length;
    await _tab(tester, 'market');
    expect(find.byType(MarketPage), findsOneWidget);
    expect(srv.calls.where((c) => c == 'GET /market/home').length, homes);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«اللحظات» empty shortcuts return to the bar and switch to the market or events tab', (tester) async {
    final (_, c) = await _pump(tester, size: const Size(900, 1400));
    for (final (kind, key, tab) in [('listing', 'tl-go-listing', 'market'), ('event', 'tl-go-event', 'events')]) {
      Navigator.of(tester.element(find.byType(HomeShell))).push(MaterialPageRoute(builder: (_) => const TimelinePage()));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(Key('feed-kind-$kind')));
      await tester.pump();
      await tester.tap(find.byKey(Key('feed-kind-$kind')));
      await _settle(tester);
      await tester.tap(find.byKey(Key(key)));
      await _settle(tester);
      expect(find.byType(TimelinePage), findsNothing, reason: kind);
      expect(c.read(navIndexProvider), navTabIds.indexOf(tab), reason: kind);
      expect(find.byType(tab == 'market' ? MarketPage : EventsPage), findsOneWidget, reason: 'القسم نفسه لا صفحة ثانية فوقه');
      expect(find.byType(HomeShell).hitTestable(), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a guest on «اللحظات» gets the market page pushed (guest tabs do not follow the signed-in bar)', (tester) async {
    final (_, c) = await _pump(tester, signedIn: false, size: const Size(900, 1400), home: const TimelinePage());
    await tester.ensureVisible(find.byKey(const Key('feed-kind-listing')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('feed-kind-listing')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('tl-go-listing')));
    await _settle(tester);
    expect(find.byType(MarketPage), findsOneWidget);
    expect(c.read(navIndexProvider), 0, reason: 'لا يتغير قسم الحساب للزائر');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on iOS native the market tab stays (no spotlight pitch) and «المشتريات» opens the orders tab', (tester) async {
    iosNativeOverride = true;
    // عرض يتسع لسطور ماي سبيس بخط الاختبار (كل حرف مربع)
    final (srv, _) = await _pump(tester, size: const Size(900, 1400));
    await _tab(tester, 'market');
    expect(find.byType(MarketPage), findsOneWidget);
    expect(find.byKey(const Key('market-sell')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('spotlight-info')), findsNothing, reason: 'سبوت لايت لا يُعرض للبيع في iOS');

    await _tab(tester, 'me');
    expect(srv.calls, contains('GET /wallet'));
    final orders = find.byKey(const Key('wallet-orders'));
    await tester.ensureVisible(orders);
    await tester.pump();
    await tester.tap(orders);
    await _settle(tester);
    final tabs = DefaultTabController.of(tester.element(find.byType(TabBarView)));
    expect(tabs.index, 1, reason: 'تبويب «الطلبات» لا «عروضي»');
    await tester.pumpWidget(const SizedBox());
  });
}
