import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import 'admin_shell.dart';

/// أسماء مجموعات الصلاحيات.
const permissionGroups = {
  'overview': 'النظرة العامة', 'users': 'المستخدمون', 'reports': 'البلاغات', 'biz': 'الدوائر التجارية', 'finance': 'المالية', 'content': 'المحتوى',
  'blog': 'المدونة', 'mail': 'البريد', 'settings': 'الإعدادات', 'audit': 'سجل الإجراءات', 'team': 'الفريق', 'tasks': 'المهام', 'inbox': 'البريد الوارد',
};

Color roleColor(int level) => level >= 90 ? Joy.primary : level >= 60 ? Joy.sunText : level >= 40 ? Joy.accent : Joy.textMuted;

/// قسم الفريق: الأعضاء وأدوارهم ومديروهم، الأدوار وصلاحياتها، والهيكل الإداري.
class AdminTeamPage extends ConsumerStatefulWidget {
  const AdminTeamPage({super.key});
  @override
  ConsumerState<AdminTeamPage> createState() => _AdminTeamPageState();
}

class _AdminTeamPageState extends ConsumerState<AdminTeamPage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(adminTeamProvider);
    return team.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminTeamProvider)),
      data: (t) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        _MeCard(t: t),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('الأعضاء'), icon: Icon(Icons.people_alt_outlined)),
            ButtonSegment(value: 1, label: Text('الأدوار'), icon: Icon(Icons.admin_panel_settings_outlined)),
            ButtonSegment(value: 2, label: Text('الهيكل'), icon: Icon(Icons.account_tree_outlined)),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
        ),
        const SizedBox(height: 14),
        if (tab == 0) _MembersTab(t: t) else if (tab == 1) _RolesTab(t: t) else const _TreeTab(),
      ]),
    );
  }
}

class _MeCard extends StatelessWidget {
  final TeamInfo t;
  const _MeCard({required this.t});
  @override
  Widget build(BuildContext context) {
    final me = t.me;
    final active = t.members.where((m) => m.active).length;
    return JoyCard(
      color: Joy.primarySoft,
      child: Row(children: [
        const Icon(Icons.groups_rounded, color: Joy.primary, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('فريق العمل · $active ${active == 1 ? 'عضو' : 'أعضاء'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('دورك: ${me.roleName ?? '—'} · ${me.owner ? 'ترى كل الأعضاء' : 'نطاقك ${me.scopeIds.length} ${me.scopeIds.length == 1 ? 'عضو' : 'أعضاء'} (أنت ومن تحتك)'}', key: const Key('team-me'), style: const TextStyle(fontSize: 12.5, height: 1.5)),
        ])),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------- الأعضاء
class _MembersTab extends ConsumerWidget {
  final TeamInfo t;
  const _MembersTab({required this.t});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = t.me.can('team.manage');
    final members = [...t.members]..sort((a, b) => b.level != a.level ? b.level.compareTo(a.level) : a.displayName.compareTo(b.displayName));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionTitle('الأعضاء')),
        if (canManage) FilledButton.icon(key: const Key('team-add'), onPressed: () => _addMember(context, ref, t), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة عضو')),
      ]),
      JoyCard(padding: EdgeInsets.zero, child: Column(children: [
        if (members.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا أعضاء بعد', style: TextStyle(color: Joy.textMuted))),
        for (final (i, m) in members.indexed)
          ListRow(
            key: Key('team-member-${m.id}'),
            leading: Opacity(opacity: m.active ? 1 : .45, child: ProfileAvatar(person: m.user, size: 44)),
            title: Row(children: [
              Flexible(child: Text(m.displayName, overflow: TextOverflow.ellipsis, style: TextStyle(color: m.active ? null : Joy.textMuted))),
              const SizedBox(width: 6),
              _chip(m.roleName, roleColor(m.level)),
              if (!m.active) _chip('موقوف', Joy.danger),
            ]),
            subtitle: Text([if (m.title.isNotEmpty) m.title, if (m.department.isNotEmpty) m.department, if (m.managerName.isNotEmpty) 'المدير: ${m.managerName}', if (m.mailbox.isNotEmpty) '${m.mailbox}@'].join(' · '), style: const TextStyle(fontSize: 12)),
            trailing: canManage && (t.me.owner || m.level < t.me.level || m.id == _myId(ref)) ? const Icon(Icons.edit_outlined, color: Joy.textMuted, size: 18) : null,
            onTap: canManage ? () => _editMember(context, ref, t, m) : null,
            divider: i < members.length - 1,
          ),
      ])),
    ]);
  }

