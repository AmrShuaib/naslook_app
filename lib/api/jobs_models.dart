import 'models.dart';

/// نماذج التوظيف (server/jobs.js): ملف التوظيف الخاص، العرض الوظيفي، بطاقة المطابقة، المرشح في لوحة الدائرة، المسودة من المحرك،
/// الإحصاءات والباقة.

Map<String, dynamic> _m(dynamic v) => asMap(v);
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? d;
int? _in(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? d;
List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty && e != '{}').toList() : const [];

/// أنواع الدوام كما يعرّفها الخادم.
const jobTypes = <String, String>{'full': 'دوام كامل', 'part': 'دوام جزئي', 'remote': 'عن بُعد', 'intern': 'تدريب', 'shift': 'ورديات', 'freelance': 'عمل حر'};
const jobEducation = <String, String>{'none': 'غير محدد', 'secondary': 'ثانوية', 'diploma': 'دبلوم', 'bachelor': 'بكالوريوس', 'master': 'ماجستير', 'phd': 'دكتوراه'};
const jobAvailability = <String, String>{'now': 'فوراً', '2w': 'خلال أسبوعين', '1m': 'خلال شهر', '3m': 'خلال ثلاثة أشهر'};
const jobStages = <String, String>{'new': 'جديد', 'screening': 'فرز', 'answered': 'أجاب', 'interview': 'مقابلة', 'offer': 'عرض', 'hired': 'تعيين', 'rejected': 'معتذر'};
const jobStatuses = <String, String>{'draft': 'مسودة', 'pending': 'بانتظار الموافقة', 'open': 'منشور', 'paused': 'موقوف', 'closed': 'مغلق', 'filled': 'شُغلت'};
const matchStatuses = <String, String>{'sent': 'جديد', 'viewed': 'شوهد', 'accepted': 'قبلت', 'declined': 'رفضت', 'later': 'لاحقاً', 'answered': 'أجبت', 'withdrawn': 'انسحبت', 'expired': 'انتهى'};
String jobTypeLabel(String t) => jobTypes[t] ?? t;
String jobStageLabel(String s) => jobStages[s] ?? s;
String jobStatusLabel(String s) => jobStatuses[s] ?? s;

/// ملف التوظيف الخاص بالمستخدم («أبحث عن عمل»).
class JobProfile {
  final String userId;
  final bool active;
  final List<String> titles, fields, districts, types, skills, languages;
  final String city, education, availability, summary;
  final int experienceYears;
  final int? salaryMin, salaryMax;
  final String? cvUrl, cvName;
  final DateTime? updatedAt, createdAt;
  const JobProfile({
    this.userId = '', this.active = true, this.titles = const [], this.fields = const [], this.districts = const [], this.types = const [], this.skills = const [], this.languages = const [],
    this.city = '', this.education = 'none', this.availability = 'now', this.summary = '', this.experienceYears = 0, this.salaryMin, this.salaryMax, this.cvUrl, this.cvName, this.updatedAt, this.createdAt,
  });
  factory JobProfile.fromJson(Map m) => JobProfile(
        userId: m['userId']?.toString() ?? '', active: m['active'] != false, titles: _strings(m['titles']), fields: _strings(m['fields']), districts: _strings(m['districts']), types: _strings(m['types']),
        skills: _strings(m['skills']), languages: _strings(m['languages']), city: m['city']?.toString() ?? '', education: m['education']?.toString() ?? 'none', availability: m['availability']?.toString() ?? 'now',
        summary: m['summary']?.toString() ?? '', experienceYears: _i(m['experienceYears']), salaryMin: _in(m['salaryMin']), salaryMax: _in(m['salaryMax']), cvUrl: m['cvUrl']?.toString(), cvName: m['cvName']?.toString(),
        updatedAt: _t(m['updatedAt']), createdAt: _t(m['createdAt']));
  Map<String, dynamic> toJson() => {
        'active': active, 'titles': titles, 'fields': fields, 'city': city, 'districts': districts, 'types': types, 'experienceYears': experienceYears, 'education': education, 'skills': skills,
        'languages': languages, 'salaryMin': salaryMin, 'salaryMax': salaryMax, 'availability': availability, 'summary': summary, 'cvUrl': cvUrl, 'cvName': cvName,
      };
  JobProfile copyWith({bool? active, List<String>? titles, List<String>? fields, List<String>? districts, List<String>? types, List<String>? skills, List<String>? languages, String? city, String? education, String? availability, String? summary, int? experienceYears, int? salaryMin, int? salaryMax, bool clearSalary = false, String? cvUrl, String? cvName, bool clearCv = false}) => JobProfile(
        userId: userId, active: active ?? this.active, titles: titles ?? this.titles, fields: fields ?? this.fields, districts: districts ?? this.districts, types: types ?? this.types, skills: skills ?? this.skills, languages: languages ?? this.languages,
        city: city ?? this.city, education: education ?? this.education, availability: availability ?? this.availability, summary: summary ?? this.summary, experienceYears: experienceYears ?? this.experienceYears,
        salaryMin: clearSalary ? null : salaryMin ?? this.salaryMin, salaryMax: clearSalary ? null : salaryMax ?? this.salaryMax, cvUrl: clearCv ? null : cvUrl ?? this.cvUrl, cvName: clearCv ? null : cvName ?? this.cvName, updatedAt: updatedAt, createdAt: createdAt);
}

