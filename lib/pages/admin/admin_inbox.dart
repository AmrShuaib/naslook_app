import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_api.dart';
import '../../api/client.dart';
import '../../api/chat_tools_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/media.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';
import 'admin_tasks.dart';
import 'admin_users.dart';

const inboxFolders = [('inbox', 'الوارد'), ('unread', 'غير المقروء'), ('waiting', 'بانتظار العميل'), ('snoozed', 'مؤجلة'), ('starred', 'المميز'), ('closed', 'مغلقة'), ('archived', 'المؤرشف'), ('spam', 'المزعج')];
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
  String? mailbox, tag;
  String folder = 'inbox', query = '';

  void _refresh() { ref.invalidate(adminInboxMailboxesProvider); ref.invalidate(adminInboxProvider); ref.invalidate(adminInboxTagsProvider); ref.read(inboxUnreadProvider.notifier).refresh(); }

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
        final key = '$current|$folder|${tag ?? ''}';
        final threads = ref.watch(adminInboxProvider(key));
        final tags = ref.watch(adminInboxTagsProvider(current)).valueOrNull ?? const <(String, int)>[];
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
          ]),
          const SizedBox(height: 4),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            if (i.canReply) IconButton(key: const Key('inbox-templates'), tooltip: 'الردود الجاهزة', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => TemplatesSheet(canShare: i.canManage)), icon: const Icon(Icons.article_outlined)),
            if (i.canReply) IconButton(key: const Key('inbox-me'), tooltip: 'توقيعي ورد الغياب', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const InboxMeSheet()), icon: const Icon(Icons.draw_outlined)),
            if (i.canReply) IconButton(key: const Key('inbox-outbox'), tooltip: 'الرسائل المجدولة', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const OutboxSheet()), icon: const Icon(Icons.schedule_send_outlined)),
            IconButton(key: const Key('inbox-stats'), tooltip: 'المؤشرات', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const InboxStatsSheet()), icon: const Icon(Icons.insights_outlined)),
            if (i.canManage) IconButton(key: const Key('inbox-rules'), tooltip: 'القواعد التلقائية', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const InboxRulesSheet()), icon: const Icon(Icons.auto_fix_high_outlined)),
            if (i.canManage) IconButton(key: const Key('inbox-blocked'), tooltip: 'المرسلون المحظورون', onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const BlockedSheet()), icon: const Icon(Icons.block_outlined)),
            if (i.canManage) IconButton(key: const Key('inbox-settings'), tooltip: 'إعدادات الاستقبال', onPressed: () => _settings(context), icon: const Icon(Icons.settings_outlined)),
          ])),
          const SizedBox(height: 6),
          TextField(key: const Key('inbox-search'), onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو الموضوع')),
          if (query.trim().length >= 2) Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('inbox-search-all'), onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => SearchResultsSheet(q: query.trim(), info: i)).then((_) => _refresh()), icon: const Icon(Icons.manage_search_rounded, size: 18), label: Text('ابحث عن «${query.trim()}» في نصوص الرسائل في كل صناديقك'))),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final f in inboxFolders) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(key: Key('inbox-folder-${f.$1}'), label: Text(f.$2), selected: folder == f.$1, onSelected: (_) => setState(() => folder = f.$1)))])),
          if (tags.isNotEmpty || tag != null) Padding(padding: const EdgeInsets.only(top: 6), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            const Icon(Icons.label_outline_rounded, size: 16, color: Joy.textMuted),
            const SizedBox(width: 6),
            if (tag != null) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: InputChip(key: const Key('inbox-tag-clear'), label: Text('#$tag'), selected: true, visualDensity: VisualDensity.compact, onDeleted: () => setState(() => tag = null), onPressed: () => setState(() => tag = null))),
            for (final g in tags) if (g.$1 != tag) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: FilterChip(key: Key('inbox-tag-${g.$1}'), label: Text('#${g.$1} · ${g.$2}', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => tag = g.$1))),
          ]))),
          const SizedBox(height: 10),
          threads.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxProvider(key))),
            data: (list) {
              final q = query.trim().toLowerCase();
              final items = q.isEmpty ? list : list.where((t) => t.subject.toLowerCase().contains(q) || t.who.toLowerCase().contains(q) || t.snippet.toLowerCase().contains(q) || t.tags.any((x) => x.toLowerCase().contains(q))).toList();
              if (items.isEmpty) return EmptyState(icon: Icons.inbox_outlined, title: 'لا رسائل', subtitle: tag != null ? 'لا محادثات بالوسم #$tag في هذا المجلد.' : 'صندوق ${box.address} فارغ في هذا المجلد.');
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
                      if (t.status != 'open' || t.tags.isNotEmpty || t.spam) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, children: [if (t.spam) _pill('مزعج', Joy.danger), if (t.status != 'open') _pill(threadStatusName(t.status), threadStatusColor(t.status)), for (final g in t.tags) _pill('#$g', Joy.textMuted)])),
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
      final sendAt = body['sendAt'] as DateTime?;
      await ref.read(apiClientProvider).adminInboxCompose(mailbox: body['mailbox'] as String, to: body['to'] as String, subject: body['subject'] as String, text: body['text'] as String, attachments: (body['attachments'] as List<InboxAttachment>?) ?? const [], sendAt: sendAt);
      _refresh();
      ref.invalidate(adminInboxOutboxProvider);
      if (context.mounted) toast(context, sendAt == null ? 'أُرسلت الرسالة من ${body['mailbox']}@${i.domain}' : 'ستُرسل الرسالة ${dueText(sendAt)}');
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
  bool busy = false, noteMode = false, _typingSent = false, _draftLoaded = false, _needsFresh = true;
  List<InboxViewer> others = const [];
  Timer? _presence, _draftTimer;
  String _lastSavedDraft = '';
  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    // تحديث المحادثة عند كل فتح (المسودة والمجدول والزوار تتغير بين فتح وآخر)؛ بعد اكتمال البناء الحالي
    Future.microtask(() { if (mounted) ref.invalidate(adminInboxThreadProvider(widget.threadId)); });
    final every = ref.read(inboxPresenceIntervalProvider);
    if (every != null) _presence = Timer.periodic(every, (_) => _heartbeat());
    reply.addListener(() {
      final typing = reply.text.trim().isNotEmpty;
      if (typing != _typingSent) _heartbeat();
      if (!noteMode) { _draftTimer?.cancel(); _draftTimer = Timer(ref.read(inboxDraftDebounceProvider), _saveDraft); }
    });
  }

  /// حفظ تلقائي للمسودة بعد توقف الكتابة (لا يُحفظ ما لم يتغير)
  Future<void> _saveDraft() async {
    final text = reply.text.trim();
    if (noteMode || text == _lastSavedDraft) return;
    _lastSavedDraft = text;
    try { await _api.adminInboxDraftSave(threadId: widget.threadId, text: text); } catch (_) { /* تُحاول لاحقاً */ }
  }

  void _restoreDraft(InboxThreadDetail d) {
    if (_draftLoaded) return;
    _draftLoaded = true;
    final text = d.draftText;
    if (text.isEmpty || reply.text.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (!mounted) return; _lastSavedDraft = text; reply.text = text; toast(context, 'استُعيدت مسودتك المحفوظة'); });
  }

  Future<void> _ai(String kind) async {
    setState(() => busy = true);
    try {
      final text = await _api.adminInboxAi(widget.threadId, kind);
      if (!mounted) return;
      setState(() => busy = false);
      if (kind == 'reply') {
        setState(() { noteMode = false; reply.text = reply.text.trim().isEmpty ? text : '${reply.text.trim()}\n\n$text'; });
        toast(context, 'أُدرجت مسودة الرد؛ راجعها قبل الإرسال');
      } else {
        await showDialog<void>(context: context, builder: (d) => AlertDialog(
          title: const Row(children: [Icon(Icons.auto_awesome_outlined, color: Joy.primary), SizedBox(width: 8), Text('ملخص المحادثة')]),
          content: SingleChildScrollView(child: SelectableText(text, key: const Key('ai-summary'), style: const TextStyle(height: 1.7))),
          actions: [TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: text)); Navigator.pop(d); }, child: const Text('نسخ')), FilledButton(onPressed: () => Navigator.pop(d), child: const Text('حسناً'))],
        ));
      }
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _spam(InboxThread t) async {
    if (t.spam) {
      try { await _api.adminInboxSpam(widget.threadId, undo: true); ref.invalidate(adminInboxThreadProvider(widget.threadId)); if (mounted) toast(context, 'أُعيدت المحادثة وأُلغي الحظر'); } catch (e) { if (mounted) toast(context, adminErrText(e), error: true); }
      return;
    }
    final domain = t.counterpart.contains('@') ? t.counterpart.split('@').last : '';
    final choice = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: const Text('تعليم كمزعج'),
      content: Text('تُنقل هذه المحادثة (وكل محادثات ${t.counterpart}) إلى مجلد المزعج بلا إشعارات. هل تحظر المرسل أيضاً؟', style: const TextStyle(height: 1.6)),
      actions: [
        TextButton(key: const Key('spam-cancel'), onPressed: () => Navigator.pop(d), child: const Text('تراجع')),
        TextButton(key: const Key('spam-only'), onPressed: () => Navigator.pop(d, 'only'), child: const Text('نقل فقط')),
        if (domain.isNotEmpty) TextButton(key: const Key('spam-domain'), onPressed: () => Navigator.pop(d, 'domain'), child: Text('حظر @$domain')),
        FilledButton(key: const Key('spam-sender'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, 'sender'), child: const Text('حظر المرسل')),
      ],
    ));
    if (choice == null || !mounted) return;
    try {
      await _api.adminInboxSpam(widget.threadId, domain: choice == 'domain', block: choice != 'only');
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
      ref.invalidate(adminInboxBlockedProvider);
      if (mounted) toast(context, choice == 'only' ? 'نُقلت إلى المزعج' : 'نُقلت إلى المزعج وحُظر المرسل');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _schedule() async {
    final when = await pickSendTime(context);
    if (when == null) return;
    await _send(sendAt: when);
  }

  Future<void> _cancelScheduled(InboxOutboxItem o) async {
    try { await _api.adminInboxOutboxCancel(o.id); ref.invalidate(adminInboxThreadProvider(widget.threadId)); ref.invalidate(adminInboxOutboxProvider); if (mounted) toast(context, 'أُلغي الإرسال المجدول'); } catch (e) { if (mounted) toast(context, adminErrText(e), error: true); }
  }

  @override
  void dispose() {
    _presence?.cancel();
    _draftTimer?.cancel();
    // مغادرة المحادثة: يُقرأ العميل مسبقاً لأن ref لا يُستخدم بعد التخلص
    _api.adminInboxPresence(widget.threadId, leave: true).catchError((_) => const <InboxViewer>[]);
    reply.dispose();
    super.dispose();
  }

  /// نبضة تواجد: أنا هنا (وأكتب؟) وتعود بمن سواي على المحادثة
  Future<void> _heartbeat() async {
    final typing = reply.text.trim().isNotEmpty && !noteMode;
    _typingSent = typing;
    try {
      final o = await _api.adminInboxPresence(widget.threadId, typing: typing);
      if (mounted) setState(() => others = o);
    } catch (_) {
      // بلا شبكة: نُبقي آخر حالة
    }
  }

  Future<void> _toTask(InboxThreadDetail d) async {
    final l = await ref.read(adminTasksProvider('mine|open').future).catchError((_) => const TaskList());
    if (!mounted) return;
    final t = d.thread;
    final body = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => TaskEditorSheet(
      assignees: l.assignees, canAssign: l.canAssign || l.canManage,
      initialTitle: t.subject, initialDescription: 'من بريد ${t.who} <${t.counterpart}> عبر ${d.address}:\n${t.snippet}',
      related: {'type': 'inbox', 'id': t.id, 'label': t.subject},
    ));
    if (body == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).adminTaskCreate(body);
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
      ref.invalidate(adminTasksProvider);
      ref.invalidate(adminTasksSummaryProvider);
      if (mounted) toast(context, 'أُنشئت المهمة من هذه المحادثة');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _patch(Map<String, dynamic> body, String ok) async {
    setState(() => busy = true);
    try {
      final r = await ref.read(apiClientProvider).adminInboxUpdate(widget.threadId, body);
      ref.invalidate(adminInboxThreadProvider(widget.threadId));
      if (mounted) toast(context, r.ratingSent ? '$ok وأُرسل للعميل طلب تقييم' : ok);
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send({DateTime? sendAt}) async {
    final text = reply.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    setState(() => busy = true);
    try {
      if (noteMode) {
        await ref.read(apiClientProvider).adminInboxNote(widget.threadId, text);
        if (mounted) toast(context, 'حُفظت الملاحظة الداخلية');
      } else {
        await ref.read(apiClientProvider).adminInboxReply(widget.threadId, text: text.isEmpty ? 'مرفق' : text, attachments: List.of(attachments), sendAt: sendAt);
        _draftTimer?.cancel();
        _lastSavedDraft = '';
        ref.invalidate(adminInboxOutboxProvider);
        if (mounted) toast(context, sendAt == null ? 'أُرسل الرد' : 'ستُرسل ${dueText(sendAt)}');
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
        loading: () { _needsFresh = false; return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())); },
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxThreadProvider(widget.threadId))),
        data: (d) {
          final t = d.thread;
          // لا تُستعاد المسودة من نسخة مخزّنة قديمة؛ ننتظر التحديث الطازج
          if (detail.isRefreshing) { _needsFresh = false; } else if (!_needsFresh) { _restoreDraft(d); }
          final present = others.isNotEmpty ? others : d.viewers;
          final typingNames = present.where((v) => v.typing).map((v) => v.name).toList();
          final c = d.customer;
          return SizedBox(
            height: MediaQuery.of(context).size.height * .88,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (present.isNotEmpty)
                Container(
                  key: const Key('thread-presence'),
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: typingNames.isNotEmpty ? Joy.danger.withValues(alpha: .1) : Joy.sunSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: (typingNames.isNotEmpty ? Joy.danger : Joy.sunText).withValues(alpha: .35))),
                  child: Row(children: [
                    Icon(typingNames.isNotEmpty ? Icons.keyboard_alt_outlined : Icons.visibility_outlined, size: 18, color: typingNames.isNotEmpty ? Joy.danger : Joy.sunText),
                    const SizedBox(width: 8),
                    Expanded(child: Text(typingNames.isNotEmpty ? '${typingNames.join('، ')} يكتب رداً على هذه المحادثة الآن؛ انتبه من الرد المكرر' : '${present.map((v) => v.name).join('، ')} يفتح هذه المحادثة الآن', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: typingNames.isNotEmpty ? Joy.danger : Joy.sunText))),
                  ]),
                ),
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
                IconButton(key: Key(t.spam ? 'thread-unspam' : 'thread-spam'), tooltip: t.spam ? 'ليس مزعجاً' : 'مزعج', onPressed: busy ? null : () => _spam(t), icon: Icon(t.spam ? Icons.restore_from_trash_outlined : Icons.report_gmailerrorred_outlined, color: t.spam ? Joy.danger : Joy.textMuted)),
              ]),
              if (t.spam) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('في مجلد المزعج: لا إشعارات ولا ردود تلقائية لهذا المرسل.', key: const Key('thread-spam-note'), style: const TextStyle(color: Joy.danger, fontSize: 12, fontWeight: FontWeight.w700))),
              if (d.scheduled.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: [
                for (final o in d.scheduled) InputChip(key: Key('scheduled-${o.id}'), avatar: const Icon(Icons.schedule_send_outlined, size: 15, color: Joy.primary), label: Text('مجدولة: ${dueText(o.sendAt)}', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, deleteButtonTooltipMessage: 'إلغاء', onDeleted: busy ? null : () => _cancelScheduled(o)),
              ]),
              if (c != null)
                Container(
                  key: const Key('thread-customer'),
                  margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    CircleAvatar(radius: 16, backgroundColor: c.known ? Joy.primarySoft : Joy.surface, backgroundImage: c.avatarUrl != null && c.avatarUrl!.isNotEmpty ? NetworkImage(c.avatarUrl!) : null, child: c.avatarUrl != null && c.avatarUrl!.isNotEmpty ? null : Icon(c.known ? Icons.person_rounded : Icons.person_outline, size: 18, color: c.known ? Joy.primary : Joy.textMuted)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(c.known ? '${c.nickname.isNotEmpty ? c.nickname : c.userId} · ${c.userId}' : 'غير مسجّل في ناس لايف', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                        if (c.known && c.verified) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.verified_rounded, size: 14, color: Joy.primary)),
                        if (c.suspended) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: _pill('موقوف', Joy.danger)),
                      ]),
                      Text('${c.threads} ${c.threads == 1 ? 'محادثة' : 'محادثات'} معنا${c.since != null ? ' منذ ${timeAgo(c.since)}' : ''}${c.memberSince != null ? ' · عضو منذ ${timeAgo(c.memberSince)}' : ''}', style: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
                    ])),
                    if (c.known) TextButton(key: const Key('thread-customer-open'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: c.userId!))), child: const Text('ملف المستخدم')),
                  ]),
                ),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in threadStatuses) ChoiceChip(key: Key('thread-status-${s.$1}'), avatar: Icon(s.$3, size: 15), label: Text(s.$2, style: const TextStyle(fontSize: 12)), selected: t.status == s.$1, selectedColor: threadStatusColor(s.$1).withValues(alpha: .18), visualDensity: VisualDensity.compact, onSelected: busy || t.status == s.$1 ? null : (_) => _patch({'status': s.$1}, 'المحادثة الآن ${s.$2}')),
                for (final g in t.tags) _pill('#$g', Joy.textMuted),
                for (final k in d.tasks)
                  ActionChip(key: Key('thread-task-${k.id}'), avatar: Icon(k.status == 'done' ? Icons.task_alt_rounded : Icons.assignment_outlined, size: 15, color: statusColor(k.status)), label: Text(k.title, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => TaskDetailSheet(taskId: k.id))),
                ActionChip(key: const Key('thread-to-task'), avatar: const Icon(Icons.add_task_rounded, size: 15, color: Joy.primary), label: const Text('حوّل إلى مهمة', style: TextStyle(fontSize: 12, color: Joy.primary)), visualDensity: VisualDensity.compact, onPressed: busy ? null : () => _toTask(d)),
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
                  if (widget.info.aiEnabled) IconButton(key: const Key('thread-ai-summary'), tooltip: 'ملخص ذكي', onPressed: busy ? null : () => _ai('summary'), icon: const Icon(Icons.auto_awesome_outlined, size: 20, color: Joy.primary)),
                  if (widget.info.aiEnabled && !noteMode) IconButton(key: const Key('thread-ai-reply'), tooltip: 'اقترح رداً', onPressed: busy ? null : () => _ai('reply'), icon: const Icon(Icons.auto_fix_high_outlined, size: 20, color: Joy.primary)),
                  if (!noteMode) IconButton(key: const Key('thread-template'), tooltip: 'رد جاهز', onPressed: busy ? null : _template, icon: const Icon(Icons.article_outlined, size: 20, color: Joy.textMuted)),
                  if (!noteMode) IconButton(key: const Key('thread-attach'), tooltip: 'إرفاق ملف', onPressed: busy ? null : _attach, icon: const Icon(Icons.attach_file_rounded, size: 20, color: Joy.textMuted)),
                  if (!noteMode) IconButton(key: const Key('thread-schedule'), tooltip: 'إرسال لاحقاً', onPressed: busy ? null : _schedule, icon: const Icon(Icons.schedule_send_outlined, size: 20, color: Joy.textMuted)),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: TextField(key: const Key('thread-reply-field'), controller: reply, minLines: 1, maxLines: 6, decoration: InputDecoration(hintText: noteMode ? 'ملاحظة يراها الفريق فقط…' : 'اكتب ردّك… يُرسل من ${d.address}', helperText: !noteMode && d.signature.isNotEmpty ? 'سيُضاف توقيعك تلقائياً في نهاية الرد' : null, isDense: true, filled: noteMode, fillColor: noteMode ? Joy.sunSoft : null))),
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
  Timer? _draftTimer;
  String _saved = '';

  @override
  void initState() {
    super.initState();
    for (final c in [to, subject, text]) { c.addListener(() { _draftTimer?.cancel(); _draftTimer = Timer(ref.read(inboxDraftDebounceProvider), _saveDraft); }); }
    _restore();
  }

  Future<void> _restore() async {
    try {
      final drafts = await ref.read(apiClientProvider).adminInboxDrafts();
      final d = drafts.where((x) => x['threadId'] == null).firstOrNull;
      if (d == null || !mounted) return;
      to.text = d['to']?.toString() ?? ''; subject.text = d['subject']?.toString() ?? ''; text.text = d['text']?.toString() ?? '';
      final mb = d['mailbox']?.toString() ?? '';
      if (widget.mailboxes.any((b) => b.alias == mb)) setState(() => mailbox = mb);
      _saved = '${to.text}|${subject.text}|${text.text}';
      if (mounted) toast(context, 'استُعيدت مسودة رسالتك');
    } catch (_) { /* بلا مسودة */ }
  }

  Future<void> _saveDraft() async {
    final sig = '${to.text}|${subject.text}|${text.text}';
    if (sig == _saved) return;
    _saved = sig;
    try { await ref.read(apiClientProvider).adminInboxDraftSave(text: text.text.trim(), to: to.text.trim(), subject: subject.text.trim(), mailbox: mailbox); } catch (_) { /* تُحاول لاحقاً */ }
  }

  @override
  void dispose() { _draftTimer?.cancel(); super.dispose(); }

  Map<String, dynamic>? _body(BuildContext context) {
    if (!to.text.contains('@')) { toast(context, 'اكتب بريد المستلم', error: true); return null; }
    if (subject.text.trim().isEmpty || text.text.trim().isEmpty) { toast(context, 'الموضوع والنص مطلوبان', error: true); return null; }
    _draftTimer?.cancel();
    return <String, dynamic>{'mailbox': mailbox, 'to': to.text.trim(), 'subject': subject.text.trim(), 'text': text.text.trim(), 'attachments': List<InboxAttachment>.of(attachments)};
  }

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
          Row(children: [
            Expanded(child: FilledButton.icon(key: const Key('compose-send'), onPressed: () { final b = _body(context); if (b != null) Navigator.pop(context, b); }, icon: const Icon(Icons.send_rounded), label: const Text('إرسال'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const Key('compose-schedule'), onPressed: () async { final b = _body(context); if (b == null) return; final when = await pickSendTime(context); if (when == null || !context.mounted) return; Navigator.pop(context, {...b, 'sendAt': when}); }, icon: const Icon(Icons.schedule_send_outlined, size: 18), label: const Text('لاحقاً')),
          ]),
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
  final secret = TextEditingController(), sharedSig = TextEditingController(), sharedAwayText = TextEditingController(), aiKey = TextEditingController();
  String? provider, aiModel;
  bool? sharedAway, csat;
  bool busy = false, seeded = false;

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
      await ref.read(apiClientProvider).adminInboxSettingsSave({
        'provider': provider ?? s.provider,
        if (secret.text.trim().isNotEmpty) 'webhookSecret': secret.text.trim(),
        if (sharedSig.text.trim() != s.sharedSignature) 'sharedSignature': sharedSig.text.trim(),
        if ((sharedAway ?? s.sharedAway) != s.sharedAway) 'sharedAway': sharedAway,
        if (sharedAwayText.text.trim() != s.sharedAwayText) 'sharedAwayText': sharedAwayText.text.trim(),
        if (csat != null && csat != s.csat) 'csat': csat,
        if (aiKey.text.trim().isNotEmpty) 'aiKey': aiKey.text.trim(),
        if (aiModel != null && aiModel != s.aiModel) 'aiModel': aiModel,
      });
      aiKey.clear();
      ref.invalidate(adminInboxMailboxesProvider);
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
          if (!seeded) { seeded = true; sharedSig.text = s.sharedSignature; sharedAwayText.text = s.sharedAwayText; }
          final away = sharedAway ?? s.sharedAway;
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
            const Divider(height: 24),
            Text('الصندوق المشترك ${s.shared}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(key: const Key('inbox-shared-signature'), controller: sharedSig, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'توقيع الصندوق المشترك', hintText: 'فريق ناس لايف\nnaslife.app', helperText: 'يُضاف في نهاية كل رسالة تُرسل من الصندوق المشترك')),
            SwitchListTile(key: const Key('inbox-shared-away'), contentPadding: EdgeInsets.zero, value: away, onChanged: (v) => setState(() => sharedAway = v), title: const Text('رد تلقائي على الوارد للصندوق المشترك', style: TextStyle(fontSize: 13.5)), subtitle: const Text('مرة واحدة لكل مُرسِل كل 24 ساعة، ولا يُرسل للرسائل الآلية', style: TextStyle(fontSize: 11.5))),
            if (away) TextField(key: const Key('inbox-shared-away-text'), controller: sharedAwayText, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'نص الرد التلقائي', hintText: 'وصلتنا رسالتك وسنرد خلال يوم عمل.')),
            const Divider(height: 24),
            const Text('جودة الخدمة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            SwitchListTile(key: const Key('inbox-csat'), contentPadding: EdgeInsets.zero, value: csat ?? s.csat, onChanged: (v) => setState(() => csat = v), title: const Text('طلب تقييم من العميل عند إغلاق المحادثة', style: TextStyle(fontSize: 13.5)), subtitle: const Text('رسالة واحدة بنجوم من 1 إلى 5 وتعليق اختياري؛ تظهر النتائج في المؤشرات', style: TextStyle(fontSize: 11.5))),
            const Divider(height: 24),
            const Text('المساعد الذكي (Claude)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('يلخّص المحادثة ويقترح مسودة رد داخل المحادثة. يحتاج مفتاح API من console.anthropic.com؛ يُحفظ على الخادم ولا يُعرض مجدداً.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
            TextField(key: const Key('inbox-ai-key'), controller: aiKey, obscureText: true, textDirection: TextDirection.ltr, autocorrect: false, decoration: InputDecoration(labelText: 'مفتاح Anthropic (sk-ant-…)', helperText: s.hasAiKey ? 'محفوظ؛ اتركه فارغاً للإبقاء عليه' : 'غير مضبوط بعد', suffixIcon: s.hasAiKey ? IconButton(key: const Key('inbox-ai-clear'), tooltip: 'إزالة المفتاح', onPressed: busy ? null : () async { try { await ref.read(apiClientProvider).adminInboxSettingsSave({'aiKey': ''}); ref.invalidate(adminInboxSettingsProvider); ref.invalidate(adminInboxMailboxesProvider); if (context.mounted) toast(context, 'أُزيل المفتاح'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); } }, icon: const Icon(Icons.delete_outline_rounded)) : null)),
            DropdownButtonFormField<String>(key: const Key('inbox-ai-model'), initialValue: s.aiModels.contains(aiModel ?? s.aiModel) ? (aiModel ?? s.aiModel) : s.aiModels.first, decoration: const InputDecoration(labelText: 'النموذج'), items: [for (final m in s.aiModels) DropdownMenuItem(value: m, child: Text(m, textDirection: TextDirection.ltr))], onChanged: (v) => setState(() => aiModel = v)),
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


/// إعداداتي في البريد: توقيعي الذي يُلحق بكل رد، ورد الغياب لصندوقي.
class InboxMeSheet extends ConsumerStatefulWidget {
  const InboxMeSheet({super.key});
  @override
  ConsumerState<InboxMeSheet> createState() => _InboxMeSheetState();
}

class _InboxMeSheetState extends ConsumerState<InboxMeSheet> {
  final signature = TextEditingController(), awayText = TextEditingController();
  bool? away;
  DateTime? until;
  bool busy = false, seeded = false, untilTouched = false;

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: until ?? now.add(const Duration(days: 1)), helpText: 'حتى تاريخ');
    if (d == null || !mounted) return;
    setState(() { until = DateTime(d.year, d.month, d.day, 9); untilTouched = true; });
  }

  Future<void> _save(InboxMe m) async {
    setState(() => busy = true);
    try {
      final saved = await ref.read(apiClientProvider).adminInboxMeSave({
        'signature': signature.text.trim(),
        'away': away ?? m.away,
        'awayText': awayText.text.trim(),
        if (untilTouched) 'awayUntil': until?.toUtc().toIso8601String(),
      });
      ref.invalidate(adminInboxMeProvider);
      if (mounted) { toast(context, saved.away ? 'حُفظ التوقيع وفُعّل رد الغياب' : 'حُفظ التوقيع'); Navigator.pop(context); }
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(adminInboxMeProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: me.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxMeProvider)),
        data: (m) {
          if (!seeded) { seeded = true; signature.text = m.signature; awayText.text = m.awayText; until = m.awayUntil; }
          final on = away ?? m.away;
          return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('توقيعي ورد الغياب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            Text(m.address.isNotEmpty ? 'ينطبق على ردودك من أي صندوق، ورد الغياب على الوارد إلى ${m.address}.' : 'ينطبق التوقيع على ردودك. رد الغياب يحتاج صندوقاً باسمك.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
            const SizedBox(height: 10),
            TextField(key: const Key('me-signature'), controller: signature, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'التوقيع', hintText: 'سارة\nفريق دعم ناس لايف', helperText: 'يُضاف تلقائياً في نهاية كل رد ورسالة جديدة')),
            const SizedBox(height: 6),
            SwitchListTile(key: const Key('me-away'), contentPadding: EdgeInsets.zero, value: on, onChanged: m.mailbox.isEmpty ? null : (v) => setState(() => away = v), title: const Text('رد تلقائي أثناء غيابي', style: TextStyle(fontSize: 13.5)), subtitle: const Text('يُرسل مرة واحدة لكل مُرسِل كل 24 ساعة', style: TextStyle(fontSize: 11.5))),
            if (on) ...[
              TextField(key: const Key('me-away-text'), controller: awayText, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'نص رد الغياب', hintText: 'شكراً لرسالتك؛ أنا في إجازة حتى الأحد وسأرد بعدها.')),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: OutlinedButton.icon(key: const Key('me-away-until'), onPressed: _pickUntil, icon: const Icon(Icons.event_rounded, size: 18), label: Text(until == null ? 'حتى إشعار آخر (اختر تاريخاً لينتهي تلقائياً)' : 'ينتهي ${timeAgo(until)}'))),
                if (until != null) IconButton(tooltip: 'بلا نهاية', onPressed: () => setState(() { until = null; untilTouched = true; }), icon: const Icon(Icons.close_rounded)),
              ]),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(key: const Key('me-save'), onPressed: busy ? null : () => _save(m), icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
          ]));
        },
      ),
    );
  }
}

