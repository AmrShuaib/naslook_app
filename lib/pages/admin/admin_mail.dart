import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

/// مزوّدو البريد المدعومون في server/mail.js.
const mailProviders = [
  ('off', 'معطّل', Icons.do_not_disturb_on_outlined),
  ('smtp', 'SMTP', Icons.dns_outlined),
  ('resend', 'Resend', Icons.send_outlined),
  ('brevo', 'Brevo', Icons.mark_email_read_outlined),
  ('sendgrid', 'SendGrid', Icons.cloud_upload_outlined),
];

/// إعدادات SMTP الجاهزة لأشهر الخدمات.
const smtpPresets = [
  ('gmail', 'Gmail', 'smtp.gmail.com', 465, true, 'استخدم «كلمة مرور التطبيقات» من إعدادات أمان Google، لا كلمة مرور الحساب'),
  ('outlook', 'Outlook', 'smtp.office365.com', 587, false, 'بريد Microsoft 365 أو Outlook.com بكلمة مرور الحساب أو كلمة مرور تطبيق'),
  ('zoho', 'Zoho', 'smtp.zoho.com', 465, true, 'بريد Zoho Mail بكلمة مرور تطبيق'),
  ('brevo-smtp', 'Brevo SMTP', 'smtp-relay.brevo.com', 587, false, 'اسم المستخدم هو بريد حسابك في Brevo وكلمة السر مفتاح SMTP من الحساب'),
];

/// صفحة خدمة البريد في لوحة الإدارة: اختيار المزوّد، بيانات الاتصال، رسالة تجريبية، وسجل الإرسال.
class AdminMailPage extends ConsumerStatefulWidget {
  const AdminMailPage({super.key});
  @override
  ConsumerState<AdminMailPage> createState() => _AdminMailPageState();
}

class _AdminMailPageState extends ConsumerState<AdminMailPage> {
  final host = TextEditingController(), port = TextEditingController(), user = TextEditingController(), pass = TextEditingController(), apiKey = TextEditingController(), from = TextEditingController(), fromName = TextEditingController(), replyTo = TextEditingController(), testTo = TextEditingController();
  String provider = 'off';
  bool secure = false, loaded = false, busy = false, testing = false, showPass = false;

  void _load(AdminMailSettings s) {
    if (loaded) return;
    loaded = true;
    provider = s.provider;
    host.text = s.host;
    port.text = '${s.port}';
    secure = s.secure;
    user.text = s.user;
    pass.text = s.pass;
    apiKey.text = s.apiKey;
    from.text = s.from;
    fromName.text = s.fromName;
    replyTo.text = s.replyTo;
  }

  void _applyPreset((String, String, String, int, bool, String) p) => setState(() {
        provider = 'smtp';
        host.text = p.$3;
        port.text = '${p.$4}';
        secure = p.$5;
        if (fromName.text.trim().isEmpty) fromName.text = 'ناس لايف';
      });

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminMailSave({
        'provider': provider,
        'host': host.text.trim(), 'port': int.tryParse(port.text.trim()) ?? (secure ? 465 : 587), 'secure': secure, 'user': user.text.trim(), 'pass': pass.text,
        'apiKey': apiKey.text.trim(), 'from': from.text.trim(), 'fromName': fromName.text.trim(), 'replyTo': replyTo.text.trim(),
      });
      loaded = false;
      ref.invalidate(adminMailProvider);
      if (mounted) toast(context, provider == 'off' ? 'عُطّلت خدمة البريد' : 'حُفظت إعدادات البريد');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// بعد توثيق النطاق يتبدّل المرسل على الخادم: نعيد جلب الإعدادات ونملأ الحقول بالقيم الجديدة.
  Future<void> _reloadSettings() async {
    try {
      final s = await ref.refresh(adminMailProvider.future);
      if (!mounted) return;
      setState(() { loaded = false; _load(s); });
    } catch (_) { /* تُعرض عند إعادة البناء */ }
  }

