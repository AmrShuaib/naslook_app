import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notify/message_sound.dart';
import 'notify_providers.dart';

import '../api/admin_api.dart';
import '../api/admin_blog_api.dart';
import '../api/models.dart';
import 'app_state.dart';

/// هل فُتح التطبيق في وضع الإدارة؟ يُحدَّد من الرابط عند الإقلاع:
/// المضيف admin.*، أو المسار /admin، أو الجزء #/admin.
bool detectAdminMode([Uri? uri]) {
  final u = uri ?? Uri.base;
  if (!kIsWeb && uri == null) return false;
  final host = u.host.toLowerCase();
  final path = u.path.toLowerCase();
  final frag = u.fragment.toLowerCase();
  return host.startsWith('admin.') || path == '/admin' || path.startsWith('/admin/') || frag == '/admin' || frag.startsWith('/admin/') || frag == 'admin' || u.queryParameters['admin'] == '1';
}

/// يُلتقط عند الإقلاع في main() قبل أن يعيد محرك Flutter كتابة الجزء (#/) من الرابط.
bool adminModeAtBoot = false;
void captureAdminMode() { adminModeAtBoot = detectAdminMode(); }

final adminModeProvider = StateProvider<bool>((_) => adminModeAtBoot || detectAdminMode());
final adminStatusProvider = FutureProvider<AdminStatus>((ref) => ref.watch(apiClientProvider).adminStatus());
final adminOverviewProvider = FutureProvider<AdminOverview>((ref) => ref.watch(apiClientProvider).adminOverview());
final adminUsersProvider = FutureProvider.family<List<AdminUser>, ({String q, String? filter})>((ref, k) => ref.watch(apiClientProvider).adminUsers(q: k.q, filter: k.filter));
final adminUserProvider = FutureProvider.family<AdminUserDetail, String>((ref, id) => ref.watch(apiClientProvider).adminUser(id));
final adminReportsProvider = FutureProvider.family<AdminReports, bool>((ref, all) => ref.watch(apiClientProvider).adminReports(all: all));
/// طابور الإشراف على بلاغات المحتوى: (الكل؟، النوع أو '' للكل).
final adminModerationProvider = FutureProvider.family<ModerationQueue, (bool, String)>((ref, a) => ref.watch(apiClientProvider).adminModeration(all: a.$1, type: a.$2));
final adminBizProvider = FutureProvider<List<AdminBiz>>((ref) => ref.watch(apiClientProvider).adminBiz());
final adminClaimsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) => ref.watch(apiClientProvider).adminClaims());
final adminFinanceProvider = FutureProvider<AdminFinance>((ref) => ref.watch(apiClientProvider).adminFinance());
final adminContentProvider = FutureProvider<AdminContent>((ref) => ref.watch(apiClientProvider).adminContent());
final adminSettingsProvider = FutureProvider<AdminSettings>((ref) => ref.watch(apiClientProvider).adminSettings());
final adminAuditProvider = FutureProvider<List<AdminAudit>>((ref) => ref.watch(apiClientProvider).adminAudit());
final adminAdminsProvider = FutureProvider<List<({Person user, String grantedBy, DateTime? since})>>((ref) => ref.watch(apiClientProvider).adminAdmins());
/// قائمة المدونة في لوحة الإدارة مفتاحها (البحث، النوع، الحالة).
final adminBlogProvider = FutureProvider.family<BlogAdminList, ({String q, String kind, String status})>((ref, k) => ref.watch(apiClientProvider).adminBlogList(q: k.q, kind: k.kind, status: k.status));
final adminBlogPostProvider = FutureProvider.family<BlogPost, String>((ref, id) => ref.watch(apiClientProvider).adminBlogGet(id));
/// إعدادات خدمة البريد وسجل الإرسال في لوحة الإدارة.
final adminMailProvider = FutureProvider<AdminMailSettings>((ref) => ref.watch(apiClientProvider).adminMail());
final adminMailLogProvider = FutureProvider<AdminMailLog>((ref) => ref.watch(apiClientProvider).adminMailLog());
final adminMailDomainProvider = FutureProvider<AdminMailDomainInfo>((ref) => ref.watch(apiClientProvider).adminMailDomain());
final adminTeamProvider = FutureProvider<TeamInfo>((ref) => ref.watch(apiClientProvider).adminTeam());
/// قائمة المهام بحسب العرض (mine | team | all) وفلتر الحالة: المفتاح "view|status".
final adminTasksProvider = FutureProvider.family<TaskList, String>((ref, key) { final parts = key.split('|'); return ref.watch(apiClientProvider).adminTasks(view: parts[0], status: parts.length > 1 ? parts[1] : null); });
final adminTaskProvider = FutureProvider.family<WorkTask, String>((ref, id) => ref.watch(apiClientProvider).adminTask(id));
final adminTasksSummaryProvider = FutureProvider<List<TaskSummaryRow>>((ref) => ref.watch(apiClientProvider).adminTasksSummary());
final adminInboxMailboxesProvider = FutureProvider<InboxInfo>((ref) => ref.watch(apiClientProvider).adminInboxMailboxes());
/// محادثات صندوق: المفتاح "mailbox|folder".
final adminInboxProvider = FutureProvider.family<List<InboxThread>, String>((ref, key) { final parts = key.split('|'); return ref.watch(apiClientProvider).adminInbox(mailbox: parts[0], folder: parts.length > 1 ? parts[1] : 'inbox', tag: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null); });
final adminInboxThreadProvider = FutureProvider.family<InboxThreadDetail, String>((ref, id) => ref.watch(apiClientProvider).adminInboxThread(id));
final adminInboxSettingsProvider = FutureProvider<InboxSettings>((ref) => ref.watch(apiClientProvider).adminInboxSettings());
final adminInboxTemplatesProvider = FutureProvider<List<InboxTemplate>>((ref) => ref.watch(apiClientProvider).adminInboxTemplates());
final adminInboxMeProvider = FutureProvider<InboxMe>((ref) => ref.watch(apiClientProvider).adminInboxMe());
final adminInboxRulesProvider = FutureProvider<InboxRules>((ref) => ref.watch(apiClientProvider).adminInboxRules());
/// وسوم الصندوق (للتصفية) حسب الصندوق.
final adminInboxTagsProvider = FutureProvider.family<List<(String, int)>, String>((ref, mailbox) => ref.watch(apiClientProvider).adminInboxTags(mailbox));
/// فاصل نبضة التواجد داخل المحادثة (null يعطّلها في الاختبارات).
final inboxPresenceIntervalProvider = Provider<Duration?>((_) => const Duration(seconds: 10));
/// مهلة الحفظ التلقائي للمسودات بعد آخر كتابة.
final inboxDraftDebounceProvider = Provider<Duration>((_) => const Duration(milliseconds: 1500));
final adminInboxStatsProvider = FutureProvider.family<InboxStats, int>((ref, days) => ref.watch(apiClientProvider).adminInboxStats(days: days));
final adminInboxOutboxProvider = FutureProvider<List<InboxOutboxItem>>((ref) => ref.watch(apiClientProvider).adminInboxOutbox());
final adminInboxBlockedProvider = FutureProvider<List<InboxBlocked>>((ref) => ref.watch(apiClientProvider).adminInboxBlocked());
/// فاصل تحديث عدّاد البريد الوارد (null يعطّل التحديث التلقائي في الاختبارات).
final inboxPollIntervalProvider = Provider<Duration?>((_) => const Duration(seconds: 30));
/// إجمالي غير المقروء في صناديق العضو: يُحدَّث دورياً، ويقرع الجرس عند الزيادة، ويظهر في شارة القسم وعنوان التبويب.
final inboxUnreadProvider = StateNotifierProvider.autoDispose<InboxUnreadNotifier, int>((ref) => InboxUnreadNotifier(ref));

