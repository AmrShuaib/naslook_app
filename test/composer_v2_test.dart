// المحرّر الجديد: الكاميرا أولاً (صورة/فيديو/نص) ثم «راجع وعدّل» ثم شاشة النشر بوجهاتها الثلاث (الخريطة، دائرة، السوق)،
// مع الطبقة الصوتية والفلاتر وكاميرا النظام احتياطاً وتعديل منشور قائم.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/posts_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/camera.dart';
import 'package:naslook/core/media/filters.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/core/media/voice_record.dart';
import 'package:naslook/pages/posts/post_composer.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// صورة PNG صالحة 4×4 (حمراء) حتى تعمل معاينة الصورة وخبز الفلتر في الاختبار
final Uint8List _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mM4YaPxHxkzkC4AAJdYIrG6Q2NNAAAAAElFTkSuQmCC');

class _FakeCamera implements LiveCamera {
  bool started = false, _front = false, _rec = false;
  @override
  bool get front => _front;
  @override
  bool get recording => _rec;
  @override
  Future<void> start({bool front = false}) async { started = true; _front = front; }
  @override
  Widget view() => const ColoredBox(color: Colors.black);
  @override
  Future<void> flip() async => _front = !_front;
  @override
  Future<CameraShot?> capturePhoto() async => (bytes: _png, mime: 'image/png', name: 'photo.png', durationSec: null);
  @override
  Future<void> startVideo() async => _rec = true;
  @override
  Future<CameraShot?> stopVideo() async { _rec = false; return (bytes: Uint8List.fromList([1, 2, 3]), mime: 'video/webm', name: 'clip.webm', durationSec: 5); }
  @override
  void dispose() {}
}

class _FakeRecorder implements VoiceRecordSession {
  bool _on = false;
  @override
  bool get recording => _on;
  @override
  Duration get elapsed => const Duration(seconds: 3);
  @override
  Future<void> start() async => _on = true;
  @override
  Future<RecordedVoice?> stop() async { _on = false; return (bytes: Uint8List.fromList([9, 9, 9]), mime: 'audio/webm', name: 'voice.weba', duration: const Duration(seconds: 3)); }
  @override
  Future<void> cancel() async => _on = false;
  @override
  void dispose() {}
}

class _FakePlayer extends VoicePlayerBase {
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {}
  @override
  Future<void> play() async => emit(const VoiceState(playing: true, duration: Duration(seconds: 3)));
  @override
  Future<void> pause() async => emit(const VoiceState(playing: false, duration: Duration(seconds: 3)));
  @override
  Future<void> seek(Duration position) async {}
}

const _pid = 'aaaaaaaa-0000-4000-8000-000000000001';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final uploads = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, dynamic> _post(Map<String, dynamic> b) => {
        'id': _pid, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'status': 'active', 'views': 0, 'likes': 0, 'liked': false, 'mine': true, 'expired': false, 'createdAt': DateTime.now().toUtc().toIso8601String(),
        'lat': 21.5, 'lng': 39.2, 'kind': 'text', 'overlays': [], 'caption': '', ...b,
      };
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(req.url.hasQuery ? '$key?${req.url.query}' : key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    switch (key) {
      case 'POST /chat/upload':
        final ct = req.headers['content-type'] ?? '';
        uploads.add(ct);
        final n = uploads.length;
        return _json({'url': ct.startsWith('audio') ? '/chat/media/voice$n.weba' : ct.startsWith('video') ? '/chat/media/clip$n.webm' : '/chat/media/img$n.jpg', 'type': ct, 'kind': ct.split('/').first, 'size': req.bodyBytes.length});
      case 'POST /mapposts':
        return _json(_post(bodies[key]!));
      case 'PATCH /mapposts/$_pid':
        return _json(_post({'kind': 'image', 'mediaUrl': '/chat/media/old.jpg', ...bodies[key]!}));
      case 'GET /biz/mine':
        return _json({'circles': [{'id': 'biz-mine', 'name': 'my shop', 'nameAr': 'متجري', 'category': 'brand', 'lat': 21.5, 'lng': 39.2, 'active': true}], 'claims': [], 'admin': false});
      case 'GET /biz':
        return _json([{'id': 'biz-brew92', 'name': 'brew92', 'nameAr': 'برو ٩٢', 'category': 'cafe', 'lat': 21.5, 'lng': 39.2, 'following': true, 'active': true}]);
      case 'POST /biz/biz-brew92/community':
        return _json({'id': 'cp1', 'bizId': 'biz-brew92', 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'topic': bodies[key]!['topic'], 'text': bodies[key]!['text'], 'images': bodies[key]!['images'], 'replies': 0, 'likes': 0, 'liked': false, 'createdAt': DateTime.now().toUtc().toIso8601String()});
      case 'POST /market':
        return _json({'id': '11111111-1111-4111-8111-111111111111', 'seller': {'id': 'SA0000001', 'nickname': 'amr'}, 'kind': bodies[key]!['kind'], 'category': bodies[key]!['category'], 'title': bodies[key]!['title'], 'description': '', 'price': bodies[key]!['price'], 'status': 'active', 'images': bodies[key]!['images'], 'mine': true});
      case 'GET /me/map-presence':
        return _json({'lat': null, 'lng': null, 'visible': false, 'title': ''});
      case 'GET /notify/unread':
        return _json({'unread': 0});
    }
    return _json({'error': 'not-found'}, 404);
  }
}

