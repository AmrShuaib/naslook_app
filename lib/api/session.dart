import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// بيانات المستخدم كما يرجعها الخادم بعد الدخول بالنك نيم + الرقم السري.
class SessionUser {
  final String id;
  final String nickname;
  final String? displayName;
  final String? avatarUrl;

  const SessionUser({
    required this.id,
    required this.nickname,
    this.displayName,
    this.avatarUrl,
  });

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: (json['id'] ?? json['_id'] ?? json['userId'] ?? '').toString(),
      nickname: (json['nickname'] ?? json['nick'] ?? json['username'] ?? '')
          .toString(),
      displayName: json['displayName']?.toString() ?? json['name']?.toString(),
      avatarUrl: json['avatarUrl']?.toString() ?? json['avatar']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        if (displayName != null) 'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  SessionUser copyWith({
    String? id,
    String? nickname,
    String? displayName,
    String? avatarUrl,
  }) {
    return SessionUser(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

/// الجلسة الحالية: رمز الدخول (token) الذي أصدره الخادم + بيانات المستخدم.
///
/// ملاحظة: لا يوجد تشفير من جهة العميل. الرقم السري يُرسل كما هو للخادم عبر
/// HTTPS ولا يُحفظ محلياً أبداً؛ يُحفظ فقط رمز الجلسة وبيانات المستخدم.
class Session {
  final String token;
  final SessionUser user;

  /// عبارة الاسترداد التي يصدرها الخادم مرة واحدة عند التسجيل (لا تُحفظ محلياً).
  final String? recoveryPhrase;

  const Session({required this.token, required this.user, this.recoveryPhrase});

  bool get isValid => token.isNotEmpty;

  factory Session.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final userJson = rawUser is Map<String, dynamic>
        ? rawUser
        : rawUser is Map
            ? Map<String, dynamic>.from(rawUser)
            : json; // بعض الخوادم ترجع بيانات المستخدم في المستوى الأعلى
    return Session(
      token: (json['token'] ??
              json['accessToken'] ??
              json['access_token'] ??
              json['sessionToken'] ??
              '')
          .toString(),
      user: SessionUser.fromJson(userJson),
      recoveryPhrase: json['recoveryPhrase']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson()};

  Session copyWith({String? token, SessionUser? user, bool clearRecovery = false}) =>
      Session(
        token: token ?? this.token,
        user: user ?? this.user,
        recoveryPhrase: clearRecovery ? null : recoveryPhrase,
      );
}

/// تخزين الجلسة محلياً (localStorage على الويب عبر shared_preferences).
class SessionStore {
  static const _key = 'naslife.session.v2';

  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = Session.fromJson(Map<String, dynamic>.from(decoded));
      return session.isValid ? session : null;
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
