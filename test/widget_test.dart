import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/app/app.dart';
import 'package:naslook/app/router.dart';

void main() {
  testWidgets('التنقل بين التبويبات يغيّر المسار والعنوان', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();
    Finder appBarTitle(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));

    expect(location(), '/home');
    expect(appBarTitle('الرئيسية'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group));
    await tester.pumpAndSettle();

    expect(location(), '/circles');
    expect(appBarTitle('الدوائر'), findsOneWidget);

    router.go('/login');
    await tester.pumpAndSettle();

    expect(location(), '/login');
    expect(find.text('NASLOOK'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });
}
