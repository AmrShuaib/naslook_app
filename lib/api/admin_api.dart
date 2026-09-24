import 'biz_models.dart' show Biz;
import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';

Map<String, dynamic> _m(dynamic v) => asMap(v);
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
List<String> _strs(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];

/// حالة لوحة الإدارة للمستخدم الحالي.
class AdminStatus {
  final bool hasAdmin, setupRequired, isAdmin;
  final Person? user;
  final int admins;
  /// عند الإعداد الأول: آخر حرفين من رمز الإعداد الفعّال وتاريخه ومسار ملف admin-ids على الخادم.
  final String? setupHint, bootstrapFile;
  final DateTime? setupCodeCreatedAt;
  /// دور العضو في فريق العمل وصلاحياته ('*' = كل الصلاحيات).
  final String? role, roleName;
  final int level;
  final List<String> permissions;
  final String title, department;
  const AdminStatus({this.hasAdmin = false, this.setupRequired = false, this.isAdmin = false, this.user, this.admins = 0, this.setupHint, this.bootstrapFile, this.setupCodeCreatedAt, this.role, this.roleName, this.level = 0, this.permissions = const [], this.title = '', this.department = ''});
  factory AdminStatus.fromJson(Map m) => AdminStatus(hasAdmin: m['hasAdmin'] == true, setupRequired: m['setupRequired'] == true, isAdmin: m['isAdmin'] == true, user: m['user'] is Map ? Person.fromJson(_m(m['user'])) : null, admins: _i(m['admins']),
      setupHint: m['setupHint']?.toString(), bootstrapFile: m['bootstrapFile']?.toString(), setupCodeCreatedAt: _t(m['setupCodeCreatedAt']),
      role: m['role']?.toString(), roleName: m['roleName']?.toString(), level: _i(m['level']), permissions: m['permissions'] is List ? (m['permissions'] as List).map((e) => e.toString()).toList() : (m['isAdmin'] == true ? const ['*'] : const []),
      title: m['title']?.toString() ?? '', department: m['department']?.toString() ?? '');
  bool can(String perm) => permissions.contains('*') || permissions.contains(perm);
  bool get owner => permissions.contains('*');
}

/// دور في فريق العمل بصلاحياته.
class TeamRole {
  final String id, name, description;
  final int level, members;
  final List<String> permissions;
  final bool builtin;
  const TeamRole({required this.id, required this.name, this.description = '', this.level = 10, this.permissions = const [], this.builtin = false, this.members = 0});
  factory TeamRole.fromJson(Map m) => TeamRole(id: m['id'].toString(), name: m['name']?.toString() ?? '', description: m['description']?.toString() ?? '', level: _i(m['level']), permissions: (m['permissions'] as List? ?? const []).map((e) => e.toString()).toList(), builtin: m['builtin'] == true, members: _i(m['members']));
  bool get all => permissions.contains('*');
}

/// عضو فريق العمل.
class TeamMember {
  final Person user;
  final String roleId, roleName, title, department, managerName, mailbox;
  final String? managerId;
  final int level;
  final List<String> permissions;
  final bool active, legacy;
  final DateTime? since;
  const TeamMember({required this.user, required this.roleId, required this.roleName, this.level = 0, this.permissions = const [], this.title = '', this.department = '', this.managerId, this.managerName = '', this.active = true, this.mailbox = '', this.legacy = false, this.since});
  factory TeamMember.fromJson(Map m) => TeamMember(
        user: Person.fromJson(_m(m['user'])), roleId: m['roleId']?.toString() ?? '', roleName: m['roleName']?.toString() ?? '', level: _i(m['level']), permissions: (m['permissions'] as List? ?? const []).map((e) => e.toString()).toList(),
        title: m['title']?.toString() ?? '', department: m['department']?.toString() ?? '', managerId: m['managerId']?.toString(), managerName: m['managerName']?.toString() ?? '', active: m['active'] != false, mailbox: m['mailbox']?.toString() ?? '', legacy: m['legacy'] == true, since: _t(m['since']));
  String get id => user.id;
  String get displayName => user.nickname.isEmpty ? user.id : user.nickname;
}

class TeamPermission {
  final String key, group, label;
  const TeamPermission({required this.key, required this.group, required this.label});
  factory TeamPermission.fromJson(Map m) => TeamPermission(key: m['key'].toString(), group: m['group']?.toString() ?? '', label: m['label']?.toString() ?? '');
}

class TeamMe {
  final String? roleId, roleName;
  final int level;
  final List<String> permissions;
  final bool scopeAll;
  final List<String> scopeIds;
  const TeamMe({this.roleId, this.roleName, this.level = 0, this.permissions = const [], this.scopeAll = false, this.scopeIds = const []});
  factory TeamMe.fromJson(Map m) => TeamMe(roleId: m['roleId']?.toString(), roleName: m['roleName']?.toString(), level: _i(m['level']), permissions: (m['permissions'] as List? ?? const []).map((e) => e.toString()).toList(), scopeAll: m['scopeAll'] == true, scopeIds: (m['scopeIds'] as List? ?? const []).map((e) => e.toString()).toList());
  bool can(String perm) => permissions.contains('*') || permissions.contains(perm);
  bool get owner => permissions.contains('*');
}

class TeamInfo {
  final List<TeamMember> members;
  final List<TeamRole> roles;
  final List<String> departments;
  final TeamMe me;
  const TeamInfo({this.members = const [], this.roles = const [], this.departments = const [], this.me = const TeamMe()});
  factory TeamInfo.fromJson(Map m) => TeamInfo(members: asList(m['members']).map(TeamMember.fromJson).toList(), roles: asList(m['roles']).map(TeamRole.fromJson).toList(), departments: (m['departments'] as List? ?? const []).map((e) => e.toString()).toList(), me: TeamMe.fromJson(_m(m['me'])));
}

/// عقدة في الهيكل الإداري.
class TeamNode {
  final TeamMember member;
  final int depth;
  final List<TeamNode> reports;
  const TeamNode({required this.member, this.depth = 0, this.reports = const []});
  factory TeamNode.fromJson(Map m) => TeamNode(member: TeamMember.fromJson(m), depth: _i(m['depth']), reports: asList(m['reports']).map(TeamNode.fromJson).toList());
}

/// مهمة عمل.
class WorkTask {
  final String id, title, description, status, priority, department;
  final Person? assignee, creator;
  final DateTime? dueAt, createdAt, updatedAt, completedAt;
  final List<String> tags;
  final Map<String, dynamic>? related;
  final List<TaskCheck> checklist;
  final int comments;
  final bool overdue, canEdit, canUpdateStatus, mine;
  final List<TaskComment> commentList;
  final List<TaskEvent> events;
  const WorkTask({required this.id, required this.title, this.description = '', this.status = 'todo', this.priority = 'normal', this.department = '', this.assignee, this.creator, this.dueAt, this.createdAt, this.updatedAt, this.completedAt, this.tags = const [], this.related, this.checklist = const [], this.comments = 0, this.overdue = false, this.canEdit = false, this.canUpdateStatus = false, this.mine = false, this.commentList = const [], this.events = const []});
  factory WorkTask.fromJson(Map m) => WorkTask(
        id: m['id'].toString(), title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', status: m['status']?.toString() ?? 'todo', priority: m['priority']?.toString() ?? 'normal', department: m['department']?.toString() ?? '',
        assignee: m['assignee'] is Map ? Person.fromJson(_m(m['assignee'])) : null, creator: m['creator'] is Map ? Person.fromJson(_m(m['creator'])) : null,
        dueAt: _t(m['dueAt']), createdAt: _t(m['createdAt']), updatedAt: _t(m['updatedAt']), completedAt: _t(m['completedAt']),
        tags: (m['tags'] as List? ?? const []).map((e) => e.toString()).toList(), related: m['related'] is Map ? _m(m['related']) : null,
        checklist: asList(m['checklist']).map(TaskCheck.fromJson).toList(), comments: _i(m['comments']), overdue: m['overdue'] == true, canEdit: m['canEdit'] == true, canUpdateStatus: m['canUpdateStatus'] == true, mine: m['mine'] == true,
        commentList: asList(m['commentList']).map(TaskComment.fromJson).toList(), events: asList(m['events']).map(TaskEvent.fromJson).toList());
  int get checksDone => checklist.where((c) => c.done).length;
  bool get done => status == 'done';
}

class TaskCheck {
  final String text;
  final bool done;
  const TaskCheck({required this.text, this.done = false});
  factory TaskCheck.fromJson(Map m) => TaskCheck(text: m['text']?.toString() ?? '', done: m['done'] == true);
  Map<String, dynamic> toJson() => {'text': text, 'done': done};
}

class TaskComment {
  final String id, text;
  final Person user;
  final DateTime? createdAt;
  const TaskComment({required this.id, required this.user, required this.text, this.createdAt});
  factory TaskComment.fromJson(Map m) => TaskComment(id: m['id'].toString(), user: Person.fromJson(_m(m['user'])), text: m['text']?.toString() ?? '', createdAt: _t(m['createdAt']));
}

