import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/my_bookings_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/notifications/notifications_page.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _n1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
const _n2 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final items = <Map<String, dynamic>>[
    {'id': _n1, 'kind': 'biz_order', 'title': 'طلب جديد · إيكيا', 'body': 'sara: مكتبة BILLY × 2 بقيمة 898 ر.س', 'data': {'bizId': 'biz-ikea', 'orderId': 'x'}, 'readAt': null, 'createdAt': DateTime.now().toUtc().toIso8601String()},
    {'id': _n2, 'kind': 'transfer_in', 'title': 'وصلك تحويل', 'body': 'sara حوّل لك 25 ر.س', 'data': {'from': 'SA0000002', 'amount': 2500}, 'readAt': DateTime.now().toUtc().toIso8601String(), 'createdAt': DateTime.now().toUtc().toIso8601String()},
  ];
  int get unread => items.where((n) => n['readAt'] == null).length;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /notify':
        return _json({'items': items, 'unread': unread});
      case 'GET /notify/unread':
        return _json({'unread': unread});
      case 'POST /notify/read':
        final b = bodies[key]!;
        for (final n in items) {
          if (b['all'] == true || (b['ids'] as List?)?.contains(n['id']) == true) n['readAt'] ??= DateTime.now().toUtc().toIso8601String();
        }
        return _json({'ok': true, 'unread': unread});
      case 'GET /notify/$_n1':
        return _json(items[0]);
      case 'GET /requests':
      case 'GET /chats':
      case 'GET /vessels/feed':
      case 'GET /contacts':
        return _json([]);
      case 'GET /biz/biz-ikea':
        return _json({'id': 'biz-ikea', 'name': 'IKEA', 'nameAr': 'إيكيا', 'category': 'brand', 'lat': 21.5, 'lng': 39.2, 'items': [], 'reviews': [], 'posts': [], 'myOrders': [], 'myRole': 'owner'});
      case 'GET /biz/biz-ikea/stats':
        return _json({'orders': {}, 'revenue': {}, 'byKind': [], 'daily': [], 'topItems': [], 'social': {}});
      case 'GET /biz/biz-ikea/orders':
        return _json([]);
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
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
  await tester.pump(const Duration(milliseconds: 300));
}

AppNotification _n(String kind, [Map<String, dynamic> data = const {}]) => AppNotification(id: 'x', kind: kind, title: 't', data: data);

void main() {
  test('capturePendingNotification reads #/n/<id> only', () {
    capturePendingNotification(Uri.parse('https://naslife.app/#/n/$_n1'));
    expect(pendingNotificationId, _n1);
    capturePendingNotification(Uri.parse('https://naslife.app/#/'));
    expect(pendingNotificationId, isNull);
    capturePendingNotification(Uri.parse('https://naslife.app/#/n/not-a-uuid'));
    expect(pendingNotificationId, isNull);
  });

  test('notificationTarget maps kinds to pages', () {
    expect(notificationTarget(_n('biz_order', {'bizId': 'biz-ikea'})), isA<BusinessDashboardPage>().having((p) => p.initialTab, 'orders tab', 1));
    expect(notificationTarget(_n('biz_review', {'bizId': 'biz-ikea'})), isA<BusinessDashboardPage>().having((p) => p.initialTab, 'reviews tab', 4));
    expect(notificationTarget(_n('claim_decided', {'bizId': 'biz-vox', 'approved': false})), isA<BusinessPage>());
    expect(notificationTarget(_n('order_status', {'bizId': 'biz-vox'})), isA<MyBookingsPage>());
    expect(notificationTarget(_n('transfer_in')), isA<WalletPage>());
    expect(notificationTarget(_n('report_new')), isA<AdminShell>().having((a) => a.initialSection, 'reports section', 2));
    expect(notificationTarget(_n('biz_order')), isNull, reason: 'بلا معرّف دائرة لا وجهة');
    expect(notificationTarget(_n('account_warning')), isNull);
  });

  testWidgets('notifications page lists items, marks all read', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const NotificationsPage());
    expect(find.text('طلب جديد · إيكيا'), findsOneWidget);
    expect(find.text('وصلك تحويل'), findsOneWidget);
    expect(find.text('تعليم الكل كمقروء'), findsOneWidget);
    await tester.tap(find.text('تعليم الكل كمقروء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(srv.bodies['POST /notify/read']!['all'], isTrue);
    expect(find.text('تعليم الكل كمقروء'), findsNothing);
  });

  testWidgets('tapping an order notification marks it read and opens the dashboard orders tab', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const NotificationsPage());
    await tester.tap(find.text('طلب جديد · إيكيا'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(srv.bodies['POST /notify/read']!['ids'], [_n1]);
    expect(find.byType(BusinessDashboardPage), findsOneWidget);
    expect((tester.widget(find.byType(BusinessDashboardPage)) as BusinessDashboardPage).initialTab, 1);
  });

  testWidgets('unread provider polls once without a timer in tests', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, Consumer(builder: (_, ref, __) => Text('${ref.watch(notifyUnreadProvider).valueOrNull ?? -1}', textDirection: TextDirection.ltr)));
    expect(find.text('1'), findsOneWidget);
    expect(srv.calls.where((c) => c == 'GET /notify/unread').length, 1);
  });
}
