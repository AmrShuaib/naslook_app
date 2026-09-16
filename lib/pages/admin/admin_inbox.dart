import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

const inboxFolders = [('inbox', 'الوارد'), ('unread', 'غير المقروء'), ('starred', 'المميز'), ('archived', 'المؤرشف')];

/// البريد الوارد: صندوق لكل عضو باسمه على النطاق وصندوق مشترك؛ محادثات، رد وإنشاء، تمييز وأرشفة وإسناد، وإعدادات الاستقبال.
class AdminInboxPage extends ConsumerStatefulWidget {
  const AdminInboxPage({super.key});
  @override
  ConsumerState<AdminInboxPage> createState() => _AdminInboxPageState();
}

class _AdminInboxPageState extends ConsumerState<AdminInboxPage> {
  String? mailbox;
  String folder = 'inbox', query = '';

  void _refresh() { ref.invalidate(adminInboxMailboxesProvider); ref.invalidate(adminInboxProvider); }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(adminInboxMailboxesProvider);
    return info.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxMailboxesProvider)),
      data: (i) {
        if (i.mailboxes.isEmpty) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            EmptyState(icon: Icons.inbox_rounded, title: 'لا صندوق بريد لك بعد', subtitle: i.myMailbox.isEmpty ? 'اطلب من مديرك تعيين «صندوق البريد» في بيانات عضويتك (قسم الفريق) ليصبح لك عنوان باسمك على ${i.domain}.' : 'ليست لديك صلاحية قراءة البريد.'),
          ]);
        }
        final current = i.mailboxes.any((b) => b.alias == mailbox) ? mailbox! : i.mailboxes.first.alias;
        final box = i.mailboxes.firstWhere((b) => b.alias == current);
        final key = '$current|$folder';
        final threads = ref.watch(adminInboxProvider(key));
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          if (!i.receivingConfigured || (i.received == 0 && i.canManage))
            Padding(padding: const EdgeInsets.only(bottom: 10), child: JoyCard(key: const Key('inbox-banner'), color: Joy.sunSoft, child: Row(children: [
              const Icon(Icons.mark_email_unread_outlined, color: Joy.sunText),
              const SizedBox(width: 10),
              Expanded(child: Text(i.received == 0 ? 'لم تصل أي رسالة بعد. الإرسال يعمل، أما الاستقبال فيحتاج ربط الـ Webhook من إعدادات الاستقبال.' : 'الاستقبال غير مضبوط بعد.', style: const TextStyle(fontSize: 12.5, height: 1.5))),
              if (i.canManage) TextButton(onPressed: () => _settings(context), child: const Text('الإعداد')),
            ]))),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              key: const Key('inbox-mailbox'),
              initialValue: current,
              decoration: const InputDecoration(isDense: true, labelText: 'الصندوق'),
              items: [for (final b in i.mailboxes) DropdownMenuItem(value: b.alias, child: Row(mainAxisSize: MainAxisSize.min, children: [Text('${b.label} · ${b.address}', style: const TextStyle(fontSize: 13)), if (b.unread > 0) Container(margin: const EdgeInsetsDirectional.only(start: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Joy.accent, borderRadius: BorderRadius.circular(999)), child: Text('${b.unread}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))]))],
              onChanged: (v) => setState(() => mailbox = v),
            )),
            const SizedBox(width: 8),
            if (i.canReply) FilledButton.icon(key: const Key('inbox-compose'), onPressed: () => _compose(context, i, current), icon: const Icon(Icons.edit_outlined), label: const Text('رسالة')),
            if (i.canManage) IconButton(key: const Key('inbox-settings'), tooltip: 'إعدادات الاستقبال', onPressed: () => _settings(context), icon: const Icon(Icons.settings_outlined)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(key: const Key('inbox-search'), onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو الموضوع'))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [for (final f in inboxFolders) ChoiceChip(key: Key('inbox-folder-${f.$1}'), label: Text(f.$2), selected: folder == f.$1, onSelected: (_) => setState(() => folder = f.$1))]),
          const SizedBox(height: 10),
          threads.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxProvider(key))),
            data: (list) {
              final q = query.trim().toLowerCase();
              final items = q.isEmpty ? list : list.where((t) => t.subject.toLowerCase().contains(q) || t.who.toLowerCase().contains(q) || t.snippet.toLowerCase().contains(q)).toList();
              if (items.isEmpty) return EmptyState(icon: Icons.inbox_outlined, title: 'لا رسائل', subtitle: 'صندوق ${box.address} فارغ في هذا المجلد.');
              return JoyCard(padding: EdgeInsets.zero, child: Column(children: [
                for (final (idx, t) in items.indexed)
                  ListRow(
                    key: Key('inbox-thread-${t.id}'),
                    leading: Stack(clipBehavior: Clip.none, children: [
                      CircleAvatar(radius: 20, backgroundColor: t.lastDirection == 'out' ? Joy.primarySoft : Joy.surface2, child: Icon(t.lastDirection == 'out' ? Icons.reply_rounded : Icons.mail_outline_rounded, color: t.unread > 0 ? Joy.primary : Joy.textMuted, size: 20)),
                      if (t.unread > 0) Positioned(top: -2, right: -2, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Joy.accent, shape: BoxShape.circle))),
                    ]),
                    title: Row(children: [
                      Expanded(child: Text(t.who, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: t.unread > 0 ? FontWeight.w800 : FontWeight.w600))),
                      if (t.starred) const Icon(Icons.star_rounded, size: 16, color: Joy.sunText),
                      Text(timeAgo(t.lastAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                    ]),
                    subtitle: Text('${t.subject}\n${t.snippet}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.unread > 0 ? Joy.text : Joy.textMuted, fontWeight: t.unread > 0 ? FontWeight.w600 : null)),
                    trailing: t.assignedName.isNotEmpty ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(t.assignedName, style: const TextStyle(fontSize: 11, color: Joy.primary, fontWeight: FontWeight.w700))) : null,
                    onTap: () => _open(context, t.id, i),
                    divider: idx < items.length - 1,
                  ),
              ]));
            },
          ),
        ]);
      },
    );
  }

  Future<void> _open(BuildContext context, String id, InboxInfo i) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => InboxThreadSheet(threadId: id, info: i));
    _refresh();
  }

  Future<void> _compose(BuildContext context, InboxInfo i, String current) async {
    final body = await showModalBottomSheet<Map<String, String>>(context: context, isScrollControlled: true, builder: (_) => _ComposeSheet(mailboxes: i.mailboxes, initial: current));
    if (body == null || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).adminInboxCompose(mailbox: body['mailbox']!, to: body['to']!, subject: body['subject']!, text: body['text']!);
      _refresh();
      if (context.mounted) toast(context, 'أُرسلت الرسالة من ${body['mailbox']}@${i.domain}');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _settings(BuildContext context) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const InboxSettingsSheet());
    ref.invalidate(adminInboxMailboxesProvider);
  }
}

