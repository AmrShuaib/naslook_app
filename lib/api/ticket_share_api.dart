import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../state/providers.dart';
import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';

/// تذكرة أرسلتُها وما زالت معلّقة (server/ticket_share.js): إلى مستخدم ([to]) أو برابط لشخص واحد ([url]).
/// التذكرة تبقى لي وتظهر في تذاكري حتى يقبلها المستلم.
class TicketShareOut {
  final String ticketId, transferId, mode;
  final Person? to;
  final String? url;
  final DateTime? createdAt;
  const TicketShareOut({required this.ticketId, required this.transferId, required this.mode, this.to, this.url, this.createdAt});

  factory TicketShareOut.fromJson(Map m) => TicketShareOut(
        ticketId: '${m['ticketId'] ?? ''}',
        transferId: '${m['transferId'] ?? ''}',
        mode: m['mode'] == 'link' ? 'link' : 'user',
        to: m['to'] is Map ? Person.fromJson(m['to'] as Map) : null,
        url: (m['url'] as String?)?.isNotEmpty == true ? m['url'] as String : null,
        createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}')?.toLocal(),
      );

  bool get isLink => mode == 'link';
}

/// تذكرة وصلتني من مستخدم وتنتظر قبولي أو رفضي.
class TicketShareIn {
  final String transferId, ticketId, eventId, title, tier;
  final Person from;
  final DateTime? startsAt, createdAt;
  final String? placeName;
  const TicketShareIn({required this.transferId, required this.from, required this.ticketId, required this.eventId, required this.title, required this.tier, this.startsAt, this.placeName, this.createdAt});

  factory TicketShareIn.fromJson(Map m) {
    final t = m['ticket'] is Map ? m['ticket'] as Map : const {};
    return TicketShareIn(
      transferId: '${m['transferId'] ?? ''}',
      from: Person.fromJson(m['from'] is Map ? m['from'] as Map : const {}),
      ticketId: '${t['id'] ?? ''}',
      eventId: '${t['eventId'] ?? ''}',
      title: '${t['title'] ?? ''}',
      tier: '${t['tier'] ?? ''}',
      startsAt: DateTime.tryParse('${t['startsAt'] ?? ''}')?.toLocal(),
      placeName: (t['placeName'] as String?)?.isNotEmpty == true ? t['placeName'] as String : null,
      createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}')?.toLocal(),
    );
  }
}

class TicketShares {
  final List<TicketShareOut> outgoing;
  final List<TicketShareIn> incoming;
  const TicketShares({this.outgoing = const [], this.incoming = const []});

  factory TicketShares.fromJson(Map<String, dynamic> m) => TicketShares(
        outgoing: asList(m['outgoing']).map(TicketShareOut.fromJson).toList(),
        incoming: asList(m['incoming']).map(TicketShareIn.fromJson).toList(),
      );

  /// الإرسال المعلّق لتذكرتي إن وُجد.
  TicketShareOut? pendingOf(String ticketId) {
    for (final o in outgoing) {
      if (o.ticketId == ticketId) return o;
    }
    return null;
  }
}

/// معاينة رابط تذكرة (`/t/<رمز>`) قبل الاستلام؛ تُعرض بلا حساب.
class TicketClaimPreview {
  final String title, tier, fromName;
  final String? fromAvatar, placeName;
  final DateTime? startsAt;
  /// false حين استُلمت التذكرة أو استرجعها صاحبها.
  final bool pending;
  const TicketClaimPreview({required this.title, required this.tier, required this.fromName, this.fromAvatar, this.placeName, this.startsAt, this.pending = true});

  factory TicketClaimPreview.fromJson(Map<String, dynamic> m) {
    final f = m['from'] is Map ? m['from'] as Map : const {};
    return TicketClaimPreview(
      title: '${m['title'] ?? ''}',
      tier: '${m['tier'] ?? ''}',
      fromName: '${f['nickname'] ?? ''}',
      fromAvatar: f['avatarUrl']?.toString(),
      placeName: (m['placeName'] as String?)?.isNotEmpty == true ? m['placeName'] as String : null,
      startsAt: DateTime.tryParse('${m['startsAt'] ?? ''}')?.toLocal(),
      pending: m['status'] != 'gone',
    );
  }
}

/// مسارات توزيع التذاكر (server/ticket_share.js).
extension TicketShareApi on ApiClient {
  Future<TicketShares> ticketShares() async => TicketShares.fromJson(await get('/tickets/shares'));
  Future<TicketShareOut> sendTicket(String ticketId, String userId) async => TicketShareOut.fromJson(await post('/tickets/$ticketId/send', {'userId': userId}));
  /// رابط لشخص واحد؛ الخادم يعيد الرابط المعلّق نفسه إن وُجد.
  Future<TicketShareOut> ticketLink(String ticketId) async => TicketShareOut.fromJson(await post('/tickets/$ticketId/link', const {}));
  Future<void> undoTicketSend(String ticketId) => delete('/tickets/$ticketId/send');
  Future<Ticket> acceptTicket(String transferId) async => Ticket.fromJson(await post('/tickets/transfers/$transferId/accept', const {}));
  Future<void> declineTicket(String transferId) => post('/tickets/transfers/$transferId/decline', const {});
  Future<TicketClaimPreview> ticketClaimPreview(String token) async => TicketClaimPreview.fromJson(await get('/tickets/claim/$token'));
  Future<Ticket> claimTicket(String token) async => Ticket.fromJson(await post('/tickets/claim', {'token': token}));
}

/// الإرسالات المعلّقة (مني وإليّ). تُجلب من جديد عند كل فتح حتى لا تبقى تذكرة قُبلت أو استُرجعت ظاهرة كمعلّقة.
final ticketSharesProvider = FutureProvider.autoDispose<TicketShares>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).ticketShares() : const TicketShares());

/// رسالة عربية لكل رمز خطأ من مسارات التوزيع. الرمز من جسم الرد لأن العميل يعرّب بعض الرموز العامة في رسالته.
String ticketShareErrText(Object e) {
  final code = e is ApiException ? '${e.body?['error'] ?? ''}' : '';
  return switch (code) {
    'not-transferable' => 'هذه التذكرة لا يمكن إرسالها (مستخدمة أو مستردّة أو أُلغيت فعاليتها)',
    'already-pending' => 'هذه التذكرة مُرسلة وتنتظر القبول. استرجعها أولاً ثم أرسلها من جديد',
    'bad-user' => 'لم نجد هذا المستخدم',
    'blocked' => 'لا يمكن الإرسال إلى هذا المستخدم',
    'gone' => 'هذه التذكرة لم تعد متاحة: استُلمت أو استرجعها صاحبها',
    'self' => 'هذه تذكرتك أنت، أرسلها لغيرك',
    'not-found' => 'لم نجد هذه التذكرة',
    _ => e is ApiException && e.isNetwork ? 'تعذر الاتصال، حاول مرة أخرى' : 'تعذر إتمام الطلب، حاول مرة أخرى',
  };
}
