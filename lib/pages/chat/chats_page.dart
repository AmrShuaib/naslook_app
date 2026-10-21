import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/jobs_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/safety_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../jobs/job_offers_page.dart';
import 'chat_thread_page.dart';

/// نتيجة بحث في الرسائل كما فسّرناها من رد الخادم.
class ChatSearchHit {
  final String id, content, type;
  final Person peer;
  final DateTime? at;
  final bool mine;
  const ChatSearchHit({required this.id, required this.content, required this.type, required this.peer, this.at, this.mine = false});

  /// يفسّر صفاً من /messages/search بتسامح: الطرف الآخر من peer أو من المرسل/المستلم حسب هويتي.
  static ChatSearchHit? parse(Map<String, dynamic> m, String myId, Map<String, Person> known) {
    final id = (m['id'] ?? m['messageId'] ?? '').toString();
    if (id.isEmpty) return null;
    final sender = (m['senderId'] ?? m['sender_id'] ?? m['from'] ?? m['from_id'] ?? m['user_id'] ?? m['author_id'] ?? '').toString();
    final to = (m['to'] ?? m['toId'] ?? m['recipientId'] ?? m['recipient_id'] ?? m['receiverId'] ?? '').toString();
    Person? peer;
    if (m['peer'] is Map) peer = Person.fromJson(asMap(m['peer']));
    final peerId = peer?.id ?? (m['peerId'] ?? m['peer_id'] ?? (sender == myId ? to : sender)).toString();
    peer ??= known[peerId] ?? Person(id: peerId, nickname: (m['peerNickname'] ?? m['nickname'] ?? m['senderNickname'] ?? peerId).toString());
    return ChatSearchHit(
      id: id, content: (m['content'] ?? m['text'] ?? '').toString(), type: (m['type'] ?? 'text').toString(), peer: peer,
      at: DateTime.tryParse((m['sentAt'] ?? m['sent_at'] ?? m['createdAt'] ?? m['created_at'] ?? '').toString())?.toLocal(), mine: sender == myId,
    );
  }
}

/// معاينة آخر رسالة في صف القائمة: أيقونة ونص قصير بحسب النوع (وسائط، رمز اختصار، نص)، بدل الإيموجي داخل النص.
({IconData? icon, String text}) chatPreview(String? type, String? content) {
  if (content == null || content.isEmpty) return (icon: null, text: 'ابدأ المحادثة');
  switch (Message.kindOf(type ?? 'text', content)) {
    case 'image':
      return (icon: Icons.photo_camera_rounded, text: 'صورة');
    case 'video':
      return (icon: Icons.videocam_rounded, text: 'فيديو');
    case 'audio':
      return (icon: Icons.mic_rounded, text: 'رسالة صوتية');
    case 'file':
      return (icon: Icons.attach_file_rounded, text: 'ملف');
  }
  // أمر اختصار (/pay، /meet…) يُعرض باسمه لا بنصه الخام
  final cmd = parseCommand(content);
  if (cmd != null) {
    return switch (cmd.kind) {
      CodeKind.pay => (icon: Icons.payments_rounded, text: 'طلب مبلغ'),
      CodeKind.send => (icon: Icons.send_rounded, text: 'تحويل مبلغ'),
      CodeKind.split => (icon: Icons.call_split_rounded, text: 'تقسيم حساب'),
      CodeKind.meet => (icon: Icons.event_rounded, text: 'موعد'),
      CodeKind.invite => (icon: Icons.group_add_rounded, text: 'دعوة'),
      CodeKind.where || CodeKind.loc => (icon: Icons.place_rounded, text: 'موقع'),
      CodeKind.me => (icon: Icons.person_pin_circle_rounded, text: 'بطاقتي'),
      _ => (icon: Icons.bolt_rounded, text: content.replaceAll(RegExp(r'\s+'), ' ').trim()),
    };
  }
  return (icon: null, text: content.replaceAll(RegExp(r'\s+'), ' ').trim());
}

