// الشاشات الفارغة المفيدة (docs/empty-states.md): الودجة المشتركة EmptyState (زر واحد، لون النوع، النسخة المدمجة،
// بلا طفح عند 320 بكسل وتكبير 1.6) ثم صفحات تمثيلية بخادم يعيد قوائم فارغة: العنوان والزر يظهران والزر ينقل.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/app_theme.dart';
import 'package:naslook/core/nav_provider.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/pages/chat/chats_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/market/wanted_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/widgets.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// خادم بلا بيانات: كل قراءة قائمة فارغة.
Future<http.Response> _emptyServer(http.Request req) async =>
    http.Response(jsonEncode(req.method == 'GET' ? [] : {'ok': true}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

late ProviderContainer _container;

Future<void> _pumpPage(WidgetTester tester, Widget home) async {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_emptyServer));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      _container = ProviderScope.containerOf(context, listen: false);
      return home;
    })),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpWidget(WidgetTester tester, Widget child, {Size size = const Size(400, 800), double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)), child: Scaffold(body: child)),
  ));
  await tester.pump();
}

void main() {
  group('EmptyState', () {
    testWidgets('the old constructor still works: icon, title, subtitle and a ready action widget', (tester) async {
      var taps = 0;
      await _pumpWidget(tester, EmptyState(icon: Icons.inbox_outlined, title: 'لا شيء', subtitle: 'شرح', action: OutlinedButton(onPressed: () => taps++, child: const Text('افعل'))));
      expect(find.text('لا شيء'), findsOneWidget);
      expect(find.text('شرح'), findsOneWidget);
      await tester.tap(find.text('افعل'));
      expect(taps, 1);
    });

    testWidgets('actionLabel + onAction build one keyed button that fires', (tester) async {
      var taps = 0;
      await _pumpWidget(tester, EmptyState(icon: Icons.inbox_outlined, title: 'فارغ', actionKey: const Key('empty-x-action'), actionLabel: 'ابدأ', actionIcon: Icons.add_rounded, onAction: () => taps++));
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-x-action')));
      expect(taps, 1);
    });

    testWidgets('no button without a label or without a callback', (tester) async {
      await _pumpWidget(tester, Column(children: [
        EmptyState(icon: Icons.inbox_outlined, title: 'أ', onAction: () {}),
        const EmptyState(icon: Icons.inbox_outlined, title: 'ب', actionLabel: 'زر'),
      ]));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('زر'), findsNothing);
    });

    testWidgets('tint colours the icon and the button; the default stays brand blue', (tester) async {
      final green = Joy.kindColor('market');
      await _pumpWidget(tester, Column(children: [
        EmptyState(icon: Icons.storefront_outlined, title: 'سوق', tint: green, actionKey: const Key('a'), actionLabel: 'بع', onAction: () {}),
        const EmptyState(icon: Icons.photo_camera_outlined, title: 'لحظات'),
      ]));
      expect(tester.widget<Icon>(find.byIcon(Icons.storefront_outlined)).color, green);
      expect(tester.widget<Icon>(find.byIcon(Icons.photo_camera_outlined)).color, Joy.primary);
      final style = tester.widget<FilledButton>(find.byKey(const Key('a'))).style!;
      expect(style.backgroundColor!.resolve({}), green);
    });

    testWidgets('a light tint (offers yellow) gets dark button text', (tester) async {
      await _pumpWidget(tester, EmptyState(icon: Icons.local_offer_outlined, title: 'عروض', tint: Joy.kindColor('offer'), actionKey: const Key('a'), actionLabel: 'عرض', onAction: () {}));
      expect(tester.widget<FilledButton>(find.byKey(const Key('a'))).style!.foregroundColor!.resolve({}), Joy.text);
    });

    testWidgets('compact is smaller than the full variant', (tester) async {
      await _pumpWidget(tester, const Column(children: [
        EmptyState(key: Key('full'), icon: Icons.inbox_outlined, title: 'كامل', subtitle: 'شرح'),
        EmptyState(key: Key('compact'), compact: true, icon: Icons.inbox_outlined, title: 'مدمج', subtitle: 'شرح'),
      ]));
      expect(tester.getSize(find.byKey(const Key('compact'))).height, lessThan(tester.getSize(find.byKey(const Key('full'))).height));
    });

    testWidgets('no overflow at 320 wide with text scale 1.6, even in a short box', (tester) async {
      await _pumpWidget(
        tester,
        SizedBox(
          height: 220,
          child: EmptyState(
            icon: Icons.storefront_outlined,
            title: 'لم تعرض شيئاً للبيع بعد في هذا السوق الطويل الاسم',
            subtitle: 'هنا عروضك مع مشاهداتها وطلباتها. أضف صوراً ووصفاً وسعراً ويراه من حولك في كل مكان قريب منك.',
            actionKey: const Key('a'), actionLabel: 'اعرض للبيع الآن من هنا مباشرة', actionIcon: Icons.add_rounded, onAction: () {},
          ),
        ),
        size: const Size(320, 568), scale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('a')), findsOneWidget);
    });

    testWidgets('ErrorState still shows the message and retries', (tester) async {
      var retries = 0;
      await _pumpWidget(tester, ErrorState(ApiException(500, 'انقطع الاتصال'), onRetry: () => retries++));
      expect(find.text('تعذر جلب البيانات'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retries, 1);
    });
  });

  group('empty pages', () {
    testWidgets('chats: «لا محادثات بعد» and «ابدأ محادثة» opens the new-chat dialog', (tester) async {
      await _pumpPage(tester, const Scaffold(body: ChatsPage()));
      expect(find.text('لا محادثات بعد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-chats-action')));
      await tester.pumpAndSettle();
      expect(find.text('محادثة جديدة'), findsOneWidget);
    });

    testWidgets('my tickets: «تصفّح الفعاليات» opens the events page, whose empty state offers «أنشئ فعالية»', (tester) async {
      await _pumpPage(tester, const MyTicketsPage());
      expect(find.text('لا تذاكر بعد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-tickets-action')));
      await tester.pumpAndSettle();
      expect(find.byType(EventsPage), findsOneWidget);
      expect(find.text('لا فعاليات قادمة'), findsOneWidget);
      expect(find.byKey(const Key('empty-events-action')), findsOneWidget);
    });

    testWidgets('market orders: «تصفّح السوق» switches the shell to the market tab', (tester) async {
      await _pumpPage(tester, const OrdersPage());
      expect(find.text('لا طلبات بعد'), findsOneWidget);
      expect(_container.read(navIndexProvider), 0);
      await tester.tap(find.byKey(const Key('empty-orders-action')));
      await tester.pumpAndSettle();
      expect(_container.read(navIndexProvider), navTabIds.indexOf('market'));
    });

    testWidgets('my listings: the empty tab explains and offers «اعرض للبيع»', (tester) async {
      await _pumpPage(tester, const OrdersPage(initialTab: 0));
      expect(find.text('لم تعرض شيئاً للبيع بعد'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'اعرض للبيع'), findsOneWidget);
      expect(find.byKey(const Key('empty-listings-action')), findsOneWidget);
    });

    testWidgets('wanted: the empty list button opens the «ماذا تبحث عنه؟» form', (tester) async {
      await _pumpPage(tester, const WantedPage());
      expect(find.text('لا طلبات مفتوحة حالياً'), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-wanted-action')));
      await tester.pumpAndSettle();
      expect(find.text('ماذا تبحث عنه؟'), findsOneWidget);
    });

    testWidgets('my bookings: «استكشف ما يُحجز» switches to the explore tab', (tester) async {
      await _pumpPage(tester, const MyBookingsPage());
      expect(find.text('لا حجوزات بعد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-bookings-action')));
      await tester.pumpAndSettle();
      expect(_container.read(navIndexProvider), navTabIds.indexOf('events'));
    });
  });
}
