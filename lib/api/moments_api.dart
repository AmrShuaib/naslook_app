import '../core/share/share_links.dart' show publicOrigin;
import 'client.dart';

/// التفاعلات السريعة على اللحظة (server/moment_extras.js): أربعة رموز فقط بهذا الترتيب.
const momentEmojis = ['😍', '😂', '🔥', '👏'];

/// عدّاد كل رمز وتفاعلي (null إن لم أتفاعل أو كنت زائراً).
class MomentReactions {
  final Map<String, int> counts;
  final String? mine;
  const MomentReactions({this.counts = const {}, this.mine});

  static const empty = MomentReactions();

  factory MomentReactions.fromJson(Map m) {
    final raw = m['counts'];
    final counts = <String, int>{};
    if (raw is Map) {
      for (final e in momentEmojis) {
        final v = raw[e];
        final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
        if (n > 0) counts[e] = n;
      }
    }
    final mine = m['mine']?.toString();
    return MomentReactions(counts: counts, mine: momentEmojis.contains(mine) ? mine : null);
  }

  int count(String emoji) => counts[emoji] ?? 0;
  int get total => counts.values.fold(0, (a, b) => a + b);

  /// النتيجة المتوقعة محلياً قبل رد الخادم: تبديل تفاعلي إلى [emoji] أو إزالته (null).
  MomentReactions withMine(String? emoji) {
    final next = Map<String, int>.of(counts);
    void bump(String e, int d) {
      final n = (next[e] ?? 0) + d;
      if (n > 0) {
        next[e] = n;
      } else {
        next.remove(e);
      }
    }

    if (mine != null) bump(mine!, -1);
    if (emoji != null) bump(emoji, 1);
    return MomentReactions(counts: next, mine: emoji);
  }
}

/// رابط اللحظة العام: الخادم (server/share.js) يعرض بطاقة Open Graph ثم يحوّل المتصفح إلى `/#/m/<id>`.
String momentLink(String id) => '${publicOrigin()}/m/$id';

extension MomentsApi on ApiClient {
  /// عام: الزائر يرى العدّادات وتفاعله null.
  Future<MomentReactions> momentReactions(String id) async => MomentReactions.fromJson(await get('/moments/$id/reactions'));

  /// يضع تفاعلي أو يغيّره، أو يزيله حين [emoji] null.
  Future<MomentReactions> reactMoment(String id, String? emoji) async =>
      MomentReactions.fromJson(emoji == null ? await delete('/moments/$id/react') : await post('/moments/$id/react', {'emoji': emoji}));
}
