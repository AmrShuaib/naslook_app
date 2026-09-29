import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/commerce_api.dart';
import '../api/commerce_models.dart';
import '../api/models.dart';
import '../api/posts_api.dart';
import '../api/profile_v2_api.dart';
import '../api/profile_v2_models.dart';
import 'app_state.dart';
import 'providers.dart';

/// null حين لا يعرف الخادم المسار بعد (404) أو حين لا يعود بملف (بلا معرّف): الشاشات تكتفي حينها بملف النواة.
Future<ProfileV2?> _tolerant(Future<ProfileV2> Function() f) async {
  try {
    final p = await f();
    return p.id.isEmpty ? null : p;
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
}

/// ملف مستخدم بالمعرّف أو النك نيم كما يراه الزائر.
final profileV2Provider = FutureProvider.family<ProfileV2?, String>((ref, id) => _tolerant(() => ref.watch(apiClientProvider).profileV2(id)));

/// ملفي مع الإعدادات واكتمال الملف؛ للزائر null بلا طلب.
final myProfileV2Provider = FutureProvider<ProfileV2?>((ref) async => ref.watch(signedInProvider) ? _tolerant(() => ref.watch(apiClientProvider).myProfileV2()) : null);

/// إحصاءات آخر 7 أيام لصاحب الحساب؛ null إن تعذّرت.
final profileStats7Provider = FutureProvider<ProfileStats7?>((ref) async {
  if (!ref.watch(signedInProvider)) return null;
  try {
    return await ref.watch(apiClientProvider).profileStats7();
  } catch (_) {
    return null;
  }
});

final followersProvider = FutureProvider.family<List<Person>, String>((ref, id) => ref.watch(apiClientProvider).followers(id));
final followingProvider = FutureProvider.family<List<Person>, String>((ref, id) => ref.watch(apiClientProvider).following(id));

/// منشورات المستخدم النشطة على الخريطة (تبويب «المنشورات» في ملفه) عبر مرشّح الناشرين في البث.
final userPostsProvider = FutureProvider.family<List<MapPost>, String>((ref, id) async => (await ref.watch(apiClientProvider).postsFeed(authors: [id], limit: 30, radiusKm: 500)).items);

/// عروض البائع في السوق (تبويب «السوق» في ملفه).
final sellerListingsProvider = FutureProvider.family<List<Listing>, String>((ref, id) => ref.watch(apiClientProvider).market(seller: id, limit: 30));
