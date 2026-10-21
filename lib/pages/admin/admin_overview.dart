import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../ui/widgets.dart';
import '../business/owner/business_dashboard_page.dart' show RevenueBars;
import 'admin_shell.dart';

class AdminOverviewPage extends ConsumerWidget {
  final ValueChanged<String> onGo;
  const AdminOverviewPage({super.key, required this.onGo});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ov = ref.watch(adminOverviewProvider);
    return ov.when(
      data: (o) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminOverviewProvider),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          TileGrid(children: [
            StatTile(label: 'المستخدمون', value: '${o.usersTotal}', icon: Icons.people_alt_outlined, hint: '${o.usersNew7} جدد هذا الأسبوع', onTap: () => onGo('users')),
            StatTile(label: 'طلبات 7 أيام', value: '${o.orders7}', icon: Icons.shopping_bag_outlined, color: Joy.accent, hint: money(o.revenue7)),
            StatTile(label: 'الدوائر التجارية', value: '${o.circlesActive}', icon: Icons.storefront_outlined, hint: '${o.circlesOwned} مملوكة · ${o.circlesInactive} موقوفة', onTap: () => onGo('biz')),
            StatTile(label: 'طلبات ملكية', value: '${o.claims}', icon: Icons.fact_check_outlined, color: o.claims > 0 ? Joy.warning : Joy.textMuted, hint: 'بانتظار القرار', onTap: () => onGo('biz')),
            // توثيق الدوائر: العدد بانتظار القرار (كهرماني حين يوجد) ومستويات الاكتمال؛ اللمسة تفتح قسم «التوثيق» في الدوائر
            StatTile(
              key: const Key('tile-verifications'),
              label: 'توثيق بانتظار القرار',
              value: '${o.pendingVerifications}',
              icon: Icons.verified_outlined,
              color: o.pendingVerifications > 0 ? Joy.warning : Joy.textMuted,
              hint: 'منشورة ${o.tiers.published} · مكتملة ${o.tiers.complete} · موثّقة ${o.tiers.verified} · نشطة ${o.tiers.active}',
              onTap: () {
                ref.read(adminBizSegmentProvider.notifier).state = 'verifications';
                onGo('biz');
              },
            ),
            StatTile(label: 'بلاغات مفتوحة', value: o.reportsAvailable ? '${o.reportsOpen}' : '—', icon: Icons.flag_outlined, color: o.reportsOpen > 0 ? Joy.danger : Joy.textMuted, hint: o.reportsAvailable ? 'تحتاج مراجعة' : 'جدول البلاغات غير متاح', onTap: () => onGo('reports')),
            StatTile(label: 'أرصدة المحافظ', value: money(o.walletBalance), icon: Icons.account_balance_wallet_outlined, color: Joy.success, hint: '${o.walletAccounts} محفظة', onTap: () => onGo('finance')),
            StatTile(label: 'حسابات موقوفة', value: '${o.usersSuspended}', icon: Icons.block_rounded, color: o.usersSuspended > 0 ? Joy.danger : Joy.textMuted, hint: '${o.admins} مدير نظام'),
            StatTile(label: 'الشحن التجريبي', value: o.testTopup ? 'مفعّل' : 'معطّل', icon: Icons.science_outlined, color: o.testTopup ? Joy.warning : Joy.textMuted, hint: 'من الإعدادات', onTap: () => onGo('settings')),
          ]),
          const SizedBox(height: 16),
          const SectionTitle('الطلبات والإيرادات · آخر 14 يوماً'),
          JoyCard(child: RevenueBars(daily: [for (final d in o.daily) (day: d.day, orders: d.orders, revenue: d.revenue)])),
          const SizedBox(height: 8),
          const SectionTitle('مستخدمون جدد يومياً'),
          JoyCard(child: _UsersBars(daily: o.daily)),
          const SizedBox(height: 8),
          const SectionTitle('الخادم'),
          JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kvRow('Node', o.server['node']?.toString() ?? ''),
            kvRow('مدة التشغيل', '${((o.server['uptimeSec'] as num?) ?? 0) ~/ 60} دقيقة'),
            kvRow('جدول البلاغات', o.server['reportsTable']?.toString() ?? 'غير موجود'),
            kvRow('جدول الحظر', o.server['blocksTable']?.toString() ?? 'غير موجود'),
            kvRow('الجداول', (o.server['tables'] as List?)?.join('، ') ?? ''),
          ])),
          const SizedBox(height: 8),
          const SectionTitle('النسخ الاحتياطي'),
          const _BackupCard(),
        ]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminOverviewProvider)),
    );
  }
}

