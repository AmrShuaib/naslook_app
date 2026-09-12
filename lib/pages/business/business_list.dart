import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/biz_models.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/biz_providers.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart';
import 'my_bookings_page.dart';
import 'owner/my_businesses_page.dart';

/// مركز جدة: بديل الترتيب بالقرب حين يتعذّر تحديد الموقع.
const LatLng kJeddahCenter = LatLng(21.5433, 39.1728);

/// قائمة الدوائر التجارية مع تصفية بالفئة، ومفتوح الآن، وترتيب بالأقرب أو التقييم أو المتابعة (تُستخدم داخل تبويب الدوائر وفي صفحة مستقلة).
class BizListView extends ConsumerStatefulWidget {
  final EdgeInsets padding;
  const BizListView({super.key, this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 96)});
  @override
  ConsumerState<BizListView> createState() => _BizListViewState();
}

class _BizListViewState extends ConsumerState<BizListView> {
  String cat = '';
  bool open = false;
  String sort = '';
  LatLng? loc;
  bool locating = false;

  BizQuery get key => (cat: cat, open: open, sort: sort, lat: sort == 'near' ? loc?.latitude : null, lng: sort == 'near' ? loc?.longitude : null);

  /// «الأقرب»: موقع الجهاز، وإلا موقع المستخدم على الخريطة، وإلا مركز جدة مع تنبيه.
  Future<void> _near() async {
    if (sort == 'near') return setState(() => sort = '');
    setState(() => locating = true);
    var l = await DeviceLocation.current(precise: false);
    l ??= () {
      final p = ref.read(myPresenceProvider).valueOrNull;
      return p?.lat != null && p?.lng != null ? LatLng(p!.lat!, p.lng!) : null;
    }();
    if (!mounted) return;
    if (l == null) {
      l = kJeddahCenter;
      toast(context, 'تعذّر تحديد موقعك؛ رُتّبت حسب مركز جدة');
    }
    setState(() {
      loc = l;
      sort = 'near';
      locating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(bizListProvider(key));
    return Column(children: [
      SizedBox(
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _chip('الكل', Icons.apps_rounded, cat == '', () => setState(() => cat = '')),
            for (final c in BizCategory.values) _chip(c.plural, c.icon, cat == c.key, () => setState(() => cat = c.key)),
          ]),
        ),
      ),
      SizedBox(
        height: 40,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _chip('مفتوح الآن', Icons.schedule_rounded, open, () => setState(() => open = !open), color: Joy.success),
            _chip('الأقرب', locating ? Icons.hourglass_top_rounded : Icons.near_me_rounded, sort == 'near', locating ? () {} : _near),
            _chip('الأعلى تقييماً', Icons.star_rounded, sort == 'rating', () => setState(() => sort = sort == 'rating' ? '' : 'rating')),
            _chip('الأكثر متابعة', Icons.favorite_rounded, sort == 'popular', () => setState(() => sort = sort == 'popular' ? '' : 'popular')),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: list.when(
          skipLoadingOnReload: true,
          data: (items) => items.isEmpty
              ? EmptyState(icon: open ? Icons.schedule_rounded : Icons.storefront_outlined, title: open ? 'لا شيء مفتوح الآن في هذه الفئة' : 'لا دوائر تجارية بعد', subtitle: open ? 'أزل فلتر «مفتوح الآن» أو جرّب فئة أخرى.' : null)
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(bizListProvider(key)),
                  child: ListView.separated(
                    padding: widget.padding,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => BizRow(items[i]),
                  ),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizListProvider(key))),
        ),
      ),
    ]);
  }

  Widget _chip(String label, IconData icon, bool on, VoidCallback onTap, {Color color = Joy.primary}) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(
          avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
          label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text)),
          selected: on,
          showCheckmark: false,
          selectedColor: color,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );
}

/// شارة الحالة: مفتوح الآن / مغلق (تُخفى إن لم تُفهم ساعات العمل).
class OpenBadge extends StatelessWidget {
  final bool? openNow;
  const OpenBadge(this.openNow, {super.key});
  @override
  Widget build(BuildContext context) {
    final o = openNow;
    if (o == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: o ? const Color(0xFFE3F5EA) : Joy.surface2, borderRadius: BorderRadius.circular(999)),
      child: Text(o ? 'مفتوح الآن' : 'مغلق', style: TextStyle(fontSize: 10.5, color: o ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w700)),
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
              if (b.matchedItem != null && b.matchedItem!.isNotEmpty)
                Text('يوجد: ${b.matchedItem}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.primary, fontSize: 12)),
              const SizedBox(height: 3),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // التقييم والحالة والمسافة تلتف على سطرين عند الضيق، والسعر يبقى في الطرف
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Stars(rating: b.rating, count: b.ratingCount),
                    OpenBadge(b.openNow),
                    if (b.distanceLabel != null) Text(b.distanceLabel!, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                  ]),
                ),
                if (b.minPrice != null) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text('من ${money(b.minPrice!)}', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12.5))),
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
          actions: [
            IconButton(tooltip: 'نشاطي التجاري', icon: const Icon(Icons.storefront_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBusinessesPage()))),
            IconButton(tooltip: 'حجوزاتي', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage()))),
          ],
        ),
        body: const BizListView(padding: EdgeInsets.fromLTRB(20, 4, 20, 24)),
      );
}