  static String? _myId(WidgetRef ref) => ref.read(appStateProvider).user?.id;
}

Widget _chip(String text, Color color) => Container(margin: const EdgeInsetsDirectional.only(start: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));

/// الأدوار التي يستطيع الفاعل منحها: أقل من مستواه (المالك يمنح الكل).
List<TeamRole> _grantable(TeamInfo t) => t.roles.where((r) => t.me.owner || r.level < t.me.level).toList();

Future<void> _addMember(BuildContext context, WidgetRef ref, TeamInfo t) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => _MemberSheet(t: t));
  if (result == null || !context.mounted) return;
  try {
    final m = await ref.read(apiClientProvider).adminTeamAdd(result);
    ref.invalidate(adminTeamProvider);
    ref.invalidate(adminTeamTreeProvider);
    if (context.mounted) toast(context, 'أُضيف ${m.displayName} بدور ${m.roleName}');
  } catch (e) {
    if (context.mounted) toast(context, adminErrText(e), error: true);
  }
}

Future<void> _editMember(BuildContext context, WidgetRef ref, TeamInfo t, TeamMember m) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => _MemberSheet(t: t, member: m));
  if (result == null || !context.mounted) return;
  final api = ref.read(apiClientProvider);
  try {
    if (result['remove'] == true) {
      await api.adminTeamRemove(m.id);
      if (context.mounted) toast(context, 'أُزيل ${m.displayName} من الفريق');
    } else {
      await api.adminTeamUpdate(m.id, result);
      if (context.mounted) toast(context, 'حُفظت بيانات ${m.displayName}');
    }
    ref.invalidate(adminTeamProvider);
    ref.invalidate(adminTeamTreeProvider);
    ref.invalidate(adminStatusProvider);
  } catch (e) {
    if (context.mounted) toast(context, adminErrText(e), error: true);
  }
}

