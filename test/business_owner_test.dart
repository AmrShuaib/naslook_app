import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/my_businesses_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _biz({String role = 'owner', bool active = true, List<Map<String, dynamic>> items = const [], List<Map<String, dynamic>> posts = const [], List<Map<String, dynamic>> reviews = const []}) => {
      'id': 'biz-cafe', 'name': 'Cafe', 'nameAr': 'مقهى عمرو', 'category': 'brand', 'sector': 'مقهى', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2, 'address': 'الروضة، جدة', 'hours': '8-12',
      'color': '#0058A3', 'highlights': ['توصيل'], 'verified': false, 'official': false, 'active': active, 'ownerId': role == 'owner' ? 'SA0000001' : 'SA0000002', 'myRole': role, 'views': 7,
      'followers': 3, 'rating': 4.0, 'ratingCount': 1, 'minPrice': 1500, 'itemsCount': items.length, 'items': items, 'reviews': reviews, 'posts': posts, 'myOrders': [],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String role = 'owner';
  bool active = true;
  final items = <Map<String, dynamic>>[{'id': 'cafe-latte', 'bizId': 'biz-cafe', 'kind': 'product', 'title': 'لاتيه', 'price': 1500, 'unit': 'item', 'stock': 10, 'meta': {}, 'active': true}];
  final posts = <Map<String, dynamic>>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /biz/biz-cafe') return _json(_biz(role: role, active: active, items: items, posts: posts, reviews: [{'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'rating': 4, 'text': 'لذيذ', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'mine': false}]));
    if (key == 'GET /biz/biz-cafe/stats') {
      return _json({'orders': {'total': 5, 'confirmed': 2, 'used': 2, 'cancelled': 1, 'last7': 4, 'next24h': 1, 'customers': 3}, 'revenue': {'total': 9000, 'last7': 6000, 'last30': 9000}, 'byKind': [{'kind': 'product', 'count': 5, 'total': 9000}],
        'daily': [for (var i = 13; i >= 0; i--) {'day': DateTime.now().subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'orders': i % 3, 'revenue': (i % 3) * 1500}], 'topItems': [{'itemId': 'cafe-latte', 'title': 'لاتيه', 'count': 5, 'total': 9000}], 'followers': 3, 'rating': 4.0, 'reviews': 1, 'unanswered': 1, 'views': 7});
    }
    if (key == 'GET /biz/biz-cafe/orders') {
      return _json([{'id': 'o1', 'bizId': 'biz-cafe', 'itemId': 'cafe-latte', 'title': 'لاتيه', 'kind': 'product', 'qty': 2, 'units': 1, 'total': 3000, 'status': 'confirmed', 'code': 'NAS-AAAA1111', 'meta': {}, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'cancellable': true, 'customer': {'id': 'SA0000002', 'nickname': 'sara'}}]);
    }
    if (key == 'POST /biz/biz-cafe/checkin') return _json({'id': 'o1', 'bizId': 'biz-cafe', 'itemId': 'cafe-latte', 'title': 'لاتيه', 'kind': 'product', 'qty': 2, 'units': 1, 'total': 3000, 'status': 'used', 'code': 'NAS-AAAA1111', 'meta': {}, 'customer': {'id': 'SA0000002', 'nickname': 'sara'}});
    if (key == 'POST /biz/biz-cafe/items') { final b = bodies[key]!; items.add({'id': 'cafe-new', 'bizId': 'biz-cafe', 'kind': b['kind'], 'title': b['title'], 'price': b['price'], 'unit': 'item', 'stock': b['stock'], 'meta': b['meta'] ?? {}, 'active': true}); return _json(items.last); }
    if (key == 'PATCH /biz/biz-cafe/items/cafe-latte') { items.first.addAll(bodies[key]!); return _json(items.first); }
    if (key == 'PATCH /biz/biz-cafe') { active = bodies[key]!['active'] ?? active; return _json(_biz(role: role, active: active, items: items)); }
    if (key == 'POST /biz/biz-cafe/posts') { final b = bodies[key]!; posts.add({'id': 'p1', 'bizId': 'biz-cafe', 'kind': b['kind'], 'title': b['title'], 'body': b['body'], 'active': true, 'createdAt': DateTime.now().toUtc().toIso8601String()}); return _json(posts.last); }
    if (key == 'POST /biz/biz-cafe/reviews/SA0000002/reply') return _json({'ok': true});
    if (key == 'GET /biz/biz-cafe/team') return _json({'owner': {'id': 'SA0000001', 'nickname': 'amr'}, 'staff': [{'user': {'id': 'SA0000003', 'nickname': 'khalid'}, 'role': 'staff', 'since': DateTime.now().toUtc().toIso8601String()}]});
    if (key == 'GET /biz/mine') return _json({'circles': [_biz(role: role, active: active, items: items)], 'claims': [{'bizId': 'biz-vox', 'name': 'فوكس', 'status': 'pending', 'note': '', 'createdAt': DateTime.now().toUtc().toIso8601String()}], 'admin': false});
    if (key == 'POST /biz/biz-cafe/claim') return _json({'ok': true, 'status': 'pending'});
    if (path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('Biz role helpers and stats parsing', () {
    expect(Biz.fromJson(_biz(role: 'staff')).canOperate, isTrue);
    expect(Biz.fromJson(_biz(role: 'staff')).canManage, isFalse);
    expect(Biz.fromJson(_biz(role: 'manager')).canManage, isTrue);
    expect(Biz.fromJson(_biz(role: 'manager')).isOwner, isFalse);
    expect(Biz.fromJson(_biz(role: 'admin')).isOwner, isTrue);
    final s = BizStats.fromJson({'orders': {'total': 5, 'last7': 2}, 'revenue': {'last7': 6000}, 'daily': [{'day': '2026-09-01', 'orders': 1, 'revenue': 100}], 'topItems': [], 'byKind': [], 'rating': 4.5});
    expect(s.ordersTotal, 5);
    expect(s.revenueLast7, 6000);
    expect(s.daily.single.revenue, 100);
    expect(s.rating, 4.5);
  });

  testWidgets('my businesses lists owned circles and pending claims', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const MyBusinessesPage());
    expect(find.text('مقهى عمرو'), findsOneWidget);
    expect(find.text('منشورة'), findsOneWidget);
    expect(find.text('فوكس'), findsOneWidget);
    expect(find.text('دائرة تجارية جديدة'), findsOneWidget);
  });

  testWidgets('dashboard overview shows stats and revenue bars', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
    expect(find.text('إيرادات 7 أيام'), findsOneWidget);
    expect(find.text('60 ر.س'), findsOneWidget);
    expect(find.byType(RevenueBars), findsOneWidget);
    expect(find.text('لاتيه'), findsWidgets);
    expect(srv.calls, contains('GET /biz/biz-cafe/stats'));
  });

  testWidgets('orders tab: check-in from the order sheet posts orderId', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 1));
    expect(find.text('sara'), findsOneWidget);
    await tester.tap(find.text('sara'));
    await tester.pumpAndSettle();
    expect(find.text('NAS-AAAA1111'), findsOneWidget);
    await tester.tap(find.text('تأكيد التسليم'));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /biz/biz-cafe/checkin'));
    expect(srv.bodies['POST /biz/biz-cafe/checkin']!['orderId'], 'o1');
  });

  testWidgets('catalog tab: toggling an item posts active=false and adding posts a product', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 2));
    expect(find.text('لاتيه'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(srv.bodies['PATCH /biz/biz-cafe/items/cafe-latte']!['active'], false);
    await tester.tap(find.text('إضافة منتج'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'اسم المنتج'), 'كابتشينو');
    await tester.enterText(find.widgetWithText(TextField, 'السعر (ر.س)'), '18');
    await tester.tap(find.text('إضافة').last);
    await tester.pumpAndSettle();
    final b = srv.bodies['POST /biz/biz-cafe/items']!;
    expect(b['title'], 'كابتشينو');
    expect(b['price'], 1800);
    expect(b['kind'], 'product');
  });

  testWidgets('posts tab: publishing an offer posts kind=offer', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 3));
    await tester.tap(find.text('منشور جديد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عرض'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'العنوان'), 'خصم 20%');
    await tester.tap(find.text('نشر'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /biz/biz-cafe/posts']!['kind'], 'offer');
    expect(srv.bodies['POST /biz/biz-cafe/posts']!['title'], 'خصم 20%');
  });

  testWidgets('reviews tab: reply posts text', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 4));
    expect(find.text('لذيذ'), findsOneWidget);
    await tester.tap(find.text('رد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'شكراً');
    await tester.tap(find.text('نشر الرد'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /biz/biz-cafe/reviews/SA0000002/reply']!['text'], 'شكراً');
  });

  testWidgets('team tab lists owner and staff', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 5));
    expect(find.text('amr'), findsOneWidget);
    expect(find.text('khalid'), findsOneWidget);
    expect(find.text('نقل ملكية الدائرة'), findsOneWidget);
  });

  testWidgets('staff role cannot see manage-only controls', (tester) async {
    final srv = _Srv()..role = 'staff';
    await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 2));
    expect(find.text('إضافة منتج'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('public page shows dashboard shortcut for owner and claim button when unowned', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const BusinessPage(id: 'biz-cafe'));
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
  });
}
