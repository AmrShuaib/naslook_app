import 'client.dart';

/// عنصر في «الصف» (server/row.js): بطاقة واحدة من نوع لحظة/عرض/فعالية/وظيفة/سوق بترتيب الأقرب أولاً.
/// الحقول كلها متسامحة مع النقص حتى لا يُسقط عنصرٌ ناقص الصفَّ كله.
class RowItem {
  /// moment | offer | event | job | listing
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
        _ => 'شاهد',
      };

  /// اسم النوع في سطر البطاقة الأول.
  String get kindLabel => switch (kind) {
        'offer' => 'عرض',
        'event' => 'فعالية',
        'job' => 'وظيفة',
        'listing' => 'سوق',
        _ => 'لحظة',
      };

  /// مفتاح الدبّوس المقابل على الخريطة (نفس صيغة `MapItem.key`).
  String get pinKey => switch (kind) {
        'moment' => 'post:$id',
        'offer' => 'offer:$id',
        'listing' => 'listing:$id',
        'event' => 'event:$id',
        'job' => 'job:$id',
        _ => '$kind:$id',
      };
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

extension RowApi on ApiClient {
  /// الصف حول موقع المستخدم (عام: يعمل للزائر). بلا موقع يعيد الأحدث.
  Future<RowFeed> rowNear({double? lat, double? lng, int radiusKm = 15, int limit = 30}) async {
    final m = await get('/row', query: {if (lat != null) 'lat': '$lat', if (lng != null) 'lng': '$lng', 'radiusKm': '$radiusKm', 'limit': '$limit'});
    return RowFeed.fromJson(m);
  }
}
