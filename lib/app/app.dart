import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/admin/admin_shell.dart';
import '../state/admin_providers.dart';
import 'i18n/l10n.dart';
import '../core/app_theme.dart';
import '../core/nav_provider.dart';
import '../core/notify/message_sound.dart';
import '../api/notify_api.dart';
import '../core/notify_open.dart';
import '../core/share/share_links.dart';
import '../pages/business/business_page.dart';
import '../pages/profile/public_profile_page.dart';
import '../api/client.dart';
import '../core/push/push_service.dart';
import '../state/app_state.dart';
import '../state/notify_providers.dart';
import '../state/providers.dart';
import '../screens/login_page.dart';
import '../pages/home/home_page.dart';
import '../pages/map/map_page.dart';
import '../pages/circles/circles_page.dart';
import '../pages/myspace/myspace_page.dart';
import '../pages/myspace/consent_sheet.dart';
import '../api/account_api.dart';
import '../pages/notifications/notifications_page.dart';
import '../pages/search/search_page.dart';
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
      // تكبير كل النصوص درجتين ونصف (25%) فوق إعداد حجم الخط في نظام المستخدم
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          // سقف للتكبير: على iOS يضاعف حجم الخط في النظام (Dynamic Type) فيتجاوز 3 أضعاف ويكسر الواجهة
          data: mq.copyWith(textScaler: TextScaler.linear((mq.textScaler.scale(1.0) * 1.25).clamp(1.0, 1.6))),
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
        // رابط عام (دائرة أو حساب) بلا جلسة: نعرض الوجهة كزائر مع شريط للدخول، إلا إن طلب الزائر الدخول
        if (pendingLink != null && !ref.watch(guestWantsLoginProvider)) return GuestShell(link: pendingLink!);
        return const LoginPage();
      case AuthStatus.signedIn:
        return ref.watch(adminModeProvider) ? const AdminShell() : const HomeShell();
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
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  late final MessageBell _bell = MessageBell(ref.read);
  // iOS يعلّق المقبس في الخلفية؛ عند العودة نعيد الاتصال فوراً بدل انتظار مهلة إعادة المحاولة
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: () => ref.read(socketProvider)?.reconnectNow(force: true));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowRecovery());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingNotification());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLink());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskConsent());
    // جرس الرسائل: يُفتح سياق الصوت عند أول لمسة، ويُقرع عند وصول رسالة عبر الاتصال المباشر
    MessageSound.prepare();
    _life; // يُنشأ المستمع مع الشاشة
    // يفتح اتصال WebSocket مبكراً، ويجدّد اشتراك الإشعارات الفورية إن كان الإذن ممنوحاً
    Future.microtask(() {
      if (!mounted) return;
      _socketSub = ref.read(socketProvider)?.events.listen(_bell.handle);
      PushService.resubscribeIfGranted(ref.read(apiClientProvider));
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _life.dispose();
    super.dispose();
  }

  /// من سجّل قبل إضافة الشروط أو بعد تحديثها يوافق مرة واحدة؛ فشل الطلب لا يحبس المستخدم (يُعاد في الإقلاع التالي).
  Future<void> _maybeAskConsent() async {
    String? version;
    try {
      version = await ref.read(apiClientProvider).pendingConsent();
    } catch (_) {
      return;
    }
    if (version == null || !mounted) return;
    final ok = await ConsentSheet.show(context);
    if (!mounted) return;
    if (ok == true) {
      try { await ref.read(apiClientProvider).acceptConsent(version); } catch (_) {}
    } else if (ok == false) {
      await ref.read(appStateProvider.notifier).logout();
    }
  }

  /// رابط عام (`/c/<دائرة>` أو `/u/<نك نيم>`) وصل عند الإقلاع: نفتح وجهته بعد الدخول.
  void _openPendingLink() {
    final l = pendingLink;
    if (l == null || !mounted) return;
    pendingLink = null;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pendingLinkPage(l)));
  }

  /// إشعار دفع نُقر عليه والتطبيق مغلق: وصل الرابط `#/n/<id>` عند الإقلاع، نفتح وجهته بعد الدخول.
  Future<void> _openPendingNotification() async {
    final id = pendingNotificationId;
    if (id == null) return;
    pendingNotificationId = null;
    try {
      final n = await ref.read(apiClientProvider).notification(id);
      if (!mounted) return;
      await openNotification(context, ref, n);
    } catch (_) {
      // إشعار محذوف أو لمستخدم آخر: نتجاهله
    }
  }

  /// بعد التسجيل: إن أرسل الخادم بيانات الاسترداد إلى البريد نكتفي بسطر إخبار، وإلا (تسجيل بلا بريد أو البريد معطّل)
  /// نعرض عبارة الاسترداد مرة واحدة ليحفظها المستخدم.
  Future<void> _maybeShowRecovery() async {
    final session = ref.read(appStateProvider).session;
    final phrase = session?.recoveryPhrase;
    if (phrase == null || _recoveryShown || !mounted) return;
    _recoveryShown = true;
    final me = session!.user;
    // بطاقة الحساب: من أنت الآن بوضوح (الاسم والمعرّف) حتى لا يلتبس الحساب الجديد بحساب آخر على الجهاز نفسه
    final who = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.verified_user_rounded, color: Joy.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(me.nickname, key: const Key('welcome-nick'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Joy.primary)),
          Text('المعرّف ${me.id}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ])),
      ]),
    );
    if (session.recoverySent) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          key: const Key('welcome-dialog'),
          title: const Text('تم إنشاء حسابك'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            who,
            const SizedBox(height: 12),
            Text('أرسلنا رمز تأكيد البريد وبيانات حسابك وعبارة الاسترداد إلى ${session.email ?? 'بريدك'}. أكّد بريدك من ماي سبيس متى شئت.', style: const TextStyle(height: 1.6)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ابدأ'))],
        ),
      );
      ref.read(appStateProvider.notifier).dismissRecoveryPhrase();
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('احفظ عبارة الاسترداد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            who,
            const SizedBox(height: 12),
            const Text('نسخة احتياطية لاستعادة حسابك إن نسيت كلمة السر ولم تصلك رسائل البريد. لن تُعرض مرة أخرى.'),
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
    // جرس التنبيهات يجمع الرسائل غير المقروءة وإشعارات التجارة والإدارة
    final bell = badge + (ref.watch(notifyUnreadProvider).valueOrNull ?? 0);
    return Scaffold(
      appBar: i == 1
          ? null
          : AppBar(
              title: Text(HomeShell.titles[i]),
              actions: [
                IconButton(tooltip: 'بحث', icon: const Icon(Icons.search_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()))),
                IconButton(
                  tooltip: 'التنبيهات',
                  icon: Badge(isLabelVisible: bell > 0, label: Text('$bell'), backgroundColor: Joy.accent, child: const Icon(Icons.notifications_outlined)),
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


/// وجهة رابط عام: صفحة الدائرة أو الملف العام بالنك نيم.
Widget pendingLinkPage(PendingLink l) => l.isCircle ? BusinessPage(id: l.value) : PublicProfilePage(handle: l.value);

/// الزائر ضغط «سجّل الدخول» من شريط الزائر.
final guestWantsLoginProvider = StateProvider<bool>((ref) => false);

/// تصفّح كزائر: الوجهة المشتركة مع شريط سفلي للدخول، وأي فعل يتطلب حساباً (401) يعرض دعوة للدخول.
class GuestShell extends ConsumerStatefulWidget {
  final PendingLink link;
  const GuestShell({super.key, required this.link});
  @override
  ConsumerState<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends ConsumerState<GuestShell> {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    ApiClient.onUnauthorized = _promptSignIn;
  }

  @override
  void dispose() {
    if (ApiClient.onUnauthorized == _promptSignIn) ApiClient.onUnauthorized = null;
    super.dispose();
  }

  void _login() => ref.read(guestWantsLoginProvider.notifier).state = true;

  void _promptSignIn() {
    if (_prompting || !mounted) return;
    _prompting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('هذا يحتاج حساباً', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('سجّل الدخول أو أنشئ حساباً في ثوانٍ لتشارك وتطلب وتتابع.', style: TextStyle(color: Joy.textMuted, height: 1.5)),
            const SizedBox(height: 14),
            FilledButton(key: const Key('guest-login-sheet'), onPressed: () { Navigator.pop(ctx); _login(); }, child: const Text('سجّل الدخول')),
          ]),
        ),
      );
      _prompting = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        body: Column(children: [
          Expanded(child: pendingLinkPage(widget.link)),
          Material(
            color: Joy.surface,
            child: SafeArea(
              top: false,
              child: Container(
                key: const Key('guest-bar'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Joy.line))),
                child: Row(children: [
                  const Icon(Icons.visibility_outlined, size: 18, color: Joy.textMuted),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('تتصفح كزائر · للمشاركة والطلب سجّل الدخول', style: TextStyle(fontSize: 13, color: Joy.textMuted, fontWeight: FontWeight.w600), maxLines: 2)),
                  FilledButton(key: const Key('guest-login'), onPressed: _login, style: FilledButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), child: const Text('سجّل الدخول')),
                ]),
              ),
            ),
          ),
        ]),
      );
}
