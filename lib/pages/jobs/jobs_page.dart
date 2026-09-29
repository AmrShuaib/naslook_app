import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/jobs_api.dart';
import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../state/jobs_public_providers.dart';
import '../../state/providers.dart' show signedInProvider;
import '../../ui/widgets.dart';
import 'job_page.dart';
import 'job_profile_page.dart';

/// ملف التوظيف الخاص بالمستخدم (لعرض الدعوة لإنشائه في الحالة الفارغة)؛ للزائر لا طلب.
final _myJobProfileProvider = FutureProvider<JobProfileState>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).jobProfile() : const JobProfileState());

/// قائمة الوظائف العامة: بحث، مدن، أنواع الدوام، وبطاقات الوظائف. تُفتح عامة أو مقيّدة بدائرة واحدة.
class JobsPage extends ConsumerStatefulWidget {
  /// إن حُدّدت تُعرض وظائف هذه الدائرة فقط.
  final String? bizId;
  /// اسم الدائرة للعنوان حين تكون القائمة مقيّدة بها.
  final String? title;
  const JobsPage({super.key, this.bizId, this.title});
  @override
  ConsumerState<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends ConsumerState<JobsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String q = '', city = '', type = '';

  JobsQuery get _key => (q: q, city: city, type: type, bizId: widget.bizId ?? '');
  /// القائمة بلا فلاتر: مصدر المدن المتاحة حتى لا تختفي الرقائق عند التصفية.
  JobsQuery get _base => (q: '', city: '', type: '', bizId: widget.bizId ?? '');

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () { if (mounted) setState(() => q = v.trim()); });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(jobsListProvider(_key));
    final cities = ref.watch(jobsListProvider(_base)).valueOrNull?.cities ?? list.valueOrNull?.cities ?? const <String>[];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(widget.bizId != null ? 'وظائف ${widget.title ?? 'الدائرة'}' : 'الوظائف'),
        actions: [
          if (ref.watch(signedInProvider))
            IconButton(key: const Key('jobs-my-profile'), tooltip: 'ملفي «أبحث عن عمل»', icon: const Icon(Icons.badge_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobProfilePage()))),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            key: const Key('jobs-search'),
            controller: _search,
            onChanged: _onSearch,
            onSubmitted: (v) => setState(() => q = v.trim()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث بالمسمّى أو المهارة',
              prefixIcon: const Icon(Icons.search_rounded, color: Joy.textMuted),
              suffixIcon: q.isEmpty ? null : IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _search.clear(); setState(() => q = ''); }),
              isDense: true,
            ),
          ),
        ),
        if (cities.isNotEmpty)
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                _chip('كل المدن', Icons.location_city_rounded, city == '', () => setState(() => city = ''), key: const Key('jobs-city-all')),
                for (final c in cities) _chip(c, Icons.place_outlined, city == c, () => setState(() => city = city == c ? '' : c), key: Key('jobs-city-$c')),
              ]),
            ),
          ),
        SizedBox(
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              for (final e in jobTypes.entries) _chip(e.value, _typeIcon(e.key), type == e.key, () => setState(() => type = type == e.key ? '' : e.key), key: Key('jobs-type-${e.key}'), color: Joy.accent),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: list.when(
            skipLoadingOnReload: true,
            data: (page) => page.items.isEmpty
                ? _Empty(filtered: q.isNotEmpty || city.isNotEmpty || type.isNotEmpty, onClear: () { _search.clear(); setState(() { q = ''; city = ''; type = ''; }); })
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(jobsListProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => JobCard(job: page.items[i], showBiz: widget.bizId == null),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobsListProvider(_key))),
          ),
        ),
      ]),
    );
  }

  static IconData _typeIcon(String t) => switch (t) {
        'part' => Icons.schedule_rounded,
        'remote' => Icons.laptop_mac_rounded,
        'intern' => Icons.school_outlined,
        'shift' => Icons.nightlight_outlined,
        'freelance' => Icons.handshake_outlined,
        _ => Icons.work_outline_rounded,
      };

  Widget _chip(String label, IconData icon, bool on, VoidCallback onTap, {Key? key, Color color = Joy.primary}) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(
          key: key,
          avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
          label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text)),
          selected: on,
          showCheckmark: false,
          selectedColor: color,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );
}

