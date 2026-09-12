import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/l10n.dart';
import '../core/app_theme.dart';
import '../core/nav_provider.dart';
import '../core/push/push_service.dart';
import '../state/app_state.dart';
import '../state/providers.dart';
import '../screens/login_page.dart';
import '../pages/home/home_page.dart';
import '../pages/map/map_page.dart';
import '../pages/circles/circles_page.dart';
import '../pages/myspace/myspace_page.dart';
import '../pages/notifications/notifications_page.dart';
import '../pages/chat/chats_page.dart';

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
      // تكبير كل النصوص درجة واحدة (10%) فوق إعداد حجم الخط في نظام المستخدم
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * 1.1)),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const LoginPage();
      case AuthStatus.signedIn:
        return const HomeShell();
    }
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const titles = ['الرئيسية', 'الخرائط', 'الدوائر', 'المحادثات', 'ماي سبيس'];
  static const screens = [HomePage(), MapPage(), CirclesPage(), ChatsPage(), MySpacePage()];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _recoveryShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowRecovery());
    // يفتح اتصال WebSocket مبكراً، ويجدّد اشتراك الإشعارات الفورية إن كان الإذن ممنوحاً
    Future.microtask(() {
      ref.read(socketProvider);
      PushService.resubscribeIfGranted(ref.read(apiClientProvider));
    });
  }

  Future<void> _maybeShowRecovery() async {
    final phrase = ref.read(appStateProvider).session?.recoveryPhrase;
    if (phrase == null || _recoveryShown || !mounted) return;
    _recoveryShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('احفظ عبارة الاسترداد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هذه هي الطريقة الوحيدة لاستعادة حسابك إن نسيت الرقم السري. لن تُعرض مرة أخرى.'),
            const SizedBox(height: 12),
            SelectableText(phrase, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phrase));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ عبارة الاسترداد')));
            },
            child: const Text('نسخ'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('حفظتها')),
        ],
      ),
    );
    ref.read(appStateProvider.notifier).dismissRecoveryPhrase();
  }

  @override
  Widget build(BuildContext context) {
    final i = ref.watch(navIndexProvider);
    final badge = ref.watch(unreadCountProvider);
    return Scaffold(
      appBar: i == 1
          ? null
          : AppBar(
              title: Text(HomeShell.titles[i]),
              actions: [
                IconButton(
                  tooltip: 'التنبيهات',
                  icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: Joy.accent, child: const Icon(Icons.notifications_outlined)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsPage())),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: IndexedStack(index: i, children: HomeShell.screens),
      bottomNavigationBar: Container(
        // شريط سفلي أبيض بخط فاصل رفيع وأيقونات ملوّنة عند التحديد (بلا مؤشر خلفي)
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        child: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (x) => ref.read(navIndexProvider.notifier).state = x,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
            const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'الخرائط'),
            const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'الدوائر'),
            NavigationDestination(
              icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: Joy.accent, child: const Icon(Icons.chat_bubble_outline_rounded)),
              selectedIcon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: Joy.accent, child: const Icon(Icons.chat_bubble_rounded)),
              label: 'المحادثات',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'ماي سبيس'),
          ],
        ),
      ),
    );
  }
}
