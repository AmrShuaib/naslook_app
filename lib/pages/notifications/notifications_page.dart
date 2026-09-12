import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/notify_api.dart';
import '../../core/app_theme.dart';
import '../../core/notify_open.dart';
import '../../state/app_state.dart';
import '../../state/notify_providers.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';

/// التنبيهات: إشعارات الطلبات والحجوزات والمحفظة والإدارة، ثم طلبات الصداقة والرسائل غير المقروءة والمنشورات الجديدة في دوائري.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notif = ref.watch(notificationsProvider);
    final reqs = ref.watch(requestsProvider);
    final chats = ref.watch(chatsProvider).value?.where((c) => c.unread > 0).toList() ?? const <Chat>[];
    final feed = ref.watch(feedProvider).value?.where((p) => p.unread).toList() ?? const <Post>[];
    final contacts = ref.watch(contactsProvider);
    final unread = notif.valueOrNull?.unread ?? 0;

    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('التنبيهات')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(notifyUnreadProvider);
          ref.invalidate(requestsProvider);
          ref.invalidate(chatsProvider);
          ref.invalidate(feedProvider);
          ref.invalidate(contactsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            SectionTitle('الإشعارات', action: unread > 0 ? 'تعليم الكل كمقروء' : null, onAction: unread > 0 ? () => _readAll(context, ref) : null),
            notif.when(
              data: (p) => p.items.isEmpty
                  ? const _Hint('تصلك هنا الطلبات والحجوزات والتحويلات والتقييمات وإجراءات الإدارة')
                  : Column(children: [for (final n in p.items.take(40)) Padding(padding: const EdgeInsets.only(bottom: 8), child: NotificationCard(n))]),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => _Hint(e.toString()),
            ),
            const SizedBox(height: 14),
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

  Future<void> _readAll(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiClientProvider).notifyRead(all: true);
      ref.invalidate(notificationsProvider);
      ref.invalidate(notifyUnreadProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
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

/// بطاقة إشعار: أيقونة النوع، العنوان والنص، الوقت، ونقطة لغير المقروء. النقر يفتح الوجهة ويعلّمه مقروءاً.
class NotificationCard extends ConsumerWidget {
  final AppNotification n;
  const NotificationCard(this.n, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = notificationStyle(n.kind);
    return JoyCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => openNotification(context, ref, n),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: s.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(s.icon, color: s.color, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: n.unread ? FontWeight.w700 : FontWeight.w600, fontSize: 13.5))),
            if (n.unread) Container(width: 8, height: 8, margin: const EdgeInsetsDirectional.only(start: 6), decoration: const BoxDecoration(color: Joy.accent, shape: BoxShape.circle)),
          ]),
          if (n.body.isNotEmpty) Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          Text(timeAgo(n.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
        ])),
      ]),
    );
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
