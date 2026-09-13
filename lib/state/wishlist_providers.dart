import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/wishlist_api.dart';
import '../ui/widgets.dart';
import 'app_state.dart';

/// قائمة أمنيات المستخدم الحالي.
final wishlistProvider = FutureProvider<List<WishItem>>((ref) => ref.watch(apiClientProvider).wishlist());

/// مفاتيح العناصر المحفوظة (نوع:مرجع) لتلوين أزرار القلب فوراً.
final wishKeysProvider = Provider<Set<String>>((ref) => ref.watch(wishlistProvider).maybeWhen(data: (l) => {for (final w in l) w.key}, orElse: () => const <String>{}));

/// يضيف المرجع إلى الأمنيات أو يزيله إن كان محفوظاً، مع رسالة قصيرة.
Future<void> toggleWish(BuildContext context, WidgetRef ref, {required String kind, required String refId}) async {
  final api = ref.read(apiClientProvider);
  final current = ref.read(wishlistProvider).valueOrNull ?? const <WishItem>[];
  WishItem? existing;
  for (final w in current) {
    if (w.kind == kind && w.refId == refId) existing = w;
  }
  try {
    if (existing != null) {
      await api.removeWish(existing.id);
      if (context.mounted) toast(context, 'أُزيل من قائمة أمنياتك');
    } else {
      await api.addWish(kind: kind, refId: refId);
      if (context.mounted) toast(context, 'أُضيف إلى قائمة أمنياتك');
    }
    ref.invalidate(wishlistProvider);
  } catch (e) {
    if (context.mounted) toast(context, 'تعذر تحديث قائمة الأمنيات', error: true);
  }
}