/// حالة ملف التوظيف مع عدّادات الصندوق (GET /jobs/profile).
class JobProfileState {
  final JobProfile? profile;
  final int pending, total;
  const JobProfileState({this.profile, this.pending = 0, this.total = 0});
  factory JobProfileState.fromJson(Map m) => JobProfileState(profile: m['profile'] is Map ? JobProfile.fromJson(_m(m['profile'])) : null, pending: _i(m['pending']), total: _i(m['total']));
}

/// ملخص الدائرة المرفق بالعرض.
class JobBiz {
  final String id, name, nameAr, category, address, city;
  final String? logoUrl;
  final bool verified;
  final double? lat, lng;
  const JobBiz({required this.id, this.name = '', this.nameAr = '', this.category = '', this.address = '', this.city = '', this.logoUrl, this.verified = false, this.lat, this.lng});
  factory JobBiz.fromJson(Map m) => JobBiz(
        id: m['id']?.toString() ?? '', name: m['name']?.toString() ?? '', nameAr: m['nameAr']?.toString() ?? '', category: m['category']?.toString() ?? '', address: m['address']?.toString() ?? '', city: m['city']?.toString() ?? '',
        logoUrl: m['logoUrl']?.toString(), verified: m['verified'] == true, lat: m['lat'] == null ? null : _d(m['lat']), lng: m['lng'] == null ? null : _d(m['lng']));
  String get title => nameAr.isNotEmpty ? nameAr : name;
}

/// سؤال فرز أولي.
class JobQuestion {
  final String id, text, kind;
  final List<String> options;
  final bool required;
  const JobQuestion({required this.id, required this.text, this.kind = 'text', this.options = const [], this.required = true});
  factory JobQuestion.fromJson(Map m) => JobQuestion(id: m['id']?.toString() ?? '', text: m['text']?.toString() ?? '', kind: m['kind']?.toString() ?? 'text', options: _strings(m['options']), required: m['required'] != false);
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'kind': kind, 'options': options, 'required': required};
  JobQuestion copyWith({String? id, String? text, String? kind, List<String>? options, bool? required}) => JobQuestion(id: id ?? this.id, text: text ?? this.text, kind: kind ?? this.kind, options: options ?? this.options, required: required ?? this.required);
  static const kinds = <String, String>{'text': 'نص', 'yesno': 'نعم/لا', 'choice': 'اختيار', 'number': 'رقم'};
}

