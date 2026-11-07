// ماسح رموز QR (نوفمبر 2026): الفكّ بـ zxing2 (رموز qr_flutter نفسها التي يعرضها العميل)، قراءة الرموز، ورقة المسح بكاميرا
// بديلة (QrCamera.factoryOverride) ورفض الإذن والتقاط الصورة حيث لا كاميرا حية، ومسارات الاستلام الثلاثة: الدائرة (مسح ← ملخص ← تأكيد)،
// بوابة الفعالية مع «امسح التالي» وقائمة الحضور، وتسليم السوق برمز المشتري.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/pages/business/owner/dashboard_orders.dart';
import 'package:naslook/pages/events/events_page.dart';
import 'package:naslook/pages/market/orders_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/qr_scanner.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// كاميرا بديلة: كل محاولة مسح تأخذ أول ما في [queue]؛ [startError] يحاكي رفض الإذن.
class _FakeCam implements QrCamera {
  final queue = <String?>[];
  final Object? startError;
  bool torch = false, disposed = false, started = false;
  _FakeCam({this.startError});
  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    started = true;
  }
  @override
  Widget view() => const ColoredBox(key: Key('fake-cam'), color: Colors.black);
  @override
  Future<String?> scan() async => queue.isEmpty ? null : queue.removeAt(0);
  @override
  bool get torchAvailable => true;
  @override
  bool get torchOn => torch;
  @override
  Future<void> setTorch(bool on) async => torch = on;
  @override
  void dispose() => disposed = true;
}

/// رمز QR مرسوم ببكسلات رمادية (هامش أربع وحدات) من مُرمّز zxing2.
({Uint8List gray, int w, int h}) _qrGray(String text, {int scale = 4, bool invert = false}) {
  final m = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  final n = m.width, side = (n + 8) * scale;
  final gray = Uint8List(side * side)..fillRange(0, side * side, invert ? 0 : 255);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (m.get(x, y) != 1) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          gray[((y + 4) * scale + dy) * side + (x + 4) * scale + dx] = invert ? 255 : 0;
        }
      }
    }
  }
  return (gray: gray, w: side, h: side);
}

Uint8List _qrPng(String text) {
  final q = _qrGray(text, scale: 6);
  final im = img.Image(width: q.w, height: q.h);
  for (var y = 0; y < q.h; y++) {
    for (var x = 0; x < q.w; x++) {
      final v = q.gray[y * q.w + x];
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final Future<http.Response?> Function(String key, http.Request req) route;
  _Srv(this.route);
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if (req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    final r = await route(key, req);
    if (r != null) return r;
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key.startsWith('GET /wishlist')) return _json({'saved': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _settle(tester);
}

/// ورقة المسح وحدها: زر يفتحها ويحفظ ما تعيده.
class _Opener extends StatefulWidget {
  const _Opener();
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  String? result = 'none';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          FilledButton(key: const Key('open'), onPressed: () async { final r = await showQrScanSheet(context, title: 'تأكيد الاستلام', manualHint: 'NAS-…', check: checkVenueCode); setState(() => result = r); }, child: const Text('افتح')),
          Text('result:$result', key: const Key('result')),
        ]),
      );
}

String _result(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('result'))).data!;

