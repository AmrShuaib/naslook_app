import 'client.dart';
import 'models.dart';
import 'profile_v2_models.dart';

/// مسارات الملف الشخصي v2 (server/profile_ext.js): الملف بالمعرّف أو النك نيم، ملفي مع الإعدادات والاكتمال،
/// التعديل، التعريف الصوتي/المرئي، المتابعة، أحداث الملف، إحصاءات 7 أيام، وفحص اسم المستخدم.
extension ProfileV2Api on ApiClient {
  Future<ProfileV2> profileV2(String idOrHandle) async => ProfileV2.fromJson(await get('/profiles/${Uri.encodeComponent(idOrHandle)}/v2'));
  Future<ProfileV2> myProfileV2() async => ProfileV2.fromJson(await get('/me/profile/v2'));
  Future<ProfileV2> updateProfileV2(Map<String, dynamic> patch) async => ProfileV2.fromJson(await put('/me/profile/v2', patch));

  Future<ProfileIntro?> setIntro({required String kind, required String url, required int sec}) async =>
      ProfileIntro.fromJsonOrNull((await put('/me/profile/intro', {'kind': kind, 'url': url, 'sec': sec}))['intro']) ?? ProfileIntro(kind: kind, url: url, sec: sec, at: DateTime.now());
  Future<void> deleteIntro() => delete('/me/profile/intro');

  Future<FollowResult> follow(String id) async => FollowResult.fromJson(await post('/profiles/$id/follow', const {}));
  Future<FollowResult> unfollow(String id) async => FollowResult.fromJson(await delete('/profiles/$id/follow'));
  Future<List<Person>> followers(String id, {int limit = 50}) async => asList(await getList('/profiles/$id/followers', query: {'limit': '$limit'})).map(Person.fromJson).toList();
  Future<List<Person>> following(String id, {int limit = 50}) async => asList(await getList('/profiles/$id/following', query: {'limit': '$limit'})).map(Person.fromJson).toList();

  /// حدث على الملف (message | share | link): خلفي، لا يزعج الزائر ولا يفشل الواجهة.
  Future<void> profileEvent(String id, String kind) => post('/profiles/$id/event', {'kind': kind}, prompt: false).then((_) {}).catchError((_) {});

  Future<ProfileStats7> profileStats7() async => ProfileStats7.fromJson(await get('/me/profile/stats'));
  Future<HandleCheck> checkHandle(String nickname) async => HandleCheck.fromJson(await get('/handles/check', query: {'nickname': nickname.trim().toLowerCase()}));
}