/// يفتح المحرّر من زر ويعيد الخادم الوهمي؛ [edit] لتعديل منشور قائم
Future<_Srv> _pump(WidgetTester tester, {MapPost? edit, bool liveCamera = true}) async {
  SharedPreferences.setMockInitialValues({});
  LiveCamera.factoryOverride = liveCamera ? () => _FakeCamera() : null;
  VoiceRecordSession.factoryOverride = () => _FakeRecorder();
  VoicePlayer.factoryOverride = () => _FakePlayer();
  pickImageOverride = ({bool camera = false}) async => (bytes: _png, mime: 'image/png', name: camera ? 'system.png' : 'gallery.png');
  // خبز الصورة يحتاج زمناً حقيقياً (فكّ الصورة والرسم)؛ في اختبار الودجات نستبدله ونتحقق من الخبز الحقيقي في اختبار مستقل
  bakePhotoOverride = (src, {required filter, adjust = const PhotoAdjust(), frame = const PhotoFrame(), name = 'photo.jpg', mime = 'image/jpeg'}) async => (bytes: src, mime: 'image/jpeg', name: 'baked-${filter.id}.jpg');
  addTearDown(() { LiveCamera.factoryOverride = null; VoiceRecordSession.factoryOverride = null; VoicePlayer.factoryOverride = null; pickImageOverride = null; bakePhotoOverride = null; });
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    child: MaterialApp(locale: const Locale('ar'), home: Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(onPressed: () => PostComposerPage.open(ctx, lat: 21.5, lng: 39.2, placeName: 'الكورنيش', edit: edit), child: const Text('open')))))),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return srv;
}