/// إجابة مرشح على سؤال.
class JobAnswer {
  final String id, text, kind;
  final dynamic value;
  const JobAnswer({required this.id, this.text = '', this.kind = 'text', this.value});
  factory JobAnswer.fromJson(Map m) => JobAnswer(id: m['id']?.toString() ?? '', text: m['text']?.toString() ?? '', kind: m['kind']?.toString() ?? 'text', value: m['value']);
  String get display => value == null ? '—' : value == true ? 'نعم' : value == false ? 'لا' : value.toString();
}

/// حالتي على عرض (مرفقة بالعروض العامة).
class JobMine {
  final String? matchId;
  final String status, stage;
  const JobMine({this.matchId, this.status = '', this.stage = ''});
  factory JobMine.fromJson(Map m) => JobMine(matchId: m['matchId']?.toString(), status: m['status']?.toString() ?? '', stage: m['stage']?.toString() ?? '');
  bool get applied => ['accepted', 'answered', 'withdrawn'].contains(status) || ['interview', 'offer', 'hired', 'rejected'].contains(stage);
}

/// عدّادات المرشحين على عرض.
class JobCounts {
  final int sent, viewed, accepted, answered, declined;
  final Map<String, int> byStage;
  const JobCounts({this.sent = 0, this.viewed = 0, this.accepted = 0, this.answered = 0, this.declined = 0, this.byStage = const {}});
  factory JobCounts.fromJson(Map m) => JobCounts(sent: _i(m['sent']), viewed: _i(m['viewed']), accepted: _i(m['accepted']), answered: _i(m['answered']), declined: _i(m['declined']), byStage: {for (final e in _m(m['byStage']).entries) e.key: _i(e.value)});
}

/// نتيجة المطابقة عند النشر.
class JobMatched {
  final int sent, considered;
  final bool capped;
  const JobMatched({this.sent = 0, this.considered = 0, this.capped = false});
  factory JobMatched.fromJson(Map m) => JobMatched(sent: _i(m['sent']), considered: _i(m['considered']), capped: m['capped'] == true);
}

