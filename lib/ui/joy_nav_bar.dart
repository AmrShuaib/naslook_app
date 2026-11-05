import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/nav_provider.dart';

/// شريط تنقّل عائم (كبسولة) بالأقسام الستة الثابتة وزر كاميرا مرتفع في الوسط:
/// الخريطة، الدوائر، السوق | الكاميرا | الفعاليات، المحادثات، ماي سبيس.
/// سبعة مواضع على جوال 360 بكسل: عرض كل قسم بقدر اسمه، والنصفان متساويان فتبقى الكاميرا في المنتصف تماماً،
/// وإن ضاق نصف عن أسمائه صغُر خط الأسماء كلها بنسبة واحدة فتبقى كاملة ومتّسقة بلا قصّ.
class JoyNavBar extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCompose;
  /// شارات بعدد غير المقروء لكل قسم (مثل المحادثات).
  final Map<String, int> badges;
  const JoyNavBar({super.key, required this.tabs, required this.index, required this.onSelect, required this.onCompose, this.badges = const {}});

  static const height = 62.0;
  static const margin = 12.0;
  /// موضع الكاميرا في الكبسولة (الزر 56 يرتفع فوقها).
  static const composeWidth = 58.0;
  /// حجم خط الأسماء قبل التصغير؛ يُصغَّر حين لا يتسع النصف لأسمائه.
  static const labelSize = 10.5;
  /// أقل فراغ حول كل اسم، وحشوة طرفي الكبسولة حتى لا يلامس اسم الطرف انحناءها.
  static const _gap = 3.0, _endPad = 5.0;

  /// هامش الكبسولة الجانبي: أضيق على الجوالات الصغيرة (أقل من 380) ليتسع للأقسام الستة.
  static double sideMargin(double width) => width < 380 ? 8 : margin;

  /// المسافة التي تحجزها الكبسولة أسفل الصفحات حتى لا يختفي محتواها خلفها. نقرأ viewPadding لا padding لأن Scaffold
  /// مع extendBody يضيف ارتفاع الشريط إلى padding الجسم، فكان الصف يرتفع فوق الكبسولة بفراغ يظهر فيه نص الخريطة.
  static double inset(BuildContext context) => height + margin + MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final half = (tabs.length / 2).ceil();
    return LayoutBuilder(builder: (context, outer) {
      final side = sideMargin(outer.maxWidth);
      return Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side, margin + MediaQuery.paddingOf(context).bottom),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: _endPad),
          decoration: BoxDecoration(
            color: Joy.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Joy.line),
            boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          clipBehavior: Clip.none,
          child: LayoutBuilder(builder: (context, c) {
            final l = _layout(context, c.maxWidth, half);
            return Row(children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i == half) _ComposeButton(onTap: onCompose),
                SizedBox(
                  width: l.widths[i],
                  child: _Item(meta: navTabMeta(tabs[i]), selected: i == index, badge: badges[tabs[i]] ?? 0, fontSize: labelSize * l.scale, onTap: () => onSelect(i)),
                ),
              ],
            ]);
          }),
        ),
      );
    });
  }

  /// يقيس الأسماء بالخط الحالي ومعامل تكبير النص (بالوزن العريض حتى لا يتغير التوزيع عند الاختيار)، ثم يقسم كل نصف
  /// على أقسامه بقدر أسمائها. معامل التصغير واحد للجميع: أصغر ما يلزم ليتسع النصف الأضيق.
  ({List<double> widths, double scale}) _layout(BuildContext context, double inner, int half) {
    final style = DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: labelSize, fontWeight: FontWeight.w700));
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    double measure(String s) {
      final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: dir, textScaler: scaler, maxLines: 1)..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final natural = [for (final id in tabs) measure(navTabMeta(id)?.label ?? '')];
    final halves = [[for (var i = 0; i < half; i++) i], [for (var i = half; i < tabs.length; i++) i]];
    final each = math.max(0.0, (inner - composeWidth) / 2);
    var scale = 1.0;
    for (final g in halves) {
      final sum = g.fold<double>(0, (s, i) => s + natural[i]);
      if (sum > 0) scale = math.min(scale, (each - _gap * g.length) / sum);
    }
    scale = scale.clamp(0.5, 1.0);
    final widths = List<double>.filled(tabs.length, 0);
    for (final g in halves) {
      if (g.isEmpty) continue;
      final extra = (each - g.fold<double>(0, (s, i) => s + natural[i] * scale)) / g.length;
      for (final i in g) {
        widths[i] = math.max(0, natural[i] * scale + extra);
      }
    }
    return (widths: widths, scale: scale);
  }
}

class _Item extends StatelessWidget {
  final NavTabMeta? meta;
  final bool selected;
  final int badge;
  final double fontSize;
  final VoidCallback onTap;
  const _Item({required this.meta, required this.selected, required this.badge, required this.fontSize, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = selected ? Joy.primary : Joy.textMuted;
    return InkWell(
      key: Key('nav-${meta?.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Badge(isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: Joy.accent, child: Icon(selected ? (meta?.selectedIcon ?? Icons.circle) : (meta?.icon ?? Icons.circle_outlined), color: color, size: 23)),
        const SizedBox(height: 2),
        // التصغير الاحتياطي يبقي الاسم كاملاً إن اختلف القياس قليلاً عن الرسم (الخط لم يُحمَّل بعد مثلاً)
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(meta?.label ?? '', maxLines: 1, softWrap: false, style: TextStyle(fontSize: fontSize, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: JoyNavBar.composeWidth,
        child: OverflowBox(
          maxHeight: 84,
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: Material(
              color: Joy.primary,
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: Joy.primary.withValues(alpha: .5),
              child: InkWell(
                key: const Key('nav-compose'),
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(width: 56, height: 56, child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: 26)),
              ),
            ),
          ),
        ),
      );
}