class TaskEvent {
  final String id, kind;
  final Person user;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  const TaskEvent({required this.id, required this.kind, required this.user, this.data = const {}, this.createdAt});
  factory TaskEvent.fromJson(Map m) => TaskEvent(id: m['id'].toString(), kind: m['kind']?.toString() ?? '', user: Person.fromJson(_m(m['user'])), data: _m(m['data']), createdAt: _t(m['createdAt']));
}

class TaskAssignee {
  final String id, nickname, roleName, title;
  final String? avatarUrl;
  const TaskAssignee({required this.id, required this.nickname, this.roleName = '', this.title = '', this.avatarUrl});
  factory TaskAssignee.fromJson(Map m) => TaskAssignee(id: m['id'].toString(), nickname: m['nickname']?.toString() ?? '', roleName: m['roleName']?.toString() ?? '', title: m['title']?.toString() ?? '', avatarUrl: m['avatarUrl']?.toString());
  Person get person => Person(id: id, nickname: nickname, avatarUrl: avatarUrl);
  String get displayName => nickname.isEmpty ? id : nickname;
}

class TaskList {
  final List<WorkTask> items;
  final Map<String, int> counts;
  final List<TaskAssignee> assignees;
  final bool canAssign, canManage;
  final String view;
  const TaskList({this.items = const [], this.counts = const {}, this.assignees = const [], this.canAssign = false, this.canManage = false, this.view = 'mine'});
  factory TaskList.fromJson(Map m) => TaskList(items: asList(m['items']).map(WorkTask.fromJson).toList(), counts: {for (final e in _m(m['counts']).entries) e.key: _i(e.value)}, assignees: asList(m['assignees']).map(TaskAssignee.fromJson).toList(), canAssign: m['canAssign'] == true, canManage: m['canManage'] == true, view: m['view']?.toString() ?? 'mine');
}

class TaskSummaryRow {
  final TaskAssignee member;
  final String department;
  final int open, overdue, review, done30;
  const TaskSummaryRow({required this.member, this.department = '', this.open = 0, this.overdue = 0, this.review = 0, this.done30 = 0});
  factory TaskSummaryRow.fromJson(Map m) => TaskSummaryRow(member: TaskAssignee.fromJson(m), department: m['department']?.toString() ?? '', open: _i(m['open']), overdue: _i(m['overdue']), review: _i(m['review']), done30: _i(m['done30']));
}

/// صندوق بريد مرئي للعضو.
class InboxMailbox {
  final String alias, address, kind, label;
  final String? ownerId;
  final int unread;
  const InboxMailbox({required this.alias, required this.address, required this.kind, required this.label, this.ownerId, this.unread = 0});
  factory InboxMailbox.fromJson(Map m) => InboxMailbox(alias: m['alias'].toString(), address: m['address']?.toString() ?? '', kind: m['kind']?.toString() ?? 'own', label: m['label']?.toString() ?? '', ownerId: m['ownerId']?.toString(), unread: _i(m['unread']));
}

class InboxInfo {
  final List<InboxMailbox> mailboxes;
  final String domain, myMailbox, receivingProvider;
  final bool domainVerified, canReply, canManage, receivingConfigured, aiEnabled, csat;
  final int received, totalUnread;
  final DateTime? lastReceivedAt;
  const InboxInfo({this.mailboxes = const [], this.domain = '', this.myMailbox = '', this.receivingProvider = 'generic', this.domainVerified = false, this.canReply = false, this.canManage = false, this.receivingConfigured = false, this.aiEnabled = false, this.csat = true, this.received = 0, this.totalUnread = 0, this.lastReceivedAt});
  factory InboxInfo.fromJson(Map m) { final r = _m(m['receiving']); return InboxInfo(mailboxes: asList(m['mailboxes']).map(InboxMailbox.fromJson).toList(), domain: m['domain']?.toString() ?? '', myMailbox: m['myMailbox']?.toString() ?? '', receivingProvider: r['provider']?.toString() ?? 'generic', aiEnabled: m['aiEnabled'] == true, csat: m['csat'] != false, domainVerified: m['domainVerified'] == true, canReply: m['canReply'] == true, canManage: m['canManage'] == true, receivingConfigured: r['configured'] == true, received: _i(r['received']), totalUnread: m['totalUnread'] == null ? asList(m['mailboxes']).fold(0, (s, b) => s + _i(b['unread'])) : _i(m['totalUnread']), lastReceivedAt: _t(r['lastReceivedAt'])); }
}

/// قالب رد جاهز.
class InboxTemplate {
  final String id, title, body, ownerId, ownerName;
  final bool shared;
  const InboxTemplate({required this.id, required this.title, required this.body, this.ownerId = '', this.ownerName = '', this.shared = true});
  factory InboxTemplate.fromJson(Map m) => InboxTemplate(id: m['id'].toString(), title: m['title']?.toString() ?? '', body: m['body']?.toString() ?? '', ownerId: m['ownerId']?.toString() ?? '', ownerName: m['ownerName']?.toString() ?? '', shared: m['shared'] != false);
}

class InboxThread {
  final String id, mailbox, subject, snippet, counterpart, counterpartName, lastDirection, assignedName, status;
  final String? assignedTo;
  final List<String> participants, tags;
  final DateTime? lastAt, snoozeUntil, closedAt;
  final int unread, messages;
  final bool archived, starred, snoozed, spam, ratingSent;
  final DateTime? ratingSentAt;
  const InboxThread({this.spam = false, this.ratingSent = false, this.ratingSentAt, required this.id, required this.mailbox, this.subject = '', this.snippet = '', this.counterpart = '', this.counterpartName = '', this.lastDirection = 'in', this.assignedName = '', this.status = 'open', this.assignedTo, this.participants = const [], this.tags = const [], this.lastAt, this.snoozeUntil, this.closedAt, this.unread = 0, this.messages = 0, this.archived = false, this.starred = false, this.snoozed = false});
  factory InboxThread.fromJson(Map m) => InboxThread(spam: m['spam'] == true, ratingSent: m['ratingSent'] == true, ratingSentAt: _t(m['ratingSentAt']), id: m['id'].toString(), mailbox: m['mailbox']?.toString() ?? '', subject: m['subject']?.toString() ?? '', snippet: m['snippet']?.toString() ?? '', counterpart: m['counterpart']?.toString() ?? '', counterpartName: m['counterpartName']?.toString() ?? '', lastDirection: m['lastDirection']?.toString() ?? 'in', assignedName: m['assignedName']?.toString() ?? '', status: m['status']?.toString() ?? 'open', assignedTo: m['assignedTo']?.toString(), participants: (m['participants'] as List? ?? const []).map((e) => e.toString()).toList(), tags: (m['tags'] as List? ?? const []).map((e) => e.toString()).toList(), lastAt: _t(m['lastAt']), snoozeUntil: _t(m['snoozeUntil']), closedAt: _t(m['closedAt']), unread: _i(m['unread']), messages: _i(m['messages']), archived: m['archived'] == true, starred: m['starred'] == true, snoozed: m['snoozed'] == true);
  String get who => counterpartName.isNotEmpty ? counterpartName : counterpart;
}

/// مرفق في رسالة.
class InboxAttachment {
  final String name, type;
  final String? downloadUrl;
  final int size;
  const InboxAttachment({required this.name, this.type = '', this.downloadUrl, this.size = 0});
  factory InboxAttachment.fromJson(Map m) => InboxAttachment(name: m['name']?.toString() ?? 'مرفق', type: m['type']?.toString() ?? '', downloadUrl: (m['downloadUrl'] ?? m['url'])?.toString(), size: _i(m['size']));
  Map<String, dynamic> toJson() => {'name': name, 'url': downloadUrl, 'type': type, 'size': size};
}

class InboxAddress {
  final String email, name;
  const InboxAddress({required this.email, this.name = ''});
  factory InboxAddress.fromJson(dynamic m) => m is Map ? InboxAddress(email: m['email']?.toString() ?? '', name: m['name']?.toString() ?? '') : InboxAddress(email: m.toString());
}

class InboxMessage {
  final String id, direction, subject, text, sentByName;
  final String? html, sentBy;
  final InboxAddress from;
  final List<InboxAddress> to, cc;
  final List<InboxAttachment> attachments;
  final bool read;
  final DateTime? createdAt;
  const InboxMessage({required this.id, required this.direction, required this.from, this.to = const [], this.cc = const [], this.subject = '', this.text = '', this.html, this.attachments = const [], this.read = true, this.sentBy, this.sentByName = '', this.createdAt});
  factory InboxMessage.fromJson(Map m) => InboxMessage(id: m['id'].toString(), direction: m['direction']?.toString() ?? 'in', from: InboxAddress.fromJson(m['from'] ?? const {}), to: (m['to'] as List? ?? const []).map(InboxAddress.fromJson).toList(), cc: (m['cc'] as List? ?? const []).map(InboxAddress.fromJson).toList(), subject: m['subject']?.toString() ?? '', text: m['text']?.toString() ?? '', html: m['html']?.toString(), attachments: asList(m['attachments']).map(InboxAttachment.fromJson).toList(), read: m['read'] != false, sentBy: m['sentBy']?.toString(), sentByName: m['sentByName']?.toString() ?? '', createdAt: _t(m['createdAt']));
  bool get outgoing => direction == 'out';
  bool get note => direction == 'note';
}

