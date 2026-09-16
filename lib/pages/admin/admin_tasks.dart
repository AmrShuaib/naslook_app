import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

const taskStatuses = [('todo', 'جديدة', Icons.radio_button_unchecked), ('doing', 'قيد التنفيذ', Icons.play_circle_outline), ('review', 'للمراجعة', Icons.rate_review_outlined), ('blocked', 'معلّقة', Icons.pause_circle_outline), ('done', 'منجزة', Icons.check_circle_outline)];
const taskPriorities = [('low', 'منخفضة'), ('normal', 'عادية'), ('high', 'مرتفعة'), ('urgent', 'عاجلة')];
String statusName(String s) => taskStatuses.firstWhere((x) => x.$1 == s, orElse: () => taskStatuses.first).$2;
String priorityName(String p) => taskPriorities.firstWhere((x) => x.$1 == p, orElse: () => taskPriorities[1]).$2;
Color priorityColor(String p) => switch (p) { 'urgent' => Joy.danger, 'high' => Joy.sunText, 'low' => Joy.textMuted, _ => Joy.primary };
Color statusColor(String s) => switch (s) { 'done' => Joy.success, 'doing' => Joy.primary, 'review' => Joy.sunText, 'blocked' => Joy.danger, _ => Joy.textMuted };
String dueText(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final now = DateTime.now();
  final day = DateTime(l.year, l.month, l.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  if (day == 0) return 'اليوم $hm';
  if (day == 1) return 'غداً $hm';
  if (day == -1) return 'أمس $hm';
  return '${l.year}/${l.month}/${l.day} $hm';
}

/// قسم المهام: مهامي / فريقي / الكل، عدّادات، فلتر حالة وبحث، إنشاء وإسناد، وتفاصيل بقائمة تحقق وتعليقات وسجل.
class AdminTasksPage extends ConsumerStatefulWidget {
  const AdminTasksPage({super.key});
  @override
  ConsumerState<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends ConsumerState<AdminTasksPage> {
  String view = 'mine', status = 'open', query = '';
  bool summary = false;

  String get key => '$view|$status';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminTasksProvider(key));
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminTasksProvider(key))),
      data: (l) {
        final q = query.trim().toLowerCase();
        final items = q.isEmpty ? l.items : l.items.where((t) => t.title.toLowerCase().contains(q) || t.description.toLowerCase().contains(q) || (t.assignee?.nickname.toLowerCase().contains(q) ?? false)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          Row(children: [
            Expanded(child: SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'mine', label: Text('مهامي'), icon: Icon(Icons.person_outline)),
                if (l.canAssign || l.canManage) const ButtonSegment(value: 'team', label: Text('فريقي'), icon: Icon(Icons.groups_outlined)),
                if (l.canManage) const ButtonSegment(value: 'all', label: Text('الكل'), icon: Icon(Icons.all_inclusive)),
              ],
              selected: {view},
              onSelectionChanged: (s) => setState(() => view = s.first),
            )),
            const SizedBox(width: 8),
            FilledButton.icon(key: const Key('task-new'), onPressed: () => _create(context, l), icon: const Icon(Icons.add_task_rounded), label: const Text('مهمة')),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Counter(key: const Key('task-count-open'), label: 'مفتوحة', value: (l.counts['todo'] ?? 0) + (l.counts['doing'] ?? 0) + (l.counts['review'] ?? 0) + (l.counts['blocked'] ?? 0), color: Joy.primary),
            _Counter(label: 'قيد التنفيذ', value: l.counts['doing'] ?? 0, color: Joy.primary),
            _Counter(label: 'للمراجعة', value: l.counts['review'] ?? 0, color: Joy.sunText),
            _Counter(key: const Key('task-count-overdue'), label: 'متأخرة', value: l.counts['overdue'] ?? 0, color: Joy.danger),
            _Counter(label: 'منجزة', value: l.counts['done'] ?? 0, color: Joy.success),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(key: const Key('task-search'), onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث في المهام'))),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final (k, label) in [('open', 'المفتوحة'), ('', 'الكل'), ...taskStatuses.map((s) => (s.$1, s.$2))])
              Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(key: Key('task-filter-${k.isEmpty ? 'all' : k}'), label: Text(label), selected: status == k, onSelected: (_) => setState(() => status = k))),
          ])),
          const SizedBox(height: 12),
          if (items.isEmpty)
            EmptyState(icon: Icons.task_alt_rounded, title: 'لا مهام هنا', subtitle: view == 'mine' ? 'أنشئ مهمة لنفسك أو انتظر إسناداً من مديرك.' : 'لم تُسند مهام لفريقك بعد.')
          else
            for (final t in items) _TaskCard(task: t, onTap: () => _open(context, t.id), onStatus: (s) => _setStatus(context, t, s)),
          if (l.canAssign || l.canManage) ...[
            const SizedBox(height: 16),
            SectionTitle('أداء الفريق', action: summary ? 'إخفاء' : 'عرض', onAction: () => setState(() => summary = !summary)),
            if (summary) const _SummaryCard(),
          ],
        ]);
      },
    );
  }

  void _refresh() { ref.invalidate(adminTasksProvider); ref.invalidate(adminTasksSummaryProvider); }

  Future<void> _create(BuildContext context, TaskList l) async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => TaskEditorSheet(assignees: l.assignees, canAssign: l.canAssign || l.canManage));
    if (body == null || !context.mounted) return;
    try {
      final t = await ref.read(apiClientProvider).adminTaskCreate(body);
      _refresh();
      if (context.mounted) toast(context, t.assignee == null || t.mine ? 'أُنشئت المهمة' : 'أُسندت المهمة إلى ${t.assignee!.nickname}');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _setStatus(BuildContext context, WorkTask t, String s) async {
    try {
      await ref.read(apiClientProvider).adminTaskUpdate(t.id, {'status': s});
      _refresh();
      if (context.mounted) toast(context, 'المهمة الآن ${statusName(s)}');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _open(BuildContext context, String id) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => TaskDetailSheet(taskId: id));
    _refresh();
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Counter({super.key, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Joy.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text('$value', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16)), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 12))]),
      );
}

