import 'models.dart';

/// نماذج الملف الشخصي v2 (server/profile_v2.js): الغلاف والاسم المعروض والمسمى والمدينة والروابط، التعريف الصوتي أو
/// المرئي، الأرقام، شارات الثقة، أعلام الزائر، إعدادات التحكم واكتمال الملف. كل التحويل من JSON متسامح مع النقص.

String _s(Map m, String k, [String d = '']) => m[k]?.toString() ?? d;
String? _sn(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}
int _i(Map m, String k, [int d = 0]) => m[k] is num ? (m[k] as num).toInt() : int.tryParse(m[k]?.toString() ?? '') ?? d;
double? _dn(Map m, String k) => m[k] is num ? (m[k] as num).toDouble() : double.tryParse(m[k]?.toString() ?? '');
bool _b(Map m, String k, [bool d = false]) => m[k] is bool ? m[k] as bool : d;
bool? _bn(Map m, String k) => m[k] is bool ? m[k] as bool : null;
DateTime? _t(Map m, String k) => m[k] == null ? null : DateTime.tryParse(m[k].toString())?.toLocal();

/// أنواع الروابط المسموحة وتسمياتها.
const profileLinkKinds = {'instagram': 'إنستغرام', 'x': 'X', 'tiktok': 'تيك توك', 'snapchat': 'سناب شات', 'website': 'موقع', 'other': 'رابط'};

/// رابط تعريفي في الملف (حتى ثلاثة).
class ProfileLink {
  final String kind, value, url;
  const ProfileLink({required this.kind, required this.value, this.url = ''});
  factory ProfileLink.fromJson(Map m) => ProfileLink(kind: profileLinkKinds.containsKey(_s(m, 'kind')) ? _s(m, 'kind') : 'other', value: _s(m, 'value'), url: _s(m, 'url'));
  Map<String, dynamic> toJson() => {'kind': kind, 'value': value};
  String get kindLabel => profileLinkKinds[kind] ?? 'رابط';
  /// النص المعروض: اسم الحساب للشبكات، والنطاق بلا بروتوكول للمواقع.
  String get label => value.replaceFirst(RegExp(r'^https?://(www\.)?'), '').replaceFirst(RegExp(r'/+$'), '');
  /// الرابط الفعلي: ما بناه الخادم، وإلا نبنيه محلياً بالقاعدة نفسها.
  String get href {
    if (url.isNotEmpty) return url;
    final v = value.replaceFirst(RegExp(r'^@'), '');
    return switch (kind) {
      'instagram' => 'https://instagram.com/$v',
      'x' => 'https://x.com/$v',
      'tiktok' => 'https://tiktok.com/@$v',
      'snapchat' => 'https://snapchat.com/add/$v',
      _ => v.startsWith('http') ? v : 'https://$v',
    };
  }
}

/// «عرّف بنفسك»: تسجيل صوتي حتى 60 ثانية أو فيديو حتى 30 ثانية.
class ProfileIntro {
  final String kind, url;
  final int sec;
  final DateTime? at;
  const ProfileIntro({required this.kind, required this.url, this.sec = 0, this.at});
  static ProfileIntro? fromJsonOrNull(dynamic v) {
    if (v is! Map || _s(v, 'url').isEmpty) return null;
    return ProfileIntro(kind: _s(v, 'kind') == 'video' ? 'video' : 'voice', url: _s(v, 'url'), sec: _i(v, 'sec'), at: _t(v, 'at'));
  }
  bool get isVideo => kind == 'video';
  String get durationText => clockText(sec);
}

