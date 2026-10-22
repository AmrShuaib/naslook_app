// «اللحظات»: شبكة متدرّجة بعمودين من بطاقات تتحرك (فيديو يدور صامتاً بلا تحكم بحد أربع معاينات، صورة تتقرّب، نص على تدرّج) لكل ما يبثه
// GET /feed الأحدث أولاً، رقاقة «عام» افتراضية وبقية الأنواع في الشريط العلوي (كل رقاقة تجلب kind=…)، تصفح بالمؤشر before=،
// الجديد يصل فوراً من القناة الحية في الأعلى أو خلف كبسولة «جديدة» أثناء التصفح، لمسة اللحظة تفتح العارض وبقية الأنواع رحلاتها،
// وحالة فارغة لكل نوع. والدخول إليها من زر في شريط الرئيسية.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/row_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/location.dart';
import 'package:naslook/core/media/native_io.dart';
import 'package:naslook/core/media/video_view.dart';
import 'package:naslook/pages/business/offers_page.dart';
import 'package:naslook/pages/map/map_page.dart';
import 'package:naslook/pages/posts/post_viewer.dart';
import 'package:naslook/pages/posts/timeline_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

String _pid(int i) => 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}';

/// لحظة بصيغة /mapposts (كما تصل من القناة الحية وكحمولة بطاقة الصف).
Map<String, dynamic> _post(int i, {Duration ago = const Duration(minutes: 2), String kind = 'image', String caption = '', bool mine = false}) => {
      'id': _pid(i), 'user': {'id': 'SA000000$i', 'nickname': 'user$i'}, 'kind': kind, 'caption': caption,
      'mediaUrl': kind == 'text' ? null : 'https://test.local/chat/media/p$i.${kind == 'video' ? 'mp4' : 'jpg'}', 'overlays': [], 'tag': 'moment', 'placeName': i == 1 ? 'الكورنيش' : null,
      'lat': 21.54, 'lng': 39.17, 'status': 'active', 'views': 0, 'likes': i == 1 ? 7 : 0, 'liked': false, 'mine': mine, 'expired': false,
      'createdAt': DateTime.now().subtract(ago).toUtc().toIso8601String(), 'expiresAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
    };

/// بطاقة لحظة كما يبنيها server/row.js من المنشور.
Map<String, dynamic> _momentItem(Map<String, dynamic> p) => {
      'kind': 'moment', 'id': p['id'], 'refId': p['id'], 'title': (p['caption'] as String).isNotEmpty ? p['caption'] : '${p['kind'] == 'video' ? 'فيديو' : 'صورة'} من ${(p['user'] as Map)['nickname']}',
      'subtitle': 'الآن', 'who': (p['user'] as Map)['nickname'], 'logoUrl': null, 'imageUrl': p['kind'] == 'text' ? null : p['mediaUrl'],
      'lat': p['lat'], 'lng': p['lng'], 'distanceKm': 0.4, 'at': p['createdAt'], 'endsAt': p['expiresAt'], 'act': 'شاهد', 'payload': p,
    };

Map<String, dynamic> _item(String kind, String id, {String title = '', String who = 'دائرة', String? refId, Duration ago = const Duration(minutes: 5), String? imageUrl}) => {
      'kind': kind, 'id': id, 'refId': refId ?? id, 'title': title.isEmpty ? '$kind $id' : title, 'subtitle': 'سطر $kind', 'who': who, 'logoUrl': null, 'imageUrl': imageUrl,
      'lat': 21.5, 'lng': 39.2, 'distanceKm': 1.2, 'at': DateTime.now().subtract(ago).toUtc().toIso8601String(), 'endsAt': null, 'act': RowItem.defaultAct(kind), 'payload': {},
    };