  Future<void> _sendTest() async {
    final to = testTo.text.trim();
    if (to.isEmpty || !to.contains('@')) { toast(context, 'اكتب بريداً صحيحاً لاستلام الرسالة التجريبية', error: true); return; }
    setState(() => testing = true);
    try {
      await ref.read(apiClientProvider).adminMailTest(to);
      ref.invalidate(adminMailLogProvider);
      if (mounted) toast(context, 'أُرسلت الرسالة التجريبية إلى $to — تفقّد الوارد أو الرسائل غير المرغوبة');
    } catch (e) {
      ref.invalidate(adminMailLogProvider);
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminMailProvider);
    return settings.when(
      data: (s) {
        _load(s);
        final isSmtp = provider == 'smtp', isHttp = provider != 'off' && !isSmtp;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          _StatusBanner(settings: s),
          const SizedBox(height: 14),
          const SectionTitle('المزوّد'),
          JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in mailProviders)
                ChoiceChip(key: Key('mail-provider-${p.$1}'), avatar: Icon(p.$3, size: 18, color: provider == p.$1 ? Joy.primary : Joy.textMuted), label: Text(p.$2), selected: provider == p.$1, onSelected: (_) => setState(() => provider = p.$1)),
            ]),
            const SizedBox(height: 10),
            Text(switch (provider) {
              'off' => 'لن تُرسل أي رسالة (تأكيد البريد معطّل). اختر مزوّداً لتفعيل الخدمة.',
              'smtp' => 'أي بريد يدعم SMTP: Gmail أو Outlook أو Zoho أو خادم بريدك الخاص. الأنسب للبداية بلا اشتراك.',
              'resend' => 'خدمة Resend: 3000 رسالة شهرياً مجاناً. أنشئ مفتاح API بصلاحية كاملة من resend.com ثم اربط النطاق من قسم «بريد رسمي باسم النطاق» أدناه.',
              'brevo' => 'خدمة Brevo: مفتاح API (xkeysib-…) من إعدادات الحساب، مع 300 رسالة يومياً مجاناً.',
              _ => 'خدمة SendGrid: مفتاح API بصلاحية Mail Send من لوحة SendGrid.',
            }, style: const TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6)),
          ])),
          if (isSmtp) ...[
            const SizedBox(height: 14),
            const SectionTitle('خادم SMTP'),
            JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('إعداد سريع', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final p in smtpPresets) ActionChip(key: Key('mail-preset-${p.$1}'), label: Text(p.$2), onPressed: () => _applyPreset(p))]),
              const SizedBox(height: 12),
              TextField(key: const Key('mail-host'), controller: host, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'الخادم (host)', hintText: 'smtp.gmail.com')),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 120, child: TextField(key: const Key('mail-port'), controller: port, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'المنفذ'))),
                const SizedBox(width: 12),
                Expanded(child: SwitchListTile(key: const Key('mail-secure'), contentPadding: EdgeInsets.zero, value: secure, onChanged: (v) => setState(() { secure = v; if (port.text == '587' && v) port.text = '465'; if (port.text == '465' && !v) port.text = '587'; }), title: const Text('TLS مباشر', style: TextStyle(fontSize: 14)), subtitle: Text(secure ? 'المنفذ 465' : 'STARTTLS على 587', style: const TextStyle(fontSize: 12)))),
              ]),
              const SizedBox(height: 8),
              TextField(key: const Key('mail-user'), controller: user, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'اسم المستخدم', hintText: 'غالباً عنوان البريد كاملاً')),
              const SizedBox(height: 8),
              TextField(key: const Key('mail-pass'), controller: pass, obscureText: !showPass, textDirection: TextDirection.ltr, autocorrect: false, enableSuggestions: false,
                  decoration: InputDecoration(labelText: 'كلمة السر أو كلمة مرور التطبيق', helperText: s.hasPass ? 'محفوظة؛ اتركها كما هي للإبقاء عليها' : null, suffixIcon: IconButton(icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => showPass = !showPass)))),
              const SizedBox(height: 10),
              for (final p in smtpPresets) if (host.text.trim() == p.$3) Text(p.$6, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
            ])),
          ],
          if (isHttp) ...[
            const SizedBox(height: 14),
            const SectionTitle('مفتاح الخدمة'),
            JoyCard(child: TextField(key: const Key('mail-apikey'), controller: apiKey, obscureText: !showPass, textDirection: TextDirection.ltr, autocorrect: false, enableSuggestions: false,
                decoration: InputDecoration(labelText: 'API key', helperText: s.hasApiKey ? 'محفوظ؛ اتركه كما هو للإبقاء عليه' : 'يُنشأ من لوحة المزوّد ويُحفظ في قاعدة البيانات', suffixIcon: IconButton(icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => showPass = !showPass))))),
          ],
          if (provider != 'off') ...[
            const SizedBox(height: 14),
            const SectionTitle('المرسل'),
            JoyCard(child: Column(children: [
              TextField(key: const Key('mail-from'), controller: from, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'بريد المرسل', hintText: 'no-reply@naslife.app', helperText: 'يجب أن يكون بريداً مسموحاً به عند المزوّد (البريد نفسه في Gmail، أو نطاق موثّق في الخدمات الأخرى)')),
              const SizedBox(height: 8),
              TextField(key: const Key('mail-from-name'), controller: fromName, decoration: const InputDecoration(labelText: 'اسم المرسل', hintText: 'ناس لايف')),
              const SizedBox(height: 8),
              TextField(key: const Key('mail-reply-to'), controller: replyTo, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'بريد الرد (اختياري)', hintText: 'support@naslife.app')),
            ])),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(key: const Key('mail-save'), onPressed: busy ? null : _save, icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined), label: Text(provider == 'off' ? 'حفظ (تعطيل البريد)' : 'حفظ الإعدادات')),
          const SizedBox(height: 18),
          const SectionTitle('بريد رسمي باسم النطاق'),
          _DomainCard(onSettingsChanged: _reloadSettings),
          const SizedBox(height: 18),
          const SectionTitle('رسالة تجريبية'),
          JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('احفظ الإعدادات أولاً ثم أرسل رسالة إلى بريدك للتأكد من وصولها.', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(key: const Key('mail-test-to'), controller: testTo, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'إلى', hintText: 'you@example.com'))),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(key: const Key('mail-test-send'), onPressed: testing || !s.configured ? null : _sendTest, icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.outgoing_mail), label: const Text('إرسال')),
            ]),
            if (!s.configured) const Padding(padding: EdgeInsets.only(top: 6), child: Text('الإرسال متاح بعد حفظ إعدادات مزوّد صالحة.', style: TextStyle(color: Joy.warning, fontSize: 12))),
          ])),
          const SizedBox(height: 18),
          SectionTitle('سجل الإرسال', action: 'تحديث', onAction: () => ref.invalidate(adminMailLogProvider)),
          const _MailLogCard(),
          const SizedBox(height: 18),
          const SectionTitle('ما الذي يستخدم البريد؟'),
          const JoyCard(child: Text('• تأكيد «بريد الدخول» من ماي سبيس برمز من 6 أرقام صالح 15 دقيقة.\n• الرسائل التجريبية من هذه الصفحة.\n• استعادة كلمة السر بالبريد غير متاحة لأن كلمات السر في نواة الخادم لا تملك واجهة لإعادة التعيين؛ تبقى عبارة الاستعادة هي الطريقة المعتمدة.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.7))),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminMailProvider)),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final AdminMailSettings settings;
  const _StatusBanner({required this.settings});
  @override
  Widget build(BuildContext context) {
    final on = settings.configured;
    final label = mailProviders.firstWhere((p) => p.$1 == settings.provider, orElse: () => mailProviders.first).$2;
    return JoyCard(
      key: const Key('mail-status'),
      color: on ? Joy.primarySoft : Joy.sunSoft,
      child: Row(children: [
        Icon(on ? Icons.mark_email_read_rounded : Icons.mail_lock_outlined, color: on ? Joy.primary : Joy.sunText, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(on ? 'خدمة البريد مفعّلة' : 'خدمة البريد غير مفعّلة', style: TextStyle(fontWeight: FontWeight.w800, color: on ? Joy.primary : Joy.sunText)),
          const SizedBox(height: 2),
          Text(on ? 'عبر $label · المرسل ${settings.from}' : 'رسائل تأكيد البريد لن تُرسل حتى تُدخل بيانات مزوّد وتحفظها', style: TextStyle(fontSize: 12.5, color: on ? Joy.text : Joy.sunText, height: 1.5)),
        ])),
      ]),
    );
  }
}

