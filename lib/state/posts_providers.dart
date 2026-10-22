import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/posts_api.dart';
import '../core/location.dart';
import 'app_state.dart';
import 'feed_providers.dart';
import 'providers.dart';
import 'row_providers.dart';

/// منشورات الخريطة ضمن الحدود المرئية.
final mapPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(bbox: ref.watch(bboxProvider)));
/// أحدث المنشورات للشريط في الرئيسية.
final recentPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(limit: 30));
/// منشوراتي: للزائر قائمة فارغة بلا طلب.
final myPostsProvider = FutureProvider<List<MapPost>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).myPosts() : const <MapPost>[]);

/// نقطة الأصل للبث والأماكن الرائجة بلا طلب إذن: آخر موقع معروف للجهاز، وإلا موقع حضور المستخدم، وإلا مركز الحدود الحالية.
final feedOriginProvider = Provider<LatLng>((ref) {
  final last = DeviceLocation.lastBrowse;
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

/// [removedPostId]: لحظة حُذفت أو أُخفيت أو أخفاها بلاغ من العارض؛ تُزال بطاقتها في مكانها من كل قائمة مفتوحة
/// لأن التحديث وحده يصل مدى الصفحة الأولى فقط، فتبقى المخفية في الصفحات التالية حتى التحديث الكامل.
void invalidatePosts(WidgetRef ref, {String? removedPostId}) {
  ref.invalidate(trendingPlacesProvider);
  ref.invalidate(mapPostsProvider);
  ref.invalidate(recentPostsProvider);
  ref.invalidate(myPostsProvider);
  // اللحظة الجديدة تظهر في «الصف» فور نشرها بدل انتظار التحديث الدوري
  ref.invalidate(rowProvider);
  // «اللحظات» لا تُرمى: إبطالها كان يمسح القائمة وصفحاتها وموضع التمرير تحت العارض بعد كل حذف أو إخفاء أو بلاغ أو حظر.
  // كل قائمة مفتوحة تتحدّث في مكانها: الجديد خلف الكبسولة (أو مباشرة في الأعلى) وما زال من مدى الصفحة الأولى يُزال
  for (final n in openMoments(ref)) {
    if (removedPostId != null) n.removeMoment(removedPostId);
    n.refresh(applyNow: false);
  }
}