class _Srv {
  final calls = <String>[];
  /// طلبات /feed كاملة بمعاملاتها (kind، before)
  final feeds = <Map<String, String>>[];
  /// عناصر البث بصيغة /row الأحدث أولاً؛ /feed يرشّحها بالنوع ويصفّحها بالمؤشر
  List<Map<String, dynamic>> items = [];
  int pageSize = 30;
  bool feedFail = false;
  /// بوابتان تحجزان ردّ الصفحة الأولى أو صفحة `before` حتى تُفتحا (لترتيب الطلبات المتزامنة)؛ الردّ يُحسب بعد فتحها
  Completer<void>? firstGate, moreGate;
  final deleted = <String>[];
  final live = <Map<String, dynamic>>[];
  int liveSeq = 0;
  bool liveFail = false;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if (key == 'GET /feed') {
      if (feedFail) return _json({'error': 'down'}, 503);
      final q = req.url.queryParameters;
      feeds.add(q);
      final kind = q['kind'] ?? 'all';
      final before = q['before'];
      final gate = before == null ? firstGate : moreGate;
      if (gate != null) await gate.future;
      var list = items.where((it) => kind == 'all' || it['kind'] == kind).toList();
      // المؤشر معتم كما يرسله الخادم (`<at>~<ترتيب النوع>~<id>`): التطبيق يعيده حرفياً والخادم الوهمي وحده يحلّله
      if (before != null) list = list.where((it) => DateTime.parse(it['at'] as String).isBefore(DateTime.parse(before.split('~').first))).toList();
      final page = list.take(pageSize).toList();
      return _json({'items': page, 'next': page.length == pageSize && list.length > pageSize ? _cursor(page.last) : null, 'located': q.containsKey('lat')});
    }
    if (req.method == 'DELETE' && req.url.path.startsWith('/mapposts/')) {
      final id = req.url.pathSegments.last;
      deleted.add(id);
      items.removeWhere((it) => it['kind'] == 'moment' && it['id'] == id);
      return _json({'ok': true});
    }
    if (key == 'GET /live/wait') {
      if (liveFail) return _json({'error': 'down'}, 503);
      if (!req.url.queryParameters.containsKey('after')) return _json({'seq': liveSeq, 'events': [], 'reset': false});
      final evs = [for (final e in live) {'seq': ++liveSeq, 'kind': e['kind'], 'at': DateTime.now().toUtc().toIso8601String(), 'data': e['data'] ?? {}}];
      live.clear();
      return _json({'seq': liveSeq, 'events': evs, 'reset': false});
    }
    if (key == 'GET /row') return _json({'items': [], 'located': true});
    if (key == 'GET /mapposts') return _json([]);
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /settings/public') return _json({'announcement': '', 'maintenance': false});
    if (key.startsWith('GET /biz/')) return _json({'id': 'biz-1', 'name': 'كافيه', 'category': 'cafe', 'lat': 21.5, 'lng': 39.2, 'offers': []});
    if (req.method == 'GET') return _json([]);
    return _json({'ok': true});
  }
}

Future<_Srv> _pump(WidgetTester tester, {Widget home = const TimelinePage(), _Srv? srv, Size size = const Size(420, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  DeviceLocation.override = () async => const LatLng(21.54, 39.17);
  addTearDown(() => DeviceLocation.override = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle))..token = 't';
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())), notifyPollIntervalProvider.overrideWithValue(null)],
    // التطبيق عربي من اليمين إلى اليسار؛ الاختبار بلا مفوّضي الترجمة فنفرض الاتجاه كما في الإنتاج
    child: MaterialApp(locale: const Locale('ar'), builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!), home: home),
  ));
  await _settle(tester);
  return s;
}

Future<void> _settle(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// الرقاقات الأخيرة خارج الشاشة الضيقة: نمرّر الشريط إليها ثم نلمسها
Future<void> _tapChip(WidgetTester tester, String kind) async {
  await tester.ensureVisible(find.byKey(Key('feed-kind-$kind')));
  await tester.pump();
  await tester.tap(find.byKey(Key('feed-kind-$kind')));
}

String _cursor(Map<String, dynamic> it) => '${it['at']}~0~${it['id']}';

int _fetches(_Srv s) => s.calls.where((c) => c == 'GET /feed').length;
int _mores(_Srv s) => s.feeds.where((q) => q['before'] != null).length;

/// موضع تمرير الشبكة
double _offset(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('tl-list')), matching: find.byType(Scrollable)).first).position.pixels;
int _waits(_Srv s) => s.calls.where((c) => c == 'GET /live/wait').length;

