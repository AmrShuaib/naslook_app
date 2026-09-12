import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/admin_api.dart';
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
final adminBizProvider = FutureProvider<List<AdminBiz>>((ref) => ref.watch(apiClientProvider).adminBiz());
final adminClaimsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) => ref.watch(apiClientProvider).adminClaims());
final adminFinanceProvider = FutureProvider<AdminFinance>((ref) => ref.watch(apiClientProvider).adminFinance());
final adminContentProvider = FutureProvider<AdminContent>((ref) => ref.watch(apiClientProvider).adminContent());
final adminSettingsProvider = FutureProvider<AdminSettings>((ref) => ref.watch(apiClientProvider).adminSettings());
final adminAuditProvider = FutureProvider<List<AdminAudit>>((ref) => ref.watch(apiClientProvider).adminAudit());
final adminAdminsProvider = FutureProvider<List<({Person user, String grantedBy, DateTime? since})>>((ref) => ref.watch(apiClientProvider).adminAdmins());
final publicSettingsProvider = FutureProvider<PublicSettings>((ref) => ref.watch(apiClientProvider).publicSettings());

void invalidateAdmin(WidgetRef ref) {
  for (final p in [adminStatusProvider, adminOverviewProvider, adminBizProvider, adminClaimsProvider, adminFinanceProvider, adminContentProvider, adminSettingsProvider, adminAuditProvider, adminAdminsProvider]) {
    ref.invalidate(p);
  }
  ref.invalidate(adminUsersProvider);
  ref.invalidate(adminUserProvider);
  ref.invalidate(adminReportsProvider);
}