/// القواعد التلقائية: عند وصول رسالة تطابق الشروط تُوسم أو تُسند أو تُميّز أو تُغلق أو تُؤرشف.
class InboxRulesSheet extends ConsumerStatefulWidget {
  const InboxRulesSheet({super.key});
  @override
  ConsumerState<InboxRulesSheet> createState() => _InboxRulesSheetState();
}

class _InboxRulesSheetState extends ConsumerState<InboxRulesSheet> {
  Future<void> _edit(InboxRules info, InboxRule? r) async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _RuleEditor(info: info, rule: r));
    if (body == null || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      if (r == null) { await api.adminInboxRuleCreate(body); } else { await api.adminInboxRuleUpdate(r.id, body); }
      ref.invalidate(adminInboxRulesProvider);
      if (mounted) toast(context, 'حُفظت القاعدة');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _toggle(InboxRule r, bool v) async {
    try { await ref.read(apiClientProvider).adminInboxRuleUpdate(r.id, {'enabled': v}); ref.invalidate(adminInboxRulesProvider); } catch (e) { if (mounted) toast(context, adminErrText(e), error: true); }
  }

  Future<void> _delete(InboxRule r) async {
    try { await ref.read(apiClientProvider).adminInboxRuleDelete(r.id); ref.invalidate(adminInboxRulesProvider); if (mounted) toast(context, 'حُذفت القاعدة'); } catch (e) { if (mounted) toast(context, adminErrText(e), error: true); }
  }

  Future<void> _test() async {
    final from = TextEditingController(), subject = TextEditingController();
    List<InboxRule>? result;
    await showDialog<void>(context: context, builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
      title: const Text('جرّب القواعد على رسالة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(key: const Key('rule-test-from'), controller: from, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'من', hintText: 'name@example.com')),
        TextField(key: const Key('rule-test-subject'), controller: subject, decoration: const InputDecoration(labelText: 'الموضوع')),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: AlignmentDirectional.centerStart, child: Text(result!.isEmpty ? 'لا قاعدة تنطبق' : 'تنطبق: ${result!.map((r) => r.name).join('، ')}', key: const Key('rule-test-result'), style: TextStyle(fontWeight: FontWeight.w700, color: result!.isEmpty ? Joy.textMuted : Joy.success)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق')),
        FilledButton(key: const Key('rule-test-run'), onPressed: () async { try { final r = await ref.read(apiClientProvider).adminInboxRuleTest(from: from.text.trim(), subject: subject.text.trim()); setD(() => result = r); } catch (e) { if (d.mounted) toast(d, adminErrText(e), error: true); } }, child: const Text('جرّب')),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(adminInboxRulesProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: rules.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxRulesProvider)),
        data: (info) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('القواعد التلقائية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            TextButton(key: const Key('rule-test'), onPressed: info.rules.isEmpty ? null : _test, child: const Text('جرّب')),
            TextButton.icon(key: const Key('rule-new'), onPressed: () => _edit(info, null), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('قاعدة')),
          ]),
          const Text('تُطبَّق بالترتيب على كل رسالة واردة. مثال: الموضوع يحتوي «شكوى» → وسم #شكوى وإسناد إلى فريق الدعم.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 8),
          Flexible(child: info.rules.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('لا قواعد بعد.', style: TextStyle(color: Joy.textMuted)))
              : ListView(shrinkWrap: true, children: [
                  for (final r in info.rules)
                    ListTile(
                      key: Key('rule-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Switch(key: Key('rule-toggle-${r.id}'), value: r.enabled, onChanged: (v) => _toggle(r, v)),
                      title: Text(r.name, style: TextStyle(color: r.enabled ? null : Joy.textMuted)),
                      subtitle: Text('${_condText(r.conditions)} ← ${_actText(r.actions, info)} · طُبّقت ${r.hits} مرة', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(key: Key('rule-delete-${r.id}'), tooltip: 'حذف', onPressed: () => _delete(r), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger)),
                      onTap: () => _edit(info, r),
                    ),
                ])),
        ]),
      ),
    );
  }

  static String _condText(Map<String, dynamic> c) {
    final parts = <String>[];
    if (c['mailbox'] != null) parts.add('الصندوق ${c['mailbox']}');
    if (c['fromContains'] != null) parts.add('المرسل يحتوي «${c['fromContains']}»');
    if (c['subjectContains'] != null) parts.add('الموضوع يحتوي «${c['subjectContains']}»');
    if (c['textContains'] != null) parts.add('النص يحتوي «${c['textContains']}»');
    return parts.join(' و');
  }

  static String _actText(Map<String, dynamic> a, InboxRules info) {
    final parts = <String>[];
    final tags = (a['tags'] as List? ?? const []).map((e) => '#$e').join(' ');
    if (tags.isNotEmpty) parts.add('وسم $tags');
    if (a['assignTo'] != null) parts.add('إسناد إلى ${info.assignees.where((x) => x.id == a['assignTo']).map((x) => x.name).firstOrNull ?? a['assignTo']}');
    if (a['star'] == true) parts.add('تمييز');
    if (a['status'] != null) parts.add('الحالة ${threadStatusName(a['status'].toString())}');
    if (a['archive'] == true) parts.add('أرشفة');
    return parts.join('، ');
  }
}

