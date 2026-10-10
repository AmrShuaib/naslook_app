import 'package:flutter/material.dart';

/// ثيمات التطبيق. الوضع الفاتح هو المستخدم حالياً، والداكن جاهز للتفعيل لاحقاً.
class AppTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    fontFamily: 'Cairo', // أضف الخط إلى pubspec.yaml لاحقاً
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: Colors.blue,
    fontFamily: 'Cairo',
  );
}
