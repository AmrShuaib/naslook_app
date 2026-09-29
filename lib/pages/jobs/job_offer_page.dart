import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../ui/widgets.dart';

/// بديل مؤقت لصفحة العرض الوظيفي (الأسئلة والقبول)؛ تُستبدل بالصفحة الكاملة عند الدمج.
class JobOfferPage extends StatelessWidget {
  final String matchId;
  const JobOfferPage({super.key, required this.matchId});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('العرض الوظيفي')),
        body: const EmptyState(icon: Icons.work_outline_rounded, title: 'قريباً', subtitle: 'صفحة العرض تُبنى الآن.'),
      );
}