class _RuleEditor extends StatefulWidget {
  final InboxRules info;
  final InboxRule? rule;
  const _RuleEditor({required this.info, this.rule});
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final name = TextEditingController(text: widget.rule?.name ?? '');
  late final from = TextEditingController(text: widget.rule?.conditions['fromContains']?.toString() ?? '');
  late final subject = TextEditingController(text: widget.rule?.conditions['subjectContains']?.toString() ?? '');
  late final text = TextEditingController(text: widget.rule?.conditions['textContains']?.toString() ?? '');
  late final tags = TextEditingController(text: widget.rule?.tags.join('، ') ?? '');
  late String? mailbox = widget.rule?.conditions['mailbox']?.toString();
  late String? assignTo = widget.rule?.actions['assignTo']?.toString();
  late String? status = widget.rule?.actions['status']?.toString();
  late bool star = widget.rule?.actions['star'] == true, archive = widget.rule?.actions['archive'] == true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.rule == null ? 'قاعدة جديدة' : 'تعديل القاعدة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 10),
        TextField(key: const Key('rule-name'), controller: name, decoration: const InputDecoration(labelText: 'اسم القاعدة', hintText: 'الشكاوى')),
        const SizedBox(height: 10),
        const Text('عندما تصل رسالة…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        DropdownButtonFormField<String?>(key: const Key('rule-mailbox'), initialValue: widget.info.mailboxes.contains(mailbox) ? mailbox : null, decoration: const InputDecoration(labelText: 'إلى الصندوق'), items: [const DropdownMenuItem<String?>(value: null, child: Text('أي صندوق')), for (final m in widget.info.mailboxes) DropdownMenuItem<String?>(value: m, child: Text(m))], onChanged: (v) => setState(() => mailbox = v)),
        TextField(key: const Key('rule-from'), controller: from, decoration: const InputDecoration(labelText: 'والمرسل يحتوي', hintText: 'مثال: @bank.com أو اسم')),
        TextField(key: const Key('rule-subject'), controller: subject, decoration: const InputDecoration(labelText: 'والموضوع يحتوي', hintText: 'شكوى')),
        TextField(key: const Key('rule-text'), controller: text, decoration: const InputDecoration(labelText: 'والنص يحتوي')),
        const SizedBox(height: 10),
        const Text('افعل…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        TextField(key: const Key('rule-tags'), controller: tags, decoration: const InputDecoration(labelText: 'أضف وسوماً (بفاصلة)', hintText: 'شكوى، عاجل')),
        DropdownButtonFormField<String?>(key: const Key('rule-assign'), initialValue: widget.info.assignees.any((a) => a.id == assignTo) ? assignTo : null, decoration: const InputDecoration(labelText: 'أسند إلى'), items: [const DropdownMenuItem<String?>(value: null, child: Text('لا تُسند')), for (final a in widget.info.assignees) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))], onChanged: (v) => setState(() => assignTo = v)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          ChoiceChip(key: const Key('rule-status-none'), label: const Text('اترك الحالة'), selected: status == null, onSelected: (_) => setState(() => status = null)),
          for (final s in threadStatuses) ChoiceChip(key: Key('rule-status-${s.$1}'), label: Text(s.$2), selected: status == s.$1, onSelected: (_) => setState(() => status = s.$1)),
        ]),
        SwitchListTile(key: const Key('rule-star'), contentPadding: EdgeInsets.zero, value: star, onChanged: (v) => setState(() => star = v), title: const Text('ميّز المحادثة', style: TextStyle(fontSize: 13.5))),
        SwitchListTile(key: const Key('rule-archive'), contentPadding: EdgeInsets.zero, value: archive, onChanged: (v) => setState(() => archive = v), title: const Text('أرشف مباشرة (بلا إشعار)', style: TextStyle(fontSize: 13.5))),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('rule-save'),
          onPressed: () {
            if (name.text.trim().isEmpty) { toast(context, 'اكتب اسماً للقاعدة', error: true); return; }
            Navigator.pop(context, {
              'name': name.text.trim(),
              'conditions': {if (mailbox != null) 'mailbox': mailbox, if (from.text.trim().isNotEmpty) 'fromContains': from.text.trim(), if (subject.text.trim().isNotEmpty) 'subjectContains': subject.text.trim(), if (text.text.trim().isNotEmpty) 'textContains': text.text.trim()},
              'actions': {
                if (tags.text.trim().isNotEmpty) 'tags': tags.text.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                if (assignTo != null) 'assignTo': assignTo, if (star) 'star': true, if (archive) 'archive': true, if (status != null) 'status': status,
              },
            });
          },
          icon: const Icon(Icons.save_outlined), label: const Text('حفظ القاعدة'),
        ),
      ])),
    );
  }
}