/// العرض الوظيفي (للعامة أو للإدارة؛ الحقول الإدارية فارغة في العام).
class Job {
  final String id, bizId, title, titleEn, department, description, descriptionEn, city, district, type, education, status;
  final List<String> must, nice, skills;
  final int experienceMin, openings, views;
  final int? salaryMin, salaryMax;
  final bool salaryVisible, public;
  final DateTime? deadline, publishedAt, closedAt, createdAt, updatedAt;
  final List<JobQuestion> questions;
  final String? createdBy, assigneeId, draftSource, bizName, plan;
  final JobBiz? biz;
  final JobMine? mine;
  final JobCounts? counts;
  final JobMatched? matched;
  final Person? assignee;
  const Job({
    required this.id, required this.bizId, required this.title, this.titleEn = '', this.department = '', this.description = '', this.descriptionEn = '', this.city = '', this.district = '', this.type = 'full',
    this.education = 'none', this.status = 'draft', this.must = const [], this.nice = const [], this.skills = const [], this.experienceMin = 0, this.openings = 1, this.views = 0, this.salaryMin, this.salaryMax,
    this.salaryVisible = false, this.public = true, this.deadline, this.publishedAt, this.closedAt, this.createdAt, this.updatedAt, this.questions = const [], this.createdBy, this.assigneeId, this.draftSource,
    this.bizName, this.plan, this.biz, this.mine, this.counts, this.matched, this.assignee,
  });
  factory Job.fromJson(Map m) {
    final req = _m(m['requirements']);
    return Job(
      id: m['id']?.toString() ?? '', bizId: m['bizId']?.toString() ?? '', title: m['title']?.toString() ?? '', titleEn: m['titleEn']?.toString() ?? '', department: m['department']?.toString() ?? '',
      description: m['description']?.toString() ?? '', descriptionEn: m['descriptionEn']?.toString() ?? '', city: m['city']?.toString() ?? '', district: m['district']?.toString() ?? '', type: m['type']?.toString() ?? 'full',
      education: m['education']?.toString() ?? 'none', status: m['status']?.toString() ?? 'draft', must: _strings(req['must']), nice: _strings(req['nice']), skills: _strings(m['skills']),
      experienceMin: _i(m['experienceMin']), openings: _i(m['openings'], 1), views: _i(m['views']), salaryMin: _in(m['salaryMin']), salaryMax: _in(m['salaryMax']), salaryVisible: m['salaryVisible'] == true,
      public: m['public'] != false, deadline: _t(m['deadline']), publishedAt: _t(m['publishedAt']), closedAt: _t(m['closedAt']), createdAt: _t(m['createdAt']), updatedAt: _t(m['updatedAt']),
      questions: asList(m['questions']).map(JobQuestion.fromJson).toList(), createdBy: m['createdBy']?.toString(), assigneeId: m['assigneeId']?.toString(), draftSource: m['draftSource']?.toString(),
      bizName: m['bizName']?.toString(), plan: m['plan']?.toString(), biz: m['biz'] is Map ? JobBiz.fromJson(_m(m['biz'])) : null, mine: m['mine'] is Map ? JobMine.fromJson(_m(m['mine'])) : null,
      counts: m['counts'] is Map ? JobCounts.fromJson(_m(m['counts'])) : null, matched: m['matched'] is Map ? JobMatched.fromJson(_m(m['matched'])) : null, assignee: m['assignee'] is Map ? Person.fromJson(_m(m['assignee'])) : null,
    );
  }
  String get typeLabel => jobTypeLabel(type);
  String get statusLabel => jobStatusLabel(status);
  bool get isOpen => status == 'open';
  /// نص الراتب إن كان مرئياً.
  String get salaryText {
    if (salaryMin == null && salaryMax == null) return '';
    if (salaryMin != null && salaryMax != null) return '$salaryMin – $salaryMax ر.س';
    return salaryMin != null ? 'من $salaryMin ر.س' : 'حتى $salaryMax ر.س';
  }
  /// جسم التعديل/الإنشاء للخادم.
  Map<String, dynamic> toBody() => {
        'title': title, 'titleEn': titleEn, 'department': department, 'description': description, 'descriptionEn': descriptionEn, 'requirements': {'must': must, 'nice': nice}, 'skills': skills, 'city': city,
        'district': district, 'type': type, 'experienceMin': experienceMin, 'education': education, 'salaryMin': salaryMin, 'salaryMax': salaryMax, 'salaryVisible': salaryVisible, 'openings': openings,
        'deadline': deadline?.toUtc().toIso8601String(), 'public': public, 'questions': questions.map((q) => q.toJson()).toList(), if (assigneeId != null) 'assigneeId': assigneeId, if (draftSource != null) 'draftSource': draftSource,
      };
}

/// موعد مقابلة.
class JobInterview {
  final String id, mode, place, note, status;
  final DateTime? at;
  const JobInterview({required this.id, this.at, this.mode = 'onsite', this.place = '', this.note = '', this.status = 'scheduled'});
  factory JobInterview.fromJson(Map m) => JobInterview(id: m['id']?.toString() ?? '', at: _t(m['at']), mode: m['mode']?.toString() ?? 'onsite', place: m['place']?.toString() ?? '', note: m['note']?.toString() ?? '', status: m['status']?.toString() ?? 'scheduled');
  String get modeLabel => switch (mode) { 'video' => 'اتصال مرئي', 'call' => 'اتصال هاتفي', _ => 'حضوري' };
  static const modes = <String, String>{'onsite': 'حضوري', 'call': 'اتصال هاتفي', 'video': 'اتصال مرئي'};
}

