import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final navIndexProvider = StateProvider<int>((_) => 0);

/// قسم من شريط التنقّل السفلي.
class NavTabMeta {
  final String id, label;
  final IconData icon, selectedIcon;
  const NavTabMeta(this.id, this.label, this.icon, this.selectedIcon);
}

/// الأقسام الأربعة الثابتة (قرار المالك، نظام «الصف»): لا تخصيص للشريط؛ زر الكاميرا في الوسط.
const navTabs = <NavTabMeta>[
  NavTabMeta('home', 'الخريطة', Icons.map_outlined, Icons.map_rounded),
  NavTabMeta('circles', 'الدوائر', Icons.groups_outlined, Icons.groups_rounded),
  NavTabMeta('chats', 'المحادثات', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  NavTabMeta('me', 'ماي سبيس', Icons.person_outline_rounded, Icons.person_rounded),
];
const navTabIds = ['home', 'circles', 'chats', 'me'];

NavTabMeta? navTabMeta(String id) {
  for (final t in navTabs) {
    if (t.id == id) return t;
  }
  return null;
}

/// يفتح قسماً في الشريط السفلي بمعرّفه (لا شيء إن لم يكن من الأربعة).
void openNavTab(WidgetRef ref, String tab) {
  final i = navTabIds.indexOf(tab);
  if (i >= 0) ref.read(navIndexProvider.notifier).state = i;
}
