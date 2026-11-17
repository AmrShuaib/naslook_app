import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';

/// اسم الميزة في موافقة الذكاء الاصطناعي (server/profile_voice.js).
const profileVoiceFeature = 'profile_voice';

/// حالة «عرّف بنفسك بالصوت» للحساب: هل المساعد مضبوط، وهل وافق المستخدم، وحدود النص.
class VoiceFillStatus {
  final bool available, consented;
  final int minChars, maxChars, maxSec;
  const VoiceFillStatus({required this.available, this.consented = false, this.minChars = 20, this.maxChars = 1500, this.maxSec = 60});
  factory VoiceFillStatus.fromJson(Map m) {
    final l = m['limits'] is Map ? m['limits'] as Map : const {};
    int n(String k, int d) => (l[k] as num?)?.toInt() ?? d;
    return VoiceFillStatus(available: m['available'] == true, consented: m['consented'] == true, minChars: n('minChars', 20), maxChars: n('maxChars', 1500), maxSec: n('maxSec', 60));
  }
  VoiceFillStatus copyWith({bool? consented}) => VoiceFillStatus(available: available, consented: consented ?? this.consented, minChars: minChars, maxChars: maxChars, maxSec: maxSec);
}

/// رابط تواصل استُخرج من الكلام (النوع من أنواع الملف، والقيمة اسم الحساب أو الموقع).
class VoiceFillLink {
  final String kind, value;
  const VoiceFillLink(this.kind, this.value);

  /// اسم الحقل في [VoiceFillResult.unsure] ومفتاح شارته في الشاشة.
  String get field => 'links.$kind';
}

/// ما وزّعه الخادم من كلام المستخدم على حقول ملفه، للمراجعة فقط: لا شيء منه محفوظ. الحقل الغائب null (لم يُذكر).
class VoiceFillResult {
  final String? displayName, bio, jobTitle, city, district;
  final List<String> skills;
  final List<VoiceFillLink> links;

  /// حقول يطلب الخادم التأكد من كتابتها (أسماء الحسابات خصوصاً).
  final Set<String> unsure;
  const VoiceFillResult({this.displayName, this.bio, this.jobTitle, this.city, this.district, this.skills = const [], this.links = const [], this.unsure = const {}});

  factory VoiceFillResult.fromJson(Map m) {
    final f = m['fields'] is Map ? m['fields'] as Map : const {};
    String? s(String k) {
      final v = f[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return VoiceFillResult(
      displayName: s('displayName'),
      bio: s('bio'),
      jobTitle: s('jobTitle'),
      city: s('city'),
      district: s('district'),
      skills: [for (final x in (f['skills'] as List? ?? const [])) if (x is String && x.trim().isNotEmpty) x.trim()],
      links: [for (final x in (f['links'] as List? ?? const [])) if (x is Map && x['kind'] is String && x['value'] is String && (x['value'] as String).trim().isNotEmpty) VoiceFillLink(x['kind'] as String, (x['value'] as String).trim())],
      unsure: {for (final x in (m['unsure'] as List? ?? const [])) if (x is String) x},
    );
  }

  bool get isEmpty => displayName == null && bio == null && jobTitle == null && city == null && district == null && skills.isEmpty && links.isEmpty;
}

/// مسارات «عرّف بنفسك بالصوت» (server/profile_voice.js).
extension ProfileVoiceApi on ApiClient {
  Future<VoiceFillStatus> profileVoiceStatus() async => VoiceFillStatus.fromJson(await get('/me/profile/voice/status'));

  /// موافقة المستخدم على إرسال نصه إلى المساعد الذكي لهذه الميزة.
  Future<void> giveAiConsent(String feature, {String source = 'app'}) => post('/me/ai-consent', {'feature': feature, 'source': source});

  /// سحب الموافقة: الطلب التالي يُرفض حتى يوافق من جديد.
  Future<void> withdrawAiConsent(String feature) => delete('/me/ai-consent?feature=${Uri.encodeQueryComponent(feature)}');

  /// يوزّع النص على حقول الملف ويعيدها للمراجعة. النداء قد يأخذ نصف دقيقة، فمهلته أطول من مهلة الطلبات العادية.
  Future<VoiceFillResult> profileVoiceFill(String text) async {
    final body = Uint8List.fromList(utf8.encode(jsonEncode({'text': text})));
    return VoiceFillResult.fromJson(await postBytes('/me/profile/voice', body, contentType: 'application/json', timeout: const Duration(seconds: 45)));
  }
}

/// نص عربي لخطأ الميزة بحسب رمز الخادم.
String profileVoiceErrText(Object e) {
  const generic = 'تعذّر ترتيب كلامك الآن. أعد المحاولة أو اكتب الحقول بنفسك.';
  if (e is! ApiException) return generic;
  if (e.isNetwork) return e.message.contains('مهلة') ? 'أخذ الترتيب وقتاً طويلاً. أعد المحاولة.' : 'تعذّر الاتصال. تحقق من الإنترنت ثم أعد المحاولة.';
  switch ((e.body?['error'] ?? '').toString()) {
    case 'text-too-short':
      return 'الكلام قصير. اذكر اسمك وما تعمله ومدينتك على الأقل.';
    case 'text-too-long':
      return 'الكلام طويل. اختصره ثم أعد المحاولة.';
    case 'ai-consent-required':
      return 'نحتاج موافقتك قبل إرسال كلامك إلى المساعد الذكي. أغلق وافتح «عرّف بنفسك بالصوت» من جديد.';
    case 'ai-unavailable':
      return 'المساعد الذكي غير مفعّل الآن. اكتب الحقول بنفسك.';
    case 'busy':
      return 'الخدمة مشغولة اليوم. أعد المحاولة غداً أو اكتب الحقول بنفسك.';
    case 'rate-limited':
      if (e.body?['scope'] == 'day') return 'بلغت حد اليوم من المحاولات. أعد المحاولة غداً أو اكتب الحقول بنفسك.';
      final sec = (e.body?['retryAfterSec'] as num?)?.toInt() ?? 3600;
      return 'محاولات كثيرة. أعد المحاولة بعد ${(sec / 60).ceil()} دقيقة.';
    case 'in-progress':
      return 'طلب سابق ما زال جارياً. انتظر قليلاً.';
    case 'ai-timeout':
      return 'أخذ الترتيب وقتاً طويلاً. أعد المحاولة.';
    case 'suspended':
      return 'هذا الحساب موقوف. راسل الدعم.';
  }
  return generic;
}