/// بطاقة عرض وصلتني أو تقديمي (صندوق العروض وعروضي).
class JobMatch {
  final String id, jobId, bizId, status, stage, stageLabel, source;
  final double score;
  final List<String> reasons;
  final DateTime? sentAt, viewedAt, acceptedAt, answeredAt, declinedAt;
  final List<JobAnswer>? answers;
  final Job? job;
  final List<JobQuestion> questions;
  final Person? assignee;
  final JobInterview? interview;
  const JobMatch({
    required this.id, required this.jobId, this.bizId = '', this.status = 'sent', this.stage = 'new', this.stageLabel = '', this.source = 'match', this.score = 0, this.reasons = const [], this.sentAt, this.viewedAt,
    this.acceptedAt, this.answeredAt, this.declinedAt, this.answers, this.job, this.questions = const [], this.assignee, this.interview,
  });
  factory JobMatch.fromJson(Map m) => JobMatch(
        id: m['id']?.toString() ?? '', jobId: m['jobId']?.toString() ?? '', bizId: m['bizId']?.toString() ?? '', status: m['status']?.toString() ?? 'sent', stage: m['stage']?.toString() ?? 'new',
        stageLabel: m['stageLabel']?.toString() ?? '', source: m['source']?.toString() ?? 'match', score: _d(m['score']), reasons: _strings(m['reasons']), sentAt: _t(m['sentAt']), viewedAt: _t(m['viewedAt']),
        acceptedAt: _t(m['acceptedAt']), answeredAt: _t(m['answeredAt']), declinedAt: _t(m['declinedAt']), answers: m['answers'] is List ? asList(m['answers']).map(JobAnswer.fromJson).toList() : null,
        job: m['job'] is Map ? Job.fromJson(_m(m['job'])) : null, questions: asList(m['questions']).map(JobQuestion.fromJson).toList(), assignee: m['assignee'] is Map ? Person.fromJson(_m(m['assignee'])) : null,
        interview: m['interview'] is Map ? JobInterview.fromJson(_m(m['interview'])) : null);
  String get statusLabel => matchStatuses[status] ?? status;
  bool get pending => status == 'sent' || status == 'viewed';
  bool get needsAnswers => status == 'accepted';
  bool get answered => status == 'answered' || answeredAt != null;
  bool get closed => ['declined', 'withdrawn', 'expired'].contains(status) || ['hired', 'rejected'].contains(stage);
}

/// نتيجة القبول أو الإجابة أو التقديم: الأسئلة المطلوبة أو الشخص الذي تُفتح معه المحادثة.
class JobOfferResult {
  final String status;
  final String? matchId;
  final List<JobQuestion> questions;
  final Person? chatWith;
  const JobOfferResult({this.status = '', this.matchId, this.questions = const [], this.chatWith});
  factory JobOfferResult.fromJson(Map m) => JobOfferResult(status: m['status']?.toString() ?? '', matchId: m['matchId']?.toString(), questions: asList(m['questions']).map(JobQuestion.fromJson).toList(), chatWith: m['chatWith'] is Map ? Person.fromJson(_m(m['chatWith'])) : null);
}

/// صندوق العروض (GET /jobs/inbox) وعروضي (GET /jobs/mine).
class JobInbox {
  final List<JobMatch> items, active, history;
  final int pending;
  const JobInbox({this.items = const [], this.active = const [], this.history = const [], this.pending = 0});
  factory JobInbox.fromJson(Map m) => JobInbox(items: asList(m['items']).map(JobMatch.fromJson).toList(), active: asList(m['active']).map(JobMatch.fromJson).toList(), history: asList(m['history']).map(JobMatch.fromJson).toList(), pending: _i(m['pending']));
}

/// ملاحظة عضو فريق على مرشح.
class JobNote {
  final String id, text;
  final Person? author;
  final int? rating;
  final DateTime? createdAt;
  const JobNote({required this.id, this.text = '', this.author, this.rating, this.createdAt});
  factory JobNote.fromJson(Map m) => JobNote(id: m['id']?.toString() ?? '', text: m['text']?.toString() ?? '', author: m['author'] is Map ? Person.fromJson(_m(m['author'])) : null, rating: _in(m['rating']), createdAt: _t(m['createdAt']));
}

