import 'camera.dart';

/// على غير الويب لا كاميرا حية بعد؛ المحرّر يلجأ إلى كاميرا النظام عبر image_picker.
bool get supported => false;
LiveCamera createCamera() => throw UnsupportedError('LiveCamera is web-only');
