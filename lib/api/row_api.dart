import 'client.dart';

/// عنصر في «الصف» (server/row.js): بطاقة واحدة من نوع لحظة/عرض/فعالية/وظيفة/سوق/دائرة «هنا اليوم» بترتيب الأقرب أولاً.
/// الحقول كلها متسامحة مع النقص حتى لا يُسقط عنصرٌ ناقص الصفَّ كله، ونوع غير معروف يُعرض ببطاقة افتراضية.
class RowItem {
  /// moment | offer | event | job | listing | circle
  final String kind;
  final String id;
  /// معرّف الوجهة: الدائرة للعرض والوظيفة، والفعالية، والإعلان، والمنشور
  final String refId;
  final String title, subtitle, who, act;
  final String? logoUrl, imageUrl;
  final double lat, lng;
  /// null حين لا يُعرف موقع المستخدم (الصف بالأحدث)
  final double? distanceKm;
  final DateTime? at, endsAt;
  /// زمن الترتيب في «اللحظات» إن أرسله الخادم (`feedAt`)؛ وإلا فـ [at] هو زمن الترتيب كما كان
  final DateTime? feedAt;
  /// للحظة: المنشور كاملاً كما يعيده `/mapposts` حتى يُفتح العارض بلا طلب آخر
  final Map<String, dynamic> payload;

  const RowItem({
    required this.kind,
    required this.id,
    String? refId,
    this.title = '',
    this.subtitle = '',
    this.who = '',
    String? act,
    this.logoUrl,
    this.imageUrl,
    this.lat = 0,
    this.lng = 0,
    this.distanceKm,
    this.at,
    this.endsAt,
    this.feedAt,
    this.payload = const {},
  })  : refId = refId ?? id,
        act = act ?? '';

