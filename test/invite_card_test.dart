// بطاقة الدعوة: رابط `#/hi/<رمز>` يبدأ القادم على إنشاء الحساب ويحفظ رمز الداعي؛ بعد الدخول يُرسل الرمز مرة واحدة ويُمسح
// (ويبقى عند انقطاع الشبكة)؛ وصفحة البطاقة في ماي سبيس تعرض رمز QR لرابط الترحيب وعدد من انضموا.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/invite_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/app/app.dart';
import 'package:naslook/core/invite_ref.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/platform.dart';
import 'package:naslook/core/share/share_links.dart';
import 'package:naslook/pages/invite/invite_card_page.dart';
import 'package:naslook/pages/market/market_page.dart';
import 'package:naslook/pages/welcome/welcome_seen.dart';
import 'package:naslook/screens/login_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _Auth extends AppStateNotifier {
  _Auth(super.api, super.store, bool signedIn) {
    state = signedIn
        ? const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')))
        : const AppState(status: AuthStatus.signedOut);
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final _accepts = <String>[];
int _acceptStatus = 200;
int _joined = 0;
bool _inviteFails = false;

Future<http.Response> _handle(http.Request req) async {
  switch ('${req.method} ${req.url.path}') {
    case 'GET /settings/public': return _json({'announcement': '', 'maintenance': false});
    case 'GET /row': return _json({'items': [], 'located': false});
    case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
    case 'GET /notify/unread': return _json({'unread': 0});
    case 'GET /me/invite':
      if (_inviteFails) return _json({'error': 'boom'}, 500);
      return _json({'code': 'abcdef12', 'url': 'https://naslife.app/hi/abcdef12', 'joined': _joined});
    case 'POST /invite/accept':
      _accepts.add('${(jsonDecode(req.body) as Map)['code']}');
      if (_acceptStatus == 0) throw http.ClientException('offline');
      if (_acceptStatus != 200) return _json({'error': 'not-new'}, _acceptStatus);
      return _json({'ok': true, 'inviter': {'id': 'SA0000002', 'nickname': 'amr2', 'name': 'عمرو'}});
  }
  if (req.method == 'GET') return _json([]);
  return _json({'ok': true});
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

ApiClient _api({bool signedIn = true}) {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
  if (signedIn) api.token = 't';
  return api;
}

Future<void> _pump(WidgetTester tester, {Widget home = const AuthGate(), bool signedIn = false, Size size = const Size(900, 1400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _api(signedIn: signedIn);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _Auth(api, SessionStore(), signedIn)),
      notifyPollIntervalProvider.overrideWithValue(null),
      marketPosProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DeviceLocation.override = () async => null;
    iosNativeOverride = false;
    _accepts.clear();
    _acceptStatus = 200;
    _joined = 0;
    _inviteFails = false;
    await InviteRef.clear();
    InviteRef.takeRegister();
  });
  tearDown(() async {
    WelcomeSeen.debugSet(true);
    iosNativeOverride = null;
    DeviceLocation.override = null;
    ApiClient.onUnauthorized = null;
    pendingLink = null;
    await InviteRef.clear();
    InviteRef.takeRegister();
  });

  test('the invitation link parses with and without a code, and nothing else does', () {
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/hi/abcdef12')).toString(), 'invite:abcdef12');
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/hi')).toString(), 'invite:');
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/hi/ABC')), isNull);
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/hint')), isNull);
    expect(parsePendingLink(Uri.parse('https://naslife.app/#/hi/abcdef12/x')), isNull);
  });

  test('capturing an invitation link keeps the code on the device and leaves no pending destination', () async {
    capturePendingLink(Uri.parse('https://naslife.app/#/hi/abcdef12'));
    expect(pendingLink, isNull);
    expect(InviteRef.arrived, isTrue);
    expect(await InviteRef.pending(), 'abcdef12');
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getString(InviteRef.prefsKey), 'abcdef12');
    // كما بعد إعادة تحميل: الذاكرة فارغة والرمز في التخزين
    SharedPreferences.setMockInitialValues({InviteRef.prefsKey: 'zzzzzz99'});
    await InviteRef.clear();
    SharedPreferences.setMockInitialValues({InviteRef.prefsKey: 'zzzzzz99'});
    expect(await InviteRef.pending(), 'zzzzzz99');
  });

  test('the generic card starts sign-up without a code', () async {
    capturePendingLink(Uri.parse('https://naslife.app/#/hi'));
    expect(InviteRef.arrived, isTrue);
    expect(await InviteRef.pending(), isNull);
    expect(InviteRef.takeRegister(), isTrue);
    expect(InviteRef.takeRegister(), isFalse);
  });

  test('accepting sends the code once, returns the inviter name and clears it', () async {
    InviteRef.capture('abcdef12');
    expect(await acceptPendingInvite(_api()), 'عمرو');
    expect(_accepts, ['abcdef12']);
    expect(await InviteRef.pending(), isNull);
    expect(await acceptPendingInvite(_api()), isNull);
    expect(_accepts.length, 1);
  });

  test('a refusal clears the code; a network failure keeps it for the next launch', () async {
    InviteRef.capture('abcdef12');
    _acceptStatus = 409;
    expect(await acceptPendingInvite(_api()), isNull);
    expect(await InviteRef.pending(), isNull);

    InviteRef.capture('abcdef12');
    _acceptStatus = 0;
    expect(await acceptPendingInvite(_api()), isNull);
    expect(await InviteRef.pending(), 'abcdef12');
    _acceptStatus = 500;
    expect(await acceptPendingInvite(_api()), isNull);
    expect(await InviteRef.pending(), 'abcdef12');
  });

  testWidgets('a visitor from an invitation skips the tour and lands on sign-up', (tester) async {
    WelcomeSeen.debugSet(false);
    capturePendingLink(Uri.parse('https://naslife.app/#/hi/abcdef12'));
    await _pump(tester);
    expect(find.byKey(const Key('welcome-tour')), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('reg-nickname')), findsOneWidget, reason: 'شاشة الدخول تبدأ على إنشاء الحساب');
  });

  testWidgets('after signing in the invitation is accepted and the newcomer is greeted by the inviter name', (tester) async {
    InviteRef.capture('abcdef12');
    await _pump(tester, signedIn: true);
    await _settle(tester);
    expect(_accepts, ['abcdef12']);
    expect(find.textContaining('دعاك عمرو'), findsOneWidget);
    await _settle(tester, 20);
  });

  testWidgets('the card page shows the QR for my welcome link and how many joined', (tester) async {
    await _pump(tester, home: const InviteCardPage(), signedIn: true);
    expect(find.byKey(const Key('invite-card')), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byKey(const Key('invite-qr')));
    expect(qr.toStringShort(), isNotEmpty);
    expect(find.text('امسح وانضم'), findsOneWidget);
    expect(find.textContaining('أبرز البطاقة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invite-share')));
    await _settle(tester);
    expect(find.text('https://naslife.app/hi/abcdef12'), findsWidgets, reason: 'ورقة المشاركة تعرض الرابط');
  });

  testWidgets('the card page counts joiners, fits a small phone at large text, and offers retry on failure', (tester) async {
    _joined = 3;
    await _pump(tester, home: const InviteCardPage(), signedIn: true);
    expect(find.text('انضم بدعوتك: 3'), findsOneWidget);
    await _pump(tester, home: const InviteCardPage(key: Key('small')), signedIn: true, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('invite-qr')), findsOneWidget);

    _inviteFails = true;
    await _pump(tester, home: const InviteCardPage(key: Key('again')), signedIn: true);
    expect(find.byKey(const Key('invite-retry')), findsOneWidget);
    _inviteFails = false;
    await tester.tap(find.byKey(const Key('invite-retry')));
    await _settle(tester);
    expect(find.byKey(const Key('invite-card')), findsOneWidget);
  });
}
