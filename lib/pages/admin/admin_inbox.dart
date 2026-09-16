import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_api.dart';
import '../../api/chat_tools_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/media.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

const inboxFolders = [('inbox', 'الوارد'), ('unread', 'غير المقروء'), ('waiting', 'بانتظار العميل'), ('snoozed', 'مؤجلة'), ('starred', 'المميز'), ('closed', 'مغلقة'), ('archived', 'المؤرشف')];
const threadStatuses = [('open', 'مفتوحة', Icons.mark_email_unread_outlined), ('waiting', 'بانتظار العميل', Icons.hourglass_bottom_rounded), ('closed', 'مغلقة', Icons.check_circle_outline)];
String threadStatusName(String s) => threadStatuses.firstWhere((x) => x.$1 == s, orElse: () => threadStatuses.first).$2;
Color threadStatusColor(String s) => switch (s) { 'closed' => Joy.success, 'waiting' => Joy.sunText, _ => Joy.primary };

/// البريد الوارد: صندوق لكل عضو باسمه على النطاق وصندوق مشترك؛ محادثات بحالة وتأجيل ووسوم، رد بقوالب ومرفقات،
/// ملاحظات داخلية، تمييز وأرشفة وإسناد، وإعدادات الاستقبال.
class AdminInboxPage extends ConsumerStatefulWidget {
  const AdminInboxPage({super.key});
  @override
  ConsumerState<AdminInboxPage> createState() => _AdminInboxPageState();
}

class _AdminInboxPageState extends ConsumerState<AdminInboxPage> {
  String? mailbox;
  String folder = 'inbox', query = '';

  void _refresh() { ref.invalidate(adminInboxMailboxesProvider); ref.invalidate(adminInboxProvider); ref.read(inboxUnreadProvider.notifier).refresh(); }

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
            if (i.canReply) IconButton(key: const Key('inbox-templates'), tooltip: 'الردود الجاهزة', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => TemplatesSheet(canShare: i.canManage)), icon: const Icon(Icons.article_outlined)),
            if (i.canManage) IconButton(key: const Key('inbox-settings'), tooltip: 'إعدادات الاستقبال', onPressed: () => _settings(context), icon: const Icon(Icons.settings_outlined)),
          ]),
          const SizedBox(height: 10),
          TextField(key: const Key('inbox-search'), onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو الموضوع')),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final f in inboxFolders) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(key: Key('inbox-folder-${f.$1}'), label: Text(f.$2), selected: folder == f.$1, onSelected: (_) => setState(() => folder = f.$1)))])),
          const SizedBox(height: 10),
          threads.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxProvider(key))),
            data: (list) {
              final q = query.trim().toLowerCase();
              final items = q.isEmpty ? list : list.where((t) => t.subject.toLowerCase().contains(q) || t.who.toLowerCase().contains(q) || t.snippet.toLowerCase().contains(q) || t.tags.any((x) => x.toLowerCase().contains(q))).toList();
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
                      if (t.snoozed) const Icon(Icons.snooze_rounded, size: 16, color: Joy.textMuted),
                      Text(timeAgo(t.lastAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                    ]),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t.subject}\n${t.snippet}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.unread > 0 ? Joy.text : Joy.textMuted, fontWeight: t.unread > 0 ? FontWeight.w600 : null)),
                      if (t.status != 'open' || t.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, children: [if (t.status != 'open') _pill(threadStatusName(t.status), threadStatusColor(t.status)), for (final g in t.tags) _pill('#$g', Joy.textMuted)])),
                    ]),
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
    final body = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => _ComposeSheet(mailboxes: i.mailboxes, initial: current));
    if (body == null || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).adminInboxCompose(mailbox: body['mailbox'] as String, to: body['to'] as String, subject: body['subject'] as String, text: body['text'] as String, attachments: (body['attachments'] as List<InboxAttachment>?) ?? const []);
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

Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));

