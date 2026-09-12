import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/commerce_models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

class AdminSettingsPage extends ConsumerStatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  ConsumerState<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends ConsumerState<AdminSettingsPage> {
  final maxTopup = TextEditingController(), announcement = TextEditingController(), support = TextEditingController();
  bool? testTopup, maintenance;
  bool loaded = false, busy = false;

  void _load(AdminSettings s) {
    if (loaded) return;
    loaded = true;
    maxTopup.text = (s.maxTopup / 100).toStringAsFixed(0);
    announcement.text = s.announcement;
    support.text = s.supportHandle;
    testTopup = s.testTopup;
    maintenance = s.maintenance;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminSettingsProvider);
    final admins = ref.watch(adminAdminsProvider);
    return settings.when(
      data: (s) {
        _load(s);
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          const SectionTitle('المحفظة'),
          JoyCard(child: Column(children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, value: testTopup ?? s.testTopup, onChanged: (v) => setState(() => testTopup = v), title: const Text('الشحن التجريبي'), subtitle: const Text('يسمح لأي مستخدم بشحن محفظته بلا دفع حقيقي. عطّله قبل الإطلاق.')),
            TextField(controller: maxTopup, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أقصى شحن في المرة الواحدة (ريال)')),
          ])),
          const SectionTitle('الإعلان العام'),
          JoyCard(child: Column(children: [
            TextField(controller: announcement, maxLines: 2, decoration: const InputDecoration(labelText: 'نص يظهر في الرئيسية لكل المستخدمين (اتركه فارغاً لإخفائه)')),
            const SizedBox(height: 8),
            TextField(controller: support, decoration: const InputDecoration(labelText: 'نك نيم حساب الدعم (اختياري)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: maintenance ?? s.maintenance, onChanged: (v) => setState(() => maintenance = v), title: const Text('وضع الصيانة'), subtitle: const Text('يعرض تنبيه صيانة للمستخدمين دون إيقاف الخدمة')),
          ])),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : () async {
              setState(() => busy = true);
              try {
                await ref.read(apiClientProvider).adminSaveSettings({'testTopup': testTopup ?? s.testTopup, 'maxTopup': parseSar(maxTopup.text), 'announcement': announcement.text.trim(), 'supportHandle': support.text.trim(), 'maintenance': maintenance ?? s.maintenance});
                loaded = false;
                invalidateAdmin(ref);
                ref.invalidate(publicSettingsProvider);
                if (context.mounted) toast(context, 'حُفظت الإعدادات');
              } catch (e) {
                if (context.mounted) toast(context, adminErrText(e), error: true);
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ الإعدادات'),
          ),
          const SizedBox(height: 16),
          SectionTitle('مديرو النظام', action: 'إضافة', onAction: _addAdmin),
          admins.when(
            data: (list) => JoyCard(padding: EdgeInsets.zero, child: Column(children: [
              for (final (i, a) in list.indexed)
                ListRow(
                  leading: ProfileAvatar(person: a.user, size: 40),
                  title: Text(a.user.nickname.isEmpty ? a.user.id : a.user.nickname),
                  subtitle: Text('${a.user.id} · منذ ${timeAgo(a.since)} · ${a.grantedBy == 'setup' ? 'الإعداد الأول' : a.grantedBy == 'env' ? 'بيئة الخادم' : 'بواسطة ${a.grantedBy}'}'),
                  trailing: IconButton(tooltip: 'سحب الصلاحية', onPressed: () => _revoke(a.user.id, a.user.nickname), icon: const Icon(Icons.remove_circle_outline_rounded, color: Joy.danger)),
                  divider: i < list.length - 1,
                ),
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('المديرون معرّفون في جدول المستخدمين الأساسي فقط', style: TextStyle(color: Joy.textMuted))),
            ])),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminAdminsProvider)),
          ),
          const SizedBox(height: 16),
          const SectionTitle('النطاق الفرعي'),
          const JoyCard(child: Text('اللوحة متاحة على naslife.app/admin. لتعمل على admin.naslife.app أضف سجل DNS من نوع A يشير إلى خادمك ثم شغّل server/install-admin-subdomain.sh على الخادم مرة واحدة.', style: TextStyle(color: Joy.textMuted, height: 1.6, fontSize: 13))),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminSettingsProvider)),
    );
  }

  Future<void> _addAdmin() async {
    final handle = await askText(context, title: 'ترقية مستخدم إلى مدير نظام', hint: 'النك نيم أو المعرّف SA…', confirm: 'ترقية', maxLines: 1);
    if (handle == null || handle.trim().isEmpty) return;
    var id = handle.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{7}$').hasMatch(id)) {
      try { id = (await ref.read(apiClientProvider).userByHandle(handle.trim().toLowerCase())).id; } catch (_) { if (mounted) toast(context, 'لم نجد هذا المستخدم', error: true); return; }
    }
    try {
      await ref.read(apiClientProvider).adminGrant(id, grant: true);
      invalidateAdmin(ref);
      if (mounted) toast(context, 'أصبح مديراً');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _revoke(String id, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('سحب صلاحية $name؟'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('سحب'))]));
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).adminGrant(id, grant: false);
      invalidateAdmin(ref);
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
