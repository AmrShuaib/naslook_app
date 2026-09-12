import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_biz.dart';
import 'admin_content.dart';
import 'admin_finance.dart';
import 'admin_overview.dart';
import 'admin_reports.dart';
import 'admin_settings.dart';
import 'admin_users.dart';

/// أقسام لوحة الإدارة.
const adminSections = [
  ('overview', 'نظرة عامة', Icons.space_dashboard_outlined),
  ('users', 'المستخدمون', Icons.people_alt_outlined),
  ('reports', 'البلاغات', Icons.flag_outlined),
  ('biz', 'الدوائر التجارية', Icons.storefront_outlined),
  ('finance', 'المالية', Icons.account_balance_wallet_outlined),
  ('content', 'المحتوى', Icons.inventory_2_outlined),
  ('settings', 'الإعدادات', Icons.tune_rounded),
  ('audit', 'سجل الإجراءات', Icons.history_rounded),
];

/// رسالة خطأ مفهومة لعمليات الإدارة.
String adminErrText(Object e) {
  final s = e.toString();
  if (s.contains('admin-only')) return 'هذا الإجراء لمدير النظام فقط';
  if (s.contains('bad-code')) return 'رمز الإعداد غير صحيح';
  if (s.contains('already-set-up')) return 'تم إعداد الإدارة مسبقاً؛ اطلب من مدير حالي ترقيتك';
  if (s.contains('last-admin')) return 'لا يمكن سحب صلاحية آخر مدير';
  if (s.contains('insufficient-funds')) return 'رصيد المستخدم لا يكفي لهذا الخصم';
  if (s.contains('bad-amount')) return 'المبلغ غير مقبول';
  if (s.contains('not-found')) return 'غير موجود';
  if (s.contains('self')) return 'لا يمكنك تطبيق هذا على حسابك';
  if (s.contains('already-cancelled')) return 'ملغاة مسبقاً';
  return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
}

/// غلاف لوحة الإدارة: شريط جانبي على الشاشات العريضة وقائمة جانبية على الجوال، مع شاشات الإعداد الأول ورفض الوصول.
class AdminShell extends ConsumerStatefulWidget {
  final bool standalone;
  /// القسم الذي تُفتح عليه اللوحة (ترتيب [adminSections])؛ تستخدمه الإشعارات لفتح البلاغات أو الدوائر مباشرة.
  final int initialSection;
  const AdminShell({super.key, this.standalone = true, this.initialSection = 0});
  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  late int index = widget.initialSection.clamp(0, adminSections.length - 1);

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(adminStatusProvider);
    return status.when(
      data: (s) {
        if (s.setupRequired) return _SetupScreen(status: s, standalone: widget.standalone);
        if (!s.isAdmin) return _Forbidden(status: s, standalone: widget.standalone);
        return _Layout(index: index, onSelect: (i) => setState(() => index = i), status: s, standalone: widget.standalone);
      },
      loading: () => const Scaffold(backgroundColor: Joy.bg, body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(backgroundColor: Joy.bg, appBar: AppBar(title: const Text('لوحة الإدارة')), body: ErrorState(e, onRetry: () => ref.invalidate(adminStatusProvider))),
    );
  }
}

