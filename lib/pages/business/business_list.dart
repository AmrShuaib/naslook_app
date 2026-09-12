import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/biz_models.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/biz_providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart';
import 'my_bookings_page.dart';

/// قائمة الدوائر التجارية مع تصفية بالفئة (تُستخدم داخل تبويب الدوائر وفي صفحة مستقلة).
class BizListView extends ConsumerStatefulWidget {
  final EdgeInsets padding;
  const BizListView({super.key, this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 96)});
  @override
  ConsumerState<BizListView> createState() => _BizListViewState();
}

class _BizListViewState extends ConsumerState<BizListView> {
  String cat = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(bizListProvider(cat));
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            _chip('الكل', Icons.apps_rounded, ''),
            for (final c in BizCategory.values) _chip(c.plural, c.icon, c.key),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: list.when(
          data: (items) => items.isEmpty
              ? const EmptyState(icon: Icons.storefront_outlined, title: 'لا دوائر تجارية بعد')
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(bizListProvider(cat)),
                  child: ListView.separated(
                    padding: widget.padding,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => BizRow(items[i]),
                  ),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizListProvider(cat))),
        ),
      ),
    ]);
  }

  Widget _chip(String label, IconData icon, String key) {
    final on = cat == key;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
        label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text)),
        selected: on,
        showCheckmark: false,
        selectedColor: Joy.primary,
        onSelected: (_) => setState(() => cat = key),
      ),
    );
  }
}

class BizRow extends StatelessWidget {
  final Biz b;
  const BizRow(this.b, {super.key});
  @override
  Widget build(BuildContext context) => JoyCard(
        onTap: () => openBusiness(context, b.id, initial: b),
        child: Row(children: [
          BizLogo(biz: b, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
                if (b.following) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: const Text('متابَع', style: TextStyle(fontSize: 10.5, color: Joy.primary, fontWeight: FontWeight.w600))),
              ]),
              Text('${b.sector.isNotEmpty ? b.sector : b.category.label} · ${b.address.split('،').first}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              const SizedBox(height: 3),
              Row(children: [
                Stars(rating: b.rating, count: b.ratingCount),
                const SizedBox(width: 10),
                Text('${b.followers} متابع', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                const Spacer(),
                if (b.minPrice != null) Text('من ${money(b.minPrice!)}', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ]),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        ]),
      );
}

/// صفحة مستقلة للدوائر التجارية (من الرئيسية).
class BusinessesPage extends StatelessWidget {
  const BusinessesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(
          title: const Text('الدوائر التجارية'),
          actions: [IconButton(tooltip: 'حجوزاتي', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage())))],
        ),
        body: const BizListView(padding: EdgeInsets.fromLTRB(20, 4, 20, 24)),
      );
}
