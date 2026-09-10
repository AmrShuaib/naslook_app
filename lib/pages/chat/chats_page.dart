import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'chat_thread_page.dart';

class ChatsPage extends ConsumerStatefulWidget {
  const ChatsPage({super.key});
  @override
  ConsumerState<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends ConsumerState<ChatsPage> {
  @override
  void initState() {
    super.initState();
    // أي حدث رسالة يعيد تحميل القائمة
    Future.microtask(() {
      final s = ref.read(socketProvider);
      s?.events.listen((e) {
        final ev = e['event'];
        if (ev == 'message' || ev == 'read' || ev == 'delivered') ref.invalidate(chatsProvider);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        child: const Icon(Icons.chat_rounded),
      ),
      body: chats.when(
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'لا محادثات بعد', subtitle: 'أضف صديقاً بنك نيمه وابدأ الحديث.', action: OutlinedButton(onPressed: _newChat, child: const Text('محادثة جديدة')))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(chatsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ChatRow(list[i]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(chatsProvider)),
      ),
    );
  }

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
    final preview = c.lastContent == null ? 'ابدأ المحادثة' : (c.lastType == 'text' ? c.lastContent! : 'مرفق');
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
