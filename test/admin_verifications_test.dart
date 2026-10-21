// طابور توثيق الدوائر في الإدارة وبطاقته في النظرة العامة: قسم «التوثيق» يسرد المعلّقة بالفئة والحضور والمالك ونوع
// الكيان ورقمه والمستند، «مطابق» يرسل الاعتماد، «مرفوض» يطلب سبباً إلزامياً ويرسله في الحمولة، «استعلام رسمي» يفتح رابط
// الجهة عبر البديل الاختباري، نسخ الرقم إلى الحافظة، الفلاتر تطلب الحالة المختارة، وبطاقة «توثيق بانتظار القرار» تعرض
// العدد كهرمانياً وتفتح القسم.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/admin_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/app_theme.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/admin/admin_biz.dart';
import 'package:naslook/pages/admin/admin_overview.dart';
import 'package:naslook/pages/admin/admin_shell.dart';
import 'package:naslook/state/admin_providers.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _row(String id, String nameAr, {String status = 'pending', String category = 'shop', String presence = 'fixed', String kind = 'cr', String number = '4030123456', String owner = 'sara', String? reason, String? doc = '/chat/media/doc-cr.jpg'}) => {
      'bizId': id, 'name': id, 'nameAr': nameAr, 'category': category, 'logoUrl': null, 'presence': presence, 'ownerId': 'SA0000002', 'owner': {'id': 'SA0000002', 'nickname': owner},
      'entityKind': kind, 'entityNumber': number, 'docUrl': doc, 'submittedAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(), 'status': status, 'reason': reason,
      'lookupUrl': kind == 'cr' ? 'https://mc.gov.sa/cr-inquiry' : 'https://freelance.sa/verify',
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  /// حالات الطابور المطلوبة بالترتيب
  final statuses = <String>[];
  int pending = 2;
  List<Map<String, dynamic>> rows = [
    _row('biz-cr', 'متجر نور'),
    _row('biz-fl', 'ورشة خالد المتنقلة', category: 'services', presence: 'mobile', kind: 'freelance', number: 'FL20481', owner: 'khalid'),
    _row('biz-ok', 'إيكيا', status: 'approved', category: 'brand'),
    _row('biz-rj', 'زارا', status: 'rejected', reason: 'الرقم لا يطابق'),
  ];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  List<Map<String, dynamic>> _daily() => [for (var i = 13; i >= 0; i--) {'day': DateTime.now().subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'users': i % 3, 'orders': i % 4, 'revenue': (i % 4) * 1000}];

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'GET /adminapi/status':
        return _json({'hasAdmin': true, 'setupRequired': false, 'isAdmin': true, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'admins': 1});
      case 'GET /adminapi/overview':
        return _json({
          'users': {'total': 120, 'new7': 9, 'suspended': 1, 'admins': 1}, 'orders7': {'count': 14, 'revenue': 250000},
          'circles': {'active': 22, 'inactive': 0, 'owned': 2, 'claims': 0, 'pendingVerifications': pending, 'tiers': {'published': 22, 'complete': 9, 'verified': 4, 'active': 1}},
          'reports': {'open': 0, 'available': true}, 'wallets': {'accounts': 40, 'balance': 990000}, 'daily': _daily(), 'server': {'node': 'v22', 'uptimeSec': 600, 'tables': ['users']},
        });
      case 'GET /adminapi/biz':
      case 'GET /adminapi/claims':
        return _json([]);
      case 'GET /adminapi/biz/verifications':
        final st = req.url.queryParameters['status'] ?? 'pending';
        statuses.add(st);
        return _json(rows.where((r) => st == 'all' || r['status'] == st).toList());
      case 'POST /adminapi/biz/biz-cr/verification/approve':
        rows.firstWhere((r) => r['bizId'] == 'biz-cr')['status'] = 'approved';
        pending--;
        return _json({'ok': true, 'status': 'approved'});
      case 'POST /adminapi/biz/biz-fl/verification/reject':
        final reason = (bodies[key]?['reason'] ?? '').toString().trim();
        if (reason.length < 3) return _json({'error': 'reason-required'}, 400);
        rows.firstWhere((r) => r['bizId'] == 'biz-fl')
          ..['status'] = 'rejected'
          ..['reason'] = reason;
        pending--;
        return _json({'ok': true, 'status': 'rejected'});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  api.token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pumpAndSettle();
}

