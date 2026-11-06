// إقرار العمر وبيانات المنشأة (5 نوفمبر 2026): requireAdult قبل أول فعل مالي (ورقة «أقر بأن عمري 18 سنة فأكثر» برابط الشروط،
// POST /me/adult-attest، تذكّر الحالة، وتعذّر معرفتها لا يحبس)، والمعالج العام لرفض 403 adult-required من أي طلب، ونقاط الدخول
// (الشحن التجريبي في المحفظة، الطلب المدفوع في صفحة الدائرة وفي عرض السوق، والتذكرة المدفوعة، والمجاني بلا سؤال)، وإقرار 13+ في ورقة الموافقة، وبيانات المنشأة
// في «عن ناس لايف» وإعدادات الإدارة، وسطر الكيان للدائرة الموثقة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/admin_api.dart';
import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/commerce_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/require_adult.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/admin/admin_settings.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/market/listing_page.dart';
import 'package:naslook/pages/myspace/consent_sheet.dart';
import 'package:naslook/pages/myspace/myspace_page.dart';
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

/// خادم وهمي: حالة الإقرار، ومسارات صريحة، والباقي قائمة فارغة لطلبات GET و{ok} لغيرها.
class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final routes = <String, _Route>{};
  Object? adult = false; // false/true أو null (خادم أقدم بلا الحقل) أو 'error' (500)
  bool attestFails = false;
  _Srv() {
    routes['GET /notify/unread'] = (_, __) => {'unread': 0};
    routes['GET /settings/public'] = (_, __) => {'announcement': '', 'maintenance': false, 'testTopup': true, 'transfersEnabled': false, 'chatPaymentsEnabled': false};
    routes['GET /pay/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar', 'methods': [], 'min': 10000, 'max': 500000, 'currency': 'SAR'};
    routes['GET /legal/consent'] = (_, __) {
      if (adult == 'error') return _json({'error': 'boom'}, 500);
      return {'needs': false, 'version': '2026-09-25', if (adult is bool) 'adult': adult, if (adult == true) 'adultAt': '2026-11-05T10:00:00Z'};
    };
    routes['POST /me/adult-attest'] = (_, b) {
      if (attestFails) return _json({'error': 'unavailable'}, 503);
      if (b?['confirm'] != true) return _json({'error': 'confirm-required'}, 400);
      adult = true;
      return {'ok': true, 'adult': true, 'adultAt': '2026-11-05T10:00:00Z'};
    };
  }
  static http.Response _json(Object? body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

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

late ApiClient _api;

Future<ProviderContainer> _pump(WidgetTester tester, _Srv srv, Widget home, {Size size = const Size(600, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(_api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(_api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return MaterialApp(locale: const Locale('ar'), home: home);
    }),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// زر يستدعي requireAdult ويحفظ النتيجة.
class _Probe extends ConsumerWidget {
  final List<bool> results;
  const _Probe(this.results);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(body: Center(child: ElevatedButton(key: const Key('go'), onPressed: () async => results.add(await requireAdult(context, ref)), child: const Text('go'))));
}

/// غلاف يثبّت المعالج العام كما يفعل HomeShell، وزر يرسل شحناً يرفضه الخادم.
class _GateHost extends ConsumerStatefulWidget {
  const _GateHost();
  @override
  ConsumerState<_GateHost> createState() => _GateHostState();
}

class _GateHostState extends ConsumerState<_GateHost> {
  String? error;
  @override
  void initState() {
    super.initState();
    AdultGate.install(context, ref);
  }

  @override
  void dispose() {
    AdultGate.uninstall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          ElevatedButton(
            key: const Key('pay'),
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).walletTopup(5000);
              } on ApiException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('pay'),
          ),
          if (error != null) Text(error!, key: const Key('pay-error')),
        ]),
      );
}

Finder _hintContaining(String text) => find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').contains(text));

