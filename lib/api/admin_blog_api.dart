// واجهة إدارة المدونة (server/blog.js → /adminapi/blog): القائمة بالمرشّحات والعدّادات، الإنشاء والتعديل، النشر والجدولة،
// التثبيت، النسخ، الحذف، وروابط معاينة المسودات.
import 'client.dart';
import 'models.dart';

DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// أنواع منشورات المدونة وتسمياتها.
const blogKinds = {'update': 'تحديث', 'news': 'خبر', 'post': 'تدوينة'};

/// منشور مدونة كما تراه الإدارة.
class BlogPost {
  final String id, slug, kind, title, summary, body, status, effectiveStatus, url;
  final String? coverUrl;
  final List<String> tags;
  final bool pinned;
  final DateTime? publishedAt, createdAt, updatedAt;
  final int views, bodyLength;
  const BlogPost({
    required this.id, required this.slug, required this.kind, required this.title, this.summary = '', this.body = '', this.status = 'draft', this.effectiveStatus = 'draft', this.url = '',
    this.coverUrl, this.tags = const [], this.pinned = false, this.publishedAt, this.createdAt, this.updatedAt, this.views = 0, this.bodyLength = 0,
  });
  factory BlogPost.fromJson(Map m) => BlogPost(
        id: m['id'].toString(), slug: m['slug']?.toString() ?? '', kind: m['kind']?.toString() ?? 'update', title: m['title']?.toString() ?? '',
        summary: m['summary']?.toString() ?? '', body: m['body']?.toString() ?? '', status: m['status']?.toString() ?? 'draft', effectiveStatus: m['effectiveStatus']?.toString() ?? (m['status']?.toString() ?? 'draft'),
        url: m['url']?.toString() ?? '', coverUrl: (m['coverUrl']?.toString().isEmpty ?? true) ? null : m['coverUrl'].toString(), tags: asList(m['tags']).map((e) => e.toString()).toList(),
        pinned: m['pinned'] == true, publishedAt: _t(m['publishedAt']), createdAt: _t(m['createdAt']), updatedAt: _t(m['updatedAt']), views: _i(m['views']), bodyLength: _i(m['bodyLength'] ?? (m['body']?.toString().length ?? 0)),
      );
  String get kindLabel => blogKinds[kind] ?? kind;
  String get statusLabel => switch (effectiveStatus) { 'published' => 'منشور', 'scheduled' => 'مجدول', _ => 'مسودة' };
}

/// قائمة الإدارة مع العدّادات.
class BlogAdminList {
  final List<BlogPost> posts;
  final int total, all, draft, published, scheduled, views;
  const BlogAdminList({required this.posts, required this.total, required this.all, required this.draft, required this.published, required this.scheduled, required this.views});
  factory BlogAdminList.fromJson(Map m) {
    final c = asMap(m['counts']);
    return BlogAdminList(posts: asList(m['posts']).map(BlogPost.fromJson).toList(), total: _i(m['total']), all: _i(c['all']), draft: _i(c['draft']), published: _i(c['published']), scheduled: _i(c['scheduled']), views: _i(c['views']));
  }
}

extension AdminBlogApi on ApiClient {
  Future<BlogAdminList> adminBlogList({String q = '', String kind = '', String status = 'all'}) async =>
      BlogAdminList.fromJson(await get('/adminapi/blog', query: {if (q.isNotEmpty) 'q': q, if (kind.isNotEmpty) 'kind': kind, 'status': status}));
  Future<BlogPost> adminBlogGet(String id) async => BlogPost.fromJson(await get('/adminapi/blog/$id'));
  Future<BlogPost> adminBlogCreate(Map<String, dynamic> fields) async => BlogPost.fromJson(await post('/adminapi/blog', fields));
  Future<BlogPost> adminBlogUpdate(String id, Map<String, dynamic> fields) async => BlogPost.fromJson(await patch('/adminapi/blog/$id', fields));
  Future<BlogPost> adminBlogPublish(String id, {DateTime? at}) async => BlogPost.fromJson(await post('/adminapi/blog/$id/publish', {if (at != null) 'publishedAt': at.toUtc().toIso8601String()}));
  Future<BlogPost> adminBlogUnpublish(String id) async => BlogPost.fromJson(await post('/adminapi/blog/$id/unpublish', const {}));
  Future<BlogPost> adminBlogPin(String id, {required bool pinned}) async => BlogPost.fromJson(await post('/adminapi/blog/$id/pin', {'pinned': pinned}));
  Future<BlogPost> adminBlogDuplicate(String id) async => BlogPost.fromJson(await post('/adminapi/blog/$id/duplicate', const {}));
  Future<String> adminBlogPreviewLink(String id) async => (await post('/adminapi/blog/$id/preview', const {}))['url'].toString();
  Future<void> adminBlogDelete(String id) => delete('/adminapi/blog/$id');
}
