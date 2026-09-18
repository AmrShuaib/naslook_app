// البازارات الموسمية: شريط في أعلى السوق وصفحة لكل بازار بعروضه، والبائع يضيف عروضه إليه من الصفحة نفسها
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'market_page.dart';

final bazaarProvider = FutureProvider.family<Bazaar, String>((ref, id) async {
  final pos = await ref.watch(marketPosProvider.future);
  return ref.watch(apiClientProvider).bazaar(id, lat: pos?.lat, lng: pos?.lng);
});

String bazaarDates(Bazaar b) {
  String d(DateTime? t) => t == null ? '' : '${t.day}/${t.month}';
  if (b.upcoming) return 'يبدأ ${d(b.startsAt)} وينتهي ${d(b.endsAt)}';
  if (b.live) return 'حتى ${d(b.endsAt)}';
  return 'انتهى ${d(b.endsAt)}';
}

/// شريط البازارات في أعلى السوق: بطاقة لكل بازار جارٍ أو قادم
class BazaarStrip extends StatelessWidget {
  final List<Bazaar> items;
  const BazaarStrip({super.key, required this.items});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JoyCard(
                key: Key('bazaar-${b.id}'), color: b.live ? Joy.sunSoft : Joy.surface2, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BazaarPage(b.id))),
                child: Row(children: [
                  Icon(Icons.celebration_rounded, color: b.live ? Joy.sunText : Joy.textMuted),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text('${b.stateLabel} · ${b.listings} عرض${b.city.isNotEmpty ? ' · ${b.city}' : ''} · ${bazaarDates(b)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                  ])),
                  const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
                ]),
              ),
            ),
        ]),
      );
}

class BazaarPage extends ConsumerWidget {
  final String id;
  const BazaarPage(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bazaarProvider(id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(b.valueOrNull?.title ?? 'بازار')),
      body: b.when(
        data: (x) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(bazaarProvider(id)),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: JoyCard(color: x.live ? Joy.sunSoft : Joy.surface2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: x.live ? Joy.sun : Joy.control, borderRadius: BorderRadius.circular(999)), child: Text(x.stateLabel, style: TextStyle(color: x.live ? Joy.sunText : Joy.text, fontSize: 11.5, fontWeight: FontWeight.w800))),
                ]),
                if (x.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(x.description, style: const TextStyle(fontSize: 13.5))),
                const SizedBox(height: 6),
                Text('${x.listings} عرض${x.city.isNotEmpty ? ' · ${x.city}' : ''}${x.category != null ? ' · ${marketCategories[x.category] ?? x.category}' : ''} · ${bazaarDates(x)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                if (x.state != 'ended') Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.tonalIcon(key: const Key('bazaar-join'), onPressed: () => _pickMine(context, ref, x), icon: const Icon(Icons.add_business_outlined, size: 18), label: Text(x.mine > 0 ? 'عروضي في البازار (${x.mine})' : 'أضف عروضك')))),
              ])),
            )),
            if (x.items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.celebration_outlined, title: 'لا عروض بعد', subtitle: 'كن أول من يضيف عرضه إلى هذا البازار.'))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .72),
                  delegate: SliverChildBuilderDelegate((_, i) => ListingCard(x.items[i]), childCount: x.items.length),
                ),
              ),
          ]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bazaarProvider(id))),
      ),
    );
  }

  /// ورقة باختيار عروضي النشطة: نقرة تضيف العرض أو تزيله من البازار
  Future<void> _pickMine(BuildContext context, WidgetRef ref, Bazaar b) async {
    List<Listing> all;
    try { all = await ref.read(myListingsProvider.future); } catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); return; }
    final mine = all.where((l) => l.status == 'active' && (b.category == null || l.category == b.category)).toList();
    final inBazaar = {for (final l in b.items) if (l.mine) l.id};
    if (!context.mounted) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('عروضك في البازار', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(b.category != null ? 'يقبل هذا البازار عروض ${marketCategories[b.category] ?? b.category} فقط' : 'اختر ما تريد عرضه في البازار', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (mine.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('ليس لديك عروض نشطة مناسبة. انشر عرضاً أولاً من السوق.', style: TextStyle(color: Joy.textMuted))),
        Flexible(child: ListView(shrinkWrap: true, children: [
          for (final l in mine)
            SwitchListTile(
              key: Key('bz-add-${l.id}'), contentPadding: EdgeInsets.zero, value: inBazaar.contains(l.id), title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(money(l.price), style: const TextStyle(fontSize: 12)),
              onChanged: (v) async {
                try {
                  if (v) { await ref.read(apiClientProvider).joinBazaar(b.id, l.id); inBazaar.add(l.id); } else { await ref.read(apiClientProvider).leaveBazaar(b.id, l.id); inBazaar.remove(l.id); }
                  setSt(() {});
                  ref.invalidate(bazaarProvider(b.id)); ref.invalidate(marketHomeProvider);
                } catch (e) { if (ctx.mounted) toast(ctx, marketErrText(e), error: true); }
              },
            ),
        ])),
      ]),
    ))));
  }
}
