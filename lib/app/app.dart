import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'i18n/l10n.dart';
import '../core/app_theme.dart';
import '../core/nav_provider.dart';
import '../pages/home/home_page.dart';
import '../pages/map/map_page.dart';
import '../pages/circles/circles_page.dart';
import '../pages/myspace/myspace_page.dart';
import '../pages/notifications/notifications_page.dart';
import '../pages/chat/chat_page.dart'; // استيراد شاشة المحادثات

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Naslook App',
      theme: AppTheme.light,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const titles = [
    'الرئيسية',
    'الخرائط',
    'الدوائر',
    'ماي سبيس',
    'التنبيهات',
    'المحادثات', // إضافة عنوان المحادثات
  ];

  static const screens = [
    HomePage(),
    MapPage(),
    CirclesPage(),
    MySpacePage(),
    NotificationsPage(),
    ChatPage(userName: 'مستخدم تجريبي', userImage: ''), // إضافة شاشة المحادثات
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = ref.watch(navIndexProvider);
    return Scaffold(
      appBar: AppBar(title: Text(titles[i])),
      body: screens[i],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: i,
        onTap: (newIndex) =>
            ref.read(navIndexProvider.notifier).state = newIndex,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'المحادثات', // إضافة عنصر المحادثات
          ),
        ],
      ),
    );
  }
}
