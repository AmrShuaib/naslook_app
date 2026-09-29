import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jobs_api.dart';
import '../api/jobs_models.dart';
import 'admin_providers.dart';
import 'app_state.dart';

/// مزوّدو الجانب العام من التوظيف: قائمة الوظائف، الوظيفة، وظائف الدائرة، والدوائر التي توظّف (للخريطة).

/// مفتاح قائمة الوظائف العامة: البحث والمدينة والدوام والدائرة (فارغ = الكل).
typedef JobsQuery = ({String q, String city, String type, String bizId});
const JobsQuery jobsQueryAll = (q: '', city: '', type: '', bizId: '');

final jobsListProvider = FutureProvider.family<JobsList, JobsQuery>((ref, k) => ref.watch(apiClientProvider).publicJobs(q: k.q, city: k.city, type: k.type, bizId: k.bizId));
final publicJobProvider = FutureProvider.family<Job, String>((ref, id) => ref.watch(apiClientProvider).publicJob(id));
/// الوظائف المفتوحة لدائرة معيّنة (بطاقة «وظائف شاغرة» في صفحة الدائرة).
final bizJobsProvider = FutureProvider.family<List<Job>, String>((ref, bizId) => ref.watch(apiClientProvider).bizJobs(bizId));
/// معرّفات الدوائر التي لديها وظائف مفتوحة الآن (فلتر «وظائف» على الخريطة).
final hiringBizProvider = FutureProvider<Set<String>>((ref) async => {for (final h in await ref.watch(apiClientProvider).hiringCircles()) h.bizId});

/// هل التوظيف مفعّل من الإدارة؟ يظهر افتراضياً حتى تصل الإعدادات (ليست ميزة مالية فلا حاجة للإخفاء الاحترازي).
final jobsEnabledProvider = Provider<bool>((ref) => ref.watch(publicSettingsProvider).valueOrNull?.jobsEnabled ?? true);

/// يحدّث ما يخص الوظائف العامة بعد تقديم أو تغيير.
void invalidatePublicJobs(WidgetRef ref, {String? jobId, String? bizId}) {
  ref.invalidate(jobsListProvider);
  ref.invalidate(hiringBizProvider);
  if (jobId != null) ref.invalidate(publicJobProvider(jobId));
  if (bizId != null) ref.invalidate(bizJobsProvider(bizId));
}
