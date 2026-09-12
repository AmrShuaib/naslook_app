import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../state/biz_providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart';

/// كل طلبات وحجوزات المستخدم لدى الدوائر التجارية.
class MyBookingsPage extends ConsumerWidget {
  const MyBookingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myBizOrdersProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('حجوزاتي وطلباتي')),
      body: orders.when(
        data: (list) {
          if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا حجوزات بعد', subtitle: 'احجز فندقاً أو سيارة أو تذاكر سينما أو اشترِ من براند، وستظهر هنا برموزها.');
          final up = list.where((o) => o.upcoming).toList(), past = list.where((o) => !o.upcoming).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myBizOrdersProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              if (up.isNotEmpty) ...[
                const SectionTitle('السارية'),
                JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, o) in up.indexed) OrderRow(o, showBiz: true, last: i == up.length - 1, onChanged: () => ref.invalidate(myBizOrdersProvider))])),
              ],
              if (past.isNotEmpty) ...[
                const SectionTitle('السابقة'),
                Opacity(opacity: .7, child: JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, o) in past.indexed) OrderRow(o, showBiz: true, last: i == past.length - 1)]))),
              ],
            ]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myBizOrdersProvider)),
      ),
    );
  }
}
