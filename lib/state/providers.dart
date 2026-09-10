import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../api/naslife_api.dart';
import '../api/ws.dart';
import 'app_state.dart';

/// اتصال WebSocket واحد طوال الجلسة، يُعاد إنشاؤه عند تغيّر الرمز.
final socketProvider = Provider<NaslifeSocket?>((ref) {
  final token = ref.watch(appStateProvider.select((s) => s.session?.token));
  if (token == null) return null;
  final api = ref.watch(apiClientProvider);
  final s = NaslifeSocket(url: api.wsUrl, token: token)..connect();
  ref.onDispose(s.close);
  return s;
});

final profileProvider = FutureProvider<Profile>((ref) => ref.watch(apiClientProvider).myProfile());
final contactsProvider = FutureProvider<List<Person>>((ref) => ref.watch(apiClientProvider).contacts());
final requestsProvider = FutureProvider<List<FriendRequest>>((ref) => ref.watch(apiClientProvider).requests());
final chatsProvider = FutureProvider<List<Chat>>((ref) => ref.watch(apiClientProvider).chats());
final myVesselsProvider = FutureProvider<List<Vessel>>((ref) => ref.watch(apiClientProvider).myVessels());
final discoverVesselsProvider = FutureProvider.family<List<Vessel>, String>((ref, q) => ref.watch(apiClientProvider).vessels(q: q));
final feedProvider = FutureProvider<List<Post>>((ref) => ref.watch(apiClientProvider).feed());
final myPresenceProvider = FutureProvider<MyPresence>((ref) => ref.watch(apiClientProvider).myPresence());

/// الحدود الجغرافية الحالية للخريطة (تبدأ بجدة).
final bboxProvider = StateProvider<BBox>((_) => BBox.jeddah);
final storiesProvider = FutureProvider<List<Story>>((ref) => ref.watch(apiClientProvider).stories(ref.watch(bboxProvider)));
final presenceProvider = FutureProvider<List<Presence>>((ref) => ref.watch(apiClientProvider).mapPresence(ref.watch(bboxProvider)));
final pinsProvider = FutureProvider<List<Pin>>((ref) => ref.watch(apiClientProvider).pins(ref.watch(bboxProvider)));
final businessesProvider = FutureProvider<List<Business>>((ref) => ref.watch(apiClientProvider).businesses(ref.watch(bboxProvider)));

/// عدد الرسائل غير المقروءة + الطلبات لشارة الجرس.
final unreadCountProvider = Provider<int>((ref) {
  final chats = ref.watch(chatsProvider).value ?? const [];
  final reqs = ref.watch(requestsProvider).value ?? const [];
  return chats.fold<int>(0, (n, c) => n + c.unread) + reqs.length;
});