/// محادثة: الرسائل الواردة والصادرة، تمييز/أرشفة/إسناد، والرد بعنوان الصندوق.
class InboxThreadSheet extends ConsumerStatefulWidget {
  final String threadId;
  final InboxInfo info;
  const InboxThreadSheet({super.key, required this.threadId, required this.info});
  @override
  ConsumerState<InboxThreadSheet> createState() => _InboxThreadSheetState();
}

class _InboxThreadSheetState extends ConsumerState<InboxThreadSheet> {
  final reply = TextEditingController();
  bool busy = false;

  Future<void> _patch(Map<String, dynamic> body, String ok) async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminInboxUpdate(widget.threadId, body);
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() async {
    final text = reply.text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminInboxReply(widget.threadId, text: text);
      reply.clear();
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
      if (mounted) toast(context, 'أُرسل الرد');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _assign(InboxThreadDetail d) async {
    final team = await ref.read(adminTeamProvider.future).catchError((_) => const TeamInfo());
    if (!mounted) return;
    final picked = await showModalBottomSheet<String?>(context: context, builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
      const Text('إسناد المحادثة إلى', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      ListTile(leading: const Icon(Icons.person_off_outlined), title: const Text('بلا إسناد'), onTap: () => Navigator.pop(ctx, '')),
      for (final m in team.members.where((m) => m.active)) ListTile(key: Key('assign-${m.id}'), leading: const Icon(Icons.person_outline), title: Text(m.displayName), subtitle: Text(m.roleName, style: const TextStyle(fontSize: 11)), onTap: () => Navigator.pop(ctx, m.id)),
    ])));
    if (picked == null) return;
    await _patch({'assignedTo': picked.isEmpty ? null : picked}, picked.isEmpty ? 'أُلغي الإسناد' : 'أُسندت المحادثة');
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(adminInboxThreadProvider(widget.threadId));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      child: detail.when(
        loading: () => const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxThreadProvider(widget.threadId))),
        data: (d) {
          final t = d.thread;
          return SizedBox(
            height: MediaQuery.of(context).size.height * .85,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.subject, key: const Key('thread-subject'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${t.who} · عبر ${d.address}${t.assignedName.isNotEmpty ? ' · مسندة إلى ${t.assignedName}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                ])),
                IconButton(key: const Key('thread-star'), tooltip: 'تمييز', onPressed: busy ? null : () => _patch({'starred': !t.starred}, t.starred ? 'أُزيل التمييز' : 'مُيّزت'), icon: Icon(t.starred ? Icons.star_rounded : Icons.star_border_rounded, color: t.starred ? Joy.sunText : Joy.textMuted)),
                IconButton(key: const Key('thread-archive'), tooltip: t.archived ? 'إخراج من الأرشيف' : 'أرشفة', onPressed: busy ? null : () => _patch({'archived': !t.archived}, t.archived ? 'أُعيدت إلى الوارد' : 'أُرشفت'), icon: Icon(t.archived ? Icons.unarchive_outlined : Icons.archive_outlined, color: Joy.textMuted)),
                IconButton(key: const Key('thread-assign'), tooltip: 'إسناد', onPressed: busy ? null : () => _assign(d), icon: const Icon(Icons.person_add_alt_outlined, color: Joy.textMuted)),
              ]),
              const Divider(),
              Expanded(child: ListView(children: [
                for (final m in d.messages)
                  Align(
                    alignment: m.outgoing ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                    child: Container(
                      key: Key('msg-${m.id}'),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 640),
                      decoration: BoxDecoration(color: m.outgoing ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(m.outgoing ? '${m.sentByName.isNotEmpty ? m.sentByName : 'الفريق'} ← ${m.to.map((a) => a.email).join('، ')}' : '${m.from.name.isNotEmpty ? m.from.name : m.from.email}${m.from.name.isNotEmpty ? ' <${m.from.email}>' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                          Text(timeAgo(m.createdAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                        ]),
                        if (m.cc.isNotEmpty) Text('نسخة: ${m.cc.map((a) => a.email).join('، ')}', style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                        const SizedBox(height: 6),
                        SelectableText(m.text.isEmpty ? '(بلا نص)' : m.text, style: const TextStyle(height: 1.6, fontSize: 13.5)),
                        if (m.attachments.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [for (final a in m.attachments) Chip(avatar: const Icon(Icons.attach_file_rounded, size: 14), label: Text('${a['name'] ?? 'مرفق'}', style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)])),
                      ]),
                    ),
                  ),
              ])),
              if (widget.info.canReply) ...[
                const Divider(),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: TextField(key: const Key('thread-reply-field'), controller: reply, minLines: 1, maxLines: 6, decoration: InputDecoration(hintText: 'اكتب ردّك… يُرسل من ${d.address}', isDense: true))),
                  const SizedBox(width: 6),
                  IconButton.filled(key: const Key('thread-reply-send'), onPressed: busy ? null : _send, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded)),
                ]),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  final List<InboxMailbox> mailboxes;
  final String initial;
  const _ComposeSheet({required this.mailboxes, required this.initial});
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final to = TextEditingController(), subject = TextEditingController(), text = TextEditingController();
  late String mailbox = widget.initial;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('رسالة جديدة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(key: const Key('compose-mailbox'), initialValue: mailbox, decoration: const InputDecoration(labelText: 'من'), items: [for (final b in widget.mailboxes) DropdownMenuItem(value: b.alias, child: Text(b.address))], onChanged: (v) => setState(() => mailbox = v ?? mailbox)),
          const SizedBox(height: 8),
          TextField(key: const Key('compose-to'), controller: to, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'إلى', hintText: 'name@example.com')),
          const SizedBox(height: 8),
          TextField(key: const Key('compose-subject'), controller: subject, decoration: const InputDecoration(labelText: 'الموضوع')),
          const SizedBox(height: 8),
          TextField(key: const Key('compose-text'), controller: text, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'النص')),
          const SizedBox(height: 14),
          FilledButton.icon(key: const Key('compose-send'), onPressed: () {
            if (!to.text.contains('@')) { toast(context, 'اكتب بريد المستلم', error: true); return; }
            if (subject.text.trim().isEmpty || text.text.trim().isEmpty) { toast(context, 'الموضوع والنص مطلوبان', error: true); return; }
            Navigator.pop(context, {'mailbox': mailbox, 'to': to.text.trim(), 'subject': subject.text.trim(), 'text': text.text.trim()});
          }, icon: const Icon(Icons.send_rounded), label: const Text('إرسال')),
        ])),
      );
}

