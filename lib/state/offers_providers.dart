import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/offers_map_api.dart';
import 'app_state.dart';
import 'providers.dart';
import 'search_providers.dart';

/// طبقة «عروض» على الخريطة: العروض النشطة ضمن حدود الخريطة الحالية.
final mapOffersProvider = FutureProvider<List<MapOffer>>((ref) => ref.watch(apiClientProvider).offersMap(ref.watch(bboxProvider)));

/// «عروض اليوم» في الرئيسية: الأقرب إلى موقع المستخدم (أو الأحدث بلا موقع).
final offersNearProvider = FutureProvider<List<MapOffer>>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  return ref.watch(apiClientProvider).offersNear(lat: loc?.latitude, lng: loc?.longitude, radiusKm: 15, limit: 12);
});