/// اختيار وقت الإرسال المجدول: خيارات سريعة أو تاريخ ووقت.
Future<DateTime?> pickSendTime(BuildContext context) async {
  final now = DateTime.now();
  final choice = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 4), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('إرسال لاحقاً', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
    ListTile(key: const Key('schedule-hour'), leading: const Icon(Icons.hourglass_top_rounded), title: const Text('بعد ساعة'), onTap: () => Navigator.pop(ctx, 'hour')),
    ListTile(key: const Key('schedule-tomorrow'), leading: const Icon(Icons.wb_sunny_outlined), title: const Text('غداً صباحاً (9:00)'), onTap: () => Navigator.pop(ctx, 'tomorrow')),
    ListTile(key: const Key('schedule-pick'), leading: const Icon(Icons.event_rounded), title: const Text('اختر التاريخ والوقت'), onTap: () => Navigator.pop(ctx, 'pick')),
    const SizedBox(height: 8),
  ])));
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case 'hour': return now.add(const Duration(hours: 1));
    case 'tomorrow': return DateTime(now.year, now.month, now.day + 1, 9);
  }
  final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)), initialDate: now, helpText: 'تاريخ الإرسال');
  if (d == null || !context.mounted) return null;
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0));
  if (tm == null) return null;
  final when = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  if (when.isBefore(now.add(const Duration(minutes: 1)))) { if (context.mounted) toast(context, 'اختر وقتاً لاحقاً', error: true); return null; }
  return when;
}

