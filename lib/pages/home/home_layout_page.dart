import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/home_layout.dart';
import '../../state/layout_providers.dart';

/// شاشة «تخصيص الرئيسية» (النموذج ٢): الأقسام بمقبض سحب ومفتاح إظهار وخيارات محتوى، وأقسام شريط التنقّل.
class HomeLayoutPage extends ConsumerStatefulWidget {
  const HomeLayoutPage({super.key});
  @override
  ConsumerState<HomeLayoutPage> createState() => _HomeLayoutPageState();
}

class _HomeLayoutPageState extends ConsumerState<HomeLayoutPage> {
  String? _open;

  /// خيارات محتوى القسم: معرّف ونص.
  static const blockOptions = <String, List<(String, String)>>{
    'around': [('friends', 'الأصدقاء فقط')],
    'feed': [('text', 'نصوص فقط')],
  };

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(homeLayoutProvider);
    final n = ref.read(homeLayoutProvider.notifier);
    final visible = layout.visible.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تخصيص الرئيسية'),
          actions: [
            TextButton(key: const Key('layout-reset'), onPressed: layout.isDefault ? null : () => _confirmReset(context, n), child: const Text('استعادة الافتراضي')),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'الأقسام'), Tab(text: 'شريط التنقّل')]),
        ),
        body: TabBarView(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('$visible ظاهرة · ${layout.hidden.length} مخفية. اسحب من المقبض لإعادة الترتيب، وأطفئ ما لا تريد رؤيته. اضغط القسم لخيارات محتواه.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
            ),
            Expanded(
              child: ReorderableListView.builder(
                key: const Key('layout-list'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                buildDefaultDragHandles: false,
                itemCount: layout.order.length,
                onReorderItem: (from, to) {
                  final o = [...layout.order];
                  final id = o.removeAt(from);
                  o.insert(to, id);
                  // المثبّت يبقى أول القائمة مهما سُحب غيره فوقه
                  n.update((l) => l.reorder(o));
                },
                itemBuilder: (context, i) {
                  final id = layout.order[i];
                  final meta = homeBlockMeta(id);
                  final off = layout.isHidden(id), pinned = layout.isPinned(id);
                  final opts = blockOptions[id] ?? const [];
                  return Card(
                    key: ValueKey('row-$id'),
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Joy.line)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        key: Key('layout-row-$id'),
                        onTap: opts.isEmpty ? null : () => setState(() => _open = _open == id ? null : id),
                        leading: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (pinned)
                            const SizedBox(width: 28, child: Icon(Icons.push_pin_rounded, size: 18, color: Joy.textMuted))
                          else
                            ReorderableDragStartListener(index: i, child: SizedBox(key: Key('layout-drag-$id'), width: 28, child: const Icon(Icons.drag_indicator_rounded, color: Joy.textMuted))),
                          Container(width: 36, height: 36, decoration: BoxDecoration(color: off ? Joy.surface2 : Joy.primarySoft, borderRadius: BorderRadius.circular(10)), child: Icon(meta?.icon ?? Icons.widgets_outlined, color: off ? Joy.textMuted : Joy.primary, size: 20)),
                        ]),
                        title: Row(children: [
                          Flexible(child: Text(meta?.title ?? id, style: TextStyle(fontWeight: FontWeight.w600, color: off ? Joy.textMuted : Joy.text))),
                          if (layout.isFresh(id)) Container(margin: const EdgeInsetsDirectional.only(start: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.sun, borderRadius: BorderRadius.circular(999)), child: const Text('جديد', style: TextStyle(color: Joy.sunText, fontSize: 10.5, fontWeight: FontWeight.w700))),
                        ]),
                        subtitle: Text(pinned ? 'مثبّت · ${meta?.hint ?? ''}' : (opts.isEmpty ? meta?.hint ?? '' : '${meta?.hint ?? ''} · ${opts.length} خيار'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        trailing: Switch(key: Key('layout-switch-$id'), value: !off, onChanged: pinned ? null : (_) => n.update((l) => l.toggle(id))),
                      ),
                      if (_open == id && opts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final (key, label) in opts)
                              FilterChip(
                                key: Key('layout-opt-$id-$key'),
                                label: Text(label),
                                selected: (layout.opts[id] ?? const []).contains(key),
                                onSelected: (_) => n.update((l) => l.toggleOpt(id, key)),
                              ),
                          ]),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ]),
          _NavPicker(layout: layout),
        ]),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, HomeLayoutNotifier n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة الترتيب الافتراضي؟'),
        content: const Text('تعود كل الأقسام ظاهرة بترتيبها الأصلي، ويعود شريط التنقّل إلى الدوائر والمحادثات.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('layout-reset-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة'))],
      ),
    );
    if (ok == true) await n.resetAll();
  }
}

/// اختيار قسمي شريط التنقّل بين «الخريطة» و«ماي سبيس» (زر الكاميرا في الوسط).
class _NavPicker extends ConsumerWidget {
  final HomeLayout layout;
  const _NavPicker({required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(homeLayoutProvider.notifier);
    final middle = [for (final id in layout.nav) if (id != 'home' && id != 'me') id];
    final full = middle.length >= navMiddleSlots;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text('اختر $navMiddleSlots من الأقسام لشريط التنقّل السفلي. «الخريطة» و«ماي سبيس» ثابتان في الطرفين، وزر الكاميرا في الوسط.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 12),
        // معاينة الشريط
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: Joy.surface, border: Border.all(color: Joy.line), borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: Row(children: [
            for (final id in layout.nav) ...[
              if (id == layout.nav[layout.nav.length ~/ 2]) Container(width: 46, height: 46, decoration: const BoxDecoration(color: Joy.primary, shape: BoxShape.circle), child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 22)),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(navTabMeta(id)?.icon ?? Icons.circle_outlined, size: 20, color: id == 'home' ? Joy.primary : Joy.textMuted), Text(navTabMeta(id)?.label ?? id, style: TextStyle(fontSize: 10, color: id == 'home' ? Joy.primary : Joy.textMuted, fontWeight: FontWeight.w600))])),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        Text(full ? '$navMiddleSlots من $navMiddleSlots · أطفئ قسماً لتضيف غيره' : '${middle.length} من $navMiddleSlots · يمكنك إضافة ${navMiddleSlots - middle.length}', key: const Key('nav-count'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        for (final t in navTabs)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Joy.line)),
            child: SwitchListTile(
              key: Key('nav-switch-${t.id}'),
              secondary: Container(width: 36, height: 36, decoration: BoxDecoration(color: layout.nav.contains(t.id) ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(10)), child: Icon(t.icon, color: layout.nav.contains(t.id) ? Joy.primary : Joy.textMuted, size: 20)),
              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.locked ? 'ثابت' : (middle.contains(t.id) ? 'في الشريط' : 'غير ظاهر'), style: const TextStyle(fontSize: 12)),
              value: layout.nav.contains(t.id),
              onChanged: t.locked || (full && !middle.contains(t.id))
                  ? null
                  : (v) => n.update((l) => l.withNav(v ? [...middle, t.id] : [for (final m in middle) if (m != t.id) m])),
            ),
          ),
        const SizedBox(height: 8),
        const Text('الأقسام غير الموجودة في الشريط تبقى متاحة من «الاختصارات» في الرئيسية ومن ماي سبيس.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
      ],
    );
  }
}
