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
  const AdminStatus({this.hasAdmin = false, this.setupRequired = false, this.isAdmin = false, this.user, this.admins = 0});
  factory AdminStatus.fromJson(Map m) => AdminStatus(hasAdmin: m['hasAdmin'] == true, setupRequired: m['setupRequired'] == true, isAdmin: m['isAdmin'] == true, user: m['user'] is Map ? Person.fromJson(_m(m['user'])) : null, admins: _i(m['admins']));
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
  final String? avatarUrl;
  final DateTime? createdAt, lastSeen;
  final bool deleted, isAdmin, suspended;
  final int? balance;
  const AdminUser({required this.id, this.nickname = '', this.avatarUrl, this.bio = '', this.flagNote = '', this.createdAt, this.lastSeen, this.deleted = false, this.isAdmin = false, this.suspended = false, this.balance});
  factory AdminUser.fromJson(Map m) => AdminUser(
        id: m['id'].toString(), nickname: m['nickname']?.toString() ?? '', avatarUrl: m['avatarUrl']?.toString(), bio: m['bio']?.toString() ?? '', flagNote: m['flagNote']?.toString() ?? '',
        createdAt: _t(m['createdAt']), lastSeen: _t(m['lastSeen']), deleted: m['deleted'] == true, isAdmin: m['isAdmin'] == true, suspended: m['suspended'] == true, balance: m['balance'] == null ? null : _i(m['balance']),
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
  const AdminUserDetail({required this.user, this.points = 0, this.ordersCount = 0, this.ordersTotal = 0, this.transactions = const [], this.circles = const [], this.reportsAbout = const [], this.actions = const []});
  factory AdminUserDetail.fromJson(Map m) => AdminUserDetail(
        user: AdminUser.fromJson(_m(m['user'])), points: _i(m['points']), ordersCount: _i(_m(m['orders'])['count']), ordersTotal: _i(_m(m['orders'])['total']),
        transactions: asList(m['transactions']).map(WalletTx.fromJson).toList(),
        circles: [for (final c in asList(m['circles'])) (id: c['id'].toString(), name: c['name']?.toString() ?? '', category: c['category']?.toString() ?? '', active: c['active'] != false)],
        reportsAbout: asList(m['reportsAbout']).map(AdminReport.fromJson).toList(), actions: asList(m['actions']).map(AdminAudit.fromJson).toList(),
      );
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
  final String announcement, supportHandle, bannedWords;
  final int reportThreshold;
  const AdminSettings({this.testTopup = false, this.maintenance = false, this.setupCodePresent = false, this.maxTopup = 10000000, this.announcement = '', this.supportHandle = '', this.bannedWords = '', this.reportThreshold = 3});
  factory AdminSettings.fromJson(Map m) => AdminSettings(testTopup: m['testTopup'] == true, maintenance: m['maintenance'] == true, setupCodePresent: m['setupCodePresent'] == true, maxTopup: _i(m['maxTopup']), announcement: m['announcement']?.toString() ?? '', supportHandle: m['supportHandle']?.toString() ?? '',
      bannedWords: m['bannedWords']?.toString() ?? '', reportThreshold: m['reportThreshold'] == null ? 3 : _i(m['reportThreshold']));
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
  Future<AdminReports> adminReports({bool all = false}) async => AdminReports.fromJson(await get('/adminapi/reports', query: {'status': all ? 'all' : 'open'}));
  Future<void> adminReportAction(String id, {required String action, String note = '', String? targetId}) => post('/adminapi/reports/$id/action', {'action': action, 'note': note, if (targetId != null) 'targetId': targetId});
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
}

// يُبقي الاستيراد مستخدماً للأنواع المشتركة في الواجهة
typedef AdminBizRef = Biz;
List<String> adminStrings(dynamic v) => _strs(v);
