import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/nav_provider.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';

/// يفتح الملف الشخصي لأي مستخدم؛ إن كان المستخدم نفسه يُنقل إلى ماي سبيس.
void openProfile(BuildContext context, Person person) {
  if (person.id.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(person: person)));
}

final userProfileProvider = FutureProvider.family<Profile, String>((ref, id) => ref.watch(apiClientProvider).profileOf(id));
final userPresenceProvider = FutureProvider.family<bool, String>((ref, id) async {
  try {
    return (await ref.watch(apiClientProvider).presenceOf(id))['online'] == true;
  } catch (_) {
    return false;
  }
});

class UserProfilePage extends ConsumerWidget {
  final Person person;
  const UserProfilePage({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(appStateProvider.select((s) => s.user));
    final isMe = me?.id == person.id;
    final profile = ref.watch(userProfileProvider(person.id));
    final online = ref.watch(userPresenceProvider(person.id)).value ?? false;
    final contacts = ref.watch(contactsProvider).value ?? const <Person>[];
    final isContact = contacts.any((c) => c.id == person.id);
    final p = profile.valueOrNull;
    final nickname = p?.nickname.isNotEmpty == true ? p!.nickname : person.nickname;
    final avatar = p?.avatarUrl ?? person.avatarUrl;

    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(nickname),
        actions: [
          if (!isMe)
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (v) => v == 'report' ? _report(context, ref) : _block(context, ref),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ'))),
                PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر', style: TextStyle(color: Joy.danger)))),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userProfileProvider(person.id));
          ref.invalidate(userPresenceProvider(person.id));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(child: Avatar(name: nickname, url: avatar, size: 104, ring: true, online: online)),
            const SizedBox(height: 12),
            Center(child: Text(nickname, style: Theme.of(context).textTheme.headlineSmall)),
            const SizedBox(height: 2),
            Center(
              child: Text(
                [
                  if (person.id.isNotEmpty) person.id,
                  online ? 'متصل الآن' : 'غير متصل',
                  if (p?.createdAt != null) 'عضو منذ ${_since(p!.createdAt!)}',
                ].join(' · '),
                style: TextStyle(color: online ? Joy.success : Joy.textMuted, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (isMe)
              OutlinedButton.icon(
                onPressed: () { Navigator.of(context).pop(); ref.read(navIndexProvider.notifier).state = 4; },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('هذا ملفك · عدّله من ماي سبيس'),
              )
            else
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: Person(id: person.id, nickname: nickname, avatarUrl: avatar)))), icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('مراسلة'))),
                const SizedBox(width: 8),
                Expanded(
                  child: isContact
                      ? OutlinedButton.icon(onPressed: () => _removeContact(context, ref), icon: const Icon(Icons.check_rounded, color: Joy.success), label: const Text('صديق'))
                      : OutlinedButton.icon(onPressed: () => _addContact(context, ref), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة صديق')),
                ),
              ]),
            const SizedBox(height: 20),
            profile.when(
              data: (pr) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (pr.bio.isNotEmpty) ...[
                  const SectionTitle('نبذة'),
                  JoyCard(child: Text(pr.bio, style: const TextStyle(height: 1.6))),
                  const SizedBox(height: 14),
                ],
                if (pr.skills.isNotEmpty || pr.hobbies.isNotEmpty || pr.lookingFor.isNotEmpty) ...[
                  const SectionTitle('عنه'),
                  JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (pr.skills.isNotEmpty) _chips('مهاراته', pr.skills, Joy.primarySoft, Joy.primary),
                    if (pr.hobbies.isNotEmpty) _chips('هواياته', pr.hobbies, Joy.sunSoft, Joy.sunText),
                    if (pr.lookingFor.isNotEmpty) _chips('يبحث عن', pr.lookingFor, Joy.accentSoft, Joy.accent),
                  ])),
                  const SizedBox(height: 14),
                ],
                if (pr.offerings.isNotEmpty) ...[
                  const SectionTitle('عروضه'),
                  for (final o in pr.offerings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: JoyCard(child: Row(children: [
                        if (o.imageUrl != null && o.imageUrl!.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(o.imageUrl!), width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52))) else const Icon(Icons.local_offer_outlined, color: Joy.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(o.name, style: const TextStyle(fontWeight: FontWeight.w600)), if (o.description.isNotEmpty) Text(o.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)])),
                      ])),
                    ),
                ],
                if (pr.bio.isEmpty && pr.skills.isEmpty && pr.hobbies.isEmpty && pr.lookingFor.isEmpty && pr.offerings.isEmpty)
                  const EmptyState(icon: Icons.person_outline_rounded, title: 'لم يضف تفاصيل بعد'),
              ]),
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => e is ApiException && (e.statusCode == 403 || e.statusCode == 404)
                  ? const EmptyState(icon: Icons.lock_outline_rounded, title: 'ملف خاص', subtitle: 'تفاصيل هذا المستخدم تظهر لأصدقائه فقط')
                  : ErrorState(e, onRetry: () => ref.invalidate(userProfileProvider(person.id))),
            ),
          ],
        ),
      ),
    );
  }

  static String _since(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays < 30) return 'أيام';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()} شهر';
    return '${(d.inDays / 365).floor()} سنة';
  }

  Widget _chips(String title, List<String> items, Color bg, Color fg) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Joy.textMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in items) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(s, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)))]),
        ]),
      );

  Future<void> _addContact(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiClientProvider).addContact(person.id);
      ref.invalidate(contactsProvider);
      ref.invalidate(requestsProvider);
      if (context.mounted) toast(context, 'أُرسل طلب الصداقة إلى ${person.nickname}');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _removeContact(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إزالة ${person.nickname} من أصدقائك؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إزالة'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).removeContact(person.id);
      ref.invalidate(contactsProvider);
      if (context.mounted) toast(context, 'أُزيل من أصدقائك');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await askText(context, title: 'إبلاغ عن ${person.nickname}', hint: 'ما المشكلة؟', confirm: 'إرسال البلاغ');
    if (reason == null || reason.isEmpty || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).reportUser(person.id, reason);
      if (context.mounted) toast(context, 'وصل بلاغك وسنراجعه');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حظر ${person.nickname}؟'),
        content: const Text('لن يستطيع مراسلتك أو رؤية لحظاتك.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حظر'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).blockUser(person.id);
      ref.invalidate(contactsProvider);
      ref.invalidate(chatsProvider);
      if (context.mounted) { toast(context, 'تم حظر ${person.nickname}'); Navigator.of(context).pop(); }
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }
}
