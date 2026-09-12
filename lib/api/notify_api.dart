import 'client.dart';
import 'models.dart';

DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// إشعار داخل التطبيق من الخادم (server/notify.js): طلبات وحجوزات وتقييمات وتحويلات وإجراءات الإدارة.
class AppNotification {
  final String id, kind, title, body;
  final Map<String, dynamic> data;
  final DateTime? readAt, createdAt;
  const AppNotification({required this.id, required this.kind, required this.title, this.body = '', this.data = const {}, this.readAt, this.createdAt});
  bool get unread => readAt == null;
  String? str(String key) => data[key]?.toString();
  factory AppNotification.fromJson(Map m) => AppNotification(
        id: m['id']?.toString() ?? '', kind: m['kind']?.toString() ?? '', title: m['title']?.toString() ?? '', body: m['body']?.toString() ?? '',
        data: asMap(m['data']), readAt: _t(m['readAt']), createdAt: _t(m['createdAt']));
  AppNotification markRead() => AppNotification(id: id, kind: kind, title: title, body: body, data: data, readAt: readAt ?? DateTime.now(), createdAt: createdAt);
}

class NotifyPage {
  final List<AppNotification> items;
  final int unread;
  const NotifyPage({this.items = const [], this.unread = 0});
}

/// نتيجة الإشعار التجريبي: هل أُرسل دفع للمتصفح، ولماذا لا إن لم يُرسل.
class NotifyTestResult {
  final bool ok, pushReady;
  final int pushed, subscriptions;
  final String reason;
  const NotifyTestResult({this.ok = false, this.pushReady = false, this.pushed = 0, this.subscriptions = 0, this.reason = ''});
  factory NotifyTestResult.fromJson(Map m) => NotifyTestResult(ok: m['ok'] == true, pushReady: m['push'] == true, pushed: _i(m['pushed']), subscriptions: _i(m['subscriptions']), reason: m['reason']?.toString() ?? '');
}

extension NotifyApi on ApiClient {
  Future<NotifyPage> notifications({int limit = 50, DateTime? before}) async {
    final d = await get('/notify', query: {'limit': '$limit', if (before != null) 'before': before.toUtc().toIso8601String()});
    return NotifyPage(items: [for (final m in asList(d['items'])) AppNotification.fromJson(m)], unread: _i(d['unread']));
  }

  Future<int> notifyUnread() async => _i((await get('/notify/unread'))['unread']);

  /// يعلّم إشعارات بعينها (أو الكل) مقروءة ويعيد العدد المتبقي.
  Future<int> notifyRead({List<String> ids = const [], bool all = false}) async => _i((await post('/notify/read', all ? {'all': true} : {'ids': ids}))['unread']);

  Future<AppNotification> notification(String id) async => AppNotification.fromJson(await get('/notify/$id'));

  Future<void> deleteNotification(String id) => delete('/notify/$id');

  Future<NotifyTestResult> notifyTest() async => NotifyTestResult.fromJson(await post('/notify/test', const {}));
}
