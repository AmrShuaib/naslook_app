import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../core/platform.dart' as platform;
import 'session.dart';

/// خطأ قادم من الخادم أو من الشبكة.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  const ApiException(this.statusCode, this.message, {this.body});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// عميل HTTP لخادم Naslife (Node/Fastify).
///
/// المصادقة بالنك نيم + الرقم السري بدون أي تشفير من جهة العميل:
/// يُرسل الزوج كما هو في JSON، ويرد الخادم برمز جلسة (token) يُرسل لاحقاً
/// في ترويسة `Authorization: Bearer <token>`.
///
/// عنوان الخادم:
///  - يمكن تمريره عبر `--dart-define=NASLIFE_API_BASE=https://...`
///  - وإلا، على الويب يُستخدم نفس الأصل الذي يُقدَّم منه التطبيق (naslife.app)
///  - وإلا `https://naslife.app`.
class ApiClient {
  static const _envBase = String.fromEnvironment('NASLIFE_API_BASE');
  static const defaultBase = 'https://naslife.app';

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  /// رمز الجلسة في صندوق مشترك بين العميل الأصلي ونُسخه (ApiClient.view) حتى يظل الرمز واحداً مهما تعدّدت النسخ.
  final _TokenBox _box;
  String? get _token => _box.value;

  /// يُستدعى عند رفض الخادم طلباً لزائر بلا جلسة (401)؛ تعيّنه واجهة الزائر لعرض الدخول.
  static void Function()? onUnauthorized;

  ApiClient({String? baseUrl, http.Client? httpClient, this.timeout = const Duration(seconds: 20)})
      : baseUrl = _normalize(baseUrl ?? resolveBaseUrl()),
        _http = httpClient ?? http.Client(),
        _box = _TokenBox() {
    _currentBase = this.baseUrl;
  }

  /// نسخة تشارك [base] الاتصال ورمز الجلسة نفسيهما لكنها كائن مختلف: تُنشأ مع كل تبديل حساب حتى تُعاد بناء مزوّدات
  /// البيانات التي تعتمد عليها (Riverpod لا يعيد البناء حين تبقى القيمة الكائن نفسه).
  ApiClient.view(ApiClient base)
      : baseUrl = base.baseUrl,
        _http = base._http,
        timeout = base.timeout,
        _box = base._box;

  static String? _currentBase;
  /// أصل الخادم الذي تُطلب منه الوسائط (آخر عميل أُنشئ، وإلا الأصل المستنتج)
  static String get mediaBase => _currentBase ?? _normalize(resolveBaseUrl());

