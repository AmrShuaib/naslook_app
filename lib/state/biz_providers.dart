import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/biz_api.dart';
import '../api/biz_models.dart';
import 'app_state.dart';
import 'providers.dart';

/// قائمة الدوائر التجارية بفئة معيّنة ('' = الكل).
/// مفتاح قائمة الدوائر: الفئة، مفتوح الآن، الترتيب، وموقع المستخدم للترتيب بالقرب.
typedef BizQuery = ({String cat, bool open, String sort, double? lat, double? lng});
const BizQuery bizQueryAll = (cat: '', open: false, sort: '', lat: null, lng: null);
final bizListProvider = FutureProvider.family<List<Biz>, BizQuery>((ref, k) =>
    ref.watch(apiClientProvider).businessCircles(category: k.cat.isEmpty ? null : BizCategory.of(k.cat), openNow: k.open, sort: k.sort, lat: k.lat, lng: k.lng));
final bizDetailProvider = FutureProvider.family<Biz, String>((ref, id) => ref.watch(apiClientProvider).businessCircle(id));
final myBizOrdersProvider = FutureProvider<List<BizOrder>>((ref) => ref.watch(apiClientProvider).myBizOrders());

// ---- العروض
/// عروض دائرة معيّنة (السارية والقادمة والمنتهية) مع حالة العضوية ومستوى التنبيه.
final bizOffersProvider = FutureProvider.family<BizOffersPage, String>((ref, id) => ref.watch(apiClientProvider).bizOffers(id));
/// عروضي من الدوائر المنضم إليها.
final myOffersProvider = FutureProvider<MyOffers>((ref) => ref.watch(apiClientProvider).myOffers());
/// عروض الدائرة من جهة المالك مع الإحصاءات والقوالب.
final manageOffersProvider = FutureProvider.family<ManageOffers, String>((ref, id) => ref.watch(apiClientProvider).manageOffers(id));

/// الدوائر التجارية ضمن حدود الخريطة الحالية.
final mapBizProvider = FutureProvider<List<Biz>>((ref) => ref.watch(apiClientProvider).businessCircles(bbox: ref.watch(bboxProvider)));

/// نقطة تطلب صفحة أخرى من الخريطة التركيز عليها (تُصفَّر بعد الاستخدام).
final mapFocusProvider = StateProvider<({double lat, double lng})?>((_) => null);

void invalidateBiz(WidgetRef ref, String id) {
  ref.invalidate(bizDetailProvider(id));
  ref.invalidate(myBizOrdersProvider);
  ref.invalidate(bizListProvider);
  ref.invalidate(bizOffersProvider(id));
  ref.invalidate(myOffersProvider);
}

// ---- لوحة صاحب النشاط
final myBusinessesProvider = FutureProvider<MyBusinesses>((ref) => ref.watch(apiClientProvider).myBusinesses());
final bizStatsProvider = FutureProvider.family<BizStats, String>((ref, id) => ref.watch(apiClientProvider).bizStats(id));
final bizOrdersProvider = FutureProvider.family<List<BizOrder>, ({String id, String status})>((ref, k) => ref.watch(apiClientProvider).bizOrders(k.id, status: k.status));
final bizTeamProvider = FutureProvider.family<BizTeam, String>((ref, id) => ref.watch(apiClientProvider).bizTeam(id));
final bizClaimsProvider = FutureProvider<List<BizClaim>>((ref) => ref.watch(apiClientProvider).bizClaims());

/// يحدّث كل ما يخص الدائرة بعد تعديل من لوحة التحكم.
void invalidateBizAll(WidgetRef ref, String id) {
  invalidateBiz(ref, id);
  ref.invalidate(bizStatsProvider(id));
  ref.invalidate(bizOrdersProvider);
  ref.invalidate(bizTeamProvider(id));
  ref.invalidate(myBusinessesProvider);
  ref.invalidate(mapBizProvider);
  ref.invalidate(manageOffersProvider(id));
}