/// اختيار ملف مرفق ورفعه إلى الخادم؛ يعيد null عند الإلغاء.
Future<InboxAttachment?> pickAttachment(BuildContext context, WidgetRef ref) async {
  Uint8List? bytes; String mime = 'application/octet-stream'; String name = 'file';
  if (kIsWeb && WebMedia.available) {
    final m = await WebMedia.pick('file');
    if (m == null) return null;
    bytes = m.bytes; mime = m.mime; name = m.name;
  } else {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (x == null) return null;
    bytes = await x.readAsBytes(); mime = x.mimeType ?? 'image/jpeg'; name = x.name;
  }
  if (bytes.length > 25 * 1024 * 1024) { if (context.mounted) toast(context, 'الملف أكبر من 25 ميغابايت', error: true); return null; }
  final up = await ref.read(apiClientProvider).uploadMedia(bytes, contentType: mime, fileName: name);
  return InboxAttachment(name: name, type: up.type, downloadUrl: up.url, size: up.size);
}

/// محادثة: الرسائل والملاحظات، الحالة والتأجيل والوسوم، تمييز/أرشفة/إسناد، الرد بقالب ومرفقات أو ملاحظة داخلية.
class InboxThreadSheet extends ConsumerStatefulWidget {
  final String threadId;
  final InboxInfo info;
  const InboxThreadSheet({super.key, required this.threadId, required this.info});
  @override
  ConsumerState<InboxThreadSheet> createState() => _InboxThreadSheetState();
}

class _InboxThreadSheetState extends ConsumerState<InboxThreadSheet> {
  final reply = TextEditingController();
  final attachments = <InboxAttachment>[];
  bool busy = false, noteMode = false;

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
    if (text.isEmpty && attachments.isEmpty) return;
    setState(() => busy = true);
    try {
      if (noteMode) {
        await ref.read(apiClientProvider).adminInboxNote(widget.threadId, text);
        if (mounted) toast(context, 'حُفظت الملاحظة الداخلية');
      } else {
        await ref.read(apiClientProvider).adminInboxReply(widget.threadId, text: text.isEmpty ? 'مرفق' : text, attachments: List.of(attachments));
        if (mounted) toast(context, 'أُرسل الرد');
      }
      reply.clear();
      attachments.clear();
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _attach() async {
    try {
      final a = await pickAttachment(context, ref);
      if (a != null && mounted) setState(() => attachments.add(a));
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _template() async {
    final picked = await showModalBottomSheet<InboxTemplate>(context: context, isScrollControlled: true, builder: (_) => TemplatesSheet(canShare: widget.info.canManage, pick: true));
    if (picked == null || !mounted) return;
    try {
      final text = await ref.read(apiClientProvider).adminInboxTemplateRender(picked.id, threadId: widget.threadId);
      if (!mounted) return;
      setState(() { noteMode = false; reply.text = reply.text.trim().isEmpty ? text : '${reply.text.trim()}\n$text'; });
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _snooze(InboxThread t) async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(key: const Key('snooze-hours'), leading: const Icon(Icons.snooze_rounded), title: const Text('بعد 3 ساعات'), onTap: () => Navigator.pop(ctx, 'h3')),
      ListTile(key: const Key('snooze-tomorrow'), leading: const Icon(Icons.wb_sunny_outlined), title: const Text('غداً صباحاً (9:00)'), onTap: () => Navigator.pop(ctx, 'tomorrow')),
      ListTile(key: const Key('snooze-week'), leading: const Icon(Icons.date_range_outlined), title: const Text('بعد أسبوع'), onTap: () => Navigator.pop(ctx, 'week')),
      if (t.snoozed) ListTile(key: const Key('snooze-cancel'), leading: const Icon(Icons.alarm_off_rounded), title: const Text('إلغاء التأجيل'), onTap: () => Navigator.pop(ctx, 'cancel')),
      const SizedBox(height: 8),
    ])));
    if (choice == null) return;
    final until = switch (choice) { 'h3' => now.add(const Duration(hours: 3)), 'tomorrow' => DateTime(now.year, now.month, now.day + 1, 9), 'week' => now.add(const Duration(days: 7)), _ => null };
    await _patch({'snoozeUntil': until?.toUtc().toIso8601String()}, until == null ? 'أُلغي التأجيل' : 'أُجّلت المحادثة');
  }

