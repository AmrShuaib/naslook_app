import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/row_api.dart';
import 'app_state.dart';
import 'search_providers.dart';

/// «الصف» في الرئيسية: الأقرب إلى موقع المستخدم (أو الأحدث بلا موقع)، كما يفعل [offersNearProvider].
/// لا يتبع حدود الخريطة عمداً: الخريطة تتبع البطاقة لا العكس، فلا يُعاد الجلب مع كل حركة.
final rowProvider = FutureProvider<RowFeed>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  return ref.watch(apiClientProvider).rowNear(lat: loc?.latitude, lng: loc?.longitude, radiusKm: 15, limit: 30);
});