/// إعدادات الاستقبال: مزوّد الاستقبال، سر التوقيع، رابط الـ Webhook، والرمز العام.
class InboxSettingsSheet extends ConsumerStatefulWidget {
  const InboxSettingsSheet({super.key});
  @override
  ConsumerState<InboxSettingsSheet> createState() => _InboxSettingsSheetState();
}

class _InboxSettingsSheetState extends ConsumerState<InboxSettingsSheet> {
  final secret = TextEditingController();
  String? provider;
  bool busy = false;

  void _copy(String v) { Clipboard.setData(ClipboardData(text: v)); toast(context, 'نُسخ'); }

  Future<void> _rotate() async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminInboxSettingsSave({'rotateToken': true});
      ref.invalidate(adminInboxSettingsProvider);
      if (mounted) toast(context, 'جُدد الرمز؛ حدّث الرابط عند خدمة التحويل');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save(InboxSettings s) async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminInboxSettingsSave({'provider': provider ?? s.provider, if (secret.text.trim().isNotEmpty) 'webhookSecret': secret.text.trim()});
      secret.clear();
      ref.invalidate(adminInboxSettingsProvider);
      if (mounted) toast(context, 'حُفظت إعدادات الاستقبال');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(adminInboxSettingsProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: st.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxSettingsProvider)),
        data: (s) {
          final p = provider ?? s.provider;
          return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('إعدادات الاستقبال', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            Text('الإرسال يعمل عبر قسم البريد. الاستقبال يحتاج خدمة تستلم رسائل ${s.domain} وتدفعها إلى الخادم عبر Webhook. الرسائل إلى اسم عضو (sara@) تصل لصندوقه، والباقي إلى ${s.shared}.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('وصل حتى الآن: ${s.received} · مرفوض: ${s.rejected}${s.lastReceivedAt != null ? ' · آخر رسالة ${timeAgo(s.lastReceivedAt)}' : ''}', key: const Key('inbox-stats'), style: const TextStyle(fontSize: 12.5))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ChoiceChip(key: const Key('inbox-provider-resend'), label: const Text('Resend Receiving'), selected: p == 'resend', onSelected: (_) => setState(() => provider = 'resend')),
              ChoiceChip(key: const Key('inbox-provider-generic'), label: const Text('Webhook عام'), selected: p == 'generic', onSelected: (_) => setState(() => provider = 'generic')),
            ]),
            const SizedBox(height: 10),
            if (p == 'resend') ...[
              const Text('في لوحة Resend: Domains ثم naslife.app ثم Receiving وفعّله وأضف سجل MX الذي يعرضه في name.com. ثم Webhooks ثم Add Endpoint بهذا الرابط وحدث email.received، وانسخ Signing Secret إلى الحقل أدناه.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 8),
              _UrlRow(label: 'رابط الـ Webhook', value: s.resendUrl, onCopy: () => _copy(s.resendUrl), copyKey: const Key('inbox-copy-resend')),
              TextField(key: const Key('inbox-secret'), controller: secret, obscureText: true, textDirection: TextDirection.ltr, autocorrect: false, decoration: InputDecoration(labelText: 'Signing Secret (whsec_…)', helperText: s.hasSecret ? 'محفوظ؛ اتركه فارغاً للإبقاء عليه' : 'مطلوب للتحقق من أن الرسائل من Resend فعلاً')),
            ] else ...[
              const Text('أي خدمة تحويل بريد تدعم Webhook (مثل Cloudflare Email Workers أو ImprovMX) ترسل JSON فيه from وto وsubject وtext إلى هذا الرابط. الرمز في الرابط هو الحماية؛ لا تشاركه.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 8),
              _UrlRow(label: 'رابط الـ Webhook العام', value: s.genericUrl, onCopy: () => _copy(s.genericUrl), copyKey: const Key('inbox-copy-generic')),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(key: const Key('inbox-settings-save'), onPressed: busy ? null : () => _save(s), icon: const Icon(Icons.save_outlined), label: const Text('حفظ'))),
              const SizedBox(width: 8),
              TextButton(key: const Key('inbox-rotate'), onPressed: busy ? null : _rotate, child: const Text('تجديد الرمز')),
            ]),
          ]));
        },
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  final String label, value;
  final VoidCallback onCopy;
  final Key copyKey;
  const _UrlRow({required this.label, required this.value, required this.onCopy, required this.copyKey});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
          Row(children: [
            Expanded(child: SelectableText(value, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            IconButton(key: copyKey, tooltip: 'نسخ', iconSize: 18, visualDensity: VisualDensity.compact, onPressed: onCopy, icon: const Icon(Icons.copy_rounded)),
          ]),
        ]),
      );
}
