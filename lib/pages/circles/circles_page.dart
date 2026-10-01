import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../../state/safety_providers.dart';
import '../business/business_list.dart';
import '../../core/nav_provider.dart';
import 'post_card.dart';
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
        else if (tab == 0)
          Expanded(child: _MineTab(mine: mine, onDiscover: () => setState(() => tab = 1), onCreate: _create))
        else
        Expanded(
          child: discover.when(
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.groups_rounded, title: 'لا دوائر مطابقة', subtitle: 'جرّب كلمة أخرى أو أنشئ دائرة جديدة.')
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
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(discoverVesselsProvider)),
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
    final r = await showCreateCircleSheet(context);
    if (r == null) return;
    try {
      final v = await ref.read(apiClientProvider).createVessel(name: r.name, topic: r.topic, isPublic: r.isPublic);
      ref.invalidate(myVesselsProvider);
      if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v)));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }
}

/// «دوائري» بنظام «الخريطة أولاً»: حلقات الدوائر (حلقة ملوّنة لما فيه جديد خلال ٢٤ ساعة) ثم آخر ما في دوائرك ثم اكتشف حولك.
class _MineTab extends ConsumerWidget {
  final AsyncValue<List<Vessel>> mine;
  final VoidCallback onDiscover, onCreate;
  const _MineTab({required this.mine, required this.onDiscover, required this.onCreate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = mine.value ?? const <Vessel>[];
    final feed = ref.watch(feedProvider);
    final blocked = ref.watch(blockedIdsProvider);
    final discover = (ref.watch(discoverVesselsProvider('')).valueOrNull ?? const <Vessel>[]).where((v) => !v.member).take(8).toList();
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myVesselsProvider);
        ref.invalidate(feedProvider);
        ref.invalidate(discoverVesselsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final v in list)
                  _Ring(
                    key: Key('circle-ring-${v.id}'),
                    name: v.name,
                    fresh: v.lastPostAt != null && now.difference(v.lastPostAt!).inHours < 24,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v))),
                  ),
                _Ring(key: const Key('circle-ring-new'), name: 'جديدة', add: true, onTap: onCreate),
              ],
            ),
          ),
          if (mine.isLoading && list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (!mine.isLoading && list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: JoyCard(
                color: Joy.sunSoft,
                child: Row(children: [
                  const Icon(Icons.groups_rounded, color: Joy.sunText),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('لم تنضم لأي دائرة بعد. اكتشف الدوائر النشطة حولك أو أنشئ دائرتك.', style: TextStyle(color: Joy.sunText))),
                  TextButton(onPressed: onDiscover, child: const Text('اكتشف')),
                ]),
              ),
            ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 6), child: SectionTitle('آخر ما في دوائرك', action: 'الخريطة', onAction: () => openNavTab(ref, 'home'))),
          feed.when(
            data: (all) {
              final posts = [for (final p in all) if (!isBlockedId(blocked, p.author.id)) p];
              return posts.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: EmptyState(icon: Icons.forum_outlined, title: 'لا منشورات بعد', subtitle: 'انضم إلى دائرة أو انشر أول منشور فيها.'))
                  : Column(children: [for (final p in posts.take(20)) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: PostCard(p))]);
            },
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: ErrorState(e, onRetry: () => ref.invalidate(feedProvider))),
          ),
          if (discover.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 6), child: SectionTitle('اكتشف حولك', action: 'الكل', onAction: onDiscover)),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: discover.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _DiscoverCard(discover[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final String name;
  final bool fresh, add;
  final VoidCallback onTap;
  const _Ring({super.key, required this.name, required this.onTap, this.fresh = false, this.add = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: SizedBox(
            width: 68,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fresh ? Joy.primary : (add ? Colors.transparent : Joy.line), width: fresh ? 2.5 : 1.5)),
                child: add
                    ? Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Joy.control, width: 1.5)), child: const Icon(Icons.add_rounded, color: Joy.primary))
                    : Avatar(name: name, size: 56),
              ),
              const SizedBox(height: 5),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: fresh ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      );
}

class _DiscoverCard extends ConsumerWidget {
  final Vessel v;
  const _DiscoverCard(this.v);
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        width: 160,
        child: JoyCard(
          key: Key('discover-${v.id}'),
          padding: const EdgeInsets.all(12),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleDetailPage(vesselId: v.id, initial: v))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Avatar(name: v.name, size: 40),
            Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text('${v.kind == 'business' ? 'تجارية' : (v.topic.isNotEmpty ? v.topic : 'مجتمع')} · ${v.members} عضواً', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
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
              child: const Text('انضم', style: TextStyle(fontSize: 12.5)),
            ),
          ]),
        ),
      );
}

/// ما تعود به ورقة إنشاء الدائرة.
class NewCircle {
  final String name, topic;
  final bool isPublic;
  const NewCircle({required this.name, required this.topic, required this.isPublic});
}

/// ورقة سفلية لإنشاء دائرة: تتحرك فوق لوحة المفاتيح ولا يغطّيها شيء، مع عدّاد للاسم واختيار عامة/خاصة كبطاقتين.
Future<NewCircle?> showCreateCircleSheet(BuildContext context) => showModalBottomSheet<NewCircle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Joy.surface,
      builder: (_) => const CreateCircleSheet(),
    );

class CreateCircleSheet extends StatefulWidget {
  const CreateCircleSheet({super.key});
  @override
  State<CreateCircleSheet> createState() => _CreateCircleSheetState();
}

class _CreateCircleSheetState extends State<CreateCircleSheet> {
  final _name = TextEditingController();
  final _topic = TextEditingController();
  var _public = true;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.of(context).pop(NewCircle(name: n, topic: _topic.text.trim(), isPublic: _public));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _name.text.trim().isNotEmpty;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.groups_rounded, color: Joy.primary)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('دائرة جديدة', style: TextStyle(fontFamily: AppTheme.displayFont, fontWeight: FontWeight.w700, fontSize: 21)),
              Text('مكان لأصدقائك أو جيرانك أو مهتمّين بموضوع واحد', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ])),
          ]),
          const SizedBox(height: 18),
          TextField(
            key: const Key('circle-name'),
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(labelText: 'اسم الدائرة', hintText: 'مثال: ناس لايف · التحديثات', prefixIcon: Icon(Icons.badge_outlined, color: Joy.textMuted)),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('circle-topic'),
            controller: _topic,
            maxLength: 160,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(labelText: 'الموضوع أو الوصف', hintText: 'عمّ تتحدث الدائرة؟ يظهر للمنضمّين الجدد', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _VisibilityOption(key: const Key('circle-public'), selected: _public, icon: Icons.public_rounded, title: 'عامة', subtitle: 'يجدها الجميع وينضمون فوراً', onTap: () => setState(() => _public = true))),
            const SizedBox(width: 10),
            Expanded(child: _VisibilityOption(key: const Key('circle-private'), selected: !_public, icon: Icons.lock_outline_rounded, title: 'خاصة', subtitle: 'بدعوة منك فقط', onTap: () => setState(() => _public = false))),
          ]),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('circle-create'),
            onPressed: canCreate ? _submit : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إنشاء الدائرة'),
          ),
        ]),
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _VisibilityOption({super.key, required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected ? Joy.primarySoft : Joy.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Joy.primary : Joy.line, width: selected ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: selected ? Joy.primary : Joy.textMuted),
              const Spacer(),
              if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: Joy.primary),
            ]),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: selected ? Joy.primary : Joy.text)),
            Text(subtitle, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5, height: 1.4)),
          ]),
        ),
      );
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
