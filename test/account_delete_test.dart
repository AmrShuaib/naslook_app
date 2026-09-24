// حذف الحساب من داخل التطبيق والروابط القانونية والموافقة (شروط متاجر التطبيقات):
// ماي سبيس ← حذف الحساب يعرض الموانع والتحذيرات، ولا يُفعَّل زر الحذف إلا بكلمة التأكيد وكلمة السر والإقرار،
// الرصيد الموجب يتطلب طلب الاسترداد، والحذف الناجح يسجّل الخروج؛ وروابط الخصوصية والشروط والدعم تُفتح من ماي سبيس.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/myspace/consent_sheet.dart';
import 'package:naslook/pages/myspace/delete_account_page.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final calls = <String>[];
  Map<String, dynamic>? lastBody, deleteBody;
  Map<String, dynamic> preview = {};
  final opened = <Uri>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened.clear();
    LegalLinks.openOverride = (u) async => opened.add(u);
  });
  tearDown(() => LegalLinks.openOverride = null);

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty) { try { lastBody = jsonDecode(req.body) as Map<String, dynamic>; } catch (_) {} }
    switch (key) {
      case 'GET /me/account/delete/preview': return _json(preview);
      case 'POST /me/account/delete':
        deleteBody = lastBody;
        if (lastBody!['password'] != 'Password1') return _json({'error': 'bad-password'}, 403);
        return _json({'ok': true, 'status': (preview['balance'] as int) > 0 ? 'pending_refund' : 'done'});
      case 'GET /me': return _json({'id': 'SA0000001', 'nickname': 'amr'});
      case 'GET /me/profile': return _json({'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true});
      case 'GET /me/map-presence': return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /me/recovery': return _json({'enabled': true, 'email': 'amr@example.com', 'verified': true, 'mailConfigured': true});
      case 'GET /me/login-email': return _json({'email': 'amr@example.com', 'verified': true, 'mailConfigured': true});
      case 'GET /notify/unread': return _json({'unread': 0});
    }
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }

  Map<String, dynamic> cleanPreview({int balance = 0, List<Map<String, dynamic>> blockers = const [], List<Map<String, dynamic>> warnings = const []}) => {
        'canDelete': blockers.isEmpty, 'blockers': blockers, 'warnings': [if (balance > 0) {'code': 'wallet-balance', 'count': 1}, ...warnings],
        'balance': balance, 'confirmWord': 'حذف', 'hasRecovery': true, 'refundDays': 30,
      };

  Future<ProviderContainer> pump(WidgetTester tester, Widget home) async {
    calls.clear();
    lastBody = null;
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
    api.token = 't';
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(locale: const Locale('ar'), home: home);
      }),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  testWidgets('MySpace shows delete account, contact and legal links that open in-app', (tester) async {
    await pump(tester, const Scaffold(body: MySpacePage()));
    await tester.scrollUntilVisible(find.byKey(const Key('legal-terms')), 300);
    expect(find.byKey(const Key('delete-account')), findsOneWidget);
    await tester.tap(find.byKey(const Key('legal-privacy')));
    await tester.tap(find.byKey(const Key('legal-terms')));
    await tester.pump();
    expect(opened.map((u) => u.path), ['/privacy', '/terms']);
    await tester.tap(find.byKey(const Key('contact-us')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact-email')));
    await tester.pumpAndSettle();
    expect(opened.last.scheme, 'mailto');
    expect(opened.last.path, LegalLinks.supportEmail);
  });

  testWidgets('blockers disable deletion and are listed', (tester) async {
    preview = cleanPreview(blockers: [{'code': 'open-orders', 'count': 2}]);
    await pump(tester, const DeleteAccountPage());
    expect(find.byKey(const Key('del-blocker-open-orders')), findsOneWidget);
    expect(find.textContaining('طلبات مفتوحة'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('del-submit'))).onPressed, isNull);
  });

  testWidgets('delete requires ack, confirm word and password; wrong password is reported; success signs out', (tester) async {
    preview = cleanPreview();
    final c = await pump(tester, const DeleteAccountPage());
    FilledButton submit() => tester.widget<FilledButton>(find.byKey(const Key('del-submit')));
    expect(submit().onPressed, isNull);
    await tester.tap(find.byKey(const Key('del-ack')));
    await tester.enterText(find.byKey(const Key('del-confirm')), 'نعم');
    await tester.enterText(find.byKey(const Key('del-password')), 'wrong');
    await tester.pump();
    expect(submit().onPressed, isNull, reason: 'كلمة التأكيد غير مطابقة');
    await tester.enterText(find.byKey(const Key('del-confirm')), 'حذف');
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('del-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('كلمة السر غير صحيحة'), findsOneWidget);
    expect(deleteBody!['confirm'], 'حذف');
    await tester.enterText(find.byKey(const Key('del-password')), 'Password1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('del-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.where((x) => x == 'POST /me/account/delete').length, 2);
    expect(deleteBody!['refund'], isFalse);
    expect(c.read(appStateProvider).status, AuthStatus.signedOut, reason: 'يُسجَّل الخروج بعد الحذف');
  });

  testWidgets('positive balance requires the refund request', (tester) async {
    preview = cleanPreview(balance: 2500);
    await pump(tester, const DeleteAccountPage());
    expect(find.byKey(const Key('del-warning-wallet-balance')), findsOneWidget);
    await tester.tap(find.byKey(const Key('del-ack')));
    await tester.enterText(find.byKey(const Key('del-confirm')), 'حذف');
    await tester.enterText(find.byKey(const Key('del-password')), 'Password1');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('del-submit'))).onPressed, isNull, reason: 'يلزم طلب الاسترداد');
    await tester.tap(find.byKey(const Key('del-refund')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('del-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deleteBody!['refund'], isTrue);
  });

  testWidgets('consent sheet returns true on accept and false on logout', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () async => result = await ConsentSheet.show(ctx), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('consent-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pump();
    expect(opened.single.path, '/terms');
    await tester.tap(find.byKey(const Key('consent-accept')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('consent-logout')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
