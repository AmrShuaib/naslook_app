import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../events/events_page.dart' show when;
import 'admin_shell.dart';

class AdminContentPage extends ConsumerWidget {
  const AdminContentPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(adminContentProvider);
    return content.when(
      data: (c) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        SectionTitle('الفعاليات · ${c.events.length}'),
        if (c.events.isEmpty) const EmptyState(icon: Icons.event_outlined, title: 'لا فعاليات'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, e) in c.events.indexed)
            ListRow(
              leading: ProfileAvatar(person: e.host, size: 40),
              title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${e.host.nickname} · ${when(e.startsAt)} · ${e.sold} تذكرة${e.cancelled ? ' · ملغاة' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: e.cancelled ? const Text('ملغاة', style: TextStyle(color: Joy.textMuted, fontSize: 12)) : IconButton(tooltip: 'إلغاء الفعالية واسترداد التذاكر', onPressed: () => _cancelEvent(context, ref, e.id, e.title), icon: const Icon(Icons.cancel_outlined, color: Joy.danger)),
              divider: i < c.events.length - 1,
            ),
        ])),
        const SizedBox(height: 8),
        SectionTitle('إعلانات السوق · ${c.listings.length}'),
        if (c.listings.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'لا إعلانات'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, l) in c.listings.indexed)
            ListRow(
              leading: ProfileAvatar(person: l.seller, size: 40),
              title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${l.seller.nickname} · ${marketCategories[l.category] ?? l.category} · ${money(l.price)} · ${timeAgo(l.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: 'إخفاء الإعلان', onPressed: () => _hide(context, ref, l.id, l.title), icon: const Icon(Icons.visibility_off_outlined, color: Joy.danger)),
              divider: i < c.listings.length - 1,
            ),
        ])),
        const SizedBox(height: 8),
        SectionTitle('الدوائر الاجتماعية · ${c.vessels.length}'),
        if (c.vessels.isEmpty) const EmptyState(icon: Icons.groups_outlined, title: 'لا بيانات', subtitle: 'جدول الدوائر الاجتماعية في الخادم الأساسي غير متاح للقراءة من هنا.'),
        JoyCard(padding: EdgeInsets.zero, child: Column(children: [
          for (final (i, v) in c.vessels.indexed) ListRow(leading: const Icon(Icons.groups_outlined, color: Joy.primary), title: Text(v.name), subtitle: Text('${v.kind}${v.members != null ? ' · ${v.members} عضو' : ''}'), divider: i < c.vessels.length - 1),
        ])),
      ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminContentProvider)),
    );
  }

  Future<void> _cancelEvent(BuildContext context, WidgetRef ref, String id, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('إلغاء "$title"؟'), content: const Text('تُسترد كل التذاكر إلى المشترين ويُخصم من المضيف.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إلغاء الفعالية'))]));
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).adminCancelEvent(id);
      invalidateAdmin(ref);
      if (context.mounted) toast(context, 'أُلغيت الفعالية');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _hide(BuildContext context, WidgetRef ref, String id, String title) async {
    try {
      await ref.read(apiClientProvider).adminHideListing(id);
      invalidateAdmin(ref);
      if (context.mounted) toast(context, 'أُخفي "$title"');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
