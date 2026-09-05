import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'i18n/l10n.dart';
import '../core/app_theme.dart';
import '../core/nav_provider.dart';
import '../state/app_state.dart';
import '../screens/login_page.dart';
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
      title: 'Naslife',
      theme: AppTheme.light,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('ar'),
      home: const AuthGate(),
    );
  }
}

/// يعرض شاشة الدخول أو الواجهة الرئيسية حسب حالة الجلسة.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(appStateProvider.select((s) => s.status));
    switch (status) {
      case AuthStatus.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.signedOut:
        return const LoginPage();
      case AuthStatus.signedIn:
        return const HomeShell();
    }
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
    final user = ref.watch(appStateProvider.select((s) => s.user));
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[i]),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: Text(user.nickname)),
            ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(appStateProvider.notifier).logout(),
          ),
        ],
      ),
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
