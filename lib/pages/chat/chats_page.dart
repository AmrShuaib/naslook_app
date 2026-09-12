import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
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
    final sender = (m['senderId'] ?? m['sender_id'] ?? m['from'] ?? '').toString();
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

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final requests = ref.watch(requestsProvider);
    final reqCount = requests.value?.length ?? 0;
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            for (final (i, l) in ['المحادثات', reqCount > 0 ? 'الطلبات · $reqCount' : 'الطلبات'].indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(l, style: TextStyle(color: _tab == i ? Joy.primaryOn : Joy.text)), selected: _tab == i, onSelected: (_) => setState(() => _tab = i), showCheckmark: false, selectedColor: Joy.primary),
              ),
          ]),
        ),
        Expanded(child: _tab == 0 ? _chatsTab(chats) : _requestsTab(requests)),
      ]),
    );
  }

  Widget _chatsTab(AsyncValue<List<Chat>> chats) => chats.when(
        data: (all) {
          final q = _q.toLowerCase();
          final list = q.isEmpty ? all : all.where((c) => c.peer.nickname.toLowerCase().contains(q) || c.peer.id.toLowerCase().contains(q) || (c.lastContent?.toLowerCase().contains(q) ?? false)).toList();
          if (all.isEmpty) {
            return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'لا محادثات بعد', subtitle: 'أضف صديقاً بنك نيمه وابدأ الحديث.', action: OutlinedButton(onPressed: _newChat, child: const Text('محادثة جديدة')));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(chatsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              children: [
                if (list.isEmpty && _hits.isEmpty && !_searchingServer) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا نتائج', style: TextStyle(color: Joy.textMuted)))),
                for (final c in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ChatRow(c)),
                if (_q.length >= 2) ...[
                  if (_searchingServer) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                  if (_hits.isNotEmpty) const SectionTitle('رسائل'),
                  for (final h in _hits) Padding(padding: const EdgeInsets.only(bottom: 8), child: _HitRow(h, query: _q)),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(chatsProvider)),
      );

  Widget _requestsTab(AsyncValue<List<FriendRequest>> requests) => requests.when(
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.mark_email_read_outlined, title: 'لا طلبات مراسلة', subtitle: 'رسائل من غير أصدقائك تظهر هنا أولاً حتى تقبلها أو تتجاهلها.')
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(requestsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RequestRow(list[i]),
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

class _ChatRow extends StatelessWidget {
  final Chat c;
  const _ChatRow(this.c);
  @override
  Widget build(BuildContext context) {
    final preview = c.lastContent == null ? 'ابدأ المحادثة' : Message.previewOf(c.lastType ?? 'text', c.lastContent!);
    return JoyCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: c.peer))),
      child: Row(children: [
        Avatar(name: c.peer.nickname, url: c.peer.avatarUrl, size: 50),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(c.peer.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            Text(timeAgo(c.lastAt), style: TextStyle(fontSize: 11.5, color: c.unread > 0 ? Joy.primary : Joy.textMuted)),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(child: Text('${c.lastMine ? 'أنت: ' : ''}$preview', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 13))),
            if (c.unread > 0) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)), child: Text('${c.unread}', style: const TextStyle(color: Joy.primaryOn, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ])),
      ]),
    );
  }
}

/// نتيجة بحث: تفتح المحادثة وتقفز إلى الرسالة.
class _HitRow extends StatelessWidget {
  final ChatSearchHit h;
  final String query;
  const _HitRow(this.h, {required this.query});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: h.peer, initialMessageId: h.id))),
        child: Row(children: [
          Avatar(name: h.peer.nickname, url: h.peer.avatarUrl, size: 40),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(h.peer.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))), Text(timeAgo(h.at), style: const TextStyle(fontSize: 11, color: Joy.textMuted))]),
            Text('${h.mine ? 'أنت: ' : ''}${Message.previewOf(h.type, h.content)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
        ]),
      );
}

class _RequestRow extends ConsumerWidget {
  final FriendRequest r;
  const _RequestRow(this.r);
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r.from))),
        child: Row(children: [
          Avatar(name: r.from.nickname, url: r.from.avatarUrl, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.from.nickname, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${r.lastContent ?? 'يريد مراسلتك'} · ${timeAgo(r.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
          IconButton(tooltip: 'تجاهل', onPressed: () => _act(context, ref, accept: false), icon: const Icon(Icons.close_rounded, color: Joy.textMuted)),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: () => _act(context, ref, accept: true), child: const Text('قبول')),
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