/// الحالة الفارغة: مع فلاتر تقترح مسحها؛ وبلا فلاتر تدعو من لا ملف له إلى إنشاء ملف «أبحث عن عمل» لتصله العروض.
class _Empty extends ConsumerWidget {
  final bool filtered;
  final VoidCallback onClear;
  const _Empty({required this.filtered, required this.onClear});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filtered) return EmptyState(icon: Icons.search_off_rounded, title: 'لا وظائف مطابقة', subtitle: 'جرّب كلمة أخرى أو أزل الفلاتر.', action: OutlinedButton(onPressed: onClear, child: const Text('إزالة الفلاتر')));
    final hasProfile = ref.watch(_myJobProfileProvider).valueOrNull?.profile != null;
    return EmptyState(
      icon: Icons.work_outline_rounded,
      title: 'لا وظائف شاغرة الآن',
      subtitle: hasProfile ? 'ملفك «أبحث عن عمل» جاهز؛ ستصلك بطاقات العروض المطابقة فور نشرها.' : 'أنشئ ملف «أبحث عن عمل» لتصلك بطاقات العروض المطابقة فور نشرها.',
      action: hasProfile
          ? null
          : FilledButton.icon(
              key: const Key('jobs-profile-cta'),
              onPressed: () { if (requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobProfilePage())); },
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('أبحث عن عمل'),
            ),
    );
  }
}

/// بطاقة وظيفة في القائمة: الدائرة (شعار واسم وتوثيق)، المسمّى، المدينة والدوام، الراتب إن ظهر، تاريخ النشر، وشارة «تقدّمت».
class JobCard extends StatelessWidget {
  final Job job;
  final bool showBiz;
  const JobCard({super.key, required this.job, this.showBiz = true});
  @override
  Widget build(BuildContext context) {
    final biz = job.biz;
    final applied = job.mine?.applied == true;
    return JoyCard(
      key: Key('job-${job.id}'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobPage(id: job.id, initial: job))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (biz != null) Avatar(name: biz.title, url: biz.logoUrl, size: 46, radius: 13) else Container(width: 46, height: 46, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.work_outline_rounded, color: Joy.primary)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showBiz && biz != null)
              Row(children: [
                Flexible(child: Text(biz.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600))),
                if (biz.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified_rounded, size: 14, color: Joy.primary)),
              ]),
            Row(children: [
              Expanded(child: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              if (applied)
                Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)),
                    child: const Text('تقدّمت', key: Key('job-applied-badge'), style: TextStyle(fontSize: 10.5, color: Joy.primary, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 3),
            Text([if (job.city.isNotEmpty) job.city, job.typeLabel].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            const SizedBox(height: 3),
            Row(children: [
              if (job.salaryVisible && job.salaryText.isNotEmpty) ...[
                Text(job.salaryText, style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(width: 8),
              ],
              if (job.publishedAt != null) Text('نُشرت ${timeAgo(job.publishedAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            ]),
          ]),
        ),
        const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
      ]),
    );
  }
}

/// بطاقة مختصرة في صفحة الدائرة: «N وظائف شاغرة» تفتح قائمة وظائف الدائرة؛ تختفي حين لا وظائف مفتوحة أو التوظيف مطفأ.
class JobsEntryCard extends ConsumerWidget {
  final String bizId;
  final String title;
  const JobsEntryCard({super.key, required this.bizId, required this.title});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(jobsEnabledProvider)) return const SizedBox.shrink();
    final jobs = ref.watch(bizJobsProvider(bizId)).valueOrNull ?? const <Job>[];
    if (jobs.isEmpty) return const SizedBox.shrink();
    final n = jobs.length;
    final first = jobs.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JoyCard(
        key: const Key('jobs-entry'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobsPage(bizId: bizId, title: title))),
        color: Joy.primarySoft,
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.work_outline_rounded, color: Joy.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n == 1 ? 'وظيفة شاغرة' : n == 2 ? 'وظيفتان شاغرتان' : '$n وظائف شاغرة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Joy.primary)),
              Text([first.title, first.typeLabel].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.text, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_left_rounded, color: Joy.primary),
        ]),
      ),
    );
  }
}
