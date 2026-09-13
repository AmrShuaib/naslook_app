import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/community_api.dart';
import 'app_state.dart';

/// الصفحة الأولى من مساحة مجتمع دائرة (بموضوع اختياري). الصفحات الأقدم تُجلب من الصفحة نفسها بـ before.
final communityFeedProvider = FutureProvider.family<CommunityFeed, ({String bizId, String? topic})>((ref, a) => ref.watch(apiClientProvider).communityFeed(a.bizId, topic: a.topic));

/// منشور مع ردوده.
final communityThreadProvider = FutureProvider.family<CommunityThread, ({String bizId, String postId})>((ref, a) => ref.watch(apiClientProvider).communityThread(a.bizId, a.postId));

/// يعيد تحميل كل ما يخص مساحة الدائرة (كل المواضيع) بعد تغيير.
void invalidateCommunity(Ref ref, String bizId) {
  ref.invalidate(communityFeedProvider);
  ref.invalidate(communityThreadProvider);
}
