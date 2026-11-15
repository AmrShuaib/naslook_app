// «اعرض المحفوظ ثم حدّث» (lib/core/swr.dart): أول بناء يعيد المحفوظ فوراً ثم يتحدث من الشبكة، بلا محفوظ يُجلب مباشرة،
// التحديث اليدوي يذهب للشبكة، الفشل الخلفي يُبقي المحفوظ، والمحفوظ مفصول بالجلسة ويُمسح عند الخروج.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/core/swr.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var calls = 0;
  var value = 1;
  var fail = false;
  late ApiClient api;
  late FutureProvider<int> numProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Swr.prime();
    await Swr.clear();
    calls = 0;
    value = 1;
    fail = false;
    api = ApiClient(baseUrl: 'http://x', httpClient: MockClient((req) async {
      calls++;
      if (fail) return http.Response('{"error":"down"}', 500);
      return http.Response(jsonEncode({'n': value}), 200, headers: {'content-type': 'application/json'});
    }))..token = 'tok-a';
    numProvider = FutureProvider<int>((ref) => swr(ref, 'num', () async => (await api.get('/num'))['n'] as int));
  });

  test('no cache yet: fetches from the network and stores the answer', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(numProvider.future), 1);
    expect(calls, 1);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('swr:')).length, 1);
  });

  test('next launch: cached value first, then the fresh one without a second manual request', () async {
    final c1 = ProviderContainer();
    await c1.read(numProvider.future);
    await Future<void>.delayed(Duration.zero);
    c1.dispose();
    // «فتح جديد للتطبيق»: الذاكرة تُنسى والتخزين يبقى
    final keep = (await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('swr:')).toList();
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in keep) k: prefs.getString(k)!};
    await Swr.clear();
    SharedPreferences.setMockInitialValues(saved);
    await Swr.prime();
    value = 2;
    calls = 0;
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final seen = <int>[];
    c2.listen(numProvider, (_, next) { if (next.hasValue) seen.add(next.value!); }, fireImmediately: true);
    expect(await c2.read(numProvider.future), 1, reason: 'المحفوظ يظهر أولاً');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await c2.read(numProvider.future), 2, reason: 'ثم الجديد من الشبكة');
    expect(calls, 1, reason: 'طلب واحد في الخلفية');
    expect(seen, containsAllInOrder([1, 2]));
    // التحديث اليدوي بعدها يذهب للشبكة
    value = 3;
    c2.invalidate(numProvider);
    expect(await c2.read(numProvider.future), 3);
    expect(calls, 2);
  });

  test('offline refresh keeps showing the cached value', () async {
    final c1 = ProviderContainer();
    await c1.read(numProvider.future);
    await Future<void>.delayed(Duration.zero);
    c1.dispose();
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in prefs.getKeys().where((k) => k.startsWith('swr:'))) k: prefs.getString(k)!};
    await Swr.clear();
    SharedPreferences.setMockInitialValues(saved);
    await Swr.prime();
    fail = true;
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(numProvider.future), 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(numProvider).value, 1);
    expect(c2.read(numProvider).hasError, isFalse);
  });

  test('another session never sees this cache, and sign-out clears it', () async {
    final c1 = ProviderContainer();
    await c1.read(numProvider.future);
    await Future<void>.delayed(Duration.zero);
    c1.dispose();
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in prefs.getKeys().where((k) => k.startsWith('swr:'))) k: prefs.getString(k)!};
    expect(saved.keys.single.contains('tok-a'), isFalse, reason: 'رمز الجلسة لا يُكتب في المفتاح');
    await Swr.clear();
    SharedPreferences.setMockInitialValues(saved);
    await Swr.prime();
    api.token = 'tok-b';
    value = 7;
    calls = 0;
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(numProvider.future), 7, reason: 'جلسة أخرى: من الشبكة لا من محفوظ غيرها');
    expect(calls, 1);
    await Future<void>.delayed(Duration.zero);
    await Swr.clear();
    expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('swr:')), isEmpty);
  });

  test('requests outside swr are never cached', () async {
    await api.get('/num');
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('swr:')), isEmpty);
  });
}