  Future<void> _tags(InboxThread t) async {
    final v = await askText(context, title: 'الوسوم', hint: 'مثال: vip، شكوى، شراكة', initial: t.tags.join('، '), confirm: 'حفظ');
    if (v == null) return;
    await _patch({'tags': v.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList()}, 'حُفظت الوسوم');
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
            height: MediaQuery.of(context).size.height * .88,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.subject, key: const Key('thread-subject'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${t.who} · عبر ${d.address}${t.assignedName.isNotEmpty ? ' · مسندة إلى ${t.assignedName}' : ''}${t.snoozed ? ' · مؤجلة حتى ${timeAgo(t.snoozeUntil)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                ])),
                IconButton(key: const Key('thread-star'), tooltip: 'تمييز', onPressed: busy ? null : () => _patch({'starred': !t.starred}, t.starred ? 'أُزيل التمييز' : 'مُيّزت'), icon: Icon(t.starred ? Icons.star_rounded : Icons.star_border_rounded, color: t.starred ? Joy.sunText : Joy.textMuted)),
                IconButton(key: const Key('thread-snooze'), tooltip: 'تأجيل', onPressed: busy ? null : () => _snooze(t), icon: Icon(Icons.snooze_rounded, color: t.snoozed ? Joy.primary : Joy.textMuted)),
                IconButton(key: const Key('thread-tags'), tooltip: 'وسوم', onPressed: busy ? null : () => _tags(t), icon: const Icon(Icons.label_outline_rounded, color: Joy.textMuted)),
                IconButton(key: const Key('thread-archive'), tooltip: t.archived ? 'إخراج من الأرشيف' : 'أرشفة', onPressed: busy ? null : () => _patch({'archived': !t.archived}, t.archived ? 'أُعيدت إلى الوارد' : 'أُرشفت'), icon: Icon(t.archived ? Icons.unarchive_outlined : Icons.archive_outlined, color: Joy.textMuted)),
                IconButton(key: const Key('thread-assign'), tooltip: 'إسناد', onPressed: busy ? null : () => _assign(d), icon: const Icon(Icons.person_add_alt_outlined, color: Joy.textMuted)),
              ]),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in threadStatuses) ChoiceChip(key: Key('thread-status-${s.$1}'), avatar: Icon(s.$3, size: 15), label: Text(s.$2, style: const TextStyle(fontSize: 12)), selected: t.status == s.$1, selectedColor: threadStatusColor(s.$1).withValues(alpha: .18), visualDensity: VisualDensity.compact, onSelected: busy || t.status == s.$1 ? null : (_) => _patch({'status': s.$1}, 'المحادثة الآن ${s.$2}')),
                for (final g in t.tags) _pill('#$g', Joy.textMuted),
              ]),
              const Divider(),
              Expanded(child: ListView(children: [
                for (final m in d.messages)
                  Align(
                    alignment: m.outgoing || m.note ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                    child: Container(
                      key: Key('msg-${m.id}'),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 640),
                      decoration: BoxDecoration(color: m.note ? Joy.sunSoft : m.outgoing ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(14), border: m.note ? Border.all(color: Joy.sunText.withValues(alpha: .4)) : null),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          if (m.note) const Padding(padding: EdgeInsetsDirectional.only(end: 6), child: Icon(Icons.sticky_note_2_outlined, size: 15, color: Joy.sunText)),
                          Expanded(child: Text(m.note ? 'ملاحظة داخلية · ${m.sentByName.isNotEmpty ? m.sentByName : m.from.name}' : m.outgoing ? '${m.sentByName.isNotEmpty ? m.sentByName : 'الفريق'} إلى ${m.to.map((a) => a.email).join('، ')}' : '${m.from.name.isNotEmpty ? m.from.name : m.from.email}${m.from.name.isNotEmpty ? ' <${m.from.email}>' : ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: m.note ? Joy.sunText : null), overflow: TextOverflow.ellipsis)),
                          Text(timeAgo(m.createdAt), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                        ]),
                        if (m.cc.isNotEmpty) Text('نسخة: ${m.cc.map((a) => a.email).join('، ')}', style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
                        const SizedBox(height: 6),
                        SelectableText(m.text.isEmpty ? '(بلا نص)' : m.text, style: const TextStyle(height: 1.6, fontSize: 13.5)),
                        if (m.attachments.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final a in m.attachments)
                            ActionChip(
                              key: Key('att-${m.id}-${a.name}'),
                              avatar: const Icon(Icons.attach_file_rounded, size: 14),
                              label: Text('${a.name}${a.size > 0 ? ' · ${(a.size / 1024).ceil()} ك.ب' : ''}', style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              onPressed: a.downloadUrl == null ? null : () => _openAttachment(a.downloadUrl!),
                            ),
                        ])),
                      ]),
                    ),
                  ),
              ])),
              if (widget.info.canReply) ...[
                const Divider(),
                if (attachments.isNotEmpty) Wrap(spacing: 6, children: [for (final a in attachments) InputChip(key: Key('pending-att-${a.name}'), avatar: const Icon(Icons.attach_file_rounded, size: 14), label: Text(a.name, style: const TextStyle(fontSize: 11)), onDeleted: () => setState(() => attachments.remove(a)))]),
                Row(children: [
                  ChoiceChip(key: const Key('thread-mode-reply'), label: const Text('رد للعميل', style: TextStyle(fontSize: 12)), selected: !noteMode, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => noteMode = false)),
                  const SizedBox(width: 6),
                  ChoiceChip(key: const Key('thread-mode-note'), label: const Text('ملاحظة داخلية', style: TextStyle(fontSize: 12)), selected: noteMode, selectedColor: Joy.sunSoft, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => noteMode = true)),
                  const Spacer(),
                  if (!noteMode) IconButton(key: const Key('thread-template'), tooltip: 'رد جاهز', onPressed: busy ? null : _template, icon: const Icon(Icons.article_outlined, size: 20, color: Joy.textMuted)),
                  if (!noteMode) IconButton(key: const Key('thread-attach'), tooltip: 'إرفاق ملف', onPressed: busy ? null : _attach, icon: const Icon(Icons.attach_file_rounded, size: 20, color: Joy.textMuted)),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: TextField(key: const Key('thread-reply-field'), controller: reply, minLines: 1, maxLines: 6, decoration: InputDecoration(hintText: noteMode ? 'ملاحظة يراها الفريق فقط…' : 'اكتب ردّك… يُرسل من ${d.address}', isDense: true, filled: noteMode, fillColor: noteMode ? Joy.sunSoft : null))),
                  const SizedBox(width: 6),
                  IconButton.filled(key: const Key('thread-reply-send'), style: noteMode ? IconButton.styleFrom(backgroundColor: Joy.sunText) : null, onPressed: busy ? null : _send, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(noteMode ? Icons.sticky_note_2_outlined : Icons.send_rounded)),
                ]),
              ],
            ]),
          );
        },
      ),
    );
  }

  Future<void> _openAttachment(String url) async {
    final api = ref.read(apiClientProvider);
    final full = url.startsWith('http') ? url : '${api.baseUrl}$url${url.contains('?') ? '&' : '?'}token=${api.token ?? ''}';
    await launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
  }
}

