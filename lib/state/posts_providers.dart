import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/posts_api.dart';
import 'app_state.dart';
import 'providers.dart';

/// منشورات الخريطة ضمن الحدود المرئية.
final mapPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(bbox: ref.watch(bboxProvider)));
/// أحدث المنشورات للشريط في الرئيسية.
final recentPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).posts(limit: 30));
final myPostsProvider = FutureProvider<List<MapPost>>((ref) => ref.watch(apiClientProvider).myPosts());

void invalidatePosts(WidgetRef ref) {
  ref.invalidate(mapPostsProvider);
  ref.invalidate(recentPostsProvider);
  ref.invalidate(myPostsProvider);
}