class _TaskCard extends StatelessWidget {
  final WorkTask task;
  final VoidCallback onTap;
  final ValueChanged<String> onStatus;
  const _TaskCard({required this.task, required this.onTap, required this.onStatus});
  @override
  Widget build(BuildContext context) {
    final t = task;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: JoyCard(
        key: Key('task-${t.id}'),
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, decoration: BoxDecoration(color: priorityColor(t.priority), borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(16)))),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.title, style: TextStyle(fontWeight: FontWeight.w700, decoration: t.done ? TextDecoration.lineThrough : null, color: t.done ? Joy.textMuted : null), maxLines: 2, overflow: TextOverflow.ellipsis)),
                _pill(statusName(t.status), statusColor(t.status)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (t.assignee != null) Row(mainAxisSize: MainAxisSize.min, children: [ProfileAvatar(person: t.assignee!, size: 20), const SizedBox(width: 4), Text(t.assignee!.nickname, style: const TextStyle(fontSize: 12))]) else const Text('بلا مسند', style: TextStyle(fontSize: 12, color: Joy.textMuted)),
                if (t.dueAt != null) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.schedule_rounded, size: 14, color: t.overdue ? Joy.danger : Joy.textMuted), const SizedBox(width: 3), Text(dueText(t.dueAt), style: TextStyle(fontSize: 12, color: t.overdue ? Joy.danger : Joy.textMuted, fontWeight: t.overdue ? FontWeight.w700 : null))]),
                Text(priorityName(t.priority), style: TextStyle(fontSize: 12, color: priorityColor(t.priority), fontWeight: FontWeight.w600)),
                if (t.checklist.isNotEmpty) Text('${t.checksDone}/${t.checklist.length} ✓', style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
                if (t.comments > 0) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.mode_comment_outlined, size: 14, color: Joy.textMuted), const SizedBox(width: 3), Text('${t.comments}', style: const TextStyle(fontSize: 12, color: Joy.textMuted))]),
              ]),
              if (t.canUpdateStatus && !t.done) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, children: [
                  if (t.status != 'doing') _quick('ابدأ', Icons.play_arrow_rounded, () => onStatus('doing'), key: Key('task-start-${t.id}')),
                  if (t.status == 'doing' && !t.mine) _quick('أنجزت', Icons.check_rounded, () => onStatus('done'), key: Key('task-done-${t.id}')),
                  if (t.status == 'doing' && t.mine) _quick('للمراجعة', Icons.rate_review_outlined, () => onStatus('review'), key: Key('task-review-${t.id}')),
                  if (t.status == 'review' && !t.mine) _quick('اعتماد', Icons.verified_outlined, () => onStatus('done'), key: Key('task-done-${t.id}')),
                ]),
              ),
            ]),
          )),
        ])),
      ),
    );
  }
}

Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));
Widget _quick(String label, IconData icon, VoidCallback onTap, {Key? key}) => ActionChip(key: key, avatar: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, onPressed: onTap);

