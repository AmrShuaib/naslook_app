import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/client.dart' show thumbUrl;
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';
import 'admin_users.dart';

/// البلاغات: تبويب لبلاغات المستخدمين والرسائل (النواة) وتبويب لبلاغات المحتوى مع الإخفاء والاستعادة (server/safety.js).
class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});
  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(tabs: [Tab(key: Key('reports-tab-users'), text: 'بلاغات المستخدمين'), Tab(key: Key('reports-tab-content'), text: 'بلاغات المحتوى')]),
          Expanded(child: TabBarView(children: [_UserReports(), AdminModerationTab()])),
        ]),
      );
}

class _UserReports extends ConsumerStatefulWidget {
  const _UserReports();
  @override
  ConsumerState<_UserReports> createState() => _UserReportsState();
}

class _UserReportsState extends ConsumerState<_UserReports> {
  bool all = false;
  @override
  Widget build(BuildContext context) {
    final rep = ref.watch(adminReportsProvider(all));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(children: [
          for (final (v, l) in [(false, 'المفتوحة'), (true, 'الكل')])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(label: Text(l, style: TextStyle(color: all == v ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: all == v, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => all = v))),
          Expanded(child: Text(rep.valueOrNull?.blocks != null ? '${rep.valueOrNull!.blocks} حظر بين المستخدمين' : '', textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        ]),
      ),
      Expanded(
        child: rep.when(
          data: (r) {
            if (!r.available) return const EmptyState(icon: Icons.flag_outlined, title: 'جدول البلاغات غير متاح', subtitle: 'لم نجد جدول بلاغات في قاعدة بيانات الخادم الأساسي. البلاغات من التطبيق تُرسل إلى الخادم الأساسي وستظهر هنا فور توفر الجدول.');
            if (r.items.isEmpty) return EmptyState(icon: Icons.flag_outlined, title: all ? 'لا بلاغات' : 'لا بلاغات مفتوحة', subtitle: 'كل البلاغات عولجت.');
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [for (final it in r.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ReportCard(r: it))]);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminReportsProvider)),
        ),
      ),
    ]);
  }
}

class _ReportCard extends ConsumerWidget {
  final AdminReport r;
  const _ReportCard({required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = r.action != null;
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (r.target != null) ProfileAvatar(person: r.target!, size: 44),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('بلاغ ضد ${r.target?.nickname.isNotEmpty == true ? r.target!.nickname : r.targetId ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text('من ${r.reporter?.nickname.isNotEmpty == true ? r.reporter!.nickname : r.reporterId ?? '—'} · ${timeAgo(r.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
          if (done) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(switch (r.action!.action) { 'warn' => 'تحذير', 'suspend' => 'إيقاف', _ => 'تجاهل' }, style: const TextStyle(fontSize: 11, color: Joy.textMuted, fontWeight: FontWeight.w600))),
        ]),
        if (r.reason != null || r.text != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text([if (r.reason != null) r.reason!, if (r.text != null && r.text!.isNotEmpty) r.text!].join(': '), style: const TextStyle(height: 1.5))),
        if (done && r.action!.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظة الإدارة: ${r.action!.note}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (r.targetId != null) OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: r.targetId!))), icon: const Icon(Icons.person_search_outlined, size: 18), label: const Text('ملف المُبلَّغ عنه')),
          if (!done) ...[
            FilledButton.tonalIcon(onPressed: () => _act(context, ref, 'ignore'), icon: const Icon(Icons.done_rounded, size: 18), label: const Text('تجاهل')),
            FilledButton.tonalIcon(onPressed: () => _act(context, ref, 'warn'), icon: const Icon(Icons.warning_amber_rounded, size: 18), label: const Text('تحذير')),
            FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => _act(context, ref, 'suspend'), icon: const Icon(Icons.block_rounded, size: 18), label: const Text('إيقاف الحساب')),
          ],
        ]),
      ]),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final note = await askText(context, title: switch (action) { 'warn' => 'تحذير المستخدم', 'suspend' => 'إيقاف الحساب', _ => 'تجاهل البلاغ' }, hint: 'ملاحظة تُحفظ في السجل', confirm: 'تأكيد');
    if (note == null || r.id == null) return;
    try {
      await ref.read(apiClientProvider).adminReportAction(r.id!, action: action, note: note.trim());
      invalidateAdmin(ref);
      if (context.mounted) toast(context, 'سُجّل الإجراء');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}

/// طابور الإشراف على بلاغات المحتوى: كل عنصر مرة واحدة مع عدد المبلّغين وأسبابهم وحالته وآخر إجراء.
class AdminModerationTab extends ConsumerStatefulWidget {
  const AdminModerationTab({super.key});
  @override
  ConsumerState<AdminModerationTab> createState() => _AdminModerationTabState();
}

class _AdminModerationTabState extends ConsumerState<AdminModerationTab> {
  bool all = false;
  String type = '';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminModerationProvider((all, type)));
    final types = q.valueOrNull?.types ?? const <({String id, String name})>[];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(children: [
          for (final (v, l) in [(false, 'المفتوحة'), (true, 'الكل')])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                key: Key('mod-status-${v ? 'all' : 'open'}'),
                label: Text(l, style: TextStyle(color: all == v ? Joy.primaryOn : Joy.text, fontSize: 12.5)),
                selected: all == v, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => all = v),
              ),
            ),
          const Spacer(),
          if (types.isNotEmpty)
            Flexible(
              child: DropdownButton<String>(
                key: const Key('mod-type'),
                value: types.any((t) => t.id == type) ? type : '',
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 12.5, color: Joy.text),
                items: [const DropdownMenuItem(value: '', child: Text('كل الأنواع')), for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => type = v ?? ''),
              ),
            ),
        ]),
      ),
      if (q.valueOrNull != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('${q.value!.open} عنصراً بانتظار المراجعة · يُخفى تلقائياً عند ${q.value!.threshold} مبلّغين', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ),
        ),
      Expanded(
        child: q.when(
          data: (d) => d.items.isEmpty
              ? EmptyState(icon: Icons.verified_user_outlined, title: all ? 'لا بلاغات على المحتوى' : 'لا بلاغات مفتوحة', subtitle: 'كل بلاغات المحتوى رُوجعت.')
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(adminModerationProvider),
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [for (final it in d.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ModerationCard(key: ValueKey(it.key), item: it))]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminModerationProvider)),
        ),
      ),
    ]);
  }
}

