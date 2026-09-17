// روابط المشاركة العامة: تحليل الرابط عند الإقلاع، تصفّح الزائر مع شريط الدخول ودعوة الدخول عند فعل يتطلب حساباً،
// ورقة المشاركة (QR ورابط ونسخ) للدائرة والحساب، والملف العام بالنك نيم.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/profile/public_profile_page.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

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

Map<String, dynamic> _cafe() => {
      'id': 'biz-brew92', 'name': 'Brew 92', 'nameAr': 'برو 92', 'category': 'cafe', 'sector': 'محمصة', 'description': 'محمصة', 'lat': 21.57, 'lng': 39.14, 'address': 'الروضة', 'hours': '', 'color': '#5B2E1E',
      'highlights': [], 'followers': 0, 'itemsCount': 0, 'active': true, 'reviews': [], 'myOrders': [], 'posts': [], 'items': [],
    };

class _Srv {
  final calls = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    final signed = req.headers.containsKey('x-token');
    if (key == 'GET /biz/biz-brew92') return _json(_cafe());
    if (key == 'GET /biz/biz-brew92/community') return _json({'posts': [], 'total': 0, 'members': 0, 'canModerate': false, 'hasMore': false, 'topItems': []});
    if (key == 'POST /biz/biz-brew92/follow') return signed ? _json({'ok': true}) : _json({'error': 'auth'}, 401);
    if (key == 'GET /users/sara') return _json({'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null});
    if (key == 'GET /users/nobody') return _json({'error': 'not-found'}, 404);
    if (key == 'GET /profiles/SA0000002') return _json({'id': 'SA0000002', 'nickname': 'sara', 'bio': 'أحب القهوة', 'isPublic': true});
    if (key == 'GET /presence/SA0000002') return _json({'online': false});
    if (key == 'GET /contacts') return _json([]);
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /wishlist') return signed ? _json([]) : _json({'error': 'auth'}, 401);
    if (key == 'GET /safety/words') return _json({'words': []});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {bool signedIn = true}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // الحافظة في الاختبارات: قناة النظام بلا تنفيذ فعلي
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  if (signedIn) api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => signedIn ? _SignedIn(api, SessionStore()) : _SignedOut(api, SessionStore())),
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
  tearDown(() {
    pendingLink = null;
    ApiClient.onUnauthorized = null;
  });

  test('parsePendingLink reads circle and account links from path or fragment', () {
    expect(parsePendingLink(Uri.parse('https://naslife.app/c/biz-brew92'))?.toString(), 'circle:biz-brew92');
    expect(parsePendingLink(Uri.parse('https://naslife.app/u/amr'))?.toString(), 'user:amr');
    expect(parsePendingLink(Uri.parse('https://naslife.app/u/%D8%B3%D8%A7%D8%B1%D8%A9'))?.value, 'سارة');
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/c/biz-kaia'))?.toString(), 'circle:biz-kaia');
    expect(parsePendingLink(Uri.parse('https://naslife.app/c/BAD ID')), isNull);
    expect(parsePendingLink(Uri.parse('https://naslife.app/')), isNull);
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/n/aaaaaaaa-0000-4000-8000-000000000000')), isNull);
    expect(circleLink('biz-brew92'), 'https://naslife.app/c/biz-brew92');
    expect(profileLink('amr'), 'https://naslife.app/u/amr');
  });

  testWidgets('signed-out visitor with a circle link sees the circle as a guest, then can go to login', (tester) async {
    pendingLink = const PendingLink('circle', 'biz-brew92');
    await _pump(tester, const AuthGate(), signedIn: false);
    await _settle(tester);
    expect(find.byType(GuestShell), findsOneWidget);
    expect(find.byType(BusinessPage), findsOneWidget);
    expect(find.text('برو 92'), findsWidgets);
    expect(find.byKey(const Key('guest-bar')), findsOneWidget);
    // فعل يتطلب حساباً: الانضمام → 401 → دعوة للدخول
    await tester.tap(find.text('انضم'));
    await _settle(tester);
    expect(find.text('هذا يحتاج حساباً'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600)); // اكتمال حركة الورقة قبل اللمس
    await tester.tap(find.byKey(const Key('guest-login-sheet')));
    await _settle(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(GuestShell), findsNothing);
  });

  test('pendingLinkPage maps links to the circle page or the public profile', () {
    expect(pendingLinkPage(const PendingLink('circle', 'biz-brew92')), isA<BusinessPage>());
    expect((pendingLinkPage(const PendingLink('user', 'sara')) as PublicProfilePage).handle, 'sara');
  });

  testWidgets('share sheet on the circle page shows the public link, a QR code and a copy button', (tester) async {
    await _pump(tester, const BusinessPage(id: 'biz-brew92'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('share-circle')));
    await _settle(tester);
    expect(find.byKey(const Key('share-qr')), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('share-url'))).data, 'https://naslife.app/c/biz-brew92');
    await tester.tap(find.byKey(const Key('share-copy')));
    await _settle(tester);
    expect(find.text('نُسخ الرابط'), findsOneWidget);
  });

  testWidgets('public profile by nickname resolves and shares /u/<nickname>; unknown nickname shows not found', (tester) async {
    await _pump(tester, const PublicProfilePage(handle: 'sara'));
    await _settle(tester);
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(find.text('sara'), findsWidgets);
    await tester.tap(find.byKey(const Key('share-profile')));
    await _settle(tester);
    expect(tester.widget<SelectableText>(find.byKey(const Key('share-url'))).data, 'https://naslife.app/u/sara');
    await tester.tap(find.byKey(const Key('share-copy')));
    await _settle(tester);
    await _pump(tester, const PublicProfilePage(handle: 'nobody'));
    await _settle(tester);
    expect(find.text('الحساب غير موجود'), findsOneWidget);
  });
}