void main() {
  tearDown(() {
    QrCamera.factoryOverride = null;
    pickImageOverride = null;
    decodeQrImageOverride = null;
    openAppSettingsOverride = null;
  });

  group('decoder', () {
    test('zxing2 reads a ticket code from luminance, an encoded PNG, and an inverted code', () {
      final q = _qrGray('NAS-1A2B3C4D');
      expect(decodeQrLuminance(q.gray, q.w, q.h), 'NAS-1A2B3C4D');
      expect(decodeQrEncodedSync(_qrPng('naslife:market:22222222-2222-4222-8222-222222222222:4321')), 'naslife:market:22222222-2222-4222-8222-222222222222:4321');
      final inv = _qrGray('NAS-FFFF0000', invert: true);
      expect(decodeQrLuminance(inv.gray, inv.w, inv.h), isNull, reason: 'إطارات الكاميرا تكتفي بالمحاولة السريعة');
      expect(decodeQrLuminance(inv.gray, inv.w, inv.h, thorough: true), 'NAS-FFFF0000', reason: 'الصورة الثابتة تجرّب الرمز المعكوس');
      final rgba = Uint8List(q.w * q.h * 4);
      for (var i = 0; i < q.w * q.h; i++) {
        rgba.fillRange(i * 4, i * 4 + 3, q.gray[i]);
        rgba[i * 4 + 3] = 255;
      }
      expect(decodeQrRgba(rgba, q.w, q.h), 'NAS-1A2B3C4D');
      expect(decodeQrLuminance(Uint8List(100 * 100)..fillRange(0, 10000, 255), 100, 100), isNull, reason: 'صورة بلا رمز');
      expect(decodeQrEncodedSync(Uint8List.fromList([1, 2, 3])), isNull, reason: 'بايتات ليست صورة');
    });

    testWidgets('the QR that qr_flutter draws for the customer decodes back to the same text', (tester) async {
      const data = 'naslife:market:22222222-2222-4222-8222-222222222222:4321';
      await tester.pumpWidget(MaterialApp(home: Center(child: RepaintBoundary(key: const Key('qr'), child: Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: data, size: 220))))));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('qr')));
      final out = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return decodeQrRgba(bytes!.buffer.asUint8List(), image.width, image.height, thorough: true);
      });
      expect(out, data);
      expect(checkMarketCode(out!, orderId: '22222222-2222-4222-8222-222222222222', scanned: true).code, '4321');
    });
  });

  group('code checks', () {
    test('venue codes: scanned text must carry NAS-…, typed text is upper-cased', () {
      expect(checkVenueCode('nas-1a2b3c4d', scanned: true).code, 'NAS-1A2B3C4D');
      expect(checkVenueCode('https://naslife.app/t/NAS-1A2B3C4D', scanned: true).code, 'NAS-1A2B3C4D');
      expect(checkVenueCode('https://example.com', scanned: true).error, 'هذا ليس رمز حجز أو تذكرة من ناس لايف');
      expect(checkVenueCode(' abc ', scanned: false).code, 'ABC');
      expect(checkVenueCode('1a2b3c4d', scanned: false).code, 'NAS-1A2B3C4D', reason: 'الخانات الثماني وحدها');
      expect(checkVenueCode('  ', scanned: false).error, 'اكتب الرمز');
    });
    test('market codes: four digits (Arabic digits too) or the QR for this very order', () {
      const id = '22222222-2222-4222-8222-222222222222';
      expect(checkMarketCode('٤٣٢١', orderId: id, scanned: false).code, '4321');
      expect(checkMarketCode(marketQrData(id, '4321'), orderId: id, scanned: true).code, '4321');
      expect(checkMarketCode(marketQrData('33333333-3333-4333-8333-333333333333', '4321'), orderId: id, scanned: true).error, 'هذا رمز طلب آخر، لا هذا الطلب');
      expect(checkMarketCode('NAS-1A2B3C4D', orderId: id, scanned: true).error, 'هذا ليس رمز استلام من ناس لايف');
      expect(checkMarketCode('12ab', orderId: id, scanned: false).error, 'الرمز أرقام فقط');
    });
  });

  group('scan sheet', () {
    testWidgets('live camera: a foreign QR is refused in place, the right one closes the sheet; torch toggles; camera released', (tester) async {
      final cam = _FakeCam();
      QrCamera.factoryOverride = () => cam;
      await _pump(tester, _Srv((_, __) async => null), const _Opener());
      await _tap(tester, find.byKey(const Key('open')));
      expect(cam.started, isTrue);
      expect(find.byKey(const Key('fake-cam')), findsOneWidget);
      expect(find.byKey(const Key('qr-live')), findsOneWidget);
      expect(find.byKey(const Key('qr-manual')), findsOneWidget, reason: 'الإدخال اليدوي في الورقة نفسها');
      await _tap(tester, find.byKey(const Key('qr-torch')));
      expect(cam.torch, isTrue);
      cam.queue.add('https://example.com/menu');
      await _settle(tester);
      expect(find.text('هذا ليس رمز حجز أو تذكرة من ناس لايف'), findsOneWidget);
      expect(find.byKey(const Key('qr-title')), findsOneWidget, reason: 'الورقة باقية');
      cam.queue.add('NAS-1A2B3C4D');
      await _settle(tester);
      expect(find.byKey(const Key('qr-title')), findsNothing);
      expect(_result(tester), 'result:NAS-1A2B3C4D');
      expect(cam.disposed, isTrue);
    });

    testWidgets('permission denied: clear Arabic help, open settings, and manual entry still works', (tester) async {
      var opened = 0;
      openAppSettingsOverride = () async => opened++;
      QrCamera.factoryOverride = () => _FakeCam(startError: const MediaPermissionDenied('camera'));
      await _pump(tester, _Srv((_, __) async => null), const _Opener());
      await _tap(tester, find.byKey(const Key('open')));
      expect(find.byKey(const Key('qr-denied')), findsOneWidget);
      expect(find.text('لا إذن للكاميرا'), findsOneWidget);
      expect(find.textContaining('فعّلها'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('qr-open-settings')));
      expect(opened, 1);
      await tester.enterText(find.byKey(const Key('qr-manual')), 'nas-9z9z');
      await _tap(tester, find.byKey(const Key('qr-manual-go')));
      expect(_result(tester), 'result:NAS-9Z9Z');
    });

    testWidgets('no live camera (iOS app): a photo of the code is decoded with zxing2; a blurry photo asks again', (tester) async {
      var shots = 0;
      pickImageOverride = ({bool camera = false}) async {
        shots++;
        expect(camera, isTrue);
        return shots == 1 ? (bytes: _qrPng('hello'), mime: 'image/png', name: 'x.png') : (bytes: _qrPng('NAS-5EED1234'), mime: 'image/png', name: 'q.png');
      };
      await _pump(tester, _Srv((_, __) async => null), const _Opener());
      await _tap(tester, find.byKey(const Key('open')));
      expect(find.byKey(const Key('qr-still')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('qr-photo')));
      expect(find.text('هذا ليس رمز حجز أو تذكرة من ناس لايف'), findsOneWidget);
      decodeQrImageOverride = (_) async => null;
      await _tap(tester, find.byKey(const Key('qr-photo')));
      expect(find.byKey(const Key('qr-error')), findsOneWidget);
      expect(find.textContaining('لم نجد رمزاً واضحاً'), findsOneWidget);
      decodeQrImageOverride = null;
      await _tap(tester, find.byKey(const Key('qr-photo')));
      expect(_result(tester), 'result:NAS-5EED1234');
      expect(shots, 3);
    });

    testWidgets('a photo refused by the system shows the permission help', (tester) async {
      pickImageOverride = ({bool camera = false}) async => throw const MediaPermissionDenied('camera');
      await _pump(tester, _Srv((_, __) async => null), const _Opener());
      await _tap(tester, find.byKey(const Key('open')));
      await _tap(tester, find.byKey(const Key('qr-photo')));
      expect(find.byKey(const Key('qr-denied')), findsOneWidget);
    });
  });

  group('circle check-in', () {
    Map<String, dynamic> biz() => {
          'id': 'biz-shop', 'name': 'Shop', 'nameAr': 'متجر لمسة', 'category': 'shop', 'sector': '', 'description': '', 'lat': 21.5, 'lng': 39.2, 'address': 'جدة', 'hours': '', 'color': '#0058A3', 'highlights': [],
          'verified': true, 'official': false, 'active': true, 'ownerId': 'SA0000001', 'myRole': 'owner', 'followers': 0, 'itemsCount': 0, 'items': [], 'reviews': [], 'posts': [], 'myOrders': [], 'verificationStatus': 'approved', 'canSell': true,
        };
    Map<String, dynamic> order(String code, {String status = 'confirmed'}) => {
          'id': 'o-$code', 'bizId': 'biz-shop', 'bizNameAr': 'متجر لمسة', 'category': 'shop', 'itemId': 'oil', 'title': 'زيت شعر', 'kind': 'product', 'qty': 1, 'units': 1, 'total': 5000, 'status': status, 'code': code, 'note': '', 'meta': {},
          'createdAt': DateTime.now().toUtc().toIso8601String(), 'payment': 'wallet', 'paid': true, 'funds': 'held', 'customer': {'id': 'SA0000002', 'nickname': 'sara'},
          if (status == 'used') 'usedAt': DateTime.now().toUtc().toIso8601String(),
        };
    _Srv server() => _Srv((key, req) async {
          if (key == 'GET /biz/biz-shop/orders') {
            final q = req.url.queryParameters['q'] ?? '';
            return _json([order('NAS-ABCD1234'), order('NAS-USED0001', status: 'used')].where((o) => (o['code'] as String).contains(q)).toList());
          }
          if (key == 'GET /biz/biz-shop/stats') return _json({'orders': {'total': 1}, 'revenue': {'total': 0}, 'byKind': [], 'daily': [], 'topItems': []});
          if (key == 'POST /biz/biz-shop/checkin') return _json(order('NAS-ABCD1234', status: 'used'));
          return null;
        });

    testWidgets('scan → order summary → confirm calls the same check-in, then «امسح التالي» reopens the camera', (tester) async {
      final cams = <_FakeCam>[];
      QrCamera.factoryOverride = () { final c = _FakeCam(); cams.add(c); return c; };
      final srv = server();
      await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(biz()))));
      expect(find.text('مسح رمز الاستلام'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
      await _tap(tester, find.byKey(const Key('orders-checkin-code')));
      cams.last.queue.add('NAS-ABCD1234');
      await _settle(tester);
      expect(srv.calls, contains('GET /biz/biz-shop/orders?q=NAS-ABCD1234'));
      expect(find.byKey(const Key('order-summary')), findsOneWidget);
      expect(find.text('sara'), findsWidgets);
      expect(find.text('زيت شعر'), findsWidgets);
      expect(srv.calls.where((c) => c == 'POST /biz/biz-shop/checkin'), isEmpty, reason: 'لا تأكيد قبل الضغط');
      await _tap(tester, find.byKey(const Key('scan-confirm')));
      expect(srv.bodies['POST /biz/biz-shop/checkin'], {'code': 'NAS-ABCD1234'});
      expect(find.byKey(const Key('scan-ok')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('scan-next')));
      expect(find.byKey(const Key('qr-title')), findsOneWidget);
      expect(cams.length, 2);
    });

    testWidgets('a used code or a code of another circle is shown, not confirmable', (tester) async {
      final cam = _FakeCam();
      QrCamera.factoryOverride = () => cam;
      final srv = server();
      await _pump(tester, srv, Scaffold(body: OrdersTab(biz: Biz.fromJson(biz()))));
      await _tap(tester, find.byKey(const Key('orders-checkin-code')));
      cam.queue.add('NAS-USED0001');
      await _settle(tester);
      expect(find.byKey(const Key('scan-warning')), findsOneWidget);
      expect(find.textContaining('استُخدم هذا الرمز من قبل'), findsOneWidget);
      expect(find.byKey(const Key('scan-confirm')), findsNothing);
      await _tap(tester, find.byKey(const Key('scan-rescan')));
      cam.queue.add('NAS-0THER999');
      await _settle(tester);
      expect(find.text('لا طلب بهذا الرمز في هذه الدائرة'), findsOneWidget);
      expect(find.byKey(const Key('scan-confirm')), findsNothing);
      await _tap(tester, find.byKey(const Key('scan-done')));
      expect(srv.calls.where((c) => c.startsWith('POST /biz/biz-shop/checkin')), isEmpty);
    });
  });

  group('event host', () {
    const evId = '55555555-5555-4555-8555-555555555555';
    Map<String, dynamic> event() => {
          'id': evId, 'host': {'id': 'SA0000001', 'nickname': 'amr'}, 'title': 'أمسية القراءة', 'description': '', 'startsAt': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(), 'placeName': 'مكتبة الحي',
          'cancelled': false, 'isHost': true, 'going': 3, 'myTickets': 0, 'tiers': [{'id': 't1', 'name': 'عادي', 'price': 0, 'quantity': 50, 'sold': 3, 'left': 47}],
        };
    Map<String, dynamic> att(String id, String nick, {bool inside = false, String tier = 'عادي', String? code}) => {
          'ticketId': id, 'holder': {'id': 'SA000000${id.length}', 'nickname': nick, 'avatarUrl': null}, 'tier': tier, 'status': inside ? 'used' : 'valid', 'checkedIn': inside,
          'checkedInAt': inside ? DateTime.now().toUtc().toIso8601String() : null, 'boughtAt': DateTime.now().toUtc().toIso8601String(), 'paid': 0, if (code != null) 'code': code,
        };
    _Srv server({List<String> used = const []}) {
      final inside = {...used};
      return _Srv((key, req) async {
        if (key == 'GET /events/$evId') return _json(event());
        if (key == 'GET /events/$evId/attendees') {
          final q = req.url.queryParameters;
          final code = q['code'];
          if (code != null) return _json({'items': [if (code == 'NAS-AAAA0001') att('k1', 'رنا', inside: inside.contains(code), code: code)], 'next': null, 'total': 3, 'checkedIn': inside.length, 'people': 3});
          if (q['status'] == 'in') return _json({'items': [att('k2', 'bandar', inside: true, tier: 'كبار الزوار')], 'next': null, 'total': 3, 'checkedIn': 1, 'people': 3});
          if (q['cursor'] == 'c2') return _json({'items': [att('k3', 'colin')], 'next': null, 'total': 3, 'checkedIn': 1, 'people': 3});
          return _json({'items': [att('k1', 'رنا'), att('k2', 'bandar', inside: true, tier: 'كبار الزوار')], 'next': 'c2', 'total': 3, 'checkedIn': 1, 'people': 3});
        }
        if (key == 'POST /events/$evId/checkin') { inside.add('NAS-AAAA0001'); return _json({'ok': true, 'holder': {'id': 'SA0000002', 'nickname': 'رنا'}}); }
        return null;
      });
    }

    testWidgets('attendee list: counts, names, tier and in/out, filter and «عرض المزيد»', (tester) async {
      final srv = server();
      await _pump(tester, srv, const EventDetailPage(eventId: evId));
      expect(find.text('مسح التذاكر عند الدخول'), findsOneWidget);
      expect(find.text('دخل 1 من 3'), findsOneWidget);
      expect(find.byKey(const Key('attendee-k1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('attendee-k1')), matching: find.text('عادي · لم يدخل بعد')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('attendee-k2')), matching: find.textContaining('كبار الزوار · دخل')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('attendees-more')));
      expect(srv.calls.any((c) => c.contains('/attendees') && c.contains('cursor=c2')), isTrue);
      expect(find.byKey(const Key('attendee-k3')), findsOneWidget);
      expect(find.byKey(const Key('attendees-more')), findsNothing);
      await _tap(tester, find.byKey(const Key('att-filter-in')));
      expect(srv.calls.any((c) => c.contains('/attendees') && c.contains('status=in')), isTrue);
      expect(find.byKey(const Key('attendee-k1')), findsNothing);
      expect(find.byKey(const Key('attendee-k2')), findsOneWidget);
    });

    testWidgets('gate: scan → ticket summary → confirm entry; next scan of the same ticket says it is already in', (tester) async {
      final cams = <_FakeCam>[];
      QrCamera.factoryOverride = () { final c = _FakeCam(); cams.add(c); return c; };
      final srv = server();
      await _pump(tester, srv, const EventDetailPage(eventId: evId));
      await _tap(tester, find.byKey(const Key('event-checkin-code')));
      cams.last.queue.add('NAS-AAAA0001');
      await _settle(tester);
      expect(srv.calls, contains('GET /events/$evId/attendees?code=NAS-AAAA0001&limit=1'));
      expect(find.byKey(const Key('ticket-summary')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('ticket-summary')), matching: find.text('رنا')), findsOneWidget);
      expect(find.text('لم يدخل بعد'), findsWidgets);
      await _tap(tester, find.byKey(const Key('scan-confirm')));
      expect(srv.bodies['POST /events/$evId/checkin'], {'code': 'NAS-AAAA0001'});
      expect(find.text('تذكرة صالحة · رنا'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('scan-next')));
      cams.last.queue.add('NAS-AAAA0001');
      await _settle(tester);
      expect(find.textContaining('دخل بهذه التذكرة من قبل'), findsOneWidget);
      expect(find.byKey(const Key('scan-confirm')), findsNothing);
      await _tap(tester, find.byKey(const Key('scan-done')));
      expect(srv.calls.where((c) => c == 'POST /events/$evId/checkin').length, 1);
    });

    testWidgets('an unknown ticket is refused before any check-in; typing the code works the same', (tester) async {
      QrCamera.factoryOverride = () => _FakeCam(startError: const MediaPermissionDenied('camera'));
      final srv = server();
      await _pump(tester, srv, const EventDetailPage(eventId: evId));
      await _tap(tester, find.byKey(const Key('event-checkin-code')));
      expect(find.byKey(const Key('qr-denied')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('qr-manual')), 'nas-zzzz9999');
      await _tap(tester, find.byKey(const Key('qr-manual-go')));
      expect(find.text('لا تذكرة بهذا الرمز في هذه الفعالية'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('scan-done')));
      expect(srv.calls.where((c) => c.startsWith('POST /events/$evId/checkin')), isEmpty);
    });
  });

  group('market seller', () {
    const lid = '11111111-1111-4111-8111-111111111111', oid = '22222222-2222-4222-8222-222222222222';
    Map<String, dynamic> order({required bool asSeller, String status = 'delivered'}) => {
          'id': oid, 'listingId': lid, 'title': 'كيك عيد ميلاد', 'imageUrl': null, 'kind': 'product', 'qty': 1, 'total': 22000, 'discount': 0, 'commission': asSeller ? 1100 : null, 'status': status, 'note': '',
          'code': asSeller ? null : '4321', 'buyer': {'id': 'SA0000003', 'nickname': 'noura'}, 'seller': {'id': 'SA0000001', 'nickname': 'amr'}, 'mineAsSeller': asSeller, 'reviewed': false, 'createdAt': '2026-11-01T10:00:00Z',
        };

    testWidgets('buyer sees a QR beside the four digits; the seller does not', (tester) async {
      await _pump(tester, _Srv((key, _) async => key == 'GET /market/orders/$oid' ? _json(order(asSeller: false)) : null), const OrderPage(oid));
      expect(find.byKey(const Key('order-code')), findsOneWidget);
      expect(find.byKey(const Key('order-code-qr')), findsOneWidget);
      await _pump(tester, _Srv((key, _) async => key == 'GET /market/orders/$oid' ? _json(order(asSeller: true)) : null), const OrderPage(oid));
      expect(find.byKey(const Key('order-code-qr')), findsNothing);
      expect(find.text('مسح رمز المشتري'), findsOneWidget);
    });

    testWidgets("another order's QR is refused without spending an attempt; this order's QR → summary → confirm", (tester) async {
      final cam = _FakeCam();
      QrCamera.factoryOverride = () => cam;
      var status = 'delivered';
      final srv = _Srv((key, req) async {
        if (key == 'GET /market/orders/$oid') return _json(order(asSeller: true, status: status));
        if (key == 'GET /market/orders') return _json([order(asSeller: true, status: status)]);
        if (key == 'POST /market/orders/$oid/confirm') { status = 'completed'; return _json({'ok': true}); }
        return null;
      });
      await _pump(tester, srv, const OrderPage(oid));
      await _tap(tester, find.byKey(const Key('seller-code')));
      cam.queue.add(marketQrData('33333333-3333-4333-8333-333333333333', '4321'));
      await _settle(tester);
      expect(find.text('هذا رمز طلب آخر، لا هذا الطلب'), findsOneWidget);
      expect(srv.calls.where((c) => c.startsWith('POST')), isEmpty);
      cam.queue.add(marketQrData(oid, '4321'));
      await _settle(tester);
      expect(find.byKey(const Key('market-summary')), findsOneWidget);
      expect(find.text('noura'), findsWidgets);
      await _tap(tester, find.byKey(const Key('scan-confirm')));
      expect(srv.bodies['POST /market/orders/$oid/confirm'], {'code': '4321'});
      expect(find.text('اكتمل الطلب ووصلك المبلغ'), findsOneWidget);
      expect(find.byKey(const Key('scan-next')), findsNothing, reason: 'طلب واحد، لا «التالي»');
    });
  });
}