/// الردود الجاهزة: قائمة القوالب المشتركة والخاصة، إنشاء وتعديل وحذف، أو اختيار قالب لإدراجه.
class TemplatesSheet extends ConsumerStatefulWidget {
  final bool canShare, pick;
  const TemplatesSheet({super.key, required this.canShare, this.pick = false});
  @override
  ConsumerState<TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends ConsumerState<TemplatesSheet> {
  Future<void> _edit(InboxTemplate? t) async {
    final title = TextEditingController(text: t?.title ?? ''), body = TextEditingController(text: t?.body ?? '');
    var shared = t?.shared ?? widget.canShare;
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
      title: Text(t == null ? 'قالب جديد' : 'تعديل القالب'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(key: const Key('template-title'), controller: title, decoration: const InputDecoration(labelText: 'الاسم', hintText: 'ترحيب')),
        const SizedBox(height: 8),
        TextField(key: const Key('template-body'), controller: body, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'النص', helperText: 'متغيرات: {{name}} {{email}} {{agent}} {{mailbox}}', helperMaxLines: 2)),
        if (widget.canShare) SwitchListTile(key: const Key('template-shared'), contentPadding: EdgeInsets.zero, value: shared, onChanged: (v) => setD(() => shared = v), title: const Text('مشترك لكل الفريق', style: TextStyle(fontSize: 13))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), FilledButton(key: const Key('template-save'), onPressed: () => Navigator.pop(d, true), child: const Text('حفظ'))],
    )));
    if (ok != true || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      if (t == null) {
        await api.adminInboxTemplateCreate(title: title.text, body: body.text, shared: shared);
      } else {
        await api.adminInboxTemplateUpdate(t.id, {'title': title.text.trim(), 'body': body.text.trim(), if (widget.canShare) 'shared': shared});
      }
      ref.invalidate(adminInboxTemplatesProvider);
      if (mounted) toast(context, 'حُفظ القالب');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminInboxTemplatesProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(widget.pick ? 'اختر رداً جاهزاً' : 'الردود الجاهزة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          TextButton.icon(key: const Key('template-new'), onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('قالب جديد')),
        ]),
        const SizedBox(height: 8),
        Flexible(child: list.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxTemplatesProvider)),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('لا قوالب بعد. أنشئ قالباً مثل «ترحيب» أو «تم استلام طلبك».', style: TextStyle(color: Joy.textMuted)))
              : ListView(shrinkWrap: true, children: [
                  for (final t in items)
                    ListTile(
                      key: Key('template-${t.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(t.shared ? Icons.groups_outlined : Icons.lock_outline, color: Joy.textMuted),
                      title: Text(t.title),
                      subtitle: Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      trailing: widget.pick ? const Icon(Icons.add_circle_outline, color: Joy.primary) : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'تعديل', onPressed: () => _edit(t), icon: const Icon(Icons.edit_outlined, size: 18)),
                        IconButton(key: Key('template-delete-${t.id}'), tooltip: 'حذف', onPressed: () async { try { await ref.read(apiClientProvider).adminInboxTemplateDelete(t.id); ref.invalidate(adminInboxTemplatesProvider); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); } }, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger)),
                      ]),
                      onTap: widget.pick ? () => Navigator.pop(context, t) : () => _edit(t),
                    ),
                ]),
        )),
      ]),
    );
  }
}

