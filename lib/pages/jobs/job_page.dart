import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/jobs_api.dart';
import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../core/require_account.dart';
import '../../core/share/share_links.dart';
import '../../state/app_state.dart';
import '../../state/jobs_public_providers.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness, shortDate;
import '../chat/chat_thread_page.dart';
import 'job_offer_page.dart';
import 'job_profile_page.dart';

/// رابط الوظيفة العام للمشاركة.
String jobLink(String id) => '${publicOrigin()}/jobs/$id';

/// صفحة الوظيفة العامة: الدائرة، المسمّى، الدوام والمدينة والموعد النهائي، الراتب إن ظهر، الوصف والمتطلبات والمهارات،
/// وأسفلها «تقدّم الآن» أو حالتي على الوظيفة (تقدّمت / لديك دعوة).
class JobPage extends ConsumerStatefulWidget {
  final String id;
  /// نسخة من القائمة تُعرض حتى يصل التفصيل.
  final Job? initial;
  const JobPage({super.key, required this.id, this.initial});
  @override
  ConsumerState<JobPage> createState() => _JobPageState();
}

class _JobPageState extends ConsumerState<JobPage> {
  bool _busy = false;

  Future<void> _apply(Job job) async {
    if (!requireAccount(context) || _busy) return;
    setState(() => _busy = true);
    JobOfferResult? r;
    var needProfile = false;
    try {
      r = await ref.read(apiClientProvider).applyJob(job.id);
      invalidatePublicJobs(ref, jobId: job.id, bizId: job.bizId);
    } on ApiException catch (e) {
      if (!mounted) return;
      final code = e.body?['error']?.toString() ?? '';
      if (code == 'profile-required') {
        needProfile = true;
      } else {
        if (code == 'already') invalidatePublicJobs(ref, jobId: job.id, bizId: job.bizId);
        toast(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      // يُرفع الانشغال قبل أي تنقّل أو حوار حتى لا يبقى مؤشر الزر يدور خلفهما
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (needProfile) return _needProfile();
    if (r == null) return;
    if (r.questions.isNotEmpty && r.matchId != null) {
      // أسئلة فرز: تُجاب في صفحة العرض، وبعدها تُفتح المحادثة مع المسؤول
      toast(context, 'تقدّمت؛ أجب على أسئلة الفرز لتصل إلى فريق التوظيف');
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobOfferPage(matchId: r!.matchId!)));
    } else if (r.chatWith != null) {
      toast(context, 'تقدّمت على «${job.title}»؛ يمكنك التواصل مع فريق التوظيف الآن');
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r!.chatWith!)));
    } else {
      toast(context, 'تقدّمت على «${job.title}»');
    }
  }

  /// التقديم يحتاج ملف «أبحث عن عمل»؛ نعرض حواراً يفتح صفحة الملف.
  Future<void> _needProfile() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('أكمل ملفك أولاً'),
        content: const Text('التقديم يحتاج ملف «أبحث عن عمل» (المسمّى والمهارات والمدينة). يستغرق دقيقة، ويبقى خاصاً حتى تجيب على أسئلة الدائرة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لاحقاً')),
          FilledButton(key: const Key('job-go-profile'), onPressed: () => Navigator.pop(d, true), child: const Text('إنشاء الملف')),
        ],
      ),
    );
    if (go == true && mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobProfilePage()));
  }

  void _share(Job job) => shareLink(context, title: job.title, url: jobLink(job.id), subtitle: 'وظيفة${job.biz != null ? ' في ${job.biz!.title}' : ''} على ناس لايف');

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(publicJobProvider(widget.id));
    final job = detail.valueOrNull ?? widget.initial;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: const Text('الوظيفة'),
        actions: [if (job != null) IconButton(key: const Key('job-share'), tooltip: 'مشاركة', icon: const Icon(Icons.ios_share_rounded), onPressed: () => _share(job))],
      ),
      body: job == null
          ? detail.when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(publicJobProvider(widget.id))),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(publicJobProvider(widget.id)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (job.biz != null) _BizCard(biz: job.biz!),
                  const SizedBox(height: 12),
                  Text(job.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, height: 1.3)),
                  if (job.department.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(job.department, style: const TextStyle(color: Joy.textMuted, fontSize: 13))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _tag(Icons.work_outline_rounded, job.typeLabel),
                    if (job.city.isNotEmpty) _tag(Icons.place_outlined, [job.city, if (job.district.isNotEmpty) job.district].join(' · ')),
                    if (job.deadline != null) _tag(Icons.event_outlined, 'حتى ${shortDate(job.deadline!)}', color: Joy.accentSoft, fg: Joy.accent),
                    if (job.experienceMin > 0) _tag(Icons.timeline_rounded, 'خبرة ${job.experienceMin}+ سنوات'),
                    if (job.education != 'none') _tag(Icons.school_outlined, jobEducation[job.education] ?? job.education),
                  ]),
                  if (job.salaryVisible && job.salaryText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    JoyCard(
                      color: Joy.primarySoft,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.payments_outlined, color: Joy.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(job.salaryText, key: const Key('job-salary'), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                        const Spacer(),
                        const Text('شهرياً', style: TextStyle(color: Joy.primary, fontSize: 12)),
                      ]),
                    ),
                  ],
                  if (job.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionTitle('عن الوظيفة'),
                    Text(job.description, style: const TextStyle(height: 1.7, fontSize: 14.5)),
                  ],
                  if (job.must.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionTitle('المتطلبات'),
                    for (final r in job.must) _bullet(r, Icons.check_circle_rounded, Joy.primary),
                  ],
                  if (job.nice.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SectionTitle('يُفضَّل'),
                    for (final r in job.nice) _bullet(r, Icons.add_circle_outline_rounded, Joy.textMuted),
                  ],
                  if (job.skills.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SectionTitle('المهارات'),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final s in job.skills) Chip(label: Text(s, style: const TextStyle(fontSize: 12.5, color: Joy.text)), visualDensity: VisualDensity.compact, backgroundColor: Joy.surface2, side: BorderSide.none)]),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [
                    const Icon(Icons.groups_outlined, size: 18, color: Joy.textMuted),
                    const SizedBox(width: 6),
                    Text(job.openings == 1 ? 'شاغر واحد' : job.openings == 2 ? 'شاغران' : '${job.openings} شواغر', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
                    if (job.publishedAt != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.schedule_rounded, size: 18, color: Joy.textMuted),
                      const SizedBox(width: 6),
                      Text('نُشرت ${timeAgo(job.publishedAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
                    ],
                  ]),
                ],
              ),
            ),
      bottomNavigationBar: job == null ? null : _Bottom(job: job, busy: _busy, onApply: () => _apply(job)),
    );
  }

  static Widget _tag(IconData icon, String text, {Color color = Joy.surface2, Color fg = Joy.text}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: fg), const SizedBox(width: 4), Text(text, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600))]),
      );

  static Widget _bullet(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(height: 1.5, fontSize: 14)))]),
      );
}

