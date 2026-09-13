// أسماء الدوائر على الخريطة على طريقة خرائط قوقل: نص صغير بهالة بيضاء تحت نقطة كل دائرة، يُوضع في فضاء الشاشة مع منع
// التداخل (الأهم أولاً: الموثّقة ثم الأكثر متابعة)، ويزداد عدد الأسماء وحجم الخط كلما كبّرت الخريطة. إن لم يتسع المكان تحت
// النقطة يُجرَّب يمينها ثم يسارها ثم فوقها، وإلا يُخفى الاسم حتى التكبير التالي.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models.dart';
import '../../core/app_theme.dart';
import 'map_cluster.dart';

/// مرشّح اسم: موضعه على الشاشة وحجم نقطته وأولويته ونصّه.
class LabelCandidate {
  final String key;
  final String text;
  final Offset at;
  final double dot;
  /// أعلى أولوية = يُوضع أولاً ويحجز مكانه قبل غيره.
  final double priority;
  final Color color;
  final Object? data;
  const LabelCandidate({required this.key, required this.text, required this.at, required this.dot, required this.priority, this.color = Joy.text, this.data});
}

/// اسم موضوع: مستطيله على الشاشة وموضعه النسبي للنقطة.
class PlacedLabel {
  final LabelCandidate c;
  final Rect rect;
  /// below | right | left | above
  final String side;
  const PlacedLabel(this.c, this.rect, this.side);
  /// إزاحة الزاوية العلوية اليسرى للمستطيل عن النقطة.
  Offset get delta => rect.topLeft - c.at;
}

/// حجم الخط بحسب التكبير.
double labelFontSize(double zoom) => zoom >= 16 ? 13 : zoom >= 14 ? 12 : 11;

/// الحد الأقصى لعدد الأسماء بحسب التكبير (أقل عند التصغير حتى لا تزدحم الخريطة)؛ صفر تحت 11.
int labelBudget(double zoom) => zoom < 11 ? 0 : zoom < 12.5 ? 8 : zoom < 14 ? 16 : zoom < 15.5 ? 32 : 80;

/// قياس عرض النص (مع ذاكرة مؤقتة) بخط التطبيق.
final _measureCache = <String, double>{};
double measureLabelWidth(String text, double fontSize) => _measureCache.putIfAbsent('$fontSize|$text', () {
      final p = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)), textDirection: TextDirection.rtl, maxLines: 1)..layout();
      return p.width;
    });

/// أولوية الدائرة: الرسمية والموثّقة أولاً، ثم عدد المتابعين، ثم الأسماء الأقصر.
double businessPriority(Business b) => (b.verified ? 1000 : 0) + math.min(b.followers, 900).toDouble() - b.name.length * .1;

/// لون الاسم حسب فئة الدائرة (كما تلوّن قوقل أسماء المطاعم والفنادق).
Color labelColorFor(String? kind) => switch (kind) {
      'cafe' => const Color(0xFF7A4B2B),
      'hotel' => const Color(0xFF6A3FA0),
      'cinema' => const Color(0xFFB4306A),
      'hospital' => const Color(0xFFC62828),
      'airport' => const Color(0xFF1565C0),
      'car_rental' => const Color(0xFF2E7D32),
      'brand' => Joy.primary,
      'restaurant' => const Color(0xFFC2410C),
      'company' => const Color(0xFF334E68),
      'university' => const Color(0xFF3949AB),
      _ => const Color(0xFF3C4043),
    };

