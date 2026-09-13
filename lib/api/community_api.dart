import 'client.dart';
import 'models.dart';

/// مواضيع مساحة المجتمع وتسمياتها (ترتيب الشرائح والاختيار في المؤلّف).
const communityTopics = {'general': 'عام', 'photo': 'صور', 'question': 'سؤال', 'tip': 'نصيحة', 'alert': 'تنبيه'};

/// منشور في مساحة مجتمع دائرة (server/biz_community.js).
class CommunityPost {
  final String id, bizId, topic, text;
  final Person user;
  final List<String> images;
  final bool pinned, hidden, liked, mine, staff;
  final int likes, replies;
  final DateTime? createdAt;
  const CommunityPost({
    required this.id, required this.bizId, required this.user, required this.topic, required this.text, this.images = const [],
    this.pinned = false, this.hidden = false, this.liked = false, this.mine = false, this.staff = false, this.likes = 0, this.replies = 0, this.createdAt,
  });

  factory CommunityPost.fromJson(Map m) => CommunityPost(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', user: Person.fromJson(m['user'] is Map ? m['user'] as Map : const {'id': '', 'nickname': ''}),
        topic: m['topic']?.toString() ?? 'general', text: m['text']?.toString() ?? '',
        images: [for (final u in (m['images'] is List ? m['images'] as List : const [])) u.toString()],
        pinned: m['pinned'] == true, hidden: m['hidden'] == true, liked: m['liked'] == true, mine: m['mine'] == true, staff: m['staff'] == true,
        likes: (m['likes'] as num?)?.toInt() ?? 0, replies: (m['replies'] as num?)?.toInt() ?? 0,
        createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString())?.toLocal(),
      );

  String get topicLabel => communityTopics[topic] ?? 'عام';

  CommunityPost copyWith({bool? pinned, bool? hidden, bool? liked, int? likes, int? replies}) => CommunityPost(
        id: id, bizId: bizId, user: user, topic: topic, text: text, images: images, pinned: pinned ?? this.pinned, hidden: hidden ?? this.hidden,
        liked: liked ?? this.liked, mine: mine, staff: staff, likes: likes ?? this.likes, replies: replies ?? this.replies, createdAt: createdAt);
}

/// رد على منشور في المساحة.
class CommunityReply {
  final String id, postId, text;
  final Person user;
  final bool mine;
  final DateTime? createdAt;
  const CommunityReply({required this.id, required this.postId, required this.user, required this.text, this.mine = false, this.createdAt});
  factory CommunityReply.fromJson(Map m) => CommunityReply(
        id: m['id'].toString(), postId: m['postId']?.toString() ?? '', user: Person.fromJson(m['user'] is Map ? m['user'] as Map : const {'id': '', 'nickname': ''}),
        text: m['text']?.toString() ?? '', mine: m['mine'] == true, createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString())?.toLocal());
}

/// صفحة من منشورات المساحة مع إحصاءات المساحة.
class CommunityFeed {
  final List<CommunityPost> posts;
  final int total, members;
  final bool canModerate, hasMore;
  const CommunityFeed({required this.posts, this.total = 0, this.members = 0, this.canModerate = false, this.hasMore = false});
  factory CommunityFeed.fromJson(Map m) => CommunityFeed(
        posts: asList(m['posts']).map(CommunityPost.fromJson).toList(), total: (m['total'] as num?)?.toInt() ?? 0, members: (m['members'] as num?)?.toInt() ?? 0,
        canModerate: m['canModerate'] == true, hasMore: m['hasMore'] == true);
}

/// منشور مع ردوده.
class CommunityThread {
  final CommunityPost post;
  final List<CommunityReply> replies;
  final bool canModerate;
  const CommunityThread({required this.post, required this.replies, this.canModerate = false});
}

extension CommunityApi on ApiClient {
  Future<CommunityFeed> communityFeed(String bizId, {String? topic, DateTime? before, int limit = 30}) async => CommunityFeed.fromJson(await get('/biz/$bizId/community', query: {
        if (topic != null && topic.isNotEmpty) 'topic': topic,
        if (before != null) 'before': before.toUtc().toIso8601String(),
        'limit': '$limit',
      }));

  Future<CommunityPost> communityPost(String bizId, {required String topic, required String text, List<String> images = const []}) async =>
      CommunityPost.fromJson(await post('/biz/$bizId/community', {'topic': topic, 'text': text, 'images': images}));

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

  Future<CommunityReply> communityReply(String bizId, String postId, String text) async => CommunityReply.fromJson(await post('/biz/$bizId/community/$postId/replies', {'text': text}));
  Future<void> communityDeleteReply(String bizId, String postId, String replyId) => delete('/biz/$bizId/community/$postId/replies/$replyId');
}