/// نتائج البحث الشامل في نصوص الرسائل عبر كل الصناديق المرئية.
class SearchResultsSheet extends ConsumerStatefulWidget {
  final String q;
  final InboxInfo info;
  const SearchResultsSheet({super.key, required this.q, required this.info});
  @override
  ConsumerState<SearchResultsSheet> createState() => _SearchResultsSheetState();
}

class _SearchResultsSheetState extends ConsumerState<SearchResultsSheet> {
  late Future<List<InboxSearchHit>> hits = ref.read(apiClientProvider).adminInboxSearch(widget.q);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('نتائج «${widget.q}» في نصوص الرسائل', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          Flexible(child: FutureBuilder<List<InboxSearchHit>>(
            future: hits,
            builder: (context, snap) {
              if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => hits = ref.read(apiClientProvider).adminInboxSearch(widget.q)));
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final items = snap.data!;
              if (items.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا نتائج.', style: TextStyle(color: Joy.textMuted)));
              return ListView(shrinkWrap: true, children: [
                for (final h in items)
                  ListTile(
                    key: Key('search-hit-${h.thread.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(h.direction == 'in' ? Icons.mail_outline_rounded : Icons.reply_rounded, color: Joy.textMuted),
                    title: Text('${h.thread.who} · ${h.thread.subject}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    subtitle: Text('${h.excerpt}\n${h.thread.mailbox}@${widget.info.domain} · ${timeAgo(h.at)}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => InboxThreadSheet(threadId: h.thread.id, info: widget.info)),
                  ),
              ]);
            },
          )),
        ]),
      );
}

