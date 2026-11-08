// رسائل الدوائر الخاصة (server/biz_inbox.js): محادثة بين مستخدم ودائرة تجارية، منفصلة عن محادثات النواة.
// العميل يرى ردود الفريق باسم الدائرة وشعارها؛ الفريق يرى من كتب كل رد منهم.
import 'client.dart';
import 'models.dart';

DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// الدائرة كما تظهر في المحادثة: الاسم والشعار والتوثيق.
class BizInboxCircle {
  final String id, name;
  final String? logoUrl, category, ownerId;
  final bool verified;
  const BizInboxCircle({required this.id, this.name = '', this.logoUrl, this.category, this.ownerId, this.verified = false});
  factory BizInboxCircle.fromJson(Map m) => BizInboxCircle(
        id: m['id']?.toString() ?? '', name: m['name']?.toString() ?? '', logoUrl: m['logoUrl']?.toString(), category: m['category']?.toString(),
        ownerId: m['ownerId']?.toString(), verified: m['verified'] == true,
      );
}

/// بطاقة مرجع داخل الرسالة: طلب للعميل في الدائرة أو صنف من كتالوجها (محلولة لحظة القراءة).
class BizMsgRef {
  final String kind, id, title;
  final String? code, status, imageUrl, itemKind;
  final int? total, price;
  final DateTime? startAt;
  /// المرجع حُذف أو لم يعد متاحاً.
  final bool missing;
  const BizMsgRef({required this.kind, required this.id, this.title = '', this.code, this.status, this.imageUrl, this.itemKind, this.total, this.price, this.startAt, this.missing = false});
  factory BizMsgRef.fromJson(Map m) => BizMsgRef(
        kind: m['kind']?.toString() ?? '', id: m['id']?.toString() ?? '', title: m['title']?.toString() ?? '', code: m['code']?.toString(), status: m['status']?.toString(),
        imageUrl: m['imageUrl']?.toString(), itemKind: m['itemKind']?.toString(), total: m['total'] == null ? null : _i(m['total']), price: m['price'] == null ? null : _i(m['price']),
        startAt: _t(m['startAt']), missing: m['missing'] == true,
      );
  bool get isOrder => kind == 'order';
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id};
  String get statusLabel => switch (status) { 'confirmed' => 'مؤكد', 'used' => 'مستخدم', 'cancelled' => 'ملغى', 'no_show' => 'لم يحضر', _ => status ?? '' };
}

class BizThreadMessage {
  final String id, threadId, side, text;
  final bool mine, hidden;
  final List<String> photos;
  final BizMsgRef? ref;
  /// عضو الفريق الذي كتب الرد (يظهر للفريق فقط).
  final Person? sender;
  final String? clientId;
  final DateTime? createdAt;
  const BizThreadMessage({required this.id, required this.threadId, required this.side, this.text = '', this.mine = false, this.hidden = false, this.photos = const [], this.ref, this.sender, this.clientId, this.createdAt});
  factory BizThreadMessage.fromJson(Map m) => BizThreadMessage(
        id: m['id']?.toString() ?? '', threadId: m['threadId']?.toString() ?? '', side: m['side']?.toString() ?? 'customer', text: m['text']?.toString() ?? '',
        mine: m['mine'] == true, hidden: m['hidden'] == true, photos: [for (final p in (m['photos'] is List ? m['photos'] as List : const [])) p.toString()],
        ref: m['ref'] is Map ? BizMsgRef.fromJson(m['ref'] as Map) : null, sender: m['sender'] is Map ? Person.fromJson(m['sender'] as Map) : null,
        clientId: m['clientId']?.toString(), createdAt: _t(m['createdAt']),
      );
  bool get fromTeam => side == 'team';
}

class BizThread {
  final String id, bizId, status, lastText, lastSide;
  final int unread;
  final DateTime? lastAt, createdAt, closedAt, seenAt;
  /// للعميل: الدائرة؛ للفريق: العميل والمسؤول.
  final BizInboxCircle? biz;
  final Person? customer, assignee;
  const BizThread({required this.id, required this.bizId, this.status = 'open', this.lastText = '', this.lastSide = 'customer', this.unread = 0, this.lastAt, this.createdAt, this.closedAt, this.seenAt, this.biz, this.customer, this.assignee});
  factory BizThread.fromJson(Map m) => BizThread(
        id: m['id']?.toString() ?? '', bizId: m['bizId']?.toString() ?? '', status: m['status']?.toString() ?? 'open', lastText: m['lastText']?.toString() ?? '',
        lastSide: m['lastSide']?.toString() ?? 'customer', unread: _i(m['unread']), lastAt: _t(m['lastAt']), createdAt: _t(m['createdAt']), closedAt: _t(m['closedAt']), seenAt: _t(m['seenAt']),
        biz: m['biz'] is Map ? BizInboxCircle.fromJson(m['biz'] as Map) : null,
        customer: m['customer'] is Map ? Person.fromJson(m['customer'] as Map) : null, assignee: m['assignee'] is Map ? Person.fromJson(m['assignee'] as Map) : null,
      );
  bool get closed => status == 'closed';
}

