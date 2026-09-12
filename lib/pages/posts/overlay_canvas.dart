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

/// يرسم طبقات المنشور (نصوص وملصقات) فوق الوسائط بمواضع نسبية حتى تتطابق في المحرّر والعارض مهما اختلف حجم الشاشة.
/// في وضع التحرير تُسحب الطبقة بالإصبع وتُكبَّر وتُدار بالإصبعين، ونقرة تحددها ونقرتان تفتحان تعديلها.
class OverlayCanvas extends StatelessWidget {
  final List<PostOverlay> overlays;
  final bool editable;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final void Function(int index, PostOverlay updated)? onChanged;
  final ValueChanged<int>? onEdit;
  const OverlayCanvas({super.key, required this.overlays, this.editable = false, this.selected, this.onSelect, this.onChanged, this.onEdit});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < overlays.length; i++)
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
                  child: OverlayContent(overlay: overlays[i], canvasWidth: w),
                ),
              ),
            ),
        ]);
      });
}

/// محتوى طبقة واحدة: نص بخلفية اختيارية وظل للقراءة على الصور، أو ملصق إيموجي كبير.
class OverlayContent extends StatelessWidget {
  final PostOverlay overlay;
  final double canvasWidth;
  const OverlayContent({super.key, required this.overlay, required this.canvasWidth});

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final base = canvasWidth * (o.isSticker ? 0.12 : 0.065);
    final size = base * o.scale;
    if (o.isSticker) return Text(o.text, style: TextStyle(fontSize: size, height: 1.1), textAlign: TextAlign.center);
    final color = colorFromHex(o.color);
    final bg = o.bg == null ? null : colorFromHex(o.bg);
    final style = TextStyle(
      color: color, fontSize: size, height: 1.25,
      fontWeight: o.font == 'plain' ? FontWeight.w600 : FontWeight.w800,
      fontStyle: o.font == 'hand' ? FontStyle.italic : FontStyle.normal,
      fontFamily: o.font == 'serif' ? 'serif' : null,
      shadows: bg == null ? [const Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))] : null,
    );
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