/// ورقة إضافة/تعديل عضو: بحث عن مستخدم (للإضافة)، الدور، المسمى، القسم، المدير المباشر، الصندوق، الحالة.
class _MemberSheet extends ConsumerStatefulWidget {
  final TeamInfo t;
  final TeamMember? member;
  const _MemberSheet({required this.t, this.member});
  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  final search = TextEditingController(), title = TextEditingController(), dept = TextEditingController(), mailbox = TextEditingController();
  List<TeamCandidate> results = const [];
  TeamCandidate? picked;
  String? roleId;
  String? managerId;
  bool active = true, searching = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    final grantable = _grantable(widget.t);
    if (m != null) {
      roleId = m.roleId; title.text = m.title; dept.text = m.department; mailbox.text = m.mailbox; managerId = m.managerId; active = m.active;
    } else {
      roleId = grantable.any((r) => r.id == 'support') ? 'support' : (grantable.isNotEmpty ? grantable.last.id : null);
      managerId = widget.t.me.owner ? null : ref.read(appStateProvider).user?.id;
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) { setState(() => results = const []); return; }
    setState(() => searching = true);
    try {
      final r = await ref.read(apiClientProvider).adminTeamSearch(q);
      if (mounted) setState(() => results = r);
    } catch (_) {
      if (mounted) setState(() => results = const []);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final m = widget.member;
    final editing = m != null;
    final roles = editing && !_grantable(t).any((r) => r.id == roleId) ? t.roles : _grantable(t);
    final managers = t.members.where((x) => x.active && x.id != m?.id).toList();
    final myId = ref.read(appStateProvider).user?.id;
    final selfEdit = editing && m.id == myId;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(editing ? 'تعديل ${m.displayName}' : 'إضافة عضو إلى الفريق', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        if (!editing) ...[
          if (picked == null) ...[
            TextField(key: const Key('team-search'), controller: search, autofocus: true, onChanged: _search, decoration: InputDecoration(labelText: 'ابحث بالنك نيم أو المعرّف', suffixIcon: searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.search_rounded))),
            const SizedBox(height: 6),
            for (final c in results)
              ListTile(key: Key('team-pick-${c.id}'), contentPadding: EdgeInsets.zero, leading: ProfileAvatar(person: c.person, size: 36), title: Text(c.nickname.isEmpty ? c.id : c.nickname), subtitle: Text(c.id, style: const TextStyle(fontSize: 11)), trailing: c.member ? _chip('عضو', Joy.textMuted) : null, enabled: !c.member, onTap: c.member ? null : () => setState(() => picked = c)),
            if (search.text.trim().length >= 2 && results.isEmpty && !searching) const Padding(padding: EdgeInsets.all(8), child: Text('لا نتائج', style: TextStyle(color: Joy.textMuted))),
          ] else
            ListTile(contentPadding: EdgeInsets.zero, leading: ProfileAvatar(person: picked!.person, size: 40), title: Text(picked!.nickname.isEmpty ? picked!.id : picked!.nickname), subtitle: Text(picked!.id), trailing: TextButton(onPressed: () => setState(() => picked = null), child: const Text('تغيير'))),
          const Divider(),
        ],
        if (editing || picked != null) ...[
          DropdownButtonFormField<String>(
            key: const Key('team-role'),
            initialValue: roles.any((r) => r.id == roleId) ? roleId : null,
            decoration: const InputDecoration(labelText: 'الدور'),
            items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text('${r.name} · مستوى ${r.level}'))],
            onChanged: selfEdit && !t.me.owner ? null : (v) => setState(() => roleId = v),
          ),
          const SizedBox(height: 8),
          TextField(key: const Key('team-title'), controller: title, decoration: const InputDecoration(labelText: 'المسمى الوظيفي', hintText: 'مثال: مسؤول دعم العملاء')),
          const SizedBox(height: 8),
          TextField(key: const Key('team-dept'), controller: dept, decoration: InputDecoration(labelText: 'القسم', hintText: t.departments.isEmpty ? 'مثال: العمليات' : t.departments.join('، '))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('team-manager'),
            initialValue: managers.any((x) => x.id == managerId) ? managerId : null,
            decoration: const InputDecoration(labelText: 'المدير المباشر'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('بلا مدير (أعلى الهيكل)')), for (final x in managers) DropdownMenuItem<String?>(value: x.id, child: Text('${x.displayName} · ${x.roleName}'))],
            onChanged: (v) => setState(() => managerId = v),
          ),
          const SizedBox(height: 8),
          TextField(key: const Key('team-mailbox'), controller: mailbox, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'صندوق البريد (قبل @)', hintText: 'sara', helperText: 'يُستخدم في البريد الوارد: الاسم@naslife.app')),
          if (editing && !selfEdit) SwitchListTile(key: const Key('team-active'), contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v), title: const Text('عضو نشط'), subtitle: const Text('الموقوف يفقد دخول اللوحة فوراً ويبقى في السجل', style: TextStyle(fontSize: 12))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: const Key('team-save'),
              onPressed: roleId == null ? null : () => Navigator.pop(context, {
                if (!editing) 'userId': picked!.id,
                'roleId': roleId, 'title': title.text.trim(), 'department': dept.text.trim(), 'managerId': managerId, 'mailbox': mailbox.text.trim().toLowerCase(),
                if (editing) 'active': active,
              }),
              icon: Icon(editing ? Icons.save_outlined : Icons.person_add_alt_1_rounded), label: Text(editing ? 'حفظ' : 'إضافة إلى الفريق'),
            )),
            if (editing && !selfEdit) ...[
              const SizedBox(width: 8),
              TextButton.icon(key: const Key('team-remove'), onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('إزالة ${m.displayName} من الفريق؟'), content: const Text('يفقد دخول اللوحة، ويُنقل من تحته إلى مديره.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(key: const Key('team-remove-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إزالة'))]));
                if (ok == true && context.mounted) Navigator.pop(context, {'remove': true});
              }, icon: const Icon(Icons.person_remove_outlined, color: Joy.danger, size: 18), label: const Text('إزالة', style: TextStyle(color: Joy.danger))),
            ],
          ]),
        ],
      ])),
    );
  }
}

