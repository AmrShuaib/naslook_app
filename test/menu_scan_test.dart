// «صوّر المنيو»: زر تبويب الكتالوج للمالك والمدير فقط، تنبيه الخصوصية قبل القراءة، رفع الصور ثم POST /menu/scan، شاشة المراجعة
// (أقسام، تعديل، حذف، تحديد الكل/لا شيء)، الإضافة صنفاً صنفاً بالهللات مع بقاء ما فشل، أوقات المواعيد لفئات الحجز، وأخطاء القراءة.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/menu_scan_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/pages/business/owner/dashboard_catalog.dart';
import 'package:naslook/pages/business/owner/menu_scan_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _id = 'biz-cafe';
// PNG شفاف 1×1 حتى تُرسم المصغّرة بلا خطأ ترميز
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _Srv {
  final calls = <String>[];
  final scans = <Map<String, dynamic>>[];
  final created = <Map<String, dynamic>>[];
  int uploads = 0;
  /// رد القراءة: الحالة والجسم
  int scanStatus = 200;
  Map<String, dynamic> scanBody = {
    'items': [
      {'title': 'لاتيه', 'price': 1800, 'priceKnown': true, 'description': 'حليب طازج', 'section': 'مشروبات ساخنة'},
      {'title': 'موكا', 'price': 2150, 'priceKnown': true, 'description': '', 'section': 'مشروبات ساخنة'},
      {'title': 'ممنوع', 'price': 900, 'priceKnown': true, 'description': '', 'section': 'حلويات'},
      {'title': 'كيكة اليوم', 'price': 0, 'priceKnown': false, 'description': '', 'section': 'حلويات'},
    ],
    'warnings': [{'code': 'no-price', 'message': '1 من الأصناف بلا سعر مقروء. اكتب سعرها قبل الإضافة.'}],
  };
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'POST /chat/upload':
        uploads++;
        return _json({'url': '/chat/media/up$uploads.png', 'type': 'image/png', 'kind': 'image', 'size': req.bodyBytes.length});
      case 'POST /menu/scan':
        scans.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json(scanBody, scanStatus);
      case 'POST /biz/$_id/items':
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        if (b['title'] == 'ممنوع') return _json({'error': 'banned-words', 'word': 'ممنوع'}, 400);
        created.add(b);
        return _json({'id': 'it-${created.length}', 'bizId': _id, 'kind': b['kind'], 'title': b['title'], 'price': b['price'], 'unit': 'item', 'meta': b['meta'] ?? {}, 'active': true});
    }
    if (req.method == 'GET') return _json({});
    return _json({'ok': true});
  }
}

