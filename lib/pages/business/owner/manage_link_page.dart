import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_theme.dart';
import '../../../state/biz_providers.dart';
import 'business_dashboard_page.dart';
import 'my_businesses_page.dart';

/// وجهة رابط الإدارة من الويب (`naslife.app/business/manage`): من يدير دائرة واحدة يدخل لوحتها مباشرة،
/// ومن يدير أكثر أو لا يدير شيئاً يرى «نشاطي التجاري» (القائمة وزر التسجيل).
class ManageLinkPage extends ConsumerWidget {
  const ManageLinkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myBusinessesProvider);
    return mine.when(
      loading: () => const Scaffold(backgroundColor: Joy.bg, body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const MyBusinessesPage(),
      data: (m) => m.circles.length == 1 ? BusinessDashboardPage(key: const Key('manage-dashboard'), id: m.circles.first.id, initial: m.circles.first) : const MyBusinessesPage(),
    );
  }
}