class _ComposeSheet extends ConsumerStatefulWidget {
  final List<InboxMailbox> mailboxes;
  final String initial;
  const _ComposeSheet({required this.mailboxes, required this.initial});
  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final to = TextEditingController(), subject = TextEditingController(), text = TextEditingController();
  final attachments = <InboxAttachment>[];
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
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(key: const Key('compose-template'), onPressed: () async {
              final t = await showModalBottomSheet<InboxTemplate>(context: context, isScrollControlled: true, builder: (_) => const TemplatesSheet(canShare: false, pick: true));
              if (t == null || !context.mounted) return;
              try { final r = await ref.read(apiClientProvider).adminInboxTemplateRender(t.id); setState(() => text.text = text.text.trim().isEmpty ? r : '${text.text.trim()}\n$r'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); }
            }, icon: const Icon(Icons.article_outlined, size: 18), label: const Text('رد جاهز')),
            TextButton.icon(key: const Key('compose-attach'), onPressed: () async { try { final a = await pickAttachment(context, ref); if (a != null) setState(() => attachments.add(a)); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); } }, icon: const Icon(Icons.attach_file_rounded, size: 18), label: const Text('إرفاق')),
          ]),
          if (attachments.isNotEmpty) Wrap(spacing: 6, children: [for (final a in attachments) InputChip(avatar: const Icon(Icons.attach_file_rounded, size: 14), label: Text(a.name, style: const TextStyle(fontSize: 11)), onDeleted: () => setState(() => attachments.remove(a)))]),
          const SizedBox(height: 14),
          FilledButton.icon(key: const Key('compose-send'), onPressed: () {
            if (!to.text.contains('@')) { toast(context, 'اكتب بريد المستلم', error: true); return; }
            if (subject.text.trim().isEmpty || text.text.trim().isEmpty) { toast(context, 'الموضوع والنص مطلوبان', error: true); return; }
            Navigator.pop(context, <String, dynamic>{'mailbox': mailbox, 'to': to.text.trim(), 'subject': subject.text.trim(), 'text': text.text.trim(), 'attachments': List<InboxAttachment>.of(attachments)});
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
            Text('وصل حتى الآن: ${s.received} · مرفوض: ${s.rejected}${s.lastReceivedAt != null ? ' · آخر رسالة ${timeAgo(s.lastReceivedAt)}' : ''}', key: const Key('inbox-stats'), style: const TextStyle(fontSize: 12.5)),
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
