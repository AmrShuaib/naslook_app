import 'client.dart';
import 'jobs_models.dart';

/// مسارات التوظيف (server/jobs.js): ملف التوظيف، صندوق العروض وعروضي، الوظائف العامة والتقديم، إدارة العروض والمرشحين في الدائرة،
/// والإدارة العامة.
extension JobsApi on ApiClient {
  // ---- ملف التوظيف والعروض الواردة
  Future<JobProfileState> jobProfile() async => JobProfileState.fromJson(await get('/jobs/profile'));
  Future<JobProfile> saveJobProfile(Map<String, dynamic> body) async => JobProfile.fromJson((await put('/jobs/profile', body))['profile'] ?? const {});
  Future<void> deleteJobProfile() => delete('/jobs/profile', body: const {});
  Future<JobInbox> jobsInbox() async => JobInbox.fromJson(await get('/jobs/inbox'));
  Future<JobInbox> myJobs() async => JobInbox.fromJson(await get('/jobs/mine'));
  Future<JobMatch> jobOffer(String matchId) async => JobMatch.fromJson(await get('/jobs/offers/$matchId'));
  Future<JobOfferResult> acceptJobOffer(String matchId) async => JobOfferResult.fromJson(await post('/jobs/offers/$matchId/accept', const {}));
  Future<void> declineJobOffer(String matchId, {String reason = ''}) => post('/jobs/offers/$matchId/decline', {'reason': reason});
  Future<void> laterJobOffer(String matchId) => post('/jobs/offers/$matchId/later', const {});
  /// الإجابات: قائمة {id, value}؛ القيمة نص أو رقم أو true/false أو خيار.
  Future<JobOfferResult> answerJobOffer(String matchId, List<Map<String, dynamic>> answers) async => JobOfferResult.fromJson(await post('/jobs/offers/$matchId/answers', {'answers': answers}));
  Future<void> withdrawJobOffer(String matchId) => post('/jobs/offers/$matchId/withdraw', const {});

  // ---- العام
  Future<JobsList> publicJobs({String q = '', String city = '', String type = '', String bizId = ''}) async =>
      JobsList.fromJson(await get('/jobs', query: {if (q.isNotEmpty) 'q': q, if (city.isNotEmpty) 'city': city, if (type.isNotEmpty) 'type': type, if (bizId.isNotEmpty) 'bizId': bizId}));
  Future<List<HiringBiz>> hiringCircles() async => (await getList('/jobs/hiring')).map((e) => HiringBiz.fromJson(e as Map)).toList();
  Future<List<Job>> bizJobs(String bizId) async => (await getList('/biz/$bizId/jobs')).map((e) => Job.fromJson(e as Map)).toList();
  Future<Job> publicJob(String id) async => Job.fromJson(await get('/jobs/$id'));
  Future<JobOfferResult> applyJob(String id) async => JobOfferResult.fromJson(await post('/jobs/$id/apply', const {}));

