import 'package:flutter/material.dart';

import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';

/// علامات الثقة على الوظائف (فجوة 7 في تقرير النواقص): سطر الأمان الثابت، وشارة «دائرة غير موثّقة».
/// الخادم لا يرسل بطاقات عروض الدوائر غير الموثّقة، لكن عروضها تبقى في القائمة العامة، فالتحذير يسبق التقديم.

/// سطر الأمان: لا رسوم ولا صورة هوية قبل المقابلة. [compact] سطر صغير بلا إطار (بطاقة العرض في المحادثات).
class JobSafetyNote extends StatelessWidget {
  final bool compact;
  const JobSafetyNote({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(jobSafetyLine, style: TextStyle(color: Joy.sunText, fontSize: compact ? 11.5 : 12.5, height: 1.45, fontWeight: FontWeight.w600));
    if (compact) {
      return Row(key: const Key('job-safety'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.shield_outlined, size: 14, color: Joy.sunText)),
        const SizedBox(width: 6),
        Expanded(child: text),
      ]);
    }
    return Container(
      key: const Key('job-safety'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 18, color: Joy.sunText),
        const SizedBox(width: 8),
        Expanded(child: text),
      ]),
    );
  }
}

/// شارة «دائرة غير موثّقة»: الدائرة لم تقدّم سجلاً تجارياً أو وثيقة عمل حر معتمدة.
class UnverifiedCircleTag extends StatelessWidget {
  const UnverifiedCircleTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('job-unverified'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.info_outline_rounded, size: 13, color: Joy.textMuted),
          SizedBox(width: 4),
          Text('دائرة غير موثّقة', style: TextStyle(color: Joy.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}