  factory RowItem.fromJson(Map m) {
    final kind = m['kind']?.toString() ?? 'moment';
    final id = m['id']?.toString() ?? '';
    final act = m['act']?.toString();
    return RowItem(
      kind: kind,
      id: id,
      refId: (m['refId']?.toString().isNotEmpty ?? false) ? m['refId'].toString() : id,
      title: m['title']?.toString() ?? '',
      subtitle: m['subtitle']?.toString() ?? '',
      who: m['who']?.toString() ?? '',
      act: act == null || act.isEmpty ? defaultAct(kind) : act,
      logoUrl: _url(m['logoUrl']),
      imageUrl: _url(m['imageUrl']),
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      distanceKm: (m['distanceKm'] as num?)?.toDouble(),
      at: DateTime.tryParse(m['at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(m['endsAt']?.toString() ?? ''),
      feedAt: DateTime.tryParse(m['feedAt']?.toString() ?? ''),
      payload: m['payload'] is Map ? Map<String, dynamic>.from(m['payload'] as Map) : const {},
    );
  }

  static String? _url(Object? v) {
    final s = v?.toString();
    return s == null || s.isEmpty ? null : s;
  }

  /// فعل البطاقة الافتراضي لكل نوع إن غاب من الخادم.
  static String defaultAct(String kind) => switch (kind) {
        'offer' => 'استخدم',
        'event' => 'تذكرة',
        'job' => 'قدّم',
        'listing' => 'اطلب',
        'circle' => 'زيارة',
        _ => 'شاهد',
      };

  /// اسم النوع في سطر البطاقة الأول.
  String get kindLabel => switch (kind) {
        'offer' => 'عرض',
        'event' => 'فعالية',
        'job' => 'وظيفة',
        'listing' => 'سوق',
        'circle' => 'هنا اليوم',
        _ => 'لحظة',
      };

  /// مفتاح الدبّوس المقابل على الخريطة (نفس صيغة `MapItem.key`).
  /// الدائرة «هنا اليوم» تحمل مفتاح دبّوس الدوائر (business) حتى يُبرز دبّوس طبقة الدوائر عند دبّوسها المؤقت.
  String get pinKey => switch (kind) {
        'moment' => 'post:$id',
        'offer' => 'offer:$id',
        'listing' => 'listing:$id',
        'event' => 'event:$id',
        'job' => 'job:$id',
        'circle' => 'business:$refId',
        _ => '$kind:$id',
      };

  /// الزمن الذي يرتّب به `/feed` البطاقة (الأحدث أولاً): `feedAt` ثم `at`. يقارن به التطبيق مدى الصفحة الأولى عند التحديث.
  DateTime? get feedTime => feedAt ?? at;

  /// للدائرة «هنا اليوم»: نهاية الدبّوس المؤقت من الحمولة (`payload.until`) أو من `endsAt`.
  DateTime? get hereUntil => DateTime.tryParse(payload['until']?.toString() ?? '') ?? endsAt;

  /// بطاقة لحظة من منشور بصيغة `/mapposts` (كما تصل من القناة الحية): نفس ما يبنيه `server/row.js` للنوع `moment`
  /// حتى تُدرج اللحظة الحيّة في «اللحظات» بلا جلب، والحمولة المنشور نفسه ليُفتح العارض.
  /// [distanceKm] يحسبه التطبيق من موقع المستخدم (حمولة البث عامة بلا مسافة).
  factory RowItem.moment(Map post, {double? distanceKm}) {
    final user = post['user'] is Map ? Map<String, dynamic>.from(post['user'] as Map) : const <String, dynamic>{};
    final kind = post['kind']?.toString() ?? 'text';
    final caption = post['caption']?.toString().trim() ?? '';
    final title = post['title']?.toString().trim() ?? '';
    final nick = user['nickname']?.toString() ?? '';
    final place = post['placeName']?.toString().trim() ?? '';
    final mediaAr = switch (kind) { 'image' => 'صورة', 'video' => 'فيديو', 'audio' => 'تسجيل صوتي', _ => 'لحظة' };
    final media = post['mediaUrl']?.toString();
    return RowItem(
      kind: 'moment',
      id: post['id']?.toString() ?? '',
      title: caption.isNotEmpty ? caption : title.isNotEmpty ? title : '$mediaAr من ${place.isNotEmpty ? place : nick.isNotEmpty ? nick : 'جار قريب'}',
      subtitle: place,
      who: nick,
      logoUrl: _url(user['avatarUrl']),
      imageUrl: (kind == 'image' || kind == 'video') ? _url(media) : null,
      lat: (post['lat'] as num?)?.toDouble() ?? 0,
      lng: (post['lng'] as num?)?.toDouble() ?? 0,
      distanceKm: distanceKm ?? (post['distanceKm'] as num?)?.toDouble(),
      at: DateTime.tryParse(post['createdAt']?.toString() ?? ''),
      endsAt: DateTime.tryParse(post['expiresAt']?.toString() ?? ''),
      payload: Map<String, dynamic>.from(post),
    );
  }
}

/// ردّ `GET /row`: العناصر، وهل رُتّبت بموقع المستخدم.
class RowFeed {
  final List<RowItem> items;
  final bool located;
  const RowFeed({this.items = const [], this.located = false});

  factory RowFeed.fromJson(Map m) => RowFeed(
        items: [for (final e in (m['items'] as List? ?? const [])) if (e is Map) RowItem.fromJson(e)],
        located: m['located'] == true,
      );
}

/// نصف قطر الصف و«اللحظات» بالكيلومتر حين يُعرف موقع المستخدم؛ والتطبيق يرشّح به اللحظات الحيّة أيضاً فلا تظهر لحظة أبعد منه.
const feedRadiusKm = 15;

/// أنواع «اللحظات» بترتيب رقائق الشريط العلوي: `all` (عام) ثم الأنواع الستة التي يبنيها `server/row.js`.
const feedKinds = ['all', 'moment', 'offer', 'event', 'job', 'listing', 'circle'];

/// اسم الرقاقة لكل نوع في «اللحظات».
String feedKindLabel(String kind) => switch (kind) {
      'moment' => 'لحظات',
      'offer' => 'عروض',
      'event' => 'فعاليات',
      'job' => 'وظائف',
      'listing' => 'السوق',
      'circle' => 'دوائر',
      _ => 'عام',
    };

/// صفحة من `GET /feed`: العناصر بصيغة `/row` نفسها الأحدث أولاً، ومؤشر الصفحة التالية أو null في النهاية.
/// [next] نص معتم من الخادم (مثل `2026-10-22T10:00:00.000Z~0~<id>`) يُعاد في `before=` حرفياً ولا يُحلَّل.
class FeedPage {
  final List<RowItem> items;
  final String? next;
  final bool located;
  const FeedPage({this.items = const [], this.next, this.located = false});

  factory FeedPage.fromJson(Map m) => FeedPage(
        items: [for (final e in (m['items'] as List? ?? const [])) if (e is Map) RowItem.fromJson(e)],
        next: (m['next']?.toString().isNotEmpty ?? false) ? m['next'].toString() : null,
        located: m['located'] == true,
      );
}

extension RowApi on ApiClient {
  /// الصف حول موقع المستخدم (عام: يعمل للزائر). بلا موقع يعيد الأحدث.
  Future<RowFeed> rowNear({double? lat, double? lng, int radiusKm = feedRadiusKm, int limit = 30}) async {
    final m = await get('/row', query: {if (lat != null) 'lat': '$lat', if (lng != null) 'lng': '$lng', 'radiusKm': '$radiusKm', 'limit': '$limit'});
    return RowFeed.fromJson(m);
  }

  /// «اللحظات»: `GET /feed?kind=&lat=&lng=&radiusKm=&limit=&before=` الأحدث أولاً بين الأنواع المختارة (`all` يدمجها كلها)،
  /// ضمن [radiusKm] حين يُعرف الموقع، و[before] مؤشر الصفحة التالية من الردّ السابق كما هو. عام: يعمل للزائر.
  Future<FeedPage> feedItems({String kind = 'all', double? lat, double? lng, int radiusKm = feedRadiusKm, int limit = 30, String? before}) async {
    final m = await get('/feed', query: {
      'kind': kind,
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
      'radiusKm': '$radiusKm',
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    });
    return FeedPage.fromJson(m);
  }
}
