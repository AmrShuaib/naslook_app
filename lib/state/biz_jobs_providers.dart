import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jobs_api.dart';
import '../api/jobs_models.dart';
import 'app_state.dart';

/// مزوّدات جانب الدائرة في التوظيف: لوحة العروض، الأرقام العامة، مرشحو عرض، مرشح واحد، وإحصاءات عرض.
/// مستقلة عن مزوّدات الباحث عن عمل حتى لا تتصادم الجلسات المتوازية على ملف واحد.
typedef JobRef = ({String bizId, String jobId});
typedef JobMatchRef = ({String bizId, String jobId, String matchId});

final jobsBoardProvider = FutureProvider.family<JobsBoard, String>((ref, bizId) => ref.watch(apiClientProvider).bizJobsBoard(bizId));
final jobsOverviewProvider = FutureProvider.family<JobsOverview, String>((ref, bizId) => ref.watch(apiClientProvider).bizJobsOverview(bizId));
final jobCandidatesProvider = FutureProvider.family<JobCandidates, JobRef>((ref, k) => ref.watch(apiClientProvider).jobCandidates(k.bizId, k.jobId));
final jobCandidateProvider = FutureProvider.family<JobCandidate, JobMatchRef>((ref, k) => ref.watch(apiClientProvider).jobCandidate(k.bizId, k.jobId, k.matchId));
final jobStatsProvider = FutureProvider.family<JobStats, JobRef>((ref, k) => ref.watch(apiClientProvider).jobStats(k.bizId, k.jobId));

/// بعد أي إجراء على عرض أو مرشح: تُعاد كل قوائم الدائرة لأن العدّادات مشتركة بينها.
void invalidateBizJobs(WidgetRef ref, String bizId) {
  ref.invalidate(jobsBoardProvider(bizId));
  ref.invalidate(jobsOverviewProvider(bizId));
  ref.invalidate(jobCandidatesProvider);
  ref.invalidate(jobCandidateProvider);
  ref.invalidate(jobStatsProvider);
}
