import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/safety_api.dart';
import 'app_state.dart';

/// المحادثات المكتومة للمستخدم الحالي.
final mutesProvider = FutureProvider<List<ChatMute>>((ref) => ref.watch(apiClientProvider).mutes());

/// معرّفات الأطراف المكتومة (فارغة حتى تصل القائمة).
final mutedPeersProvider = Provider<Set<String>>((ref) => ref.watch(mutesProvider).maybeWhen(data: (l) => {for (final m in l) m.peerId}, orElse: () => const <String>{}));

/// الكلمات المحظورة للتحقق المسبق قبل إرسال رسالة (تُجلب مرة واحدة).
final bannedWordsProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await ref.watch(apiClientProvider).bannedWords();
  } catch (_) {
    return const [];
  }
});

/// المحظورون.
final blockedUsersProvider = FutureProvider<List<BlockedUser>>((ref) => ref.watch(apiClientProvider).blockedUsers());
