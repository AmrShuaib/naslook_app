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