class ChatsPage extends ConsumerStatefulWidget {
  const ChatsPage({super.key});
  @override
  ConsumerState<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends ConsumerState<ChatsPage> {
  StreamSubscription? _sub;
  final _search = TextEditingController();
  Timer? _debounce;
  int _tab = 0;
  String _q = '';
  List<ChatSearchHit> _hits = const [];
  bool _searchingServer = false;
  /// حضور وصل من القناة الحية (حدث presence) ويغلب ما جاء مع قائمة المحادثات.
  final _live = <String, bool>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      _sub = ref.read(socketProvider)?.events.listen((e) {
        final ev = e['event'];
        final isMessage = (ev == null && e['senderId'] != null && e['content'] != null) || ev == 'message' || ev == 'new-message';
        if (isMessage || ev == 'read' || ev == 'delivered' || ev == '_connected') {
          ref.invalidate(chatsProvider);
          if (isMessage && e['isRequest'] == true) ref.invalidate(requestsProvider);
        } else if (ev == 'presence') {
          final id = (e['peerId'] ?? e['userId'] ?? e['from'] ?? e['id'])?.toString().toUpperCase();
          if (id != null && id.isNotEmpty && mounted) setState(() => _live[id] = e['online'] == true);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    setState(() => _q = v.trim());
    _debounce?.cancel();
    if (_q.length < 2) { setState(() { _hits = const []; _searchingServer = false; }); return; }
    _debounce = Timer(const Duration(milliseconds: 400), _serverSearch);
  }

  Future<void> _serverSearch() async {
    final q = _q;
    setState(() => _searchingServer = true);
    try {
      final rows = await ref.read(apiClientProvider).searchMessages(q);
      if (!mounted || q != _q) return;
      final myId = ref.read(appStateProvider).user?.id ?? '';
      final known = {for (final c in ref.read(chatsProvider).value ?? const <Chat>[]) c.peer.id: c.peer};
      final hits = rows.map((r) => ChatSearchHit.parse(r, myId, known)).whereType<ChatSearchHit>().toList();
      setState(() { _hits = hits; _searchingServer = false; });
    } catch (_) {
      // الخادم لا يدعم البحث أو رفضه: نكتفي بالبحث المحلي
      if (mounted) setState(() { _hits = const []; _searchingServer = false; });
    }
  }

  /// السحب للتحديث ينتظر وصول القائمة فعلاً حتى يبقى المؤشر ظاهراً ريثما تصل.
  Future<void> _refresh() async {
    ref.invalidate(chatsProvider);
    ref.invalidate(requestsProvider);
    ref.invalidate(jobsInboxProvider);
    try {
      await ref.read(chatsProvider.future);
    } catch (_) {
      // الخطأ يظهر في القائمة نفسها
    }
  }

  /// قائمة الصف بالضغط المطوّل: تعليم كمقروءة، كتم/إلغاء كتم (server/safety.js)، والملف الشخصي.
  Future<void> _rowMenu(Chat c, {required bool muted}) async {
    final api = ref.read(apiClientProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: ProfileAvatar(person: c.peer, size: 40),
            title: Text(c.peer.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.peer.id, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ),
          const Divider(height: 1),
          if (c.unread > 0)
            ListTile(key: const Key('chat-menu-read'), leading: const Icon(Icons.mark_chat_read_rounded, color: Joy.primary), title: const Text('تعليم كمقروءة'), onTap: () => Navigator.pop(ctx, 'read')),
          ListTile(
            key: Key(muted ? 'chat-menu-unmute' : 'chat-menu-mute'),
            leading: Icon(muted ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: Joy.primary),
            title: Text(muted ? 'إلغاء كتم الإشعارات' : 'كتم الإشعارات'),
            subtitle: muted ? null : const Text('لا تنبيه ولا شارة لهذه المحادثة', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, muted ? 'unmute' : 'mute'),
          ),
          ListTile(key: const Key('chat-menu-profile'), leading: const Icon(Icons.person_outline_rounded, color: Joy.primary), title: const Text('الملف الشخصي'), onTap: () => Navigator.pop(ctx, 'profile')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'read':
          await api.markRead(c.peer.id);
          ref.invalidate(chatsProvider);
        case 'mute':
          await api.mute(c.peer.id);
          ref.invalidate(mutesProvider);
          if (mounted) toast(context, 'كُتمت محادثة ${c.peer.nickname}');
        case 'unmute':
          await api.unmute(c.peer.id);
          ref.invalidate(mutesProvider);
          if (mounted) toast(context, 'أُلغي كتم محادثة ${c.peer.nickname}');
        case 'profile':
          if (mounted) openProfile(context, c.peer);
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final requests = ref.watch(requestsProvider);
    // عروض التوظيف بانتظار الرد تُعدّ طلبات أيضاً (المؤجّلة لا تُحسب ولا تُعرض هنا)
    final jobOffers = (ref.watch(jobsInboxProvider).valueOrNull?.items ?? const <JobMatch>[]).where((m) => m.pending).toList();
    final reqCount = (requests.value?.length ?? 0) + jobOffers.length;
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        child: const Icon(Icons.chat_rounded),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onQuery,
            decoration: InputDecoration(
              hintText: 'ابحث في المحادثات والرسائل',
              prefixIcon: const Icon(Icons.search_rounded, color: Joy.textMuted),
              suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _search.clear(); _onQuery(''); }),
            ),
          ),
        ),
        // الشرائح تتمرّر أفقياً حتى لا تضيق بها الشاشات الصغيرة
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            for (final (i, l) in ['المحادثات', reqCount > 0 ? 'الطلبات · $reqCount' : 'الطلبات'].indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(l, style: TextStyle(color: _tab == i ? Joy.primaryOn : Joy.text)), selected: _tab == i, onSelected: (_) => setState(() => _tab = i), showCheckmark: false, selectedColor: Joy.primary),
              ),
            // عروض التوظيف بانتظار الرد تظهر كشريحة مستقلة تفتح الطلبات (حيث تُعرض أولاً)
            if (jobOffers.isNotEmpty)
              ChoiceChip(key: const Key('chat-chip-jobs'), avatar: Icon(Icons.work_outline_rounded, size: 16, color: _tab == 1 ? Joy.primaryOn : Joy.primary), label: Text('التوظيف · ${jobOffers.length}', style: TextStyle(color: _tab == 1 ? Joy.primaryOn : Joy.text)), selected: false, onSelected: (_) => setState(() => _tab = 1), showCheckmark: false),
          ]),
        ),
        Expanded(child: _tab == 0 ? _chatsTab(chats, requests.valueOrNull ?? const [], jobOffers) : _requestsTab(requests, jobOffers)),
      ]),
    );
  }

  Widget _chatsTab(AsyncValue<List<Chat>> chats, List<FriendRequest> pending, List<JobMatch> jobOffers) => chats.when(
        data: (all) {
          final muted = ref.watch(mutedPeersProvider);
          final q = _q.toLowerCase();
          final list = q.isEmpty ? all : all.where((c) => c.peer.nickname.toLowerCase().contains(q) || c.peer.id.toLowerCase().contains(q) || (c.lastContent?.toLowerCase().contains(q) ?? false)).toList();
          if (all.isEmpty && pending.isEmpty && jobOffers.isEmpty) {
            return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'لا محادثات بعد', subtitle: 'أضف صديقاً بنك نيمه وابدأ الحديث.', action: OutlinedButton(onPressed: _newChat, child: const Text('محادثة جديدة')));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              // قابلة للسحب دائماً حتى يعمل السحب للتحديث ولو كانت المحادثات قليلة
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // أول عرض وظيفي بانتظار الرد مثبّت فوق المحادثات
                if (q.isEmpty && jobOffers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Material(
                      color: Joy.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        key: const Key('chat-job-pinned'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _tab = 1),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.work_outline_rounded, color: Joy.primary)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('عرض وظيفي: ${jobOffers.first.job?.title ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Joy.bubbleOutText)),
                              Text(jobOffers.length > 1 ? '${jobOffers.length} عروض بانتظار ردك' : 'بانتظار ردك · افتح لتقبل أو تعتذر', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.text, fontSize: 12)),
                            ])),
                            const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
                          ]),
                        ),
                      ),
                    ),
                  ),
                // ملخص طلبات المراسلة من غير الأصدقاء
                if (q.isEmpty && pending.isNotEmpty)
                  ListRow(
                    key: const Key('chat-requests-row'),
                    divider: list.isNotEmpty,
                    onTap: () => setState(() => _tab = 1),
                    leading: SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(children: [
                        for (final (i, r) in pending.take(3).toList().indexed)
                          PositionedDirectional(start: i * 12.0, top: 8, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Joy.surface, width: 2)), child: ProfileAvatar(person: r.from, size: 34))),
                      ]),
                    ),
                    title: Text(pending.length == 1 ? 'طلب مراسلة واحد' : '${pending.length} طلبات مراسلة'),
                    subtitle: const Text('من غير الأصدقاء · اقبل أو تجاهل', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Joy.textMuted)),
                    trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
                  ),
                if (list.isEmpty && _hits.isEmpty && !_searchingServer) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا نتائج', style: TextStyle(color: Joy.textMuted)))),
                for (final (i, c) in list.indexed)
                  _ChatRow(
                    c,
                    muted: muted.contains(c.peer.id),
                    online: _live[c.peer.id.toUpperCase()] ?? c.peer.online,
                    divider: i < list.length - 1 || _hits.isNotEmpty,
                    onLongPress: () => _rowMenu(c, muted: muted.contains(c.peer.id)),
                  ),
                if (_q.length >= 2) ...[
                  if (_searchingServer) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                  if (_hits.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('رسائل', style: TextStyle(fontWeight: FontWeight.w700, color: Joy.textMuted, fontSize: 13))),
                  for (final (i, h) in _hits.indexed) _HitRow(h, query: _q, divider: i < _hits.length - 1),
                ],
              ],
            ),
          );
        },
        loading: () => const _ChatsSkeleton(),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(chatsProvider)),
      );

  /// قسم «التوظيف» أولاً (بطاقات عروض بأزرار الرد) ثم طلبات المراسلة كما هي.
  Widget _requestsTab(AsyncValue<List<FriendRequest>> requests, List<JobMatch> jobOffers) => requests.when(
        data: (list) => list.isEmpty && jobOffers.isEmpty
            ? const EmptyState(icon: Icons.mark_email_read_outlined, title: 'لا طلبات مراسلة', subtitle: 'رسائل من غير أصدقائك وعروض التوظيف تظهر هنا أولاً حتى تقبلها أو تتجاهلها.')
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(requestsProvider);
                  ref.invalidate(jobsInboxProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (jobOffers.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(children: [
                          const Icon(Icons.work_outline_rounded, size: 18, color: Joy.primary),
                          const SizedBox(width: 6),
                          const Expanded(child: Text('التوظيف', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                          TextButton(key: const Key('jobs-all'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobOffersPage())), child: const Text('الكل', style: TextStyle(fontSize: 13))),
                        ]),
                      ),
                      for (final m in jobOffers) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: JobOfferCard(m, actions: true)),
                      if (list.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 2), child: Text('طلبات المراسلة', style: TextStyle(fontWeight: FontWeight.w700, color: Joy.textMuted, fontSize: 13))),
                    ],
                    for (final (i, r) in list.indexed) _RequestRow(r, divider: i < list.length - 1),
                  ],
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(requestsProvider)),
      );

  Future<void> _newChat() async {
    final handle = await askText(context, title: 'محادثة جديدة', hint: 'النك نيم أو المعرّف', confirm: 'فتح', maxLines: 1);
    if (handle == null || handle.isEmpty) return;
    try {
      final p = await ref.read(apiClientProvider).userByHandle(handle.trim().toLowerCase());
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p)));
    } catch (e) {
      if (mounted) toast(context, 'لم أجد "$handle"', error: true);
    }
  }
}