void main() {
  final opened = <Uri>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened.clear();
    LegalLinks.openOverride = (u) async => opened.add(u);
    AdultGate.resetForTests();
  });
  tearDown(() {
    LegalLinks.openOverride = null;
    AdultGate.resetForTests();
  });

  group('models', () {
    test('listingBodyPriced: price or a priced variant means selling for money', () {
      expect(listingBodyPriced({'price': 0}), isFalse);
      expect(listingBodyPriced({'price': 2500}), isTrue);
      expect(listingBodyPriced({'price': 0, 'variants': [{'name': 'كبير', 'price': 0}]}), isFalse);
      expect(listingBodyPriced({'price': 0, 'variants': [{'name': 'كبير', 'price': 3000}]}), isTrue);
      expect(listingBodyPriced({}), isFalse);
    });

    test('BizEntity: parsed only for a known kind with a number; label per kind', () {
      expect(BizEntity.tryParse({'kind': 'cr', 'number': '4030111222'})?.label, 'سجل تجاري رقم 4030111222');
      expect(BizEntity.tryParse({'kind': 'freelance', 'number': 'FL20250077'})?.label, 'وثيقة عمل حر رقم FL20250077');
      expect(BizEntity.tryParse({'kind': 'passport', 'number': '1'}), isNull);
      expect(BizEntity.tryParse({'kind': 'cr', 'number': ''}), isNull);
      expect(BizEntity.tryParse(null), isNull);
      expect(Biz.fromJson({'id': 'b', 'name': 'B', 'category': 'shop', 'lat': 1, 'lng': 2, 'entity': {'kind': 'cr', 'number': '4030111222'}}).entity?.number, '4030111222');
      expect(Biz.fromJson({'id': 'b', 'name': 'B', 'category': 'shop', 'lat': 1, 'lng': 2}).entity, isNull, reason: 'ردود قديمة بلا الحقل');
    });

    test('settings parse the company identity (empty by default)', () {
      expect(PublicSettings.fromJson(const {}).companyCr, '');
      final p = PublicSettings.fromJson(const {'companyCr': '4030000001', 'companyVat': '310000000000003', 'companyAddress': 'حي الروضة، جدة'});
      expect([p.companyCr, p.companyVat, p.companyAddress], ['4030000001', '310000000000003', 'حي الروضة، جدة']);
      expect(AdminSettings.fromJson(const {'companyVat': '310000000000003'}).companyVat, '310000000000003');
    });
  });

  group('requireAdult', () {
    testWidgets('attested account passes without a sheet, and the state is remembered', (tester) async {
      final srv = _Srv()..adult = true;
      final results = <bool>[];
      await _pump(tester, srv, _Probe(results));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(results, [true, true]);
      expect(srv.calls.where((c) => c == 'GET /legal/consent').length, 1, reason: 'الإقرار لا يُسحب فلا يُسأل الخادم مرة ثانية');
    });

    testWidgets('unattested: the sheet links to the terms and «أقر» records the declaration once', (tester) async {
      final srv = _Srv();
      final results = <bool>[];
      await _pump(tester, srv, _Probe(results));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      expect(find.text('أقر بأن عمري 18 سنة فأكثر'), findsOneWidget);
      expect(find.byKey(const Key('adult-retry-note')), findsNothing);
      await tester.tap(find.byKey(const Key('adult-terms')));
      await tester.pump();
      expect(opened.single.path, '/terms');
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(srv.bodies['POST /me/adult-attest'], {'confirm': true, 'source': 'app'});
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(results, [true, true]);
      expect(srv.calls.where((c) => c == 'POST /me/adult-attest').length, 1);
      expect(srv.calls.where((c) => c == 'GET /legal/consent').length, 1);
    });

    testWidgets('«ليس الآن» returns false and records nothing', (tester) async {
      final srv = _Srv();
      final results = <bool>[];
      await _pump(tester, srv, _Probe(results));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adult-cancel')));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(srv.calls, isNot(contains('POST /me/adult-attest')));
    });

    testWidgets('unknown state (server error or an older server) never blocks: the server stays the judge', (tester) async {
      final srv = _Srv()..adult = 'error';
      final results = <bool>[];
      await _pump(tester, srv, _Probe(results));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      srv.adult = null; // ردّ بلا الحقل
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(results, [true, true]);
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
    });

    testWidgets('a failed attest shows the error and does not continue', (tester) async {
      final srv = _Srv()..attestFails = true;
      final results = <bool>[];
      await _pump(tester, srv, _Probe(results));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(results, [false]);
      expect(find.text('هذه الخدمة غير متاحة حالياً'), findsOneWidget);
    });
  });

  group('generic handler', () {
    testWidgets('403 adult-required from any request opens the same sheet; after «أقر» the user is told to retry', (tester) async {
      final srv = _Srv();
      srv.routes['POST /wallet/topup'] = (_, __) => srv.adult == true ? {'ok': true} : _Srv._json({'error': 'adult-required'}, 403);
      await _pump(tester, srv, const _GateHost());
      await tester.tap(find.byKey(const Key('pay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pay-error')), findsOneWidget);
      expect(find.text('هذه العملية لمن عمره 18 سنة فأكثر؛ أكّد عمرك ثم أعد المحاولة'), findsOneWidget);
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      expect(find.byKey(const Key('adult-retry-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(srv.bodies['POST /me/adult-attest']?['confirm'], isTrue);
      expect(find.text('تم تأكيد عمرك. أعد المحاولة الآن'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      // إعادة المحاولة تمر
      await tester.tap(find.byKey(const Key('pay')));
      await tester.pumpAndSettle();
      expect(srv.calls.where((c) => c == 'POST /wallet/topup').length, 2);
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
    });

    testWidgets('uninstalled handler: the error still surfaces but no sheet opens', (tester) async {
      final srv = _Srv();
      srv.routes['POST /wallet/topup'] = (_, __) => _Srv._json({'error': 'adult-required'}, 403);
      await _pump(tester, srv, const Scaffold(body: SizedBox()));
      Object? err;
      try {
        await _api.walletTopup(5000);
      } catch (e) {
        err = e;
      }
      await tester.pumpAndSettle();
      expect(err, isA<ApiException>());
      expect(ApiClient.onAdultRequired, isNull);
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
    });
  });

  group('entry points', () {
    Map<String, dynamic> wallet() => {'balance': 0, 'points': 0, 'currency': 'SAR', 'upcomingTickets': 0, 'recent': [], 'testTopup': true, 'maxTopup': 500000};

    testWidgets('wallet test top-up asks for the declaration before the amount', (tester) async {
      final srv = _Srv();
      srv.routes['GET /wallet'] = (_, __) => wallet();
      await _pump(tester, srv, const WalletPage(), size: const Size(600, 1500));
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      expect(_hintContaining('5000 ر.س'), findsNothing, reason: 'لا نموذج مبلغ قبل الإقرار');
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pumpAndSettle();
      expect(_hintContaining('5000 ر.س'), findsOneWidget);
      await tester.enterText(_hintContaining('5000 ر.س'), '100');
      await tester.tap(find.text('شحن').last);
      await tester.pumpAndSettle();
      expect(srv.bodies['POST /wallet/topup'], {'amount': 10000});
    });

    testWidgets('declining stops the top-up', (tester) async {
      final srv = _Srv();
      srv.routes['GET /wallet'] = (_, __) => wallet();
      await _pump(tester, srv, const WalletPage(), size: const Size(600, 1500));
      await tester.tap(find.byKey(const Key('wallet-test-topup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adult-cancel')));
      await tester.pumpAndSettle();
      expect(_hintContaining('5000 ر.س'), findsNothing);
      expect(srv.calls, isNot(contains('POST /wallet/topup')));
    });

    Map<String, dynamic> biz({Map<String, dynamic>? entity, List<Map<String, dynamic>> items = const []}) => {
          'id': 'biz-shop', 'name': 'Shop', 'nameAr': 'متجر الحي', 'category': 'shop', 'sector': '', 'description': 'وصف', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '9-5',
          'verified': true, 'canSell': true, 'verificationStatus': 'approved', 'followers': 0, 'ratingCount': 0, 'itemsCount': items.length, 'items': items, 'reviews': [], 'myOrders': [],
          if (entity != null) 'entity': entity,
        };

    Map<String, dynamic> item(String id, String title, int price) => {'id': id, 'bizId': 'biz-shop', 'kind': 'product', 'title': title, 'description': '', 'price': price, 'unit': 'item', 'stock': 5, 'meta': {}};
    _Route orderOk() => (_, b) => {'id': 'o1', 'bizId': 'biz-shop', 'itemId': b?['itemId'], 'title': 'x', 'kind': 'product', 'qty': 1, 'units': 1, 'total': 0, 'status': 'confirmed', 'code': 'NAS-1', 'meta': {}, 'createdAt': '2026-11-05T10:00:00Z', 'cancellable': true};
    Future<void> buy(WidgetTester tester) async {
      await tester.ensureVisible(find.text('اشترِ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اشترِ'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ادفع'));
      await tester.pumpAndSettle();
    }

    testWidgets('approved circle shows its commercial registration; a paid item asks for the declaration first', (tester) async {
      final srv = _Srv();
      srv.routes['GET /biz/biz-shop'] = (_, __) => biz(entity: {'kind': 'cr', 'number': '4030111222'}, items: [item('it-paid', 'حقيبة', 2500)]);
      srv.routes['POST /biz/biz-shop/orders'] = orderOk();
      await _pump(tester, srv, const BusinessPage(id: 'biz-shop'), size: const Size(800, 2600));
      expect(find.byKey(const Key('info-entity')), findsOneWidget);
      expect(find.text('سجل تجاري رقم 4030111222'), findsOneWidget);
      await buy(tester);
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adult-cancel')));
      await tester.pumpAndSettle();
      expect(srv.bodies['POST /biz/biz-shop/orders'], isNull, reason: 'رفض الإقرار لا يرسل الطلب');
      await buy(tester);
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pumpAndSettle();
      expect(srv.calls.indexOf('POST /me/adult-attest'), lessThan(srv.calls.indexOf('POST /biz/biz-shop/orders')));
      expect(srv.bodies['POST /biz/biz-shop/orders']?['itemId'], 'it-paid');
    });

    testWidgets('a free item is ordered without the declaration', (tester) async {
      final srv = _Srv();
      srv.routes['GET /biz/biz-shop'] = (_, __) => biz(items: [item('it-free', 'هدية', 0)]);
      srv.routes['POST /biz/biz-shop/orders'] = orderOk();
      await _pump(tester, srv, const BusinessPage(id: 'biz-shop'), size: const Size(800, 2600));
      await buy(tester);
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
      expect(srv.calls, isNot(contains('GET /legal/consent')));
      expect(srv.bodies['POST /biz/biz-shop/orders']?['itemId'], 'it-free');
    });

    testWidgets('a circle without an approved entity shows no entity row', (tester) async {
      final srv = _Srv();
      srv.routes['GET /biz/biz-shop'] = (_, __) => biz();
      await _pump(tester, srv, const BusinessPage(id: 'biz-shop'), size: const Size(800, 2600));
      expect(find.byKey(const Key('info-entity')), findsNothing);
    });

    const lid = '11111111-1111-4111-8111-111111111111';
    Map<String, dynamic> listing(int price) => {
          'id': lid, 'seller': {'id': 'SA0000002', 'nickname': 'sara', 'avatarUrl': null}, 'sellerRating': null, 'sellerRatingCount': 0, 'sellerBadges': [], 'kind': 'product', 'category': 'other',
          'title': 'سماعة', 'description': 'جديدة', 'price': price, 'imageUrl': null, 'images': [], 'placeName': 'الروضة', 'city': 'جدة', 'lat': 21.5, 'lng': 39.1, 'status': 'active', 'stock': null, 'sold': 0,
          'views': 1, 'variants': [], 'availability': null, 'spotlight': false, 'mine': false, 'createdAt': '2026-11-05T08:00:00Z',
        };

    testWidgets('market listing: a paid order asks for the declaration before the note to the seller', (tester) async {
      final srv = _Srv();
      srv.routes['GET /market/$lid'] = (_, __) => listing(2500);
      srv.routes['POST /market/$lid/order'] = (_, __) => {'ok': true, 'id': 'o1', 'total': 2500, 'discount': 0, 'commission': 0, 'code': '4321'};
      await _pump(tester, srv, const ListingPage(lid), size: const Size(600, 2000));
      await tester.tap(find.byKey(const Key('order-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      expect(find.text('ملاحظة للبائع'), findsNothing, reason: 'الإقرار قبل أن يكتب المشتري شيئاً');
      await tester.tap(find.byKey(const Key('adult-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('ملاحظة للبائع'), findsOneWidget);
      await tester.tap(find.text('تأكيد الطلب'));
      await tester.pumpAndSettle();
      expect(srv.calls.indexOf('POST /me/adult-attest'), lessThan(srv.calls.indexOf('POST /market/$lid/order')));
    });

    testWidgets('market listing: a free order goes straight to the note', (tester) async {
      final srv = _Srv();
      srv.routes['GET /market/$lid'] = (_, __) => listing(0);
      await _pump(tester, srv, const ListingPage(lid), size: const Size(600, 2000));
      await tester.tap(find.byKey(const Key('order-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
      expect(find.text('ملاحظة للبائع'), findsOneWidget);
      expect(srv.calls, isNot(contains('GET /legal/consent')));
    });

    Map<String, dynamic> event() => {
          'id': 'ev1', 'title': 'حفلة', 'description': '', 'host': {'id': 'SA0000002', 'nickname': 'sara'}, 'placeName': 'المسرح', 'startsAt': '2026-12-01T18:00:00Z', 'isHost': false, 'going': 0, 'myTickets': 0,
          'tiers': [
            {'id': 't-paid', 'name': 'عادي', 'description': '', 'price': 1500, 'quantity': 10, 'sold': 0, 'left': 10},
            {'id': 't-free', 'name': 'مجانية', 'description': '', 'price': 0, 'quantity': 10, 'sold': 0, 'left': 10},
          ],
        };

    testWidgets('event: a paid ticket asks for the declaration; declining sends nothing', (tester) async {
      final srv = _Srv();
      srv.routes['GET /events/ev1'] = (_, __) => event();
      await _pump(tester, srv, const EventDetailPage(eventId: 'ev1'), size: const Size(600, 1600));
      await tester.tap(find.textContaining('ادفع'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adult-cancel')));
      await tester.pumpAndSettle();
      expect(srv.calls, isNot(contains('POST /events/ev1/tickets')));
    });

    testWidgets('event: a free ticket is booked without the declaration', (tester) async {
      final srv = _Srv();
      srv.routes['GET /events/ev1'] = (_, __) => event();
      srv.routes['POST /events/ev1/tickets'] = (_, __) => {'data': []};
      await _pump(tester, srv, const EventDetailPage(eventId: 'ev1'), size: const Size(600, 1600));
      await tester.tap(find.text('احجز'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adult-sheet')), findsNothing);
      expect(srv.bodies['POST /events/ev1/tickets']?['tierId'], 't-free');
      expect(srv.calls, isNot(contains('GET /legal/consent')));
    });
  });

  group('legal identity and the 13+ declaration', () {
    testWidgets('consent sheet carries the 13+ declaration', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () => ConsentSheet.show(ctx), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consent-age')), findsOneWidget);
      expect(find.textContaining('وأقر أن عمري 13 سنة فأكثر'), findsOneWidget);
    });

    void mySpaceRoutes(_Srv srv) {
      srv.routes['GET /me'] = (_, __) => {'id': 'SA0000001', 'nickname': 'amr'};
      srv.routes['GET /me/profile'] = (_, __) => {'id': 'SA0000001', 'nickname': 'amr', 'isPublic': true};
      srv.routes['GET /me/map-presence'] = (_, __) => {'lat': null, 'lng': null, 'visible': false, 'title': ''};
      srv.routes['GET /me/recovery'] = (_, __) => {'enabled': true, 'email': 'amr@example.com', 'verified': true, 'mailConfigured': true};
      srv.routes['GET /me/login-email'] = (_, __) => {'email': 'amr@example.com', 'verified': true, 'mailConfigured': true};
    }

    testWidgets('«عن ناس لايف» shows the company name always and the CR, VAT and address when set', (tester) async {
      final srv = _Srv();
      mySpaceRoutes(srv);
      srv.routes['GET /settings/public'] = (_, __) => {'announcement': '', 'companyCr': '4030000001', 'companyVat': '310000000000003', 'companyAddress': 'حي الروضة، جدة'};
      await _pump(tester, srv, const Scaffold(body: MySpacePage()), size: const Size(420, 1400));
      await tester.scrollUntilVisible(find.byKey(const Key('about-company')), 300);
      final tile = find.byKey(const Key('about-company'));
      expect(find.descendant(of: tile, matching: find.text('شركة أريب الرقمية')), findsOneWidget);
      final sub = tester.widget<Text>(find.descendant(of: tile, matching: find.textContaining('Areeb Alraqmiah Company'))).data!;
      expect(sub, contains('سجل تجاري رقم 4030000001'));
      expect(sub, contains('الرقم الضريبي 310000000000003'));
      expect(sub, contains('العنوان الوطني: حي الروضة، جدة'));
    });

    testWidgets('«عن ناس لايف» without the identity shows only the legal name', (tester) async {
      final srv = _Srv();
      mySpaceRoutes(srv);
      await _pump(tester, srv, const Scaffold(body: MySpacePage()), size: const Size(420, 1400));
      await tester.scrollUntilVisible(find.byKey(const Key('about-company')), 300);
      final sub = tester.widget<Text>(find.descendant(of: find.byKey(const Key('about-company')), matching: find.textContaining('Areeb Alraqmiah Company'))).data!;
      expect(sub, 'Areeb Alraqmiah Company');
    });

    Future<void> save(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.byKey(const Key('set-save')), 400, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byKey(const Key('set-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('set-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('admin settings edit the company identity and explain a bad CR', (tester) async {
      final srv = _Srv();
      srv.routes['GET /adminapi/settings'] = (_, __) => {'testTopup': false, 'maxTopup': 100000, 'minTopup': 10000, 'maxCardTopup': 500000, 'companyCr': '4030000001', 'companyVat': '', 'companyAddress': ''};
      srv.routes['GET /adminapi/payments/config'] = (_, __) => {'enabled': false, 'provider': 'moyasar'};
      await _pump(tester, srv, const Scaffold(body: AdminSettingsPage()), size: const Size(600, 3600));
      await tester.scrollUntilVisible(find.byKey(const Key('set-company-cr')), 300, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<TextField>(find.byKey(const Key('set-company-cr'))).controller!.text, '4030000001');
      await tester.enterText(find.byKey(const Key('set-company-vat')), '310000000000003');
      await tester.enterText(find.byKey(const Key('set-company-address')), 'RRRD2929، حي الروضة، جدة');
      await save(tester);
      final b = srv.bodies['POST /adminapi/settings']!;
      expect([b['companyCr'], b['companyVat'], b['companyAddress']], ['4030000001', '310000000000003', 'RRRD2929، حي الروضة، جدة']);
      srv.routes['POST /adminapi/settings'] = (_, __) => _Srv._json({'error': 'bad-cr'}, 400);
      await save(tester);
      expect(find.text('رقم السجل التجاري 10 أرقام'), findsOneWidget);
    });
  });
}
