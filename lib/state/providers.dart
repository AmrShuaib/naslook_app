import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../api/naslife_api.dart';
import '../api/ws.dart';
import 'app_state.dart';
import 'safety_providers.dart';

/// اتصال WebSocket واحد طوال الجلسة، يُعاد إنشاؤه عند تغيّر الرمز.
final socketProvider = Provider<NaslifeSocket?>((ref) {
  final token = ref.watch(appStateProvider.select((s) => s.session?.token));
  if (token == null) return null;
  final api = ref.watch(apiClientProvider);
  final s = NaslifeSocket(url: api.wsUrl, token: token)..connect();
  ref.onDispose(s.close);
  return s;
});

/// هل توجد جلسة؟ مزوّدات النواة (القصص، الحضور، الدبابيس، المحادثات…) خاصة بالحسابات: للزائر تعيد قيماً فارغة
/// بدل طلبها، فلا تُكشف مواقع الناس ولا تُملأ السجلات برفض 401.
final signedInProvider = Provider<bool>((ref) => ref.watch(appStateProvider.select((s) => s.isSignedIn)));

final profileProvider = FutureProvider<Profile>((ref) => ref.watch(apiClientProvider).myProfile());
final contactsProvider = FutureProvider<List<Person>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).contacts() : const <Person>[]);
final requestsProvider = FutureProvider<List<FriendRequest>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).requests() : const <FriendRequest>[]);
final chatsProvider = FutureProvider<List<Chat>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).chats() : const <Chat>[]);
final myVesselsProvider = FutureProvider<List<Vessel>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).myVessels() : const <Vessel>[]);
final discoverVesselsProvider = FutureProvider.family<List<Vessel>, String>((ref, q) => ref.watch(apiClientProvider).vessels(q: q));
/// المنشورات المخفية بقرار مشرفي الدوائر أو البلاغات؛ تُصفّى من البث وصفحات الدوائر.
final hiddenPostsProvider = FutureProvider<Set<String>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).hiddenPosts() : const <String>{});
final feedProvider = FutureProvider<List<Post>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  final api = ref.watch(apiClientProvider);
  final hidden = await ref.watch(hiddenPostsProvider.future);
  final posts = await api.feed();
  return hidden.isEmpty ? posts : posts.where((p) => !hidden.contains(p.id)).toList();
});
final myPresenceProvider = FutureProvider<MyPresence>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).myPresence() : const MyPresence());

/// الحدود الجغرافية الحالية للخريطة (تبدأ بجدة).
final bboxProvider = StateProvider<BBox>((_) => BBox.jeddah);
final storiesProvider = FutureProvider<List<Story>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).stories(ref.watch(bboxProvider)) : const <Story>[]);
final presenceProvider = FutureProvider<List<Presence>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).mapPresence(ref.watch(bboxProvider)) : const <Presence>[]);
final pinsProvider = FutureProvider<List<Pin>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).pins(ref.watch(bboxProvider)) : const <Pin>[]);
final businessesProvider = FutureProvider<List<Business>>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).businesses(ref.watch(bboxProvider)) : const <Business>[]);

/// عدد الرسائل غير المقروءة + الطلبات لشارة الجرس.
final unreadCountProvider = Provider<int>((ref) {
  if (!ref.watch(signedInProvider)) return 0;
  final chats = ref.watch(chatsProvider).value ?? const [];
  final reqs = ref.watch(requestsProvider).value ?? const [];
  final muted = ref.watch(mutedPeersProvider);
  // المحادثات المكتومة لا تُحسب في الشارة
  return chats.fold<int>(0, (n, c) => n + (muted.contains(c.peer.id) ? 0 : c.unread)) + reqs.length;
});