/// ورقة إنشاء/تعديل مهمة.
class TaskEditorSheet extends StatefulWidget {
  final List<TaskAssignee> assignees;
  final bool canAssign;
  final WorkTask? task;
  const TaskEditorSheet({super.key, required this.assignees, required this.canAssign, this.task});
  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final title = TextEditingController(), desc = TextEditingController(), tags = TextEditingController(), checklist = TextEditingController(), dept = TextEditingController();
  String priority = 'normal';
  String? assigneeId;
  DateTime? due;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      title.text = t.title; desc.text = t.description; tags.text = t.tags.join('، '); checklist.text = t.checklist.map((c) => c.text).join('\n'); dept.text = t.department;
      priority = t.priority; assigneeId = t.assignee?.id; due = t.dueAt;
    } else if (widget.assignees.length == 1) {
      assigneeId = widget.assignees.first.id;
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 730)), initialDate: due ?? now, helpText: 'موعد التسليم');
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(due ?? DateTime(now.year, now.month, now.day, 17)), helpText: 'وقت التسليم');
    setState(() => due = DateTime(d.year, d.month, d.day, tm?.hour ?? 17, tm?.minute ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(editing ? 'تعديل المهمة' : 'مهمة جديدة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        TextField(key: const Key('task-title'), controller: title, autofocus: !editing, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'ماذا يجب إنجازه؟')),
        const SizedBox(height: 8),
        TextField(key: const Key('task-desc'), controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'التفاصيل (اختياري)')),
        const SizedBox(height: 8),
        if (widget.canAssign)
          DropdownButtonFormField<String?>(
            key: const Key('task-assignee'),
            initialValue: widget.assignees.any((a) => a.id == assigneeId) ? assigneeId : null,
            decoration: const InputDecoration(labelText: 'المسند إليه'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('بلا مسند الآن')), for (final a in widget.assignees) DropdownMenuItem<String?>(value: a.id, child: Text('${a.displayName}${a.title.isNotEmpty ? ' · ${a.title}' : a.roleName.isNotEmpty ? ' · ${a.roleName}' : ''}'))],
            onChanged: (v) => setState(() => assigneeId = v),
          )
        else
          const Text('تُسند المهمة إليك (الإسناد للآخرين يحتاج صلاحية إسناد)', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        const SizedBox(height: 10),
        const Text('الأولوية', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [for (final p in taskPriorities) ChoiceChip(key: Key('task-priority-${p.$1}'), label: Text(p.$2), selected: priority == p.$1, selectedColor: priorityColor(p.$1).withValues(alpha: .18), onSelected: (_) => setState(() => priority = p.$1))]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const Key('task-due'), onPressed: _pickDue, icon: const Icon(Icons.event_rounded, size: 18), label: Text(due == null ? 'موعد التسليم (اختياري)' : dueText(due)))),
          if (due != null) IconButton(tooltip: 'إزالة الموعد', onPressed: () => setState(() => due = null), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 8),
        TextField(key: const Key('task-checklist'), controller: checklist, maxLines: 4, decoration: const InputDecoration(labelText: 'قائمة التحقق (بند في كل سطر)', hintText: 'مراجعة الشكاوى\nالرد على العملاء')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(key: const Key('task-tags'), controller: tags, decoration: const InputDecoration(labelText: 'وسوم (بفاصلة)', hintText: 'بلاغات، دعم'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(key: const Key('task-dept'), controller: dept, decoration: const InputDecoration(labelText: 'القسم'))),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('task-save'),
          onPressed: () {
            if (title.text.trim().length < 2) { toast(context, 'اكتب عنواناً من حرفين على الأقل', error: true); return; }
            Navigator.pop(context, {
              'title': title.text.trim(), 'description': desc.text.trim(), 'priority': priority, 'dueAt': due?.toUtc().toIso8601String(),
              if (widget.canAssign) 'assigneeId': assigneeId,
              'tags': tags.text.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              'checklist': [for (final line in checklist.text.split('\n')) if (line.trim().isNotEmpty) {'text': line.trim(), 'done': widget.task?.checklist.any((c) => c.text == line.trim() && c.done) ?? false}],
              'department': dept.text.trim(),
            });
          },
          icon: Icon(editing ? Icons.save_outlined : Icons.add_task_rounded), label: Text(editing ? 'حفظ' : 'إنشاء المهمة'),
        ),
      ])),
    );
  }
}