class _Layout extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final AdminStatus status;
  final bool standalone;
  const _Layout({required this.index, required this.onSelect, required this.status, required this.standalone});

  Widget _page(int i) => switch (adminSections[i].$1) {
        'overview' => AdminOverviewPage(onGo: (key) => onSelect(adminSections.indexWhere((s) => s.$1 == key))),
        'users' => const AdminUsersPage(),
        'reports' => const AdminReportsPage(),
        'biz' => const AdminBizPage(),
        'finance' => const AdminFinancePage(),
        'content' => const AdminContentPage(),
        'settings' => const AdminSettingsPage(),
        _ => const AdminAuditPage(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = status.user;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final title = adminSections[index].$2;
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إدارة Naslife', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text('لوحة التحكم', style: TextStyle(color: Joy.textMuted, fontSize: 11.5))])),
        ]),
      );
      final nav = ListView(padding: EdgeInsets.zero, children: [
        header,
        for (final (i, s) in adminSections.indexed)
          ListTile(
            selected: i == index,
            selectedTileColor: Joy.primarySoft,
            selectedColor: Joy.primary,
            leading: Icon(s.$3),
            title: Text(s.$2, style: TextStyle(fontWeight: i == index ? FontWeight.w700 : FontWeight.w500)),
            onTap: () { onSelect(i); if (!wide) Navigator.of(context).maybePop(); },
          ),
        const Divider(),
        if (me != null) ListTile(leading: ProfileAvatar(person: me, size: 36), title: Text(me.nickname), subtitle: Text(me.id, style: const TextStyle(fontSize: 11)), trailing: IconButton(tooltip: 'تسجيل الخروج', icon: const Icon(Icons.logout_rounded), onPressed: () => ref.read(appStateProvider.notifier).logout())),
        if (!standalone) ListTile(leading: const Icon(Icons.arrow_back_rounded), title: const Text('العودة إلى التطبيق'), onTap: () => Navigator.of(context).maybePop()),
      ]);
      if (wide) {
        return Scaffold(
          backgroundColor: Joy.bg,
          body: Row(children: [
            SizedBox(width: 260, child: Material(color: Joy.surface, child: Container(decoration: const BoxDecoration(border: Border(left: BorderSide(color: Joy.line))), child: nav))),
            Expanded(child: Column(children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(color: Joy.surface, border: Border(bottom: BorderSide(color: Joy.line))),
                child: Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const Spacer(), IconButton(tooltip: 'تحديث', onPressed: () => invalidateAdmin(ref), icon: const Icon(Icons.refresh_rounded))]),
              ),
              Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: _page(index)))),
            ])),
          ]),
        );
      }
      return Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: Text(title), actions: [IconButton(tooltip: 'تحديث', onPressed: () => invalidateAdmin(ref), icon: const Icon(Icons.refresh_rounded))]),
        drawer: Drawer(backgroundColor: Joy.surface, child: SafeArea(child: nav)),
        body: _page(index),
      );
    });
  }
}

class _SetupScreen extends ConsumerStatefulWidget {
  final AdminStatus status;
  final bool standalone;
  const _SetupScreen({required this.status, required this.standalone});
  @override
  ConsumerState<_SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<_SetupScreen> {
  final code = TextEditingController();
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('إعداد لوحة الإدارة'), leading: widget.standalone ? null : const BackButton()),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              const Icon(Icons.admin_panel_settings_rounded, size: 56, color: Joy.primary),
              const SizedBox(height: 12),
              const Text('لا يوجد مدير بعد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 8),
              Text('أدخل رمز الإعداد ليصبح حسابك ${widget.status.user?.nickname ?? ''} أول مدير للمنصة. الرمز مكتوب على الخادم في الملف /opt/naslife/ops/admin-setup-code ومطبوع في سجل التشغيل.', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, height: 1.6)),
              const SizedBox(height: 18),
              TextField(controller: code, textAlign: TextAlign.center, style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700), decoration: const InputDecoration(hintText: 'NL-XXXXXX-XXXXXX')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : () async {
                  setState(() => busy = true);
                  try {
                    await ref.read(apiClientProvider).adminSetup(code.text.trim());
                    invalidateAdmin(ref);
                    if (context.mounted) toast(context, 'أصبحت مدير النظام');
                  } catch (e) {
                    if (context.mounted) toast(context, adminErrText(e), error: true);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('تفعيل حسابي كمدير'),
              ),
              const SizedBox(height: 10),
              const Text('لعرض الرمز عبر SSH:\ncat /opt/naslife/ops/admin-setup-code', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12, fontFamily: 'monospace')),
            ]),
          ),
        ),
      );
}

class _Forbidden extends ConsumerWidget {
  final AdminStatus status;
  final bool standalone;
  const _Forbidden({required this.status, required this.standalone});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('لوحة الإدارة'), leading: standalone ? null : const BackButton()),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'هذه اللوحة لمديري النظام',
          subtitle: 'حسابك ${status.user?.nickname ?? ''} ليس مديراً. اطلب من مدير حالي ترقيتك من قسم المستخدمين.',
          action: OutlinedButton.icon(onPressed: () => ref.read(appStateProvider.notifier).logout(), icon: const Icon(Icons.logout_rounded, size: 18), label: const Text('تسجيل الخروج والدخول بحساب آخر')),
        ),
      );
}

/// بطاقة إحصاء مشتركة بين صفحات الإدارة.
class StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? hint;
  final VoidCallback? onTap;
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color = Joy.primary, this.hint, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Joy.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: color))),
            if (hint != null) Text(hint!, style: const TextStyle(color: Joy.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

/// شبكة بطاقات تتكيف مع العرض.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  const TileGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 560 ? 3 : 2;
        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

/// صف مفتاح/قيمة.
Widget kvRow(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Joy.textMuted, fontSize: 13))), Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13.5)))]),
    );
