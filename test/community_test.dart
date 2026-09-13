// دائرة المطار ومساحة المجتمع: تصنيف مطار، بطاقة الدخول في صفحة الدائرة، الخيط بالمثبّت والشارات، تصفية المواضيع،
// النشر بنص وموضوع وصورة مرفوعة، النقاش بالردود والإعجاب، وقائمة الإدارة والبلاغ.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/community_api.dart';
import 'package:naslook/api/notify_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/media/pick_image.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/community_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();
Map<String, dynamic> _person(String id, String n) => {'id': id, 'nickname': n, 'avatarUrl': null};

Map<String, dynamic> _airport() => {
      'id': 'biz-kaia', 'name': 'King Abdulaziz International Airport', 'nameAr': 'مطار الملك عبدالعزيز الدولي بجدة', 'category': 'airport', 'sector': 'مطار دولي',
      'description': 'بوابة جدة الجوية', 'lat': 21.6796, 'lng': 39.1568, 'address': 'شمال جدة', 'hours': '24 ساعة', 'phone': '8001168888', 'website': 'https://www.jed-airport.com', 'color': '#0E5C8A',
      'highlights': ['الصالة 1', 'صالة الحج'], 'followers': 10, 'itemsCount': 2, 'active': true, 'reviews': [], 'myOrders': [], 'posts': [],
      'items': [
        {'id': 'kaia-lost', 'bizId': 'biz-kaia', 'kind': 'info', 'title': 'الأمتعة المفقودة والموجودات', 'description': 'مكتب الموجودات في قاعة الوصول', 'price': 0, 'unit': 'item', 'meta': {'hours': '24 ساعة', 'location': 'الصالة 1 · قاعة الوصول', 'phone': '8001168888'}, 'active': true},
        {'id': 'kaia-wifi', 'bizId': 'biz-kaia', 'kind': 'info', 'title': 'الواي فاي المجاني ونقاط الشحن', 'description': 'شبكة مجانية في كل الصالات', 'price': 0, 'unit': 'item', 'meta': {'hours': '24 ساعة'}, 'active': true},
      ],
    };

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final queries = <String, Map<String, String>>{};
  bool moderator = false;
  int uploads = 0;
  late final posts = <Map<String, dynamic>>[
    {'id': 'c-2', 'bizId': 'biz-kaia', 'user': _person('SA0000002', 'sara'), 'topic': 'photo', 'text': 'الصالة الجديدة من الداخل', 'images': ['/chat/media/a.jpg', '/chat/media/b.jpg'], 'pinned': false, 'hidden': false, 'likes': 2, 'liked': false, 'replies': 0, 'mine': false, 'staff': false, 'createdAt': _ago(const Duration(hours: 5))},
    {'id': 'c-1', 'bizId': 'biz-kaia', 'user': _person('SA0000003', 'khalid'), 'topic': 'general', 'text': 'أهلاً بكم في مساحة المطار، نرد على استفساراتكم هنا', 'images': [], 'pinned': true, 'hidden': false, 'likes': 4, 'liked': false, 'replies': 1, 'mine': false, 'staff': true, 'createdAt': _ago(const Duration(days: 3))},
    {'id': 'c-3', 'bizId': 'biz-kaia', 'user': _person('SA0000001', 'amr'), 'topic': 'question', 'text': 'هل يوجد مصلى في صالة الحج؟', 'images': [], 'pinned': false, 'hidden': false, 'likes': 0, 'liked': false, 'replies': 2, 'mine': true, 'staff': false, 'createdAt': _ago(const Duration(minutes: 30))},
  ];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    queries[key] = req.url.queryParameters;
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /biz/biz-kaia') return _json(_airport());
    if (key == 'GET /biz/biz-kaia/community') {
      final topic = req.url.queryParameters['topic'];
      final list = [for (final p in posts) if (topic == null || p['topic'] == topic) p]..sort((a, b) => ((b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0)) != 0 ? ((b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0)) : (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return _json({'posts': list, 'total': posts.length, 'members': 3, 'canModerate': moderator, 'hasMore': false});
    }
    if (key == 'POST /biz/biz-kaia/community') {
      final b = bodies[key]!;
      if ((b['text'] as String).contains('احتيال')) return _json({'error': 'banned-words', 'word': 'احتيال'}, 400);
      final p = {'id': 'c-new', 'bizId': 'biz-kaia', 'user': _person('SA0000001', 'amr'), 'topic': b['topic'], 'text': b['text'], 'images': b['images'], 'pinned': false, 'hidden': false, 'likes': 0, 'liked': false, 'replies': 0, 'mine': true, 'staff': false, 'createdAt': _ago(Duration.zero)};
      posts.insert(0, p);
      return _json(p);
    }
    if (key == 'GET /biz/biz-kaia/community/c-3') {
      return _json({'post': posts.firstWhere((p) => p['id'] == 'c-3'), 'replies': [
        {'id': 'r-1', 'postId': 'c-3', 'user': _person('SA0000003', 'khalid'), 'text': 'نعم، مصليات للرجال والنساء قرب البوابات', 'mine': false, 'createdAt': _ago(const Duration(minutes: 20))},
        {'id': 'r-2', 'postId': 'c-3', 'user': _person('SA0000001', 'amr'), 'text': 'شكراً', 'mine': true, 'createdAt': _ago(const Duration(minutes: 10))},
      ], 'canModerate': moderator});
    }
    if (key == 'POST /biz/biz-kaia/community/c-3/replies') return _json({'id': 'r-3', 'postId': 'c-3', 'user': _person('SA0000001', 'amr'), 'text': bodies[key]!['text'], 'mine': true, 'createdAt': _ago(Duration.zero)});
    if (key == 'POST /biz/biz-kaia/community/c-2/like') return _json({'ok': true, 'liked': true, 'likes': 3});
    if (key == 'POST /biz/biz-kaia/community/c-2/pin') return _json({...posts.firstWhere((p) => p['id'] == 'c-2'), 'pinned': bodies[key]!['pinned']});
    if (key == 'POST /biz/biz-kaia/community/c-2/hide') return _json({...posts.firstWhere((p) => p['id'] == 'c-2'), 'hidden': bodies[key]!['hidden']});
    if (key == 'POST /chat/upload') {
      uploads++;
      return _json({'url': '/chat/media/up$uploads.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': req.bodyBytes.length});
    }
    if (key == 'POST /safety/report') return _json({'ok': true, 'reports': 1, 'hidden': false, 'threshold': 3});
    if (key == 'GET /safety/words') return _json({'words': ['احتيال'], 'threshold': 3});
    if (key == 'GET /wallet') return _json({'balance': 0, 'points': 0});
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /wishlist') return _json([]);
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {bool moderator = false}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final srv = _Srv()..moderator = moderator;
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return srv;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  test('airport category and community models', () {
    expect(BizCategory.of('airport'), BizCategory.airport);
    expect(BizCategory.airport.itemKind, 'info');
    expect(BizCategory.airport.catalogTitle, 'مرافق المطار والخدمات');
    final p = CommunityPost.fromJson({'id': 'x', 'bizId': 'biz-kaia', 'user': _person('SA0000002', 'sara'), 'topic': 'tip', 'text': 'نصيحة', 'images': ['/chat/media/a.jpg'], 'pinned': true, 'likes': 3, 'liked': true, 'replies': 1, 'staff': true, 'createdAt': '2026-09-13T01:00:00Z'});
    expect(p.topicLabel, 'نصيحة');
    expect(p.images.single, '/chat/media/a.jpg');
    expect(p.copyWith(liked: false, likes: 2).likes, 2);
    expect(communityTopics.keys, ['general', 'photo', 'question', 'tip', 'alert']);
    // وجهات الإشعارات
    final n = AppNotification.fromJson({'id': 'n1', 'kind': 'community_reply', 'title': 'رد', 'body': '', 'data': {'bizId': 'biz-kaia', 'postId': 'c-3'}, 'read': false, 'createdAt': '2026-09-13T01:00:00Z'});
    expect(notificationTarget(n), isA<CommunityPage>());
    expect((notificationTarget(n) as CommunityPage).initialPostId, 'c-3');
  });

  testWidgets('airport page lists facilities and a prominent community card that opens the space', (tester) async {
    final srv = await _pump(tester, const BusinessPage(id: 'biz-kaia'));
    await _settle(tester);
    expect(find.text('مطار الملك عبدالعزيز الدولي بجدة'), findsWidgets);
    expect(find.text('مرافق المطار والخدمات'), findsOneWidget);
    expect(find.text('الأمتعة المفقودة والموجودات'), findsOneWidget);
    expect(find.text('الواي فاي المجاني ونقاط الشحن'), findsOneWidget);
    expect(find.text('اشترِ'), findsNothing);
    expect(find.byKey(const Key('community-card')), findsOneWidget);
    expect(find.text('3 مشاركة من 3 مشارك'), findsOneWidget);
    expect(find.textContaining('أهلاً بكم في مساحة المطار', findRichText: true), findsOneWidget, reason: 'آخر المشاركات تظهر في البطاقة');
    await tester.tap(find.byKey(const Key('community-open')));
    await _settle(tester);
    expect(find.byType(CommunityPage), findsOneWidget);
    expect(find.text('مساحة مطار الملك عبدالعزيز الدولي بجدة'), findsOneWidget);
    expect(srv.calls.where((c) => c == 'GET /biz/biz-kaia/community').length, greaterThanOrEqualTo(1));
  });

  testWidgets('feed: pinned first with staff badge, topic filter, and posting text with a topic', (tester) async {
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'));
    await _settle(tester);
    expect(find.text('3 مشاركة · 3 مشارك'), findsOneWidget);
    final cards = find.byType(CommunityPostCard);
    expect(cards, findsNWidgets(3));
    final first = tester.widget<CommunityPostCard>(cards.first);
    expect(first.post.id, 'c-1', reason: 'المثبّت أولاً');
    expect(find.text('مثبّت'), findsOneWidget);
    expect(find.text('فريق الدائرة'), findsOneWidget);
    expect(find.text('أنت'), findsOneWidget, reason: 'مشاركتي تُعرض باسم «أنت»');
    expect(find.text('2 ردّان'), findsOneWidget);
    // تصفية بموضوع الأسئلة
    await tester.tap(find.byKey(const Key('community-topic-question')));
    await _settle(tester);
    expect(srv.queries['GET /biz/biz-kaia/community']?['topic'], 'question');
    expect(find.byType(CommunityPostCard), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-topic-all')));
    await _settle(tester);
    expect(find.byType(CommunityPostCard), findsNWidgets(3));
    // النشر: زر الإرسال معطّل بلا نص
    expect(tester.widget<IconButton>(find.byKey(const Key('community-send'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('community-input')), 'استخدموا بوابات الجوازات الذكية');
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-topic')));
    await _settle(tester);
    await tester.tap(find.text('نصيحة').last);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-kaia/community']!;
    expect(body['topic'], 'tip');
    expect(body['text'], 'استخدموا بوابات الجوازات الذكية');
    expect(body['images'], isEmpty);
    expect(find.byType(CommunityPostCard), findsNWidgets(4));
    expect(tester.widget<TextField>(find.byKey(const Key('community-input'))).controller!.text, isEmpty);
    // كلمة محظورة تُرفض قبل الإرسال
    await tester.enterText(find.byKey(const Key('community-input')), 'هذا احتيال');
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    expect(find.textContaining('كلمة غير مسموحة'), findsOneWidget);
    expect(srv.calls.where((c) => c == 'POST /biz/biz-kaia/community').length, 1);
  });

  testWidgets('composer uploads a picked photo and sends its url with the photo topic', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList(png), mime: 'image/png', name: 'gate.png');
    addTearDown(() => pickImageOverride = null);
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-photo')));
    await _settle(tester);
    expect(srv.calls, contains('POST /chat/upload'));
    expect(find.byType(Image), findsWidgets);
    expect(tester.widget<IconButton>(find.byKey(const Key('community-send'))).onPressed, isNotNull, reason: 'صورة بلا نص تكفي للنشر');
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-kaia/community']!;
    expect(body['topic'], 'photo');
    expect(body['images'], ['/chat/media/up1.jpg']);
  });

  testWidgets('thread: replies listed, reply sent, like toggles from the feed', (tester) async {
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-like-c-2')));
    await _settle(tester);
    expect(srv.calls, contains('POST /biz/biz-kaia/community/c-2/like'));
    expect(find.text('3'), findsOneWidget, reason: 'عدّاد الإعجاب يتحدث فوراً');
    await tester.tap(find.text('هل يوجد مصلى في صالة الحج؟'));
    await _settle(tester);
    expect(find.byType(CommunityThreadPage), findsOneWidget);
    expect(find.text('نعم، مصليات للرجال والنساء قرب البوابات'), findsOneWidget);
    expect(find.text('شكراً'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-reply-input')), 'وأين المصلى في الوصول؟');
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-reply-send')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-kaia/community/c-3/replies']!['text'], 'وأين المصلى في الوصول؟');
  });

  testWidgets('moderator menu pins and hides; others can report', (tester) async {
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'), moderator: true);
    await _settle(tester);
    final saraCard = find.ancestor(of: find.text('الصالة الجديدة من الداخل'), matching: find.byType(CommunityPostCard));
    await tester.tap(find.descendant(of: saraCard, matching: find.byTooltip('خيارات')));
    await _settle(tester);
    expect(find.byKey(const Key('community-menu-pin')), findsOneWidget);
    expect(find.byKey(const Key('community-menu-hide')), findsOneWidget);
    expect(find.byKey(const Key('community-menu-report')), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-menu-pin')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-kaia/community/c-2/pin']!['pinned'], true);
    expect(find.text('مثبّت'), findsNWidgets(2));
    await tester.tap(find.descendant(of: saraCard, matching: find.byTooltip('خيارات')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-menu-hide')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-kaia/community/c-2/hide']!['hidden'], true);
    expect(find.text('مخفي'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.descendant(of: saraCard, matching: find.byTooltip('خيارات')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-menu-report')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'محتوى مسيء');
    await tester.tap(find.text('إرسال البلاغ'));
    await _settle(tester);
    final rep = srv.bodies['POST /safety/report']!;
    expect(rep['targetType'], 'community');
    expect(rep['targetId'], 'c-2');
    expect(find.textContaining('وصل بلاغك'), findsOneWidget);
  });
}
