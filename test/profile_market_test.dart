import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _lid = '55555555-5555-4555-8555-555555555555';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String listingStatus = 'hidden';
  String? avatar;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> _listing() => {'id': _lid, 'seller': {'id': 'SA0000001', 'nickname': 'amr'}, 'kind': 'product', 'category': 'food', 'title': 'برجر لحم', 'description': 'طازج', 'price': 5000, 'imageUrl': null, 'placeName': 'جدة', 'status': listingStatus, 'mine': true};

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    final ct = req.headers['content-type'] ?? '';
    if (ct.contains('json') && req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'POST /chat/upload':
        return _json({'url': '/chat/media/a.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': 3});
      case 'POST /profile/avatar':
        avatar = 'https://test.local${bodies[key]!['url']}';
        return _json({'ok': true, 'avatarUrl': avatar});
      case 'DELETE /profile/avatar':
        avatar = null;
        return _json({'ok': true});
      case 'GET /me/profile':
        return _json({'id': 'SA0000001', 'nickname': 'amr', 'bio': '', 'avatarUrl': avatar, 'skills': [], 'hobbies': [], 'lookingFor': []});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /vessels/mine':
      case 'GET /contacts':
      case 'GET /market':
      case 'GET /market/orders':
        return _json([]);
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': false});
      case 'GET /notify/unread':
        return _json({'unread': 0});
      case 'POST /market':
        return _json({..._listing(), 'status': 'active', 'imageUrl': bodies[key]!['imageUrl']});
      case 'GET /market/mine':
        return _json([_listing()]);
      case 'GET /market/$_lid':
        return _json(_listing());
      case 'PATCH /market/$_lid':
        if (bodies[key]!['status'] != null) listingStatus = bodies[key]!['status'] as String;
        return _json(_listing());
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
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
  setUp(() => pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList('img'.codeUnits), mime: 'image/jpeg', name: 'a.jpg'));
  tearDown(() => pickImageOverride = null);

  testWidgets('profile edit dialog uploads and sets an avatar, then can remove it', (tester) async {
    final srv = await _pump(tester, const Scaffold(body: MySpacePage()));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await _settle(tester);
    expect(find.text('تعديل الملف'), findsOneWidget);
    expect(find.text('إضافة صورة'), findsOneWidget);
    await tester.tap(find.text('إضافة صورة'));
    await _settle(tester);
    expect(srv.calls, containsAllInOrder(['POST /chat/upload', 'POST /profile/avatar']));
    expect(srv.bodies['POST /profile/avatar']!['url'], '/chat/media/a.jpg');
    final ctx = tester.element(find.text('تعديل الملف'));
    expect(ProviderScope.containerOf(ctx).read(appStateProvider).user?.avatarUrl, 'https://test.local/chat/media/a.jpg');
    expect(find.text('تغيير الصورة'), findsOneWidget);
    expect(find.text('إزالة الصورة'), findsOneWidget);
    await tester.tap(find.text('إزالة الصورة'));
    await _settle(tester);
    expect(srv.calls, contains('DELETE /profile/avatar'));
    expect(ProviderScope.containerOf(ctx).read(appStateProvider).user?.avatarUrl, isNull);
    expect(find.text('إضافة صورة'), findsOneWidget);
  });

  testWidgets('new listing form takes an image and publishes it', (tester) async {
    final srv = await _pump(tester, const MarketPage());
    await tester.tap(find.text('اعرض للبيع'));
    await _settle(tester);
    expect(find.text('عرض جديد'), findsOneWidget);
    await tester.tap(find.text('إضافة صورة'));
    await _settle(tester);
    expect(find.text('تغيير الصورة'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'العنوان'), 'برجر');
    await tester.enterText(find.widgetWithText(TextField, 'السعر (ر.س)'), '50');
    await tester.tap(find.text('نشر'));
    await tester.pump(const Duration(seconds: 15)); // مهلة تحديد الموقع في بيئة الاختبار
    await _settle(tester);
    expect(srv.calls, containsAllInOrder(['POST /chat/upload', 'POST /market']));
    expect(srv.bodies['POST /market']!['imageUrl'], '/chat/media/a.jpg');
    expect(srv.bodies['POST /market']!['price'], 5000);
  });

  testWidgets('my listings tab shows hidden listing and can show it again', (tester) async {
    final srv = await _pump(tester, const OrdersPage(initialTab: 0));
    expect(find.text('عروضي'), findsOneWidget);
    expect(find.text('برجر لحم'), findsOneWidget);
    expect(find.textContaining('مخفي'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await _settle(tester);
    expect(srv.bodies['PATCH /market/$_lid']!['status'], 'active');
    expect(find.textContaining('ظاهر في السوق'), findsOneWidget);
  });

  testWidgets('listing page shows owner actions for a hidden listing', (tester) async {
    await _pump(tester, const ListingPage(_lid));
    expect(find.text('العرض مخفي ولا يراه أحد غيرك.'), findsOneWidget);
    expect(find.text('إظهار العرض'), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget);
    await tester.tap(find.text('تعديل'));
    await _settle(tester);
    expect(find.text('تعديل العرض'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'العنوان'), findsOneWidget);
  });
}