class InboxUnreadNotifier extends StateNotifier<int> {
  final Ref ref;
  Timer? _timer;
  bool _primed = false;
  InboxUnreadNotifier(this.ref) : super(0) {
    refresh();
    final every = ref.read(inboxPollIntervalProvider);
    if (every != null) _timer = Timer.periodic(every, (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
  }
  Future<void> refresh() async {
    try {
      final info = await ref.read(apiClientProvider).adminInboxMailboxes();
      if (!mounted) return;
      final n = info.totalUnread;
      if (_primed && n > state && ref.read(messageSoundProvider)) MessageSound.play();
      _primed = true;
      state = n;
      SystemChrome.setApplicationSwitcherDescription(ApplicationSwitcherDescription(label: n > 0 ? '($n) إدارة ناس لايف' : 'إدارة ناس لايف', primaryColor: 0xFF0A6E78));
    } catch (_) {
      // بلا شبكة أو بلا صلاحية: نُبقي القيمة الحالية
    }
  }
}
final adminTeamTreeProvider = FutureProvider<List<TeamNode>>((ref) => ref.watch(apiClientProvider).adminTeamTree());
final adminTeamPermissionsProvider = FutureProvider<List<TeamPermission>>((ref) => ref.watch(apiClientProvider).adminTeamPermissions());
final publicSettingsProvider = FutureProvider<PublicSettings>((ref) => ref.watch(apiClientProvider).publicSettings());

void invalidateAdmin(WidgetRef ref) {
  for (final p in [adminStatusProvider, adminOverviewProvider, adminBizProvider, adminClaimsProvider, adminFinanceProvider, adminContentProvider, adminSettingsProvider, adminAuditProvider, adminAdminsProvider, adminMailProvider, adminMailLogProvider, adminMailDomainProvider, adminTeamProvider, adminTeamTreeProvider, adminTasksProvider, adminTasksSummaryProvider, adminInboxMailboxesProvider, adminInboxProvider, adminInboxTemplatesProvider, adminInboxMeProvider, adminInboxRulesProvider, adminInboxTagsProvider, adminInboxStatsProvider, adminInboxOutboxProvider, adminInboxBlockedProvider]) {
    ref.invalidate(p);
  }
  ref.invalidate(adminUsersProvider);
  ref.invalidate(adminBlogProvider);
  ref.invalidate(adminBlogPostProvider);
  ref.invalidate(adminUserProvider);
  ref.invalidate(adminReportsProvider);
  ref.invalidate(adminModerationProvider);
}
