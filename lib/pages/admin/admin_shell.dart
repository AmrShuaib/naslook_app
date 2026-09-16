import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/client.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_biz.dart';
import 'admin_blog.dart';
import 'admin_content.dart';
import 'admin_finance.dart';
import 'admin_mail.dart';
import 'admin_overview.dart';
import 'admin_reports.dart';
import 'admin_settings.dart';
import 'admin_users.dart';
import 'admin_team.dart';

/// أقسام لوحة الإدارة (المفتاح، الاسم، الأيقونة، الصلاحية المطلوبة لظهوره).
const adminSections = [
  ('overview', 'نظرة عامة', Icons.space_dashboard_outlined, 'overview.view'),
  ('users', 'المستخدمون', Icons.people_alt_outlined, 'users.view'),
  ('reports', 'البلاغات', Icons.flag_outlined, 'reports.view'),
  ('biz', 'الدوائر التجارية', Icons.storefront_outlined, 'biz.view'),
  ('finance', 'المالية', Icons.account_balance_wallet_outlined, 'finance.view'),
  ('content', 'المحتوى', Icons.inventory_2_outlined, 'content.view'),
  ('blog', 'المدونة', Icons.newspaper_outlined, 'blog.view'),
  ('mail', 'البريد', Icons.mail_outline_rounded, 'mail.view'),
  ('team', 'الفريق', Icons.groups_outlined, 'team.view'),
  ('settings', 'الإعدادات', Icons.tune_rounded, 'settings.view'),
  ('audit', 'سجل الإجراءات', Icons.history_rounded, 'audit.view'),
];

