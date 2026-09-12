import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../state/wishlist_providers.dart';

/// زر حفظ (إشارة مرجعية) يضيف عنصراً (عرض سوق، منتج/خدمة دائرة، فعالية، منشور) إلى قائمة الأمنيات أو يزيله منها.
class WishButton extends ConsumerWidget {
  final String kind, refId;
  /// حجم مضغوط داخل البطاقات
  final bool compact;
  /// فوق خلفية داكنة (عارض المنشورات)
  final bool dark;
  const WishButton({super.key, required this.kind, required this.refId, this.compact = false, this.dark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wished = ref.watch(wishKeysProvider).contains('$kind:$refId');
    return IconButton(
      key: ValueKey('wish-$kind-$refId'),
      tooltip: wished ? 'إزالة من أمنياتي' : 'أضف إلى أمنياتي',
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: compact ? const EdgeInsets.all(4) : null,
      constraints: compact ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
      onPressed: () => toggleWish(context, ref, kind: kind, refId: refId),
      icon: Icon(wished ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined, color: wished ? Joy.accent : (dark ? Colors.white : Joy.textMuted), size: compact ? 22 : 24),
    );
  }
}