/// الرسائل المجدولة: ما ينتظر الإرسال، وما أُرسل أو فشل مؤخراً.
class OutboxSheet extends ConsumerWidget {
  const OutboxSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminInboxOutboxProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('الرسائل المجدولة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        Flexible(child: list.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxOutboxProvider)),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('لا رسائل مجدولة. من أي رد اختر «إرسال لاحقاً».', style: TextStyle(color: Joy.textMuted)))
              : ListView(shrinkWrap: true, children: [
                  for (final o in items)
                    ListTile(
                      key: Key('outbox-${o.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (o.status) { 'sent' => Icons.check_circle_outline, 'failed' => Icons.error_outline, 'cancelled' => Icons.cancel_outlined, _ => Icons.schedule_send_outlined }, color: switch (o.status) { 'sent' => Joy.success, 'failed' => Joy.danger, _ => Joy.textMuted }),
                      title: Text('${o.subject} · إلى ${o.to}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(switch (o.status) { 'queued' => 'ستُرسل ${dueText(o.sendAt)} من ${o.mailbox}', 'sent' => 'أُرسلت ${timeAgo(o.sentAt)}', 'failed' => 'فشلت: ${o.error ?? ''}', _ => 'أُلغيت' }, style: const TextStyle(fontSize: 12)),
                      trailing: o.status == 'queued' ? IconButton(key: Key('outbox-cancel-${o.id}'), tooltip: 'إلغاء', onPressed: () async { try { await ref.read(apiClientProvider).adminInboxOutboxCancel(o.id); ref.invalidate(adminInboxOutboxProvider); if (context.mounted) toast(context, 'أُلغيت'); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); } }, icon: const Icon(Icons.close_rounded, color: Joy.danger)) : null,
                    ),
                ]),
        )),
      ]),
    );
  }
}