  static String resolveBaseUrl() {
    if (_envBase.isNotEmpty) return _envBase;
    if (kIsWeb) {
      final origin = Uri.base.origin;
      // أثناء التطوير المحلي (flutter run) نتجه للخادم الفعلي.
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return defaultBase;
      }
      return origin;
    }
    return defaultBase;
  }

  static String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  String? get token => _box.value;
  set token(String? value) => _box.value = (value == null || value.isEmpty) ? null : value;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return u;
    final q = Map<String, String>.from(query)..removeWhere((k, v) => v.isEmpty);
    return u.replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> _headers({bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        // خادم Naslife يقرأ رمز الجلسة من ترويسة x-token
        if (_token != null) 'x-token': _token!,
        if (_token != null) 'Authorization': 'Bearer $_token',
        ...clientHeaders(),
      };

  /// ترويسة تعريف العميل: التطبيقات الأصلية فقط (الخادم يمنع فيها شراء سبوت لايت وأدوات المال؛ انظر core/platform.dart).
  /// الويب لا يرسلها لأن ترويسة مخصّصة تفرض طلب CORS تمهيدياً بلا فائدة.
  static Map<String, String> clientHeaders() {
    final tag = platform.clientHeader;
    return tag == null ? const {} : {'x-naslife-client': tag};
  }

  // ---------------------------------------------------------------------------
  // المصادقة
  // ---------------------------------------------------------------------------

  /// تسجيل حساب جديد بالبريد الإلكتروني + اسم المستخدم + كلمة السر عبر إضافة الحسابات بالبريد (server/auth_alias.js)؛
  /// وإن لم تكن منشورة على الخادم نرجع إلى مسار النواة /register بالنك نيم فقط.
  Future<Session> register({required String nickname, required String pin, String? email, bool acceptTerms = false}) async {
    Map<String, dynamic> data;
    if (email != null && email.trim().isNotEmpty) {
      try {
        data = await post('/auth/register', {'email': email.trim().toLowerCase(), 'nickname': nickname.trim(), 'password': pin.trim(), if (acceptTerms) 'acceptTerms': true});
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        data = await post('/register', {'nickname': nickname.trim(), 'password': pin.trim()});
      }
    } else {
      data = await post('/register', {'nickname': nickname.trim(), 'password': pin.trim()});
    }
    final session = Session.fromJson(data);
    if (!session.isValid) {
      throw ApiException(500, 'الخادم لم يُرجع رمز جلسة', body: data);
    }
    token = session.token;
    return session;
  }

  /// هل اسم المستخدم متاح؟ (server/auth_alias.js) يعيد null إن لم يكن الخادم يدعم الفحص.
  Future<bool?> nicknameAvailable(String nickname) async {
    try {
      final r = await get('/auth/nickname-available', query: {'nickname': nickname.trim().toLowerCase()});
      return r['available'] == true;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// نسيت كلمة السر: يطلب إرسال رمز إلى البريد (الرد عام دائماً كي لا يُكشف وجود الحساب).
  Future<void> forgotPassword(String email) => post('/auth/forgot', {'email': email.trim().toLowerCase()});

  /// يعيّن كلمة سر جديدة بالرمز الذي وصل بالبريد ويعيد جلسة دخول.
  Future<Session> resetPassword({required String email, required String code, required String password}) async {
    final data = await post('/auth/reset', {'email': email.trim().toLowerCase(), 'code': code.trim(), 'password': password});
    final session = Session.fromJson(data);
    if (!session.isValid) throw ApiException(500, 'الخادم لم يُرجع رمز جلسة', body: data);
    token = session.token;
    return session;
  }

  /// تغيير كلمة السر للمستخدم الحالي بكلمة السر الحالية؛ يعيد رمز الجلسة الجديد إن أصدرته النواة ويعتمده.
  Future<String?> changePassword({required String current, required String next}) async {
    final r = await post('/auth/change-password', {'current': current, 'password': next});
    final t = r['token']?.toString();
    if (t != null && t.isNotEmpty) token = t;
    return t;
  }

  /// الدخول بالنك نيم أو البريد + الرقم السري: عبر إضافة الدخول بالبريد (server/auth_alias.js)، وإن لم تكن
  /// منشورة على الخادم نرجع إلى مسار النواة /login بالنك نيم.
  Future<Session> login({required String nickname, required String pin}) async {
    final body = {'handle': nickname.trim(), 'password': pin.trim()};
    Map<String, dynamic> data;
    try {
      data = await post('/auth/login', body);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      data = await post('/login', body);
    }
    final session = Session.fromJson(data);
    if (!session.isValid) {
      throw ApiException(500, 'الخادم لم يُرجع رمز جلسة', body: data);
    }
    token = session.token;
    return session;
  }

  /// بيانات المستخدم الحالي (للتحقق من صلاحية الجلسة المحفوظة).
  Future<SessionUser> me() async {
    final data = await get('/me');
    final raw = data['user'];
    final userJson = raw is Map ? Map<String, dynamic>.from(raw) : data;
    return SessionUser.fromJson(userJson);
  }

  /// إنهاء الجلسة على الخادم (يتجاهل الأخطاء؛ الجلسة المحلية تُمسح دائماً).
  Future<void> logout() async {
    try {
      await post('/logout', const {});
    } catch (_) {
      // لا شيء
    } finally {
      token = null;
    }
  }

  // ---------------------------------------------------------------------------
  // طلبات عامة
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers(json: false)), prompt: false);

  /// [prompt] false للطلبات الخلفية (تسجيل مشاهدة أو نقرة): رفضها لزائر لا يفتح دعوة الدخول.
  Future<Map<String, dynamic>> post(String path, Object body, {bool prompt = true}) => _send(
        () => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body)),
        prompt: prompt,
      );

  Future<Map<String, dynamic>> put(String path, Object body) => _send(
        () => _http.put(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> patch(String path, Object body) => _send(
        () => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> delete(String path, {Object? body}) => _send(
        () => _http.delete(_uri(path), headers: _headers(json: body != null), body: body == null ? null : jsonEncode(body)),
      );

  /// رفع جسم ثنائي كما هو (الملف نفسه هو الجسم) مع نوع المحتوى وترويسات إضافية.
  Future<Map<String, dynamic>> postBytes(String path, Uint8List bytes, {required String contentType, Map<String, String>? headers, Duration? timeout}) =>
      _send(() => _http.post(_uri(path), headers: {..._headers(json: false), 'Content-Type': contentType, ...?headers}, body: bytes), timeout: timeout);

  Future<Map<String, dynamic>> patch_(String path, Object body) => _send(
        () => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  /// طلب GET يرجع مصفوفة (يعيد القائمة كما هي).
  Future<List<dynamic>> getList(String path, {Map<String, String>? query}) async {
    final data = await get(path, query: query);
    final raw = data['data'] ?? data['items'] ?? data['rows'] ?? data['list'];
    if (raw is List) return raw;
    return const [];
  }

  /// يحوّل مساراً نسبياً من الخادم (مثل /chat/media/x.jpg) إلى رابط مطلق.
  String absolute(String url) => url.startsWith('http') ? url : '$baseUrl${url.startsWith('/') ? '' : '/'}$url';

  /// رابط وسائط على أصل هذا العميل (انظر [mediaUrl]).
  String media(String url) => mediaUrl(url, base: baseUrl);

  /// أصل WebSocket المطابق لعنوان الخادم.
  String get wsUrl => '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws';

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, {Duration? timeout, bool prompt = true}) async {
    http.Response res;
    try {
      res = await request().timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ApiException(0, 'انتهت مهلة الاتصال بالخادم');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'تعذر الاتصال بالخادم: ${e.message}');
    } catch (e) {
      throw ApiException(0, 'تعذر الاتصال بالخادم: $e');
    }

    final decoded = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    // زائر بلا جلسة يحاول فعلاً يتطلب حساباً: نُعلم الواجهة لتعرض الدخول بدل خطأ غامض
    if (res.statusCode == 401 && _token == null) {
      if (prompt) onUnauthorized?.call(); // القراءات الخلفية لا تزعج الزائر؛ الأفعال فقط
      throw const ApiException(401, 'سجّل الدخول أولاً');
    }

    throw ApiException(res.statusCode, _errorMessage(res.statusCode, decoded), body: decoded);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (text.trim().isEmpty) return const {};
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return {'data': v};
    } catch (_) {
      return {'raw': text};
    }
  }

  static const _serverErrors = <String, String>{
    'nickname-taken': 'اسم المستخدم مستخدم من قبل، اختر غيره',
    'invalid-nickname': 'اسم المستخدم غير صالح: حروف إنجليزية صغيرة وأرقام و _ فقط (3 إلى 25)',
    'invalid-password': 'الرقم السري غير صالح',
    'weak-password': 'الرقم السري يجب أن يكون 8 خانات على الأقل',
    'bad-credentials': 'النك نيم أو الرقم السري غير صحيح',
    'auth': 'انتهت الجلسة، سجّل الدخول مجدداً',
    'not-found': 'الحساب غير موجود',
    'deleted': 'هذا الحساب محذوف',
    'reserved': 'هذا الاسم غير متاح، اختر غيره',
    'confirm-mismatch': 'كلمة التأكيد غير مطابقة',
    'blocked': 'لا يمكن إتمام العملية الآن',
    'stale-version': 'تحدّثت الشروط، أعد فتح التطبيق',
    'delete-failed': 'تعذّر حذف الحساب، حاول مرة أخرى',
    'iap-required': 'هذه الخدمة غير متاحة في هذا التطبيق',
    'unavailable': 'هذه الخدمة غير متاحة حالياً',
    'place-required': 'حدّد مكان الفعالية قبل تسعير التذاكر',
    'too-many': 'محاولات كثيرة، انتظر دقيقة ثم حاول',
    'too-many-attempts': 'محاولات كثيرة، انتظر دقيقة ثم حاول',
    'email-taken': 'هذا البريد مسجّل لحساب آخر؛ سجّل الدخول به أو استخدم «نسيت كلمة السر»',
    'bad-email': 'صيغة البريد الإلكتروني غير صحيحة',
    'bad-code': 'الرمز غير صحيح',
    'code-expired': 'انتهت صلاحية الرمز؛ اطلب رمزاً جديداً',
    'no-code': 'اطلب رمزاً أولاً',
    'too-soon': 'انتظر دقيقة قبل طلب رمز جديد',
    'mail-not-configured': 'خدمة البريد غير مفعّلة على الخادم بعد، فلا يمكن إرسال الرمز الآن',
    'no-recovery': 'لا يمكن استعادة هذا الحساب بالبريد؛ ادخل بكلمة السر أو استخدم عبارة الاسترداد',
    'bad-password': 'كلمة السر الحالية غير صحيحة',
    'send-failed': 'تعذّر إرسال الرسالة الآن؛ حاول لاحقاً',
    'provider-required': 'اختر Resend أو Brevo واحفظ مفتاح API أولاً',
    'bad-domain': 'اكتب اسم نطاق صحيحاً مثل naslife.app',
    'bad-local': 'اسم البريد قبل @ يحتوي أحرفاً غير مسموحة',
    'provider-failed': 'رفض المزوّد الطلب؛ تأكد من صحة المفتاح وصلاحياته',
    'key-restricted': 'المفتاح الحالي للإرسال فقط. أنشئ في Resend مفتاحاً جديداً بصلاحية Full access، الصقه في «مفتاح الخدمة» واحفظ، ثم أعد الربط',
    'key-invalid': 'المزوّد لم يقبل المفتاح؛ تأكد من نسخه كاملاً وحفظه',
    'no-domain': 'لم يُربط أي نطاق بعد',
    // العروض
    'offer-unavailable': 'هذا العرض غير متاح لطلبك الآن',
    'not-transferable': 'هذا العرض لا يمكن إرساله لغيرك',
    'already-has': 'هذا المستخدم لديه العرض بالفعل',
    'user-not-found': 'لم نجد مستخدماً بهذا المعرّف',
    'self': 'لا يمكنك إرسال العرض لنفسك',
    'not-member': 'انضم للدائرة أولاً',
    'bad-level': 'مستوى التنبيه غير معروف',
    'end-required': 'حدّد موعد انتهاء العرض',
    'item-required': 'اختر المنتج الذي يخصّه العرض',
    'price-not-lower': 'السعر الخاص يجب أن يكون أقل من السعر الأصلي',
    'bad-value': 'قيمة الخصم غير صحيحة',
    'bad-kind': 'نوع العرض غير معروف',
    'bad-title': 'اكتب عنواناً للعرض',
    'bad-item': 'المنتج غير موجود في القائمة',
    'ended': 'انتهى هذا العرض',
  };

  String _errorMessage(int status, Map<String, dynamic> body) {
    final code = body['error'];
    if (code == 'banned-words') return 'النص يحتوي كلمة غير مسموحة${body['word'] is String ? ': «${body['word']}»' : ''}';
    if (code is String && _serverErrors.containsKey(code)) {
      return _serverErrors[code]!;
    }
    final fromBody = body['message'] ?? body['msg'];
    if (fromBody is String && fromBody.isNotEmpty && !fromBody.startsWith('Route ')) {
      return fromBody;
    }
    if (code is String && code.isNotEmpty && status < 500) {
      return 'رفض الخادم الطلب ($code)';
    }
    switch (status) {
      case 400:
        return 'بيانات غير صحيحة';
      case 401:
        return 'النك نيم أو الرقم السري غير صحيح';
      case 403:
        return 'غير مصرح';
      case 404:
        return 'المسار غير موجود على الخادم';
      case 409:
        return 'النك نيم مستخدم من قبل';
      case 429:
        return 'محاولات كثيرة، حاول لاحقاً';
      default:
        return status >= 500 ? 'خطأ في الخادم ($status)' : 'خطأ غير متوقع ($status)';
    }
  }

  void close() => _http.close();
}

