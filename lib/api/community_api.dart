import 'biz_models.dart';
import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';
import '../ui/reactions.dart';

/// مواضيع مساحة المجتمع وتسمياتها (ترتيب الشرائح والاختيار في المؤلّف).
const communityTopics = {'general': 'عام', 'photo': 'صور', 'question': 'سؤال', 'tip': 'نصيحة', 'alert': 'تنبيه'};

/// منشور في مساحة مجتمع دائرة (server/biz_community.js).
/// الحد الأقصى لصور المشاركة أو الرد.
const communityMaxImages = 10;

List<String> _strList(dynamic v) => [for (final u in (v is List ? v : const [])) u.toString()];
String? _audioOf(Map m) => (m['audio'] is String && (m['audio'] as String).isNotEmpty) ? m['audio'] as String : null;

/// منتج من قائمة الدائرة مقتبس في مشاركة أو رد.
class CommunityItemRef {
  final String id, title, unit, kind;
  final int price;
  final String? imageUrl;
  const CommunityItemRef({required this.id, required this.title, required this.price, this.unit = 'item', this.kind = 'product', this.imageUrl});
  factory CommunityItemRef.fromJson(Map m) => CommunityItemRef(
      id: m['id'].toString(), title: m['title']?.toString() ?? '', price: (m['price'] as num?)?.toInt() ?? 0, unit: m['unit']?.toString() ?? 'item', kind: m['kind']?.toString() ?? 'product', imageUrl: m['imageUrl']?.toString());
  factory CommunityItemRef.of(BizItem it) => CommunityItemRef(id: it.id, title: it.title, price: it.price, unit: it.unit, kind: it.kind, imageUrl: it.imageUrl);
  static CommunityItemRef? maybe(dynamic v) => v is Map ? CommunityItemRef.fromJson(v) : null;
  String get priceLabel => price == 0 ? 'مجاني' : money(price);
}

/// منشور في مساحة مجتمع دائرة (server/biz_community.js): نص و/أو تسجيل صوتي و/أو صور (حتى 10)، وقد يقتبس منتجاً.
class CommunityPost {
  final String id, bizId, topic, text;
  final Person user;
  final List<String> images;
  final String? audio;
  final int? audioMs;
  final CommunityItemRef? item;
  final List<Reaction> reactions;
  final bool pinned, hidden, liked, mine, staff;
  final int likes, replies;
  final DateTime? createdAt;
  const CommunityPost({
    required this.id, required this.bizId, required this.user, required this.topic, required this.text, this.images = const [], this.audio, this.audioMs, this.item, this.reactions = const [],
    this.pinned = false, this.hidden = false, this.liked = false, this.mine = false, this.staff = false, this.likes = 0, this.replies = 0, this.createdAt,
  });

  factory CommunityPost.fromJson(Map m) => CommunityPost(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', user: Person.fromJson(m['user'] is Map ? m['user'] as Map : const {'id': '', 'nickname': ''}),
        topic: m['topic']?.toString() ?? 'general', text: m['text']?.toString() ?? '', images: _strList(m['images']), audio: _audioOf(m), audioMs: (m['audioMs'] as num?)?.toInt(), item: CommunityItemRef.maybe(m['item']), reactions: parseReactions(m['reactions']),
        pinned: m['pinned'] == true, hidden: m['hidden'] == true, liked: m['liked'] == true, mine: m['mine'] == true, staff: m['staff'] == true,
        likes: (m['likes'] as num?)?.toInt() ?? 0, replies: (m['replies'] as num?)?.toInt() ?? 0,
        createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString())?.toLocal(),
      );

  String get topicLabel => communityTopics[topic] ?? 'عام';

  /// وصف قصير للمعاينات: النص أو نوع المرفق.
  String get preview => text.isNotEmpty ? text : (audio != null ? 'تسجيل صوتي' : images.isNotEmpty ? (images.length == 1 ? 'صورة' : '${images.length} صور') : (item != null ? 'عن ${item!.title}' : ''));

  CommunityPost copyWith({bool? pinned, bool? hidden, bool? liked, int? likes, int? replies, List<Reaction>? reactions}) => CommunityPost(
        id: id, bizId: bizId, user: user, topic: topic, text: text, images: images, audio: audio, audioMs: audioMs, item: item, reactions: reactions ?? this.reactions, pinned: pinned ?? this.pinned, hidden: hidden ?? this.hidden,
        liked: liked ?? this.liked, mine: mine, staff: staff, likes: likes ?? this.likes, replies: replies ?? this.replies, createdAt: createdAt);
}

/// رد على منشور في المساحة: نص و/أو تسجيل صوتي و/أو صور.
class CommunityReply {
  final String id, postId, text;
  final Person user;
  final List<String> images;
  final String? audio;
  final int? audioMs;
  final CommunityItemRef? item;
  final List<Reaction> reactions;
  final int likes;
  final bool liked, mine;
  final DateTime? createdAt;
  const CommunityReply({required this.id, required this.postId, required this.user, required this.text, this.images = const [], this.audio, this.audioMs, this.item, this.reactions = const [], this.likes = 0, this.liked = false, this.mine = false, this.createdAt});
  factory CommunityReply.fromJson(Map m) => CommunityReply(
        id: m['id'].toString(), postId: m['postId']?.toString() ?? '', user: Person.fromJson(m['user'] is Map ? m['user'] as Map : const {'id': '', 'nickname': ''}),
        text: m['text']?.toString() ?? '', images: _strList(m['images']), audio: _audioOf(m), audioMs: (m['audioMs'] as num?)?.toInt(), item: CommunityItemRef.maybe(m['item']), reactions: parseReactions(m['reactions']),
        likes: (m['likes'] as num?)?.toInt() ?? 0, liked: m['liked'] == true, mine: m['mine'] == true, createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString())?.toLocal());
  CommunityReply copyWith({int? likes, bool? liked, List<Reaction>? reactions}) => CommunityReply(id: id, postId: postId, user: user, text: text, images: images, audio: audio, audioMs: audioMs, item: item, reactions: reactions ?? this.reactions, likes: likes ?? this.likes, liked: liked ?? this.liked, mine: mine, createdAt: createdAt);
}