/// المرسلون المحظورون: بريد كامل أو @نطاق؛ الوارد منهم يذهب للمزعج بصمت.
class BlockedSheet extends ConsumerStatefulWidget {
  const BlockedSheet({super.key});
  @override
  ConsumerState<BlockedSheet> createState() => _BlockedSheetState();
}

class _BlockedSheetState extends ConsumerState<BlockedSheet> {
  final pattern = TextEditingController(), reason = TextEditingController();
  Future<void> _add() async {
    try { await ref.read(apiClientProvider).adminInboxBlock(pattern.text, reason: reason.text.trim()); pattern.clear(); reason.clear(); ref.invalidate(adminInboxBlockedProvider); if (mounted) toast(context, 'أُضيف إلى المحظورين'); } catch (e) { if (mounted) toast(context, adminErrText(e), error: true); }
  }
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminInboxBlockedProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('المرسلون المحظورون', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const Text('بريد كامل (someone@x.com) أو نطاق كامل (@x.com). الوارد منهم يُحفظ في مجلد المزعج بلا إشعار.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 3, child: TextField(key: const Key('blocked-add-pattern'), controller: pattern, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(isDense: true, labelText: 'بريد أو @نطاق'))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: TextField(key: const Key('blocked-add-reason'), controller: reason, decoration: const InputDecoration(isDense: true, labelText: 'السبب'))),
          IconButton.filled(key: const Key('blocked-add'), onPressed: _add, icon: const Icon(Icons.add_rounded)),
        ]),
        const SizedBox(height: 8),
        Flexible(child: list.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxBlockedProvider)),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('لا محظورين.', style: TextStyle(color: Joy.textMuted)))
              : ListView(shrinkWrap: true, children: [
                  for (final b in items)
                    ListTile(
                      key: Key('blocked-${b.pattern}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_outlined, color: Joy.danger),
                      title: Text(b.pattern, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      subtitle: Text('${b.reason.isNotEmpty ? '${b.reason} · ' : ''}صُدّ ${b.hits} مرة${b.createdByName.isNotEmpty ? ' · بواسطة ${b.createdByName}' : ''}', style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(key: Key('blocked-delete-${b.pattern}'), tooltip: 'إلغاء الحظر', onPressed: () async { try { await ref.read(apiClientProvider).adminInboxUnblock(b.pattern); ref.invalidate(adminInboxBlockedProvider); } catch (e) { if (context.mounted) toast(context, adminErrText(e), error: true); } }, icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger)),
                    ),
                ]),
        )),
      ]),
    );
  }
}