Biz _biz({String category = 'cafe', String role = 'owner'}) => Biz.fromJson({
      'id': _id, 'name': 'Cafe', 'nameAr': 'مقهى عمرو', 'category': category, 'lat': 21.5, 'lng': 39.2, 'color': '#0058A3', 'highlights': [], 'verified': true, 'active': true,
      'ownerId': role == 'owner' ? 'SA0000001' : 'SA0000002', 'myRole': role,
      'items': [{'id': 'cafe-latte', 'bizId': _id, 'kind': 'product', 'title': 'شاي', 'price': 500, 'unit': 'item', 'stock': 10, 'meta': {}, 'active': true}], 'reviews': [], 'posts': [], 'myOrders': [],
    });

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(440, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

/// يختار صورتين ويقرأ المنيو حتى تظهر شاشة المراجعة.
Future<void> _scanTwo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('menu-pick-camera')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('menu-pick-gallery')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('menu-scan-go')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  final picks = <bool>[];
  setUp(() {
    picks.clear();
    pickImageOverride = ({bool camera = false}) async {
      picks.add(camera);
      return (bytes: _png, mime: 'image/png', name: 'menu.png');
    };
  });
  tearDown(() => pickImageOverride = null);

  test('daily times: Arabic digits and separators, invalid dropped, sorted and unique', () {
    expect(parseDailyTimes('16:30، 9:00 ١٠:١٥, 9:00'), ['09:00', '10:15', '16:30']);
    expect(parseDailyTimes('25:00, 10:70, صباحاً'), isEmpty);
    expect(parseDailyTimes(''), isEmpty);
  });

  test('scan result parsing and error texts', () {
    final r = MenuScanResult.fromJson({'items': [{'title': ' شاي ', 'price': 500}, {'title': ''}, 'x'], 'warnings': [{'code': 'partial', 'message': 'لم تكتمل القراءة.'}, {'code': 'x'}]});
    expect(r.items.length, 1);
    expect(r.items.first.title, 'شاي');
    expect(r.items.first.price, 500);
    expect(r.items.first.priceKnown, isTrue);
    expect(r.warnings, ['لم تكتمل القراءة.']);
    expect(menuScanErrText(const ApiException(503, 'x', body: {'error': 'ai-unavailable'})), contains('غير مفعّلة'));
    expect(menuScanErrText(const ApiException(429, 'x', body: {'error': 'rate-limited', 'scope': 'window', 'retryAfterSec': 125})), contains('بعد 3 دقيقة'));
    expect(menuScanErrText(const ApiException(429, 'x', body: {'error': 'rate-limited', 'scope': 'day'})), contains('غداً'));
    expect(menuScanErrText(const ApiException(0, 'انتهت مهلة الاتصال بالخادم')), contains('وقتاً طويلاً'));
    expect(menuScanErrText(const ApiException(413, 'x', body: {'error': 'image-too-large'})), contains('كبيرة'));
  });

  testWidgets('catalog tab: the scan button shows for a manager and opens the page with the privacy notice; staff do not see it', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, CatalogTab(biz: _biz(role: 'manager')));
    expect(find.byKey(const Key('menu-scan-open')), findsOneWidget);
    expect(find.text('إضافة صنف'), findsOneWidget, reason: 'زر الإضافة اليدوية باقٍ');
    await tester.tap(find.byKey(const Key('menu-scan-open')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScanPage), findsOneWidget);
    expect(find.byKey(const Key('menu-notice')), findsOneWidget);
    expect(find.textContaining('Anthropic'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('menu-scan-go'))).onPressed, isNull, reason: 'لا قراءة بلا صورة');
    expect(srv.calls.where((c) => c.startsWith('POST')), isEmpty);

    await _pump(tester, _Srv(), CatalogTab(biz: _biz(role: 'staff')));
    expect(find.byKey(const Key('menu-scan-open')), findsNothing);
  });

  testWidgets('scan then review: upload, scan, edit, remove, select, add one by one, keep the failed row', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, MenuScanPage(biz: _biz()));
    await tester.tap(find.byKey(const Key('menu-pick-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-pick-gallery')));
    await tester.pumpAndSettle();
    expect(picks, [true, false]);
    expect(find.byKey(const Key('menu-image-0')), findsOneWidget);
    expect(find.byKey(const Key('menu-image-1')), findsOneWidget);
    // حذف صورة ثم إعادة اختيارها
    await tester.tap(find.byKey(const Key('menu-image-remove-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-image-1')), findsNothing);
    await tester.tap(find.byKey(const Key('menu-pick-gallery')));
    await tester.pumpAndSettle();
    expect(srv.calls, isEmpty, reason: 'لا رفع ولا قراءة قبل الضغط');

    await tester.tap(find.byKey(const Key('menu-scan-go')));
    await tester.pumpAndSettle();
    expect(srv.calls, ['POST /chat/upload', 'POST /chat/upload', 'POST /menu/scan']);
    expect(srv.scans.single['images'], ['/chat/media/up1.png', '/chat/media/up2.png']);
    expect(srv.created, isEmpty, reason: 'القراءة لا تحفظ شيئاً');

    // المراجعة: قسمان وأربعة أصناف كلها محددة، والسعر غير المقروء فارغ
    expect(find.text('راجع الأصناف'), findsOneWidget);
    expect(find.byKey(const Key('menu-section-مشروبات ساخنة')), findsOneWidget);
    expect(find.byKey(const Key('menu-section-حلويات')), findsOneWidget);
    expect(_text(tester, 'menu-item-title-0'), 'لاتيه');
    expect(_text(tester, 'menu-item-price-0'), '18');
    expect(_text(tester, 'menu-item-price-1'), '21.50');
    expect(_text(tester, 'menu-item-desc-0'), 'حليب طازج');
    expect(_text(tester, 'menu-item-price-3'), '');
    expect(find.textContaining('بلا سعر مقروء'), findsOneWidget);
    expect(find.text('4 من 4'), findsOneWidget);
    expect(find.text('أضف المحدد (4)'), findsOneWidget);

    // لا شيء ثم الكل
    await tester.tap(find.byKey(const Key('menu-select-none')));
    await tester.pumpAndSettle();
    expect(find.text('0 من 4'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('menu-add'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('menu-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('أضف المحدد (4)'), findsOneWidget);

    // تعديل الاسم والسعر والوصف، حذف صنف، وإلغاء تحديد آخر
    await tester.enterText(find.byKey(const Key('menu-item-title-0')), 'لاتيه ساخن');
    await tester.enterText(find.byKey(const Key('menu-item-price-0')), '١٩٫٥');
    await tester.enterText(find.byKey(const Key('menu-item-desc-0')), 'إسبريسو وحليب');
    await tester.tap(find.byKey(const Key('menu-item-remove-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-item-1')), findsNothing);
    await tester.tap(find.byKey(const Key('menu-item-check-3')));
    await tester.pumpAndSettle();
    expect(find.text('أضف المحدد (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.calls.where((c) => c == 'POST /biz/$_id/items').length, 2, reason: 'نداء لكل صنف محدد');
    expect(srv.created.single, {'kind': 'product', 'title': 'لاتيه ساخن', 'description': 'إسبريسو وحليب', 'price': 1950, 'meta': <String, dynamic>{}});
    // المضاف خرج من القائمة، والمرفوض بقي بسببه، وغير المحدد بقي كما هو
    expect(find.byKey(const Key('menu-item-0')), findsNothing);
    expect(find.byKey(const Key('menu-item-error-2')), findsOneWidget);
    expect(find.textContaining('كلمة غير مسموحة'), findsWidgets);
    expect(find.byKey(const Key('menu-item-3')), findsOneWidget);
    expect(find.byType(MenuScanPage), findsOneWidget, reason: 'الصفحة تبقى ما دام فيها ما لم يُضف');

    // تصحيح المرفوض وإضافة الباقي: الصفحة تُغلق حين لا يبقى شيء
    await tester.enterText(find.byKey(const Key('menu-item-title-2')), 'تشيز كيك');
    await tester.tap(find.byKey(const Key('menu-item-check-3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('menu-item-price-3')), '14');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.map((b) => '${b['title']}=${b['price']}').toList(), ['لاتيه ساخن=1950', 'تشيز كيك=900', 'كيكة اليوم=1400']);
  });

  testWidgets('a price that was not read is never saved as free: the row is held until a price is typed', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, MenuScanPage(biz: _biz()));
    await _scanTwo(tester);
    expect(_text(tester, 'menu-item-price-3'), '');
    await tester.enterText(find.byKey(const Key('menu-item-title-2')), 'تشيز كيك');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.map((b) => b['title']).toList(), ['لاتيه', 'موكا', 'تشيز كيك'], reason: 'الصنف بلا سعر لم يُرسل');
    expect(find.byKey(const Key('menu-item-error-3')), findsOneWidget);
    expect(find.textContaining('اكتب السعر'), findsOneWidget);
    expect(find.byType(MenuScanPage), findsOneWidget);
    // حروف بلا رقم ليست سعراً
    await tester.enterText(find.byKey(const Key('menu-item-price-3')), 'حسب الطلب');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.length, 3);
    // المجاني قرار صريح: يكتب المالك 0
    await tester.enterText(find.byKey(const Key('menu-item-price-3')), '٠');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.last['title'], 'كيكة اليوم');
    expect(srv.created.last['price'], 0);
  });

  testWidgets('everything added: the page closes back to where it was opened', (tester) async {
    final srv = _Srv()..scanBody = {'items': [{'title': 'شاي', 'price': 500, 'section': ''}, {'title': 'قهوة', 'price': 800, 'section': ''}], 'warnings': []};
    await _pump(tester, srv, CatalogTab(biz: _biz()));
    await tester.tap(find.byKey(const Key('menu-scan-open')));
    await tester.pumpAndSettle();
    await _scanTwo(tester);
    expect(find.byKey(const Key('menu-section--')), findsNothing, reason: 'لا رأس قسم حين لا أقسام');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.length, 2);
    expect(find.byType(MenuScanPage), findsNothing);
    expect(find.text('أُضيف 2 إلى الكتالوج'), findsOneWidget);
  });

  testWidgets('appointment categories: daily times are asked once and block adding until given', (tester) async {
    final srv = _Srv()..scanBody = {'items': [{'title': 'قص شعر', 'price': 5000, 'section': 'الشعر'}], 'warnings': []};
    await _pump(tester, srv, MenuScanPage(biz: _biz(category: 'salon')));
    await _scanTwo(tester);
    expect(find.byKey(const Key('menu-kind')), findsOneWidget, reason: 'الصالون يجمع المواعيد والمنتجات');
    expect(find.byKey(const Key('menu-times')), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created, isEmpty);
    expect(find.textContaining('وقتاً يومياً واحداً'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('menu-times')), '16:00، 10:00');
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.single['kind'], 'clinic');
    expect(srv.created.single['price'], 5000);
    expect(srv.created.single['meta'], {'times': ['10:00', '16:00'], 'minutes': 30, 'days': [0, 1, 2, 3, 4, 5, 6]});
  });

  testWidgets('salon products: switching the kind drops the times field and sends plain products', (tester) async {
    final srv = _Srv()..scanBody = {'items': [{'title': 'شامبو', 'price': 4500, 'section': ''}], 'warnings': []};
    await _pump(tester, srv, MenuScanPage(biz: _biz(category: 'salon')));
    await _scanTwo(tester);
    await tester.tap(find.byKey(const Key('menu-kind-product')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-times')), findsNothing);
    await tester.tap(find.byKey(const Key('menu-add')));
    await tester.pumpAndSettle();
    expect(srv.created.single, {'kind': 'product', 'title': 'شامبو', 'description': '', 'price': 4500, 'meta': <String, dynamic>{}});
  });

  testWidgets('scan errors: a clear message, the photos are kept, and retry scans again', (tester) async {
    final srv = _Srv()
      ..scanStatus = 503
      ..scanBody = {'error': 'ai-unavailable'};
    await _pump(tester, srv, MenuScanPage(biz: _biz()));
    await _scanTwo(tester);
    expect(find.byKey(const Key('menu-scan-error')), findsOneWidget);
    expect(find.textContaining('غير مفعّلة'), findsOneWidget);
    expect(find.byKey(const Key('menu-image-0')), findsOneWidget);
    expect(find.text('أعد المحاولة'), findsOneWidget);
    srv
      ..scanStatus = 429
      ..scanBody = {'error': 'rate-limited', 'scope': 'window', 'retryAfterSec': 300};
    await tester.tap(find.byKey(const Key('menu-scan-go')));
    await tester.pumpAndSettle();
    expect(find.textContaining('بعد 5 دقيقة'), findsOneWidget);
    // قراءة بلا أصناف: شاشة «لم نجد» مع العودة للتصوير
    srv
      ..scanStatus = 200
      ..scanBody = {'items': [], 'warnings': [{'code': 'no-items', 'message': 'لم نجد أصنافاً في الصور. صوّر المنيو أقرب وبإضاءة أوضح.'}]};
    await tester.tap(find.byKey(const Key('menu-scan-go')));
    await tester.pumpAndSettle();
    expect(find.text('لم نجد أصنافاً'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-rescan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-scan-go')), findsOneWidget);
    expect(srv.created, isEmpty);
  });

  testWidgets('four photos at most', (tester) async {
    await _pump(tester, _Srv(), MenuScanPage(biz: _biz()));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('menu-pick-gallery')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('menu-image-3')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('menu-pick-gallery'))).onPressed, isNull);
    expect(find.textContaining('أربع صور على الأكثر'), findsOneWidget);
  });
}
