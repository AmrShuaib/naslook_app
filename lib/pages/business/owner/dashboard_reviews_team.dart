import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/naslife_api.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show Stars;
import 'business_editor.dart';

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
          if (biz.canManage)
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

/// الفريق: المالك والمديرون والموظفون، الإضافة بالنك نيم أو المعرّف، ونقل الملكية.
class TeamTab extends ConsumerWidget {
  final Biz biz;
  const TeamTab({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(bizTeamProvider(biz.id));
    return team.when(
      data: (t) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الصلاحيات', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('المالك: كل شيء بما فيه الفريق ونقل الملكية.\nالمدير: الملف والكتالوج والمنشورات والطلبات والردود.\nالموظف: عرض الطلبات وتأكيد الاستلام فقط.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
        ])),
        const SectionTitle('المالك'),
        if (t.owner != null)
          JoyCard(child: Row(children: [ProfileAvatar(person: t.owner!, size: 44), const SizedBox(width: 10), Expanded(child: Text(t.owner!.nickname, style: const TextStyle(fontWeight: FontWeight.w700))), const Text('مالك', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w600, fontSize: 12.5))]))
        else
          const JoyCard(child: Text('لا مالك بعد (دائرة تعريفية من Naslife)', style: TextStyle(color: Joy.textMuted))),
        SectionTitle('الفريق · ${t.staff.length}', action: biz.isOwner ? 'إضافة' : null, onAction: biz.isOwner ? () => _add(context, ref) : null),
        if (t.staff.isEmpty) const EmptyState(icon: Icons.group_add_outlined, title: 'لا أعضاء بعد', subtitle: 'أضف مديراً يساعدك في الإدارة أو موظفاً يؤكد الاستلام عند الباب.'),
        for (final s in t.staff)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: JoyCard(child: Row(children: [
              ProfileAvatar(person: s.user, size: 44),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${s.roleLabel} · منذ ${timeAgo(s.since)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12))])),
              if (biz.isOwner)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    try {
                      final api = ref.read(apiClientProvider);
                      if (v == 'remove') {
                        await api.removeBizStaff(biz.id, s.user.id);
                      } else {
                        await api.addBizStaff(biz.id, s.user.id, role: v);
                      }
                      ref.invalidate(bizTeamProvider(biz.id));
                    } catch (e) { if (context.mounted) toast(context, ownerErrText(e), error: true); }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: s.role == 'manager' ? 'staff' : 'manager', child: Text(s.role == 'manager' ? 'تحويل إلى موظف' : 'ترقية إلى مدير')),
                    const PopupMenuItem(value: 'remove', child: Text('إزالة من الفريق', style: TextStyle(color: Joy.danger))),
                  ],
                ),
            ])),
          ),
        if (biz.myRole == 'owner') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => _transfer(context, ref), icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: const Text('نقل ملكية الدائرة')),
        ],
      ]),
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

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final handle = TextEditingController();
    var role = 'staff';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إضافة عضو'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: handle, autofocus: true, decoration: const InputDecoration(labelText: 'النك نيم أو المعرّف (SA…)')),
            const SizedBox(height: 10),
            Row(children: [
              for (final (k, l) in [('staff', 'موظف'), ('manager', 'مدير')])
                Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(l, style: TextStyle(color: role == k ? Joy.primaryOn : Joy.text)), selected: role == k, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setS(() => role = k))),
            ]),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة'))],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final id = await _resolveUser(context, ref, handle.text);
    if (id == null) return;
    try {
      await ref.read(apiClientProvider).addBizStaff(biz.id, id, role: role);
      ref.invalidate(bizTeamProvider(biz.id));
      if (context.mounted) toast(context, 'أُضيف إلى الفريق');
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
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