// ---------------------------------------------------------------------------- الأدوار
class _RolesTab extends ConsumerWidget {
  final TeamInfo t;
  const _RolesTab({required this.t});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = t.me.can('team.manage');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionTitle('الأدوار والصلاحيات')),
        if (canManage) FilledButton.tonalIcon(key: const Key('role-new'), onPressed: () => _roleSheet(context, ref, t, null), icon: const Icon(Icons.add_rounded), label: const Text('دور جديد')),
      ]),
      const Text('كل عضو يرى في اللوحة الأقسام التي يسمح بها دوره فقط. الأدوار المدمجة ثابتة الصلاحيات، ويمكن إنشاء أدوار مخصصة بمستوى أقل من مستواك.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
      const SizedBox(height: 8),
      JoyCard(padding: EdgeInsets.zero, child: Column(children: [
        for (final (i, r) in t.roles.indexed)
          ListRow(
            key: Key('role-${r.id}'),
            leading: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: roleColor(r.level).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Text('${r.level}', style: TextStyle(color: roleColor(r.level), fontWeight: FontWeight.w800))),
            title: Row(children: [Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis)), if (r.builtin) _chip('مدمج', Joy.textMuted) else _chip('مخصص', Joy.primary)]),
            subtitle: Text('${r.all ? 'كل الصلاحيات' : '${r.permissions.length} صلاحية'} · ${r.members} ${r.members == 1 ? 'عضو' : 'أعضاء'}${r.description.isNotEmpty ? '\n${r.description}' : ''}', style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
            onTap: () => _roleSheet(context, ref, t, r),
            divider: i < t.roles.length - 1,
          ),
      ])),
    ]);
  }
}

Future<void> _roleSheet(BuildContext context, WidgetRef ref, TeamInfo t, TeamRole? role) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => _RoleSheet(t: t, role: role));
  if (result == null || !context.mounted) return;
  final api = ref.read(apiClientProvider);
  try {
    if (result['delete'] == true) { await api.adminRoleDelete(role!.id); if (context.mounted) toast(context, 'حُذف الدور'); }
    else if (role == null) { final r = await api.adminRoleCreate(result); if (context.mounted) toast(context, 'أُنشئ الدور ${r.name}'); }
    else { await api.adminRoleUpdate(role.id, result); if (context.mounted) toast(context, 'حُفظ الدور'); }
    ref.invalidate(adminTeamProvider);
  } catch (e) {
    if (context.mounted) toast(context, adminErrText(e), error: true);
  }
}

