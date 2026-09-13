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
import 'package:naslook/core/media/voice_player.dart';
import 'package:naslook/core/media/voice_record.dart';
import 'package:naslook/core/notify_open.dart';
import 'package:naslook/pages/business/business_page.dart';
import 'package:naslook/pages/business/community_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/reactions.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

/// مسجّل وهمي: يبدأ فوراً ويعيد ملفاً صوتياً بمدة ثابتة عند الإيقاف.
class _FakeRecorder implements VoiceRecordSession {
  static int cancelled = 0;
  bool _on = false;
  @override
  bool get recording => _on;
  @override
  Duration get elapsed => const Duration(seconds: 3);
  @override
  Future<void> start() async {
    _on = true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    _on = false;
    return (bytes: Uint8List.fromList(List.filled(120, 1)), mime: 'audio/webm', name: 'voice.webm', duration: const Duration(seconds: 3));
  }

  @override
  Future<void> cancel() async {
    cancelled++;
    _on = false;
  }

  @override
  void dispose() {}
}

/// مشغّل وهمي: يعلن التشغيل فوراً.
class _FakePlayer extends VoicePlayerBase {
  static int plays = 0;
  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {}
  @override
  Future<void> play() async {
    plays++;
    emit(state.copyWith(playing: true, duration: const Duration(seconds: 7)));
  }

  @override
  Future<void> pause() async => emit(state.copyWith(playing: false));
  @override
  Future<void> seek(Duration position) async => emit(state.copyWith(position: position));
  @override
  void dispose() {}
}

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();
Map<String, dynamic> _person(String id, String n) => {'id': id, 'nickname': n, 'avatarUrl': null};
Map<String, dynamic> _item(String id, String title, int price) => {'id': id, 'title': title, 'price': price, 'unit': 'item', 'kind': 'product', 'imageUrl': null};