void main() {
  tearDown(() {
    ApiClient.onUnauthorized = null;
    VideoView.factoryOverride = null;
  });

  testWidgets('renders /feed items as cards in two columns, newest first, with «عام» selected and the live counter', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'صباح جدة')), _item('offer', 'of-1', title: 'خصم القهوة'), _momentItem(_post(2, ago: const Duration(hours: 5), kind: 'text', caption: 'مساء جدة')), _item('event', 'ev-1', title: 'أمسية الكورنيش')];
    await _pump(tester, srv: srv);
    expect(find.text('اللحظات'), findsOneWidget);
    expect(srv.feeds.single['kind'], 'all');
    expect(srv.feeds.single['lat'], isNotNull);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('feed-kind-all'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('feed-kind-offer'))).selected, isFalse);
    expect(find.text('مباشر · 4'), findsOneWidget);
    final a = find.byKey(Key('tl-post-${_pid(1)}')), b = find.byKey(const Key('tl-card-offer-of-1')), c = find.byKey(Key('tl-post-${_pid(2)}'));
    expect(a, findsOneWidget);
    expect(find.text('صباح جدة'), findsOneWidget);
    expect(find.text('خصم القهوة'), findsOneWidget);
    // عمودان: الأولى والثانية جنباً إلى جنب، والثالثة تحت الأولى في العمود نفسه (العربية: الأول يميناً)
    expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
    expect(tester.getTopLeft(a).dx, greaterThan(tester.getTopLeft(b).dx));
    expect(tester.getTopLeft(c).dy, greaterThan(tester.getBottomLeft(a).dy));
    // عرض البطاقة = (العرض - 36) / 2
    expect(tester.getSize(a).width, closeTo((420 - 36) / 2, .5));
    // النص على تدرّج يعرض نصه كبيراً، والعرض يحمل فعله
    expect(find.text('مساء جدة'), findsOneWidget);
    expect(find.byKey(const Key('tl-act-offer-of-1')), findsOneWidget);
    expect(find.text('استخدم'), findsOneWidget);
    expect(find.byKey(const Key('tl-act-event-ev-1')), findsOneWidget);
    expect(find.text('تذكرة'), findsOneWidget);
    expect(find.byKey(Key('tl-act-moment-${_pid(1)}')), findsNothing, reason: 'اللحظة بلا زر فعل');
  });

  testWidgets('a chip switches the kind and refetches with kind=…, keeping the other kinds cached', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'لحظتي')), _item('offer', 'of-1', title: 'خصم القهوة'), _item('job', 'jb-1', title: 'باريستا')];
    await _pump(tester, srv: srv);
    await _tapChip(tester, 'offer');
    await _settle(tester);
    expect(srv.feeds.map((q) => q['kind']).toList(), ['all', 'offer']);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('feed-kind-offer'))).selected, isTrue);
    expect(find.text('خصم القهوة'), findsOneWidget);
    expect(find.text('لحظتي'), findsNothing);
    expect(find.text('باريستا'), findsNothing);
    await _tapChip(tester, 'job');
    await _settle(tester);
    expect(srv.feeds.last['kind'], 'job');
    expect(find.text('باريستا'), findsOneWidget);
    expect(find.text('قدّم'), findsOneWidget);
    // العودة إلى «عام»: القائمة من الذاكرة فوراً ثم تحديث في الخلفية
    await _tapChip(tester, 'all');
    await tester.pump();
    expect(find.text('لحظتي'), findsOneWidget);
    await _settle(tester);
    expect(srv.feeds.last['kind'], 'all');
    expect(_fetches(srv), 4);
  });

  testWidgets('scrolling near the end requests the next page with before=<cursor> and appends it', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 45; i++) _momentItem(_post(i, ago: Duration(minutes: i), caption: 'لحظة $i'))];
    await _pump(tester, srv: srv);
    expect(srv.feeds.length, 1);
    expect(find.byKey(Key('tl-post-${_pid(1)}')), findsOneWidget);
    expect(find.byKey(Key('tl-post-${_pid(31)}')), findsNothing);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -3600));
    await _settle(tester);
    expect(srv.feeds.length, 2);
    expect(srv.feeds[1]['before'], _cursor(srv.items[29]), reason: 'المؤشر يُعاد حرفياً');
    expect(srv.feeds[1]['kind'], 'all');
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -3000));
    await _settle(tester);
    expect(find.text('مباشر · 45'), findsOneWidget);
    expect(find.byKey(Key('tl-post-${_pid(45)}')), findsOneWidget);
    // الصفحة الأخيرة بلا مؤشر: لا طلب ثالث
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -2000));
    await _settle(tester);
    expect(srv.feeds.length, 2);
  });

  testWidgets('a moment pushed over the live channel appears at the top without a refetch, and its removal drops the card', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'قديمة'))];
    await _pump(tester, srv: srv);
    expect(_waits(srv), greaterThanOrEqualTo(1), reason: 'المصافحة ثم الانتظار');
    expect(find.byKey(const Key('tl-live-on')), findsOneWidget);
    srv.live.add({'kind': 'post', 'data': _post(9, caption: 'لحظة حيّة')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('لحظة حيّة'), findsOneWidget);
    expect(find.text('مباشر · 2'), findsOneWidget);
    expect(_fetches(srv), 1, reason: 'الحمولة تأتي مع الحدث فلا جلب');
    expect(find.byKey(const Key('tl-new')), findsNothing);
    // الجديدة في أعلى العمود الأول والقديمة بجانبها
    expect(tester.getTopLeft(find.byKey(Key('tl-post-${_pid(9)}'))).dx, greaterThan(tester.getTopLeft(find.byKey(Key('tl-post-${_pid(1)}'))).dx));
    srv.live.add({'kind': 'post_removed', 'data': {'id': _pid(9)}});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('لحظة حيّة'), findsNothing);
    expect(find.text('مباشر · 1'), findsOneWidget);
    // الحلقة لا تدور بلا توقف مع خادم يعود فوراً: استراحة ثانية بين طلبين فارغين
    final before = _waits(srv);
    await tester.pump(const Duration(seconds: 10));
    expect(_waits(srv) - before, inInclusiveRange(8, 12));
  });

  testWidgets('a live moment is ignored on the «عروض» chip but counted on «لحظات»', (tester) async {
    final srv = _Srv()..items = [_item('offer', 'of-1', title: 'خصم'), _momentItem(_post(1, caption: 'قديمة'))];
    await _pump(tester, srv: srv);
    await _tapChip(tester, 'offer');
    await _settle(tester);
    srv.live.add({'kind': 'post', 'data': _post(9, caption: 'لحظة حيّة')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('لحظة حيّة'), findsNothing);
    await _tapChip(tester, 'moment');
    await _settle(tester);
    srv.live.add({'kind': 'post', 'data': _post(8, caption: 'لحظة ثانية')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('لحظة ثانية'), findsOneWidget);
    expect(find.text('خصم'), findsNothing);
  });

  testWidgets('a live moment while scrolled down waits behind the «جديدة» pill', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 25; i++) _momentItem(_post(i, ago: Duration(minutes: 20 + i)))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -1200));
    await _settle(tester, 2);
    srv.live.add({'kind': 'post', 'data': _post(99, caption: 'وصلت حيّة')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.byKey(const Key('tl-new')), findsOneWidget);
    expect(find.text('لحظة جديدة'), findsOneWidget);
    expect(find.text('وصلت حيّة'), findsNothing);
    await tester.tap(find.byKey(const Key('tl-new')));
    await _settle(tester, 3);
    expect(find.byKey(const Key('tl-new')), findsNothing);
    expect(find.text('وصلت حيّة'), findsOneWidget);
  });

  testWidgets('the periodic refresh while scrolled down puts new items behind the pill instead of jumping the grid', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 25; i++) _momentItem(_post(i, ago: Duration(minutes: 20 + i)))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -1200));
    await _settle(tester, 2);
    srv.items = [_momentItem(_post(98, caption: 'جديدة جداً')), _momentItem(_post(97, caption: 'وجديدة')), ...srv.items];
    await tester.pump(TimelinePage.refreshEvery + const Duration(seconds: 1));
    await _settle(tester);
    expect(_fetches(srv), 2);
    expect(find.byKey(const Key('tl-new')), findsOneWidget);
    expect(find.text('2 جديدة'), findsOneWidget);
    expect(find.text('جديدة جداً'), findsNothing);
    await tester.tap(find.byKey(const Key('tl-new')));
    await _settle(tester, 3);
    expect(find.text('جديدة جداً'), findsOneWidget);
    expect(find.text('وجديدة'), findsOneWidget);
    expect(find.text('مباشر · 27'), findsOneWidget);
  });

  testWidgets('tapping a moment opens the viewer at that moment among the list moments; an offer opens its circle offers', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'الأولى')), _item('offer', 'of-1', title: 'خصم القهوة', refId: 'biz-cafe', who: 'كافيه'), _momentItem(_post(2, caption: 'الثانية'))];
    await _pump(tester, srv: srv);
    await tester.tap(find.text('الثانية'));
    await _settle(tester, 4);
    expect(find.byType(PostViewerPage), findsOneWidget);
    final v = tester.widget<PostViewerPage>(find.byType(PostViewerPage));
    expect(v.posts.map((p) => p.id).toList(), [_pid(1), _pid(2)]);
    expect(v.initial, 1);
    Navigator.of(tester.element(find.byType(PostViewerPage))).pop();
    await _settle(tester, 3);
    await tester.tap(find.text('خصم القهوة'));
    await _settle(tester, 4);
    expect(find.byType(CircleOffersPage), findsOneWidget);
    expect(tester.widget<CircleOffersPage>(find.byType(CircleOffersPage)).bizId, 'biz-cafe');
  });

  testWidgets('video cards loop muted without controls, at most four at once; the fifth shows its poster', (tester) async {
    final videos = <Map<String, Object>>[];
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false, controls = true}) {
      videos.add({'url': url, 'autoplay': autoplay, 'loop': loop, 'muted': muted, 'controls': controls});
      return Container(key: const Key('fake-video'), color: Colors.black);
    };
    final srv = _Srv()..items = [for (var i = 1; i <= 5; i++) _momentItem(_post(i, ago: Duration(minutes: i), kind: 'video', caption: 'فيديو $i'))];
    await _pump(tester, srv: srv, size: const Size(420, 1400));
    expect(find.byKey(const Key('tl-video-loop')), findsNWidgets(4));
    expect(find.byKey(const Key('tl-video-poster')), findsOneWidget);
    expect(videos.length, 4);
    for (final v in videos) {
      expect(v['autoplay'], isTrue);
      expect(v['loop'], isTrue);
      expect(v['muted'], isTrue);
      expect(v['controls'], isFalse);
      expect(v['url'].toString(), contains('/chat/media/p'));
    }
  });

  testWidgets('with animations disabled, videos show posters and images do not animate', (tester) async {
    var created = 0;
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false, controls = true}) {
      created++;
      return const SizedBox();
    };
    final srv = _Srv()..items = [_momentItem(_post(1, kind: 'video')), _momentItem(_post(2))];
    await _pump(tester, srv: srv, home: const MediaQuery(data: MediaQueryData(disableAnimations: true), child: TimelinePage()));
    expect(created, 0);
    expect(find.byKey(const Key('tl-video-poster')), findsOneWidget);
    expect(find.byKey(const Key('tl-kenburns')), findsNothing);
  });

  testWidgets('image and typographic cards breathe with a slow zoom', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1)), _momentItem(_post(2, kind: 'text', caption: 'نص'))];
    await _pump(tester, srv: srv);
    expect(find.byKey(const Key('tl-kenburns')), findsNWidgets(2));
  });

  testWidgets('the empty «عام» state invites to share a moment; «وظائف» empty state points to the jobs page', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv: srv);
    expect(find.byKey(const Key('tl-empty')), findsOneWidget);
    expect(find.text('المدينة هادئة الآن'), findsOneWidget);
    expect(find.byKey(const Key('tl-compose')), findsOneWidget);
    expect(find.text('شارك لحظة الآن'), findsOneWidget);
    await _tapChip(tester, 'job');
    await _settle(tester);
    expect(find.text('لا وظائف معلنة الآن'), findsOneWidget);
    expect(find.byKey(const Key('tl-go-job')), findsOneWidget);
    expect(find.byKey(const Key('tl-compose')), findsNothing);
  });

  testWidgets('a failed first fetch shows a retry that refetches', (tester) async {
    final srv = _Srv()..feedFail = true;
    await _pump(tester, srv: srv);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    srv.feedFail = false;
    srv.items = [_momentItem(_post(1, caption: 'عادت'))];
    await tester.tap(find.text('إعادة المحاولة'));
    await _settle(tester);
    expect(find.text('عادت'), findsOneWidget);
  });

  testWidgets('the live dot goes grey while the channel fails and red again when it recovers; the fallback refresh still works', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1))]..liveFail = true;
    await _pump(tester, srv: srv);
    expect(find.byKey(const Key('tl-live-off')), findsOneWidget);
    expect(find.byKey(const Key('tl-live-on')), findsNothing);
    final failed = _waits(srv);
    srv.liveFail = false;
    await tester.pump(const Duration(seconds: 5)); // تراجع 4 ثوانٍ ثم محاولة ناجحة
    await _settle(tester);
    expect(_waits(srv), greaterThan(failed));
    expect(find.byKey(const Key('tl-live-on')), findsOneWidget);
    srv.items = [_momentItem(_post(5, caption: 'من الجلب الاحتياطي')), _momentItem(_post(1))];
    await tester.pump(TimelinePage.refreshEvery + const Duration(seconds: 1));
    await _settle(tester);
    expect(find.text('من الجلب الاحتياطي'), findsOneWidget);
    expect(find.byKey(const Key('tl-new')), findsNothing, reason: 'في الأعلى يُعتمد مباشرة');
  });

  testWidgets('closing the page stops the live channel', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1))];
    await _pump(tester, srv: srv, home: Builder(builder: (context) => Scaffold(body: TextButton(key: const Key('open'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimelinePage())), child: const Text('افتح')))));
    expect(_waits(srv), 0);
    await tester.tap(find.byKey(const Key('open')));
    await _settle(tester);
    expect(_waits(srv), greaterThanOrEqualTo(1));
    await tester.pageBack();
    await _settle(tester);
    final after = _waits(srv);
    await tester.pump(const Duration(seconds: 10));
    expect(_waits(srv), after, reason: 'لا طلبات بعد مغادرة آخر مستمع');
  });

  testWidgets('the home top bar opens «اللحظات»', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1))];
    await _pump(tester, home: const Scaffold(body: MapPage(home: true)), srv: srv, size: const Size(900, 1400));
    await tester.tap(find.byKey(const Key('home-timeline')));
    await _settle(tester, 4);
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.text('اللحظات'), findsOneWidget);
    expect(find.byKey(Key('tl-post-${_pid(1)}')), findsOneWidget);
  });

  // ---- إصلاحات المراجعة (22 أكتوبر 2026)

  testWidgets('a refresh landing while the next page loads keeps the infinite scroll going', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 75; i++) _momentItem(_post(i, ago: Duration(minutes: i), caption: 'لحظة $i'))];
    await _pump(tester, srv: srv);
    // قبيل التحديث الدوري (ومهلة الطلب 20 ثانية فلا ننتظر أطول منها)
    await tester.pump(TimelinePage.refreshEvery - const Duration(seconds: 5));
    final more = Completer<void>();
    srv.moreGate = more;
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -3600));
    await _settle(tester, 2);
    expect(_mores(srv), 1);
    // التحديث الدوري يصل والصفحة الثانية ما زالت في الطريق
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(_fetches(srv), 3);
    srv.moreGate = null;
    more.complete();
    await _settle(tester);
    expect(find.text('مباشر · 60'), findsOneWidget, reason: 'الصفحة الثانية أُلحقت رغم التحديث');
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -6000));
    await _settle(tester);
    expect(_mores(srv), 2, reason: 'التصفح لم يتعلّق بعد التحديث');
    expect(find.text('مباشر · 75'), findsOneWidget);
  });

  testWidgets('a page requested with the old cursor is dropped when a refresh replaces the list, leaving no gap', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 45; i++) _momentItem(_post(i, ago: Duration(minutes: 10 + i), caption: 'لحظة $i'))];
    await _pump(tester, srv: srv);
    final first = Completer<void>(), more = Completer<void>();
    srv
      ..firstGate = first
      ..moreGate = more;
    // التحديث أولاً ثم الصفحة الأقدم بمؤشر القائمة الحالية، والخادم يجيب التحديث قبلها
    await tester.tap(find.byKey(const Key('tl-refresh')));
    await tester.pump();
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -3600));
    await tester.pump();
    expect(srv.feeds.last['before'], _cursor(srv.items[29]));
    // ثلاث جديدة قبل أن يجيب الخادم: الصفحة الأولى الجديدة تنتهي عند القديمة 27
    srv.items = [for (var i = 101; i <= 103; i++) _momentItem(_post(i, ago: Duration(minutes: i - 100), caption: 'جديدة $i')), ...srv.items];
    srv.firstGate = null;
    first.complete();
    await _settle(tester);
    srv.moreGate = null;
    more.complete();
    await _settle(tester);
    expect(find.text('مباشر · 30'), findsOneWidget, reason: 'صفحة المؤشر القديم لا تُلحق بالقائمة المستبدلة');
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -6000));
    await _settle(tester);
    expect(srv.feeds.last['before'], _cursor(srv.items[29]), reason: 'المؤشر الجديد: آخر القائمة المستبدلة');
    expect(find.text('مباشر · 48'), findsOneWidget, reason: 'لا فجوة: القديمة 28–30 وصلت');
  });

  testWidgets('more than a page of new items while scrolled: the pill replaces the list and paging continues from the new cursor', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 25; i++) _momentItem(_post(i, ago: Duration(minutes: 60 + i), caption: 'قديمة $i'))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -1200));
    await _settle(tester, 2);
    srv.items = [for (var i = 101; i <= 135; i++) _momentItem(_post(i, ago: Duration(minutes: i - 100), caption: 'جديدة $i')), ...srv.items];
    await tester.pump(TimelinePage.refreshEvery + const Duration(seconds: 1));
    await _settle(tester);
    expect(find.text('30+ جديدة'), findsOneWidget);
    expect(find.text('مباشر · 25'), findsOneWidget, reason: 'القائمة لا تقفز أثناء التصفح');
    await tester.tap(find.byKey(const Key('tl-new')));
    await _settle(tester, 3);
    expect(find.text('مباشر · 30'), findsOneWidget);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -6000));
    await _settle(tester);
    expect(srv.feeds.last['before'], _cursor(srv.items[29]));
    expect(find.text('مباشر · 60'), findsOneWidget, reason: 'الجديدة 131–135 لم تضع بين الصفحتين');
  });

  testWidgets('a live event for a moment already listed does not raise a false «new» pill', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 25; i++) _momentItem(_post(i, ago: Duration(minutes: 20 + i)))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -1200));
    await _settle(tester, 2);
    srv.live.add({'kind': 'post', 'data': _post(3, ago: const Duration(minutes: 23))});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.byKey(const Key('tl-new')), findsNothing);
    expect(find.text('مباشر · 25'), findsOneWidget);
  });

  testWidgets('a live removal reaches every opened chip, not just the visible one', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'ستُحذف')), _momentItem(_post(2, ago: const Duration(minutes: 3), caption: 'باقية')), _item('offer', 'of-1')];
    await _pump(tester, srv: srv);
    await _tapChip(tester, 'moment');
    await _settle(tester);
    expect(find.text('ستُحذف'), findsOneWidget);
    srv.items.removeAt(0);
    srv.live.add({'kind': 'post_removed', 'data': {'id': _pid(1)}});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('ستُحذف'), findsNothing);
    // العودة إلى «عام» تعرض المخزّن فوراً والتحديث ما زال في الطريق: المحذوفة لا تعود معه
    final gate = Completer<void>();
    srv.firstGate = gate;
    await _tapChip(tester, 'all');
    await tester.pump();
    expect(find.text('باقية'), findsOneWidget);
    expect(find.text('ستُحذف'), findsNothing);
    srv.firstGate = null;
    gate.complete();
    await _settle(tester);
  });

  testWidgets('a live moment beyond the feed radius is ignored while the list is ranked by location; a near one shows its distance', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'قديمة'))];
    await _pump(tester, srv: srv);
    srv.live.add({'kind': 'post', 'data': {..._post(9, caption: 'في الرياض'), 'lat': 24.71, 'lng': 46.67}});
    srv.live.add({'kind': 'post', 'data': {..._post(8, caption: 'قريبة'), 'lat': 21.55, 'lng': 39.17}});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('في الرياض'), findsNothing);
    expect(find.text('قريبة'), findsOneWidget);
    expect(find.textContaining('1.1 كم'), findsOneWidget, reason: 'المسافة محسوبة من موقع المستخدم');
    expect(find.text('مباشر · 2'), findsOneWidget);
  });

  testWidgets('deleting a moment from the viewer removes its card in place, keeping the loaded pages and the scroll position', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 45; i++) _momentItem(_post(i, ago: Duration(minutes: i), caption: 'لحظة $i', mine: true))];
    await _pump(tester, srv: srv);
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -3600));
    await _settle(tester);
    expect(find.text('مباشر · 45'), findsOneWidget);
    // بطاقة ظاهرة من الصفحة الأولى
    final target = [for (var i = 30; i >= 1; i--) i].firstWhere((i) => find.byKey(Key('tl-post-${_pid(i)}')).hitTestable().evaluate().isNotEmpty);
    final offset = _offset(tester);
    expect(offset, greaterThan(1000));
    await tester.tap(find.byKey(Key('tl-post-${_pid(target)}')).hitTestable());
    await _settle(tester, 3);
    expect(find.byType(PostViewerPage), findsOneWidget);
    await tester.tap(find.byTooltip('خيارات').hitTestable().first);
    await _settle(tester, 2);
    await tester.tap(find.text('حذف المنشور'));
    await _settle(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await _settle(tester, 3);
    expect(srv.deleted, hasLength(1));
    Navigator.of(tester.element(find.byType(PostViewerPage))).pop();
    await _settle(tester, 3);
    expect(find.text('مباشر · 44'), findsOneWidget, reason: 'الصفحتان باقيتان ناقص المحذوفة');
    expect(find.byKey(Key('tl-post-${srv.deleted.single}')), findsNothing);
    expect(_offset(tester), closeTo(offset, 1), reason: 'موضع التمرير باقٍ');
  });

  testWidgets('after the grid is rebuilt from empty at offset 0, a live moment goes straight to the top, not behind a pill', (tester) async {
    final srv = _Srv()..items = [for (var i = 1; i <= 4; i++) _momentItem(_post(i, ago: Duration(minutes: i)))];
    await _pump(tester, srv: srv, size: const Size(420, 500));
    await tester.drag(find.byKey(const Key('tl-list')), const Offset(0, -300));
    await _settle(tester, 2);
    expect(_offset(tester), greaterThan(40));
    for (var i = 1; i <= 4; i++) {
      srv.live.add({'kind': 'post_removed', 'data': {'id': _pid(i)}});
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.byKey(const Key('tl-empty')), findsOneWidget);
    srv.live.add({'kind': 'post', 'data': _post(9, caption: 'بعد الفراغ')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('بعد الفراغ'), findsOneWidget);
    expect(find.byKey(const Key('tl-new')), findsNothing);
  });

  testWidgets('a new item at the top keeps the four looping previews playing, each over its poster, without recreating them', (tester) async {
    final videos = <String>[];
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false, controls = true}) {
      videos.add(url);
      return Container(key: const Key('fake-video'), color: Colors.black);
    };
    final srv = _Srv()..items = [for (var i = 1; i <= 4; i++) _momentItem(_post(i, ago: Duration(minutes: i), kind: 'video', caption: 'فيديو $i'))];
    await _pump(tester, srv: srv, size: const Size(420, 1400));
    expect(find.byKey(const Key('tl-video-loop')), findsNWidgets(4));
    // الإطار الثابت تحت كل معاينة دائرة: لا لوحة فارغة ريثما يجهز المقطع
    expect(find.byKey(const Key('tl-video-under')), findsNWidgets(4));
    srv.live.add({'kind': 'post', 'data': _post(9, caption: 'صورة حيّة')});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('صورة حيّة'), findsOneWidget);
    expect(find.byKey(const Key('tl-video-loop')), findsNWidgets(4));
    expect(find.byKey(const Key('tl-video-poster')), findsNothing);
    expect(videos, hasLength(4), reason: 'البطاقات القائمة تنتقل فلا يُعاد إنشاء مشغّلاتها');
  });

  testWidgets('when a looping preview leaves, the waiting poster takes its slot and loops', (tester) async {
    VideoView.factoryOverride = (url, {autoplay = false, loop = false, muted = false, controls = true}) => Container(key: const Key('fake-video'), color: Colors.black);
    final srv = _Srv()..items = [for (var i = 1; i <= 5; i++) _momentItem(_post(i, ago: Duration(minutes: i), kind: 'video', caption: 'فيديو $i'))];
    await _pump(tester, srv: srv, size: const Size(420, 1400));
    expect(find.byKey(const Key('tl-video-loop')), findsNWidgets(4));
    expect(find.byKey(const Key('tl-video-poster')), findsOneWidget);
    srv.live.add({'kind': 'post_removed', 'data': {'id': _pid(1)}});
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.byKey(const Key('tl-video-loop')), findsNWidgets(4));
    expect(find.byKey(const Key('tl-video-poster')), findsNothing);
  });

  testWidgets('on iOS/Android a looping preview stays transparent while loading and on failure, so the poster beneath shows', (tester) async {
    nativeMobileOverride = true;
    addTearDown(() => nativeMobileOverride = null);
    // بيئة الاختبار بلا مشغّل أصلي: التهيئة تفشل كما يفشل مقطع تالف
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 200, height: 300, child: VideoView(url: 'https://test.local/chat/media/v.mp4', autoplay: true, loop: true, muted: true, controls: false)))));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('تعذر تشغيل الفيديو'), findsNothing);
    expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);
  });

  testWidgets('cards fit at a large text scale without overflowing', (tester) async {
    final srv = _Srv()
      ..items = [
        _momentItem(_post(1, kind: 'text', caption: 'نص طويل جداً ' * 12)),
        _momentItem(_post(2, kind: 'text', caption: 'سطر')),
        _item('event', 'ev-1', title: 'أمسية طويلة العنوان ' * 4, who: 'دائرة باسم طويل جداً جداً'),
        _item('job', 'jb-1', title: 'وظيفة', who: 'شركة ' * 10),
        _momentItem(_post(3, caption: 'صورة')),
      ];
    await _pump(tester, srv: srv, home: Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: const TimelinePage())));
    expect(tester.takeException(), isNull);
    expect(find.byKey(Key('tl-post-${_pid(1)}')), findsOneWidget);
    expect(find.byKey(const Key('tl-card-event-ev-1')), findsOneWidget);
  });

  testWidgets('pull-to-refresh works when the grid (or the empty state) is shorter than the screen', (tester) async {
    final srv = _Srv()..items = [_momentItem(_post(1, caption: 'وحيدة'))];
    await _pump(tester, srv: srv);
    expect(_fetches(srv), 1);
    await tester.fling(find.byKey(const Key('tl-list')), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(_fetches(srv), 2);
    srv.items = [];
    await tester.tap(find.byKey(const Key('tl-refresh')));
    await _settle(tester);
    expect(find.byKey(const Key('tl-empty')), findsOneWidget);
    final n = _fetches(srv);
    await tester.fling(find.byKey(const Key('tl-empty')), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(_fetches(srv), n + 1);
  });
}