/// صف محادثة: صورة 48 مع نقطة الحضور، اسم عريض، سطر معاينة (أيقونة الوسائط أو الرمز، و«أنت:» مع علامة الإرسال لرسالتي)،
/// الوقت النسبي، وشارة غير المقروء بلون العلامة (تُخفى للمكتومة وتحلّ محلها أيقونة الكتم). الضغط المطوّل يفتح قائمة الصف.
class _ChatRow extends StatelessWidget {
  final Chat c;
  final bool divider, muted, online;
  final VoidCallback? onLongPress;
  const _ChatRow(this.c, {this.divider = true, this.muted = false, this.online = false, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final unread = c.unread > 0 && !muted;
    final mine = c.lastMine && c.lastContent != null;
    final pv = chatPreview(c.lastType, c.lastContent);
    final id = c.peer.id;
    return InkWell(
      key: Key('chat-row-$id'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: c.peer))),
      onLongPress: onLongPress,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
          child: Row(children: [
            ProfileAvatar(key: Key('chat-avatar-$id'), person: c.peer, size: 48, online: online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.peer.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 15.5, color: Joy.text)),
                const SizedBox(height: 3),
                Row(children: [
                  // علامة الإرسال لرسالتي (قائمة المحادثات لا تحمل حالة القراءة؛ علامة واحدة = أُرسلت)
                  if (mine) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: Icon(Icons.done_rounded, key: Key('chat-tick-$id'), size: 15, color: Joy.textMuted)),
                  if (pv.icon != null) Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Icon(pv.icon, size: 15, color: unread ? Joy.primary : Joy.textMuted)),
                  Expanded(
                    child: Text('${mine ? 'أنت: ' : ''}${pv.text}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: unread ? Joy.text : Joy.textMuted, fontWeight: unread ? FontWeight.w600 : FontWeight.w500)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(timeAgo(c.lastAt), style: TextStyle(fontSize: 11.5, color: unread ? Joy.primary : Joy.textMuted, fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
              const SizedBox(height: 5),
              if (unread)
                Container(
                  key: Key('chat-unread-$id'),
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.center,
                  child: Text(c.unread > 99 ? '99+' : '${c.unread}', style: const TextStyle(color: Joy.primaryOn, fontSize: 11, fontWeight: FontWeight.w700)),
                )
              else if (muted)
                const Icon(Icons.volume_off_rounded, size: 16, color: Joy.textMuted)
              else
                const SizedBox(height: 18),
            ]),
          ]),
        ),
        if (divider) const Padding(padding: EdgeInsetsDirectional.only(start: 76), child: Divider(height: 1)),
      ]),
    );
  }
}