/// عضو في صندوق الدائرة (للإسناد): المالك أو المدير أو الموظف.
class BizInboxMember {
  final Person person;
  final String role;
  const BizInboxMember(this.person, this.role);
  factory BizInboxMember.fromJson(Map m) => BizInboxMember(Person.fromJson(m), m['role']?.toString() ?? 'staff');
  String get roleLabel => switch (role) { 'owner' => 'المالك', 'manager' => 'مدير', _ => 'موظف' };
}

/// المحادثة كاملة لقارئها: الجهة، الرسائل (الأقدم أولاً)، هل يستطيع الإرسال ولماذا، وطلبات العميل في الدائرة لبطاقة المرجع.
class BizThreadView {
  final String viewer;
  final String? role, reason;
  final BizInboxCircle biz;
  final BizThread? thread;
  final List<BizThreadMessage> messages;
  final bool hasMore, canSend, canAssignOthers;
  final List<BizMsgRef> orders;
  final List<BizInboxMember> team;
  const BizThreadView({this.viewer = 'customer', this.role, this.reason, required this.biz, this.thread, this.messages = const [], this.hasMore = false, this.canSend = true, this.canAssignOthers = false, this.orders = const [], this.team = const []});
  factory BizThreadView.fromJson(Map m) => BizThreadView(
        viewer: m['viewer']?.toString() ?? 'customer', role: m['role']?.toString(), reason: m['reason']?.toString(),
        biz: BizInboxCircle.fromJson(asMap(m['biz'])), thread: m['thread'] is Map ? BizThread.fromJson(m['thread'] as Map) : null,
        messages: asList(m['messages']).map(BizThreadMessage.fromJson).toList(), hasMore: m['hasMore'] == true, canSend: m['canSend'] != false,
        canAssignOthers: m['canAssignOthers'] == true, orders: asList(m['orders']).map(BizMsgRef.fromJson).toList(), team: asList(m['team']).map(BizInboxMember.fromJson).toList(),
      );
  bool get isTeam => viewer == 'team';
}

/// صندوق الدائرة من جهة الفريق: المحادثات حسب الفلتر وعدّاداتها.
class BizInboxPage {
  final String filter;
  final String? role;
  final bool canAssignOthers;
  final List<BizThread> threads;
  final int open, closed, mine, unread;
  final List<BizInboxMember> team;
  const BizInboxPage({this.filter = 'open', this.role, this.canAssignOthers = false, this.threads = const [], this.open = 0, this.closed = 0, this.mine = 0, this.unread = 0, this.team = const []});
  factory BizInboxPage.fromJson(Map m) {
    final c = asMap(m['counts']);
    return BizInboxPage(
      filter: m['filter']?.toString() ?? 'open', role: m['role']?.toString(), canAssignOthers: m['canAssignOthers'] == true,
      threads: asList(m['threads']).map(BizThread.fromJson).toList(), open: _i(c['open']), closed: _i(c['closed']), mine: _i(c['mine']), unread: _i(c['unread']),
      team: asList(m['team']).map(BizInboxMember.fromJson).toList(),
    );
  }
}

/// ما يعيده الإرسال: المحادثة بعد التحديث والرسالة المحفوظة.
typedef BizSendResult = ({BizThread thread, BizThreadMessage message});

extension BizInboxApi on ApiClient {
  // ---- العميل
  /// محادثتي مع دائرة (thread = null قبل أول رسالة).
  Future<BizThreadView> bizThreadWith(String bizId) async => BizThreadView.fromJson(await get('/biz/$bizId/thread'));
  /// أول رسالة تنشئ المحادثة، والتالية تتابعها.
  Future<BizSendResult> sendToBiz(String bizId, {String text = '', List<String> photos = const [], BizMsgRef? ref, String? clientId}) async =>
      _sent(await post('/biz/$bizId/thread', {'text': text, 'photos': photos, if (ref != null) 'ref': ref.toJson(), if (clientId != null) 'clientId': clientId}));
  /// «رسائل الدوائر» في قائمة محادثاتي، وعدد ما فيه ردود لم أقرأها.
  Future<({List<BizThread> threads, int unread})> myBizThreads() async {
    final d = await get('/bizinbox/threads');
    return (threads: asList(d['threads']).map(BizThread.fromJson).toList(), unread: _i(d['unread']));
  }

