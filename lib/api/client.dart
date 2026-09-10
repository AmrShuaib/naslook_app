import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

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

  String? _token;

  ApiClient({String? baseUrl, http.Client? httpClient, this.timeout = const Duration(seconds: 20)})
      : baseUrl = _normalize(baseUrl ?? resolveBaseUrl()),
        _http = httpClient ?? http.Client();

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

  String? get token => _token;
  set token(String? value) => _token = (value == null || value.isEmpty) ? null : value;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        // خادم Naslife يقرأ رمز الجلسة من ترويسة x-token
        if (_token != null) 'x-token': _token!,
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ---------------------------------------------------------------------------
  // المصادقة
  // ---------------------------------------------------------------------------

  /// تسجيل حساب جديد بالنك نيم + الرقم السري.
  Future<Session> register({required String nickname, required String pin}) async {
    final data = await post('/register', {
      'nickname': nickname.trim(),
      'password': pin.trim(),
    });
    final session = Session.fromJson(data);
    if (!session.isValid) {
      throw ApiException(500, 'الخادم لم يُرجع رمز جلسة', body: data);
    }
    token = session.token;
    return session;
  }

  /// الدخول بالنك نيم + الرقم السري.
  Future<Session> login({required String nickname, required String pin}) async {
    final data = await post('/login', {
      'handle': nickname.trim(),
      'password': pin.trim(),
    });
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
      _send(() => _http.get(_uri(path, query), headers: _headers(json: false)));

  Future<Map<String, dynamic>> post(String path, Object body) => _send(
        () => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> put(String path, Object body) => _send(
        () => _http.put(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> delete(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers(json: false)));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(0, 'انتهت مهلة الاتصال بالخادم');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'تعذر الاتصال بالخادم: ${e.message}');
    } catch (e) {
      throw ApiException(0, 'تعذر الاتصال بالخادم: $e');
    }

    final decoded = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

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
    'nickname-taken': 'النك نيم مستخدم من قبل، اختر غيره',
    'invalid-nickname': 'النك نيم غير صالح: استخدم حروفاً وأرقاماً بلا مسافات',
    'invalid-password': 'الرقم السري غير صالح',
    'weak-password': 'الرقم السري قصير أو ضعيف',
    'bad-credentials': 'النك نيم أو الرقم السري غير صحيح',
    'auth': 'انتهت الجلسة، سجّل الدخول مجدداً',
    'not-found': 'الحساب غير موجود',
    'deleted': 'هذا الحساب محذوف',
    'too-many': 'محاولات كثيرة، انتظر دقيقة ثم حاول',
  };

  String _errorMessage(int status, Map<String, dynamic> body) {
    final code = body['error'];
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
