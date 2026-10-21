// مفاتيح المال التنظيمية وحدود الشحن (حزمة الأمان، المسار ج): إعدادات الإدارة تعرض أدنى/أقصى شحن بالبطاقة وسطر حالة المفاتيح
// وترسلها بالهللة مع المفتاحين (مطفآن افتراضياً ولا يُعدّان مفعّلين إلا بـ true صريحة)، ورفض تفعيل الشحن التجريبي مع مفاتيح
// ميسر الحية (المفتاح يُرسل فقط إن غيّره المدير حتى لا يعطّل حفظ بقية الإعدادات)؛ المحفظة تأخذ سقف الشحن التجريبي من الخادم
// (maxTopup مع /wallet) لا من ثابت؛ والمالية تُظهر المال التجريبي.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/admin_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/commerce_models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/admin/admin_finance.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/wallet/wallet_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

typedef _Route = Object? Function(http.Request req, Map<String, dynamic>? body);

/// خادم وهمي: مسارات صريحة (قيمة أو http.Response جاهزة)، والباقي قائمة فارغة لطلبات GET و{ok} لغيرها.
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final routes = <String, _Route>{};
  _Srv() {
    routes['GET /notify/unread'] = (_, __) => {'unread': 0};
    routes['GET /settings/public'] = (_, __) => {'announcement': '', 'maintenance': false, 'testTopup': true, 'transfersEnabled': false, 'chatPaymentsEnabled': false};
    routes['GET /pay/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar', 'methods': [], 'min': 10000, 'max': 500000, 'currency': 'SAR'};
    routes['GET /adminapi/payments/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar'};
    routes['GET /adminapi/admins'] = (_, __) => [];
  }
  http.Response _json(Object? body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty && req.method != 'GET') {
      try {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies[key] = body;
      } catch (_) {}
    }
    final r = routes[key];
    if (r != null) {
      final out = r(req, body);
      return out is http.Response ? out : _json(out);
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return req.method == 'GET' ? _json([]) : _json({'ok': true});
  }
}

Map<String, dynamic> _settings({bool testTopup = true, bool? transfers, bool? chatPay}) => {
      'testTopup': testTopup, 'maxTopup': 100000, 'minTopup': 10000, 'maxCardTopup': 500000, 'announcement': '', 'maintenance': false, 'supportHandle': '', 'supportEmail': '', 'bannedWords': '', 'reportThreshold': 3,
      if (transfers != null) 'transfersEnabled': transfers, if (chatPay != null) 'chatPaymentsEnabled': chatPay, 'bannedWordsDefault': true,
    };

Future<_Srv> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(600, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
  return srv;
}

Future<void> _save(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('set-save')), 400, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(find.byKey(const Key('set-save')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('set-save')));
  await tester.pumpAndSettle();
}

/// حقل الحوار الذي يحمل تلميحاً يحتوي النص
Finder _hintContaining(String text) => find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').contains(text));

