import 'biz_models.dart';
import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

/// عنصر كتالوج مطابق للبحث (منتج/عرض/غرفة/سيارة) مع نشاطه.
class SearchItem {
  final String id, bizId, bizName, kind, title;
  final BizCategory category;
  final int price;
  final String? imageUrl;
  final double? distanceKm;
  const SearchItem({required this.id, required this.bizId, required this.bizName, required this.kind, required this.title, required this.category, required this.price, this.imageUrl, this.distanceKm});
  factory SearchItem.fromJson(Map m) => SearchItem(
        id: m['id'].toString(), bizId: m['bizId'].toString(), bizName: m['bizName']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', title: m['title']?.toString() ?? '',
        category: BizCategory.of(m['category']?.toString()), price: _i(m['price']), imageUrl: m['imageUrl']?.toString(), distanceKm: _d(m['distanceKm']));
}

/// شخص في نتائج البحث مع نبذته إن وُجدت.
class SearchPerson {
  final Person person;
  final String bio;
  const SearchPerson(this.person, this.bio);
  factory SearchPerson.fromJson(Map m) => SearchPerson(Person.fromJson(m), m['bio']?.toString() ?? '');
}

/// نتائج البحث الموحّد مجمّعة حسب النوع.
class SearchResults {
  final String q;
  final List<SearchPerson> people;
  final List<Vessel> vessels;
  final List<Biz> biz;
  final List<SearchItem> items;
  final List<Listing> market;
  final List<Event> events;
  const SearchResults({this.q = '', this.people = const [], this.vessels = const [], this.biz = const [], this.items = const [], this.market = const [], this.events = const []});
  factory SearchResults.fromJson(Map m) => SearchResults(
        q: m['q']?.toString() ?? '',
        people: asList(m['people']).map(SearchPerson.fromJson).toList(), vessels: asList(m['vessels']).map(Vessel.fromJson).toList(), biz: asList(m['biz']).map(Biz.fromJson).toList(),
        items: asList(m['items']).map(SearchItem.fromJson).toList(), market: asList(m['market']).map(Listing.fromJson).toList(), events: asList(m['events']).map(Event.fromJson).toList());
  int get total => people.length + vessels.length + biz.length + items.length + market.length + events.length;
  bool get isEmpty => total == 0;
}

/// اقتراحات الاكتشاف عند فراغ البحث: المفتوح الآن قريباً، الأعلى تقييماً، فعاليات قادمة، دوائر نشطة.
class DiscoverResults {
  final List<Biz> openNow, topRated;
  final List<Event> events;
  final List<Vessel> vessels;
  final bool located;
  const DiscoverResults({this.openNow = const [], this.topRated = const [], this.events = const [], this.vessels = const [], this.located = false});
  factory DiscoverResults.fromJson(Map m) => DiscoverResults(
        openNow: asList(m['openNow']).map(Biz.fromJson).toList(), topRated: asList(m['topRated']).map(Biz.fromJson).toList(),
        events: asList(m['events']).map(Event.fromJson).toList(), vessels: asList(m['vessels']).map(Vessel.fromJson).toList(), located: m['located'] == true);
}

/// أنواع البحث كما يفهمها الخادم، مع تسمياتها.
const searchTypes = <(String key, String label)>[('people', 'أشخاص'), ('vessels', 'دوائر'), ('biz', 'أنشطة'), ('items', 'منتجات'), ('market', 'السوق'), ('events', 'فعاليات')];

extension SearchApi on ApiClient {
  Future<SearchResults> search(String q, {double? lat, double? lng, String? type, int limit = 30}) async => SearchResults.fromJson(await get('/search', query: {
        'q': q,
        if (lat != null && lng != null) ...{'lat': lat.toStringAsFixed(5), 'lng': lng.toStringAsFixed(5)},
        if (type != null) ...{'type': type, 'limit': '$limit'},
      }));

  Future<DiscoverResults> discover({double? lat, double? lng}) async => DiscoverResults.fromJson(await get('/search/discover', query: {
        if (lat != null && lng != null) ...{'lat': lat.toStringAsFixed(5), 'lng': lng.toStringAsFixed(5)},
      }));
}
