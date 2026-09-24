// زر «مشاركة» في ورقة المشاركة: على iOS/Android يفتح ورقة النظام (share_plus)، وإن لم تتوفر يعود لنسخ الرابط.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/core/share/share_io.dart';
import 'package:naslook/core/share/share_links.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ar'),
    home: Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(onPressed: () => shareLink(ctx, title: 'برو ٩٢', url: 'https://naslife.app/c/biz-brew92'), child: const Text('share'))))),
  ));
  await tester.tap(find.text('share'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => nativeShareOverride = null);

  testWidgets('the native share sheet receives the title, text and link, and nothing is copied', (tester) async {
    final calls = <String>[];
    nativeShareOverride = ({required String title, required String text, required String url}) async {
      calls.add('$title|$text|$url');
      return true;
    };
    await _open(tester);
    await tester.tap(find.byKey(const Key('share-native')));
    await tester.pumpAndSettle();
    expect(calls, ['برو ٩٢|برو ٩٢ على ناس لايف|https://naslife.app/c/biz-brew92']);
    expect(find.textContaining('نُسخ الرابط'), findsNothing);
    expect(find.byKey(const Key('share-native')), findsNothing, reason: 'تُغلق الورقة');
  });

  testWidgets('without a share sheet (desktop / test host) the link is copied instead', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _open(tester);
    expect(await nativeShare(title: 't', text: 'x', url: 'u'), isFalse, reason: 'ليست iOS ولا Android');
    await tester.tap(find.byKey(const Key('share-native')));
    await tester.pump();
    expect(copied, 'https://naslife.app/c/biz-brew92');
    expect(find.text('نُسخ الرابط، الصقه حيث تريد'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
