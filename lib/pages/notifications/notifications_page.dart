import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';

/// التنبيهات: طلبات الصداقة والرسائل غير المقروءة والمنشورات الجديدة في دوائري.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reqs = ref.watch(requestsProvider);
    final chats = ref.watch(chatsProvider).value?.where((c) => c.unread > 0).toList() ?? const <Chat>[];
    final feed = ref.watch(feedProvider).value?.where((p) => p.unread).toList() ?? const <Post>[];
    final contacts = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('التنبيهات')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(requestsProvider);
          ref.invalidate(chatsProvider);
          ref.invalidate(feedProvider);
          ref.invalidate(contactsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const SectionTitle('طلبات مراسلة'),
            reqs.when(
              data: (list) => list.isEmpty
                  ? const _Hint('لا طلبات جديدة')
                  : Column(children: [for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _RequestRow(r))]),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => _Hint(e.toString()),
            ),
            const SizedBox(height: 14),
            const SectionTitle('رسائل غير مقروءة'),
            if (chats.isEmpty) const _Hint('كل الرسائل مقروءة')
            else for (final c in chats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: JoyCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: c.peer))),
                  child: Row(children: [
                    ProfileAvatar(person: c.peer, size: 40),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${c.peer.nickname}: ${c.lastContent ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)), child: Text('${c.unread}', style: const TextStyle(color: Joy.primaryOn, fontSize: 11, fontWeight: FontWeight.w700))),
                  ]),
                ),
              ),
            const SizedBox(height: 14),
            const SectionTitle('جديد في دوائرك'),
            if (feed.isEmpty) const _Hint('لا منشورات جديدة')
            else for (final p in feed.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: JoyCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    ProfileAvatar(person: p.author, size: 40),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.author.nickname} في ${p.vesselName ?? 'دائرتك'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      Text(p.type == 'text' ? p.content : 'مرفق', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                    ])),
                    Text(timeAgo(p.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
                  ]),
                ),
              ),
            const SizedBox(height: 14),
            SectionTitle('أصدقائي', action: 'إضافة', onAction: () => _add(context, ref)),
            contacts.when(
              data: (list) => list.isEmpty
                  ? const _Hint('أضف صديقاً بنك نيمه لتظهر رسائله ولحظاته هنا')
                  : Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final p in list)
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p))),
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(width: 64, child: Column(children: [ProfileAvatar(person: p, size: 52), const SizedBox(height: 4), Text(p.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5))])),
                        ),
                    ]),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => _Hint(e.toString()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final h = await askText(context, title: 'إضافة صديق', hint: 'النك نيم', confirm: 'إرسال الطلب', maxLines: 1);
    if (h == null || h.isEmpty) return;
    try {
      await ref.read(apiClientProvider).addContact(h.trim().toLowerCase());
      ref.invalidate(contactsProvider);
      ref.invalidate(requestsProvider);
      ref.invalidate(chatsProvider);
      if (context.mounted) toast(context, 'أُضيف $h إلى أصدقائك');
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }
}

class _RequestRow extends ConsumerWidget {
  final FriendRequest r;
  const _RequestRow(this.r);
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r.from))),
        child: Row(children: [
          ProfileAvatar(person: r.from, size: 44),
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
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text, style: const TextStyle(color: Joy.textMuted, fontSize: 13)));
}
