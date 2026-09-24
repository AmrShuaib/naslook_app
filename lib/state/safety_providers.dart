import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/naslife_api.dart';
import '../api/safety_api.dart';
import 'app_state.dart';

/// المحادثات المكتومة للمستخدم الحالي.
final mutesProvider = FutureProvider<List<ChatMute>>((ref) => ref.watch(apiClientProvider).mutes());

/// معرّفات الأطراف المكتومة (فارغة حتى تصل القائمة).
final mutedPeersProvider = Provider<Set<String>>((ref) => ref.watch(mutesProvider).maybeWhen(data: (l) => {for (final m in l) m.peerId}, orElse: () => const <String>{}));

/// الكلمات المحظورة للتحقق المسبق قبل الإرسال (رسالة، منشور دائرة، تعليق): قائمة الإدارة والقائمة الافتراضية معاً
/// ([BannedWords])، فيطابق التحقق في التطبيق ما يرفضه الخادم. تُجلب مرة لكل حساب.
final bannedWordsProvider = FutureProvider<List<String>>((ref) async {
  if (ref.watch(appStateProvider.select((s) => s.user?.id)) == null) return const [];
  try {
    return await ref.watch(apiClientProvider).bannedWords();
  } catch (_) {
    return const [];
  }
});

/// المحظورون للحساب الحالي. يراقب معرّف المستخدم فلا يرث حساب آخر (بعد الخروج والدخول في الجلسة نفسها) قائمة سابقه؛ فارغة للزائر.
final blockedUsersProvider = FutureProvider<List<BlockedUser>>((ref) async {
  final uid = ref.watch(appStateProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.watch(apiClientProvider).blockedUsers();
});

/// معرّفات المحظورين بأحرف كبيرة لتصفية محتواهم في القوائم احتياطاً (فارغة للزائر أو قبل وصول القائمة أو عند الخطأ).
final blockedIdsProvider = Provider<Set<String>>((ref) {
  if (ref.watch(appStateProvider.select((s) => s.user?.id)) == null) return const <String>{};
  return ref.watch(blockedUsersProvider).maybeWhen(data: (l) => {for (final u in l) u.id.toUpperCase()}, orElse: () => const <String>{});
});

/// هل [id] محظور (مقارنة بلا حساسية لحالة الأحرف).
bool isBlockedId(Set<String> blocked, String? id) => id != null && id.isNotEmpty && blocked.contains(id.toUpperCase());

/// تعليقات منشور دائرة المخفية بالبلاغات أو الإدارة.
final hiddenCommentsProvider = FutureProvider.family<Set<String>, String>((ref, postId) => ref.watch(apiClientProvider).hiddenComments(postId: postId));
