import 'package:flutter/material.dart';
import 'i18n/l10n.dart';
import 'router.dart';
import 'theme.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Naslook App',
      theme: AppTheme.light,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      routerConfig: router,
    );
  }
}
