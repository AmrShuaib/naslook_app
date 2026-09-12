import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/search_api.dart';
import '../core/location.dart';
import 'app_state.dart';
import 'providers.dart';

/// موقع المستخدم للبحث والترتيب بالقرب: GPS الجهاز، وإلا موقعه المحفوظ على الخريطة، وإلا لا شيء.
final userLocationProvider = FutureProvider<LatLng?>((ref) async {
  final gps = await DeviceLocation.current(precise: false);
  if (gps != null) return gps;
  try {
    final p = await ref.watch(myPresenceProvider.future);
    if (p.lat != null && p.lng != null) return LatLng(p.lat!, p.lng!);
  } catch (_) {}
  return null;
});

/// مفتاح البحث: الكلمة والنوع (null = الكل).
typedef SearchKey = ({String q, String? type});

/// نتائج البحث؛ تُعاد مع الموقع حين يتوفر (يُعاد الجلب تلقائياً بالمسافات).
final searchProvider = FutureProvider.family<SearchResults, SearchKey>((ref, k) {
  final loc = ref.watch(userLocationProvider).valueOrNull;
  return ref.watch(apiClientProvider).search(k.q, lat: loc?.latitude, lng: loc?.longitude, type: k.type);
});

final discoverProvider = FutureProvider<DiscoverResults>((ref) {
  final loc = ref.watch(userLocationProvider).valueOrNull;
  return ref.watch(apiClientProvider).discover(lat: loc?.latitude, lng: loc?.longitude);
});

/// آخر عمليات البحث في هذه الجلسة (الأحدث أولاً، حتى 8).
final recentSearchesProvider = StateProvider<List<String>>((_) => const []);
void rememberSearch(WidgetRef ref, String q) {
  final t = q.trim();
  if (t.length < 2) return;
  final cur = ref.read(recentSearchesProvider);
  ref.read(recentSearchesProvider.notifier).state = [t, ...cur.where((x) => x != t)].take(8).toList();
}