/// رسالة خطأ مفهومة لعمليات الإدارة.
String adminErrText(Object e) {
  final body = e is ApiException ? (e.body ?? const {}) : const <String, dynamic>{};
  final s = '${e.toString()} ${body['error'] ?? ''}';
  if (s.contains('admin-only')) return 'هذا الإجراء لمدير النظام فقط';
  if (s.contains('bad-code')) return 'رمز الإعداد غير صحيح';
  if (s.contains('already-set-up')) return 'تم إعداد الإدارة مسبقاً؛ اطلب من مدير حالي ترقيتك';
  if (s.contains('last-admin')) return 'لا يمكن سحب صلاحية آخر مدير';
  if (s.contains('insufficient-funds')) return 'رصيد المستخدم لا يكفي لهذا الخصم';
  if (s.contains('bad-amount')) return 'المبلغ غير مقبول';
  if (s.contains('not-found')) return 'غير موجود';
  if (s.contains('self')) return 'لا يمكنك تطبيق هذا على حسابك';
  if (s.contains('already-cancelled')) return 'ملغاة مسبقاً';
  if (s.contains('bad-provider')) return 'مزوّد بريد غير معروف';
  if (s.contains('bad-port')) return 'المنفذ غير صحيح';
  if (s.contains('bad-from')) return 'بريد المرسل غير صحيح';
  if (s.contains('bad-reply-to')) return 'بريد الرد غير صحيح';
  if (s.contains('bad-recipient')) return 'بريد المستلم غير صحيح';
  if (s.contains('not-configured')) return 'خدمة البريد غير مفعّلة بعد؛ اختر مزوّداً واحفظ الإعدادات أولاً';
  if (s.contains('send-failed')) return 'فشل الإرسال${body['detail'] is String ? ': ${body['detail']}' : ''}';
  if (s.contains('role-above-you')) return 'لا يمكنك منح دور بمستوى يساوي مستواك أو يعلوه';
  if (s.contains('member-above-you')) return 'هذا العضو بمستوى يساوي مستواك أو يعلوه';
  if (s.contains('permissions-above-you')) return 'لا يمكنك منح صلاحيات لا تملكها';
  if (s.contains('manager-cycle')) return 'لا يمكن أن يكون المدير أحد مرؤوسي هذا العضو';
  if (s.contains('already-member')) return 'هذا المستخدم عضو في الفريق أصلاً';
  if (s.contains('user-not-found')) return 'لا يوجد مستخدم بهذا المعرّف';
  if (s.contains('bad-role')) return 'اختر دوراً صحيحاً';
  if (s.contains('bad-manager')) return 'المدير المختار ليس عضواً في الفريق';
  if (s.contains('bad-mailbox')) return 'اسم الصندوق يقبل حروفاً إنجليزية وأرقاماً ونقطة وشرطة فقط';
  if (s.contains('out-of-scope')) return 'هذا العضو خارج نطاق إدارتك';
  if (s.contains('last-owner')) return 'لا يمكن إزالة آخر مالك';
  if (s.contains('role-exists')) return 'يوجد دور بهذا المعرّف';
  if (s.contains('role-in-use')) return 'الدور مستخدم من أعضاء؛ انقلهم أولاً';
  if (s.contains('builtin-role')) return 'الأدوار المدمجة لا تُعدَّل صلاحياتها ولا تُحذف';
  if (s.contains('forbidden')) return 'ليست لديك صلاحية لهذا الإجراء';
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
        'team' => const AdminTeamPage(),
        'overview' => AdminOverviewPage(onGo: (key) => onSelect(adminSections.indexWhere((s) => s.$1 == key))),
        'users' => const AdminUsersPage(),
        'reports' => const AdminReportsPage(),
        'biz' => const AdminBizPage(),
        'finance' => const AdminFinancePage(),
        'content' => const AdminContentPage(),
        'blog' => const AdminBlogPage(),
        'mail' => const AdminMailPage(),
        'settings' => const AdminSettingsPage(),
        _ => const AdminAuditPage(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = status.user;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      // تظهر للعضو الأقسام التي تسمح بها صلاحياته فقط
      final visible = [for (final (i, sec) in adminSections.indexed) if (status.can(sec.$4)) i];
      if (visible.isEmpty) return _Forbidden(status: status, standalone: standalone);
      final current = visible.contains(index) ? index : visible.first;
      final title = adminSections[current].$2;
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
        for (final i in visible)
          ListTile(
            key: Key('admin-nav-${adminSections[i].$1}'),
            selected: i == current,
            selectedTileColor: Joy.primarySoft,
            selectedColor: Joy.primary,
            leading: Icon(adminSections[i].$3),
            title: Text(adminSections[i].$2, style: TextStyle(fontWeight: i == current ? FontWeight.w700 : FontWeight.w500)),
            onTap: () { onSelect(i); if (!wide) Navigator.of(context).maybePop(); },
          ),
        if (status.roleName != null) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text('${status.roleName}${status.title.isNotEmpty ? ' · ${status.title}' : ''}', key: const Key('admin-role'), style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
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
              Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: _page(current)))),
            ])),
          ]),
        );
      }
      return Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: Text(title), actions: [IconButton(tooltip: 'تحديث', onPressed: () => invalidateAdmin(ref), icon: const Icon(Icons.refresh_rounded))]),
        drawer: Drawer(backgroundColor: Joy.surface, child: SafeArea(child: nav)),
        body: _page(current),
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
              TextField(
                key: const Key('setup-code'),
                controller: code,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]'))],
                style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700),
                decoration: InputDecoration(hintText: 'NL-XXXXXX-XXXXXX', helperText: widget.status.setupHint == null ? null : 'الرمز الفعّال الآن ينتهي بـ ${widget.status.setupHint}${widget.status.setupCodeCreatedAt != null ? ' · أُنشئ ${timeAgo(widget.status.setupCodeCreatedAt)}' : ''}', helperStyle: const TextStyle(color: Joy.textMuted)),
              ),
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
              const SizedBox(height: 10),
              Text('بديل بلا رمز: اكتب معرّف حسابك${widget.status.user != null ? ' (${widget.status.user!.id})' : ''} في الملف ${widget.status.bootstrapFile ?? '/opt/naslife/ops/admin-ids'} على الخادم ثم أعد تشغيل الخدمة:\necho ${widget.status.user?.id ?? 'SA0000001'} > ${widget.status.bootstrapFile ?? '/opt/naslife/ops/admin-ids'} && systemctl restart naslife', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 12, fontFamily: 'monospace')),
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