class InboxThreadDetail {
  final InboxThread thread;
  final String address, signature;
  final List<InboxMessage> messages;
  final InboxCustomer? customer;
  final List<InboxLinkedTask> tasks;
  final List<InboxViewer> viewers;
  /// مسودتي المحفوظة لهذه المحادثة (إن وُجدت)
  final Map<String, dynamic>? draft;
  final List<InboxOutboxItem> scheduled;
  const InboxThreadDetail({required this.thread, this.address = '', this.signature = '', this.messages = const [], this.customer, this.tasks = const [], this.viewers = const [], this.draft, this.scheduled = const []});
  factory InboxThreadDetail.fromJson(Map m) => InboxThreadDetail(thread: InboxThread.fromJson(m), address: m['address']?.toString() ?? '', signature: m['signature']?.toString() ?? '', messages: asList(m['messageList']).map(InboxMessage.fromJson).toList(), customer: m['customer'] is Map ? InboxCustomer.fromJson(m['customer'] as Map) : null, tasks: asList(m['tasks']).map(InboxLinkedTask.fromJson).toList(), viewers: asList(m['viewers']).map(InboxViewer.fromJson).toList(), draft: m['draft'] is Map ? _m(m['draft']) : null, scheduled: asList(m['scheduled']).map(InboxOutboxItem.fromJson).toList());
  String get draftText => draft?['text']?.toString() ?? '';
}

/// رسالة مجدولة في صندوق الصادر.
class InboxOutboxItem {
  final String id, mailbox, to, subject, text, status;
  final String? threadId, error;
  final DateTime? sendAt, sentAt, createdAt;
  const InboxOutboxItem({required this.id, this.mailbox = '', this.to = '', this.subject = '', this.text = '', this.status = 'queued', this.threadId, this.error, this.sendAt, this.sentAt, this.createdAt});
  factory InboxOutboxItem.fromJson(Map m) => InboxOutboxItem(id: m['id'].toString(), mailbox: m['mailbox']?.toString() ?? '', to: m['to']?.toString() ?? '', subject: m['subject']?.toString() ?? '', text: m['text']?.toString() ?? '', status: m['status']?.toString() ?? 'queued', threadId: m['threadId']?.toString(), error: m['error']?.toString(), sendAt: _t(m['sendAt']), sentAt: _t(m['sentAt']), createdAt: _t(m['createdAt']));
}

/// نتيجة بحث شامل: المحادثة ومقتطف من الرسالة المطابقة.
class InboxSearchHit {
  final InboxThread thread;
  final String excerpt, direction, messageId;
  final DateTime? at;
  const InboxSearchHit({required this.thread, this.excerpt = '', this.direction = 'in', this.messageId = '', this.at});
  factory InboxSearchHit.fromJson(Map m) { final x = m['match'] is Map ? _m(m['match']) : const <String, dynamic>{}; return InboxSearchHit(thread: InboxThread.fromJson(m), excerpt: x['excerpt']?.toString() ?? '', direction: x['direction']?.toString() ?? 'in', messageId: x['messageId']?.toString() ?? '', at: _t(x['at'])); }
}

/// مرسل محظور (بريد كامل أو @نطاق).
class InboxBlocked {
  final String pattern, reason, createdByName;
  final int hits;
  final DateTime? createdAt;
  const InboxBlocked({required this.pattern, this.reason = '', this.createdByName = '', this.hits = 0, this.createdAt});
  factory InboxBlocked.fromJson(Map m) => InboxBlocked(pattern: m['pattern'].toString(), reason: m['reason']?.toString() ?? '', createdByName: m['createdByName']?.toString() ?? '', hits: _i(m['hits']), createdAt: _t(m['createdAt']));
}

/// مؤشرات البريد: الإجمالي، لكل موظف، لكل صندوق، ويومياً.
class InboxAgentStat {
  final String id, name;
  final int replies, closed, firstResponseMin, ratings;
  final double? csat;
  const InboxAgentStat({required this.id, this.name = '', this.replies = 0, this.closed = 0, this.firstResponseMin = 0, this.ratings = 0, this.csat});
  factory InboxAgentStat.fromJson(Map m) => InboxAgentStat(id: m['id'].toString(), name: m['name']?.toString() ?? '', replies: _i(m['replies']), closed: _i(m['closed']), firstResponseMin: _i(m['firstResponseMin']), ratings: _i(m['ratings']), csat: (m['csat'] as num?)?.toDouble());
}

class InboxStats {
  final int days;
  final Map<String, dynamic> totals;
  final List<InboxAgentStat> agents;
  final List<Map<String, dynamic>> mailboxes, daily;
  const InboxStats({this.days = 30, this.totals = const {}, this.agents = const [], this.mailboxes = const [], this.daily = const []});
  factory InboxStats.fromJson(Map m) => InboxStats(days: _i(m['days']), totals: m['totals'] is Map ? _m(m['totals']) : const {}, agents: asList(m['agents']).map(InboxAgentStat.fromJson).toList(), mailboxes: asList(m['mailboxes']).map(_m).toList(), daily: asList(m['daily']).map(_m).toList());
  int n(String k) => _i(totals[k]);
  double? d(String k) => (totals[k] as num?)?.toDouble();
}

class InboxSettings {
  final String provider, token, resendUrl, genericUrl, domain, shared, sharedSignature, sharedAwayText, aiModel;
  final bool hasSecret, sharedAway, csat, hasAiKey;
  final int received, rejected;
  final DateTime? lastReceivedAt, sharedAwayUntil;
  final List<String> aiModels;
  const InboxSettings({this.provider = 'generic', this.token = '', this.resendUrl = '', this.genericUrl = '', this.domain = '', this.shared = '', this.sharedSignature = '', this.sharedAwayText = '', this.aiModel = 'claude-opus-5', this.hasSecret = false, this.sharedAway = false, this.csat = true, this.hasAiKey = false, this.received = 0, this.rejected = 0, this.lastReceivedAt, this.sharedAwayUntil, this.aiModels = const ['claude-opus-5']});
  factory InboxSettings.fromJson(Map m) => InboxSettings(aiModel: m['aiModel']?.toString() ?? 'claude-opus-5', csat: m['csat'] != false, hasAiKey: m['hasAiKey'] == true, aiModels: (m['aiModels'] as List? ?? const ['claude-opus-5']).map((e) => e.toString()).toList(), provider: m['provider']?.toString() ?? 'generic', token: m['token']?.toString() ?? '', resendUrl: m['resendUrl']?.toString() ?? '', genericUrl: m['genericUrl']?.toString() ?? '', domain: m['domain']?.toString() ?? '', shared: m['shared']?.toString() ?? '', sharedSignature: m['sharedSignature']?.toString() ?? '', sharedAwayText: m['sharedAwayText']?.toString() ?? '', hasSecret: m['hasSecret'] == true, sharedAway: m['sharedAway'] == true, received: _i(m['received']), rejected: _i(m['rejected']), lastReceivedAt: _t(m['lastReceivedAt']), sharedAwayUntil: _t(m['sharedAwayUntil']));
}

/// إعدادات العضو في البريد: توقيعه ورد الغياب لصندوقه.
class InboxMe {
  final String signature, awayText, mailbox, address;
  final bool away;
  final DateTime? awayUntil;
  const InboxMe({this.signature = '', this.awayText = '', this.mailbox = '', this.address = '', this.away = false, this.awayUntil});
  factory InboxMe.fromJson(Map m) => InboxMe(signature: m['signature']?.toString() ?? '', awayText: m['awayText']?.toString() ?? '', mailbox: m['mailbox']?.toString() ?? '', address: m['address']?.toString() ?? '', away: m['away'] == true, awayUntil: _t(m['awayUntil']));
}

/// بطاقة العميل: هل بريده مربوط بحساب في ناس لايف، وسجل مراسلاته.
class InboxCustomer {
  final String email, nickname;
  final String? userId, avatarUrl;
  final bool verified, suspended;
  final int threads;
  final DateTime? memberSince, since, lastAt;
  const InboxCustomer({this.email = '', this.nickname = '', this.userId, this.avatarUrl, this.verified = false, this.suspended = false, this.threads = 0, this.memberSince, this.since, this.lastAt});
  factory InboxCustomer.fromJson(Map m) => InboxCustomer(email: m['email']?.toString() ?? '', nickname: m['nickname']?.toString() ?? '', userId: m['userId']?.toString(), avatarUrl: m['avatarUrl']?.toString(), verified: m['verified'] == true, suspended: m['suspended'] == true, threads: _i(m['threads']), memberSince: _t(m['memberSince']), since: _t(m['since']), lastAt: _t(m['lastAt']));
  bool get known => userId != null && userId!.isNotEmpty;
}

/// مهمة مرتبطة بمحادثة بريد (مختصر).
class InboxLinkedTask {
  final String id, title, status, priority;
  final String? assigneeId;
  const InboxLinkedTask({required this.id, this.title = '', this.status = 'todo', this.priority = 'normal', this.assigneeId});
  factory InboxLinkedTask.fromJson(Map m) => InboxLinkedTask(id: m['id'].toString(), title: m['title']?.toString() ?? '', status: m['status']?.toString() ?? 'todo', priority: m['priority']?.toString() ?? 'normal', assigneeId: m['assigneeId']?.toString());
}

