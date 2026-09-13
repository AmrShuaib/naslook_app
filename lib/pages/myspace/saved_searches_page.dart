import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/saved_search_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/saved_search_providers.dart';
import '../../ui/widgets.dart';
import '../search/search_page.dart';

/// بحوثي المحفوظة: تفعيل/إيقاف التنبيه، عدد المطابقات وآخرها، فتح البحث، وحذف.
class SavedSearchesPage extends ConsumerWidget {
  const SavedSearchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(savedSearchesProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('بحوثي المحفوظة')),
      body: list.when(
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.saved_search_rounded,
                title: 'لا بحوث محفوظة',
                subtitle: 'ابحث عن أي شيء ثم اضغط «نبّهني عند ظهور جديد» ليصلك إشعار كلما نُشر ما يطابقه.',
                action: FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())), icon: const Icon(Icons.search_rounded), label: const Text('ابحث الآن')),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(savedSearchesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _Row(items[i]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(savedSearchesProvider)),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  final SavedSearch s;
  const _Row(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final last = s.lastMatchAt == null ? 'لا مطابقات بعد' : '${s.matches} مطابقة · آخرها ${timeAgo(s.lastMatchAt)}';
    return JoyCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(initialQuery: s.q))),
      child: Row(children: [
        Icon(s.active ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: s.active ? Joy.primary : Joy.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('«${s.q}»', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(s.scopeLabel, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          Text(last, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ])),
        Switch(
          value: s.active,
          onChanged: (v) async {
            try {
              await api.updateSavedSearch(s.id, active: v);
              ref.invalidate(savedSearchesProvider);
            } catch (e) {
              if (context.mounted) toast(context, 'تعذر التحديث', error: true);
            }
          },
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_outline_rounded, color: Joy.textMuted),
          onPressed: () async {
            try {
              await api.deleteSavedSearch(s.id);
              ref.invalidate(savedSearchesProvider);
              if (context.mounted) toast(context, 'حُذف البحث المحفوظ');
            } catch (e) {
              if (context.mounted) toast(context, 'تعذر الحذف', error: true);
            }
          },
        ),
      ]),
    );
  }
}
