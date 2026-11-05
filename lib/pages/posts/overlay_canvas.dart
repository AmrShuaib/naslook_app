import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/posts_api.dart';

/// لون من نص hex مثل #RRGGBB أو #RRGGBBAA.
Color colorFromHex(String? hex, [Color fallback = Colors.white]) {
  final h = (hex ?? '').replaceFirst('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse('${h.substring(6)}${h.substring(0, 6)}', radix: 16));
  return fallback;
}

String hexFromColor(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// أقصى ما تأخذه طبقة نص من ارتفاع القماش المرجعي؛ النص الأطول (أسطر كثيرة في منشور نصي) يصغر خطه بدل أن يُقصّ
const double kOverlayTextRoom = .8;

/// أصغر خط تنزل إليه طبقة النص في العارض نسبةً إلى عرض القماش (≈10 بكسل على هاتف بعرض 390)
const double kOverlayMinFontPerWidth = .065 * .4;

/// ارتفاع القماش المرجعي: نسبة ٩:١٦ بعرضه (العارض على الهاتف أطول منها، وعلى سطح المكتب بها). القياس عليها يجعل الخط
/// نسبةً إلى العرض واحداً في المحرّر والعارض أياً كان الجهاز، فتنكسر الأسطر في الموضع نفسه.
double overlayRefHeight(double w, double h) => math.min(h, w * 16 / 9);

/// أكبر خط بين [min] و[base] يجعل [text] الملفوف بعرض [width] لا يتجاوز [maxHeight]، بدرجات نصف بكسل حتى لا يرتجف
/// الخط مع كل حرف. `strut` يقيس كما يرسم `EditableText` (ارتفاع سطر ثابت)، وبدونه كما يرسم `Text`.
/// `fits` خطأ حين لا يتسع حتى بالحد الأدنى.
({double size, bool fits}) fitTextFont({
  required String text,
  required TextStyle style,
  required double width,
  required double maxHeight,
  required double base,
  required double min,
  bool strut = false,
  TextDirection textDirection = TextDirection.rtl,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final w = math.max(0.0, width);
  double measure(double f) {
    final s = style.copyWith(fontSize: f);
    final tp = TextPainter(text: TextSpan(text: text, style: s), textAlign: TextAlign.center, textDirection: textDirection, textScaler: textScaler, strutStyle: strut ? StrutStyle.fromTextStyle(s, forceStrutHeight: true) : null)
      ..layout(minWidth: w, maxWidth: w);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  final lo = math.min(min, base);
  if (measure(base) <= maxHeight) return (size: base, fits: true);
  if (measure(lo) > maxHeight) return (size: lo, fits: false);
  // بحث ثنائي على درجات نصف بكسل فوق lo: الدرجة a تتسع والدرجة b لا تتسع (base نفسه لا يتسع)
  final steps = ((base - lo) * 2).floor();
  var a = 0, b = lo + steps / 2 >= base - 1e-9 ? steps : steps + 1;
  while (b - a > 1) {
    final m = (a + b) >> 1;
    if (measure(lo + m / 2) <= maxHeight) {
      a = m;
    } else {
      b = m;
    }
  }
  return (size: lo + a / 2, fits: true);
}

/// نمط نص الطبقة كما يرسمه العارض (بلا الظل الذي لا يغيّر القياس)
TextStyle overlayTextStyle(PostOverlay o, double size) => TextStyle(
      color: colorFromHex(o.color), fontSize: size, height: 1.25,
      fontWeight: o.font == 'plain' ? FontWeight.w600 : FontWeight.w800,
      fontStyle: o.font == 'hand' ? FontStyle.italic : FontStyle.normal,
      fontFamily: o.font == 'serif' ? 'serif' : null,
    );

// العارض يعيد البناء مع كل نبضة تقدّم (20 مرة في الثانية)؛ نتيجة القياس تُحفظ حتى لا يُقاس النص في كل إطار
final _fitCache = <Object, double>{};

/// خط طبقة نص في قماش [canvasW]×[canvasH]: عرض القماش × 0.065 × المقياس كما كان، إلا أن يتجاوز النص
/// [kOverlayTextRoom] من الارتفاع المرجعي فيصغر حتى يتسع (حتى [kOverlayMinFontPerWidth]). لا تتغير البيانات المحفوظة.
double overlayFontSize(BuildContext context, PostOverlay o, double canvasW, double canvasH) {
  final base = canvasW * (o.isSticker ? 0.12 : 0.065) * o.scale;
  if (o.isSticker || o.text.isEmpty || !canvasW.isFinite || !canvasH.isFinite || canvasW <= 0 || canvasH <= 0) return base;
  final style = DefaultTextStyle.of(context).style.merge(overlayTextStyle(o, base));
  // الخلفية تضيف ربع الخط أعلى النص وأسفله
  final room = kOverlayTextRoom * overlayRefHeight(canvasW, canvasH) - (o.bg == null ? 0 : base * .5);
  final scaler = MediaQuery.textScalerOf(context), dir = Directionality.of(context);
  final key = (o.text, style, canvasW, room, scaler, dir);
  final hit = _fitCache[key];
  if (hit != null) return hit;
  final size = fitTextFont(text: o.text, style: style, width: canvasW * .85, maxHeight: room, base: base, min: canvasW * kOverlayMinFontPerWidth, textDirection: dir, textScaler: scaler).size;
  if (_fitCache.length >= 64) _fitCache.clear();
  return _fitCache[key] = size;
}

/// يرسم طبقات المنشور (نصوص وملصقات) فوق الوسائط بمواضع نسبية حتى تتطابق في المحرّر والعارض مهما اختلف حجم الشاشة.
/// في وضع التحرير تُسحب الطبقة بالإصبع وتُكبَّر وتُدار بالإصبعين، ونقرة تحددها ونقرتان تفتحان تعديلها.
class OverlayCanvas extends StatelessWidget {
  final List<PostOverlay> overlays;
  final bool editable;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final void Function(int index, PostOverlay updated)? onChanged;
  final ValueChanged<int>? onEdit;
  /// طبقة تُخفى مؤقتاً (أثناء كتابتها مباشرة على اللوحة في المحرّر)
  final int? hiddenIndex;
  /// ظل خلف النص ليُقرأ فوق الصور والفيديو؛ يُعطَّل على لوحة المنشور النصي المسطّحة
  final bool shadow;
  const OverlayCanvas({super.key, required this.overlays, this.editable = false, this.selected, this.onSelect, this.onChanged, this.onEdit, this.hiddenIndex, this.shadow = true});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < overlays.length; i++)
            if (i != hiddenIndex)
            Positioned(
              left: overlays[i].x * w,
              top: overlays[i].y * h,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _OverlayGesture(
                  key: ValueKey('ov$i'),
                  enabled: editable,
                  selected: editable && selected == i,
                  overlay: overlays[i],
                  canvasW: w,
                  canvasH: h,
                  onSelect: () => onSelect?.call(i),
                  onChanged: (o) => onChanged?.call(i, o),
                  onEdit: () => onEdit?.call(i),
                  child: OverlayContent(overlay: overlays[i], canvasWidth: w, canvasHeight: h, shadow: shadow),
                ),
              ),
            ),
        ]);
      });
}

