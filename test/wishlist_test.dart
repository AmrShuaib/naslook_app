// قائمة الأمنيات: الصفحة (تصفية، تحقّقت، حذف، أمنية حرة) وزر القلب في صفحة عرض السوق.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/myspace/wishlist_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _listingId = 'bbbbbbbb-0000-4000-8000-000000000001';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final items = <Map<String, dynamic>>[
    {'id': 'w1', 'kind': 'market', 'refId': 'bbbbbbbb-0000-4000-8000-000000000002', 'title': 'قهوة مختصة', 'subtitle': 'منتج في السوق', 'price': 4500, 'imageUrl': null, 'note': '', 'done': false, 'available': true},
    {'id': 'w2', 'kind': 'event', 'refId': 'cccccccc-0000-4000-8000-000000000001', 'title': 'أمسية شعرية', 'subtitle': 'فعالية · الكورنيش', 'price': 2500, 'note': 'مع خالد', 'done': false, 'available': false},
    {'id': 'w3', 'kind': 'custom', 'refId': null, 'title': 'دراجة كهربائية', 'subtitle': '', 'price': 250000, 'note': '', 'done': true, 'available': true},
  ];
  int seq = 10;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /wishlist') return _json(items);
    if (key == 'POST /wishlist') {
      final b = bodies[key]!;
      final w = {'id': 'w${++seq}', 'kind': b['kind'], 'refId': b['refId'], 'title': b['title'] ?? 'عنصر ${b['refId']}', 'subtitle': '', 'price': b['price'], 'note': b['note'] ?? '', 'done': false, 'available': true};
      items.insert(0, w);
      return _json(w);
    }
    final m = RegExp(r'^(PATCH|DELETE) /wishlist/(w\d+)$').firstMatch(key);
    if (m != null) {
      final i = items.indexWhere((x) => x['id'] == m.group(2));
      if (i < 0) return _json({'error': 'not-found'}, 404);
      if (m.group(1) == 'DELETE') {
        items.removeAt(i);
        return _json({'ok': true});
      }
      items[i] = {...items[i], ...bodies[key]!};
      return _json(items[i]);
    }
    if (key == 'GET /market/$_listingId') {
      return _json({'id': _listingId, 'seller': {'id': 'SA0000002', 'nickname': 'sara'}, 'kind': 'product', 'category': 'food', 'title': 'عسل سدر', 'description': 'طبيعي', 'price': 12000, 'status': 'active', 'mine': false});
    }
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
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
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('wishlist page lists items with filters, badges, price and note; marks done and deletes', (tester) async {
    final srv = await _pump(tester, const WishlistPage());
    expect(find.text('قهوة مختصة'), findsOneWidget);
    expect(find.text('أمسية شعرية'), findsOneWidget);
    expect(find.text('دراجة كهربائية'), findsOneWidget);
    expect(find.text('غير متاح حالياً'), findsOneWidget);
    expect(find.text('تحقّقت ✓'), findsOneWidget);
    expect(find.text('📝 مع خالد'), findsOneWidget);
    expect(find.textContaining('45'), findsWidgets);
    expect(find.text('الكل · 3'), findsOneWidget);
    // تصفية الفعاليات
    await tester.ensureVisible(find.text('فعاليات · 1'));
    await tester.tap(find.text('فعاليات · 1'));
    await _settle(tester);
    expect(find.text('قهوة مختصة'), findsNothing);
    expect(find.text('أمسية شعرية'), findsOneWidget);
    await tester.ensureVisible(find.text('الكل · 3'));
    await tester.tap(find.text('الكل · 3'));
    await _settle(tester);
    expect(find.text('قهوة مختصة'), findsOneWidget);
    // القائمة: تحقّقت
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await _settle(tester);
    await tester.tap(find.text('تحقّقت ✓').last);
    await _settle(tester);
    expect(srv.bodies['PATCH /wishlist/w1']?['done'], true);
    // القائمة: حذف
    await tester.tap(find.byIcon(Icons.more_vert_rounded).at(1));
    await _settle(tester);
    await tester.tap(find.text('حذف'));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /wishlist/w2'));
    expect(find.text('أمسية شعرية'), findsNothing);
  });

  testWidgets('a custom wish is added from the FAB with title, note and price in halalas', (tester) async {
    final srv = await _pump(tester, const WishlistPage());
    await tester.tap(find.text('أمنية جديدة'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'ماذا تتمنى؟'), 'رحلة إلى العلا');
    await tester.enterText(find.widgetWithText(TextField, 'ملاحظة (اختياري)'), 'في الشتاء');
    await tester.enterText(find.widgetWithText(TextField, 'السعر التقريبي بالريال (اختياري)'), '1500');
    await tester.tap(find.text('إضافة'));
    await _settle(tester);
    final body = srv.bodies['POST /wishlist']!;
    expect(body['kind'], 'custom');
    expect(body['title'], 'رحلة إلى العلا');
    expect(body['note'], 'في الشتاء');
    expect(body['price'], 150000);
    expect(find.text('رحلة إلى العلا'), findsOneWidget);
  });

  testWidgets('listing page heart adds the listing to the wishlist and removes it again', (tester) async {
    final srv = await _pump(tester, const ListingPage(_listingId));
    await _settle(tester);
    expect(find.text('عسل سدر'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wish-market-$_listingId')));
    await _settle(tester);
    expect(srv.bodies['POST /wishlist']?['kind'], 'market');
    expect(srv.bodies['POST /wishlist']?['refId'], _listingId);
    expect(find.byIcon(Icons.bookmark_added_rounded), findsOneWidget);
    expect(find.text('أُضيف إلى قائمة أمنياتك'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wish-market-$_listingId')));
    await _settle(tester);
    expect(srv.calls.where((c) => c.startsWith('DELETE /wishlist/')), hasLength(1));
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
  });
}