/// هيكل القائمة أثناء الجلب الأول: صفوف رمادية ثابتة بلا حركة (لا تستهلك البطارية ولا تعلّق pumpAndSettle في الاختبارات).
/// لا يظهر عند التحديث لأن المزوّد يبقي القائمة السابقة ريثما تصل الجديدة.
class _ChatsSkeleton extends StatelessWidget {
  const _ChatsSkeleton();
  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(height: h, width: w, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(6)));
    return ListView.builder(
      key: const Key('chats-skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: const BoxDecoration(color: Joy.surface2, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(90.0 + (i % 3) * 30, 13), const SizedBox(height: 8), bar(150.0 + (i % 2) * 40, 11)])),
          const SizedBox(width: 8),
          bar(28, 10),
        ]),
      ),
    );
  }
}

/// نتيجة بحث: تفتح المحادثة وتقفز إلى الرسالة.
class _HitRow extends StatelessWidget {
  final ChatSearchHit h;
  final String query;
  final bool divider;
  const _HitRow(this.h, {required this.query, this.divider = true});
  @override
  Widget build(BuildContext context) => ListRow(
        divider: divider,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: h.peer, initialMessageId: h.id))),
        leading: ProfileAvatar(person: h.peer, size: 44),
        title: Text(h.peer.nickname, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${h.mine ? 'أنت: ' : ''}${Message.previewOf(h.type, h.content)}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(timeAgo(h.at), style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
      );
}

class _RequestRow extends ConsumerWidget {
  final FriendRequest r;
  final bool divider;
  const _RequestRow(this.r, {this.divider = true});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListRow(
        divider: divider,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r.from))),
        leading: ProfileAvatar(person: r.from, size: 48),
        title: Text(r.from.nickname),
        subtitle: Text('${r.lastContent ?? 'يريد مراسلتك'} · ${timeAgo(r.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'تجاهل', onPressed: () => _act(context, ref, accept: false), icon: const Icon(Icons.close_rounded, color: Joy.textMuted)),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: () => _act(context, ref, accept: true), child: const Text('قبول')),
        ]),
      );

  Future<void> _act(BuildContext context, WidgetRef ref, {required bool accept}) async {
    final api = ref.read(apiClientProvider);
    try {
      if (accept) {
        await api.addContact(r.from.id);
      } else {
        await api.ignoreRequest(r.from.id);
      }
      ref.invalidate(requestsProvider);
      ref.invalidate(contactsProvider);
      ref.invalidate(chatsProvider);
      if (accept && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r.from)));
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }
}
