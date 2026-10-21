import 'package:web/web.dart' as web;

/// على الويب: ملف build.json بجانب التطبيق يكتبه tools/publish_bundle.sh مع كل نشر.
bool get appUpdateSupported => true;
String appUpdateBuildUrl() => '${web.window.location.origin}/build.json';
void appUpdateReload() => web.window.location.reload();
