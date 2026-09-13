import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/posts_api.dart';
import '../../api/wishlist_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/wishlist_providers.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../events/events_page.dart';
import '../market/market_page.dart';
import '../posts/post_viewer.dart';

/// قائمة الأمنيات: ما حفظه المستخدم من منتجات وخدمات وفعاليات ومنشورات، وأمنيات حرة يكتبها بنفسه.
/// تصفية حسب النوع، فتح المصدر، تعليم "تحقّقت"، ملاحظة، وحذف.
class WishlistPage extends ConsumerStatefulWidget {
  const WishlistPage({super.key});
  @override
  ConsumerState<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends ConsumerState<WishlistPage> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(wishlistProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('قائمة أمنياتي')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addCustom, icon: const Icon(Icons.add_rounded), label: const Text('أمنية جديدة')),
      body: list.when(
        data: (items) {
          final counts = <String, int>{};
          for (final w in items) {
            counts[w.kind] = (counts[w.kind] ?? 0) + 1;
          }
          final shown = filter == 'all' ? items : [for (final w in items) if (w.kind == filter) w];
          return Column(children: [
            SizedBox(
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  _chip('الكل', 'all', items.length),
                  for (final e in wishKinds.entries) if ((counts[e.key] ?? 0) > 0) _chip(e.value, e.key, counts[e.key]!),
                ]),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyState(icon: Icons.favorite_border_rounded, title: 'قائمتك فارغة', subtitle: 'اضغط رمز الحفظ على أي منتج أو خدمة أو فعالية أو منشور ليُحفظ هنا، أو أضف أمنية حرة.')
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(wishlistProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => WishRow(shown[i], onOpen: () => _open(shown[i]), onMenu: () => _menu(shown[i])),
                      ),
                    ),
            ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(wishlistProvider)),
      ),
    );
  }

  Widget _chip(String label, String value, int n) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(selected: filter == value, onSelected: (_) => setState(() => filter = value), label: Text('$label · $n')),
      );

  Future<void> _open(WishItem w) async {
    switch (w.kind) {
      case 'market':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(w.refId!)));
      case 'item':
      case 'biz':
        final id = w.kind == 'biz' ? w.refId : w.bizId;
        if (id == null || id.isEmpty) return toast(context, 'الدائرة التجارية لم تعد متاحة', error: true);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessPage(id: id)));
      case 'event':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: w.refId!)));
      case 'post':
        try {
          final p = await ref.read(apiClientProvider).mapPost(w.refId!);
          if (mounted) PostViewerPage.open(context, [p]);
        } catch (_) {
          if (mounted) toast(context, 'المنشور لم يعد متاحاً', error: true);
        }
      default:
        _editCustom(w);
    }
  }

  Future<void> _menu(WishItem w) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(w.done ? Icons.undo_rounded : Icons.check_circle_outline_rounded), title: Text(w.done ? 'ما زالت أمنية' : 'تحقّقت ✓'), onTap: () => Navigator.pop(ctx, 'done')),
          if (!w.isCustom) ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('فتح المصدر'), onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(leading: const Icon(Icons.edit_note_rounded), title: Text(w.isCustom ? 'تعديل الأمنية' : 'ملاحظة'), onTap: () => Navigator.pop(ctx, 'note')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'done':
          await api.updateWish(w.id, done: !w.done);
        case 'open':
          await _open(w);
          return;
        case 'note':
          if (w.isCustom) {
            await _editCustom(w);
            return;
          }
          final note = await askText(context, title: 'ملاحظة', hint: 'مثال: بعد الراتب', initial: w.note, confirm: 'حفظ', maxLines: 2);
          if (note == null) return;
          await api.updateWish(w.id, note: note);
        case 'delete':
          await api.removeWish(w.id);
      }
      ref.invalidate(wishlistProvider);
    } catch (e) {
      if (mounted) toast(context, 'تعذر التحديث: $e', error: true);
    }
  }

  Future<void> _addCustom() => _editCustom(null);

  /// أمنية حرة: عنوان وملاحظة وسعر تقريبي اختياري.
  Future<void> _editCustom(WishItem? w) async {
    final title = TextEditingController(text: w?.title ?? '');
    final note = TextEditingController(text: w?.note ?? '');
    final price = TextEditingController(text: w?.price == null ? '' : (w!.price! ~/ 100).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w == null ? 'أمنية جديدة' : 'تعديل الأمنية'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, maxLength: 120, decoration: const InputDecoration(labelText: 'ماذا تتمنى؟', hintText: 'منتج، خدمة، فعالية…')),
          TextField(controller: note, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر التقريبي بالريال (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(w == null ? 'إضافة' : 'حفظ')),
        ],
      ),
    );
    final t = title.text.trim();
    if (ok != true || t.isEmpty || !mounted) return;
    final p = int.tryParse(price.text.trim());
    final halalas = p == null ? null : p * 100;
    try {
      final api = ref.read(apiClientProvider);
      if (w == null) {
        await api.addWish(kind: 'custom', title: t, note: note.text.trim(), price: halalas);
      } else {
        await api.updateWish(w.id, title: t, note: note.text.trim(), price: halalas, clearPrice: halalas == null);
      }
      ref.invalidate(wishlistProvider);
    } catch (e) {
      if (mounted) toast(context, 'تعذر الحفظ: $e', error: true);
    }
  }
}

/// صف أمنية: صورة أو رمز النوع، العنوان (مشطوب إن تحقّقت)، الوصف والسعر والملاحظة، وشارة "غير متاح".
class WishRow extends StatelessWidget {
  final WishItem w;
  final VoidCallback onOpen, onMenu;
  const WishRow(this.w, {super.key, required this.onOpen, required this.onMenu});

  static IconData iconFor(String kind) => switch (kind) {
        'market' => Icons.storefront_outlined,
        'item' => Icons.shopping_bag_outlined,
        'event' => Icons.confirmation_number_outlined,
        'post' => Icons.auto_awesome_motion_outlined,
        'biz' => Icons.business_outlined,
        _ => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Joy.textMuted, fontSize: 12.5, decoration: w.done ? TextDecoration.lineThrough : null);
    return JoyCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: w.done ? Joy.surface2 : Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: w.imageUrl != null && w.imageUrl!.isNotEmpty
              ? Image.network(thumbUrl(w.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(iconFor(w.kind), color: Joy.accent))
              : Icon(iconFor(w.kind), color: w.done ? Joy.textMuted : Joy.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: w.done ? TextDecoration.lineThrough : null, color: w.done ? Joy.textMuted : Joy.text)),
            if (w.subtitle.isNotEmpty || w.isCustom) Text(w.isCustom ? 'أمنية حرة' : w.subtitle, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (w.note.isNotEmpty) Text('📝 ${w.note}', style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (w.price != null) Text(w.price == 0 ? 'مجاناً' : money(w.price!), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 13.5)),
              if (w.done)
                _badge('تحقّقت ✓', Joy.primarySoft, Joy.primary)
              else if (!w.available)
                _badge('غير متاح حالياً', Joy.surface2, Joy.textMuted),
            ]),
          ]),
        ),
        IconButton(tooltip: 'خيارات', onPressed: onMenu, icon: const Icon(Icons.more_vert_rounded, color: Joy.textMuted)),
      ]),
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}
