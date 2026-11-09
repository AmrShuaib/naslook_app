// مراقب النسخة الجديدة: أول قراءة لـ build.json تثبّت البصمة، والاختلاف اللاحق يرفع available ويُظهر الشريط،
// و«تحديث الآن» يعيد التحميل، والخطأ لا يرفع شيئاً.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naslook/core/update/app_update.dart';
import 'package:naslook/ui/update_banner.dart';

void main() {
  setUp(() { AppUpdate.reset(); AppUpdate.supportedOverride = true; });
  tearDown(() { AppUpdate.reset(); AppUpdate.supportedOverride = null; AppUpdate.fetchOverride = null; AppUpdate.reloadOverride = null; });

  test('same bundle keeps quiet, a different one raises available, errors are ignored', () async {
    var body = '{"bundle":"aaaa","code":"1"}';
    AppUpdate.fetchOverride = () async => body;
    await AppUpdate.check();
    expect(AppUpdate.current, 'aaaa');
    await AppUpdate.check();
    expect(AppUpdate.available.value, isFalse);
    AppUpdate.fetchOverride = () async => throw Exception('offline');
    await AppUpdate.check();
    expect(AppUpdate.available.value, isFalse);
    body = '{"bundle":"bbbb","code":"2"}';
    AppUpdate.fetchOverride = () async => body;
    await AppUpdate.check();
    expect(AppUpdate.available.value, isTrue);
  });

  test('a compiled build id beats the first-read baseline: a stale page still sees the newer build', () async {
    AppUpdate.buildIdOverride = 'old-1';
    // الصفحة جاءت قديمة لكن أول قراءة من الشبكة هي النسخة الجديدة: البصمة وحدها لا تكشف ذلك، المعرّف يكشفه
    AppUpdate.fetchOverride = () async => '{"bundle":"bbbb","id":"new-2"}';
    await AppUpdate.check();
    expect(AppUpdate.available.value, isTrue);
  });

  test('matching build id keeps quiet; build.json without id falls back to the bundle baseline', () async {
    AppUpdate.buildIdOverride = 'same-1';
    AppUpdate.fetchOverride = () async => '{"bundle":"aaaa","id":"same-1"}';
    await AppUpdate.check();
    await AppUpdate.check();
    expect(AppUpdate.available.value, isFalse);
    AppUpdate.fetchOverride = () async => '{"bundle":"aaaa"}';
    await AppUpdate.check();
    expect(AppUpdate.current, 'aaaa');
    AppUpdate.fetchOverride = () async => '{"bundle":"cccc"}';
    await AppUpdate.check();
    expect(AppUpdate.available.value, isTrue);
  });

  testWidgets('the banner appears when an update is available and «تحديث الآن» reloads', (tester) async {
    var reloaded = 0;
    AppUpdate.reloadOverride = () => reloaded++;
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.rtl, child: MaterialApp(home: Scaffold(body: Column(children: [UpdateBanner()])))));
    expect(find.byKey(const Key('update-banner')), findsNothing);
    AppUpdate.available.value = true;
    await tester.pump();
    expect(find.text('نسخة جديدة من ناس لايف جاهزة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-now')));
    expect(reloaded, 1);
  });
}
