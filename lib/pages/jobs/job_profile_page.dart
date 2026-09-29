import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../ui/widgets.dart';

/// بديل مؤقت لصفحة ملف التوظيف («أبحث عن عمل»)؛ تُستبدل بالصفحة الكاملة عند الدمج.
class JobProfilePage extends StatelessWidget {
  const JobProfilePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('أبحث عن عمل')),
        body: const EmptyState(icon: Icons.badge_outlined, title: 'قريباً', subtitle: 'ملف التوظيف يُبنى الآن.'),
      );
}