/// زميل يفتح المحادثة الآن (أو يكتب فيها).
class InboxViewer {
  final String id, name;
  final bool typing;
  const InboxViewer({required this.id, this.name = '', this.typing = false});
  factory InboxViewer.fromJson(Map m) => InboxViewer(id: m['id'].toString(), name: m['name']?.toString() ?? '', typing: m['typing'] == true);
}

/// قاعدة تلقائية: شروط على الصندوق/المرسل/الموضوع/النص وإجراءات عند الوصول.
class InboxRule {
  final String id, name;
  final bool enabled;
  final int position, hits;
  final Map<String, dynamic> conditions, actions;
  final DateTime? updatedAt;
  const InboxRule({required this.id, this.name = '', this.enabled = true, this.position = 0, this.hits = 0, this.conditions = const {}, this.actions = const {}, this.updatedAt});
  factory InboxRule.fromJson(Map m) => InboxRule(id: m['id'].toString(), name: m['name']?.toString() ?? '', enabled: m['enabled'] != false, position: _i(m['position']), hits: _i(m['hits']), conditions: m['conditions'] is Map ? _m(m['conditions']) : const {}, actions: m['actions'] is Map ? _m(m['actions']) : const {}, updatedAt: _t(m['updatedAt']));
  List<String> get tags => (actions['tags'] as List? ?? const []).map((e) => e.toString()).toList();
}

class InboxRuleAssignee {
  final String id, name, mailbox;
  const InboxRuleAssignee({required this.id, this.name = '', this.mailbox = ''});
  factory InboxRuleAssignee.fromJson(Map m) => InboxRuleAssignee(id: m['id'].toString(), name: m['name']?.toString() ?? '', mailbox: m['mailbox']?.toString() ?? '');
}

class InboxRules {
  final List<InboxRule> rules;
  final List<InboxRuleAssignee> assignees;
  final List<String> mailboxes;
  const InboxRules({this.rules = const [], this.assignees = const [], this.mailboxes = const []});
  factory InboxRules.fromJson(Map m) => InboxRules(rules: asList(m['rules']).map(InboxRule.fromJson).toList(), assignees: asList(m['assignees']).map(InboxRuleAssignee.fromJson).toList(), mailboxes: (m['mailboxes'] as List? ?? const []).map((e) => e.toString()).toList());
}

class TeamCandidate {
  final String id, nickname;
  final String? avatarUrl;
  final bool member;
  const TeamCandidate({required this.id, required this.nickname, this.avatarUrl, this.member = false});
  factory TeamCandidate.fromJson(Map m) => TeamCandidate(id: m['id'].toString(), nickname: m['nickname']?.toString() ?? '', avatarUrl: m['avatarUrl']?.toString(), member: m['member'] == true);
  Person get person => Person(id: id, nickname: nickname, avatarUrl: avatarUrl);
}

class AdminOverview {
  final int usersTotal, usersNew7, usersSuspended, admins, orders7, revenue7, circlesActive, circlesInactive, circlesOwned, claims, reportsOpen, walletAccounts, walletBalance;
  final int? usersActive7;
  final bool reportsAvailable, testTopup;
  final List<({DateTime day, int users, int orders, int revenue})> daily;
  final Map<String, dynamic> server;
  const AdminOverview({
    this.usersTotal = 0, this.usersNew7 = 0, this.usersSuspended = 0, this.admins = 0, this.usersActive7, this.orders7 = 0, this.revenue7 = 0, this.circlesActive = 0, this.circlesInactive = 0, this.circlesOwned = 0,
    this.claims = 0, this.reportsOpen = 0, this.reportsAvailable = false, this.walletAccounts = 0, this.walletBalance = 0, this.testTopup = false, this.daily = const [], this.server = const {},
  });
  factory AdminOverview.fromJson(Map m) {
    final u = _m(m['users']), o = _m(m['orders7']), c = _m(m['circles']), r = _m(m['reports']), w = _m(m['wallets']), s = _m(m['server']);
    return AdminOverview(
      usersTotal: _i(u['total']), usersNew7: _i(u['new7']), usersSuspended: _i(u['suspended']), admins: _i(u['admins']), usersActive7: u['active7'] == null ? null : _i(u['active7']),
      orders7: _i(o['count']), revenue7: _i(o['revenue']), circlesActive: _i(c['active']), circlesInactive: _i(c['inactive']), circlesOwned: _i(c['owned']), claims: _i(c['claims']),
      reportsOpen: _i(r['open']), reportsAvailable: r['available'] == true, walletAccounts: _i(w['accounts']), walletBalance: _i(w['balance']), testTopup: s['testTopup'] == true,
      daily: [for (final d in asList(m['daily'])) (day: DateTime.tryParse(d['day']?.toString() ?? '') ?? DateTime.now(), users: _i(d['users']), orders: _i(d['orders']), revenue: _i(d['revenue']))],
      server: s,
    );
  }
}

class AdminUser {
  final String id, nickname, bio, flagNote;
  final String? avatarUrl, email;
  final DateTime? createdAt, lastSeen;
  final bool deleted, isAdmin, suspended, emailVerified;
  final int? balance;
  const AdminUser({required this.id, this.nickname = '', this.avatarUrl, this.bio = '', this.flagNote = '', this.createdAt, this.lastSeen, this.deleted = false, this.isAdmin = false, this.suspended = false, this.balance, this.email, this.emailVerified = false});
  factory AdminUser.fromJson(Map m) => AdminUser(
        id: m['id'].toString(), nickname: m['nickname']?.toString() ?? '', avatarUrl: m['avatarUrl']?.toString(), bio: m['bio']?.toString() ?? '', flagNote: m['flagNote']?.toString() ?? '',
        createdAt: _t(m['createdAt']), lastSeen: _t(m['lastSeen']), deleted: m['deleted'] == true, isAdmin: m['isAdmin'] == true, suspended: m['suspended'] == true, balance: m['balance'] == null ? null : _i(m['balance']),
        email: (m['email']?.toString() ?? '').isEmpty ? null : m['email'].toString(), emailVerified: m['emailVerified'] == true,
      );
  Person get person => Person(id: id, nickname: nickname, avatarUrl: avatarUrl);
}

class AdminUserDetail {
  final AdminUser user;
  final int points, ordersCount, ordersTotal;
  final List<WalletTx> transactions;
  final List<({String id, String name, String category, bool active})> circles;
  final List<AdminReport> reportsAbout;
  final List<AdminAudit> actions;
  // البيانات الشخصية الكاملة: صف الحساب في النواة (بلا أسرار)، صف الملف، بُرُد الدخول، الاسترداد، الجلسات، وأعداد النشاط
  final Map<String, dynamic> personal, profile, counts;
  final List<AdminEmail> emails;
  final bool hasRecovery;
  final String? recoverySource;
  final AdminSessions? sessions;
  const AdminUserDetail({required this.user, this.points = 0, this.ordersCount = 0, this.ordersTotal = 0, this.transactions = const [], this.circles = const [], this.reportsAbout = const [], this.actions = const [],
      this.personal = const {}, this.profile = const {}, this.counts = const {}, this.emails = const [], this.hasRecovery = false, this.recoverySource, this.sessions});
  factory AdminUserDetail.fromJson(Map m) => AdminUserDetail(
        user: AdminUser.fromJson(_m(m['user'])), points: _i(m['points']), ordersCount: _i(_m(m['orders'])['count']), ordersTotal: _i(_m(m['orders'])['total']),
        transactions: asList(m['transactions']).map(WalletTx.fromJson).toList(),
        circles: [for (final c in asList(m['circles'])) (id: c['id'].toString(), name: c['name']?.toString() ?? '', category: c['category']?.toString() ?? '', active: c['active'] != false)],
        reportsAbout: asList(m['reportsAbout']).map(AdminReport.fromJson).toList(), actions: asList(m['actions']).map(AdminAudit.fromJson).toList(),
        personal: Map<String, dynamic>.from(_m(m['personal'])), profile: Map<String, dynamic>.from(_m(m['profile'])), counts: Map<String, dynamic>.from(_m(m['counts'])),
        emails: asList(m['emails']).map(AdminEmail.fromJson).toList(), hasRecovery: _m(m['recovery'])['hasPhrase'] == true, recoverySource: _m(m['recovery'])['source']?.toString(),
        sessions: m['sessions'] is Map ? AdminSessions.fromJson(_m(m['sessions'])) : null,
      );
}

class AdminEmail {
  final String email;
  final bool verified;
  final DateTime? verifiedAt, createdAt;
  const AdminEmail({required this.email, this.verified = false, this.verifiedAt, this.createdAt});
  factory AdminEmail.fromJson(Map m) => AdminEmail(email: m['email']?.toString() ?? '', verified: m['verified'] == true, verifiedAt: _t(m['verifiedAt']), createdAt: _t(m['createdAt']));
}

class AdminSessions {
  final int count;
  final DateTime? last;
  final List<String> agents;
  const AdminSessions({this.count = 0, this.last, this.agents = const []});
  factory AdminSessions.fromJson(Map m) => AdminSessions(count: _i(m['count']), last: _t(m['last']), agents: [for (final a in (m['agents'] is List ? m['agents'] as List : const [])) if (a != null && a.toString().isNotEmpty) a.toString()]);
}

