import 'client.dart';
import 'models.dart';

/// بحث محفوظ مع تنبيه (server/saved_search.js): كلمة، أنواع اختيارية، ونطاق مسافة اختياري حول موقع.
class SavedSearch {
  final String id, q;
  final List<String>? types;
  final double? lat, lng;
  final int? radiusKm;
  final bool active;
  final int matches;
  final DateTime? lastMatchAt, createdAt;
  const SavedSearch({required this.id, required this.q, this.types, this.lat, this.lng, this.radiusKm, this.active = true, this.matches = 0, this.lastMatchAt, this.createdAt});
  factory SavedSearch.fromJson(Map m) => SavedSearch(
        id: m['id'].toString(), q: m['q']?.toString() ?? '',
        types: m['types'] is List ? [for (final t in m['types'] as List) t.toString()] : null,
        lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(),
        radiusKm: m['radiusKm'] == null ? null : (m['radiusKm'] as num).toInt(),
        active: m['active'] != false, matches: m['matches'] is num ? (m['matches'] as num).toInt() : 0,
        lastMatchAt: m['lastMatchAt'] == null ? null : DateTime.tryParse(m['lastMatchAt'].toString()),
        createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString()),
      );

  /// وصف الأنواع والنطاق للعرض.
  String get scopeLabel {
    final t = types == null || types!.isEmpty ? 'كل الأنواع' : types!.map((k) => savedSearchTypes[k] ?? k).join('، ');
    return radiusKm == null ? t : '$t · ضمن $radiusKm كم';
  }
}

/// أنواع المحتوى التي يفحصها البحث المحفوظ.
const savedSearchTypes = {'posts': 'منشورات الخريطة', 'market': 'السوق', 'events': 'فعاليات', 'biz': 'أنشطة', 'items': 'منتجات الأنشطة'};

/// يحوّل نوع شريحة البحث إلى أنواع البحث المحفوظ (الأشخاص والدوائر لا تُراقب).
List<String>? savedTypesFor(String? searchType) => switch (searchType) {
      'market' => const ['market'],
      'events' => const ['events'],
      'biz' => const ['biz'],
      'items' => const ['items'],
      _ => null,
    };

extension SavedSearchApi on ApiClient {
  Future<List<SavedSearch>> savedSearches() async => asList(await getList('/searches/saved')).map(SavedSearch.fromJson).toList();
  Future<SavedSearch> saveSearch(String q, {List<String>? types, double? lat, double? lng, int? radiusKm}) async => SavedSearch.fromJson(await post('/searches/saved', {
        'q': q,
        if (types != null) 'types': types,
        if (radiusKm != null) ...{'radiusKm': radiusKm, 'lat': lat, 'lng': lng},
      }));
  Future<SavedSearch> updateSavedSearch(String id, {bool? active}) async => SavedSearch.fromJson(await patch_('/searches/saved/$id', {if (active != null) 'active': active}));
  Future<void> deleteSavedSearch(String id) => delete('/searches/saved/$id');
}
