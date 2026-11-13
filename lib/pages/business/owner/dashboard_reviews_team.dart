import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/client.dart' show ApiException;
import '../../../api/naslife_api.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show Stars;
import 'biz_activity_page.dart';
import 'business_editor.dart';
import 'team_member_page.dart';

/// التقييمات مع إمكانية الرد باسم الدائرة.
class ReviewsTab extends ConsumerWidget {
  final Biz biz;
  const ReviewsTab({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = biz.reviews;
    final unanswered = reviews.where((r) => r.reply == null).length;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      JoyCard(child: Row(children: [
        Column(children: [
          Text(biz.rating == null ? '—' : biz.rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 32, color: Joy.primary)),
          Stars(rating: biz.rating, count: biz.ratingCount),
        ]),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var s = 5; s >= 1; s--)
            Row(children: [
              SizedBox(width: 14, child: Text('$s', style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
              const Icon(Icons.star_rounded, size: 12, color: Joy.warning),
              const SizedBox(width: 6),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: reviews.isEmpty ? 0 : reviews.where((r) => r.rating == s).length / reviews.length, minHeight: 6, backgroundColor: Joy.surface2, color: Joy.primary))),
              const SizedBox(width: 6),
              SizedBox(width: 18, child: Text('${reviews.where((r) => r.rating == s).length}', style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
            ]),
        ])),
      ])),
      if (unanswered > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$unanswered تقييم بلا رد؛ الرد السريع يرفع ثقة العملاء.', style: const TextStyle(color: Joy.accent, fontSize: 12.5, fontWeight: FontWeight.w600))),
      const SizedBox(height: 12),
      if (reviews.isEmpty) const EmptyState(icon: Icons.star_outline_rounded, title: 'لا تقييمات بعد'),
      for (final r in reviews) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ReviewCard(biz: biz, r: r)),
    ]);
  }
}

class _ReviewCard extends ConsumerWidget {
  final Biz biz;
  final BizReview r;
  const _ReviewCard({required this.biz, required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) => JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProfileAvatar(person: r.user, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.user.nickname.isEmpty ? 'مستخدم' : r.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
              Row(children: [for (var s = 1; s <= 5; s++) Icon(s <= r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 14, color: Joy.warning), const SizedBox(width: 6), Text(timeAgo(r.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]),
            ])),
          ]),
          if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.text, style: const TextStyle(height: 1.5))),
          const SizedBox(height: 8),
          if (r.reply != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.storefront_rounded, size: 14, color: Joy.primary), const SizedBox(width: 4), Text('رد ${biz.title}', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12)), const Spacer(), Text(timeAgo(r.replyAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11))]),
                const SizedBox(height: 4),
                Text(r.reply!, style: const TextStyle(fontSize: 13.5, height: 1.5)),
              ]),
            ),
          if (biz.can('reviews'))
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () async {
                  final text = await askText(context, title: 'الرد على ${r.user.nickname}', hint: 'شكراً لتقييمك…', confirm: 'نشر الرد', initial: r.reply);
                  if (text == null) return;
                  try {
                    await ref.read(apiClientProvider).replyBizReview(biz.id, r.user.id, text.trim());
                    invalidateBizAll(ref, biz.id);
                  } catch (e) { if (context.mounted) toast(context, ownerErrText(e), error: true); }
                },
                icon: Icon(r.reply == null ? Icons.reply_rounded : Icons.edit_outlined, size: 18),
                label: Text(r.reply == null ? 'رد' : 'تعديل الرد'),
              ),
            ),
        ]),
      );
}

/// أدوار الفريق القابلة للإسناد، وكل دور قالب صلاحيات يعدّل المالك مفاتيحه لكل عضو.
const teamRoles = [('staff', 'موظف'), ('manager', 'مدير'), ('hr', 'توظيف')];

