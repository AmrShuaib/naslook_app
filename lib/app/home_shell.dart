import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const titles = [
    'الرئيسية',
    'الخرائط',
    'الدوائر',
    'ماي سبيس',
    'التنبيهات',
    'المحادثات',
  ];

  @override
  Widget build(BuildContext context) {
    final i = navigationShell.currentIndex;
    return Scaffold(
      appBar: AppBar(title: Text(titles[i])),
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: i,
        // الضغط على التبويب الحالي يعيده إلى مساره الأول
        onTap: (newIndex) => navigationShell.goBranch(
          newIndex,
          initialLocation: newIndex == i,
        ),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'الخرائط'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'الدوائر'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'ماي سبيس'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'التنبيهات',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'المحادثات'),
        ],
      ),
    );
  }
}
