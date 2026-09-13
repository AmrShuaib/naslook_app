import 'client.dart';
import 'models.dart';

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? d;
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// أنواع منشورات الخريطة وتسمياتها.
const postTags = {'moment': 'لحظة', 'offer': 'عرض', 'ad': 'إعلان', 'invest': 'فرصة استثمار', 'event': 'فعالية', 'job': 'وظيفة'};
const postCtaTypes = {'link': 'رابط', 'whatsapp': 'واتساب', 'call': 'اتصال', 'biz': 'دائرة تجارية', 'market': 'عرض في السوق', 'chat': 'مراسلة'};
const postTtlOptions = <(int, String)>[(24, '24 ساعة'), (72, '3 أيام'), (168, 'أسبوع')];

/// طبقة فوق الوسائط: نص أو ملصق (إيموجي) بموضع نسبي (0..1) ومقياس ودوران ولون.
class PostOverlay {
  final String type, text;
  final double x, y, scale, rot;
  final String color, align, font;
  final String? bg;
  const PostOverlay({required this.type, required this.text, this.x = 0.5, this.y = 0.5, this.scale = 1, this.rot = 0, this.color = '#FFFFFF', this.bg, this.align = 'center', this.font = 'bold'});
  bool get isSticker => type == 'sticker';
  PostOverlay copyWith({String? text, double? x, double? y, double? scale, double? rot, String? color, String? bg, bool clearBg = false, String? align, String? font}) => PostOverlay(
        type: type, text: text ?? this.text, x: x ?? this.x, y: y ?? this.y, scale: scale ?? this.scale, rot: rot ?? this.rot, color: color ?? this.color,
        bg: clearBg ? null : (bg ?? this.bg), align: align ?? this.align, font: font ?? this.font);
  Map<String, dynamic> toJson() => {'type': type, 'text': text, 'x': x, 'y': y, 'scale': scale, 'rot': rot, 'color': color, 'bg': bg, 'align': align, 'font': font};
  factory PostOverlay.fromJson(Map m) => PostOverlay(
        type: m['type'] == 'sticker' ? 'sticker' : 'text', text: m['text']?.toString() ?? '', x: _d(m['x'], .5), y: _d(m['y'], .5), scale: _d(m['scale'], 1), rot: _d(m['rot']),
        color: m['color']?.toString() ?? '#FFFFFF', bg: m['bg']?.toString(), align: m['align']?.toString() ?? 'center', font: m['font']?.toString() ?? 'bold');
}

/// زر الإجراء في المنشور: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة.
class PostCta {
  final String type, value, label;
  const PostCta({required this.type, this.value = '', this.label = ''});
  Map<String, dynamic> toJson() => {'type': type, 'value': value, 'label': label};
  factory PostCta.fromJson(Map m) => PostCta(type: m['type']?.toString() ?? 'link', value: m['value']?.toString() ?? '', label: m['label']?.toString() ?? '');
}

/// منشور على الخريطة: صورة أو فيديو قصير أو تسجيل صوتي أو نص، مع طبقاته وحقوله الاحترافية.
class MapPost {
  final String id, kind, caption, tag, title, status;
  final Person user;
  final String? mediaUrl, bg, placeName;
  final List<PostOverlay> overlays;
  final int? price, durationSec;
  final PostCta? cta;
  final double lat, lng;
  final int views, likes;
  final bool liked, mine, expired;
  final DateTime? expiresAt, createdAt;
  const MapPost({
    required this.id, required this.user, required this.kind, this.mediaUrl, this.caption = '', this.bg, this.overlays = const [], this.tag = 'moment', this.title = '', this.price, this.cta,
    required this.lat, required this.lng, this.placeName, this.durationSec, this.status = 'active', this.views = 0, this.likes = 0, this.liked = false, this.mine = false, this.expired = false, this.expiresAt, this.createdAt,
  });
  factory MapPost.fromJson(Map m) => MapPost(
        id: m['id'].toString(), user: Person.fromJson(asMap(m['user'])), kind: m['kind']?.toString() ?? 'text', mediaUrl: m['mediaUrl']?.toString(), caption: m['caption']?.toString() ?? '', bg: m['bg']?.toString(),
        overlays: asList(m['overlays']).map(PostOverlay.fromJson).toList(), tag: m['tag']?.toString() ?? 'moment', title: m['title']?.toString() ?? '', price: m['price'] == null ? null : _i(m['price']),
        cta: m['cta'] is Map ? PostCta.fromJson(asMap(m['cta'])) : null, lat: _d(m['lat']), lng: _d(m['lng']), placeName: m['placeName']?.toString(), durationSec: m['durationSec'] == null ? null : _i(m['durationSec']),
        status: m['status']?.toString() ?? 'active', views: _i(m['views']), likes: _i(m['likes']), liked: m['liked'] == true, mine: m['mine'] == true, expired: m['expired'] == true, expiresAt: _t(m['expiresAt']), createdAt: _t(m['createdAt']),
      );
  MapPost copyWith({int? likes, bool? liked, int? views, String? status}) => MapPost(
        id: id, user: user, kind: kind, mediaUrl: mediaUrl, caption: caption, bg: bg, overlays: overlays, tag: tag, title: title, price: price, cta: cta, lat: lat, lng: lng, placeName: placeName,
        durationSec: durationSec, status: status ?? this.status, views: views ?? this.views, likes: likes ?? this.likes, liked: liked ?? this.liked, mine: mine, expired: expired, expiresAt: expiresAt, createdAt: createdAt);
  String get tagLabel => postTags[tag] ?? tag;
  String get kindLabel => switch (kind) { 'image' => 'صورة', 'video' => 'فيديو', 'audio' => 'تسجيل صوتي', _ => 'نص' };
  /// نص مختصر للقوائم: العنوان أو التعليق أو أول نص في الطبقات.
  String get summary => title.isNotEmpty ? title : caption.isNotEmpty ? caption : (overlays.where((o) => !o.isSticker).map((o) => o.text).firstOrNull ?? kindLabel);
}

