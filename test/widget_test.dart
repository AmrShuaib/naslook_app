import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/app/app.dart';

void main() {
  testWidgets('shows the email + password login page when signed out',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MainApp()));
    await tester.pumpAndSettle();

    expect(find.text('البريد الإلكتروني أو اسم المستخدم'), findsOneWidget);
    expect(find.text('كلمة السر'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });
}
