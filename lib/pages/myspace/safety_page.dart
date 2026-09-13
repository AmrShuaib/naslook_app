import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/naslife_api.dart';
import '../../api/safety_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';

/// الخصوصية والأمان: المحظورون (إلغاء الحظر) والمحادثات المكتومة (إلغاء الكتم).
class SafetyPage extends ConsumerWidget {
  const SafetyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    final mutes = ref.watch(mutesProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('الخصوصية والأمان')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        const SectionTitle('المحظورون'),
        blocked.when(
          data: (list) => list.isEmpty
              ? const JoyCard(child: Text('لم تحظر أحداً. من صفحة أي شخص أو محادثته يمكنك حظره فلا يراسلك ولا يرى محتواك.', style: TextStyle(color: Joy.textMuted)))
              : JoyCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (i, u) in list.indexed)
                      ListTile(
                        leading: Avatar(name: u.nickname, url: u.avatarUrl, size: 40),
                        title: Text(u.nickname),
                        trailing: TextButton(
                          onPressed: () async {
                            try {
                              await ref.read(apiClientProvider).unblockUser(u.id);
                              ref.invalidate(blockedUsersProvider);
                              ref.invalidate(chatsProvider);
                              if (context.mounted) toast(context, 'أُلغي حظر ${u.nickname}');
                            } catch (e) {
                              if (context.mounted) toast(context, 'تعذر إلغاء الحظر', error: true);
                            }
                          },
                          child: const Text('إلغاء الحظر'),
                        ),
                        shape: i < list.length - 1 ? const Border(bottom: BorderSide(color: Joy.surface2)) : null,
                      ),
                  ]),
                ),
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => JoyCard(child: Text('تعذر جلب المحظورين', style: const TextStyle(color: Joy.textMuted))),
        ),
        const SizedBox(height: 14),
        const SectionTitle('المحادثات المكتومة'),
        mutes.when(
          data: (list) => list.isEmpty
              ? const JoyCard(child: Text('لا محادثات مكتومة. من قائمة أي محادثة اختر «كتم الإشعارات» فلا تظهر شارة رسائلها.', style: TextStyle(color: Joy.textMuted)))
              : JoyCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (i, m) in list.indexed)
                      ListTile(
                        leading: const Icon(Icons.volume_off_rounded, color: Joy.textMuted),
                        title: Text(m.peerId),
                        subtitle: Text(m.until == null ? 'مكتومة دائماً' : 'حتى ${m.until!.day}/${m.until!.month} ${m.until!.hour}:${m.until!.minute.toString().padLeft(2, '0')}'),
                        trailing: TextButton(
                          onPressed: () async {
                            try {
                              await ref.read(apiClientProvider).unmute(m.peerId);
                              ref.invalidate(mutesProvider);
                              if (context.mounted) toast(context, 'أُلغي الكتم');
                            } catch (e) {
                              if (context.mounted) toast(context, 'تعذر إلغاء الكتم', error: true);
                            }
                          },
                          child: const Text('إلغاء الكتم'),
                        ),
                        shape: i < list.length - 1 ? const Border(bottom: BorderSide(color: Joy.surface2)) : null,
                      ),
                  ]),
                ),
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(mutesProvider)),
        ),
      ]),
    );
  }
}