/// ورقة دور: عرض الصلاحيات، وللأدوار المخصصة تعديل الاسم والمستوى ومصفوفة الصلاحيات.
class _RoleSheet extends ConsumerStatefulWidget {
  final TeamInfo t;
  final TeamRole? role;
  const _RoleSheet({required this.t, this.role});
  @override
  ConsumerState<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends ConsumerState<_RoleSheet> {
  final name = TextEditingController(), desc = TextEditingController();
  late int level = widget.role?.level ?? 30;
  late final Set<String> perms = {...widget.role?.permissions ?? const []};

  @override
  void initState() {
    super.initState();
    name.text = widget.role?.name ?? '';
    desc.text = widget.role?.description ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final r = widget.role;
    final editable = t.me.can('team.manage') && (r == null || !r.builtin) && (t.me.owner || (r == null ? true : r.level < t.me.level));
    final catalogue = ref.watch(adminTeamPermissionsProvider);
    final maxLevel = t.me.owner ? 99 : (t.me.level - 1).clamp(1, 99);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r == null ? 'دور جديد' : r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (r != null && r.builtin) const Padding(padding: EdgeInsets.only(top: 4), child: Text('دور مدمج: الصلاحيات ثابتة', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        const SizedBox(height: 12),
        if (editable) ...[
          TextField(key: const Key('role-name'), controller: name, decoration: const InputDecoration(labelText: 'اسم الدور', hintText: 'مثال: مراجع مالي')),
          const SizedBox(height: 8),
          TextField(key: const Key('role-desc'), controller: desc, decoration: const InputDecoration(labelText: 'وصف مختصر')),
          const SizedBox(height: 8),
          Row(children: [
            const Text('المستوى', style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(child: Slider(key: const Key('role-level'), value: level.clamp(1, maxLevel).toDouble(), min: 1, max: maxLevel.toDouble(), divisions: maxLevel - 1 > 0 ? maxLevel - 1 : 1, label: '$level', onChanged: (v) => setState(() => level = v.round()))),
            SizedBox(width: 36, child: Text('$level', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const Text('الأعلى مستوى يدير الأدنى منه فقط', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        catalogue.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(e.toString(), style: const TextStyle(color: Joy.danger)),
          data: (list) {
            final groups = <String, List<TeamPermission>>{};
            for (final p in list) {
              groups.putIfAbsent(p.group, () => []).add(p);
            }
            final all = r?.all == true;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final g in groups.entries) ...[
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(permissionGroups[g.key] ?? g.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in g.value)
                    FilterChip(
                      key: Key('perm-${p.key}'),
                      label: Text(p.label, style: const TextStyle(fontSize: 12)),
                      selected: all || perms.contains(p.key),
                      onSelected: editable && (t.me.owner || t.me.permissions.contains(p.key)) ? (v) => setState(() => v ? perms.add(p.key) : perms.remove(p.key)) : null,
                    ),
                ]),
              ],
            ]);
          },
        ),
        const SizedBox(height: 14),
        if (editable)
          Row(children: [
            Expanded(child: FilledButton.icon(key: const Key('role-save'), onPressed: name.text.trim().isEmpty && r == null ? null : () => Navigator.pop(context, {'name': name.text.trim(), 'description': desc.text.trim(), 'level': level, 'permissions': perms.toList()}), icon: const Icon(Icons.save_outlined), label: Text(r == null ? 'إنشاء الدور' : 'حفظ'))),
            if (r != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(key: const Key('role-delete'), onPressed: r.members > 0 ? null : () => Navigator.pop(context, {'delete': true}), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger, size: 18), label: const Text('حذف', style: TextStyle(color: Joy.danger))),
            ],
          ]),
      ])),
    );
  }
}

// ---------------------------------------------------------------------------- الهيكل
class _TreeTab extends ConsumerWidget {
  const _TreeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(adminTeamTreeProvider);
    return tree.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminTeamTreeProvider)),
      data: (roots) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('الهيكل الإداري'),
        const Text('كل عضو تحت مديره المباشر. المدير يرى مهام وبريد من تحته ويسند إليهم المهام.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 8),
        JoyCard(child: roots.isEmpty ? const Text('لا أعضاء بعد', style: TextStyle(color: Joy.textMuted)) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final n in roots) _TreeNode(node: n)])),
      ]),
    );
  }
}

class _TreeNode extends StatelessWidget {
  final TeamNode node;
  const _TreeNode({required this.node});
  @override
  Widget build(BuildContext context) {
    final m = node.member;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: node.depth * 22.0, top: 4, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(key: Key('tree-${m.id}'), children: [
          if (node.depth > 0) const Icon(Icons.subdirectory_arrow_left_rounded, size: 16, color: Joy.textMuted),
          ProfileAvatar(person: m.user, size: 32),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), _chip(m.roleName, roleColor(m.level))]),
            if (m.title.isNotEmpty || m.department.isNotEmpty) Text([if (m.title.isNotEmpty) m.title, if (m.department.isNotEmpty) m.department].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ])),
          if (node.reports.isNotEmpty) Text('${node.reports.length}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ]),
        for (final c in node.reports) _TreeNode(node: c),
      ]),
    );
  }
}
