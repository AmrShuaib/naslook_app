import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/update/app_update.dart';

/// شريط رفيع أعلى الشاشة يظهر حين تُنشر نسخة ويب جديدة والتطبيق مفتوح؛ «تحديث الآن» يعيد التحميل.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppUpdate.available,
        builder: (context, on, _) => on
            ? Material(
                key: const Key('update-banner'),
                color: Joy.primary,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    child: Row(children: [
                      const Icon(Icons.system_update_alt_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('نسخة جديدة من ناس لايف جاهزة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5))),
                      TextButton(
                        key: const Key('update-now'),
                        onPressed: AppUpdate.reload,
                        style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: .18), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: const Text('تحديث الآن'),
                      ),
                    ]),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
}
