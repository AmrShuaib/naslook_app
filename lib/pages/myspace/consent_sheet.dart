import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/share/legal_links.dart';

/// ورقة الموافقة على الشروط وسياسة الخصوصية للمستخدمين الذين سجّلوا قبل إضافتها أو عند تحديثها.
/// لا تُغلق بالسحب: إما الموافقة أو تسجيل الخروج. تعيد true عند الموافقة وfalse عند اختيار الخروج.
class ConsentSheet extends StatelessWidget {
  const ConsentSheet({super.key});

  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        builder: (_) => const PopScope(canPop: false, child: ConsentSheet()),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        key: const Key('consent-sheet'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.verified_user_outlined, size: 40, color: Joy.primary),
            const SizedBox(height: 10),
            const Text('شروط الاستخدام وسياسة الخصوصية', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('لمتابعة استخدام ناس لايف نحتاج موافقتك على الشروط وسياسة الخصوصية. لا تسامح مع المحتوى المسيء أو المستخدمين المسيئين، ونراجع البلاغات خلال 24 ساعة.',
                textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, height: 1.6)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(key: const Key('consent-terms'), onPressed: () => LegalLinks.open('terms'), child: const Text('شروط الاستخدام')),
              TextButton(key: const Key('consent-privacy'), onPressed: () => LegalLinks.open('privacy'), child: const Text('سياسة الخصوصية')),
            ]),
            const SizedBox(height: 8),
            FilledButton(key: const Key('consent-accept'), onPressed: () => Navigator.of(context).pop(true), child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('أوافق'))),
            TextButton(key: const Key('consent-logout'), onPressed: () => Navigator.of(context).pop(false), child: const Text('تسجيل الخروج', style: TextStyle(color: Joy.textMuted))),
          ]),
        ),
      );
}