class _MailLogCard extends ConsumerWidget {
  const _MailLogCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(adminMailLogProvider);
    return log.when(
      data: (l) => JoyCard(padding: EdgeInsets.zero, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
          _Stat(key: const Key('mail-stat-sent'), label: 'أُرسلت (30 يوماً)', value: l.sent30d, color: Joy.success),
          const SizedBox(width: 12),
          _Stat(key: const Key('mail-stat-failed'), label: 'فشلت', value: l.failed30d, color: Joy.danger),
        ])),
        if (l.entries.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 16), child: Text('لا رسائل بعد', style: TextStyle(color: Joy.textMuted))),
        for (final (i, e) in l.entries.indexed)
          ListRow(
            key: Key('mail-log-${e.id}'),
            leading: Icon(e.sent ? Icons.check_circle_rounded : Icons.error_rounded, color: e.sent ? Joy.success : Joy.danger),
            title: Text(e.to, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            subtitle: Text('${e.subject}${e.tag != null ? ' · ${e.tag == 'test' ? 'تجريبية' : e.tag == 'verify' ? 'تأكيد بريد' : e.tag}' : ''} · ${timeAgo(e.at)}${e.error != null ? '\n${e.error}' : ''}', style: TextStyle(color: e.sent ? Joy.textMuted : Joy.danger)),
            divider: i < l.entries.length - 1,
          ),
      ])),
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminMailLogProvider)),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Stat({super.key, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)), Text(label, style: const TextStyle(fontSize: 12, color: Joy.textMuted))]),
      ));
}