/// نص خطأ إدارة الفريق: حدود الخادم (docs/circle-permissions.md) بعبارة قصيرة.
String teamErrText(Object e) {
  final body = e is ApiException ? e.body : null;
  switch (body?['error']?.toString()) {
    case 'self': return 'لا يمكنك تعديل صلاحياتك بنفسك';
    case 'team-holder': return 'هذا العضو يدير الفريق. يعدّله المالك فقط';
    case 'outranked': return 'يحمل هذا العضو صلاحيات لا تحملها. يعدّله المالك';
    case 'owner-only': return '«إدارة الفريق» ودور المدير يمنحهما المالك فقط';
    case 'not-held': return 'لا تمنح صلاحية لا تحملها: ${bizPermLabel(body?['perm']?.toString() ?? '')}';
    case 'too-many': return 'وصل الفريق إلى الحد الأقصى';
    case 'not-member': return 'لم يعد هذا العضو في الفريق';
  }
  return ownerErrText(e);
}

/// الفريق: المالك ثم الأعضاء بقوالب أدوارهم، والضغط على عضو يفتح مفاتيحه. المالك ومن يحمل «إدارة الفريق» يضيفون الأعضاء،
/// ومن هنا سجل النشاط ونقل الملكية (للمالك وحده).
class TeamTab extends ConsumerWidget {
  final Biz biz;
  const TeamTab({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(bizTeamProvider(biz.id));
    return team.when(
      data: (t0) {
        // خادم أقدم لا يرسل «me»: المالك وحده يدير الفريق كما كان
        final t = t0.myRole == null ? BizTeam(owner: t0.owner, staff: t0.staff, myRole: biz.myRole, myPerms: biz.perms, boss: biz.isOwner, limit: t0.limit) : t0;
        final canEdit = t.boss || (t.myPerms ?? const []).contains('team');
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('الأدوار والصلاحيات', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(
              'الدور قالب جاهز، وتحته مفتاح لكل صلاحية تشغّله أو تطفئه لكل عضو.\n'
              'المالك: كل شيء، ومنه نقل الملكية.\n'
              'المدير: كل الصلاحيات، ويضيف الأعضاء.\n'
              'الموظف: الطلبات والاستلام، رسائل العملاء، والإحصاءات.\n'
              'التوظيف: الوظائف والمرشحون فقط.\n'
              'اضغط على العضو لتعديل مفاتيحه.',
              key: Key('team-roles-help'),
              style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6),
            ),
          ])),
          const SectionTitle('المالك'),
          if (t.owner != null)
            JoyCard(child: Row(children: [ProfileAvatar(person: t.owner!, size: 44), const SizedBox(width: 10), Expanded(child: Text(t.owner!.nickname, style: const TextStyle(fontWeight: FontWeight.w700))), const Text('مالك', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w600, fontSize: 12.5))]))
          else
            const JoyCard(child: Text('لا مالك بعد (دائرة تعريفية من Naslife)', style: TextStyle(color: Joy.textMuted))),
          SectionTitle('الفريق · ${t.staff.length}', action: canEdit ? 'إضافة' : null, onAction: canEdit ? () => _add(context, ref, t) : null),
          if (t.staff.isEmpty) const EmptyState(icon: Icons.group_add_outlined, title: 'لا أعضاء بعد', subtitle: 'أضف مديراً يساعدك في الإدارة أو موظفاً يؤكد الاستلام عند الباب.'),
          for (final s in t.staff)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: Key('team-member-${s.user.id}'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamMemberPage(biz: biz, member: s, team: t))),
                child: JoyCard(child: Row(children: [
                  ProfileAvatar(person: s.user, size: 44),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${s.roleLabel} · منذ ${timeAgo(s.since)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    Text('${s.perms.length} من ${bizPerms.length} صلاحية${s.custom ? ' · معدّلة عن القالب' : ''}', key: Key('team-member-perms-${s.user.id}'), style: TextStyle(color: s.custom ? Joy.accent : Joy.textMuted, fontSize: 11.5)),
                  ])),
                  Icon(s.lock == null && canEdit ? Icons.tune_rounded : Icons.lock_outline_rounded, size: 18, color: Joy.textMuted),
                ])),
              ),
            ),
          const SizedBox(height: 4),
          if (canEdit) FilledButton.icon(key: const Key('team-add'), onPressed: () => _add(context, ref, t), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('إضافة عضو')),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('team-activity'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizActivityPage(bizId: biz.id))), icon: const Icon(Icons.history_rounded, size: 18), label: const Text('سجل النشاط')),
          if (biz.myRole == 'owner') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _transfer(context, ref), icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: const Text('نقل ملكية الدائرة')),
          ],
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizTeamProvider(biz.id))),
    );
  }

  Future<String?> _resolveUser(BuildContext context, WidgetRef ref, String handle) async {
    final h = handle.trim();
    if (h.isEmpty) return null;
    if (RegExp(r'^[A-Z]{2}\d{7}$').hasMatch(h.toUpperCase())) return h.toUpperCase();
    try {
      return (await ref.read(apiClientProvider).userByHandle(h.toLowerCase())).id;
    } catch (_) {
      if (context.mounted) toast(context, 'لم نجد مستخدماً بهذا الاسم', error: true);
      return null;
    }
  }

  /// إضافة عضو: الاسم ثم الدور. دور المدير لغير المالك معطّل، وما في قالب الدور من صلاحية لا أحملها يُرسل مطفأً
  /// (مدير أُطفئت له «الإحصاءات» يضيف موظفاً بلا الإحصاءات بدل أن تُرفض الإضافة).
  Future<void> _add(BuildContext context, WidgetRef ref, BizTeam t) async {
    final handle = TextEditingController();
    var role = teamRoles.map((r) => r.$1).firstWhere(t.canGrantRole, orElse: () => 'staff');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إضافة عضو'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const Key('team-add-handle'), controller: handle, autofocus: true, decoration: const InputDecoration(labelText: 'النك نيم أو المعرّف (SA…)')),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (k, l) in teamRoles)
                ChoiceChip(
                  key: Key('team-add-role-$k'),
                  label: Text(l, style: TextStyle(color: role == k ? Joy.primaryOn : (t.canGrantRole(k) ? Joy.text : Joy.textMuted))),
                  selected: role == k, showCheckmark: false, selectedColor: Joy.primary,
                  onSelected: t.canGrantRole(k) ? (_) => setS(() => role = k) : null,
                ),
            ]),
            const SizedBox(height: 8),
            Text('يبدأ بصلاحيات: ${t.startPerms(role).map(bizPermLabel).join('، ')}', key: const Key('team-add-start'), style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
            if (t.startPerms(role).length < bizRolePreset(role).length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('بلا: ${bizRolePreset(role).where((p) => !t.startPerms(role).contains(p)).map(bizPermLabel).join('، ')}. لا تحملها أنت، ويشغّلها المالك.', key: const Key('team-add-dropped'), style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
              ),
            if (!t.boss) const Padding(padding: EdgeInsets.only(top: 6), child: Text('دور المدير يمنحه المالك فقط، ولا تمنح صلاحية لا تحملها.', key: Key('team-add-limit'), style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('team-add-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة'))],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final id = await _resolveUser(context, ref, handle.text);
    if (id == null) return;
    try {
      final start = t.startPerms(role);
      final off = {for (final p in bizRolePreset(role)) if (!start.contains(p)) p: false};
      await ref.read(apiClientProvider).addBizStaff(biz.id, id, role: role, perms: off.isEmpty ? null : off);
      ref.invalidate(bizTeamProvider(biz.id));
      if (context.mounted) toast(context, 'أُضيف إلى الفريق. اضغط عليه لتعديل مفاتيحه');
    } catch (e) {
      if (context.mounted) toast(context, teamErrText(e), error: true);
    }
  }

  Future<void> _transfer(BuildContext context, WidgetRef ref) async {
    final handle = await askText(context, title: 'نقل الملكية', hint: 'النك نيم أو المعرّف للمالك الجديد', confirm: 'متابعة', maxLines: 1);
    if (handle == null || !context.mounted) return;
    final id = await _resolveUser(context, ref, handle);
    if (id == null || !context.mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('تأكيد نقل الملكية'), content: Text('ستصبح مديراً في الدائرة ويصبح $id مالكها. لا يمكن التراجع إلا بموافقة المالك الجديد.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('نقل الملكية'))]));
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).transferBiz(biz.id, id);
      invalidateBizAll(ref, biz.id);
      if (context.mounted) toast(context, 'نُقلت الملكية');
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }
}