void main() {
  group('models', () {
    test('AdminSettings: money switches default off and need an explicit true; limits default to 100 and 5,000 SAR', () {
      final empty = AdminSettings.fromJson(const {});
      expect(empty.transfersEnabled, isFalse);
      expect(empty.chatPaymentsEnabled, isFalse);
      expect(empty.minTopup, 10000);
      expect(empty.maxCardTopup, 500000);
      final loose = AdminSettings.fromJson(const {'transfersEnabled': 'yes', 'chatPaymentsEnabled': 1, 'minTopup': 20000, 'maxCardTopup': 300000});
      expect(loose.transfersEnabled, isFalse);
      expect(loose.chatPaymentsEnabled, isFalse);
      expect(loose.minTopup, 20000);
      expect(loose.maxCardTopup, 300000);
      expect(AdminSettings.fromJson(const {'transfersEnabled': true, 'chatPaymentsEnabled': true}).chatPaymentsEnabled, isTrue);
      expect(const AdminSettings().transfersEnabled, isFalse);
    });

    test('Wallet: maxTopup comes from the server, falling back to the constant; test_topup has its own label', () {
      expect(Wallet.fromJson(const {'balance': 1}).maxTopup, maxTopupHalalas);
      expect(Wallet.fromJson(const {'balance': 1, 'maxTopup': 500000}).maxTopup, 500000);
      expect(Wallet.fromJson(const {'balance': 1, 'maxTopup': 0}).maxTopup, maxTopupHalalas);
      expect(const WalletTx(id: 'x', kind: 'test_topup', amount: 100).label, 'شحن تجريبي');
      expect(const WalletTx(id: 'x', kind: 'topup', amount: 100).label, 'شحن');
    });

    test('AdminFinance parses testTopups', () {
      final f = AdminFinance.fromJson(const {'totals': {'accounts': 1, 'balance': 2, 'points': 3}, 'testTopups': {'count': 4, 'amount': 56000}});
      expect(f.testTopupsCount, 4);
      expect(f.testTopupsAmount, 56000);
      expect(AdminFinance.fromJson(const {'totals': {}}).testTopupsAmount, 0);
    });
  });

  group('admin settings', () {
    testWidgets('shows the card limits and the switches state, and saves halalas with the switches', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => _settings();
      srv.routes['POST /adminapi/settings'] = (_, b) => {..._settings(), ...?b};
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
      expect(find.text('أقصى شحن تجريبي في المرة (ريال)'), findsOneWidget);
      expect(find.text('أدنى شحن بالبطاقة (ريال)'), findsOneWidget);
      expect(find.text('أقصى شحن بالبطاقة في المرة (ريال)'), findsOneWidget);
      // القيم بالريال من الهللات
      expect((tester.widget(find.byKey(const Key('set-min-topup'))) as TextField).controller!.text, '100');
      expect((tester.widget(find.byKey(const Key('set-max-card-topup'))) as TextField).controller!.text, '5000');
      expect((tester.widget(find.byKey(const Key('set-max-topup'))) as TextField).controller!.text, '1000');
      // المفتاحان غير مرسلين من الخادم = مطفآن
      expect(find.text('التحويل: مطفأ · دفع المحادثة: مطفأ · الشحن التجريبي: مفعّل'), findsOneWidget);
      expect(find.textContaining('مطفأ افتراضياً بقرار تنظيمي'), findsNWidgets(2));
      expect((tester.widget(find.byKey(const Key('set-transfers'))) as SwitchListTile).value, isFalse);
      expect((tester.widget(find.byKey(const Key('set-chat-payments'))) as SwitchListTile).value, isFalse);
      await tester.tap(find.byKey(const Key('set-transfers')));
      await tester.pump();
      expect(find.text('التحويل: مفعّل · دفع المحادثة: مطفأ · الشحن التجريبي: مفعّل'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('set-min-topup')), '150');
      await tester.enterText(find.byKey(const Key('set-max-card-topup')), '7000');
      await tester.enterText(find.byKey(const Key('set-max-topup')), '2000');
      await _save(tester);
      final b = srv.bodies['POST /adminapi/settings']!;
      expect(b['minTopup'], 15000);
      expect(b['maxCardTopup'], 700000);
      expect(b['maxTopup'], 200000);
      expect(b['transfersEnabled'], isTrue);
      expect(b['chatPaymentsEnabled'], isFalse);
      expect(b.containsKey('testTopup'), isFalse); // لم يُلمس فلا يُرسل (وإلا رفضه الخادم مع مفاتيح ميسر الحية)
      expect(find.text('حُفظت الإعدادات'), findsOneWidget);
    });

    testWidgets('an untouched test top-up is not sent, so other settings still save while Moyasar live keys are set', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => _settings(testTopup: false);
      // كما admin.js مع مفاتيح ميسر الحية: يرفض فقط حين يصله testTopup:true
      srv.routes['POST /adminapi/settings'] = (_, b) => b?['testTopup'] == true ? http.Response(jsonEncode({'error': 'test-topup-live'}), 409, headers: {'content-type': 'application/json; charset=utf-8'}) : {..._settings(testTopup: false), ...?b};
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
      await tester.enterText(find.byKey(const Key('set-max-topup')), '2000');
      await _save(tester);
      final b = srv.bodies['POST /adminapi/settings']!;
      expect(b.containsKey('testTopup'), isFalse);
      expect(b['maxTopup'], 200000);
      expect(find.text('حُفظت الإعدادات'), findsOneWidget);
      expect(find.text('لا يمكن تفعيل الشحن التجريبي ومفاتيح ميسر الحية مضبوطة'), findsNothing);
    });

    testWidgets('a test top-up that is on at the server and switched off is sent as false', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => _settings(testTopup: true);
      srv.routes['POST /adminapi/settings'] = (_, b) => {..._settings(), ...?b};
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
      await tester.tap(find.text('الشحن التجريبي').first);
      await tester.pump();
      expect(find.text('التحويل: مطفأ · دفع المحادثة: مطفأ · الشحن التجريبي: مطفأ'), findsOneWidget);
      await _save(tester);
      expect(srv.bodies['POST /adminapi/settings']!['testTopup'], isFalse);
      expect(find.text('حُفظت الإعدادات'), findsOneWidget);
    });

    testWidgets('switches sent as true by the server show as on', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => _settings(testTopup: false, transfers: true, chatPay: true);
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
      expect(find.text('التحويل: مفعّل · دفع المحادثة: مفعّل · الشحن التجريبي: مطفأ'), findsOneWidget);
      expect((tester.widget(find.byKey(const Key('set-chat-payments'))) as SwitchListTile).value, isTrue);
    });

    testWidgets('turning the test top-up on while Moyasar live keys are set is refused with a clear toast', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => _settings(testTopup: false);
      srv.routes['POST /adminapi/settings'] = (_, __) => http.Response(jsonEncode({'error': 'test-topup-live'}), 409, headers: {'content-type': 'application/json; charset=utf-8'});
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()));
      await tester.tap(find.text('الشحن التجريبي').first);
      await tester.pump();
      await _save(tester);
      expect(srv.bodies['POST /adminapi/settings']!['testTopup'], isTrue);
      expect(find.text('لا يمكن تفعيل الشحن التجريبي ومفاتيح ميسر الحية مضبوطة'), findsOneWidget);
      expect(find.text('حُفظت الإعدادات'), findsNothing);
    });
  });

  group('wallet', () {
    Map<String, dynamic> wallet({int maxTopup = 500000}) => {'balance': 100000, 'points': 0, 'upcomingTickets': 0, 'testTopup': true, 'maxTopup': maxTopup, 'recent': [{'id': 't1', 'kind': 'test_topup', 'amount': 5000, 'note': null, 'createdAt': '2026-10-01T08:00:00Z'}]};

    testWidgets('test top-up uses the server maxTopup for the hint, the limit and the request', (tester) async {
      final srv = _Srv();
      srv.routes['GET /wallet'] = (_, __) => wallet();
      await _pump(tester, srv, const WalletPage(), size: const Size(600, 1500));
      expect(find.text('شحن تجريبي'), findsOneWidget); // بطاقة الحركة
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      expect(_hintContaining('5000 ر.س'), findsOneWidget);
      expect(_hintContaining('100000 ر.س'), findsNothing);
      // فوق السقف: رسالة وبلا طلب
      await tester.enterText(_hintContaining('5000 ر.س'), '6000');
      await tester.tap(find.text('شحن').last);
      await tester.pumpAndSettle();
      expect(find.text('أقصى شحن في المرة الواحدة 5000 ر.س؛ كرّر الشحن إن احتجت أكثر'), findsOneWidget);
      expect(srv.calls.where((c) => c == 'POST /wallet/topup'), isEmpty);
      // داخل السقف: الطلب بالهللة
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      await tester.enterText(_hintContaining('5000 ر.س'), '4000');
      await tester.tap(find.text('شحن').last);
      await tester.pumpAndSettle();
      expect(srv.bodies['POST /wallet/topup'], {'amount': 400000});
    });

    testWidgets('a higher server cap is reflected without a code change', (tester) async {
      final srv = _Srv();
      srv.routes['GET /wallet'] = (_, __) => wallet(maxTopup: 2000000);
      await _pump(tester, srv, const WalletPage(), size: const Size(600, 1500));
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      expect(_hintContaining('20000 ر.س'), findsOneWidget);
    });

    testWidgets('topup-disabled-live from the server is explained', (tester) async {
      final srv = _Srv();
      srv.routes['GET /wallet'] = (_, __) => wallet();
      srv.routes['POST /wallet/topup'] = (_, __) => http.Response(jsonEncode({'error': 'topup-disabled-live'}), 403, headers: {'content-type': 'application/json; charset=utf-8'});
      await _pump(tester, srv, const WalletPage(), size: const Size(600, 1500));
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      await tester.enterText(_hintContaining('5000 ر.س'), '50');
      await tester.tap(find.text('شحن').last);
      await tester.pumpAndSettle();
      expect(find.text('الشحن التجريبي متوقف لأن الدفع الحقيقي مفعّل'), findsOneWidget);
    });
  });

  group('admin finance', () {
    Map<String, dynamic> finance({int count = 0, int amount = 0}) => {
          'totals': {'accounts': 3, 'balance': 90000, 'points': 0}, 'testTopups': {'count': count, 'amount': amount},
          'byKind': [{'kind': 'test_topup', 'count': count, 'amount': amount}], 'daily': [{'day': '2026-10-20', 'topups': 0, 'purchases': 0, 'refunds': 0}], 'recent': [], 'topBalances': [],
        };

    testWidgets('shows the test money row when there is test money', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/finance'] = (_, __) => finance(count: 3, amount: 150000);
      await _pump(tester, srv, const Scaffold(body: AdminFinancePage()));
      expect(find.byKey(const Key('finance-test-money')), findsOneWidget);
      expect(find.text('مال تجريبي في النظام: 1500 ر.س (3 حركة)'), findsOneWidget);
      expect(find.text('شحن تجريبي'), findsOneWidget); // اسم النوع في «حسب نوع الحركة»
    });

    testWidgets('no row without test money', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/finance'] = (_, __) => finance();
      await _pump(tester, srv, const Scaffold(body: AdminFinancePage()));
      expect(find.byKey(const Key('finance-test-money')), findsNothing);
    });
  });
}
