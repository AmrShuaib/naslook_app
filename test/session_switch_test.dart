// تبديل الحساب على الجهاز نفسه: مزوّدات البيانات تُبنى من جديد مع كل صاحب جلسة (لا تبقى بيانات حساب سابق تحت اسم
// الحساب الجديد)، والتطبيق يتبع الجلسة المحفوظة حين يغيّرها تبويب آخر.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

/// خادم وهمي: الدخول يصدر رمزاً باسم الحساب، وجهات الاتصال تعتمد على الرمز المرسل.
Future<http.Response> _handle(http.Request req) async {
  final path = req.url.path;
  final token = req.headers['x-token'] ?? '';
  if (req.method == 'POST' && path == '/auth/login') {
    final b = jsonDecode(req.body) as Map;
    return _json({'id': 'SA-${b['handle']}', 'nickname': b['handle'], 'token': 'tok-${b['handle']}'});
  }
  if (req.method == 'POST' && path == '/logout') return _json({'ok': true});
  if (req.method == 'GET' && path == '/me') return _json({'id': 'SA-${token.replaceFirst('tok-', '')}', 'nickname': token.replaceFirst('tok-', '')});
  if (req.method == 'GET' && path == '/contacts') {
    if (token.isEmpty) return _json({'error': 'auth'}, 401);
    return _json([{'id': 'SA-friend', 'nickname': 'friend-of-${token.replaceFirst('tok-', '')}'}]);
  }
  return _json({'error': 'not-found'}, 404);
}

void main() {
  test('data providers are rebuilt when the signed-in account changes', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
    final container = ProviderContainer(overrides: [rawApiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final notifier = container.read(appStateProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20)); // اكتمال bootstrap بلا جلسة محفوظة
    expect(container.read(appStateProvider).status, AuthStatus.signedOut);

    expect(await notifier.login('amr', 'secret123'), isTrue);
    final sub = container.listen(contactsProvider, (_, __) {});
    addTearDown(sub.close);
    expect((await container.read(contactsProvider.future)).single.nickname, 'friend-of-amr');

    await notifier.logout();
    expect(await notifier.login('saudi', 'secret123'), isTrue);
    expect(container.read(appStateProvider).session?.user.nickname, 'saudi');
    // بدون إعادة البناء كانت تظهر جهات اتصال amr تحت اسم saudi
    expect((await container.read(contactsProvider.future)).single.nickname, 'friend-of-saudi');
  });

  test('syncFromStore follows a session written by another tab and a logout there', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(_handle));
    final container = ProviderContainer(overrides: [rawApiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final notifier = container.read(appStateProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await notifier.login('amr', 'secret123'), isTrue);

    // تبويب آخر دخل بحساب saudi
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('naslife.session.v2', jsonEncode({'token': 'tok-saudi', 'user': {'id': 'SA-saudi', 'nickname': 'saudi'}}));
    await notifier.syncFromStore();
    expect(container.read(appStateProvider).session?.user.nickname, 'saudi');
    expect(api.token, 'tok-saudi');

    // التبويب الآخر خرج
    await prefs.remove('naslife.session.v2');
    await notifier.syncFromStore();
    expect(container.read(appStateProvider).status, AuthStatus.signedOut);
    expect(api.token, isNull);
  });
}
