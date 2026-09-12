import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// خلفية نقشية خفيفة جداً تمثّل Naslife: شبكة منتظمة متناوبة من علامة Naslife
/// (ثلاث دوائر فوق ثلاثة أشخاص) ورموز التطبيق (دردشة، موقع، دوائر، قهوة، تذاكر، سوق، قلب…)
/// بلون العلامة بشفافية منخفضة على الأبيض، كما في خلفية المحادثات في واتساب.
class NaslifePattern extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double cell;
  const NaslifePattern({super.key, required this.child, this.opacity = 0.075, this.cell = 78});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: CustomPaint(painter: _PatternPainter(color: Joy.primary.withValues(alpha: opacity), cell: cell))),
        child,
      ]);
}

class _PatternPainter extends CustomPainter {
  final Color color;
  final double cell;
  _PatternPainter({required this.color, required this.cell});

  static const _icons = <IconData>[
    Icons.chat_bubble_outline_rounded,
    Icons.location_on_outlined,
    Icons.groups_outlined,
    Icons.favorite_border_rounded,
    Icons.local_cafe_outlined,
    Icons.confirmation_number_outlined,
    Icons.storefront_outlined,
    Icons.map_outlined,
    Icons.star_border_rounded,
    Icons.photo_camera_outlined,
    Icons.mic_none_rounded,
    Icons.celebration_outlined,
  ];

  final _painters = <IconData, TextPainter>{};

  TextPainter _glyph(IconData icon, double size) => _painters.putIfAbsent(icon, () {
        final tp = TextPainter(
          text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color)),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp;
      });

  /// علامة Naslife المبسّطة: ثلاث دوائر فوق ثلاثة أقواس (أشخاص) متجاورة.
  void _logo(Canvas canvas, Offset c, double s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;
    final gap = s * 0.34;
    for (var i = -1; i <= 1; i++) {
      final x = c.dx + i * gap;
      canvas.drawCircle(Offset(x, c.dy - s * 0.30), s * 0.11, p);
      // شخص: قوس علوي وساقان
      final top = c.dy - s * 0.08;
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(x - s * 0.13, top, s * 0.26, s * 0.42), topLeft: Radius.circular(s * 0.13), topRight: Radius.circular(s * 0.13));
      final path = Path()
        ..moveTo(r.left, r.bottom)
        ..lineTo(r.left, r.top + s * 0.13)
        ..arcToPoint(Offset(r.right, r.top + s * 0.13), radius: Radius.circular(s * 0.13))
        ..lineTo(r.right, r.bottom);
      canvas.drawPath(path, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / cell).ceil() + 2;
    final rows = (size.height / cell).ceil() + 2;
    final iconSize = cell * 0.30;
    for (var r = -1; r < rows; r++) {
      final shift = r.isOdd ? cell / 2 : 0.0; // صفوف متناوبة لشبكة مرتبة
      for (var c = -1; c < cols; c++) {
        final center = Offset(c * cell + shift + cell / 2, r * cell + cell / 2);
        final idx = ((r + 1000) * 7 + (c + 1000) * 3) % (_icons.length + 2);
        if (idx >= _icons.length) {
          _logo(canvas, center, cell * 0.52);
        } else {
          final tp = _glyph(_icons[idx], iconSize);
          tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }
    // تدرّج خفيف جداً في الحواف حتى لا تبدو النقشة صلبة عند الشريطين العلوي والسفلي
    final fade = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .6), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .6)], stops: const [0, .08, .92, 1])
          .createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);
    assert(math.max(cols, rows) > 0);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.color != color || old.cell != cell;
}