/// نص أي SnackBar ظاهر (لتشخيص فشل النشر في الاختبار)
String _snack(WidgetTester tester) => tester.widgetList<SnackBar>(find.byType(SnackBar)).map((s) => s.content is Text ? (s.content as Text).data : s.content.toString()).join(' | ');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  test('filter matrices: the original is identity and a filter changes it; the bake leaves an untouched photo as is and re-encodes a filtered one', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(colorFilterFor(filterById('none'), const PhotoAdjust()), isNull);
    expect(colorFilterFor(filterById('warm'), const PhotoAdjust()), isNotNull);
    expect(filterMatrix(filterById('mono'), const PhotoAdjust())[0], closeTo(filterMatrix(filterById('mono'), const PhotoAdjust())[5], 1e-9), reason: 'الأبيض والأسود يساوي بين القنوات');
    final same = await bakePhoto(_png, filter: filterById('none'));
    expect(same.bytes, same_(_png));
    // خبز حقيقي: فلتر + قصّ مربع + دوران → صورة PNG جديدة (على غير الويب)
    final baked = await bakePhoto(_png, filter: filterById('warm'), frame: const PhotoFrame(aspect: 1, quarterTurns: 1));
    expect(baked.mime, 'image/png');
    expect(baked.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'توقيع PNG');
    expect(baked.bytes, isNot(same_(_png)));
  });

  testWidgets('camera first: shutter takes a photo, the filter is baked, and the post lands on the map', (tester) async {
    final srv = await _pump(tester);
    expect(find.byKey(const Key('shutter')), findsOneWidget);
    expect(find.byKey(const Key('mode-text')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shutter')));
    await _settle(tester);
    // شاشة التعديل: أربع أدوات + صوت
    expect(find.byKey(const Key('tool-filter')), findsOneWidget);
    expect(find.byKey(const Key('tool-crop')), findsOneWidget);
    expect(find.byKey(const Key('tool-voice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tool-filter')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('filter-warm')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('tray-done')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    // شاشة النشر: الخريطة افتراضياً، المدة ٢٤ ساعة، التفاصيل مطوية
    expect(find.byKey(const Key('dest-map')), findsOneWidget);
    expect(find.byKey(const Key('pub-pro')), findsOneWidget);
    expect(find.text('نوع المنشور'), findsNothing, reason: 'التفاصيل الاحترافية مطوية');
    await tester.enterText(find.byKey(const Key('pub-caption')), 'كيك التخرج جاهز');
    await tester.tap(find.byKey(const Key('ttl-72')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    expect(srv.uploads.length, 1, reason: 'snack: ${_snack(tester)} calls: ${srv.calls}');
    expect(srv.uploads.first, startsWith('image/'), reason: 'الغلاف المخبوز يُرفع صورةً');
    final body = srv.bodies['POST /mapposts']!;
    expect(body['kind'], 'image');
    expect(body['mediaUrl'], '/chat/media/img1.jpg');
    expect(body['caption'], 'كيك التخرج جاهز');
    expect(body['ttlHours'], 72);
    expect(body['tag'], 'moment');
    expect(body['placeName'], 'الكورنيش');
    expect(find.text('open'), findsOneWidget, reason: 'يعود إلى الصفحة السابقة بعد النشر');
  });

  testWidgets('text mode: template, board colour and a voice layer publish as a text post with audio', (tester) async {
    final srv = await _pump(tester);
    await tester.tap(find.byKey(const Key('mode-text')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('tpl-question')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('board-text')), 'من يجي معي للحرم الجمعة؟');
    // الطبقة الصوتية: اضغط باستمرار ثم «استخدام»
    await tester.tap(find.byKey(const Key('board-voice')));
    await _settle(tester);
    await tester.longPress(find.byKey(const Key('voice-hold')));
    await _settle(tester);
    expect(find.byKey(const Key('voice-use')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-use')));
    await _settle(tester);
    expect(find.byKey(const Key('voice-chip')), findsOneWidget, reason: 'الشريحة الصوتية على اللوحة');
    await tester.tap(find.byKey(const Key('text-next')));
    await _settle(tester);
    expect(find.byKey(const Key('tool-filter')), findsNothing, reason: 'لا فلاتر على لوحة النص');
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    expect(find.byKey(const Key('dest-market')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    final body = srv.bodies['POST /mapposts']!;
    expect(body['kind'], 'text');
    expect(body['bg'], '#FFF4D6', reason: 'قالب السؤال يلوّن اللوحة');
    final overlays = body['overlays'] as List;
    expect(overlays.any((o) => o['text'] == 'سؤال' && o['font'] == 'badge'), isTrue);
    expect(overlays.any((o) => o['text'] == 'من يجي معي للحرم الجمعة؟' && o['color'] == '#111111'), isTrue);
    expect(body['audioUrl'], '/chat/media/voice1.weba');
    expect(body['audioSec'], 3);
  });

  testWidgets('publishing to a circle posts to its community with the photo and caption', (tester) async {
    final srv = await _pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('dest-circle')));
    await _settle(tester);
    expect(find.byKey(const Key('circle-biz-mine')), findsOneWidget);
    expect(find.byKey(const Key('circle-biz-brew92')), findsOneWidget);
    await tester.tap(find.byKey(const Key('circle-biz-brew92')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('pub-caption')), 'قهوة اليوم');
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-brew92/community']!;
    expect(body['text'], 'قهوة اليوم');
    expect(body['images'], ['/chat/media/img1.jpg']);
    expect(body['topic'], 'general');
    expect(srv.calls, isNot(contains('POST /mapposts')));
  });

  testWidgets('publishing to the market creates a listing from the quick form', (tester) async {
    final srv = await _pump(tester);
    await tester.tap(find.byKey(const Key('shutter')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('dest-market')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('lst-title')), 'كيك تخرج بتصميم خاص');
    await tester.enterText(find.byKey(const Key('lst-price')), '220');
    await tester.tap(find.byKey(const Key('lst-cat-food')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('pub-go')));
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    final body = srv.bodies['POST /market']!;
    expect(body['title'], 'كيك تخرج بتصميم خاص');
    expect(body['price'], 22000);
    expect(body['category'], 'food');
    expect(body['kind'], 'product');
    expect(body['images'], ['/chat/media/img1.jpg']);
    expect(body['lat'], 21.5);
  });

  testWidgets('holding the shutter records a video that publishes with its duration', (tester) async {
    final srv = await _pump(tester);
    await tester.longPress(find.byKey(const Key('shutter')));
    await _settle(tester);
    expect(find.byKey(const Key('edit-next')), findsOneWidget, reason: 'رفع الإصبع يوقف التسجيل ويفتح المراجعة');
    expect(find.byKey(const Key('tool-filter')), findsNothing, reason: 'لا فلاتر على الفيديو');
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    final body = srv.bodies['POST /mapposts']!;
    expect(body['kind'], 'video');
    expect(body['mediaUrl'], '/chat/media/clip1.webm');
    expect(body['durationSec'], 5);
  });

  testWidgets('without a live camera the system camera is the fallback and leads to the same edit screen', (tester) async {
    final srv = await _pump(tester, liveCamera: false);
    expect(find.byKey(const Key('cam-system')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cam-system')));
    await _settle(tester);
    expect(find.byKey(const Key('edit-next')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    expect(srv.bodies['POST /mapposts']!['kind'], 'image');
  });

  testWidgets('editing an existing post skips the camera and saves through PATCH', (tester) async {
    final post = MapPost.fromJson({'id': _pid, 'user': {'id': 'SA0000001', 'nickname': 'amr'}, 'kind': 'image', 'mediaUrl': '/chat/media/old.jpg', 'caption': 'قديم', 'overlays': [], 'tag': 'offer', 'title': 'عرض', 'price': 1500, 'lat': 21.5, 'lng': 39.2, 'status': 'active', 'mine': true});
    final srv = await _pump(tester, edit: post);
    expect(find.byKey(const Key('shutter')), findsNothing);
    expect(find.byKey(const Key('tool-filter')), findsNothing, reason: 'لا فلاتر على صورة قائمة');
    await tester.tap(find.byKey(const Key('tool-text')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('inline-text')), 'خصم ٣٠٪');
    await tester.tap(find.byKey(const Key('tray-done')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('edit-next')));
    await _settle(tester);
    expect(find.byKey(const Key('dest-map')), findsNothing, reason: 'لا اختيار وجهة عند التعديل');
    expect(find.text('حفظ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pub-go')));
    await _settle(tester);
    final body = srv.bodies['PATCH /mapposts/$_pid']!;
    expect((body['overlays'] as List).first['text'], 'خصم ٣٠٪');
    expect(body['tag'], 'offer');
    expect(body['price'], 1500);
    expect(body.containsKey('mediaUrl'), isFalse, reason: 'لم تتغير الصورة');
  });
}

Matcher same_(Uint8List a) => predicate<Uint8List>((b) => b.length == a.length && identical(a, b) || _eq(a, b));
bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
