import 'package:go_router/go_router.dart';
import 'home_shell.dart';
import '../pages/home/home_page.dart';
import '../pages/map/map_page.dart';
import '../pages/circles/circles_page.dart';
import '../pages/myspace/myspace_page.dart';
import '../pages/notifications/notifications_page.dart';
import '../pages/chat/chat_page.dart';
import '../pages/login/login_page.dart';

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    // كل تبويب فرع مستقل يحتفظ بحالته عند التنقل بين التبويبات
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/map', builder: (context, state) => const MapPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/circles',
              builder: (context, state) => const CirclesPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/myspace',
              builder: (context, state) => const MySpacePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/notifications',
              builder: (context, state) => const NotificationsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) {
                final extra = state.extra as Map<String, String>?;
                final userName = extra?['userName'] ?? 'مستخدم تجريبي';
                final userImage = extra?['userImage'] ?? '';
                return ChatPage(userName: userName, userImage: userImage);
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
  ],
);