  // ---- إدارة الدائرة
  Future<JobsBoard> bizJobsBoard(String bizId) async => JobsBoard.fromJson(await get('/biz/$bizId/manage/jobs'));
  Future<JobDraft> draftJob(String bizId, {required String title, List<String> bullets = const [], String type = 'full', String city = '', String department = '', int? salaryMin, int? salaryMax, bool useAi = true}) async =>
      JobDraft.fromJson(await post('/biz/$bizId/manage/jobs/draft', {'title': title, 'bullets': bullets, 'type': type, 'city': city, 'department': department, 'salaryMin': salaryMin, 'salaryMax': salaryMax, 'useAi': useAi}));
  Future<Job> createJob(String bizId, Map<String, dynamic> body, {bool publish = false}) async => Job.fromJson(await post('/biz/$bizId/manage/jobs', {...body, 'publish': publish}));
  Future<Job> updateJob(String bizId, String jobId, Map<String, dynamic> body) async => Job.fromJson(await patch_('/biz/$bizId/manage/jobs/$jobId', body));
  Future<Job> publishJob(String bizId, String jobId) async => Job.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/publish', const {}));
  Future<Job> pauseJob(String bizId, String jobId) async => Job.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/pause', const {}));
  Future<Job> closeJob(String bizId, String jobId, {bool filled = false}) async => Job.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/close', {'filled': filled}));
  Future<Job> duplicateJob(String bizId, String jobId) async => Job.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/duplicate', const {}));
  Future<void> deleteJob(String bizId, String jobId) => delete('/biz/$bizId/manage/jobs/$jobId', body: const {});
  Future<JobPreview> previewJobMatch(String bizId, String jobId) async => JobPreview.fromJson(await get('/biz/$bizId/manage/jobs/$jobId/preview-match'));
  Future<JobPreview> previewDraftMatch(String bizId, Map<String, dynamic> body) async => JobPreview.fromJson(await post('/biz/$bizId/manage/jobs/preview-match', body));
  Future<JobCandidates> jobCandidates(String bizId, String jobId, {String stage = ''}) async => JobCandidates.fromJson(await get('/biz/$bizId/manage/jobs/$jobId/candidates', query: {if (stage.isNotEmpty) 'stage': stage}));
  Future<JobCandidate> jobCandidate(String bizId, String jobId, String matchId) async => JobCandidate.fromJson(await get('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId'));
  Future<JobCandidate> updateJobCandidate(String bizId, String jobId, String matchId, {String? stage, String? assigneeId}) async =>
      JobCandidate.fromJson(await patch_('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId', {if (stage != null) 'stage': stage, if (assigneeId != null) 'assigneeId': assigneeId}));
  Future<JobNote> addJobNote(String bizId, String jobId, String matchId, {String text = '', int? rating}) async => JobNote.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId/notes', {'text': text, 'rating': rating}));
  Future<void> deleteJobNote(String bizId, String jobId, String matchId, String noteId) => delete('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId/notes/$noteId', body: const {});
  Future<JobInterview> scheduleJobInterview(String bizId, String jobId, String matchId, {required DateTime at, String mode = 'onsite', String place = '', String note = ''}) async =>
      JobInterview.fromJson(await post('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId/interviews', {'at': at.toUtc().toIso8601String(), 'mode': mode, 'place': place, 'note': note}));
  Future<void> updateJobInterview(String bizId, String jobId, String matchId, String interviewId, String status) => patch_('/biz/$bizId/manage/jobs/$jobId/candidates/$matchId/interviews/$interviewId', {'status': status});
  Future<JobStats> jobStats(String bizId, String jobId) async => JobStats.fromJson(await get('/biz/$bizId/manage/jobs/$jobId/stats'));
  Future<JobsOverview> bizJobsOverview(String bizId) async => JobsOverview.fromJson(await get('/biz/$bizId/manage/jobs/stats'));
  /// تصدير المرشحين CSV (باقة pro): الخادم يعيد نصاً فيُغلَّف في raw.
  Future<String> exportJobCandidates(String bizId, String jobId) async => (await get('/biz/$bizId/manage/jobs/$jobId/export'))['raw']?.toString() ?? '';

  // ---- الإدارة العامة
  Future<AdminJobs> adminJobs({String status = ''}) async => AdminJobs.fromJson(await get('/adminapi/jobs', query: {if (status.isNotEmpty) 'status': status}));
  Future<Job> adminApproveJob(String id) async => Job.fromJson(await post('/adminapi/jobs/$id/approve', const {}));
  Future<void> adminCloseJob(String id, {String reason = ''}) => post('/adminapi/jobs/$id/close', {'reason': reason});
  Future<JobPlan> adminJobPlan(String bizId) async => JobPlan.fromJson(await get('/adminapi/jobs/plans/$bizId'));
  Future<JobPlan> adminSetJobPlan(String bizId, {required String plan, int months = 1}) async => JobPlan.fromJson(await put('/adminapi/jobs/plans/$bizId', {'plan': plan, 'months': months}));
}
