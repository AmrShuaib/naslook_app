import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../business/business_list.dart';
import 'circle_detail_page.dart';

class CirclesPage extends ConsumerStatefulWidget {
  const CirclesPage({super.key});
  @override
  ConsumerState<CirclesPage> createState() => _CirclesPageState();
}

class _CirclesPageState extends ConsumerState<CirclesPage> {
  int tab = 0;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myVesselsProvider);
    final discover = ref.watch(discoverVesselsProvider(q));
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: tab == 2 ? null : FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        icon: const Icon(Icons.add_rounded),
        label: const Text('دائرة جديدة'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              _seg('دوائري${mine.value != null ? ' · ${mine.value!.length}' : ''}', 0),
              _seg('اكتشف', 1),
              _seg('تجارية', 2),
            ]),
          ),
        ),
        if (tab == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => q = v.trim()),
              decoration: const InputDecoration(hintText: 'ابحث باسم الدائرة أو موضوعها', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted)),
            ),
          ),
        if (tab == 2)
          const Expanded(child: BizListView())
        else
        Expanded(
          child: (tab == 0 ? mine : discover).when(
            data: (list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.groups_rounded,
                    title: tab == 0 ? 'لم تنضم لأي دائرة بعد' : 'لا دوائر مطابقة',
                    subtitle: tab == 0 ? 'اكتشف الدوائر النشطة حولك أو أنشئ دائرتك.' : 'جرّب كلمة أخرى أو أنشئ دائرة جديدة.',
                    action: tab == 0 ? OutlinedButton(onPressed: () => setState(() => tab = 1), child: const Text('اكتشف حولك')) : null,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(myVesselsProvider);
                      ref.invalidate(discoverVesselsProvider);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => VesselRow(list[i]),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(tab == 0 ? myVesselsProvider : discoverVesselsProvider)),
          ),
        ),
      ]),
    );
  }

  Widget _seg(String label, int i) => Expanded(
        child: InkWell(
          onTap: () => setState(() => tab = i),
          borderRadius: BorderRadius.circular(11),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tab == i ? Joy.surface : null, borderRadius: BorderRadius.circular(11)),
            child: Text(label, style: TextStyle(fontWeight: tab == i ? FontWeight.w600 : FontWeight.w400, color: tab == i ? Joy.text : Joy.textMuted)),
          ),
        ),
      );

  Future<void> _create() async {
    final name = TextEditingController(), topic = TextEditingController();
    bool isPublic = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('دائرة جديدة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الدائرة'), autofocus: true),
            const SizedBox(height: 12),
            TextField(controller: topic, decoration: const InputDecoration(labelText: 'الموضوع أو الوصف'), maxLines: 2),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: isPublic, onChanged: (v) => setS(() => isPublic = v), title: const Text('دائرة عامة'), subtitle: const Text('يمكن لأي أحد إيجادها والانضمام')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final v = await ref.read(apiClientProvider).createVessel(name: name.text.trim(), topic: topic.text.trim(), isPublic: isPublic);
      ref.invalidate(myVesselsProvider);
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v)));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }
}

class VesselRow extends ConsumerWidget {
  final Vessel v;
  const VesselRow(this.v, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v))),
        child: Row(children: [
          Avatar(name: v.name, size: 52, radius: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis)),
                if (v.kind != 'general') Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(v.kind == 'business' ? 'تجارية' : 'حي', style: const TextStyle(fontSize: 10.5, color: Joy.textMuted))),
              ]),
              if (v.topic.isNotEmpty) Text(v.topic, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              Text('${v.members} عضواً${v.lastPostAt != null ? ' · آخر منشور ${timeAgo(v.lastPostAt)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          v.member
              ? Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: const Text('عضو', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w600, fontSize: 12.5)))
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: () async {
                    try {
                      await ref.read(apiClientProvider).joinVessel(v.id);
                      ref.invalidate(myVesselsProvider);
                      ref.invalidate(discoverVesselsProvider);
                      ref.invalidate(feedProvider);
                      if (context.mounted) toast(context, 'انضممت إلى ${v.name}');
                    } catch (e) {
                      if (context.mounted) toast(context, e.toString(), error: true);
                    }
                  },
                  child: const Text('انضم'),
                ),
        ]),
      );
}
