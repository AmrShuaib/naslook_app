import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../state/jobs_providers.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'job_offer_page.dart';
import 'job_profile_page.dart';

/// «عروض التوظيف»: الواردة (بطاقات بانتظار الرد ثم المؤجّلة) وطلباتي (الجارية ثم السابقة).
class JobOffersPage extends ConsumerStatefulWidget {
  final int initialTab;
  const JobOffersPage({super.key, this.initialTab = 0});
  @override
  ConsumerState<JobOffersPage> createState() => _JobOffersPageState();
}

class _JobOffersPageState extends ConsumerState<JobOffersPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(jobsInboxProvider);
    final mine = ref.watch(myJobsProvider);
    final tabs = [('الواردة', inbox.valueOrNull?.pending ?? 0), ('طلباتي', mine.valueOrNull?.active.length ?? 0)];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('عروض التوظيف'),
        actions: [IconButton(key: const Key('offers-profile'), tooltip: 'ملفي الوظيفي', icon: const Icon(Icons.badge_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobProfilePage())))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            for (final (i, (label, n)) in tabs.indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  key: Key('jobs-tab-$i'),
                  label: Text(n == 0 ? label : '$label · $n', style: TextStyle(color: _tab == i ? Joy.primaryOn : Joy.text)),
                  selected: _tab == i, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setState(() => _tab = i),
                ),
              ),
          ]),
        ),
        Expanded(child: _tab == 0 ? _inbox(inbox) : _mine(mine)),
      ]),
    );
  }

  Widget _inbox(AsyncValue<JobInbox> inbox) => inbox.when(
        data: (d) {
          final pending = d.items.where((m) => m.pending).toList();
          final later = d.items.where((m) => !m.pending).toList();
          if (d.items.isEmpty) {
            return EmptyState(
              icon: Icons.work_outline_rounded, title: 'لا عروض واردة الآن', subtitle: 'حين تنشر دائرة وظيفة تناسب ملفك تصلك بطاقتها هنا وفي تبويب «الطلبات».',
              action: OutlinedButton(key: const Key('offers-empty-profile'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobProfilePage())), child: const Text('ملفي الوظيفي')),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(jobsInboxProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (pending.isNotEmpty) const SectionTitle('بانتظار ردك'),
                for (final m in pending) Padding(padding: const EdgeInsets.only(bottom: 10), child: JobOfferCard(m, actions: true)),
                if (later.isNotEmpty) const SectionTitle('مؤجّلة'),
                for (final m in later) Padding(padding: const EdgeInsets.only(bottom: 10), child: JobOfferCard(m, actions: true)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobsInboxProvider)),
      );

  Widget _mine(AsyncValue<JobInbox> mine) => mine.when(
        data: (d) {
          if (d.active.isEmpty && d.history.isEmpty) {
            return const EmptyState(icon: Icons.assignment_outlined, title: 'لا طلبات بعد', subtitle: 'حين تقبل عرضاً يظهر هنا مع مرحلته والمقابلات.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myJobsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (d.active.isNotEmpty) const SectionTitle('الجارية'),
                for (final m in d.active) Padding(padding: const EdgeInsets.only(bottom: 10), child: JobOfferCard(m)),
                if (d.history.isNotEmpty) const SectionTitle('السابقة'),
                for (final m in d.history) Padding(padding: const EdgeInsets.only(bottom: 10), child: JobOfferCard(m)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myJobsProvider)),
      );
}

/// بطاقة عرض وظيفي: شعار الدائرة واسمها، المسمّى، المدينة · الدوام، الراتب إن كان معلناً، أسباب المطابقة، الحالة والمقابلة.
/// [actions] يعرض أزرار الرد داخل البطاقة (تبويب «الطلبات» وصندوق الواردة)؛ اللمس يفتح صفحة العرض دائماً.
class JobOfferCard extends ConsumerWidget {
  final JobMatch m;
  final bool actions;
  const JobOfferCard(this.m, {super.key, this.actions = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = m.job;
    final b = j?.biz;
    final meta = [if (b != null && b.title.isNotEmpty) b.title, if (j != null && j.city.isNotEmpty) j.city, if (j != null) j.typeLabel].join(' · ');
    final salary = j?.salaryText ?? '';
    final iv = m.interview;
    final canAct = actions && (m.pending || m.status == 'later');
    return JoyCard(
      key: Key('job-card-${m.id}'),
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobOfferPage(matchId: m.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(name: b?.title ?? j?.bizName ?? '؟', url: b?.logoUrl, size: 46, radius: 12),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j?.title ?? 'عرض وظيفي', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              if (salary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(salary, style: const TextStyle(color: Joy.accent, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(width: 8),
          JobBadge(jobMatchBadge(m)),
        ]),
        if (m.reasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in m.reasons.take(4))
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(r, style: const TextStyle(color: Joy.primary, fontSize: 11.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        if (iv != null && iv.status == 'scheduled')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.event_available_outlined, size: 16, color: Joy.accent),
              const SizedBox(width: 6),
              Expanded(child: Text('مقابلة ${iv.modeLabel} · ${jobWhen(iv.at)}${iv.place.isNotEmpty ? ' · ${iv.place}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        if (canAct)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Expanded(child: FilledButton(key: Key('job-accept-${m.id}'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => JobOfferFlow.accept(context, ref, m), child: const Text('أقبل'))),
              if (m.pending) ...[
                const SizedBox(width: 8),
                OutlinedButton(key: Key('job-later-${m.id}'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => JobOfferFlow.later(context, ref, m), child: const Text('لاحقاً')),
              ],
              const SizedBox(width: 8),
              TextButton(key: Key('job-decline-${m.id}'), onPressed: () => JobOfferFlow.decline(context, ref, m), child: const Text('لا يناسبني', style: TextStyle(color: Joy.textMuted))),
            ]),
          ),
      ]),
    );
  }
}
