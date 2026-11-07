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

  /// صفحة من قائمة «متابِعون» ([followers] = true) أو «يتابع» لـ[id]، و[before] مؤشر الصفحة السابقة كما أعاده الخادم.
  /// الملف الخاص يرد 403 لغير صاحبه ومن أضافهم.
  Future<FollowPage> followPage(String id, {required bool followers, String? before, int limit = 30}) async =>
      FollowPage.fromJson(await get('/profiles/${Uri.encodeComponent(id)}/${followers ? 'followers' : 'following'}', query: {'limit': '$limit', if (before != null && before.isNotEmpty) 'before': before}));

  /// معرّفات «أتابعهم» (من أتابعهم ومن أضفتهم) لإدراج اللحظات الحيّة في قائمتها.
  Future<List<String>> followFeedIds() async {
    final raw = (await get('/me/following/ids'))['ids'];
    return [if (raw is List) for (final x in raw) if (x != null) x.toString()];
  }

  /// حدث على الملف (message | share | link): خلفي، لا يزعج الزائر ولا يفشل الواجهة.
  Future<void> profileEvent(String id, String kind) => post('/profiles/$id/event', {'kind': kind}, prompt: false).then((_) {}).catchError((_) {});

  /// فحص «من يراسلني» قبل أول رسالة إلى [peerId]. يعيد null (= مسموح كما كان) حين يغيب المسار عن خادم قديم (404)
  /// أو يتعذّر الفحص: القفل الخاطئ أسوأ من رسالة تصل، والنواة لا تفحص السياسة على أي حال.
  Future<MessageGate?> canMessage(String peerId) async {
    try {
      return MessageGate.fromJson(await get('/profiles/${Uri.encodeComponent(peerId)}/can-message'));
    } catch (_) {
      return null;
    }
  }

  Future<ProfileStats7> profileStats7() async => ProfileStats7.fromJson(await get('/me/profile/stats'));
  Future<HandleCheck> checkHandle(String nickname) async => HandleCheck.fromJson(await get('/handles/check', query: {'nickname': nickname.trim().toLowerCase()}));
}