/// «0:42» من عدد الثوانٍ.
String clockText(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// «مارس 2025».
String monthYear(DateTime? t) => t == null ? '' : '${_months[t.month - 1]} ${t.year}';

class ProfileStats {
  final int posts, followers, following, circles, ratingCount, completedOrders, friends;
  final double? ratingAvg;
  const ProfileStats({this.posts = 0, this.followers = 0, this.following = 0, this.circles = 0, this.ratingAvg, this.ratingCount = 0, this.completedOrders = 0, this.friends = 0});
  factory ProfileStats.fromJson(Map m) => ProfileStats(
        posts: _i(m, 'posts'), followers: _i(m, 'followers'), following: _i(m, 'following'), circles: _i(m, 'circles'),
        ratingAvg: _dn(m, 'ratingAvg'), ratingCount: _i(m, 'ratingCount'), completedOrders: _i(m, 'completedOrders'), friends: _i(m, 'friends'));
  ProfileStats copyWith({int? followers}) => ProfileStats(posts: posts, followers: followers ?? this.followers, following: following, circles: circles, ratingAvg: ratingAvg, ratingCount: ratingCount, completedOrders: completedOrders, friends: friends);
}

class ProfileTrust {
  final bool emailVerified, phoneVerified;
  final DateTime? memberSince;
  final bool? respondsFast;
  const ProfileTrust({this.emailVerified = false, this.phoneVerified = false, this.memberSince, this.respondsFast});
  factory ProfileTrust.fromJson(Map m) => ProfileTrust(emailVerified: _b(m, 'emailVerified'), phoneVerified: _b(m, 'phoneVerified'), memberSince: _t(m, 'memberSince'), respondsFast: _bn(m, 'respondsFast'));
}

class ProfileFlags {
  final bool isMe, isFollowing, isFriend, canMessage, isPrivate, blocked;
  final bool? online;
  const ProfileFlags({this.isMe = false, this.isFollowing = false, this.isFriend = false, this.canMessage = true, this.online, this.isPrivate = false, this.blocked = false});
  factory ProfileFlags.fromJson(Map m) => ProfileFlags(
        isMe: _b(m, 'isMe'), isFollowing: _b(m, 'isFollowing'), isFriend: _b(m, 'isFriend'), canMessage: _b(m, 'canMessage', true), online: _bn(m, 'online'), isPrivate: _b(m, 'isPrivate'), blocked: _b(m, 'blocked'));
  ProfileFlags copyWith({bool? isFollowing}) => ProfileFlags(isMe: isMe, isFollowing: isFollowing ?? this.isFollowing, isFriend: isFriend, canMessage: canMessage, online: online, isPrivate: isPrivate, blocked: blocked);
}

/// إعدادات التحكم (لصاحب الحساب فقط).
class ProfileSettings {
  final String msgPolicy, introVisibility;
  final bool showOnline, showCity, showFriends;
  const ProfileSettings({this.msgPolicy = 'all', this.introVisibility = 'all', this.showOnline = true, this.showCity = true, this.showFriends = false});
  factory ProfileSettings.fromJson(Map m) => ProfileSettings(
        msgPolicy: const ['all', 'friends', 'none'].contains(_s(m, 'msgPolicy')) ? _s(m, 'msgPolicy') : 'all',
        introVisibility: _s(m, 'introVisibility') == 'friends' ? 'friends' : 'all',
        showOnline: _b(m, 'showOnline', true), showCity: _b(m, 'showCity', true), showFriends: _b(m, 'showFriends'));
  ProfileSettings copyWith({String? msgPolicy, String? introVisibility, bool? showOnline, bool? showCity, bool? showFriends}) => ProfileSettings(
      msgPolicy: msgPolicy ?? this.msgPolicy, introVisibility: introVisibility ?? this.introVisibility, showOnline: showOnline ?? this.showOnline, showCity: showCity ?? this.showCity, showFriends: showFriends ?? this.showFriends);
}

/// خطوة في اكتمال الملف: avatar | cover | bio | links | intro | email | skills.
class CompletionStep {
  final String id, label;
  final bool done;
  const CompletionStep({required this.id, required this.label, this.done = false});
  factory CompletionStep.fromJson(Map m) => CompletionStep(id: _s(m, 'id'), label: _s(m, 'label', _defaultLabels[_s(m, 'id')] ?? ''), done: _b(m, 'done'));
  static const _defaultLabels = {'avatar': 'أضف صورة', 'cover': 'أضف غلافاً', 'bio': 'اكتب نبذة', 'links': 'أضف رابطاً واحداً على الأقل', 'intro': 'عرّف بنفسك بصوتك أو بفيديو', 'email': 'وثّق بريدك', 'skills': 'أضف مهاراتك'};
}

class ProfileCompletion {
  final int pct;
  final List<CompletionStep> steps;
  const ProfileCompletion({this.pct = 0, this.steps = const []});
  factory ProfileCompletion.fromJson(Map m) => ProfileCompletion(pct: _i(m, 'pct').clamp(0, 100), steps: asList(m['steps']).map(CompletionStep.fromJson).toList());
  int get remaining => steps.where((s) => !s.done).length;
}

/// إحصاءات آخر سبعة أيام لصاحب الحساب (GET /me/profile/stats).
class ProfileStats7 {
  final int visits7, visits7Prev, messages7, follows7, shares7;
  final List<({String day, int visits})> series;
  const ProfileStats7({this.visits7 = 0, this.visits7Prev = 0, this.messages7 = 0, this.follows7 = 0, this.shares7 = 0, this.series = const []});
  factory ProfileStats7.fromJson(Map m) => ProfileStats7(
        visits7: _i(m, 'visits7'), visits7Prev: _i(m, 'visits7Prev'), messages7: _i(m, 'messages7'), follows7: _i(m, 'follows7'), shares7: _i(m, 'shares7'),
        series: [for (final e in asList(m['series'])) (day: _s(e, 'day'), visits: _i(e, 'visits'))]);
  /// نسبة التغيّر عن الأسبوع السابق، أو null إن لم يكن هناك أساس للمقارنة.
  int? get visitsDeltaPct => visits7Prev <= 0 ? null : (((visits7 - visits7Prev) / visits7Prev) * 100).round();
}

/// رد فحص اسم المستخدم (GET /handles/check).
class HandleCheck {
  final bool valid, available;
  final String? reason;
  const HandleCheck({this.valid = false, this.available = false, this.reason});
  factory HandleCheck.fromJson(Map m) => HandleCheck(valid: _b(m, 'valid'), available: _b(m, 'available'), reason: _sn(m, 'reason'));
  String get text => available ? 'متاح' : switch (reason) { 'short' => 'قصير جداً (3 أحرف على الأقل)', 'chars' => 'حروف إنجليزية صغيرة وأرقام ونقطة و _ فقط', _ => 'الاسم محجوز' };
}

/// رد المتابعة وإلغائها.
class FollowResult {
  final bool following;
  final int followers;
  const FollowResult({required this.following, required this.followers});
  factory FollowResult.fromJson(Map m) => FollowResult(following: _b(m, 'following'), followers: _i(m, 'followers'));
}

/// الملف الشخصي كما يراه الزائر، ومع [settings] و[completion] لصاحب الحساب.
class ProfileV2 {
  final String id, nickname, displayName, bio, accountType, jobTitle, city, district;
  final String? avatarUrl, coverUrl;
  final List<ProfileLink> links;
  final ProfileIntro? intro;
  final ProfileStats stats;
  final ProfileTrust trust;
  final ProfileFlags flags;
  final ProfileSettings? settings;
  final ProfileCompletion? completion;
  final DateTime? memberSince;
  const ProfileV2({
    required this.id, required this.nickname, this.displayName = '', this.avatarUrl, this.coverUrl, this.bio = '', this.accountType = 'personal', this.jobTitle = '', this.city = '', this.district = '',
    this.links = const [], this.intro, this.stats = const ProfileStats(), this.trust = const ProfileTrust(), this.flags = const ProfileFlags(), this.settings, this.completion, this.memberSince,
  });

  factory ProfileV2.fromJson(Map m) => ProfileV2(
        id: _s(m, 'id'), nickname: _s(m, 'nickname'), displayName: _s(m, 'displayName'), avatarUrl: _sn(m, 'avatarUrl'), coverUrl: _sn(m, 'coverUrl'), bio: _s(m, 'bio'),
        accountType: _s(m, 'accountType') == 'pro' ? 'pro' : 'personal', jobTitle: _s(m, 'jobTitle'), city: _s(m, 'city'), district: _s(m, 'district'),
        links: asList(m['links']).map(ProfileLink.fromJson).where((l) => l.value.isNotEmpty).take(3).toList(),
        intro: ProfileIntro.fromJsonOrNull(m['intro']),
        stats: ProfileStats.fromJson(asMap(m['stats'])), trust: ProfileTrust.fromJson(asMap(m['trust'])), flags: ProfileFlags.fromJson(asMap(m['flags'])),
        settings: m['settings'] is Map ? ProfileSettings.fromJson(asMap(m['settings'])) : null,
        completion: m['completion'] is Map ? ProfileCompletion.fromJson(asMap(m['completion'])) : null,
        memberSince: _t(m, 'memberSince') ?? _t(asMap(m['trust']), 'memberSince'),
      );

  /// الاسم الظاهر: الاسم المعروض وإلا النك نيم.
  String get name => displayName.isNotEmpty ? displayName : nickname;
  bool get isPro => accountType == 'pro';
  /// «جدة · الشاطئ» أو المدينة وحدها.
  String get place => [city, district].where((s) => s.isNotEmpty).join(' · ');
  DateTime? get since => memberSince ?? trust.memberSince;

  ProfileV2 copyWith({ProfileFlags? flags, ProfileStats? stats, ProfileIntro? intro, bool clearIntro = false, ProfileSettings? settings}) => ProfileV2(
        id: id, nickname: nickname, displayName: displayName, avatarUrl: avatarUrl, coverUrl: coverUrl, bio: bio, accountType: accountType, jobTitle: jobTitle, city: city, district: district, links: links,
        intro: clearIntro ? null : (intro ?? this.intro), stats: stats ?? this.stats, trust: trust, flags: flags ?? this.flags, settings: settings ?? this.settings, completion: completion, memberSince: memberSince);
}

/// المدن والأحياء المتاحة في شاشة التعديل.
const profileCities = <String, List<String>>{
  'جدة': ['الشاطئ', 'الحمراء', 'الروضة', 'أبحر الشمالية', 'أبحر الجنوبية', 'السلامة', 'التحلية', 'البلد', 'الصفا', 'النعيم', 'الزهراء', 'الخالدية', 'المرجان', 'النهضة', 'الفيصلية', 'الربوة'],
  'الدمام': ['الشاطئ', 'الفيصلية', 'الريان', 'العزيزية', 'الفردوس', 'الجلوية', 'المزروعية', 'الناصرية', 'الضباب', 'أحد'],
};