/// تفاصيل مهمة: الوصف، قائمة التحقق، تغيير الحالة، التعديل، التعليقات، والسجل.
class TaskDetailSheet extends ConsumerStatefulWidget {
  final String taskId;
  const TaskDetailSheet({super.key, required this.taskId});
  @override
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet> {
  final comment = TextEditingController();
  bool busy = false, timeline = false;

  Future<void> _patch(Map<String, dynamic> body, {String? ok}) async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminTaskUpdate(widget.taskId, body);
      ref.invalidate(adminTaskProvider(widget.taskId));
      if (ok != null && mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() async {
    final text = comment.text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminTaskComment(widget.taskId, text);
      comment.clear();
      ref.invalidate(adminTaskProvider(widget.taskId));
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit(WorkTask t) async {
    final l = await ref.read(adminTasksProvider('mine|open').future).catchError((_) => const TaskList());
    if (!mounted) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => TaskEditorSheet(assignees: l.assignees, canAssign: l.canAssign || l.canManage, task: t));
    if (body == null) return;
    await _patch(body, ok: 'حُفظت المهمة');
  }

  Future<void> _delete(WorkTask t) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('حذف «${t.title}»؟'), content: const Text('تُحذف المهمة بتعليقاتها وسجلها.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(key: const Key('task-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))]));
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).adminTaskDelete(t.id);
      if (mounted) { toast(context, 'حُذفت المهمة'); Navigator.pop(context); }
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(adminTaskProvider(widget.taskId));
    final myId = ref.read(appStateProvider).user?.id;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: task.when(
        loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminTaskProvider(widget.taskId))),
        data: (t) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t.title, key: const Key('task-detail-title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            _pill(priorityName(t.priority), priorityColor(t.priority)),
            const SizedBox(width: 4),
            _pill(statusName(t.status), statusColor(t.status)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (t.assignee != null) Text('المسند إليه: ${t.assignee!.nickname}', style: const TextStyle(fontSize: 12.5, color: Joy.textMuted)),
            if (t.creator != null) Text('أسندها: ${t.creator!.nickname}', style: const TextStyle(fontSize: 12.5, color: Joy.textMuted)),
            if (t.dueAt != null) Text('الموعد: ${dueText(t.dueAt)}${t.overdue ? ' (متأخرة)' : ''}', style: TextStyle(fontSize: 12.5, color: t.overdue ? Joy.danger : Joy.textMuted, fontWeight: t.overdue ? FontWeight.w700 : null)),
            if (t.department.isNotEmpty) Text('القسم: ${t.department}', style: const TextStyle(fontSize: 12.5, color: Joy.textMuted)),
            for (final tag in t.tags) _pill('#$tag', Joy.textMuted),
          ]),
          if (t.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(t.description, style: const TextStyle(height: 1.6))),
          if (t.checklist.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('قائمة التحقق · ${t.checksDone}/${t.checklist.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            for (final (i, c) in t.checklist.indexed)
              CheckboxListTile(
                key: Key('task-check-$i'),
                dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                value: c.done,
                onChanged: t.canUpdateStatus && !busy ? (v) => _patch({'checklist': [for (final (j, x) in t.checklist.indexed) {'text': x.text, 'done': j == i ? v == true : x.done}]}) : null,
                title: Text(c.text, style: TextStyle(decoration: c.done ? TextDecoration.lineThrough : null, color: c.done ? Joy.textMuted : null)),
              ),
          ],
          if (t.canUpdateStatus) ...[
            const SizedBox(height: 10),
            const Text('الحالة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [for (final s in taskStatuses) ChoiceChip(key: Key('task-status-${s.$1}'), avatar: Icon(s.$3, size: 16), label: Text(s.$2), selected: t.status == s.$1, onSelected: busy || t.status == s.$1 ? null : (_) => _patch({'status': s.$1}, ok: 'المهمة الآن ${s.$2}'))]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (t.canEdit) TextButton.icon(key: const Key('task-edit'), onPressed: busy ? null : () => _edit(t), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل')),
            if (t.canEdit && (t.creator?.id == myId || t.canEdit)) TextButton.icon(key: const Key('task-delete'), onPressed: busy ? null : () => _delete(t), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger), label: const Text('حذف', style: TextStyle(color: Joy.danger))),
            const Spacer(),
            TextButton(onPressed: () => setState(() => timeline = !timeline), child: Text(timeline ? 'إخفاء السجل' : 'السجل (${t.events.length})')),
          ]),
          if (timeline)
            for (final e in t.events) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${e.user.nickname} · ${_eventText(e)} · ${timeAgo(e.createdAt)}', style: const TextStyle(fontSize: 12, color: Joy.textMuted))),
          const Divider(height: 20),
          Text('التعليقات (${t.commentList.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          for (final c in t.commentList)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ProfileAvatar(person: c.user, size: 28),
                const SizedBox(width: 8),
                Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(c.user.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), const Spacer(), Text(timeAgo(c.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11))]),
                  Text(c.text, style: const TextStyle(fontSize: 13.5, height: 1.5)),
                ]))),
              ]),
            ),
          Row(children: [
            Expanded(child: TextField(key: const Key('task-comment-field'), controller: comment, decoration: const InputDecoration(hintText: 'اكتب تعليقاً…', isDense: true), onSubmitted: (_) => _send())),
            IconButton(key: const Key('task-comment-send'), onPressed: busy ? null : _send, icon: const Icon(Icons.send_rounded, color: Joy.primary)),
          ]),
        ])),
      ),
    );
  }

  String _eventText(TaskEvent e) => switch (e.kind) {
        'created' => 'أنشأ المهمة',
        'status' => 'غيّر الحالة إلى ${statusName(e.data['to']?.toString() ?? '')}',
        'assigned' => e.data['to'] == null ? 'أزال الإسناد' : 'أسند المهمة',
        'comment' => 'علّق',
        'edited' => 'عدّل ${(e.data['fields'] as List? ?? const []).length} حقلاً',
        _ => e.kind,
      };
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminTasksSummaryProvider);
    return s.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminTasksSummaryProvider)),
      data: (rows) => JoyCard(padding: EdgeInsets.zero, child: Column(children: [
        for (final (i, r) in rows.indexed)
          ListRow(
            key: Key('task-summary-${r.member.id}'),
            leading: ProfileAvatar(person: r.member.person, size: 40),
            title: Text(r.member.displayName),
            subtitle: Text('${r.member.title.isNotEmpty ? r.member.title : r.member.roleName}${r.department.isNotEmpty ? ' · ${r.department}' : ''}', style: const TextStyle(fontSize: 12)),
            trailing: Wrap(spacing: 6, children: [_pill('${r.open} مفتوحة', Joy.primary), if (r.overdue > 0) _pill('${r.overdue} متأخرة', Joy.danger), if (r.review > 0) _pill('${r.review} للمراجعة', Joy.sunText), _pill('${r.done30} منجزة/30ي', Joy.success)]),
            divider: i < rows.length - 1,
          ),
      ])),
    );
  }
}
