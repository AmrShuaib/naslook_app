import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/posts_api.dart';
import '../core/location.dart';
import 'app_state.dart';
import 'providers.dart';

/// منشورات الخريطة ضمن الحدود المرئية.
final mapPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(bbox: ref.watch(bboxProvider)));
/// أحدث المنشورات للشريط في الرئيسية.
final recentPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(limit: 30));
final myPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).myPosts());

/// نقطة الأصل للبث والأماكن الرائجة بلا طلب إذن: آخر موقع معروف للجهاز، وإلا موقع حضور المستخدم، وإلا مركز الحدود الحالية.
final feedOriginProvider = Provider<LatLng>((ref) {
  final last = DeviceLocation.last;
  if (last != null) return last;
  final p = ref.watch(myPresenceProvider).valueOrNull;
  if (p?.lat != null && p?.lng != null) return LatLng(p!.lat!, p.lng!);
  final b = ref.watch(bboxProvider);
  return LatLng((b.minLat + b.maxLat) / 2, (b.minLng + b.maxLng) / 2);
});
/// الأماكن الرائجة خلال 24 ساعة حول نقطة الأصل (للرئيسية).
final trendingPlacesProvider = FutureProvider<List<TrendingPlace>>((ref) {
  final o = ref.watch(feedOriginProvider);
  return ref.watch(apiClientProvider).trendingPlaces(lat: o.latitude, lng: o.longitude);
});

void invalidatePosts(WidgetRef ref) {
  ref.invalidate(trendingPlacesProvider);
  ref.invalidate(mapPostsProvider);
  ref.invalidate(recentPostsProvider);
  ref.invalidate(myPostsProvider);
}
