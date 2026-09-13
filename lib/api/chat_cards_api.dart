import 'client.dart';
import 'models.dart';

/// بطاقة محلولة من الخادم لرمز إشارة (server/chat_cards.js): النوع والعنوان والسعر والحالة من مصدرها.
class ChatCard {
  /// user | biz | item | event | listing | post | space | spacepost | ticket | order
  final String type;
  final String id, title, subtitle;
  final String? image, link, bizId, eventId, code, status, category, kind;
  final int? price, left, discussions, replies, posts, members, total, qty, paid;
  final bool? openNow, cancelled, verified;
  final DateTime? startsAt;
  final Person? person;
  const ChatCard({
    required this.type, required this.id, required this.title, this.subtitle = '', this.image, this.link, this.bizId, this.eventId, this.code, this.status, this.category, this.kind,
    this.price, this.left, this.discussions, this.replies, this.posts, this.members, this.total, this.qty, this.paid, this.openNow, this.cancelled, this.verified, this.startsAt, this.person,
  });
  factory ChatCard.fromJson(Map m) {
    Person? who;
    for (final k in ['user', 'seller', 'owner', 'host']) {
      if (m[k] is Map) { who = Person.fromJson(asMap(m[k])); break; }
    }
    int? i(String k) => m[k] is num ? (m[k] as num).toInt() : null;
    bool? b(String k) => m[k] is bool ? m[k] as bool : null;
    String? s(String k) => m[k]?.toString();
    return ChatCard(
      type: s('type') ?? '', id: s('id') ?? '', title: s('title') ?? '', subtitle: s('subtitle') ?? '', image: s('image'), link: s('link'), bizId: s('bizId'), eventId: s('eventId'), code: s('code'),
      status: s('status'), category: s('category'), kind: s('kind'), price: i('price'), left: i('left'), discussions: i('discussions'), replies: i('replies'), posts: i('posts'), members: i('members'),
      total: i('total'), qty: i('qty'), paid: i('paid'), openNow: b('openNow'), cancelled: b('cancelled'), verified: b('verified'),
      startsAt: (m['startsAt'] ?? m['startAt']) == null ? null : DateTime.tryParse((m['startsAt'] ?? m['startAt']).toString())?.toLocal(), person: who,
    );
  }
}

/// طلب مسجّل بمعرّف رسالة: مبلغ، إرسال، تقسيم، موعد؛ وحالته.
class ChatRequest {
  final String messageId, kind, from, to, note, when, place, status;
  final int amount, n, share;
  final DateTime? expiresAt, resolvedAt;
  const ChatRequest({required this.messageId, required this.kind, required this.from, required this.to, this.note = '', this.when = '', this.place = '', this.status = 'pending', this.amount = 0, this.n = 1, int? share, this.expiresAt, this.resolvedAt})
      : share = share ?? amount;
  factory ChatRequest.fromJson(Map m) => ChatRequest(
        messageId: m['messageId']?.toString() ?? '', kind: m['kind']?.toString() ?? '', from: m['from']?.toString() ?? '', to: m['to']?.toString() ?? '', note: m['note']?.toString() ?? '',
        when: m['when']?.toString() ?? '', place: m['place']?.toString() ?? '', status: m['status']?.toString() ?? 'pending', amount: (m['amount'] as num?)?.toInt() ?? 0, n: (m['n'] as num?)?.toInt() ?? 1,
        share: (m['share'] as num?)?.toInt(), expiresAt: m['expiresAt'] == null ? null : DateTime.tryParse(m['expiresAt'].toString())?.toLocal(), resolvedAt: m['resolvedAt'] == null ? null : DateTime.tryParse(m['resolvedAt'].toString())?.toLocal(),
      );
  static ChatRequest? maybe(dynamic v) => v is Map ? ChatRequest.fromJson(v) : null;
  bool get pending => status == 'pending';
  String get statusLabel => switch (status) {
        'pending' => 'بانتظار الرد', 'paid' => 'مدفوع', 'accepted' => 'تمت الموافقة', 'declined' => 'مرفوض', 'cancelled' => 'ملغى', 'expired' => 'انتهت صلاحيته', 'unverified' => 'غير مؤكد', _ => status,
      };
}

extension ChatCardsApi on ApiClient {
  /// يحلّ إشارات (حتى 40) دفعة واحدة؛ المفتاح كما أُرسل، والقيمة null لما لم يُفهم أو لم يوجد.
  Future<Map<String, ChatCard?>> chatCards(Iterable<String> refs) async {
    final list = refs.toSet().toList();
    if (list.isEmpty) return const {};
    final data = await get('/chat/cards', query: {'refs': list.join(',')});
    final out = <String, ChatCard?>{};
    final m = asMap(data['refs']);
    for (final r in list) {
      out[r] = m[r] is Map ? ChatCard.fromJson(asMap(m[r])) : null;
    }
    return out;
  }

  Future<ChatRequest> chatRequest({required String messageId, required String peerId, required String kind, int amount = 0, int n = 1, String note = '', String when = '', String place = ''}) async =>
      ChatRequest.fromJson(asMap((await post('/chat/requests', {
        'messageId': messageId, 'peerId': peerId, 'kind': kind, 'amount': amount, 'n': n, 'note': note, 'when': when, 'place': place,
      }))['request']));
  Future<Map<String, ChatRequest>> chatRequests(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final data = await get('/chat/requests', query: {'ids': list.join(',')});
    return {for (final e in data.entries) if (e.value is Map) e.key: ChatRequest.fromJson(asMap(e.value))};
  }
  Future<ChatRequest> _act(String id, String action) async => ChatRequest.fromJson(asMap((await post('/chat/requests/$id/$action', const {}))['request']));
  Future<ChatRequest> chatRequestPay(String messageId) => _act(messageId, 'pay');
  Future<ChatRequest> chatRequestAccept(String messageId) => _act(messageId, 'accept');
  Future<ChatRequest> chatRequestDecline(String messageId) => _act(messageId, 'decline');
  Future<ChatRequest> chatRequestCancel(String messageId) => _act(messageId, 'cancel');
}
