import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jobs_api.dart';
import '../api/jobs_models.dart';
import 'app_state.dart';
import 'providers.dart';

/// مزوّدات التوظيف من جهة الباحث عن عمل. صندوق العروض الواردة (`jobsInboxProvider`) في providers.dart لأن شارة الجرس تعتمد عليه.

/// ملف «أبحث عن عمل» مع عدّادات الصندوق؛ للزائر فارغ بلا طلب.
final jobProfileProvider = FutureProvider<JobProfileState>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).jobProfile() : const JobProfileState());

/// طلباتي: الجارية والسابقة.
final myJobsProvider = FutureProvider<JobInbox>((ref) async => ref.watch(signedInProvider) ? ref.watch(apiClientProvider).myJobs() : const JobInbox());

/// عرض واحد بمعرّف البطاقة (الخادم يعلّمه «شوهد» عند أول فتح).
final jobOfferProvider = FutureProvider.family<JobMatch, String>((ref, id) => ref.watch(apiClientProvider).jobOffer(id));

/// يحدّث كل ما يخص التوظيف بعد قبول أو رفض أو إجابة أو حفظ الملف.
void invalidateJobs(WidgetRef ref, {String? matchId}) {
  ref.invalidate(jobsInboxProvider);
  ref.invalidate(myJobsProvider);
  ref.invalidate(jobProfileProvider);
  if (matchId != null) ref.invalidate(jobOfferProvider(matchId));
}