/// حدث في سجل المرشح.
class JobEvent {
  final String kind;
  final String? actorId;
  final Map<String, dynamic> data;
  final DateTime? at;
  const JobEvent({required this.kind, this.actorId, this.data = const {}, this.at});
  factory JobEvent.fromJson(Map m) => JobEvent(kind: m['kind']?.toString() ?? '', actorId: m['actorId']?.toString(), data: _m(m['data']), at: _t(m['at']));
  String get label => switch (kind) {
        'match.sent' => 'أُرسلت البطاقة', 'match.viewed' => 'شاهد العرض', 'match.accepted' => 'قبل العرض', 'match.declined' => 'رفض العرض', 'match.answered' => 'أجاب على الأسئلة', 'match.applied' => 'تقدّم بنفسه',
        'match.withdrawn' => 'انسحب', 'stage.changed' => 'تغيّرت المرحلة إلى ${jobStageLabel(data['to']?.toString() ?? '')}', 'note.added' => 'أُضيفت ملاحظة', 'interview.scheduled' => 'حُدّدت مقابلة',
        'interview.done' => 'تمت المقابلة', 'interview.cancelled' => 'أُلغيت المقابلة', _ => kind,
      };
}

/// مرشح في لوحة الدائرة: مجهول حتى يجيب على أسئلة الفرز.
class JobCandidate {
  final String id, jobId, label, status, stage, stageLabel, source;
  final int seq, notesCount;
  final bool anonymous;
  final double score;
  final double? rating;
  final List<String> reasons;
  final DateTime? sentAt, viewedAt, acceptedAt, answeredAt, declinedAt, updatedAt;
  final Person? assignee, user;
  final JobProfile? profile;
  final List<JobAnswer> answers;
  final List<JobInterview> interviews;
  final List<JobNote> notes;
  final List<JobEvent> events;
  const JobCandidate({
    required this.id, required this.jobId, this.label = '', this.status = 'sent', this.stage = 'new', this.stageLabel = '', this.source = 'match', this.seq = 0, this.notesCount = 0, this.anonymous = true, this.score = 0, this.rating,
    this.reasons = const [], this.sentAt, this.viewedAt, this.acceptedAt, this.answeredAt, this.declinedAt, this.updatedAt, this.assignee, this.user, this.profile, this.answers = const [], this.interviews = const [], this.notes = const [], this.events = const [],
  });
  factory JobCandidate.fromJson(Map m) => JobCandidate(
        id: m['id']?.toString() ?? '', jobId: m['jobId']?.toString() ?? '', label: m['label']?.toString() ?? '', status: m['status']?.toString() ?? 'sent', stage: m['stage']?.toString() ?? 'new', stageLabel: m['stageLabel']?.toString() ?? '',
        source: m['source']?.toString() ?? 'match', seq: _i(m['seq']), notesCount: _i(m['notesCount']), anonymous: m['anonymous'] != false, score: _d(m['score']), rating: m['rating'] == null ? null : _d(m['rating']), reasons: _strings(m['reasons']),
        sentAt: _t(m['sentAt']), viewedAt: _t(m['viewedAt']), acceptedAt: _t(m['acceptedAt']), answeredAt: _t(m['answeredAt']), declinedAt: _t(m['declinedAt']), updatedAt: _t(m['updatedAt']),
        assignee: m['assignee'] is Map ? Person.fromJson(_m(m['assignee'])) : null, user: m['user'] is Map ? Person.fromJson(_m(m['user'])) : null, profile: m['profile'] is Map ? JobProfile.fromJson(_m(m['profile'])) : null,
        answers: asList(m['answers']).map(JobAnswer.fromJson).toList(), interviews: asList(m['interviews']).map(JobInterview.fromJson).toList(), notes: asList(m['notes']).map(JobNote.fromJson).toList(), events: asList(m['events']).map(JobEvent.fromJson).toList());
  String get name => anonymous || user == null ? label : (user!.nickname.isNotEmpty ? user!.nickname : label);
  int get scorePct => (score * 100).round();
  JobInterview? get nextInterview { final s = interviews.where((i) => i.status == 'scheduled').toList()..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0))); return s.isEmpty ? null : s.first; }
}

/// مرحلة مع عددها في لوحة المرشحين.
class JobStageCount {
  final String id, label;
  final int n;
  const JobStageCount({required this.id, required this.label, this.n = 0});
  factory JobStageCount.fromJson(Map m) => JobStageCount(id: m['id']?.toString() ?? '', label: m['label']?.toString() ?? '', n: _i(m['n']));
}

