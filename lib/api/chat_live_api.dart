import 'client.dart';

/// جلسة موقع مباشر (server/chat_live.js): من يشارك، لمن، آخر موقع ووقته، ومتى تنتهي.
class LiveSession {
  final String id, from, to;
  final double? lat, lng, accuracy;
  /// وقت آخر موقع مدفوع؛ null قبل أول دفعة.
  final DateTime? at;
  final DateTime until;
  final bool active;
  const LiveSession({required this.id, required this.from, required this.to, this.lat, this.lng, this.accuracy, this.at, required this.until, required this.active});
  factory LiveSession.fromJson(Map m) {
    double? d(String k) => m[k] is num ? (m[k] as num).toDouble() : double.tryParse(m[k]?.toString() ?? '');
    return LiveSession(
      id: m['id']?.toString() ?? '', from: m['from']?.toString() ?? '', to: m['to']?.toString() ?? '',
      lat: d('lat'), lng: d('lng'), accuracy: d('accuracy'),
      at: m['at'] == null ? null : DateTime.tryParse(m['at'].toString())?.toLocal(),
      until: DateTime.tryParse(m['until']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      active: m['active'] == true,
    );
  }
  bool get hasPosition => lat != null && lng != null;
  /// هل انقضت المدة محلياً (الخادم يعيد active:false بعدها على أي حال)؟
  bool get expired => !until.isAfter(DateTime.now());
  LiveSession copyWith({bool? active}) => LiveSession(id: id, from: from, to: to, lat: lat, lng: lng, accuracy: accuracy, at: at, until: until, active: active ?? this.active);
}

/// ردود مقترحة من POST /chat/suggest: ثلاث جمل قصيرة ومصدرها (ai أو rules).
class ReplySuggestions {
  final List<String> suggestions;
  final String source;
  const ReplySuggestions(this.suggestions, this.source);
  factory ReplySuggestions.fromJson(Map m) => ReplySuggestions(
        [for (final s in (m['suggestions'] is List ? m['suggestions'] as List : const [])) if (s.toString().trim().isNotEmpty) s.toString().trim()].take(3).toList(),
        m['source']?.toString() ?? 'rules',
      );
}

/// دور في المحادثة يُرسل إلى محرّك الاقتراحات: نصّ فقط، بلا معرّفات ولا أسماء.
typedef SuggestTurn = ({bool mine, String text});

/// مسارات الموقع المباشر والردود المقترحة (server/chat_live.js).
extension ChatLiveApi on ApiClient {
  /// يبدأ جلسة مشاركة لمدة 15 أو 60 أو 480 دقيقة؛ الجديدة توقف السابقة مع الطرف نفسه.
  Future<LiveSession> liveStart(String peerId, int minutes) async => LiveSession.fromJson(await post('/chat/live', {'peerId': peerId, 'minutes': minutes}));
  /// يدفع موقع المُشارِك (مرة كل 5 ثوانٍ على الأكثر؛ التطبيق يدفع كل 10).
  Future<void> livePush(String id, double lat, double lng, {double? accuracy}) => put('/chat/live/$id', {'lat': lat, 'lng': lng, if (accuracy != null) 'accuracy': accuracy});
  Future<LiveSession> liveGet(String id) async => LiveSession.fromJson(await get('/chat/live/$id'));
  Future<void> liveStop(String id) => delete('/chat/live/$id');
  /// آخر ثماني رسائل (الأحدث أخيراً) → ثلاثة ردود مقترحة.
  Future<ReplySuggestions> suggestReplies(String peerId, List<SuggestTurn> turns) async => ReplySuggestions.fromJson(await post('/chat/suggest', {
        'peerId': peerId,
        'messages': [for (final t in turns.length > 8 ? turns.sublist(turns.length - 8) : turns) {'mine': t.mine, 'text': t.text}],
      }, prompt: false));
}
