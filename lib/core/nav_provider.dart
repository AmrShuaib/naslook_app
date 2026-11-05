import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// موضع القسم الحالي في [navTabIds]. لا تُكتب أرقام ثابتة: استعمل [openNavTab] بالمعرّف.
final navIndexProvider = StateProvider<int>((_) => 0);

/// قسم من شريط التنقّل السفلي.
class NavTabMeta {
  final String id, label;
  final IconData icon, selectedIcon;
  const NavTabMeta(this.id, this.label, this.icon, this.selectedIcon);
}

/// الأقسام الستة الثابتة (قرار المالك): لا تخصيص للشريط؛ زر الكاميرا في الوسط بعد السوق.
/// السوق ظاهر في iOS أيضاً (سلع مادية وخدمات مسموحة؛ سبوت لايت وحده يُخفى داخل الصفحة).
const navTabs = <NavTabMeta>[
  NavTabMeta('home', 'الخريطة', Icons.map_outlined, Icons.map_rounded),
  NavTabMeta('circles', 'الدوائر', Icons.groups_outlined, Icons.groups_rounded),
  NavTabMeta('market', 'السوق', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
  NavTabMeta('events', 'الفعاليات', Icons.event_outlined, Icons.event_rounded),
  NavTabMeta('chats', 'المحادثات', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  NavTabMeta('me', 'ماي سبيس', Icons.person_outline_rounded, Icons.person_rounded),
];
const navTabIds = ['home', 'circles', 'market', 'events', 'chats', 'me'];

NavTabMeta? navTabMeta(String id) {
  for (final t in navTabs) {
    if (t.id == id) return t;
  }
  return null;
}

/// يفتح قسماً في الشريط السفلي بمعرّفه؛ يعيد false إن لم يكن من أقسام الشريط.
/// يخص HomeShell وحدها: واجهة الزائر (GuestShell) تبويباتها منفصلة ولا تستمع لـ [navIndexProvider].
bool openNavTab(WidgetRef ref, String tab) {
  final i = navTabIds.indexOf(tab);
  if (i < 0) return false;
  ref.read(navIndexProvider.notifier).state = i;
  return true;
}
