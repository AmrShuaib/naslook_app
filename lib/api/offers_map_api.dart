import 'client.dart';
import 'models.dart';

/// عرض نشط مع إحداثيات دائرته: طبقة «عروض» على الخريطة وقسم «عروض اليوم» في الرئيسية (server/offers.js).
class MapOffer {
  final String id, bizId, bizName, category, kind, title, description;
  final String? logoUrl;
  final double lat, lng;
  final Map<String, dynamic> value;
  final bool membersOnly;
  final DateTime? startsAt, endsAt;
  final double? distanceKm;
  const MapOffer({required this.id, required this.bizId, required this.bizName, this.category = '', this.kind = 'deal', required this.title, this.description = '', this.logoUrl, required this.lat, required this.lng, this.value = const {}, this.membersOnly = true, this.startsAt, this.endsAt, this.distanceKm});

  factory MapOffer.fromJson(Map m) => MapOffer(
        id: m['id']?.toString() ?? '',
        bizId: m['bizId']?.toString() ?? '',
        bizName: m['bizName']?.toString() ?? '',
        category: m['category']?.toString() ?? '',
        kind: m['kind']?.toString() ?? 'deal',
        title: m['title']?.toString() ?? '',
        description: m['description']?.toString() ?? '',
        logoUrl: m['logoUrl']?.toString(),
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        value: m['value'] is Map ? Map<String, dynamic>.from(m['value'] as Map) : const {},
        membersOnly: m['membersOnly'] != false,
        startsAt: DateTime.tryParse(m['startsAt']?.toString() ?? ''),
        endsAt: DateTime.tryParse(m['endsAt']?.toString() ?? ''),
        distanceKm: (m['distanceKm'] as num?)?.toDouble(),
      );

  /// «ينتهي بعد ٣ س» / «ينتهي اليوم» / «مفتوح».
  String get endsLabel {
    final e = endsAt;
    if (e == null) return 'بلا انتهاء';
    final d = e.difference(DateTime.now());
    if (d.isNegative) return 'انتهى';
    if (d.inHours < 1) return 'ينتهي خلال ${d.inMinutes} د';
    if (d.inHours < 24) return 'ينتهي بعد ${d.inHours} س';
    if (d.inDays < 2) return 'ينتهي غداً';
    return 'ينتهي بعد ${d.inDays} أيام';
  }

  String get kindLabel => switch (kind) { 'coupon' => 'كوبون', 'checkin' => 'تسجيل حضور', 'loyalty' => 'ولاء', _ => 'خصم' };
}

extension OffersMapApi on ApiClient {
  Future<List<MapOffer>> offersMap(BBox b) async {
    final m = await get('/offers/map', query: {'minLat': '${b.minLat}', 'minLng': '${b.minLng}', 'maxLat': '${b.maxLat}', 'maxLng': '${b.maxLng}'});
    return [for (final e in (m['items'] as List? ?? const [])) MapOffer.fromJson(e as Map)];
  }

  Future<List<MapOffer>> offersNear({double? lat, double? lng, int radiusKm = 10, int limit = 20}) async {
    final m = await get('/offers/near', query: {if (lat != null) 'lat': '$lat', if (lng != null) 'lng': '$lng', 'radiusKm': '$radiusKm', 'limit': '$limit'});
    return [for (final e in (m['items'] as List? ?? const [])) MapOffer.fromJson(e as Map)];
  }
}
