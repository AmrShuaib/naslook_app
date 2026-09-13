import 'client.dart';
import 'models.dart';

/// محادثة مكتومة (server/safety.js): بلا شارة ولا تنبيه حتى [until] (null = دائماً).
class ChatMute {
  final String peerId;
  final DateTime? until;
  const ChatMute({required this.peerId, this.until});
  factory ChatMute.fromJson(Map m) => ChatMute(peerId: m['peerId'].toString().toUpperCase(), until: m['until'] == null ? null : DateTime.tryParse(m['until'].toString()));
}

/// مستخدم محظور من جدول الحظر في النواة (شكل الاستجابة يُقرأ بمرونة).
class BlockedUser {
  final String id, nickname;
  final String? avatarUrl;
  const BlockedUser({required this.id, required this.nickname, this.avatarUrl});
  static BlockedUser? fromJson(Map m) {
    final nested = (m['blocked'] ?? m['user'] ?? m['peer']);
    final src = nested is Map ? nested : m;
    final id = (src['blockedId'] ?? src['blocked_id'] ?? src['userId'] ?? src['user_id'] ?? src['id'] ?? m['blockedId'] ?? m['blocked_id'])?.toString();
    if (id == null || id.isEmpty) return null;
    final nick = (src['nickname'] ?? src['name'] ?? src['handle'] ?? m['nickname'] ?? m['blockedNickname'] ?? id).toString();
    final avatar = (src['avatarUrl'] ?? src['avatar_url'] ?? m['avatarUrl'])?.toString();
    return BlockedUser(id: id, nickname: nick, avatarUrl: avatar);
  }
}

/// تطبيع عربي مطابق لما على الخادم (normQ): حروف صغيرة، توحيد الهمزات والتاء المربوطة والألف المقصورة، وحذف التشكيل.
String normalizeArabic(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .trim();

/// أول كلمة محظورة في النص أو null (تحقق مسبق قبل الإرسال؛ الخادم يتحقق أيضاً في المنشورات والعروض).
String? bannedWordIn(String text, List<String> words) {
  if (words.isEmpty) return null;
  final t = normalizeArabic(text);
  if (t.isEmpty) return null;
  for (final w in words) {
    final n = normalizeArabic(w);
    if (n.length >= 2 && t.contains(n)) return w;
  }
  return null;
}

extension SafetyApi on ApiClient {
  Future<List<ChatMute>> mutes() async => asList(await getList('/safety/mutes')).map(ChatMute.fromJson).toList();
  Future<ChatMute> mute(String peerId, {int? hours}) async => ChatMute.fromJson(await post('/safety/mutes', {'peerId': peerId, if (hours != null) 'hours': hours}));
  Future<void> unmute(String peerId) => delete('/safety/mutes/$peerId');

  /// قائمة الكلمات المحظورة (مطبّعة) وحدّ البلاغات.
  Future<List<String>> bannedWords() async {
    final raw = (await get('/safety/words'))['words'];
    return raw is List ? [for (final w in raw) w.toString()] : const [];
  }

  /// بلاغ عن منشور خريطة أو عرض سوق؛ يعيد عدد المبلّغين وهل أُخفي تلقائياً.
  Future<({int reports, bool hidden})> reportContent({required String type, required String id, String reason = ''}) async {
    final d = await post('/safety/report', {'targetType': type, 'targetId': id, 'reason': reason});
    return (reports: (d['reports'] as num?)?.toInt() ?? 0, hidden: d['hidden'] == true);
  }

  /// المحظورون (مسار النواة /blocks).
  Future<List<BlockedUser>> blockedUsers() async {
    final raw = await get('/blocks');
    final list = raw['data'] ?? raw['items'] ?? raw['blocks'] ?? raw['list'] ?? raw['users'];
    final items = list is List ? list : const [];
    return [for (final e in items) if (e is Map) ?BlockedUser.fromJson(e)];
  }
}
