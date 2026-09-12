import 'package:flutter/material.dart';

import 'state/admin_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Naslife v2 — الدخول بالنك نيم + الرقم السري عبر خادم Node/Fastify.
/// لا يوجد اعتماد على Firebase في هذه النسخة.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  captureAdminMode();
  runApp(const ProviderScope(child: MainApp()));
}
