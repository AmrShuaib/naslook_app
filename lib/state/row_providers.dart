import '../core/swr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/row_api.dart';
import 'app_state.dart';
import 'providers.dart' show signedInProvider;
import 'search_providers.dart';

/// مركز صريح للصف يضبطه زر «ابحث في هذه المنطقة» في الخريطة؛ null = موقع المستخدم كما كان.
/// يعود إلى null حين يتبدّل الحساب (دخول أو خروج) حتى لا يرث زائرٌ منطقةَ بحث من قبله.
final rowCenterProvider = StateProvider<LatLng?>((ref) {
  ref.watch(signedInProvider);
  return null;
});

/// «الصف» في الرئيسية: الأقرب إلى موقع المستخدم (أو الأحدث بلا موقع)، كما يفعل [offersNearProvider].
/// لا يتبع حدود الخريطة عمداً: الخريطة تتبع البطاقة لا العكس، فلا يُعاد الجلب مع كل حركة. المستخدم وحده ينقله إلى
/// منطقة أخرى بزر «ابحث في هذه المنطقة» ([rowCenterProvider]).
final rowProvider = FutureProvider<RowFeed>((ref) async {
  final api = ref.watch(apiClientProvider);
  final center = ref.watch(rowCenterProvider);
  // مركز صريح: من الشبكة مباشرة بلا محفوظ، فالمحفوظ هو صف موقع المستخدم ولا يصح عرضه لمنطقة أخرى
  if (center != null) return api.rowNear(lat: center.latitude, lng: center.longitude, radiusKm: 15, limit: 30);
  // الموقع يُطلب فوراً لكن لا يُنتظر عند العرض من المحفوظ: تحديد الموقع قد يأخذ ثواني والبطاقات المحفوظة تظهر قبله
  final locF = ref.watch(userLocationProvider.future);
  return swr(ref, 'row', () async {
    final loc = Swr.cacheMode ? null : await locF;
    return api.rowNear(lat: loc?.latitude, lng: loc?.longitude, radiusKm: 15, limit: 30);
  });
});
