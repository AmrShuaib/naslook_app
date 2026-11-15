import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'admin_shell.dart' deferred as admin;

/// مدخل لوحة الإدارة بتحميل مؤجَّل: كود اللوحة (نحو 450 ك.ب من المصدر) يُنزَّل في ملف مستقل عند أول فتح لها فقط،
/// فلا يحمله كل مستخدم عادي مع أول شاشة. القسم يُعطى برقمه أو بمعرّفه ([sectionId]) لأن قائمة الأقسام نفسها داخل
/// المكتبة المؤجَّلة ولا تُقرأ قبل تحميلها.
class AdminEntry extends StatefulWidget {
  final bool standalone;
  final int initialSection;
  final String? sectionId;
  const AdminEntry({super.key, this.standalone = true, this.initialSection = 0, this.sectionId});
  @override
  State<AdminEntry> createState() => _AdminEntryState();
}

class _AdminEntryState extends State<AdminEntry> {
  // التحميل مرة واحدة للتطبيق كله: فتح اللوحة ثانيةً لا ينتظر
  static Future<void>? _loading;
  static bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (!_ready) _load();
  }

  void _load() {
    setState(() => _error = null);
    (_loading ??= admin.loadLibrary()).then((_) {
      _ready = true;
      if (mounted) setState(() {});
    }).catchError((Object e) {
      // انقطاع الشبكة أثناء التنزيل: نسمح بإعادة المحاولة بدل شاشة عالقة
      _loading = null;
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      var i = widget.initialSection;
      if (widget.sectionId != null) {
        final at = admin.adminSections.indexWhere((s) => s.$1 == widget.sectionId);
        if (at >= 0) i = at;
      }
      return admin.AdminShell(standalone: widget.standalone, initialSection: i);
    }
    return Scaffold(
      backgroundColor: Joy.bg,
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('تعذّر تحميل لوحة الإدارة'),
                const SizedBox(height: 12),
                FilledButton(key: const Key('admin-entry-retry'), onPressed: _load, child: const Text('أعد المحاولة')),
              ]),
      ),
    );
  }
}