extension PostsApi on ApiClient {
  Future<MapPost> createPost(Map<String, dynamic> body) async => MapPost.fromJson(await post('/mapposts', body));
  Future<List<MapPost>> posts({BBox? bbox, int limit = 200, String? tag}) async =>
      asList(await getList('/mapposts', query: {if (bbox != null) 'bbox': bbox.query, 'limit': '$limit', if (tag != null) 'tag': tag})).map(MapPost.fromJson).toList();
  Future<List<MapPost>> myPosts() async => asList(await getList('/mapposts/mine')).map(MapPost.fromJson).toList();
  Future<MapPost> mapPost(String id) async => MapPost.fromJson(await get('/mapposts/$id'));
  Future<MapPost> updatePost(String id, Map<String, dynamic> patch) async => MapPost.fromJson(await patch_('/mapposts/$id', patch));
  Future<void> deletePost(String id) => delete('/mapposts/$id');
  Future<int> viewPost(String id) async => _i((await post('/mapposts/$id/view', const {}))['views']);
  Future<({bool liked, int likes})> likePost(String id) async {
    final d = await post('/mapposts/$id/like', const {});
    return (liked: d['liked'] == true, likes: _i(d['likes']));
  }
}

/// مجاميع أحداث المنشورات: مشاهدات (كل فتح)، ضغطات زر الإجراء، مراسلات، إعجابات.
class PostStatTotals {
  final int views, cta, contacts, likes;
  const PostStatTotals({this.views = 0, this.cta = 0, this.contacts = 0, this.likes = 0});
  factory PostStatTotals.fromJson(Map m) => PostStatTotals(views: _i(m['views']), cta: _i(m['cta']), contacts: _i(m['contacts']), likes: _i(m['likes']));
}

/// نقطة في سلسلة زمنية (ساعة أو يوم).
class PostStatPoint {
  final String label;
  final PostStatTotals t;
  const PostStatPoint(this.label, this.t);
}

/// إحصاءات منشور واحد أو مجموعة منشورات (منشوراتي أو منشورات دائرة) مع سلسلتي 24 ساعة والأيام.
class PostStats {
  final int days, posts, uniqueViews;
  final PostStatTotals totals;
  final List<PostStatPoint> hourly, daily;
  final List<PostBriefStats> byPost;
  final int? likesTotal, viewsTotal;
  const PostStats({required this.days, this.posts = 1, required this.totals, this.uniqueViews = 0, this.hourly = const [], this.daily = const [], this.byPost = const [], this.likesTotal, this.viewsTotal});
  factory PostStats.fromJson(Map m) => PostStats(
        days: _i(m['days']), posts: m['posts'] == null ? 1 : _i(m['posts']), totals: PostStatTotals.fromJson(asMap(m['totals'])), uniqueViews: _i(m['uniqueViews']),
        hourly: [for (final h in asList(m['hourly'])) PostStatPoint(_hourLabel(h['at']?.toString()), PostStatTotals.fromJson(h))],
        daily: [for (final d in asList(m['daily'])) PostStatPoint(_dayLabel(d['date']?.toString()), PostStatTotals.fromJson(d))],
        byPost: asList(m['byPost']).map(PostBriefStats.fromJson).toList(),
        likesTotal: m['likesTotal'] == null ? null : _i(m['likesTotal']), viewsTotal: m['viewsTotal'] == null ? null : _i(m['viewsTotal']),
      );
  static String _hourLabel(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toUtc().add(const Duration(hours: 3));
    return d == null ? '' : '${d.hour}';
  }
  static String _dayLabel(String? date) => date == null || date.length < 10 ? '' : '${int.tryParse(date.substring(8, 10)) ?? ''}/${int.tryParse(date.substring(5, 7)) ?? ''}';
}

/// منشور مع مجاميعه داخل ملخص.
class PostBriefStats {
  final String id, title, kind, tag, status;
  final PostStatTotals t;
  const PostBriefStats({required this.id, required this.title, required this.kind, required this.tag, required this.status, required this.t});
  factory PostBriefStats.fromJson(Map m) => PostBriefStats(id: m['id'].toString(), title: m['title']?.toString() ?? '', kind: m['kind']?.toString() ?? 'text', tag: m['tag']?.toString() ?? 'moment', status: m['status']?.toString() ?? 'active', t: PostStatTotals.fromJson(m));
}

extension PostStatsApi on ApiClient {
  Future<PostStats> postStats(String id, {int days = 7}) async => PostStats.fromJson(await get('/mapposts/$id/stats', query: {'days': '$days'}));
  Future<PostStats> myPostStats({int days = 7}) async => PostStats.fromJson(await get('/mapposts/stats/mine', query: {'days': '$days'}));
  Future<PostStats> bizPostStats(String slug, {int days = 30}) async => PostStats.fromJson(await get('/mapposts/stats/biz/$slug', query: {'days': '$days'}));
  /// تتبّع بلا انتظار: ضغطة زر الإجراء أو فتح المراسلة من المنشور.
  Future<void> trackCta(String id) => post('/mapposts/$id/cta', const {}).then((_) {}).catchError((_) {});
  Future<void> trackContact(String id) => post('/mapposts/$id/contact', const {}).then((_) {}).catchError((_) {});
}