  // ---- المحادثة بمعرّفها (للعميل أو للفريق)
  /// beforeId: معرّف أقدم رسالة محمّلة؛ المؤشر بالمعرّف لا بالوقت لأن الوقت في JSON مقطوع إلى الميلي ثانية
  /// فتضيع رسالة أقدم في الميلي ثانية نفسها.
  Future<BizThreadView> bizThread(String threadId, {String? beforeId}) async =>
      BizThreadView.fromJson(await get('/bizinbox/threads/$threadId', query: {if (beforeId != null) 'before': beforeId}));
  Future<BizSendResult> sendBizThread(String threadId, {String text = '', List<String> photos = const [], BizMsgRef? ref, String? clientId}) async =>
      _sent(await post('/bizinbox/threads/$threadId/messages', {'text': text, 'photos': photos, if (ref != null) 'ref': ref.toJson(), if (clientId != null) 'clientId': clientId}));
  Future<void> readBizThread(String threadId) => post('/bizinbox/threads/$threadId/read', const {}, prompt: false);

  // ---- الفريق
  Future<BizInboxPage> bizInbox(String bizId, {String filter = 'open'}) async => BizInboxPage.fromJson(await get('/biz/$bizId/inbox', query: {'filter': filter}));
  /// شارة تبويب «الرسائل»: محادثات فيها رسائل لم يقرأها الفريق.
  Future<int> bizInboxUnread(String bizId) async => _i((await get('/biz/$bizId/inbox/unread'))['unread']);
  Future<BizThread> assignBizThread(String threadId, String? userId) async => BizThread.fromJson(asMap((await post('/bizinbox/threads/$threadId/assign', {'userId': userId}))['thread']));
  Future<BizThread> closeBizThread(String threadId) async => BizThread.fromJson(asMap((await post('/bizinbox/threads/$threadId/close', const {}))['thread']));
  Future<BizThread> reopenBizThread(String threadId) async => BizThread.fromJson(asMap((await post('/bizinbox/threads/$threadId/reopen', const {}))['thread']));

  BizSendResult _sent(Map<String, dynamic> d) => (thread: BizThread.fromJson(asMap(d['thread'])), message: BizThreadMessage.fromJson(asMap(d['message'])));
}

/// رسالة مفهومة لأخطاء رسائل الدوائر.
String bizInboxErrText(Object e) {
  final code = e is ApiException ? (e.body ?? const {})['error']?.toString() : null;
  return switch (code) {
    'rate-limit' => 'أرسلت رسائل كثيرة خلال دقيقة؛ انتظر قليلاً ثم أعد المحاولة',
    'too-many-threads' => 'بدأت خمس محادثات مع دوائر اليوم؛ تابع محادثاتك الحالية أو حاول غداً',
    'banned-words' => 'الرسالة فيها كلمات غير مسموحة',
    'blocked' => 'لا يمكن المراسلة بسبب الحظر',
    'suspended' => 'حسابك موقوف فلا يمكنك الإرسال الآن',
    'no-owner' => 'هذه الدائرة لم يستلمها صاحبها بعد، فلا أحد يرد على الرسائل',
    'unavailable' => 'هذه الدائرة غير متاحة الآن',
    'own-circle' => 'هذه دائرتك؛ رسائل العملاء في لوحة التحكم',
    'bad-ref' => 'لا يمكن إرفاق هذا الطلب أو الصنف',
    'too-many-photos' => 'أربع صور على الأكثر في الرسالة',
    'bad-photo' => 'تعذّر إرفاق الصورة، ارفعها من جديد',
    'empty' => 'اكتب رسالة أو أرفق صورة',
    'not-in-team' => 'هذا الشخص ليس في فريق الرسائل',
    'forbidden' => 'ليست لديك صلاحية على هذه المحادثة',
    'not-found' => 'لم تعد هذه المحادثة متاحة',
    _ => e is ApiException ? e.message : e.toString(),
  };
}

/// سبب منع الإرسال الظاهر تحت المحادثة بدل حقل الكتابة.
String? bizInboxReasonText(String? reason) => switch (reason) {
      null => null,
      'own-circle' => 'هذه دائرتك؛ رسائل العملاء في لوحة التحكم ← الرسائل',
      'no-owner' => 'هذه الدائرة لم يستلمها صاحبها بعد، فلا أحد يرد على الرسائل.',
      'blocked' => 'لا يمكن المراسلة بسبب الحظر.',
      'suspended' => 'حسابك موقوف فلا يمكنك الإرسال الآن.',
      'unavailable' => 'هذه الدائرة غير متاحة الآن.',
      _ => 'لا يمكن الإرسال الآن.',
    };
