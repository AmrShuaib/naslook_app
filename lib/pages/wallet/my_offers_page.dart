import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/biz_providers.dart';
import '../../ui/widgets.dart';
import '../business/business_list.dart';
import '../business/offers_page.dart';

/// «عروضي»: نافذة المحفظة على العروض المتاحة للعضو من دوائره، وما استخدمه وكم وفّر، وما انتهى خلال 30 يوماً.
/// لا حفظ ولا تفعيل: كل عرض من دائرة انضممت إليها يظهر هنا تلقائياً ويُطبّق على طلبك.
class MyOffersPage extends ConsumerStatefulWidget {
  final int initialTab;
  const MyOffersPage({super.key, this.initialTab = 0});
  @override
  ConsumerState<MyOffersPage> createState() => _MyOffersPageState();
}

class _MyOffersPageState extends ConsumerState<MyOffersPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myOffersProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('عروضي')),
      body: mine.when(
        data: (m) {
          final tabs = [('السارية', m.active.length), ('المستخدمة', m.used.length), ('المنتهية', m.expired.length)];
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myOffersProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _SavingsCard(month: m.savingsMonth, total: m.savingsTotal, uses: m.uses, active: m.active.length),
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (i, (label, n)) in tabs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          key: Key('offers-tab-$i'),
                          label: Text(n == 0 ? label : '$label $n'),
                          selected: _tab == i,
                          showCheckmark: false,
                          selectedColor: Joy.primary,
                          labelStyle: TextStyle(color: _tab == i ? Joy.primaryOn : Joy.text, fontWeight: FontWeight.w600, fontSize: 13),
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  if (m.active.isEmpty) const EmptyState(icon: Icons.local_offer_outlined, title: 'لا عروض متاحة الآن', subtitle: 'انضم إلى الدوائر التي تحبها لتظهر عروضها هنا وتُطبّق تلقائياً على طلباتك.'),
                  for (final o in m.active) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferCard(offer: o, member: true, showBiz: true)),
                ] else if (_tab == 1) ...[
                  if (m.used.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'لم تستخدم عرضاً بعد', subtitle: 'حين تطلب من دائرة وعرضها متاح لك يُخصم تلقائياً ويُسجّل هنا.'),
                  if (m.used.isNotEmpty) JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, u) in m.used.indexed) OfferUseRow(u, last: i == m.used.length - 1)])),
                ] else ...[
                  if (m.expired.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'لا عروض منتهية', subtitle: 'تبقى العروض المنتهية هنا 30 يوماً للرجوع إليها.'),
                  for (final o in m.expired) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferCard(offer: o, member: true, showBiz: true, compact: true)),
                ],
                if (m.active.isEmpty && m.used.isEmpty && _tab == 0) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessesPage())), icon: const Icon(Icons.storefront_outlined, size: 18), label: const Text('تصفّح الدوائر')),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myOffersProvider)),
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  final int month, total, uses, active;
  const _SavingsCard({required this.month, required this.total, required this.uses, required this.active});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Joy.primary, Color(0xFF0D8A96)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('وفّرت هذا الشهر', style: TextStyle(color: Joy.primaryOn, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(money(month), key: const Key('savings-month'), style: const TextStyle(color: Joy.primaryOn, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('الإجمالي ${money(total)} · ${uses == 0 ? 'لا استخدامات' : uses == 1 ? 'استخدام واحد' : uses == 2 ? 'استخدامان' : '$uses استخدامات'}', style: const TextStyle(color: Joy.primaryOn, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('$active', style: const TextStyle(color: Joy.primaryOn, fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 2),
              const Text('متاح لك', style: TextStyle(color: Joy.primaryOn, fontSize: 11)),
            ]),
          ),
        ]),
      );
}
