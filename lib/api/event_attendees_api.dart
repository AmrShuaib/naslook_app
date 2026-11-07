import 'client.dart';
import 'models.dart';

/// حاضر في قائمة المضيف (GET /events/:id/attendees في server/commerce.js): الاسم الظاهر والصورة والفئة ودخل أم لا ومتى.
/// [code] يصل فقط عند البحث بالرمز بعد المسح؛ القائمة نفسها بلا رموز.
class EventAttendee {
  final String ticketId, tier, status;
  final Person holder;
  final bool checkedIn;
  final DateTime? checkedInAt, boughtAt;
  final int paid;
  final String? code;
  const EventAttendee({required this.ticketId, required this.holder, required this.tier, required this.status, required this.checkedIn, this.checkedInAt, this.boughtAt, this.paid = 0, this.code});

  factory EventAttendee.fromJson(Map<String, dynamic> m) => EventAttendee(
        ticketId: '${m['ticketId'] ?? ''}',
        holder: Person.fromJson(m['holder'] is Map ? m['holder'] as Map : const {}),
        tier: '${m['tier'] ?? ''}',
        status: '${m['status'] ?? 'valid'}',
        checkedIn: m['checkedIn'] == true || m['status'] == 'used',
        checkedInAt: DateTime.tryParse('${m['checkedInAt'] ?? ''}')?.toLocal(),
        boughtAt: DateTime.tryParse('${m['boughtAt'] ?? ''}')?.toLocal(),
        paid: (m['paid'] as num?)?.toInt() ?? 0,
        code: m['code']?.toString(),
      );

  bool get refunded => status == 'refunded';
  String get name => holder.nickname.isNotEmpty ? holder.nickname : 'مستخدم';
}

/// صفحة من القائمة مع العدّادات الكلية ومؤشر الصفحة التالية (null = لا مزيد).
class AttendeePage {
  final List<EventAttendee> items;
  final String? next;
  final int total, checkedIn, people;
  const AttendeePage({this.items = const [], this.next, this.total = 0, this.checkedIn = 0, this.people = 0});

  factory AttendeePage.fromJson(Map<String, dynamic> m) => AttendeePage(
        items: asList(m['items']).map(EventAttendee.fromJson).toList(),
        next: (m['next'] as String?)?.isNotEmpty == true ? m['next'] as String : null,
        total: (m['total'] as num?)?.toInt() ?? 0,
        checkedIn: (m['checkedIn'] as num?)?.toInt() ?? 0,
        people: (m['people'] as num?)?.toInt() ?? 0,
      );
}

extension EventAttendeesApi on ApiClient {
  /// [status]: '' الكل (بلا المستردة)، 'in' دخلوا، 'out' لم يدخلوا، 'refunded'. [code] يبحث عن تذكرة بعينها بعد مسحها.
  Future<AttendeePage> eventAttendees(String eventId, {String status = '', String? cursor, String? code, String q = '', int limit = 30}) async =>
      AttendeePage.fromJson(await get('/events/$eventId/attendees', query: {
        if (status.isNotEmpty) 'status': status,
        if (cursor != null) 'cursor': cursor,
        if (code != null && code.isNotEmpty) 'code': code,
        if (q.isNotEmpty) 'q': q,
        'limit': '$limit',
      }));
}
