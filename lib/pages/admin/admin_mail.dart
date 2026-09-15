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
              'resend' => 'خدمة Resend: مفتاح API من resend.com بعد إثبات ملكية النطاق naslife.app.',
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
