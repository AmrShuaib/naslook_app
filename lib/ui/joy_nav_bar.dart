import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/nav_provider.dart';

/// شريط تنقّل عائم (كبسولة) بأربعة أقسام ثابتة (الخريطة، الدوائر، المحادثات، ماي سبيس) وزر كاميرا مرتفع في الوسط.
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
  /// المسافة التي تحجزها الكبسولة أسفل الصفحات حتى لا يختفي محتواها خلفها.
  static double inset(BuildContext context) => height + margin + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final half = (tabs.length / 2).ceil();
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, margin + MediaQuery.paddingOf(context).bottom),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Joy.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Joy.line),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        clipBehavior: Clip.none,
        child: Row(children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i == half) _ComposeButton(onTap: onCompose),
            Expanded(child: _Item(meta: navTabMeta(tabs[i]), selected: i == index, badge: badges[tabs[i]] ?? 0, onTap: () => onSelect(i))),
          ],
        ]),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final NavTabMeta? meta;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  const _Item({required this.meta, required this.selected, required this.badge, required this.onTap});
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
        Text(meta?.label ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 68,
        child: OverflowBox(
          maxHeight: 84,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 0),
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
        ),
      );
}