/// يضع الأسماء في فضاء الشاشة بلا تداخل: يمرّ على المرشّحين بترتيب الأولوية، ويحجز مستطيلات النقاط نفسها أولاً حتى لا
/// يغطي اسمٌ نقطةَ دائرة أخرى، ثم يجرّب المواضع الأربعة حول النقطة. الأسماء الخارجة عن الشاشة كلياً تُتجاهل.
List<PlacedLabel> placeLabels(List<LabelCandidate> candidates, {required Size screen, required double fontSize, required int budget, double Function(String text, double fontSize)? measure}) {
  if (budget <= 0 || candidates.isEmpty) return const [];
  final m = measure ?? measureLabelWidth;
  final sorted = [...candidates]..sort((a, b) => b.priority.compareTo(a.priority));
  final taken = <Rect>[for (final c in candidates) Rect.fromCircle(center: c.at, radius: c.dot / 2 + 1)];
  final bounds = Offset.zero & screen;
  final out = <PlacedLabel>[];
  final lineH = fontSize * 1.45;
  const padX = 6.0, gap = 2.0;
  for (final c in sorted) {
    if (out.length >= budget) break;
    if (!bounds.inflate(40).contains(c.at)) continue;
    final w = m(c.text, fontSize) + padX * 2;
    final h = lineH;
    final r = c.dot / 2;
    final options = <(String, Rect)>[
      ('below', Rect.fromLTWH(c.at.dx - w / 2, c.at.dy + r + gap, w, h)),
      ('right', Rect.fromLTWH(c.at.dx + r + gap + 1, c.at.dy - h / 2, w, h)),
      ('left', Rect.fromLTWH(c.at.dx - r - gap - 1 - w, c.at.dy - h / 2, w, h)),
      ('above', Rect.fromLTWH(c.at.dx - w / 2, c.at.dy - r - gap - h, w, h)),
    ];
    for (final (side, rect) in options) {
      if (rect.left < 0 || rect.top < 0 || rect.right > screen.width || rect.bottom > screen.height) continue;
      if (taken.any((t) => t.overlaps(rect.deflate(1)))) continue;
      taken.add(rect);
      out.add(PlacedLabel(c, rect, side));
      break;
    }
  }
  return out;
}

/// طبقة الأسماء داخل FlutterMap: تُعاد حساباتها مع كل حركة للكاميرا (MapCamera.of) فتتحرك الأسماء مع الخريطة بسلاسة.
class MapLabelLayer extends StatelessWidget {
  final List<MapItem> items;
  final double dot;
  final ValueChanged<MapItem>? onTap;
  const MapLabelLayer({super.key, required this.items, required this.dot, this.onTap});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final zoom = camera.zoom;
    final budget = labelBudget(zoom);
    if (budget == 0) return const SizedBox.shrink();
    final fontSize = labelFontSize(zoom);
    final cands = <LabelCandidate>[
      for (final it in items)
        if (it.kind == MapItemKind.business && it.title.trim().isNotEmpty)
          LabelCandidate(
            key: it.key, text: it.title.trim(), at: camera.latLngToScreenOffset(LatLng(it.lat, it.lng)), dot: dot,
            priority: businessPriority(it.data as Business), color: labelColorFor((it.data as Business).kind), data: it,
          ),
    ];
    final placed = placeLabels(cands, screen: camera.nonRotatedSize, fontSize: fontSize, budget: budget);
    return MarkerLayer(markers: [
      for (final p in placed)
        Marker(
          key: ValueKey('label-${p.c.key}'),
          point: LatLng((p.c.data as MapItem).lat, (p.c.data as MapItem).lng),
          width: p.rect.width,
          height: p.rect.height,
          // محاذاة تضع الزاوية العلوية اليسرى للمستطيل عند الإزاحة المحسوبة عن النقطة
          alignment: Alignment(2 * p.delta.dx / p.rect.width + 1, 2 * p.delta.dy / p.rect.height + 1),
          child: MapLabel(text: p.c.text, color: p.c.color, fontSize: fontSize, onTap: onTap == null ? null : () => onTap!(p.c.data as MapItem)),
        ),
    ]);
  }
}

/// نص الاسم بهالة بيضاء (طبقتان: حدّ أبيض ثم تعبئة ملونة) كما في خرائط قوقل.
class MapLabel extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  final VoidCallback? onTap;
  const MapLabel({super.key, required this.text, required this.color, required this.fontSize, this.onTap});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont, height: 1.2);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Stack(children: [
          Text(text, maxLines: 1, softWrap: false, style: base.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white.withValues(alpha: .92)..strokeJoin = StrokeJoin.round)),
          Text(text, maxLines: 1, softWrap: false, style: base.copyWith(color: color)),
        ]),
      ),
    );
  }
}