class AdminReport {
  final String? id, reporterId, targetId, reason, text;
  final Person? reporter, target;
  final DateTime? createdAt;
  final ({String action, String note, String? by, DateTime? at})? action;
  const AdminReport({this.id, this.reporterId, this.targetId, this.reason, this.text, this.reporter, this.target, this.createdAt, this.action});
  factory AdminReport.fromJson(Map m) {
    final a = m['action'] is Map ? _m(m['action']) : null;
    return AdminReport(
      id: m['id']?.toString(), reporterId: m['reporterId']?.toString(), targetId: m['targetId']?.toString(), reason: m['reason']?.toString(), text: m['text']?.toString(),
      reporter: m['reporter'] is Map ? Person.fromJson(_m(m['reporter'])) : null, target: m['target'] is Map ? Person.fromJson(_m(m['target'])) : null, createdAt: _t(m['createdAt']),
      action: a == null ? null : (action: a['action']?.toString() ?? '', note: a['note']?.toString() ?? '', by: a['by']?.toString(), at: _t(a['at'])),
    );
  }
}

class AdminReports {
  final bool available;
  final String? table;
  final List<AdminReport> items;
  final int? blocks;
  const AdminReports({this.available = false, this.table, this.items = const [], this.blocks});
  factory AdminReports.fromJson(Map m) => AdminReports(available: m['available'] == true, table: m['table']?.toString(), items: asList(m['items']).map(AdminReport.fromJson).toList(), blocks: m['blocks'] == null ? null : _i(m['blocks']));
}

class AdminBiz {
  final String id, name, latin, category, sector;
  final bool active, verified;
  final String? ownerId;
  final Person? owner;
  final int orders, revenue, followers, items, views;
  final DateTime? createdAt;
  const AdminBiz({required this.id, required this.name, this.latin = '', required this.category, this.sector = '', this.active = true, this.verified = false, this.ownerId, this.owner, this.orders = 0, this.revenue = 0, this.followers = 0, this.items = 0, this.views = 0, this.createdAt});
  factory AdminBiz.fromJson(Map m) => AdminBiz(
        id: m['id'].toString(), name: m['name']?.toString() ?? '', latin: m['latin']?.toString() ?? '', category: m['category']?.toString() ?? 'brand', sector: m['sector']?.toString() ?? '', active: m['active'] != false, verified: m['verified'] == true,
        ownerId: m['ownerId']?.toString(), owner: m['owner'] is Map ? Person.fromJson(_m(m['owner'])) : null, orders: _i(m['orders']), revenue: _i(m['revenue']), followers: _i(m['followers']), items: _i(m['items']), views: _i(m['views']), createdAt: _t(m['createdAt']),
      );
}

class AdminFinance {
  final int accounts, balance, points;
  final List<({String kind, int count, int amount})> byKind;
  final List<({DateTime day, int topups, int purchases, int refunds})> daily;
  final List<({WalletTx tx, Person user})> recent;
  final List<({Person user, int balance})> topBalances;
  const AdminFinance({this.accounts = 0, this.balance = 0, this.points = 0, this.byKind = const [], this.daily = const [], this.recent = const [], this.topBalances = const []});
  factory AdminFinance.fromJson(Map m) {
    final t = _m(m['totals']);
    return AdminFinance(
      accounts: _i(t['accounts']), balance: _i(t['balance']), points: _i(t['points']),
      byKind: [for (final k in asList(m['byKind'])) (kind: k['kind']?.toString() ?? '', count: _i(k['count']), amount: _i(k['amount']))],
      daily: [for (final d in asList(m['daily'])) (day: DateTime.tryParse(d['day']?.toString() ?? '') ?? DateTime.now(), topups: _i(d['topups']), purchases: _i(d['purchases']), refunds: _i(d['refunds']))],
      recent: [for (final r in asList(m['recent'])) (tx: WalletTx.fromJson(r), user: Person.fromJson(_m(r['user'])))],
      topBalances: [for (final b in asList(m['topBalances'])) (user: Person.fromJson(_m(b['user'])), balance: _i(b['balance']))],
    );
  }
}

class AdminContent {
  final List<({String id, String title, Person host, DateTime? startsAt, String? placeName, bool cancelled, int sold})> events;
  final List<({String id, String title, Person seller, int price, String category, String status, DateTime? createdAt})> listings;
  final List<({String id, String name, String kind, int? members})> vessels;
  const AdminContent({this.events = const [], this.listings = const [], this.vessels = const []});
  factory AdminContent.fromJson(Map m) => AdminContent(
        events: [for (final e in asList(m['events'])) (id: e['id'].toString(), title: e['title']?.toString() ?? '', host: Person.fromJson(_m(e['host'])), startsAt: _t(e['startsAt']), placeName: e['placeName']?.toString(), cancelled: e['cancelled'] == true, sold: _i(e['sold']))],
        listings: [for (final l in asList(m['listings'])) (id: l['id'].toString(), title: l['title']?.toString() ?? '', seller: Person.fromJson(_m(l['seller'])), price: _i(l['price']), category: l['category']?.toString() ?? '', status: l['status']?.toString() ?? '', createdAt: _t(l['createdAt']))],
        vessels: [for (final v in asList(m['vessels'])) (id: v['id'].toString(), name: v['name']?.toString() ?? '', kind: v['kind']?.toString() ?? '', members: v['members'] == null ? null : _i(v['members']))],
      );
}

class AdminSettings {
  final bool testTopup, maintenance, setupCodePresent;
  final int maxTopup;
  final String announcement, supportHandle, supportEmail, bannedWords;
  final int reportThreshold;
  // التحويل بين المستخدمين والدفع داخل المحادثة (يُطفآن دائماً في iOS)، والقائمة الافتراضية للكلمات المحظورة
  final bool transfersEnabled, chatPaymentsEnabled, bannedWordsDefault;
  // السوق
  final double marketCommissionPct;
  final int spotlightPricePerDay, spotlightMaxDays, spotlightMaxActive;
  final bool marketReviewNewAccounts, marketBlockContacts;
  const AdminSettings({this.testTopup = false, this.maintenance = false, this.setupCodePresent = false, this.maxTopup = 10000000, this.announcement = '', this.supportHandle = '', this.supportEmail = '', this.bannedWords = '', this.reportThreshold = 3,
      this.transfersEnabled = true, this.chatPaymentsEnabled = true, this.bannedWordsDefault = true,
      this.marketCommissionPct = 0, this.spotlightPricePerDay = 2000, this.spotlightMaxDays = 30, this.spotlightMaxActive = 12, this.marketReviewNewAccounts = false, this.marketBlockContacts = true});
  factory AdminSettings.fromJson(Map m) => AdminSettings(testTopup: m['testTopup'] == true, maintenance: m['maintenance'] == true, setupCodePresent: m['setupCodePresent'] == true, maxTopup: _i(m['maxTopup']), announcement: m['announcement']?.toString() ?? '', supportHandle: m['supportHandle']?.toString() ?? '',
      bannedWords: m['bannedWords']?.toString() ?? '', reportThreshold: m['reportThreshold'] == null ? 3 : _i(m['reportThreshold']),
      supportEmail: m['supportEmail']?.toString() ?? '', transfersEnabled: m['transfersEnabled'] != false, chatPaymentsEnabled: m['chatPaymentsEnabled'] != false, bannedWordsDefault: m['bannedWordsDefault'] != false,
      marketCommissionPct: (m['marketCommissionPct'] as num?)?.toDouble() ?? 0, spotlightPricePerDay: m['spotlightPricePerDay'] == null ? 2000 : _i(m['spotlightPricePerDay']), spotlightMaxDays: m['spotlightMaxDays'] == null ? 30 : _i(m['spotlightMaxDays']), spotlightMaxActive: m['spotlightMaxActive'] == null ? 12 : _i(m['spotlightMaxActive']),
      marketReviewNewAccounts: m['marketReviewNewAccounts'] == true, marketBlockContacts: m['marketBlockContacts'] != false);
}

/// آخر إجراء إداري على عنصر في طابور الإشراف.
class ModerationAction {
  final String action, note;
  final Person? by;
  final DateTime? at;
  const ModerationAction({required this.action, this.note = '', this.by, this.at});
  factory ModerationAction.fromJson(Map m) => ModerationAction(action: m['action']?.toString() ?? '', note: m['note']?.toString() ?? '', by: m['by'] is Map ? Person.fromJson(_m(m['by'])) : null, at: _t(m['at']));
  String get label => moderationActionLabel(action);
}

String moderationActionLabel(String a) => switch (a) { 'hide' => 'أُخفي', 'restore' => 'أُعيد إظهاره', 'suspend-owner' => 'أُوقف الناشر', 'dismiss' => 'تُجوهل', _ => a };