/// المؤشرات: الحجم، زمن أول رد، الإغلاق، التقييم، ولكل موظف وصندوق ويوم.
class InboxStatsSheet extends ConsumerStatefulWidget {
  const InboxStatsSheet({super.key});
  @override
  ConsumerState<InboxStatsSheet> createState() => _InboxStatsSheetState();
}

class _InboxStatsSheetState extends ConsumerState<InboxStatsSheet> {
  int days = 30;
  static String _mins(int m) => m <= 0 ? '—' : m < 60 ? '$m د' : m < 1440 ? '${(m / 60).toStringAsFixed(1)} س' : '${(m / 1440).toStringAsFixed(1)} ي';
  @override
  Widget build(BuildContext context) {
    final st = ref.watch(adminInboxStatsProvider(days));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('مؤشرات البريد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          for (final n in const [7, 30, 90]) Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: ChoiceChip(key: Key('stats-days-$n'), label: Text('$n يوم'), selected: days == n, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => days = n))),
        ]),
        const SizedBox(height: 8),
        Flexible(child: st.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminInboxStatsProvider(days))),
          data: (x) {
            final maxDay = x.daily.fold<int>(1, (m, d) => [m, (d['received'] as num? ?? 0).toInt(), (d['sent'] as num? ?? 0).toInt()].reduce((a, b) => a > b ? a : b));
            return ListView(shrinkWrap: true, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _StatBox(keyName: 'stats-received', label: 'وارد', value: '${x.n('received')}', sub: '${x.n('threads')} محادثة'),
                _StatBox(keyName: 'stats-sent', label: 'ردود الفريق', value: '${x.n('sent')}', sub: '${x.n('openUnanswered')} بلا رد الآن'),
                _StatBox(keyName: 'stats-first', label: 'أول رد', value: _mins(x.n('firstResponseMin')), sub: 'الوسيط ${_mins(x.n('firstResponseMedianMin'))}'),
                _StatBox(keyName: 'stats-closed', label: 'أُغلقت', value: '${x.n('closed')}', sub: x.d('resolutionHours') != null ? 'الحل خلال ${x.d('resolutionHours')!.toStringAsFixed(1)} س' : ''),
                _StatBox(keyName: 'stats-csat', label: 'رضا العملاء', value: x.d('csat') != null ? '${x.d('csat')!.toStringAsFixed(2)} / 5' : '—', sub: '${x.n('ratings')} تقييم من ${x.n('ratingsSent')} طلب'),
                _StatBox(keyName: 'stats-spam', label: 'مزعج', value: '${x.n('spam')}', sub: 'محادثة صُدّت'),
              ]),
              if (x.daily.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('يومياً · وارد وردود', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                SizedBox(height: 70, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final d in x.daily.length > 31 ? x.daily.sublist(x.daily.length - 31) : x.daily)
                    Expanded(child: Tooltip(message: '${d['day']}: وارد ${d['received']} · ردود ${d['sent']}', child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(height: 60 * ((d['received'] as num? ?? 0).toInt() / maxDay), decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 1),
                      Container(height: 60 * ((d['sent'] as num? ?? 0).toInt() / maxDay) * .5, decoration: BoxDecoration(color: Joy.success, borderRadius: BorderRadius.circular(2))),
                    ])))),
                ])),
              ],
              if (x.agents.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('لكل موظف', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                for (final a in x.agents)
                  ListTile(key: Key('stats-agent-${a.id}'), contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.person_outline, color: Joy.textMuted), title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${a.replies} رد · ${a.closed} إغلاق · أول رد ${_mins(a.firstResponseMin)}${a.csat != null ? ' · رضا ${a.csat!.toStringAsFixed(2)} (${a.ratings})' : ''}', style: const TextStyle(fontSize: 12))),
              ],
              if (x.mailboxes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('لكل صندوق', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                for (final m in x.mailboxes) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${m['mailbox']}: وارد ${m['received']} · ردود ${m['sent']}', style: const TextStyle(fontSize: 12.5))),
              ],
            ]);
          },
        )),
      ]),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String keyName, label, value, sub;
  const _StatBox({required this.keyName, required this.label, required this.value, this.sub = ''});
  @override
  Widget build(BuildContext context) => Container(
        key: Key(keyName), width: 150, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Joy.primary)),
          if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
        ]),
      );
}
