import 'client.dart';

/// حدث من «القناة الحية» (server/live.js): رقم متسلسل، نوع، وحمولة بصيغة المسار الأصلي (لحظة = كما يعيدها /mapposts).
class LiveEvent {
  final int seq;
  final String kind;
  final Map<String, dynamic> data;
  const LiveEvent({required this.seq, required this.kind, this.data = const {}});

  static const post = 'post';
  static const postRemoved = 'post_removed';
  static const postRestored = 'post_restored';
  /// حدث محلي لا يأتي من الخادم: المؤشر أقدم من حلقة الخادم فعلى الصفحات إعادة الجلب كاملاً
  static const reset = LiveEvent(seq: 0, kind: '_reset');
  bool get isReset => kind == '_reset';

  factory LiveEvent.fromJson(Map<String, dynamic> j) => LiveEvent(
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        kind: (j['kind'] ?? '').toString(),
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const {},
      );
}

/// ردّ انتظار واحد: المؤشر الجديد، الأحداث منذ المؤشر السابق، وهل انقطع التسلسل.
class LiveBatch {
  final int seq;
  final bool reset;
  final List<LiveEvent> events;
  /// يطلب الخادم تأجيل الطلب التالي ثوانيَ (ازدحام)
  final int? retryIn;
  const LiveBatch({required this.seq, this.reset = false, this.events = const [], this.retryIn});

  factory LiveBatch.fromJson(Map<String, dynamic> j) => LiveBatch(
        seq: (j['seq'] as num).toInt(),
        reset: j['reset'] == true,
        events: [for (final e in (j['events'] as List? ?? const [])) if (e is Map) LiveEvent.fromJson(Map<String, dynamic>.from(e))],
        retryIn: (j['retryIn'] as num?)?.toInt(),
      );
}

extension LiveApi on ApiClient {
  /// ينتظر عند الخادم حتى [timeoutSec] ثانية حدثاً بعد [after]؛ بلا [after] يعيد المؤشر الحالي فوراً (مصافحة).
  Future<LiveBatch> liveWait({int? after, int timeoutSec = 25}) async {
    final j = await getWait('/live/wait', query: {if (after != null) 'after': '$after', 'timeout': '$timeoutSec'}, timeout: Duration(seconds: timeoutSec + 20));
    if (j['seq'] is! num) throw const ApiException(0, 'استجابة غير متوقعة من القناة الحية');
    return LiveBatch.fromJson(j);
  }
}