/// لوحة مرشحي عرض.
class JobCandidates {
  final Job? job;
  final List<JobCandidate> items;
  final JobCounts counts;
  final List<JobStageCount> stages;
  const JobCandidates({this.job, this.items = const [], this.counts = const JobCounts(), this.stages = const []});
  factory JobCandidates.fromJson(Map m) => JobCandidates(job: m['job'] is Map ? Job.fromJson(_m(m['job'])) : null, items: asList(m['items']).map(JobCandidate.fromJson).toList(), counts: JobCounts.fromJson(_m(m['counts'])), stages: asList(m['stages']).map(JobStageCount.fromJson).toList());
}

/// باقة التوظيف للدائرة.
class JobPlan {
  final String plan;
  final DateTime? until;
  final int freeActive, active;
  const JobPlan({this.plan = 'free', this.until, this.freeActive = 3, this.active = 0});
  factory JobPlan.fromJson(Map m) => JobPlan(plan: m['plan']?.toString() ?? 'free', until: _t(m['until']), freeActive: _i(m['freeActive'], 3), active: _i(m['active']));
  bool get pro => plan == 'pro';
  bool get atLimit => !pro && active >= freeActive;
}

/// لوحة التوظيف في الدائرة (GET /biz/:id/manage/jobs).
class JobsBoard {
  final List<Job> items;
  final JobPlan plan;
  final List<Person> team;
  final String role;
  final bool enabled, requireApproval, aiAvailable;
  final int upcomingInterviews;
  const JobsBoard({this.items = const [], this.plan = const JobPlan(), this.team = const [], this.role = '', this.enabled = true, this.requireApproval = false, this.aiAvailable = false, this.upcomingInterviews = 0});
  factory JobsBoard.fromJson(Map m) => JobsBoard(
        items: asList(m['items']).map(Job.fromJson).toList(), plan: JobPlan.fromJson(_m(m['plan'])), team: asList(m['team']).map(Person.fromJson).toList(), role: m['role']?.toString() ?? '', enabled: m['enabled'] != false,
        requireApproval: m['requireApproval'] == true, aiAvailable: m['aiAvailable'] == true, upcomingInterviews: _i(m['upcomingInterviews']));
}

/// مسودة من محرك الصياغة (ai أو template).
class JobDraft {
  final String source, title, titleEn, description, descriptionEn;
  final List<String> must, nice, skills;
  final List<JobQuestion> questions;
  final String? aiError;
  const JobDraft({this.source = 'template', this.title = '', this.titleEn = '', this.description = '', this.descriptionEn = '', this.must = const [], this.nice = const [], this.skills = const [], this.questions = const [], this.aiError});
  factory JobDraft.fromJson(Map m) {
    final req = _m(m['requirements']);
    return JobDraft(
        source: m['source']?.toString() ?? 'template', title: m['title']?.toString() ?? '', titleEn: m['titleEn']?.toString() ?? '', description: m['description']?.toString() ?? '', descriptionEn: m['descriptionEn']?.toString() ?? '',
        must: _strings(req['must']), nice: _strings(req['nice']), skills: _strings(m['skills']), questions: asList(m['questions']).map(JobQuestion.fromJson).toList(), aiError: m['aiError']?.toString());
  }
  bool get fromAi => source == 'ai';
}

/// معاينة المطابقة (أعداد فقط).
class JobPreview {
  final int strong, good, weak, profiles;
  final double threshold;
  const JobPreview({this.strong = 0, this.good = 0, this.weak = 0, this.profiles = 0, this.threshold = .45});
  factory JobPreview.fromJson(Map m) => JobPreview(strong: _i(m['strong']), good: _i(m['good']), weak: _i(m['weak']), profiles: _i(m['profiles']), threshold: _d(m['threshold'], .45));
  int get reach => strong + good;
}

