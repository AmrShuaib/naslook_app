import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import 'dashboard_reviews_team.dart' show teamErrText, teamRoles;

/// مفاتيح عضو واحد في فريق الدائرة: دوره (قالب) ثم مفتاح لكل صلاحية. الحدود يفرضها الخادم والواجهة تعكسها:
/// لا أحد يعدّل مفاتيحه، ومن يدير الفريق أو يحمل صلاحية ليست عندي يعدّله المالك وحده، و«إدارة الفريق» يمنحها المالك وحده، ولا يمنح أحد ما لا يحمله.
class TeamMemberPage extends ConsumerStatefulWidget {
  final Biz biz;
  final BizStaff member;
  final BizTeam team;
  const TeamMemberPage({super.key, required this.biz, required this.member, required this.team});
  @override
  ConsumerState<TeamMemberPage> createState() => _TeamMemberPageState();
}

class _TeamMemberPageState extends ConsumerState<TeamMemberPage> {
  late String role = widget.member.role;
  late Set<String> on = {...widget.member.perms};
  bool busy = false;

  BizStaff get m => widget.member;
  BizTeam get t => widget.team;
  bool get _canEdit => t.boss || (t.myPerms ?? const []).contains('team');

  /// سبب قفل الصفحة كلها (null = قابلة للتعديل).
  String? get _pageLock => !_canEdit
      ? 'تعديل الفريق لمن يحمل «إدارة الفريق»'
      : switch (m.lock) { 'self' => 'لا يمكنك تعديل صلاحياتك بنفسك', 'team-holder' => 'هذا العضو يدير الفريق. يعدّله المالك فقط', 'outranked' => 'يحمل هذا العضو صلاحيات لا تحملها. يعدّله المالك', _ => null };

  /// سبب قفل مفتاح بعينه: تشغيل ما لا يحمله العضو منحٌ، فيلزم أن أحمله (وإدارة الفريق للمالك). ما يحمله أصلاً يُطفأ ويُعاد بلا قيد.
  String? _switchLock(String perm) {
    if (_pageLock != null) return _pageLock;
    if (m.can(perm)) return null;
    return t.grantBlock(perm);
  }

  bool get _dirty => role != m.role || on.length != m.perms.length || !on.containsAll(m.perms);

  void _setRole(String r) => setState(() {
        role = r;
        // تغيير الدور يعيد المفاتيح إلى قالبه (كما يفعل الخادم)، إلا ما لا أستطيع منحه فيبقى مطفأً
        on = {...t.startPerms(r)};
      });

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).updateBizStaff(widget.biz.id, m.user.id, role: role == m.role ? null : role, perms: {for (final (k, _) in bizPerms) k: on.contains(k)});
      ref.invalidate(bizTeamProvider(widget.biz.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'حُفظت الصلاحيات');
    } catch (e) {
      if (mounted) toast(context, teamErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('إزالة من الفريق'),
        content: Text('سيفقد ${m.user.nickname} كل صلاحياته في الدائرة.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(key: const Key('member-remove-ok'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إزالة'))],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).removeBizStaff(widget.biz.id, m.user.id);
      ref.invalidate(bizTeamProvider(widget.biz.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'أُزيل من الفريق');
    } catch (e) {
      if (mounted) toast(context, teamErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = _pageLock;
    final preset = bizRolePreset(role).toSet();
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('صلاحيات العضو')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        JoyCard(child: Row(children: [
          ProfileAvatar(person: m.user, size: 48),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.user.nickname.isEmpty ? m.user.id : m.user.nickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${m.roleLabel}${m.since == null ? '' : ' · منذ ${timeAgo(m.since)}'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
        ])),
        if (lock != null)
          Container(
            key: const Key('member-locked'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [const Icon(Icons.lock_outline_rounded, size: 18, color: Joy.textMuted), const SizedBox(width: 8), Expanded(child: Text(lock, style: const TextStyle(color: Joy.textMuted, fontSize: 13)))]),
          ),
        const SectionTitle('الدور'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (k, l) in teamRoles)
            ChoiceChip(
              key: Key('member-role-$k'),
              label: Text(l, style: TextStyle(color: role == k ? Joy.primaryOn : Joy.text)),
              selected: role == k, showCheckmark: false, selectedColor: Joy.primary,
              // دور لا أستطيع منح قالبه (كالمدير لغير المالك) لا يُختار
              onSelected: lock == null && (k == m.role || t.canGrantRole(k)) ? (_) => _setRole(k) : null,
            ),
        ]),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('الدور قالب. تغييره يعيد المفاتيح إلى قالبه، ثم عدّلها كما تريد.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5))),
        const SectionTitle('الصلاحيات'),
        JoyCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (k, label) in bizPerms)
              Builder(builder: (_) {
                final why = _switchLock(k);
                final changed = on.contains(k) != preset.contains(k);
                return SwitchListTile(
                  key: Key('perm-$k'),
                  dense: true,
                  activeTrackColor: Joy.primary,
                  title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: why != null && lock == null
                      ? Text(why, key: Key('perm-why-$k'), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))
                      : changed ? const Text('معدّل عن قالب الدور', style: TextStyle(color: Joy.accent, fontSize: 11.5)) : null,
                  value: on.contains(k),
                  onChanged: why != null || busy ? null : (v) => setState(() => v ? on.add(k) : on.remove(k)),
                );
              }),
          ]),
        ),
        const SizedBox(height: 16),
        if (lock == null) ...[
          FilledButton(key: const Key('member-save'), onPressed: busy || !_dirty ? null : _save, child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ')),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('member-remove'), onPressed: busy ? null : _remove, icon: const Icon(Icons.person_remove_outlined, size: 18, color: Joy.danger), label: const Text('إزالة من الفريق', style: TextStyle(color: Joy.danger))),
        ],
      ]),
    );
  }
}
