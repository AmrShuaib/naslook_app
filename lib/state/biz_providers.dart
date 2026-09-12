import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/biz_api.dart';
import '../api/biz_models.dart';
import 'app_state.dart';
import 'providers.dart';

/// قائمة الدوائر التجارية بفئة معيّنة ('' = الكل).
final bizListProvider = FutureProvider.family<List<Biz>, String>((ref, cat) => ref.watch(apiClientProvider).businessCircles(category: cat.isEmpty ? null : BizCategory.of(cat)));
final bizDetailProvider = FutureProvider.family<Biz, String>((ref, id) => ref.watch(apiClientProvider).businessCircle(id));
final myBizOrdersProvider = FutureProvider<List<BizOrder>>((ref) => ref.watch(apiClientProvider).myBizOrders());

/// الدوائر التجارية ضمن حدود الخريطة الحالية.
final mapBizProvider = FutureProvider<List<Biz>>((ref) => ref.watch(apiClientProvider).businessCircles(bbox: ref.watch(bboxProvider)));

/// نقطة تطلب صفحة أخرى من الخريطة التركيز عليها (تُصفَّر بعد الاستخدام).
final mapFocusProvider = StateProvider<({double lat, double lng})?>((_) => null);

void invalidateBiz(WidgetRef ref, String id) {
  ref.invalidate(bizDetailProvider(id));
  ref.invalidate(myBizOrdersProvider);
  ref.invalidate(bizListProvider);
}
