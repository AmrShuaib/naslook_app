// مقدمة التطبيق: الشعار بمقاس index.html نفسه (70% بحد 320) ونقاط بألوان الشعار، وثابتة مع تقليل الحركة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naslook/ui/launch_splash.dart';

void main() {
  test('logo width matches index.html: min(70vw, 320px)', () {
    expect(LaunchSplash.logoWidth(390), closeTo(273, .01));
    expect(LaunchSplash.logoWidth(1280), 320);
  });

  testWidgets('shows the Naslife logo asset on white with four brand dots', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LaunchSplash()));
    await tester.pump(const Duration(milliseconds: 300));
    final img = tester.widget<Image>(find.byKey(const Key('launch-logo')));
    expect((img.image as AssetImage).assetName, LaunchSplash.asset);
    expect(img.width, closeTo(273, .01));
    expect(tester.widget<Scaffold>(find.byKey(const Key('launch-splash'))).backgroundColor, Colors.white);
    final dots = tester.widgetList<Container>(find.descendant(of: find.byType(Row), matching: find.byType(Container)));
    expect(dots.map((c) => (c.decoration as BoxDecoration).color), LaunchSplash.dotColors);
  });

  testWidgets('reduced motion: dots stay still so the frame settles', (tester) async {
    await tester.pumpWidget(const MediaQuery(data: MediaQueryData(disableAnimations: true), child: MaterialApp(home: LaunchSplash())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launch-logo')), findsOneWidget);
  });
}