Map<String, dynamic> _cafe() => {
      'id': 'biz-brew92', 'name': 'Brew 92', 'nameAr': 'برو 92', 'category': 'cafe', 'sector': 'محمصة وقهوة مختصة', 'description': 'محمصة', 'lat': 21.57324, 'lng': 39.14363,
      'address': 'حي الروضة، جدة', 'hours': '', 'website': 'https://www.brew92.com', 'color': '#5B2E1E', 'logoUrl': 'asset:biz/brew92.png', 'highlights': ['محمصة جداوية'], 'followers': 0, 'itemsCount': 2, 'active': true, 'reviews': [], 'myOrders': [], 'posts': [],
      'items': [
        {'id': 'brew92-v60', 'bizId': 'biz-brew92', 'kind': 'product', 'title': 'V60 تقطير', 'description': 'حبوب الموسم', 'price': 2200, 'unit': 'item', 'stock': 50, 'meta': {}, 'active': true, 'discussions': 3},
        {'id': 'brew92-latte', 'bizId': 'biz-brew92', 'kind': 'product', 'title': 'لاتيه', 'description': '', 'price': 1900, 'unit': 'item', 'stock': 50, 'meta': {}, 'active': true, 'discussions': 0},
      ],
    };

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
    {'id': 'c-4', 'bizId': 'biz-kaia', 'user': _person('SA0000003', 'khalid'), 'topic': 'tip', 'text': '', 'images': [], 'audio': '/chat/media/demo.m4a', 'audioMs': 7000, 'pinned': false, 'hidden': false, 'likes': 1, 'liked': false, 'replies': 0, 'mine': false, 'staff': true, 'createdAt': _ago(const Duration(minutes: 15))},
    {'id': 'c-1', 'bizId': 'biz-kaia', 'user': _person('SA0000003', 'khalid'), 'topic': 'general', 'text': 'أهلاً بكم في مساحة المطار، نرد على استفساراتكم هنا', 'images': [], 'pinned': true, 'hidden': false, 'likes': 4, 'liked': false, 'replies': 1, 'mine': false, 'staff': true, 'createdAt': _ago(const Duration(days: 3))},
    {'id': 'c-3', 'bizId': 'biz-kaia', 'user': _person('SA0000001', 'amr'), 'topic': 'question', 'text': 'هل يوجد مصلى في صالة الحج؟', 'images': [], 'pinned': false, 'hidden': false, 'likes': 0, 'liked': false, 'replies': 2, 'mine': true, 'staff': false, 'createdAt': _ago(const Duration(minutes: 30))},
  ];
  late final cafePosts = <Map<String, dynamic>>[
    {'id': 'b-1', 'bizId': 'biz-brew92', 'user': _person('SA0000002', 'sara'), 'topic': 'tip', 'text': 'جرّبوا الـV60 بحبوب إثيوبيا', 'images': [], 'item': _item('brew92-v60', 'V60 تقطير', 2200), 'pinned': false, 'hidden': false, 'likes': 5, 'liked': false, 'replies': 1, 'mine': false, 'staff': false, 'createdAt': _ago(const Duration(hours: 2))},
    {'id': 'b-2', 'bizId': 'biz-brew92', 'user': _person('SA0000003', 'khalid'), 'topic': 'question', 'text': 'الفلات وايت بحليب لوز؟', 'images': [], 'item': null, 'pinned': false, 'hidden': false, 'likes': 1, 'liked': false, 'replies': 0, 'mine': false, 'staff': false, 'createdAt': _ago(const Duration(hours: 1))},
  ];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    queries[key] = req.url.queryParameters;
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /biz/biz-brew92') return _json(_cafe());
    if (key == 'GET /biz/biz-brew92/community') {
      final itemId = req.url.queryParameters['itemId'];
      final top = req.url.queryParameters['sort'] == 'top';
      final list = [for (final p in cafePosts) if (itemId == null || p['item']?['id'] == itemId) p];
      if (top) {
        list.sort((a, b) => (b['likes'] as int).compareTo(a['likes'] as int));
      } else {
        list.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      }
      return _json({'posts': list, 'total': cafePosts.length, 'members': 2, 'canModerate': false, 'hasMore': false, 'topItems': itemId == null ? [{'item': _item('brew92-v60', 'V60 تقطير', 2200), 'count': 3}] : []});
    }
    if (key == 'POST /biz/biz-brew92/community') {
      final b = bodies[key]!;
      final p = {'id': 'b-new', 'bizId': 'biz-brew92', 'user': _person('SA0000001', 'amr'), 'topic': b['topic'], 'text': b['text'], 'images': b['images'], 'item': b['itemId'] == 'brew92-latte' ? _item('brew92-latte', 'لاتيه', 1900) : b['itemId'] == 'brew92-v60' ? _item('brew92-v60', 'V60 تقطير', 2200) : null, 'pinned': false, 'hidden': false, 'likes': 0, 'liked': false, 'replies': 0, 'mine': true, 'staff': false, 'createdAt': _ago(Duration.zero)};
      cafePosts.insert(0, p);
      return _json(p);
    }
    if (key == 'GET /biz/biz-brew92/community/b-1') {
      return _json({'post': cafePosts.firstWhere((p) => p['id'] == 'b-1'), 'replies': [
        {'id': 'br-1', 'postId': 'b-1', 'user': _person('SA0000003', 'khalid'), 'text': 'صحيح، والكولد برو أيضاً', 'images': [], 'item': _item('brew92-v60', 'V60 تقطير', 2200), 'likes': 2, 'liked': false, 'mine': false, 'createdAt': _ago(const Duration(minutes: 30))},
      ], 'canModerate': false});
    }
    if (key == 'POST /biz/biz-brew92/community/b-1/replies/br-1/like') return _json({'ok': true, 'liked': true, 'likes': 3});
    if (key == 'POST /biz/biz-brew92/community/b-1/like') return _json({'ok': true, 'liked': true, 'likes': 6});
    if (key == 'POST /biz/biz-brew92/community/b-1/react' || key == 'POST /biz/biz-brew92/community/b-1/replies/br-1/react') {
      final e = bodies[key]!['emoji'] as String;
      return _json({'ok': true, 'reactions': e.isEmpty ? [] : [{'emoji': e, 'count': 1, 'mine': true}]});
    }
    if (key == 'GET /biz/biz-kaia') return _json(_airport());
    if (key == 'GET /biz/biz-kaia/community') {
      final topic = req.url.queryParameters['topic'];
      final list = [for (final p in posts) if (topic == null || p['topic'] == topic) p]..sort((a, b) => ((b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0)) != 0 ? ((b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0)) : (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return _json({'posts': list, 'total': posts.length, 'members': 3, 'canModerate': moderator, 'hasMore': false});
    }
    if (key == 'POST /biz/biz-kaia/community') {
      final b = bodies[key]!;
      if ((b['text'] as String).contains('احتيال')) return _json({'error': 'banned-words', 'word': 'احتيال'}, 400);
      final p = {'id': 'c-new', 'bizId': 'biz-kaia', 'user': _person('SA0000001', 'amr'), 'topic': b['topic'], 'text': b['text'], 'images': b['images'], 'audio': b['audio'], 'audioMs': b['audioMs'], 'pinned': false, 'hidden': false, 'likes': 0, 'liked': false, 'replies': 0, 'mine': true, 'staff': false, 'createdAt': _ago(Duration.zero)};
      posts.insert(0, p);
      return _json(p);
    }
    if (key == 'GET /biz/biz-kaia/community/c-3') {
      return _json({'post': posts.firstWhere((p) => p['id'] == 'c-3'), 'replies': [
        {'id': 'r-1', 'postId': 'c-3', 'user': _person('SA0000003', 'khalid'), 'text': 'نعم، مصليات للرجال والنساء قرب البوابات', 'mine': false, 'createdAt': _ago(const Duration(minutes: 20))},
        {'id': 'r-2', 'postId': 'c-3', 'user': _person('SA0000001', 'amr'), 'text': 'شكراً', 'mine': true, 'createdAt': _ago(const Duration(minutes: 10))},
      ], 'canModerate': moderator});
    }
    if (key == 'POST /biz/biz-kaia/community/c-3/replies') return _json({'id': 'r-3', 'postId': 'c-3', 'user': _person('SA0000001', 'amr'), 'text': bodies[key]!['text'], 'images': bodies[key]!['images'], 'audio': bodies[key]!['audio'], 'audioMs': bodies[key]!['audioMs'], 'mine': true, 'createdAt': _ago(Duration.zero)});
    if (key == 'POST /biz/biz-kaia/community/c-2/like') return _json({'ok': true, 'liked': true, 'likes': 3});
    if (key == 'POST /biz/biz-kaia/community/c-2/pin') return _json({...posts.firstWhere((p) => p['id'] == 'c-2'), 'pinned': bodies[key]!['pinned']});
    if (key == 'POST /biz/biz-kaia/community/c-2/hide') return _json({...posts.firstWhere((p) => p['id'] == 'c-2'), 'hidden': bodies[key]!['hidden']});
    if (key == 'POST /chat/upload') {
      uploads++;
      final audio = (req.headers['content-type'] ?? '').startsWith('audio/');
      return _json({'url': '/chat/media/up$uploads.${audio ? 'm4a' : 'jpg'}', 'type': audio ? 'audio/mp4' : 'image/jpeg', 'kind': audio ? 'audio' : 'image', 'size': req.bodyBytes.length});
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
  test('cafe category, quoted item model and asset logo', () {
    expect(BizCategory.of('cafe'), BizCategory.cafe);
    expect(BizCategory.cafe.itemKind, 'product');
    expect(BizCategory.cafe.catalogTitle, 'القائمة');
    final biz = Biz.fromJson(_cafe());
    expect(biz.logoUrl, 'asset:biz/brew92.png');
    expect(biz.items.first.discussions, 3);
    final ref = CommunityItemRef.fromJson(_item('brew92-v60', 'V60 تقطير', 2200));
    expect(ref.priceLabel, contains('22'));
    final post = CommunityPost.fromJson({'id': 'x', 'bizId': 'biz-brew92', 'user': _person('SA0000002', 'sara'), 'topic': 'tip', 'text': '', 'item': _item('brew92-v60', 'V60 تقطير', 2200)});
    expect(post.item!.title, 'V60 تقطير');
    expect(post.preview, 'عن V60 تقطير');
    final reply = CommunityReply.fromJson({'id': 'r', 'postId': 'x', 'user': _person('SA0000003', 'khalid'), 'text': 'ok', 'likes': 2, 'liked': true, 'item': _item('brew92-latte', 'لاتيه', 1900)});
    expect(reply.likes, 2);
    expect(reply.copyWith(liked: false, likes: 1).liked, isFalse);
    final feed = CommunityFeed.fromJson({'posts': [], 'topItems': [{'item': _item('brew92-v60', 'V60 تقطير', 2200), 'count': 3}]});
    expect(feed.topItems.single.count, 3);
  });

  testWidgets('cafe page shows the bundled logo, menu prices and a discuss button that opens the space with the product quoted', (tester) async {
    final srv = await _pump(tester, const BusinessPage(id: 'biz-brew92'));
    await _settle(tester);
    expect(find.text('برو 92'), findsWidgets);
    expect(find.text('القائمة'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/biz/brew92.png'), findsWidgets, reason: 'الشعار المضمّن يُعرض');
    expect(find.text('3 نقاش'), findsOneWidget);
    expect(find.text('ناقش'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('discuss-brew92-v60')));
    await tester.tap(find.byKey(const Key('discuss-brew92-v60')));
    await _settle(tester);
    expect(find.byType(CommunityPage), findsOneWidget);
    expect(srv.queries['GET /biz/biz-brew92/community']?['itemId'], 'brew92-v60', reason: 'المساحة تُفتح مصفّاة على المنتج');
    expect(find.textContaining('النقاش عن: V60 تقطير'), findsOneWidget);
    expect(find.byKey(const Key('community-quote-chip')), findsOneWidget, reason: 'الاقتباس جاهز في المؤلّف');
    expect(find.byType(CommunityPostCard), findsOneWidget);
    // إزالة التصفية تعرض كل المساحة وشريط الأكثر نقاشاً
    await tester.tap(find.byKey(const Key('community-filter-clear')));
    await _settle(tester);
    expect(find.byType(CommunityPostCard), findsNWidgets(2));
    expect(find.byKey(const Key('community-top-brew92-v60')), findsOneWidget);
    // إرسال مع الاقتباس الجاهز
    await tester.enterText(find.byKey(const Key('community-input')), 'أفضل قهوة مقطّرة في الروضة');
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-brew92/community']!['itemId'], 'brew92-v60');
    expect(find.byKey(const Key('community-quote-chip')), findsNothing, reason: 'الاقتباس يُمسح بعد النشر');
  });

  testWidgets('composer picks a product to quote; sort menu requests top; thread reply hearts', (tester) async {
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-brew92', title: 'برو 92'));
    await _settle(tester);
    // اختيار صنف من القائمة
    await tester.tap(find.byKey(const Key('community-quote')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('item-picker-search')), 'لات');
    await _settle(tester);
    expect(find.byKey(const Key('pick-item-brew92-v60')), findsNothing);
    await tester.tap(find.byKey(const Key('pick-item-brew92-latte')));
    await _settle(tester);
    expect(find.byKey(const Key('community-quote-chip')), findsOneWidget);
    expect(find.text('ما رأيك في لاتيه؟'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-input')), 'كريمي ومتوازن');
    await tester.pump();
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-brew92/community']!['itemId'], 'brew92-latte');
    expect(find.text('لاتيه'), findsWidgets, reason: 'المشاركة الجديدة تعرض الاقتباس');
    // الترتيب
    await tester.tap(find.byKey(const Key('community-sort')));
    await _settle(tester);
    await tester.tap(find.text('الأكثر تفاعلاً'));
    await _settle(tester);
    expect(srv.queries['GET /biz/biz-brew92/community']?['sort'], 'top');
    expect(tester.widget<CommunityPostCard>(find.byType(CommunityPostCard).first).post.id, 'b-1', reason: 'الأكثر قلوباً أولاً');
    // النقاش: قلب على رد
    await tester.tap(find.text('جرّبوا الـV60 بحبوب إثيوبيا'));
    await _settle(tester);
    expect(find.byType(CommunityThreadPage), findsOneWidget);
    expect(find.byKey(const Key('reply-like-br-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply-like-br-1')));
    await _settle(tester);
    expect(srv.calls, contains('POST /biz/biz-brew92/community/b-1/replies/br-1/like'));
    expect(find.text('3'), findsOneWidget, reason: 'عدّاد قلوب الرد يتحدث');
  });

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
    expect(find.text('4 مشاركة من 3 مشارك'), findsOneWidget);
    expect(find.byKey(const Key('community-card')).evaluate().single.renderObject!.paintBounds.top, lessThan(400), reason: 'بطاقة المساحة في أعلى الصفحة');
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
    expect(find.text('4 مشاركة · 3 مشارك'), findsOneWidget);
    final cards = find.byType(CommunityPostCard);
    expect(cards, findsNWidgets(4));
    expect(find.byKey(const Key('community-voice-play')), findsOneWidget, reason: 'المشاركة الصوتية تعرض مشغّلاً');
    final first = tester.widget<CommunityPostCard>(cards.first);
    expect(first.post.id, 'c-1', reason: 'المثبّت أولاً');
    expect(find.text('مثبّت'), findsOneWidget);
    expect(find.text('فريق الدائرة'), findsNWidgets(2), reason: 'المشاركة المثبّتة والصوتية من الفريق');
    expect(find.text('أنت'), findsOneWidget, reason: 'مشاركتي تُعرض باسم «أنت»');
    expect(find.text('2 ردّان'), findsOneWidget);
    // تصفية بموضوع الأسئلة
    await tester.tap(find.byKey(const Key('community-topic-question')));
    await _settle(tester);
    expect(srv.queries['GET /biz/biz-kaia/community']?['topic'], 'question');
    expect(find.byType(CommunityPostCard), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-topic-all')));
    await _settle(tester);
    expect(find.byType(CommunityPostCard), findsNWidgets(4));
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
    expect(find.byType(CommunityPostCard), findsNWidgets(5));
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

  testWidgets('composer records a voice note, uploads it, previews it and sends audio with duration', (tester) async {
    VoiceRecordSession.factoryOverride = _FakeRecorder.new;
    VoicePlayer.factoryOverride = _FakePlayer.new;
    addTearDown(() {
      VoiceRecordSession.factoryOverride = null;
      VoicePlayer.factoryOverride = null;
    });
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'));
    await _settle(tester);
    // تشغيل المشاركة الصوتية في الخيط
    await tester.tap(find.byKey(const Key('community-voice-play')));
    await _settle(tester);
    expect(_FakePlayer.plays, 1);
    // تسجيل: يبدأ، يظهر صف التسجيل، ثم إيقاف → رفع → معاينة
    await tester.tap(find.byKey(const Key('community-mic')));
    await _settle(tester);
    expect(find.byKey(const Key('community-rec-stop')), findsOneWidget);
    expect(find.byKey(const Key('community-input')), findsNothing, reason: 'صف التسجيل يحل محل الحقل');
    await tester.tap(find.byKey(const Key('community-rec-stop')));
    await _settle(tester);
    expect(srv.calls, contains('POST /chat/upload'));
    expect(find.byKey(const Key('community-voice-preview')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('community-send'))).onPressed, isNotNull, reason: 'تسجيل بلا نص يكفي للنشر');
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-kaia/community']!;
    expect(body['audio'], '/chat/media/up1.m4a');
    expect(body['audioMs'], 3000);
    expect(body['text'], '');
    expect(find.byKey(const Key('community-voice-preview')), findsNothing, reason: 'المعاينة تختفي بعد النشر');
    // إلغاء تسجيل لا يرفع شيئاً
    await tester.tap(find.byKey(const Key('community-mic')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-rec-cancel')));
    await _settle(tester);
    expect(_FakeRecorder.cancelled, 1);
    expect(srv.calls.where((c) => c == 'POST /chat/upload').length, 1);
  });

  testWidgets('composer caps photos at 10', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    pickImageOverride = ({bool camera = false}) async => (bytes: Uint8List.fromList(png), mime: 'image/png', name: 'g.png');
    addTearDown(() => pickImageOverride = null);
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-kaia', title: 'المطار'));
    await _settle(tester);
    for (var i = 0; i < 11; i++) {
      await tester.tap(find.byKey(const Key('community-photo')));
      await _settle(tester);
    }
    expect(srv.uploads, 10);
    expect(find.text('حتى 10 صور في المشاركة'), findsOneWidget);
    expect(find.text('10/10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // زوال رسالة الحد قبل النشر
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-send')));
    await _settle(tester);
    expect((srv.bodies['POST /biz/biz-kaia/community']!['images'] as List).length, 10);
  });

  testWidgets('thread reply composer sends a voice reply', (tester) async {
    VoiceRecordSession.factoryOverride = _FakeRecorder.new;
    addTearDown(() => VoiceRecordSession.factoryOverride = null);
    final srv = await _pump(tester, const CommunityThreadPage(bizId: 'biz-kaia', postId: 'c-3', title: 'المطار'));
    await _settle(tester);
    expect(find.byKey(const Key('community-reply-topic')), findsNothing, reason: 'لا موضوع للردود');
    await tester.tap(find.byKey(const Key('community-reply-mic')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-reply-rec-stop')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('community-reply-send')));
    await _settle(tester);
    final body = srv.bodies['POST /biz/biz-kaia/community/c-3/replies']!;
    expect(body['audio'], '/chat/media/up1.m4a');
    expect(body['audioMs'], 3000);
    expect(body['images'], isEmpty);
  });

  testWidgets('double-tap hearts a post with a burst; long-press opens the emoji bar and toggles a reaction', (tester) async {
    final srv = await _pump(tester, const CommunityPage(bizId: 'biz-brew92', title: 'برو 92'));
    await _settle(tester);
    final card = find.byKey(const Key('post-gesture-b-1'));
    expect(find.byKey(const Key('heart-burst')), findsNothing);
    // نقرتان على رأس البطاقة (منطقة الاسم) لا على اقتباس المنتج
    final head = tester.getTopLeft(card) + const Offset(200, 24);
    await tester.tapAt(head);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(head);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('heart-burst')), findsOneWidget, reason: 'قلب أحمر ينبثق');
    await _settle(tester);
    expect(srv.calls, contains('POST /biz/biz-brew92/community/b-1/like'));
    expect(find.text('6'), findsOneWidget, reason: 'عدّاد القلوب يتحدث');
    // ضغط مطوّل → شريط الإيموجي
    await tester.longPressAt(head);
    await _settle(tester);
    expect(find.byKey(const Key('reaction-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('react-😂')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-brew92/community/b-1/react']!['emoji'], '😂');
    expect(find.byKey(const Key('chip-😂')), findsOneWidget);
    // اللمس على شريحتي يزيل التفاعل
    await tester.tap(find.byKey(const Key('chip-😂')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-brew92/community/b-1/react']!['emoji'], '');
    expect(find.byKey(const Key('chip-😂')), findsNothing);
  });

  testWidgets('thread: double-tap hearts a reply; long-press reacts on it', (tester) async {
    final srv = await _pump(tester, const CommunityThreadPage(bizId: 'biz-brew92', postId: 'b-1', title: 'برو 92'));
    await _settle(tester);
    final reply = find.byKey(const Key('reply-gesture-br-1'));
    await tester.tap(reply);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(reply);
    await _settle(tester);
    expect(srv.calls, contains('POST /biz/biz-brew92/community/b-1/replies/br-1/like'));
    await tester.longPress(reply);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('react-☕')));
    await _settle(tester);
    expect(srv.bodies['POST /biz/biz-brew92/community/b-1/replies/br-1/react']!['emoji'], '☕');
    expect(find.byKey(const Key('chip-☕')), findsOneWidget);
  });

  test('applyMyReaction moves my reaction between emojis and removes it', () {
    final cur = [const Reaction(emoji: '🔥', count: 3, mine: true), const Reaction(emoji: '☕', count: 1)];
    final moved = applyMyReaction(cur, '☕');
    expect(moved.map((r) => '${r.emoji}${r.count}${r.mine ? '*' : ''}').toList(), ['🔥2', '☕2*']);
    final removed = applyMyReaction(moved, null);
    expect(removed.map((r) => '${r.emoji}${r.count}${r.mine ? '*' : ''}').toList(), ['🔥2', '☕1']);
    expect(applyMyReaction(const [], '😂').single.mine, isTrue);
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
