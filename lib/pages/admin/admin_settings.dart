import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/client.dart' show ApiException;
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../wallet/wallet_page.dart' show payConfigProvider;
import 'admin_shell.dart';

class AdminSettingsPage extends ConsumerStatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  ConsumerState<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends ConsumerState<AdminSettingsPage> {
  final maxTopup = TextEditingController(), announcement = TextEditingController(), support = TextEditingController(), supportEmail = TextEditingController(), bannedWords = TextEditingController(), threshold = TextEditingController();
  final commission = TextEditingController(), spotPrice = TextEditingController(), spotMaxDays = TextEditingController(), spotMaxActive = TextEditingController();
  bool? testTopup, maintenance, reviewNew, blockContacts, transfers, chatPayments, bannedDefault;
  bool loaded = false, busy = false;

  void _load(AdminSettings s) {
    if (loaded) return;
    loaded = true;
    maxTopup.text = (s.maxTopup / 100).toStringAsFixed(0);
    announcement.text = s.announcement;
    support.text = s.supportHandle;
    supportEmail.text = s.supportEmail;
    transfers = s.transfersEnabled;
    chatPayments = s.chatPaymentsEnabled;
    bannedDefault = s.bannedWordsDefault;
    bannedWords.text = s.bannedWords;
    threshold.text = '${s.reportThreshold}';
    testTopup = s.testTopup;
    maintenance = s.maintenance;
    commission.text = s.marketCommissionPct == s.marketCommissionPct.roundToDouble() ? '${s.marketCommissionPct.round()}' : '${s.marketCommissionPct}';
    spotPrice.text = (s.spotlightPricePerDay / 100).toStringAsFixed(0);
    spotMaxDays.text = '${s.spotlightMaxDays}';
    spotMaxActive.text = '${s.spotlightMaxActive}';
    reviewNew = s.marketReviewNewAccounts;
    blockContacts = s.marketBlockContacts;
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
            // التحويل بين المستخدمين والدفع في المحادثة قد يُعدّان إصدار نقود إلكترونية؛ مفتاحان لإطفائهما (مطفآن دائماً في iOS)
            SwitchListTile(key: const Key('set-transfers'), contentPadding: EdgeInsets.zero, value: transfers ?? s.transfersEnabled, onChanged: (v) => setState(() => transfers = v), title: const Text('التحويل بين المستخدمين'), subtitle: const Text('إرسال رصيد من محفظة إلى أخرى. مطفأ دائماً في تطبيق iOS', style: TextStyle(fontSize: 12))),
            SwitchListTile(key: const Key('set-chat-payments'), contentPadding: EdgeInsets.zero, value: chatPayments ?? s.chatPaymentsEnabled, onChanged: (v) => setState(() => chatPayments = v), title: const Text('الدفع داخل المحادثة'), subtitle: const Text('طلب مبلغ وتقسيم فاتورة وإرسال مال في الدردشة. مطفأ دائماً في تطبيق iOS', style: TextStyle(fontSize: 12))),
          ])),
          const SectionTitle('بوابة الدفع (ميسر)'),
          const _PayGatewayCard(),
          const SectionTitle('الإعلان العام'),
          JoyCard(child: Column(children: [
            TextField(controller: announcement, maxLines: 2, decoration: const InputDecoration(labelText: 'نص يظهر في الرئيسية لكل المستخدمين (اتركه فارغاً لإخفائه)')),
            const SizedBox(height: 8),
            TextField(controller: support, decoration: const InputDecoration(labelText: 'نك نيم حساب الدعم (اختياري)')),
            const SizedBox(height: 8),
            TextField(key: const Key('set-support-email'), controller: supportEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'بريد الدعم', helperText: 'يظهر في صفحات الدعم والخصوصية والشروط على naslife.app (مثل support@areebd.sa). «تواصل معنا» داخل التطبيق يبقى support@naslife.app', helperMaxLines: 3)),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: maintenance ?? s.maintenance, onChanged: (v) => setState(() => maintenance = v), title: const Text('وضع الصيانة'), subtitle: const Text('يعرض تنبيه صيانة للمستخدمين دون إيقاف الخدمة')),
          ])),
          const SectionTitle('الأمان والإشراف'),
          JoyCard(child: Column(children: [
            TextField(controller: bannedWords, maxLines: 4, decoration: const InputDecoration(labelText: 'كلمات محظورة (كلمة في كل سطر أو مفصولة بفواصل)', helperText: 'تُرفض المنشورات والعروض والتقييمات التي تحتويها، ويُنبَّه المرسل قبل إرسال رسالة تحتويها')),
            SwitchListTile(key: const Key('set-banned-default'), contentPadding: EdgeInsets.zero, value: bannedDefault ?? s.bannedWordsDefault, onChanged: (v) => setState(() => bannedDefault = v), title: const Text('القائمة الافتراضية للشتائم'), subtitle: const Text('قائمة مدمجة من الشتائم الصريحة بالعربية والإنجليزية تعمل مع كلماتك أعلاه', style: TextStyle(fontSize: 12))),
            const SizedBox(height: 8),
            TextField(controller: threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد البلاغات للإخفاء التلقائي', helperText: 'يُخفى المنشور أو العرض تلقائياً عند بلوغ هذا العدد من المبلّغين المختلفين ويُشعَر المشرفون')),
          ])),
          const SectionTitle('السوق'),
          JoyCard(child: Column(children: [
            TextField(key: const Key('set-commission'), controller: commission, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عمولة المنصة على كل طلب مكتمل (٪)', helperText: 'تُخصم من مبلغ البائع وتُقيَّد لحساب المنصة. ٠ يعني بلا عمولة')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(key: const Key('set-spot-price'), controller: spotPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر يوم سبوت لايت (ريال)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: spotMaxDays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أقصى أيام'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: spotMaxActive, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أقصى إعلانات نشطة'))),
            ]),
            SwitchListTile(key: const Key('set-review-new'), contentPadding: EdgeInsets.zero, value: reviewNew ?? s.marketReviewNewAccounts, onChanged: (v) => setState(() => reviewNew = v), title: const Text('مراجعة عروض الحسابات الجديدة'), subtitle: const Text('عروض من سجّل قبل أقل من أسبوع لا تظهر إلا بعد موافقة الإدارة', style: TextStyle(fontSize: 12))),
            SwitchListTile(key: const Key('set-block-contacts'), contentPadding: EdgeInsets.zero, value: blockContacts ?? s.marketBlockContacts, onChanged: (v) => setState(() => blockContacts = v), title: const Text('منع أرقام الجوال والروابط في العروض'), subtitle: const Text('يبقي التواصل داخل المنصة', style: TextStyle(fontSize: 12))),
          ])),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('set-save'),
            onPressed: busy ? null : () async {
              setState(() => busy = true);
              try {
                await ref.read(apiClientProvider).adminSaveSettings({'testTopup': testTopup ?? s.testTopup, 'maxTopup': parseSar(maxTopup.text), 'announcement': announcement.text.trim(), 'supportHandle': support.text.trim(), 'maintenance': maintenance ?? s.maintenance, 'marketCommissionPct': double.tryParse(commission.text.trim()) ?? s.marketCommissionPct, 'spotlightPricePerDay': parseSar(spotPrice.text), 'spotlightMaxDays': int.tryParse(spotMaxDays.text.trim()) ?? s.spotlightMaxDays, 'spotlightMaxActive': int.tryParse(spotMaxActive.text.trim()) ?? s.spotlightMaxActive, 'marketReviewNewAccounts': reviewNew ?? s.marketReviewNewAccounts, 'marketBlockContacts': blockContacts ?? s.marketBlockContacts, 'bannedWords': bannedWords.text.trim(), 'reportThreshold': int.tryParse(threshold.text.trim()) ?? s.reportThreshold,
                  'supportEmail': supportEmail.text.trim(), 'transfersEnabled': transfers ?? s.transfersEnabled, 'chatPaymentsEnabled': chatPayments ?? s.chatPaymentsEnabled, 'bannedWordsDefault': bannedDefault ?? s.bannedWordsDefault});
                loaded = false;
                invalidateAdmin(ref);
                ref.invalidate(publicSettingsProvider);
                if (context.mounted) toast(context, 'حُفظت الإعدادات');
              } catch (e) {
                if (context.mounted) toast(context, '${e is ApiException ? e.body : e}'.contains('bad-email') ? 'بريد الدعم غير صحيح' : adminErrText(e), error: true);
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

final adminPayConfigProvider = FutureProvider<PayAdminConfig>((ref) => ref.watch(apiClientProvider).adminPayConfig());

/// مفاتيح ميسر من اللوحة بدل ملف البيئة: مفتاح النشر والمفتاح السري وسر الويبهوك، مع حفظ وفحص اتصال ومسح.
/// السر لا يُعرض بعد حفظه؛ يظهر تلميح بآخر أربعة أحرف فقط.
class _PayGatewayCard extends ConsumerStatefulWidget {
  const _PayGatewayCard();
  @override
  ConsumerState<_PayGatewayCard> createState() => _PayGatewayCardState();
}

class _PayGatewayCardState extends ConsumerState<_PayGatewayCard> {
  final pk = TextEditingController(), sk = TextEditingController(), wh = TextEditingController();
  bool loaded = false, busy = false, showSecret = false;
  String? testText;
  bool? testOk;

  @override
  void dispose() {
    pk.dispose(); sk.dispose(); wh.dispose();
    super.dispose();
  }

  void _load(PayAdminConfig c) {
    if (loaded) return;
    loaded = true;
    if (c.source == 'panel') pk.text = c.publishableKey;
  }

  String _err(Object e) {
    final code = e is ApiException ? (e.body?['error']?.toString() ?? '') : '';
    return switch (code) {
      'masked-key' => 'المفتاح منسوخ مقنّعاً (فيه نجوم). في لوحة ميسر اضغط أيقونة العين لإظهار المفتاح كاملاً ثم انسخه، أو استخدم زر النسخ المجاور له',
      'bad-key' => 'صيغة المفتاح غير صحيحة: مفتاح النشر يبدأ بـ pk_test_ أو pk_live_ والسري بـ sk_test_ أو sk_live_',
      'both-keys-required' => 'أدخل المفتاحين معاً (النشر والسري)',
      'mode-mismatch' => 'المفتاحان من وضعين مختلفين: أحدهما اختبار والآخر حي',
      _ => adminErrText(e),
    };
  }

  static String _clean(String v) => v.replaceAll(RegExp(r'\s+'), '');
  static bool _masked(String v) => RegExp(r'[*•●]').hasMatch(v);

  Future<void> _paste(TextEditingController c) async {
    try {
      final t = _clean((await Clipboard.getData('text/plain'))?.text ?? '');
      if (t.isEmpty) { if (mounted) toast(context, 'الحافظة فارغة', error: true); return; }
      setState(() => c.text = t);
      if (_masked(t) && mounted) toast(context, 'هذا النص مقنّع بالنجوم؛ أظهر المفتاح في لوحة ميسر قبل نسخه', error: true);
    } catch (_) {
      if (mounted) toast(context, 'تعذر قراءة الحافظة؛ الصق يدوياً داخل الحقل', error: true);
    }
  }

  /// تلميح تحت الحقل السري: البادئة وعدد الأحرف كي يتأكد أن اللصق اكتمل دون كشف المفتاح
  String? _skHint() {
    final v = _clean(sk.text);
    if (v.isEmpty) return null;
    if (_masked(v)) return 'منسوخ مقنّعاً: فيه نجوم بدل الأحرف';
    final us = v.indexOf('_', 3);
    return '${us > 0 ? v.substring(0, us + 1) : v.substring(0, v.length.clamp(0, 8))}… · ${v.length} حرفاً';
  }

  Future<void> _save({bool clear = false}) async {
    for (final c in [pk, sk, wh]) { c.text = _clean(c.text); }
    if (!clear && (_masked(pk.text) || _masked(sk.text))) { toast(context, _err(const ApiException(400, 'masked-key', body: {'error': 'masked-key'})), error: true); return; }
    setState(() { busy = true; testText = null; });
    try {
      final c = clear
          ? await ref.read(apiClientProvider).adminSavePayConfig(publishableKey: '', secretKey: '', webhookSecret: '')
          : await ref.read(apiClientProvider).adminSavePayConfig(publishableKey: pk.text, secretKey: sk.text.trim().isEmpty ? null : sk.text, webhookSecret: wh.text.trim().isEmpty ? null : wh.text);
      sk.clear(); wh.clear();
      if (clear) pk.clear();
      loaded = false;
      ref.invalidate(adminPayConfigProvider);
      ref.invalidate(payConfigProvider);
      if (mounted) toast(context, clear ? 'أُزيلت المفاتيح' : c.enabled ? 'حُفظت المفاتيح: ${c.mode == 'live' ? 'الوضع الحي' : 'وضع الاختبار'}' : 'حُفظ');
    } catch (e) {
      if (mounted) toast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _test() async {
    setState(() { busy = true; testText = null; });
    try {
      final r = await ref.read(apiClientProvider).adminTestPay();
      final mode = r.mode == 'live' ? 'الوضع الحي' : 'وضع الاختبار';
      setState(() {
        testOk = r.ok;
        testText = r.ok
            ? 'الاتصال ناجح بميسر ($mode)'
            : switch (r.error) {
                'payments-disabled' => 'لا توجد مفاتيح محفوظة بعد',
                'bad-secret' => 'ميسر رفض المفتاح السري. تأكد من نسخه كاملاً',
                'account-inactive' => 'المفاتيح صحيحة لكن حسابك ${r.mode == 'live' ? 'الحي' : ''} لدى ميسر غير مفعّل بعد (ردّ ميسر: الحساب غير نشط). أكمل طلب Go Live أو تواصل مع دعم ميسر؛ وحتى التفعيل أعد مفاتيح الاختبار ليبقى الشحن يعمل${r.message.isEmpty ? '' : ' — ${r.message}'}',
                'provider-unreachable' => 'تعذر الوصول إلى ميسر من الخادم${r.message.isEmpty ? '' : ' (${r.message})'}',
                _ => 'فشل الفحص: ${r.error}',
              };
      });
    } catch (e) {
      setState(() { testOk = false; testText = _err(e); });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(adminPayConfigProvider);
    return cfg.when(
      loading: () => const JoyCard(child: LinearProgressIndicator()),
      error: (e, _) => JoyCard(child: ErrorState(e, onRetry: () => ref.invalidate(adminPayConfigProvider))),
      data: (c) {
        _load(c);
        final status = !c.enabled
            ? 'غير مفعّلة: زر «بالبطاقة» مخفي في المحفظة حتى تحفظ المفاتيح'
            : '${c.mode == 'live' ? 'الوضع الحي (مدفوعات حقيقية)' : 'وضع الاختبار (بطاقات وهمية، لا يُخصم مال)'} · المصدر: ${c.source == 'panel' ? 'اللوحة' : 'ملف البيئة على الخادم'}';
        return JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(c.enabled ? Icons.check_circle_rounded : Icons.cancel_rounded, color: c.enabled ? (c.mode == 'live' ? Joy.primary : Joy.sunText) : Joy.textMuted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(status, key: const Key('pay-status'), style: const TextStyle(fontSize: 13, height: 1.5))),
          ]),
          const SizedBox(height: 6),
          const Text('من لوحة ميسر ← Settings ← API Keys. المفتاح السري يظهر مقنّعاً بالنجوم؛ اضغط أيقونة العين لإظهاره كاملاً ثم انسخه (أو زر النسخ المجاور له). مفاتيح الاختبار (pk_test_ / sk_test_) لا تحتاج سجلاً تجارياً وتحاكي الدفع كاملاً.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.6)),
          const SizedBox(height: 10),
          TextField(key: const Key('pay-pk'), controller: pk, textDirection: TextDirection.ltr, textAlign: TextAlign.left, keyboardType: TextInputType.visiblePassword, autocorrect: false, enableSuggestions: false, style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(labelText: 'مفتاح النشر (Publishable key)', hintText: 'pk_test_…', suffixIcon: IconButton(key: const Key('pay-pk-paste'), tooltip: 'لصق', onPressed: () => _paste(pk), icon: const Icon(Icons.content_paste_rounded)))),
          const SizedBox(height: 8),
          TextField(
            key: const Key('pay-sk'), controller: sk, obscureText: !showSecret, textDirection: TextDirection.ltr, textAlign: TextAlign.left, keyboardType: TextInputType.visiblePassword, autocorrect: false, enableSuggestions: false, style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'المفتاح السري (Secret key)', hintText: c.secretKeySet && c.source == 'panel' ? 'محفوظ: ${c.secretKeyHint} (اتركه فارغاً للإبقاء عليه)' : 'sk_test_…',
              helperText: _skHint(), helperStyle: TextStyle(color: _masked(sk.text) ? Joy.danger : Joy.textMuted, fontSize: 11),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(key: const Key('pay-sk-paste'), tooltip: 'لصق', onPressed: () => _paste(sk), icon: const Icon(Icons.content_paste_rounded)),
                IconButton(tooltip: showSecret ? 'إخفاء' : 'إظهار', onPressed: () => setState(() => showSecret = !showSecret), icon: Icon(showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          TextField(key: const Key('pay-wh'), controller: wh, textDirection: TextDirection.ltr, textAlign: TextAlign.left, keyboardType: TextInputType.visiblePassword, autocorrect: false, enableSuggestions: false, style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(labelText: 'سر الويبهوك (اختياري)', hintText: c.webhookSecretSet && c.source == 'panel' ? 'محفوظ (اتركه فارغاً للإبقاء عليه)' : 'يُنشأ في لوحة ميسر عند إضافة الويبهوك', suffixIcon: IconButton(key: const Key('pay-wh-paste'), tooltip: 'لصق', onPressed: () => _paste(wh), icon: const Icon(Icons.content_paste_rounded)))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(key: const Key('pay-save'), onPressed: busy ? null : () => _save(), icon: const Icon(Icons.save_outlined, size: 18), label: const Text('حفظ المفاتيح')),
            OutlinedButton.icon(key: const Key('pay-test'), onPressed: busy || !c.enabled && pk.text.isEmpty ? null : _test, icon: const Icon(Icons.wifi_tethering_rounded, size: 18), label: const Text('فحص الاتصال')),
            if (c.panelKeysSet) TextButton.icon(key: const Key('pay-clear'), onPressed: busy ? null : () => _save(clear: true), style: TextButton.styleFrom(foregroundColor: Joy.danger), icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('إزالة المفاتيح')),
          ]),
          if (testText != null) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
            Icon(testOk == true ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 18, color: testOk == true ? Joy.primary : Joy.danger),
            const SizedBox(width: 6),
            Expanded(child: Text(testText!, key: const Key('pay-test-result'), style: TextStyle(fontSize: 13, color: testOk == true ? Joy.primary : Joy.danger))),
          ])),
          if (c.enabled) ...[
            const SizedBox(height: 12),
            const Text('في لوحة ميسر ← Webhooks أضف هذا الرابط لتصل تأكيدات الدفع حتى لو أغلق المستخدم الصفحة:', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.6)),
            SelectableText(c.webhookUrl, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ],
          if (c.updatedAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('آخر تحديث منذ ${timeAgo(c.updatedAt!)}${c.updatedBy.isEmpty ? '' : ' بواسطة ${c.updatedBy}'}', style: const TextStyle(color: Joy.textMuted, fontSize: 11))),
        ]));
      },
    );
  }
}