/// عنصر محتوى مُبلَّغ عنه (بلاغاته مجمّعة) في طابور الإشراف (server/safety.js).
class ModerationItem {
  final String targetType, targetId, typeName, status;
  final int reports;
  final List<String> reasons;
  final Person? owner;
  final String? title, text, mediaUrl, bizId, listingId, wantedId, vesselId, parentId;
  final DateTime? firstAt, lastAt;
  final ModerationAction? action;
  const ModerationItem({required this.targetType, required this.targetId, this.typeName = '', this.status = 'visible', this.reports = 0, this.reasons = const [], this.owner, this.title, this.text, this.mediaUrl,
      this.bizId, this.listingId, this.wantedId, this.vesselId, this.parentId, this.firstAt, this.lastAt, this.action});
  factory ModerationItem.fromJson(Map m) => ModerationItem(
        targetType: m['targetType']?.toString() ?? '', targetId: m['targetId']?.toString() ?? '', typeName: m['typeName']?.toString() ?? '',
        status: m['status']?.toString() ?? (m['hidden'] == true ? 'hidden' : 'visible'), reports: _i(m['reports']),
        reasons: [for (final r in _strs(m['reasons'])) if (r.isNotEmpty) r],
        owner: m['owner'] is Map ? Person.fromJson(_m(m['owner'])) : null,
        title: m['title']?.toString(), text: m['text']?.toString(), mediaUrl: m['mediaUrl']?.toString(),
        bizId: m['bizId']?.toString(), listingId: m['listingId']?.toString(), wantedId: m['wantedId']?.toString(), vesselId: m['vesselId']?.toString(), parentId: m['parentId']?.toString(),
        firstAt: _t(m['firstAt']), lastAt: _t(m['lastAt']), action: m['action'] is Map ? ModerationAction.fromJson(_m(m['action'])) : null,
      );
  bool get hidden => status == 'hidden';
  bool get missing => status == 'missing';
  /// مفتاح ثابت للواجهة والاختبارات.
  String get key => '$targetType-$targetId';
}

class ModerationQueue {
  final String status;
  final int open, threshold;
  final List<ModerationItem> items;
  final List<({String id, String name})> types;
  const ModerationQueue({this.status = 'open', this.open = 0, this.threshold = 3, this.items = const [], this.types = const []});
  factory ModerationQueue.fromJson(Map m) => ModerationQueue(
        status: m['status']?.toString() ?? 'open', open: _i(m['open']), threshold: m['threshold'] == null ? 3 : _i(m['threshold']),
        items: asList(m['items']).map(ModerationItem.fromJson).toList(),
        types: [for (final t in asList(m['types'])) (id: t['id'].toString(), name: t['name']?.toString() ?? t['id'].toString())],
      );
}

class AdminAudit {
  final String id, adminId, action;
  final String? target;
  final Map<String, dynamic> details;
  final DateTime? createdAt;
  final Person? admin;
  const AdminAudit({required this.id, required this.adminId, required this.action, this.target, this.details = const {}, this.createdAt, this.admin});
  factory AdminAudit.fromJson(Map m) => AdminAudit(id: m['id'].toString(), adminId: m['adminId']?.toString() ?? '', action: m['action']?.toString() ?? '', target: m['target']?.toString(), details: _m(m['details']), createdAt: _t(m['createdAt']), admin: m['admin'] is Map ? Person.fromJson(_m(m['admin'])) : null);
  String get label => switch (action) {
        'setup.first-admin' => 'إعداد أول مدير', 'wallet.credit' => 'إضافة رصيد', 'wallet.debit' => 'خصم رصيد', 'user.suspend' => 'إيقاف حساب', 'user.unsuspend' => 'إعادة تفعيل حساب',
        'admin.grant' => 'ترقية إلى مدير', 'admin.revoke' => 'سحب صلاحية مدير', 'report.ignore' => 'تجاهل بلاغ', 'report.warn' => 'تحذير بعد بلاغ', 'report.suspend' => 'إيقاف بعد بلاغ',
        'biz.update' => 'تعديل دائرة تجارية', 'claim.approve' => 'قبول طلب ملكية', 'claim.reject' => 'رفض طلب ملكية', 'finance.export' => 'تصدير مالي', 'event.cancel' => 'إلغاء فعالية', 'market.hide' => 'إخفاء إعلان', 'settings.update' => 'تعديل الإعدادات', _ => action };
}

/// إعدادات خدمة البريد (server/mail.js)؛ الأسرار تصل مقنّعة ويُعاد إرسال القناع للإبقاء عليها.
class AdminMailSettings {
  final String provider, host, user, pass, apiKey, from, fromName, replyTo;
  final int port;
  final bool secure, hasPass, hasApiKey, configured;
  const AdminMailSettings({this.provider = 'off', this.host = '', this.port = 587, this.secure = false, this.user = '', this.pass = '', this.apiKey = '', this.from = '', this.fromName = '', this.replyTo = '', this.hasPass = false, this.hasApiKey = false, this.configured = false});
  factory AdminMailSettings.fromJson(Map m) => AdminMailSettings(
        provider: m['provider']?.toString() ?? 'off', host: m['host']?.toString() ?? '', port: m['port'] == null ? 587 : _i(m['port']), secure: m['secure'] == true, user: m['user']?.toString() ?? '', pass: m['pass']?.toString() ?? '', apiKey: m['apiKey']?.toString() ?? '',
        from: m['from']?.toString() ?? '', fromName: m['fromName']?.toString() ?? '', replyTo: m['replyTo']?.toString() ?? '', hasPass: m['hasPass'] == true, hasApiKey: m['hasApiKey'] == true, configured: m['configured'] == true,
      );
}

/// سجل DNS مطلوب لتوثيق نطاق الإرسال.
class AdminDnsRecord {
  final String type, host, fqdn, value, status, source;
  final int? priority;
  final bool? dnsOk;
  final bool optional;
  const AdminDnsRecord({required this.type, required this.host, required this.fqdn, required this.value, this.status = 'pending', this.source = '', this.priority, this.dnsOk, this.optional = false});
  factory AdminDnsRecord.fromJson(Map m) => AdminDnsRecord(
        type: m['type']?.toString() ?? 'TXT', host: m['host']?.toString() ?? '@', fqdn: m['fqdn']?.toString() ?? '', value: m['value']?.toString() ?? '', status: m['status']?.toString() ?? 'pending', source: m['source']?.toString() ?? '',
        priority: m['priority'] == null ? null : _i(m['priority']), dnsOk: m['dnsOk'] is bool ? m['dnsOk'] as bool : null, optional: m['optional'] == true);
  bool get verified => status == 'verified';
}

/// نطاق الإرسال الرسمي (مثل admin@naslife.app) وحالته عند المزوّد.
class AdminMailDomain {
  final String name, local, sender, provider, status;
  final bool verified, fromApplied;
  final String? error;
  final DateTime? checkedAt, verifiedAt;
  final List<AdminDnsRecord> records;
  const AdminMailDomain({required this.name, required this.local, required this.sender, required this.provider, this.status = 'pending', this.verified = false, this.fromApplied = false, this.error, this.checkedAt, this.verifiedAt, this.records = const []});
  factory AdminMailDomain.fromJson(Map m) => AdminMailDomain(
        name: m['name']?.toString() ?? '', local: m['local']?.toString() ?? 'admin', sender: m['sender']?.toString() ?? '', provider: m['provider']?.toString() ?? '', status: m['status']?.toString() ?? 'pending',
        verified: m['verified'] == true, fromApplied: m['fromApplied'] == true, error: m['error']?.toString(), checkedAt: _t(m['checkedAt']), verifiedAt: _t(m['verifiedAt']), records: asList(m['records']).map(AdminDnsRecord.fromJson).toList());
  int get dnsFound => records.where((r) => r.dnsOk == true).length;
  int get dnsRequired => records.where((r) => !r.optional).length;
}

class AdminMailDomainInfo {
  final AdminMailDomain? domain;
  final String suggestedName, suggestedLocal, provider, from;
  final bool providerReady;
  const AdminMailDomainInfo({this.domain, this.suggestedName = 'naslife.app', this.suggestedLocal = 'admin', this.provider = 'off', this.from = '', this.providerReady = false});
  factory AdminMailDomainInfo.fromJson(Map m) => AdminMailDomainInfo(
        domain: m['domain'] is Map ? AdminMailDomain.fromJson(m['domain'] as Map) : null,
        suggestedName: asMap(m['suggested'])['name']?.toString() ?? 'naslife.app', suggestedLocal: asMap(m['suggested'])['local']?.toString() ?? 'admin',
        provider: m['provider']?.toString() ?? 'off', from: m['from']?.toString() ?? '', providerReady: m['providerReady'] == true);
}

/// سطر في سجل الإرسال.
class AdminMailEntry {
  final String id, to, subject, status;
  final String? tag, error, provider;
  final DateTime? at;
  const AdminMailEntry({required this.id, required this.to, required this.subject, required this.status, this.tag, this.error, this.provider, this.at});
  factory AdminMailEntry.fromJson(Map m) => AdminMailEntry(id: m['id'].toString(), to: m['to']?.toString() ?? '', subject: m['subject']?.toString() ?? '', status: m['status']?.toString() ?? '', tag: m['tag']?.toString(), error: m['error']?.toString(), provider: m['provider']?.toString(), at: _t(m['at']));
  bool get sent => status == 'sent';
}

