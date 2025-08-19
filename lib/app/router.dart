import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/map/map_screen.dart';
import '../features/myspace/myspace_screen.dart';
import '../features/circles/circles_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../pages/chat/chat_page.dart';

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
    GoRoute(
      path: '/myspace',
      builder: (context, state) => const MySpaceScreen(),
    ),
    GoRoute(
      path: '/circles',
      builder: (context, state) => const CirclesScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) {
        final extra = state.extra as Map<String, String>?;
        final userName = extra?['userName'] ?? 'مستخدم مجهول';
        final userImage = extra?['userImage'] ?? '';
        return ChatPage(userName: userName, userImage: userImage);
      },
    ),
  ],
);