final _ownMediaPath = RegExp(r'^/(?:chat/media|files|media|uploads|seed)/', caseSensitive: false);

/// يعيد رابط وسائط من خادمنا على أصل التطبيق نفسه.
///
/// سياسة CSP للموقع تسمح بالصور والوسائط من الأصل ذاته فقط ('self')، فرابط حُفظ عبر www.naslife.app
/// لا يعمل لمن يفتح naslife.app والعكس. أي رابط (نسبي أو مطلق على أي مضيف) يشير إلى مسارات وسائطنا
/// (/chat/media و/files و/media و/uploads) يُعاد بناؤه على [ApiClient.mediaBase]؛ وروابط المواقع الأخرى تبقى كما هي.
String mediaUrl(String url, {String? base}) {
  final s = url.trim();
  if (s.isEmpty) return s;
  final b = base ?? ApiClient.mediaBase;
  if (!s.startsWith('http://') && !s.startsWith('https://')) return '$b${s.startsWith('/') ? '' : '/'}$s';
  final u = Uri.tryParse(s);
  if (u == null || !_ownMediaPath.hasMatch(u.path)) return s;
  return '$b${u.path}${u.hasQuery ? '?${u.query}' : ''}';
}

final _chatMediaPath = RegExp(r'^/chat/media/([a-z0-9]{6,16}-[a-f0-9]{24}\.[a-z0-9]{2,5})$', caseSensitive: false);

/// رابط المصغّر (JPEG بحد 480 بكسل، أو إطار من الفيديو) لملف مرفوع عبر /chat/upload؛ يخدم القوائم والخريطة
/// والصور الرمزية فتقل البيانات المستهلكة. غير ذلك من الروابط يُعاد كما هو عبر [mediaUrl].
/// الخادم يقدّم الملف الأصلي إن تعذّر توليد المصغّر، فلا حاجة لاحتياط في التطبيق.
String thumbUrl(String url, {String? base}) {
  final full = mediaUrl(url, base: base);
  final u = Uri.tryParse(full);
  final m = u == null ? null : _chatMediaPath.firstMatch(u.path);
  if (m == null) return full;
  return '${base ?? ApiClient.mediaBase}/chat/thumb/${m.group(1)}';
}

class _TokenBox {
  String? value;
}