/// محتوى طبقة واحدة: نص بخلفية اختيارية وظل للقراءة على الصور، أو ملصق إيموجي كبير.
/// مع [canvasHeight] يصغر النص الأطول من القماش ليظهر كله (`overlayFontSize`).
class OverlayContent extends StatelessWidget {
  final PostOverlay overlay;
  final double canvasWidth;
  final double? canvasHeight;
  final bool shadow;
  const OverlayContent({super.key, required this.overlay, required this.canvasWidth, this.canvasHeight, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final size = canvasHeight == null ? canvasWidth * (o.isSticker ? 0.12 : 0.065) * o.scale : overlayFontSize(context, o, canvasWidth, canvasHeight!);
    if (o.isSticker) return Text(o.text, style: TextStyle(fontSize: size, height: 1.1), textAlign: TextAlign.center);
    final bg = o.bg == null ? null : colorFromHex(o.bg);
    final style = overlayTextStyle(o, size).copyWith(shadows: bg == null && shadow ? [const Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))] : null);
    final text = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: canvasWidth * 0.85),
      child: Text(o.text, textAlign: switch (o.align) { 'start' => TextAlign.start, 'end' => TextAlign.end, _ => TextAlign.center }, style: style),
    );
    if (bg == null) return text;
    return Container(padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: size * .25), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .5)), child: text);
  }
}

class _OverlayGesture extends StatefulWidget {
  final bool enabled, selected;
  final PostOverlay overlay;
  final double canvasW, canvasH;
  final VoidCallback onSelect, onEdit;
  final ValueChanged<PostOverlay> onChanged;
  final Widget child;
  const _OverlayGesture({super.key, required this.enabled, required this.selected, required this.overlay, required this.canvasW, required this.canvasH, required this.onSelect, required this.onChanged, required this.onEdit, required this.child});
  @override
  State<_OverlayGesture> createState() => _OverlayGestureState();
}

class _OverlayGestureState extends State<_OverlayGesture> {
  double _startScale = 1, _startRot = 0;

  @override
  Widget build(BuildContext context) {
    final body = Transform.rotate(angle: widget.overlay.rot, child: Transform.scale(scale: 1, child: widget.child));
    if (!widget.enabled) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelect,
      onDoubleTap: widget.onEdit,
      onScaleStart: (_) {
        widget.onSelect();
        _startScale = widget.overlay.scale;
        _startRot = widget.overlay.rot;
      },
      onScaleUpdate: (d) {
        final o = widget.overlay;
        widget.onChanged(o.copyWith(
          x: (o.x + d.focalPointDelta.dx / widget.canvasW).clamp(0.0, 1.0),
          y: (o.y + d.focalPointDelta.dy / widget.canvasH).clamp(0.0, 1.0),
          scale: (_startScale * d.scale).clamp(0.3, 5.0),
          rot: (_startRot + d.rotation).clamp(-3.2, 3.2),
        ));
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: widget.selected ? BoxDecoration(border: Border.all(color: Colors.white70, width: 1.5), borderRadius: BorderRadius.circular(8)) : null,
        child: body,
      ),
    );
  }
}