/// بطاقة «بريد رسمي باسم النطاق» (مثل admin@naslife.app): ربط النطاق عند المزوّد، سجلات DNS المطلوبة مع حالة كل سجل،
/// التحقق، وتعيين المرسل تلقائياً عند التوثيق.
class _DomainCard extends ConsumerStatefulWidget {
  final VoidCallback onSettingsChanged;
  const _DomainCard({required this.onSettingsChanged});
  @override
  ConsumerState<_DomainCard> createState() => _DomainCardState();
}

class _DomainCardState extends ConsumerState<_DomainCard> {
  final domain = TextEditingController(), local = TextEditingController();
  bool busy = false, seeded = false;

  Future<void> _run(Future<AdminMailDomainInfo> Function() action, String Function(AdminMailDomainInfo) message) async {
    setState(() => busy = true);
    try {
      final info = await action();
      ref.invalidate(adminMailDomainProvider);
      if (info.domain?.fromApplied == true) widget.onSettingsChanged();
      if (mounted) toast(context, message(info));
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove(AdminMailDomain d) async {
    final ok = await showDialog<bool>(context: context, builder: (x) => AlertDialog(title: Text('إلغاء ربط ${d.name}؟'), content: const Text('يُحذف الربط من هنا فقط؛ يبقى النطاق في حساب المزوّد ويمكن إعادة ربطه لاحقاً.'), actions: [TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('تراجع')), FilledButton(key: const Key('mail-domain-remove-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(x, true), child: const Text('إلغاء الربط'))]));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminMailDomainRemove();
      ref.invalidate(adminMailDomainProvider);
      if (mounted) toast(context, 'أُلغي ربط النطاق');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, 'نُسخ');
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(adminMailDomainProvider);
    return info.when(
      loading: () => const JoyCard(child: LinearProgressIndicator()),
      error: (e, _) => JoyCard(child: ErrorState(e, onRetry: () => ref.invalidate(adminMailDomainProvider))),
      data: (i) {
        final d = i.domain;
        if (d == null) {
          if (!seeded) { seeded = true; domain.text = i.suggestedName; local.text = i.suggestedLocal; }
          return JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('بدل بريد شخصي، تُرسل رسائل التأكيد والاستعادة من بريد رسمي باسم التطبيق يوثّقه المزوّد بسجلات DNS في نطاقك.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6)),
            const SizedBox(height: 10),
            Directionality(textDirection: TextDirection.ltr, child: Row(children: [
              Expanded(flex: 2, child: TextField(key: const Key('mail-domain-local'), controller: local, autocorrect: false, decoration: const InputDecoration(labelText: 'الاسم', hintText: 'admin'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('@', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              Expanded(flex: 3, child: TextField(key: const Key('mail-domain-name'), controller: domain, autocorrect: false, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'النطاق', hintText: 'naslife.app'))),
            ])),
            const SizedBox(height: 10),
            if (!i.providerReady)
              const Text('يعمل الربط مع Resend أو Brevo: اختر أحدهما أعلاه، احفظ مفتاح API (بصلاحية كاملة)، ثم عد هنا.', key: Key('mail-domain-need-provider'), style: TextStyle(color: Joy.warning, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 8),
            FilledButton.icon(key: const Key('mail-domain-start'), onPressed: busy || !i.providerReady ? null : () => _run(() => ref.read(apiClientProvider).adminMailDomainStart(domain: domain.text, local: local.text), (_) => 'أُنشئ النطاق عند المزوّد؛ أضف السجلات في DNS ثم اضغط «تحقق الآن»'),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.link_rounded), label: const Text('ابدأ الربط')),
          ]));
        }
        final (label, color) = switch (d.status) { 'verified' => ('موثّق', Joy.success), 'failed' => ('فشل التوثيق', Joy.danger), _ => ('بانتظار DNS', Joy.warning) };
        return JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d.sender, key: const Key('mail-domain-sender'), textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Container(key: const Key('mail-domain-status'), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5))),
          ]),
          const SizedBox(height: 4),
          Text('عبر ${d.provider == 'resend' ? 'Resend' : 'Brevo'} · ${d.dnsFound} من ${d.dnsRequired} سجلات ظاهرة في DNS${d.checkedAt != null ? ' · آخر فحص ${timeAgo(d.checkedAt)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          if (d.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(d.error!, style: const TextStyle(color: Joy.danger, fontSize: 12))),
          const SizedBox(height: 12),
          if (d.verified)
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Text('النطاق موثّق والمرسل الرسمي الآن ${d.sender}. أرسل رسالة تجريبية أدناه للتأكد من الوصول.', style: const TextStyle(fontSize: 13, height: 1.6)))
          else
            const Text('أضف هذه السجلات في لوحة DNS للنطاق (في name.com: My Domains ← النطاق ← DNS Records ← Add Record). اكتب Host كما هو بدون اسم النطاق، والقيمة كما هي. الانتشار يأخذ من دقائق إلى ساعة.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6)),
          const SizedBox(height: 10),
          for (final (idx, r) in d.records.indexed) _RecordRow(index: idx, record: r, onCopy: _copy),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(key: const Key('mail-domain-verify'), onPressed: busy ? null : () => _run(() => ref.read(apiClientProvider).adminMailDomainVerify(), (x) => x.domain?.verified == true ? 'تم التوثيق، المرسل الآن ${x.domain!.sender}' : 'لم تكتمل السجلات بعد: ظاهر ${x.domain?.dnsFound ?? 0} من ${x.domain?.dnsRequired ?? 0}'),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined), label: Text(d.verified ? 'إعادة الفحص' : 'تحقق الآن')),
            TextButton.icon(key: const Key('mail-domain-remove'), onPressed: busy ? null : () => _remove(d), icon: const Icon(Icons.link_off_rounded, color: Joy.danger, size: 18), label: const Text('إلغاء الربط', style: TextStyle(color: Joy.danger))),
          ]),
          const SizedBox(height: 8),
          Text('لاستقبال الردود على ${d.sender}: فعّل «Email Forwarding» في name.com إلى بريدك الشخصي (مجاني)، أو استخدم خدمة تحويل مثل ImprovMX.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        ]));
      },
    );
  }
}

class _RecordRow extends StatelessWidget {
  final int index;
  final AdminDnsRecord record;
  final void Function(String) onCopy;
  const _RecordRow({required this.index, required this.record, required this.onCopy});
  @override
  Widget build(BuildContext context) {
    final r = record;
    final (icon, color, hint) = r.dnsOk == true ? (Icons.check_circle_rounded, Joy.success, 'ظاهر في DNS') : r.dnsOk == false ? (Icons.hourglass_top_rounded, Joy.warning, 'غير ظاهر بعد') : (Icons.help_outline_rounded, Joy.textMuted, 'تعذّر الفحص');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(6)), child: Text(r.type, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          const SizedBox(width: 8),
          Expanded(child: Text(r.optional ? 'اختياري (موصى به)' : r.source.isEmpty ? '' : r.source.toUpperCase(), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))),
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          Text(hint, style: TextStyle(color: color, fontSize: 11.5)),
        ]),
        const SizedBox(height: 6),
        _Kv(label: 'Host', value: r.host, onCopy: () => onCopy(r.host), copyKey: Key('mail-domain-copy-host-$index')),
        if (r.priority != null) _Kv(label: 'Priority', value: '${r.priority}', onCopy: () => onCopy('${r.priority}'), copyKey: Key('mail-domain-copy-priority-$index')),
        _Kv(label: 'Value', value: r.value, onCopy: () => onCopy(r.value), copyKey: Key('mail-domain-copy-value-$index')),
      ]),
    );
  }
}

class _Kv extends StatelessWidget {
  final String label, value;
  final VoidCallback onCopy;
  final Key copyKey;
  const _Kv({required this.label, required this.value, required this.onCopy, required this.copyKey});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.ltr, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        Expanded(child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4))),
        IconButton(key: copyKey, tooltip: 'نسخ', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: onCopy, icon: const Icon(Icons.copy_rounded)),
      ]));
}
