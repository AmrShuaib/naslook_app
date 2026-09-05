import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/app/app.dart';

void main() {
  testWidgets('shows the nickname + PIN login page when signed out',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MainApp()));
    await tester.pumpAndSettle();

    expect(find.text('النك نيم'), findsOneWidget);
    expect(find.text('الرقم السري'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });
}