/// يفتح قسم «التوثيق» في صفحة الدوائر.
Future<_Srv> _openQueue(WidgetTester tester, [_Srv? srv]) async {
  final s = srv ?? _Srv();
  await _pump(tester, s, const Scaffold(body: AdminBizPage()));
  expect(find.byKey(const Key('biz-segments')), findsOneWidget);
  await tester.tap(find.byKey(const Key('biz-seg-verifications')));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  tearDown(() {
    ApiClient.onUnauthorized = null;
    LegalLinks.openOverride = null;
  });

  test('VerificationRow parses tolerantly and labels the entity, presence and status', () {
    final r = VerificationRow.fromJson(_row('biz-fl', 'ورشة', presence: 'mobile', kind: 'freelance', number: 'FL1'));
    expect(r.title, 'ورشة');
    expect(r.entityLabel, 'وثيقة عمل حر');
    expect(r.presenceLabel, 'دائرة متنقلة');
    expect(r.statusLabel, 'بانتظار القرار');
    expect(r.lookupUrl, 'https://freelance.sa/verify');
    final bare = VerificationRow.fromJson({'bizId': 'x', 'status': 'approved'});
    expect(bare.docUrl, isNull);
    expect(bare.owner, isNull);
    expect(bare.statusLabel, 'موثّقة');
    expect(adminBizCategoryLabel('shop'), 'متجر');
    expect(adminBizCategoryLabel('cafe'), isNot('cafe'));
    expect(adminBizCategoryLabel('weird'), 'weird');
    final o = AdminOverview.fromJson({'circles': {'active': 1, 'pendingVerifications': 3, 'tiers': {'published': 5, 'complete': 2, 'verified': 1, 'active': 0}}});
    expect(o.pendingVerifications, 3);
    expect(o.tiers.published, 5);
    expect(AdminOverview.fromJson({'circles': {'active': 1}}).tiers.verified, 0, reason: 'قبل وصول الحقول أصفار');
  });

  testWidgets('the «التوثيق» segment lists pending requests with circle, owner, entity, document and status', (tester) async {
    final srv = await _openQueue(tester);
    expect(srv.statuses, ['pending']);
    expect(find.byKey(const Key('verif-row-biz-cr')), findsOneWidget);
    expect(find.byKey(const Key('verif-row-biz-fl')), findsOneWidget);
    expect(find.byKey(const Key('verif-row-biz-ok')), findsNothing, reason: 'الموثّقة ليست في طابور المعلّقة');
    expect(tester.widget<SelectableText>(find.byKey(const Key('verif-entity-biz-cr'))).data, 'سجل تجاري: 4030123456');
    expect(tester.widget<SelectableText>(find.byKey(const Key('verif-entity-biz-fl'))).data, 'وثيقة عمل حر: FL20481');
    expect(find.text('متجر · موقع ثابت · المالك sara'), findsOneWidget);
    expect(find.text('خدمات وورش · دائرة متنقلة · المالك khalid'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('verif-status-biz-cr'))).data, 'بانتظار القرار');
    expect(find.byKey(const Key('verif-approve-biz-cr')), findsOneWidget);
    expect(find.byKey(const Key('verif-reject-biz-cr')), findsOneWidget);
    // المستند يُفتح كاملاً
    await tester.tap(find.byKey(const Key('verif-doc-biz-cr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verif-doc-view')), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verif-doc-view')), findsNothing);
  });

  testWidgets('«مطابق» posts the approval, toasts and refreshes the queue', (tester) async {
    final srv = await _openQueue(tester);
    await tester.tap(find.byKey(const Key('verif-approve-biz-cr')));
    await tester.pumpAndSettle();
    expect(srv.calls, contains('POST /adminapi/biz/biz-cr/verification/approve'));
    expect(srv.bodies['POST /adminapi/biz/biz-cr/verification/approve'], isEmpty, reason: 'الاعتماد بلا سبب');
    expect(find.text('وُثّقت الدائرة وأُبلغ المالك'), findsOneWidget);
    expect(srv.statuses.length, greaterThanOrEqualTo(2), reason: 'أُعيد جلب الطابور بعد القرار');
    expect(find.byKey(const Key('verif-row-biz-cr')), findsNothing);
    expect(find.byKey(const Key('verif-row-biz-fl')), findsOneWidget);
  });

  testWidgets('«مرفوض» asks for a reason, refuses an empty one locally, then posts it', (tester) async {
    final srv = await _openQueue(tester);
    await tester.tap(find.byKey(const Key('verif-reject-biz-fl')));
    await tester.pumpAndSettle();
    expect(find.text('سبب رفض توثيق ورشة خالد المتنقلة'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'رفض'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب سبباً من 3 أحرف على الأقل'), findsOneWidget);
    expect(srv.calls, isNot(contains('POST /adminapi/biz/biz-fl/verification/reject')));
    await tester.tap(find.byKey(const Key('verif-reject-biz-fl')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'الرقم لا يطابق اسم المنشأة');
    await tester.tap(find.widgetWithText(FilledButton, 'رفض'));
    await tester.pumpAndSettle();
    expect(srv.bodies['POST /adminapi/biz/biz-fl/verification/reject']!['reason'], 'الرقم لا يطابق اسم المنشأة');
    expect(find.text('رُفض التوثيق وأُبلغ المالك بالسبب'), findsOneWidget);
    expect(find.byKey(const Key('verif-row-biz-fl')), findsNothing);
  });

  testWidgets('«استعلام رسمي» opens the official page through the override, and the entity number can be copied', (tester) async {
    final opened = <Uri>[];
    LegalLinks.openOverride = (u) async => opened.add(u);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _openQueue(tester);
    await tester.tap(find.byKey(const Key('verif-lookup-biz-cr')));
    await tester.pump();
    expect(opened.map((u) => u.toString()), ['https://mc.gov.sa/cr-inquiry']);
    await tester.ensureVisible(find.byKey(const Key('verif-lookup-biz-fl')));
    await tester.tap(find.byKey(const Key('verif-lookup-biz-fl')));
    await tester.pump();
    expect(opened.last.toString(), 'https://freelance.sa/verify');
    await tester.ensureVisible(find.byKey(const Key('verif-copy-biz-cr')));
    await tester.tap(find.byKey(const Key('verif-copy-biz-cr')));
    await tester.pumpAndSettle();
    expect(copied, '4030123456');
    expect(find.text('نُسخ الرقم'), findsOneWidget);
  });

  testWidgets('filters request the chosen status; approved rows have no decision buttons and rejected rows show the reason', (tester) async {
    final srv = await _openQueue(tester);
    await tester.tap(find.byKey(const Key('verif-filter-approved')));
    await tester.pumpAndSettle();
    expect(srv.statuses.last, 'approved');
    expect(find.byKey(const Key('verif-row-biz-ok')), findsOneWidget);
    expect(find.byKey(const Key('verif-approve-biz-ok')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('verif-status-biz-ok'))).data, 'موثّقة');
    await tester.tap(find.byKey(const Key('verif-filter-rejected')));
    await tester.pumpAndSettle();
    expect(srv.statuses.last, 'rejected');
    expect(tester.widget<Text>(find.byKey(const Key('verif-reason-biz-rj'))).data, 'سبب الرفض: الرقم لا يطابق');
    await tester.tap(find.byKey(const Key('verif-filter-all')));
    await tester.pumpAndSettle();
    expect(srv.statuses.last, 'all');
    expect(find.byKey(const Key('verif-row-biz-cr')), findsOneWidget);
    // البطاقة الرابعة خارج الشاشة في القائمة الكسولة: نمرّر حتى تظهر
    await tester.scrollUntilVisible(find.byKey(const Key('verif-row-biz-rj')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('verif-row-biz-rj')), findsOneWidget);
  });

  testWidgets('the overview tile shows pending verifications in amber and opens the verification segment', (tester) async {
    String? gone;
    final srv = _Srv();
    await _pump(tester, srv, Scaffold(body: AdminOverviewPage(onGo: (k) => gone = k)));
    final tile = tester.widget<StatTile>(find.byKey(const Key('tile-verifications')));
    expect(tile.label, 'توثيق بانتظار القرار');
    expect(tile.value, '2');
    expect(tile.color, Joy.warning);
    expect(tile.hint, 'منشورة 22 · مكتملة 9 · موثّقة 4 · نشطة 1');
    await tester.tap(find.byKey(const Key('tile-verifications')));
    await tester.pump();
    expect(gone, 'biz');
    final container = ProviderScope.containerOf(tester.element(find.byType(AdminOverviewPage)));
    expect(container.read(adminBizSegmentProvider), 'verifications');
    // بلا طلبات معلّقة: رمادي
    await _pump(tester, _Srv()..pending = 0, Scaffold(body: AdminOverviewPage(onGo: (_) {})));
    expect(tester.widget<StatTile>(find.byKey(const Key('tile-verifications'))).color, Joy.textMuted);
  });
}
