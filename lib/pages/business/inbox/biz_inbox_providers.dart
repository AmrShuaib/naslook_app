import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_inbox_api.dart';
import '../../../state/app_state.dart';

/// «رسائل الدوائر» في قائمة محادثاتي (جهة العميل).
final myBizThreadsProvider = FutureProvider<({List<BizThread> threads, int unread})>((ref) => ref.watch(apiClientProvider).myBizThreads());

/// صندوق الدائرة من جهة الفريق بفلتر (open|mine|closed|all).
typedef BizInboxKey = ({String bizId, String filter});
final bizInboxProvider = FutureProvider.family<BizInboxPage, BizInboxKey>((ref, k) => ref.watch(apiClientProvider).bizInbox(k.bizId, filter: k.filter));

/// شارة تبويب «الرسائل» في لوحة الدائرة (0 لمن ليس في فريق الرسائل أو عند الخطأ).
final bizInboxUnreadProvider = FutureProvider.family<int, String>((ref, bizId) async {
  try {
    return await ref.watch(apiClientProvider).bizInboxUnread(bizId);
  } catch (_) {
    return 0;
  }
});

/// يحدّث القوائم والشارات بعد إرسال أو قراءة أو إسناد.
void invalidateBizInbox(WidgetRef ref, String bizId) {
  ref.invalidate(myBizThreadsProvider);
  ref.invalidate(bizInboxProvider);
  ref.invalidate(bizInboxUnreadProvider(bizId));
}