/// صفحة من منشورات المساحة مع إحصاءات المساحة.
class CommunityFeed {
  final List<CommunityPost> posts;
  final int total, members;
  final bool canModerate, hasMore;
  /// المنتجات الأكثر نقاشاً مع عدد المشاركات والردود التي تقتبسها.
  final List<({CommunityItemRef item, int count})> topItems;
  const CommunityFeed({required this.posts, this.total = 0, this.members = 0, this.canModerate = false, this.hasMore = false, this.topItems = const []});
  factory CommunityFeed.fromJson(Map m) => CommunityFeed(
        posts: asList(m['posts']).map(CommunityPost.fromJson).toList(), total: (m['total'] as num?)?.toInt() ?? 0, members: (m['members'] as num?)?.toInt() ?? 0,
        canModerate: m['canModerate'] == true, hasMore: m['hasMore'] == true,
        topItems: [for (final t in asList(m['topItems'])) if (t['item'] is Map) (item: CommunityItemRef.fromJson(t['item'] as Map), count: (t['count'] as num?)?.toInt() ?? 0)]);
}

/// منشور مع ردوده.
class CommunityThread {
  final CommunityPost post;
  final List<CommunityReply> replies;
  final bool canModerate;
  const CommunityThread({required this.post, required this.replies, this.canModerate = false});
}

extension CommunityApi on ApiClient {
  Future<CommunityFeed> communityFeed(String bizId, {String? topic, DateTime? before, int limit = 30, String? itemId, String sort = 'new'}) async => CommunityFeed.fromJson(await get('/biz/$bizId/community', query: {
        if (topic != null && topic.isNotEmpty) 'topic': topic,
        if (before != null) 'before': before.toUtc().toIso8601String(),
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
        if (sort == 'top') 'sort': 'top',
        'limit': '$limit',
      }));

  Future<CommunityPost> communityPost(String bizId, {required String topic, required String text, List<String> images = const [], String? audio, int? audioMs, String? itemId}) async =>
      CommunityPost.fromJson(await post('/biz/$bizId/community', {'topic': topic, 'text': text, 'images': images, if (audio != null) 'audio': audio, if (audio != null && audioMs != null) 'audioMs': audioMs, if (itemId != null) 'itemId': itemId}));

  Future<CommunityThread> communityThread(String bizId, String postId) async {
    final d = await get('/biz/$bizId/community/$postId');
    return CommunityThread(post: CommunityPost.fromJson(d['post'] as Map), replies: asList(d['replies']).map(CommunityReply.fromJson).toList(), canModerate: d['canModerate'] == true);
  }

  Future<void> communityDelete(String bizId, String postId) => delete('/biz/$bizId/community/$postId');
  Future<CommunityPost> communityPin(String bizId, String postId, bool pinned) async => CommunityPost.fromJson(await post('/biz/$bizId/community/$postId/pin', {'pinned': pinned}));
  Future<CommunityPost> communityHide(String bizId, String postId, bool hidden) async => CommunityPost.fromJson(await post('/biz/$bizId/community/$postId/hide', {'hidden': hidden}));

  Future<({bool liked, int likes})> communityLike(String bizId, String postId) async {
    final d = await post('/biz/$bizId/community/$postId/like', const {});
    return (liked: d['liked'] == true, likes: (d['likes'] as num?)?.toInt() ?? 0);
  }

  Future<CommunityReply> communityReply(String bizId, String postId, {required String text, List<String> images = const [], String? audio, int? audioMs, String? itemId}) async =>
      CommunityReply.fromJson(await post('/biz/$bizId/community/$postId/replies', {'text': text, 'images': images, if (audio != null) 'audio': audio, if (audio != null && audioMs != null) 'audioMs': audioMs, if (itemId != null) 'itemId': itemId}));

  /// تفاعل بإيموجي على مشاركة (فارغ يزيله)؛ يعيد التفاعلات المحدّثة.
  Future<List<Reaction>> communityReact(String bizId, String postId, String? emoji) async => parseReactions((await post('/biz/$bizId/community/$postId/react', {'emoji': emoji ?? ''}))['reactions']);
  Future<List<Reaction>> communityReplyReact(String bizId, String postId, String replyId, String? emoji) async =>
      parseReactions((await post('/biz/$bizId/community/$postId/replies/$replyId/react', {'emoji': emoji ?? ''}))['reactions']);

  Future<({bool liked, int likes})> communityReplyLike(String bizId, String postId, String replyId) async {
    final d = await post('/biz/$bizId/community/$postId/replies/$replyId/like', const {});
    return (liked: d['liked'] == true, likes: (d['likes'] as num?)?.toInt() ?? 0);
  }
  Future<void> communityDeleteReply(String bizId, String postId, String replyId) => delete('/biz/$bizId/community/$postId/replies/$replyId');
}
