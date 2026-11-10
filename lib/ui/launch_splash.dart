import 'dart:math' as math;

import 'package:flutter/material.dart';

/// مقدمة التطبيق: شعار ناس لايف على خلفية بيضاء مع أربع نقاط بألوانه. هي نفسها شاشة البداية في web/index.html (قبل
/// تحميل Flutter) وشاشة الإطلاق في iOS، بالمقاس والموضع نفسيهما، فيبقى الشعار ثابتاً أمام المستخدم من لحظة الفتح حتى
/// تُستعاد الجلسة بدل قفزة إلى مؤشر تحميل.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key});

  static const asset = 'assets/brand/naslife_logo.png';

  /// ألوان الشعار بترتيب النقاط في index.html (أصفر، أزرق، أخضر، أحمر)
  static const dotColors = [Color(0xFFFEB304), Color(0xFF0275FD), Color(0xFF29B25F), Color(0xFFEE3B2A)];

  /// عرض الشعار: 56% من عرض الشاشة بحد 260 (يطابق `min(56vw, 260px)` في index.html)
  static double logoWidth(double screenWidth) => math.min(screenWidth * 0.56, 260);

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // تقليل الحركة من إعدادات النظام: نقاط ثابتة
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// نبضة كل نقطة كما في index.html: صغيرة باهتة، ثم كاملة عند 40% من الدورة، ثم تعود عند 80%
  static double _bump(double t) => t < .4 ? t / .4 : t < .8 ? (.8 - t) / .4 : 0;

  @override
  Widget build(BuildContext context) {
    final w = LaunchSplash.logoWidth(MediaQuery.sizeOf(context).width);
    return Scaffold(
      key: const Key('launch-splash'),
      backgroundColor: Colors.white,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(LaunchSplash.asset, key: const Key('launch-logo'), width: w, height: w, gaplessPlayback: true, semanticLabel: 'ناس لايف'),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < LaunchSplash.dotColors.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Builder(builder: (context) {
                  final b = _c.isAnimating ? _bump((_c.value - i * .15) % 1.0) : 1.0;
                  return Opacity(
                    opacity: .4 + .6 * b,
                    child: Transform.scale(
                      scale: .6 + .4 * b,
                      child: Container(width: 8, height: 8, decoration: BoxDecoration(color: LaunchSplash.dotColors[i], shape: BoxShape.circle)),
                    ),
                  );
                }),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
