import '../core/swr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/row_api.dart';
import 'app_state.dart';
import 'search_providers.dart';

/// «الصف» في الرئيسية: الأقرب إلى موقع المستخدم (أو الأحدث بلا موقع)، كما يفعل [offersNearProvider].
/// لا يتبع حدود الخريطة عمداً: الخريطة تتبع البطاقة لا العكس، فلا يُعاد الجلب مع كل حركة.
final rowProvider = FutureProvider<RowFeed>((ref) async {
  // الموقع يُطلب فوراً لكن لا يُنتظر عند العرض من المحفوظ: تحديد الموقع قد يأخذ ثواني والبطاقات المحفوظة تظهر قبله
  final locF = ref.watch(userLocationProvider.future);
  final api = ref.watch(apiClientProvider);
  return swr(ref, 'row', () async {
    final loc = Swr.cacheMode ? null : await locF;
    return api.rowNear(lat: loc?.latitude, lng: loc?.longitude, radiusKm: 15, limit: 30);
  });
});