class _ModerationCard extends ConsumerStatefulWidget {
  final ModerationItem item;
  const _ModerationCard({super.key, required this.item});
  @override
  ConsumerState<_ModerationCard> createState() => _ModerationCardState();
}

class _ModerationCardState extends ConsumerState<_ModerationCard> {
  final note = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final k = it.key;
    final media = it.mediaUrl;
    final showImage = media != null && media.isNotEmpty && !RegExp(r'\.(mp4|mov|webm|m4v|mp3|m4a|aac|ogg|wav)(\?|$)', caseSensitive: false).hasMatch(media);
    final preview = it.text != null && it.text!.isNotEmpty && it.text != it.title ? it.text! : '';
    return JoyCard(
      key: Key('mod-card-$k'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showImage)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(media), width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: Joy.surface2))),
            ),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _pill(it.typeName.isEmpty ? it.targetType : it.typeName, Joy.primarySoft, Joy.primary),
              _pill(it.missing ? 'محذوف' : it.hidden ? 'مخفي' : 'ظاهر', it.hidden || it.missing ? Joy.surface2 : Joy.accentSoft, it.hidden || it.missing ? Joy.textMuted : Joy.accent, key: Key('mod-state-$k')),
              _pill('${it.reports} ${it.reports == 1 ? 'مبلّغ' : 'مبلّغين'}', Joy.surface2, Joy.text),
            ]),
            const SizedBox(height: 4),
            Text(it.title?.isNotEmpty == true ? it.title! : '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            if (preview.isNotEmpty) Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.4)),
          ])),
        ]),
        const SizedBox(height: 6),
        Text('الناشر: ${it.owner == null ? 'غير معروف' : (it.owner!.nickname.isNotEmpty ? it.owner!.nickname : it.owner!.id)} · آخر بلاغ ${timeAgo(it.lastAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        if (it.reasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [for (final r in it.reasons) _pill(r, Joy.surface2, Joy.text)]),
          ),
        if (it.action != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'آخر إجراء: ${it.action!.label}${it.action!.by?.nickname.isNotEmpty == true ? ' بواسطة ${it.action!.by!.nickname}' : ''} · ${timeAgo(it.action!.at)}${it.action!.note.isNotEmpty ? ' — ${it.action!.note}' : ''}',
              key: Key('mod-last-$k'),
              style: const TextStyle(color: Joy.textMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        TextField(key: Key('mod-note-$k'), controller: note, maxLength: 300, decoration: const InputDecoration(hintText: 'ملاحظة (تصل لصاحب المحتوى عند الإخفاء أو الإيقاف)', isDense: true, counterText: '')),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (!it.hidden && !it.missing)
            FilledButton.icon(key: Key('mod-hide-$k'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: busy ? null : () => _act('hide'), icon: const Icon(Icons.visibility_off_outlined, size: 18), label: const Text('إخفاء')),
          if (it.hidden)
            FilledButton.tonalIcon(key: Key('mod-restore-$k'), onPressed: busy ? null : () => _act('restore'), icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('إعادة الإظهار')),
          FilledButton.tonalIcon(key: Key('mod-dismiss-$k'), onPressed: busy ? null : () => _act('dismiss'), icon: const Icon(Icons.done_rounded, size: 18), label: const Text('تجاهل')),
          if (it.owner != null && !it.missing) ...[
            OutlinedButton.icon(key: Key('mod-suspend-$k'), style: OutlinedButton.styleFrom(foregroundColor: Joy.danger), onPressed: busy ? null : () => _act('suspend-owner'), icon: const Icon(Icons.block_rounded, size: 18), label: const Text('إيقاف الناشر')),
            TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: it.owner!.id))), icon: const Icon(Icons.person_search_outlined, size: 18), label: const Text('ملف الناشر')),
          ],
        ]),
      ]),
    );
  }

  Widget _pill(String t, Color bg, Color fg, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
      );

  Future<void> _act(String action) async {
    final it = widget.item;
    // إيقاف الحساب أثره أكبر من المحتوى نفسه: تأكيد صريح
    if (action == 'suspend-owner') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('إيقاف ${it.owner?.nickname ?? 'الناشر'}؟'),
          content: const Text('يُوقف الحساب ويُخفى هذا المحتوى ويصل للناشر إشعار. يمكن رفع الإيقاف من ملفه.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(key: const Key('mod-suspend-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('إيقاف')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminModerate(it.targetType, it.targetId, action: action, note: note.text.trim());
      ref.invalidate(adminModerationProvider);
      ref.invalidate(adminOverviewProvider);
      if (mounted) toast(context, switch (action) { 'hide' => 'أُخفي المحتوى', 'restore' => 'أُعيد إظهار المحتوى', 'suspend-owner' => 'أُوقف الناشر وأُخفي المحتوى', _ => 'تُجوهلت البلاغات' });
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