class _UsersBars extends StatelessWidget {
  final List<({DateTime day, int users, int orders, int revenue})> daily;
  const _UsersBars({required this.daily});
  @override
  Widget build(BuildContext context) {
    final max = daily.fold<int>(0, (m, d) => d.users > m ? d.users : m);
    return SizedBox(
      height: 110,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in daily)
          Expanded(child: Tooltip(message: '${d.day.day}/${d.day.month}: ${d.users}', child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('${d.users}', style: const TextStyle(fontSize: 9.5, color: Joy.textMuted, height: 1)),
            const SizedBox(height: 2),
            Container(height: max == 0 ? 2 : 2 + 70 * d.users / max, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: d.users == 0 ? Joy.line : Joy.success, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
            const SizedBox(height: 4),
            Text('${d.day.day}', style: const TextStyle(fontSize: 9.5, color: Joy.textMuted, height: 1)),
          ]))),
      ]),
    );
  }
}

/// بطاقة النسخ الاحتياطي: تُترجم /adminapi/backups إلى ثلاث حالات (لم يُثبَّت، سليم وحديث، قديم أو فاشل بنص الخطأ)،
/// سطراً لتمرين الاستعادة الأسبوعي، وتلميحاً كهرمانياً حين لا توجد نسخة خارج الخادم.
class _BackupCard extends ConsumerWidget {
  const _BackupCard();
  static String _hours(double? h) => h == null ? '—' : h < 1 ? 'قبل أقل من ساعة' : 'قبل ${h.round()} ساعة';
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(adminBackupsProvider);
    return JoyCard(key: const Key('backup-card'), child: b.when(
      loading: () => const Text('جارٍ قراءة حالة النسخ…', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
      error: (e, _) => Text('تعذر قراءة حالة النسخ: ${e.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), '')}', key: const Key('backup-state'), style: const TextStyle(color: Joy.danger, fontSize: 13)),
      data: (i) {
        final String state;
        final Color color;
        if (!i.installed) {
          state = 'لم يُثبَّت بعد. شغّل server/install-backup.sh على الخادم مرة واحدة (docs/ops-backup.md)';
          color = Joy.warning;
        } else if (i.ok && !i.stale) {
          state = 'آخر نسخة ${_hours(i.ageHours)} · قاعدة البيانات ${i.dbSizeText} · الوسائط ${i.mediaFiles} ملفاً · خارج الخادم: ${i.offsite ? 'نعم' : 'لا'}';
          color = Joy.text;
        } else if (!i.ok) {
          state = 'فشلت آخر نسخة (${_hours(i.ageHours)}): ${i.error ?? 'خطأ غير معروف'}';
          color = Joy.danger;
        } else {
          state = 'آخر نسخة ناجحة قديمة (${_hours(i.ageHours)}) والمفترض كل ليلة؛ افحص systemctl list-timers وسجل backup.log على الخادم';
          color = Joy.danger;
        }
        final String drill;
        final Color drillColor;
        if (i.drillOk == null) {
          drill = 'لم يُجرَ تمرين استعادة بعد';
          drillColor = Joy.warning;
        } else if (i.drillOk == true) {
          drill = 'آخر تمرين استعادة: ناجح قبل ${i.drillAgeDays ?? 0} يوماً';
          drillColor = i.drillStale ? Joy.warning : Joy.textMuted;
        } else {
          drill = 'آخر تمرين استعادة: فشل قبل ${i.drillAgeDays ?? 0} يوماً${i.drillError != null ? ' · ${i.drillError}' : ''}';
          drillColor = Joy.danger;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(state, key: const Key('backup-state'), style: TextStyle(color: color, fontSize: 13.5, height: 1.5)),
          if (i.installed) ...[
            const SizedBox(height: 6),
            Text(drill, key: const Key('backup-drill'), style: TextStyle(color: drillColor, fontSize: 12.5, height: 1.4)),
            if (i.dumpsKept > 0) kvRow('نسخ القاعدة المحفوظة على الخادم', '${i.dumpsKept}'),
            if (!i.offsite)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(i.offsiteError != null ? 'فشل النسخ خارج الخادم: ${i.offsiteError}' : 'لا نسخة خارج الخادم: اضبط BACKUP_RCLONE_REMOTE أو BACKUP_SSH_TARGET', key: const Key('backup-offsite-hint'), style: const TextStyle(color: Joy.sunText, fontSize: 12.5, height: 1.4)),
              ),
          ],
        ]);
      },
    ));
  }
}

/// سجل الإجراءات الإدارية.
class AdminAuditPage extends ConsumerWidget {
  const AdminAuditPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(adminAuditProvider);
    return audit.when(
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.history_rounded, title: 'لا إجراءات مسجّلة بعد')
          : ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [
                for (final (i, a) in list.indexed)
                  ListRow(
                    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.history_rounded, color: Joy.textMuted, size: 20)),
                    title: Text(a.label),
                    subtitle: Text('${a.admin?.nickname ?? a.adminId} · ${a.target ?? ''}${a.details.isNotEmpty ? ' · ${a.details.entries.map((e) => '${e.key}: ${e.value}').join('، ')}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(timeAgo(a.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                    divider: i < list.length - 1,
                  ),
              ])),
            ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminAuditProvider)),
    );
  }
}
