// معاينة الروابط (lib/api/chat_preview_api.dart + lib/pages/chat/widgets/link_preview_card.dart): استخراج أول رابط من النص،
// البطاقة تعرض العنوان والوصف والموقع والصورة عبر وكيل الخادم، تختفي حين ok:false أو عند خطأ الخادم، تُجلب مرة لكل رابط،
// وتفتح الرابط عبر LegalLinks.openOverride.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/chat_preview_api.dart';
import 'package:naslook/api/chat_tools_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/core/share/legal_links.dart';
import 'package:naslook/pages/chat/widgets/link_preview_card.dart';
import 'package:naslook/state/app_state.dart';

class _Srv {
  final calls = <String>[];
  Map<String, dynamic> Function(String url)? preview;
  int code = 200;
  http.Response _json(Object body, [int c = 200]) => http.Response(jsonEncode(body), c, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    calls.add('${req.method} ${req.url.path}');
    if (req.url.path == '/chat/preview') {
      if (code != 200) return _json({'error': 'not-found'}, code);
      final u = req.url.queryParameters['url'] ?? '';
      return _json(preview?.call(u) ?? {'ok': false, 'reason': 'not-html'});
    }
    if (req.url.path == '/chat/peaks') return _json({'name': 'x.m4a', 'peaks': List.generate(48, (i) => (i % 5) / 4), 'n': 48});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget child, {_Srv? srv}) async {
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 320, child: child)))),
  ));
  await tester.pumpAndSettle();
  return s;
}

Map<String, dynamic> _ok(String u) => {
      'ok': true, 'url': u, 'title': 'قهوة & كيك — برو 92', 'description': 'أفضل V60 في جدة', 'image': 'https://cdn.example.com/og.png', 'site': 'Brew92', 'cachedAt': '2026-10-21T10:00:00Z',
    };

void main() {
  test('firstLinkIn: http(s) and www, trailing punctuation stripped, media urls and dotless hosts ignored', () {
    expect(firstLinkIn('شوف https://example.com/page?x=1، حلو'), 'https://example.com/page?x=1');
    expect(firstLinkIn('www.naslife.app/c/brew92.'), 'https://www.naslife.app/c/brew92');
    expect(firstLinkIn('بلا رابط'), isNull);
    expect(firstLinkIn(''), isNull);
    expect(firstLinkIn('https://naslife.app/chat/media/k9x1-ab12cd34ef56ab12cd34ef56.jpg'), isNull, reason: 'وسائط الخادم تُعرض وسائط لا بطاقة');
    expect(firstLinkIn('http://localhost:3000/x'), isNull, reason: 'مضيف بلا نقطة');
    expect(firstLinkIn('(https://example.com/a) و https://b.example.com'), 'https://example.com/a');
    expect(firstLinkIn('HTTPS://Example.com/Path!'), 'HTTPS://Example.com/Path');
  });

  test('LinkPreview.fromJson and parsePeaks', () {
    final p = LinkPreview.fromJson(_ok('https://example.com'), url: 'https://example.com');
    expect(p.showable, isTrue);
    expect(p.hasImage, isTrue);
    expect(p.cachedAt, isNotNull);
    expect(LinkPreview.fromJson({'ok': true, 'title': ''}, url: 'u').showable, isFalse, reason: 'بلا عنوان لا تُعرض');
    expect(LinkPreview.fromJson({'ok': false, 'reason': 'private-host'}, url: 'u').reason, 'private-host');
    expect(const LinkPreview.failed('u', 'x').ok, isFalse);
    expect(parsePeaks(null), isNull);
    expect(parsePeaks([]), isNull);
    expect(parsePeaks([0, 0.5, 1, 2, -1, '0.25']), [0, 0.5, 1, 1, 0, 0.25]);
    expect(parsePeaks(['x']), isNull);
    expect(const UploadedMedia(url: '/chat/media/a.m4a', type: 'audio/mp4', kind: 'audio', size: 1, peaks: [0.2, 1]).audioExtra(durationMs: 3000), {'durationMs': 3000, 'peaks': [0.2, 1]});
    expect(const UploadedMedia(url: '/chat/media/a.jpg', type: 'image/jpeg', kind: 'image', size: 1).audioExtra(), isEmpty);
  });

  testWidgets('card renders title, description, site and the image through the server proxy; tapping opens the url', (tester) async {
    final srv = _Srv()..preview = _ok;
    Uri? opened;
    LegalLinks.openOverride = (u) async => opened = u;
    addTearDown(() => LegalLinks.openOverride = null);
    await _pump(tester, const LinkPreviewCard('https://example.com/page'), srv: srv);
    expect(find.byKey(const Key('link-preview-card')), findsOneWidget);
    expect(find.text('قهوة & كيك — برو 92'), findsOneWidget);
    expect(find.text('أفضل V60 في جدة'), findsOneWidget);
    expect(find.text('Brew92'), findsOneWidget);
    final img = tester.widget<Image>(find.byKey(const Key('link-preview-image')));
    final src = (img.image as NetworkImage).url;
    expect(src, startsWith('https://test.local'));
    expect(src, endsWith('/chat/preview/image?u=${Uri.encodeQueryComponent('https://cdn.example.com/og.png')}'), reason: 'الصورة عبر وكيل الخادم لا من المضيف الخارجي');
    expect(srv.calls.where((c) => c == 'GET /chat/preview').length, 1);
    await tester.tap(find.byKey(const Key('link-preview-card')));
    await tester.pump();
    expect(opened.toString(), 'https://example.com/page');
  });

  testWidgets('no image and no description: card still shows title and site', (tester) async {
    final srv = _Srv()..preview = (u) => {'ok': true, 'url': u, 'title': 'عنوان فقط', 'description': '', 'image': '', 'site': 'example.com'};
    await _pump(tester, const LinkPreviewCard('https://example.com/x', mine: true), srv: srv);
    expect(find.text('عنوان فقط'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.byKey(const Key('link-preview-image')), findsNothing);
  });

  testWidgets('hides itself on ok:false', (tester) async {
    await _pump(tester, const LinkPreviewCard('https://nopreview.example.com/'));
    expect(find.byKey(const Key('link-preview-card')), findsNothing);
    expect(find.byType(LinkPreviewCard), findsOneWidget);
  });

  testWidgets('hides itself when the server has no preview route (old server) without throwing', (tester) async {
    final srv = _Srv()..code = 404;
    await _pump(tester, const LinkPreviewCard('https://example.com/'), srv: srv);
    expect(find.byKey(const Key('link-preview-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one fetch per url: two cards for the same link share the cached provider', (tester) async {
    final srv = _Srv()..preview = _ok;
    await _pump(tester, const Column(children: [LinkPreviewCard('https://example.com/same'), LinkPreviewCard('https://example.com/same'), LinkPreviewCard('https://example.com/other')]), srv: srv);
    expect(find.byKey(const Key('link-preview-card')), findsNWidgets(3));
    expect(srv.calls.where((c) => c == 'GET /chat/preview').length, 2);
  });

  testWidgets('audioPeaks fetches /chat/peaks and clamps values', (tester) async {
    final srv = _Srv();
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
    final peaks = await api.audioPeaks('/chat/media/x.m4a');
    expect(peaks, hasLength(48));
    expect(peaks!.every((v) => v >= 0 && v <= 1), isTrue);
    expect(srv.calls, contains('GET /chat/peaks'));
    srv.calls.clear();
    final api2 = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient((_) async => http.Response('nope', 404)));
    expect(await api2.audioPeaks('x.m4a'), isNull, reason: 'لا ترمي عند الخطأ');
  });
}