/// بطاقة الدائرة الناشرة: تفتح صفحتها.
class _BizCard extends StatelessWidget {
  final JobBiz biz;
  const _BizCard({required this.biz});
  @override
  Widget build(BuildContext context) => JoyCard(
        key: const Key('job-biz'),
        onTap: () => openBusiness(context, biz.id),
        child: Row(children: [
          Avatar(name: biz.title, url: biz.logoUrl, size: 46, radius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(biz.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (biz.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified_rounded, size: 16, color: Joy.primary)),
              ]),
              Text([if (biz.category.isNotEmpty) biz.category, if (biz.address.isNotEmpty) biz.address.split('،').first else if (biz.city.isNotEmpty) biz.city].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        ]),
      );
}

/// الشريط السفلي: «تقدّم الآن»، أو حالتي إن تقدّمت، أو الدعوة إن وصلتني بطاقة لم أرد عليها.
class _Bottom extends StatelessWidget {
  final Job job;
  final bool busy;
  final VoidCallback onApply;
  const _Bottom({required this.job, required this.busy, required this.onApply});
  @override
  Widget build(BuildContext context) {
    final mine = job.mine;
    Widget child;
    if (!job.isOpen) {
      child = const Text('هذه الوظيفة لم تعد متاحة', key: Key('job-closed'), textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontWeight: FontWeight.w600));
    } else if (mine != null && mine.applied) {
      child = Row(children: [
        const Icon(Icons.check_circle_rounded, color: Joy.primary),
        const SizedBox(width: 8),
        Expanded(child: Text('تقدّمت · ${jobStageLabel(mine.stage)}', key: const Key('job-mine-status'), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700))),
        if (mine.matchId != null) TextButton(key: const Key('job-open-mine'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobOfferPage(matchId: mine.matchId!))), child: const Text('التفاصيل')),
      ]);
    } else if (mine != null && mine.matchId != null && ['sent', 'viewed', 'later'].contains(mine.status)) {
      child = Row(children: [
        const Icon(Icons.mark_email_unread_outlined, color: Joy.accent),
        const SizedBox(width: 8),
        const Expanded(child: Text('لديك دعوة لهذه الوظيفة', key: Key('job-invited'), style: TextStyle(color: Joy.accent, fontWeight: FontWeight.w700))),
        FilledButton(key: const Key('job-open-offer'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobOfferPage(matchId: mine.matchId!))), child: const Text('افتح العرض')),
      ]);
    } else {
      child = FilledButton.icon(
        key: const Key('job-apply'),
        onPressed: busy ? null : onApply,
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 18),
        label: const Text('تقدّم الآن'),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