class AdminMailLog {
  final List<AdminMailEntry> entries;
  final int sent30d, failed30d;
  const AdminMailLog({this.entries = const [], this.sent30d = 0, this.failed30d = 0});
  factory AdminMailLog.fromJson(Map m) => AdminMailLog(entries: asList(m['log']).map(AdminMailEntry.fromJson).toList(), sent30d: _i(m['sent30d']), failed30d: _i(m['failed30d']));
}

/// إعلان عام يظهر للمستخدمين (من الإعدادات).
class PublicSettings {
  final String announcement, supportHandle;
  final bool maintenance, testTopup;
  const PublicSettings({this.announcement = '', this.supportHandle = '', this.maintenance = false, this.testTopup = false});
  factory PublicSettings.fromJson(Map m) => PublicSettings(announcement: m['announcement']?.toString() ?? '', supportHandle: m['supportHandle']?.toString() ?? '', maintenance: m['maintenance'] == true, testTopup: m['testTopup'] == true);
}

/// مسارات لوحة الإدارة (server/admin.js).
extension AdminApi on ApiClient {
  Future<AdminStatus> adminStatus() async => AdminStatus.fromJson(await get('/adminapi/status'));
  Future<void> adminSetup(String code) => post('/adminapi/setup', {'code': code});
  Future<AdminOverview> adminOverview() async => AdminOverview.fromJson(await get('/adminapi/overview'));
  Future<List<AdminUser>> adminUsers({String q = '', String? filter}) async => asList(await getList('/adminapi/users', query: {if (q.isNotEmpty) 'q': q, if (filter != null) 'filter': filter})).map(AdminUser.fromJson).toList();
  Future<AdminUserDetail> adminUser(String id) async => AdminUserDetail.fromJson(await get('/adminapi/users/$id'));
  Future<int> adminCredit(String id, int halalas, {String note = ''}) async => _i((await post('/adminapi/users/$id/credit', {'amount': halalas, 'note': note}))['balance']);
  Future<void> adminSuspend(String id, {required bool suspended, String note = ''}) => post('/adminapi/users/$id/suspend', {'suspended': suspended, 'note': note});
  Future<void> adminGrant(String id, {required bool grant}) => post('/adminapi/users/$id/admin', {'grant': grant});
  /// تعديل ملف مستخدم من الإدارة: nickname، displayName، bio، isPublic، avatarUrl (null لإزالة الصورة)، email ('' لإزالة بريد الدخول).
  Future<AdminUser> adminUpdateUser(String id, Map<String, dynamic> fields) async => AdminUser.fromJson(asMap((await patch_('/adminapi/users/$id', fields))['user']));
  /// حذف نهائي من كل الجداول؛ [confirm] هو اسم المستخدم أو المعرّف كما كتبه المدير للتأكيد. يعيد عدد الصفوف المحذوفة لكل جدول.
  Future<Map<String, dynamic>> adminDeleteUser(String id, {required String confirm}) async => asMap((await delete('/adminapi/users/$id', body: {'confirm': confirm}))['report']);
  Future<AdminReports> adminReports({bool all = false}) async => AdminReports.fromJson(await get('/adminapi/reports', query: {'status': all ? 'all' : 'open'}));
  /// الخادم يأخذ المُبلَّغ عنه من صف البلاغ نفسه، فلا نرسل targetId.
  Future<void> adminReportAction(String id, {required String action, String note = ''}) => post('/adminapi/reports/$id/action', {'action': action, 'note': note});
  /// طابور الإشراف على بلاغات المحتوى (مفتوحة أو الكل، واختيارياً نوع واحد).
  Future<ModerationQueue> adminModeration({bool all = false, String? type}) async =>
      ModerationQueue.fromJson(await get('/adminapi/moderation', query: {'status': all ? 'all' : 'open', if (type != null && type.isNotEmpty) 'type': type}));
  /// إجراء على عنصر مُبلَّغ عنه: dismiss | hide | restore | suspend-owner.
  Future<({bool changed, String status})> adminModerate(String type, String id, {required String action, String note = ''}) async {
    final d = await post('/adminapi/moderation/$type/${Uri.encodeComponent(id)}', {'action': action, 'note': note});
    return (changed: d['changed'] == true, status: d['status']?.toString() ?? '');
  }
  Future<List<AdminBiz>> adminBiz() async => asList(await getList('/adminapi/biz')).map(AdminBiz.fromJson).toList();
  Future<void> adminBizUpdate(String id, {bool? verified, bool? active, String? ownerId, bool clearOwner = false}) => post('/adminapi/biz/$id', {if (verified != null) 'verified': verified, if (active != null) 'active': active, if (ownerId != null || clearOwner) 'ownerId': ownerId});
  Future<List<Map<String, dynamic>>> adminClaims() async => asList(await getList('/adminapi/claims'));
  Future<void> adminClaimDecide(String bizId, String userId, {required bool approve}) => post('/adminapi/claims/$bizId/$userId/${approve ? 'approve' : 'reject'}', const {});
  Future<AdminFinance> adminFinance({int days = 14}) async => AdminFinance.fromJson(await get('/adminapi/finance', query: {'days': '$days'}));
  String adminExportUrl({int days = 30, String? user, String? token}) => absolute('/adminapi/finance/export.csv?days=$days${user != null ? '&user=$user' : ''}${token != null ? '&token=${Uri.encodeQueryComponent(token)}' : ''}');
  Future<AdminContent> adminContent() async => AdminContent.fromJson(await get('/adminapi/content'));
  Future<void> adminCancelEvent(String id) => post('/adminapi/events/$id/cancel', const {});
  Future<void> adminHideListing(String id) => post('/adminapi/market/$id/hide', const {});
  Future<AdminSettings> adminSettings() async => AdminSettings.fromJson(await get('/adminapi/settings'));
  Future<AdminSettings> adminSaveSettings(Map<String, dynamic> patch) async => AdminSettings.fromJson(await post('/adminapi/settings', patch));
  Future<List<AdminAudit>> adminAudit({int limit = 100}) async => asList(await getList('/adminapi/audit', query: {'limit': '$limit'})).map(AdminAudit.fromJson).toList();
  Future<List<({Person user, String grantedBy, DateTime? since})>> adminAdmins() async => [for (final a in asList(await getList('/adminapi/admins'))) (user: Person.fromJson(_m(a['user'])), grantedBy: a['grantedBy']?.toString() ?? '', since: _t(a['since']))];
  Future<PublicSettings> publicSettings() async => PublicSettings.fromJson(await get('/settings/public'));
  // ---- خدمة البريد (server/mail.js)
  Future<AdminMailSettings> adminMail() async => AdminMailSettings.fromJson(await get('/adminapi/mail'));
  Future<AdminMailSettings> adminMailSave(Map<String, dynamic> patch) async => AdminMailSettings.fromJson(await put('/adminapi/mail', patch));
  /// يرسل رسالة تجريبية ويعيد معرّف الرسالة عند المزوّد إن وُجد.
  Future<String?> adminMailTest(String to) async => (await post('/adminapi/mail/test', {'to': to.trim()}))['id']?.toString();
  // ---- فريق العمل (server/team.js)
  Future<TeamInfo> adminTeam() async => TeamInfo.fromJson(await get('/adminapi/team'));
  Future<List<TeamNode>> adminTeamTree() async => asList((await get('/adminapi/team/tree'))['roots']).map(TeamNode.fromJson).toList();
  Future<List<TeamPermission>> adminTeamPermissions() async => asList(await getList('/adminapi/team/permissions')).map(TeamPermission.fromJson).toList();
  Future<List<TeamCandidate>> adminTeamSearch(String q) async => asList(await getList('/adminapi/team/search', query: {'q': q.trim()})).map(TeamCandidate.fromJson).toList();
  Future<TeamMember> adminTeamAdd(Map<String, dynamic> body) async => TeamMember.fromJson(await post('/adminapi/team/members', body));
  Future<TeamMember> adminTeamUpdate(String id, Map<String, dynamic> body) async => TeamMember.fromJson(await patch('/adminapi/team/members/$id', body));
  Future<void> adminTeamRemove(String id) => delete('/adminapi/team/members/$id');
  Future<TeamRole> adminRoleCreate(Map<String, dynamic> body) async => TeamRole.fromJson(await post('/adminapi/team/roles', body));
  Future<TeamRole> adminRoleUpdate(String id, Map<String, dynamic> body) async => TeamRole.fromJson(await patch('/adminapi/team/roles/$id', body));
  Future<void> adminRoleDelete(String id) => delete('/adminapi/team/roles/$id');
  // ---- مهام العمل (server/tasks.js)
  Future<TaskList> adminTasks({String view = 'mine', String? status, String? priority, String? assignee, String? q}) async =>
      TaskList.fromJson(await get('/adminapi/tasks', query: {'view': view, if (status != null && status.isNotEmpty) 'status': status, if (priority != null && priority.isNotEmpty) 'priority': priority, if (assignee != null && assignee.isNotEmpty) 'assignee': assignee, if (q != null && q.trim().isNotEmpty) 'q': q.trim()}));
  Future<WorkTask> adminTask(String id) async => WorkTask.fromJson(await get('/adminapi/tasks/$id'));
  Future<WorkTask> adminTaskCreate(Map<String, dynamic> body) async => WorkTask.fromJson(await post('/adminapi/tasks', body));
  Future<WorkTask> adminTaskUpdate(String id, Map<String, dynamic> body) async => WorkTask.fromJson(await patch('/adminapi/tasks/$id', body));
  Future<TaskComment> adminTaskComment(String id, String text) async => TaskComment.fromJson(await post('/adminapi/tasks/$id/comments', {'text': text.trim()}));
  Future<void> adminTaskDelete(String id) => delete('/adminapi/tasks/$id');
  Future<List<TaskSummaryRow>> adminTasksSummary() async => asList((await get('/adminapi/tasks/summary'))['members']).map(TaskSummaryRow.fromJson).toList();
  // ---- البريد الوارد (server/inbox.js)
  Future<InboxInfo> adminInboxMailboxes() async => InboxInfo.fromJson(await get('/adminapi/inbox/mailboxes'));
  Future<List<InboxThread>> adminInbox({required String mailbox, String folder = 'inbox', String? q, String? tag}) async => asList((await get('/adminapi/inbox', query: {'mailbox': mailbox, 'folder': folder, if (q != null && q.trim().isNotEmpty) 'q': q.trim(), if (tag != null && tag.isNotEmpty) 'tag': tag}))['threads']).map(InboxThread.fromJson).toList();
  /// الوسوم المستخدمة في صندوق مع عددها (لتصفية القائمة).
  Future<List<(String, int)>> adminInboxTags(String mailbox) async => [for (final t in asList((await get('/adminapi/inbox', query: {'mailbox': mailbox, 'folder': 'inbox'}))['tags'])) (t['tag'].toString(), _i(t['n']))];
  Future<List<InboxViewer>> adminInboxPresence(String id, {bool typing = false, bool leave = false}) async => asList((await post('/adminapi/inbox/threads/$id/presence', {if (typing) 'typing': true, if (leave) 'leave': true}))['others']).map(InboxViewer.fromJson).toList();
  Future<InboxMe> adminInboxMe() async => InboxMe.fromJson(await get('/adminapi/inbox/me'));
  Future<InboxMe> adminInboxMeSave(Map<String, dynamic> body) async => InboxMe.fromJson(await put('/adminapi/inbox/me', body));
  Future<InboxRules> adminInboxRules() async => InboxRules.fromJson(await get('/adminapi/inbox/rules'));
  Future<InboxRule> adminInboxRuleCreate(Map<String, dynamic> body) async => InboxRule.fromJson(await post('/adminapi/inbox/rules', body));
  Future<InboxRule> adminInboxRuleUpdate(String id, Map<String, dynamic> body) async => InboxRule.fromJson(await patch('/adminapi/inbox/rules/$id', body));
  Future<void> adminInboxRuleDelete(String id) => delete('/adminapi/inbox/rules/$id');
  Future<List<InboxRule>> adminInboxRuleTest({required String from, required String subject, String text = '', String? mailbox}) async => asList((await post('/adminapi/inbox/rules/test', {'from': from, 'subject': subject, 'text': text, if (mailbox != null) 'mailbox': mailbox}))['matches']).map(InboxRule.fromJson).toList();
  Future<InboxThreadDetail> adminInboxThread(String id) async => InboxThreadDetail.fromJson(await get('/adminapi/inbox/threads/$id'));
  Future<InboxThread> adminInboxUpdate(String id, Map<String, dynamic> body) async => InboxThread.fromJson(await patch('/adminapi/inbox/threads/$id', body));
  Future<Map<String, dynamic>> adminInboxReply(String id, {required String text, String? to, String? subject, List<InboxAttachment> attachments = const [], DateTime? sendAt}) => post('/adminapi/inbox/threads/$id/reply', {'text': text.trim(), if (to != null) 'to': to, if (subject != null) 'subject': subject, if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList(), if (sendAt != null) 'sendAt': sendAt.toUtc().toIso8601String()});
  Future<Map<String, dynamic>> adminInboxCompose({required String mailbox, required String to, required String subject, required String text, List<InboxAttachment> attachments = const [], DateTime? sendAt}) => post('/adminapi/inbox/compose', {'mailbox': mailbox, 'to': to.trim(), 'subject': subject.trim(), 'text': text.trim(), if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList(), if (sendAt != null) 'sendAt': sendAt.toUtc().toIso8601String()});
  Future<List<InboxSearchHit>> adminInboxSearch(String q) async => asList((await get('/adminapi/inbox/search', query: {'q': q.trim()}))['threads']).map(InboxSearchHit.fromJson).toList();
  Future<InboxThread> adminInboxSpam(String id, {bool undo = false, bool domain = false, bool block = true, String? reason}) async => InboxThread.fromJson(await post('/adminapi/inbox/threads/$id/spam', {if (undo) 'undo': true, if (domain) 'domain': true, if (!block) 'block': false, if (reason != null && reason.isNotEmpty) 'reason': reason}));
  Future<List<InboxBlocked>> adminInboxBlocked() async => asList((await get('/adminapi/inbox/blocked'))['blocked']).map(InboxBlocked.fromJson).toList();
  Future<void> adminInboxBlock(String pattern, {String reason = ''}) => post('/adminapi/inbox/blocked', {'pattern': pattern.trim(), 'reason': reason});
  Future<void> adminInboxUnblock(String pattern) => delete('/adminapi/inbox/blocked/${Uri.encodeComponent(pattern)}');
  Future<List<InboxOutboxItem>> adminInboxOutbox() async => asList((await get('/adminapi/inbox/outbox'))['items']).map(InboxOutboxItem.fromJson).toList();
  Future<void> adminInboxOutboxCancel(String id) => delete('/adminapi/inbox/outbox/$id');
  Future<List<Map<String, dynamic>>> adminInboxDrafts() async => asList((await get('/adminapi/inbox/drafts'))['drafts']).map(_m).toList();
  Future<void> adminInboxDraftSave({String? threadId, String text = '', String to = '', String subject = '', String mailbox = '', List<InboxAttachment> attachments = const []}) => put('/adminapi/inbox/drafts', {if (threadId != null) 'threadId': threadId, 'text': text, if (to.isNotEmpty) 'to': to, if (subject.isNotEmpty) 'subject': subject, if (mailbox.isNotEmpty) 'mailbox': mailbox, if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList()});
  Future<void> adminInboxDraftDelete({String? threadId}) => delete('/adminapi/inbox/drafts${threadId != null ? '?threadId=$threadId' : ''}');
  /// المساعد الذكي: kind = summary | reply
  Future<String> adminInboxAi(String id, String kind) async => (await post('/adminapi/inbox/threads/$id/ai', {'kind': kind}))['text']?.toString() ?? '';
  Future<InboxStats> adminInboxStats({int days = 30}) async => InboxStats.fromJson(await get('/adminapi/inbox/stats', query: {'days': '$days'}));
  Future<InboxMessage> adminInboxNote(String id, String text) async => InboxMessage.fromJson({...await post('/adminapi/inbox/threads/$id/notes', {'text': text.trim()}), 'from': const {}});
  Future<List<InboxTemplate>> adminInboxTemplates() async => asList((await get('/adminapi/inbox/templates'))['templates']).map(InboxTemplate.fromJson).toList();
  Future<InboxTemplate> adminInboxTemplateCreate({required String title, required String body, bool shared = true}) async => InboxTemplate.fromJson(await post('/adminapi/inbox/templates', {'title': title.trim(), 'body': body.trim(), 'shared': shared}));
  Future<InboxTemplate> adminInboxTemplateUpdate(String id, Map<String, dynamic> body) async => InboxTemplate.fromJson(await patch('/adminapi/inbox/templates/$id', body));
  Future<void> adminInboxTemplateDelete(String id) => delete('/adminapi/inbox/templates/$id');
  Future<String> adminInboxTemplateRender(String id, {String? threadId}) async => (await post('/adminapi/inbox/templates/$id/render', {if (threadId != null) 'threadId': threadId}))['text']?.toString() ?? '';
  Future<InboxSettings> adminInboxSettings() async => InboxSettings.fromJson(await get('/adminapi/inbox/settings'));
  Future<InboxSettings> adminInboxSettingsSave(Map<String, dynamic> body) async => InboxSettings.fromJson(await put('/adminapi/inbox/settings', body));
  Future<AdminMailDomainInfo> adminMailDomain() async => AdminMailDomainInfo.fromJson(await get('/adminapi/mail/domain'));
  Future<AdminMailDomainInfo> adminMailDomainStart({required String domain, String local = 'admin'}) async => AdminMailDomainInfo.fromJson(await post('/adminapi/mail/domain', {'domain': domain.trim(), 'local': local.trim()}));
  Future<AdminMailDomainInfo> adminMailDomainVerify() async => AdminMailDomainInfo.fromJson(await post('/adminapi/mail/domain/verify', const {}));
  Future<void> adminMailDomainRemove() => delete('/adminapi/mail/domain');
  Future<AdminMailLog> adminMailLog({int limit = 50}) async => AdminMailLog.fromJson(await get('/adminapi/mail/log', query: {'limit': '$limit'}));
}

// يُبقي الاستيراد مستخدماً للأنواع المشتركة في الواجهة
typedef AdminBizRef = Biz;
List<String> adminStrings(dynamic v) => _strs(v);