/// قمع عرض واحد.
class JobFunnelStep {
  final String id, label;
  final int n;
  const JobFunnelStep({required this.id, required this.label, this.n = 0});
  factory JobFunnelStep.fromJson(Map m) => JobFunnelStep(id: m['id']?.toString() ?? '', label: m['label']?.toString() ?? '', n: _i(m['n']));
}

class JobStats {
  final Job? job;
  final List<JobFunnelStep> funnel;
  final double? avgDaysToAnswer, avgHoursToView;
  final int views;
  final List<({String reason, int n})> declines;
  final Map<String, int> byStage;
  const JobStats({this.job, this.funnel = const [], this.avgDaysToAnswer, this.avgHoursToView, this.views = 0, this.declines = const [], this.byStage = const {}});
  factory JobStats.fromJson(Map m) => JobStats(
        job: m['job'] is Map ? Job.fromJson(_m(m['job'])) : null, funnel: asList(m['funnel']).map(JobFunnelStep.fromJson).toList(), avgDaysToAnswer: m['avgDaysToAnswer'] == null ? null : _d(m['avgDaysToAnswer']),
        avgHoursToView: m['avgHoursToView'] == null ? null : _d(m['avgHoursToView']), views: _i(m['views']), declines: asList(m['declines']).map((d) => (reason: d['reason']?.toString() ?? '', n: _i(d['n']))).toList(),
        byStage: {for (final e in _m(m['byStage']).entries) e.key: _i(e.value)});
}

/// إحصاءات التوظيف للدائرة كلها.
class JobsOverview {
  final int open, filled, candidates, answered, hired, upcomingInterviews;
  final JobPlan plan;
  const JobsOverview({this.open = 0, this.filled = 0, this.candidates = 0, this.answered = 0, this.hired = 0, this.upcomingInterviews = 0, this.plan = const JobPlan()});
  factory JobsOverview.fromJson(Map m) => JobsOverview(open: _i(m['open']), filled: _i(m['filled']), candidates: _i(m['candidates']), answered: _i(m['answered']), hired: _i(m['hired']), upcomingInterviews: _i(m['upcomingInterviews']), plan: JobPlan.fromJson(_m(m['plan'])));
}

/// قائمة الوظائف العامة مع الفلاتر المتاحة.
class JobsList {
  final List<Job> items;
  final List<String> cities;
  const JobsList({this.items = const [], this.cities = const []});
  factory JobsList.fromJson(Map m) => JobsList(items: asList(m['items']).map(Job.fromJson).toList(), cities: _strings(m['cities']));
}

/// دائرة توظّف الآن (للخريطة).
class HiringBiz {
  final String bizId;
  final int open;
  const HiringBiz({required this.bizId, this.open = 0});
  factory HiringBiz.fromJson(Map m) => HiringBiz(bizId: m['bizId']?.toString() ?? '', open: _i(m['open']));
}

/// قائمة الإدارة العامة للوظائف.
class AdminJobs {
  final List<Job> items;
  final int open, pending, seekers, hired;
  final bool jobsEnabled, jobsRequireApproval;
  final int jobsFreeActive, jobsWeeklyCap;
  final double jobsMinScore;
  const AdminJobs({this.items = const [], this.open = 0, this.pending = 0, this.seekers = 0, this.hired = 0, this.jobsEnabled = true, this.jobsRequireApproval = false, this.jobsFreeActive = 3, this.jobsWeeklyCap = 5, this.jobsMinScore = .45});
  factory AdminJobs.fromJson(Map m) {
    final t = _m(m['totals']), s = _m(m['settings']);
    return AdminJobs(items: asList(m['items']).map(Job.fromJson).toList(), open: _i(t['open']), pending: _i(t['pending']), seekers: _i(t['seekers']), hired: _i(t['hired']), jobsEnabled: s['jobsEnabled'] != false,
        jobsRequireApproval: s['jobsRequireApproval'] == true, jobsFreeActive: _i(s['jobsFreeActive'], 3), jobsWeeklyCap: _i(s['jobsWeeklyCap'], 5), jobsMinScore: _d(s['jobsMinScore'], .45));
  }
}
