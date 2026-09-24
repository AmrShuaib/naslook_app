import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// حالة آخر محاولة لتحديد الموقع، لتعرض الواجهة الطريق المناسب (مثل «افتح الإعدادات»).
enum LocationStatus { unknown, granted, denied, deniedForever, serviceDisabled }

/// موقع الجهاز (المتصفح على الويب، وخدمة الموقع على iOS/Android). يرجع null إن رُفض أو تعذّر.
///
/// طلب واحد في كل مرة: عدة شاشات تطلب الموقع معاً عند الإقلاع، وiOS يرفض طلب إذن ثانياً أثناء الأول
/// (PERMISSION_REQUEST_IN_PROGRESS) ويستبدل معالج طلب الموقع السابق، فيشترك المتزامنون في طلب واحد.
class DeviceLocation {
  static LatLng? last;
  /// بديل للاختبارات: يُستدعى بدل خدمة الموقع إن وُجد.
  static Future<LatLng?> Function()? override;
  /// بديل للاختبارات لفتح الإعدادات.
  static Future<bool> Function()? openSettingsOverride;

  static LocationStatus status = LocationStatus.unknown;
  /// رفض دائم: لن يظهر طلب الإذن مجدداً، والحل الوحيد إعدادات التطبيق.
  static bool get deniedForever => status == LocationStatus.deniedForever;
  static bool get serviceDisabled => status == LocationStatus.serviceDisabled;

  static Future<LatLng?>? _flight;
  static bool _flightPrecise = false;

  /// [timeout] مهلة إجمالية: طلب الإذن أو تحديد الموقع قد لا يرد أبداً على بعض المتصفحات، وعندها يُعاد آخر موقع معروف.
  static Future<LatLng?> current({bool precise = true, Duration timeout = const Duration(seconds: 14)}) =>
      _shared(precise).timeout(timeout, onTimeout: () => last);

  static Future<LatLng?> _shared(bool precise) {
    final f = _flight;
    if (f != null) {
      if (_flightPrecise || !precise) return f;
      // طلب دقيق أثناء طلب تقريبي: ننتظر الجاري ثم نطلب الدقيق، لا طلبين معاً
      return f.then((_) => _shared(true));
    }
    _flightPrecise = precise;
    late final Future<LatLng?> run;
    run = _run(precise).whenComplete(() {
      if (identical(_flight, run)) _flight = null;
    });
    _flight = run;
    return run;
  }

  static Future<LatLng?> _run(bool precise) async {
    final o = override;
    if (o != null) return o();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        status = LocationStatus.serviceDisabled;
        return last;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        status = LocationStatus.deniedForever;
        return null;
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        status = LocationStatus.denied;
        return null;
      }
      status = LocationStatus.granted;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precise ? LocationAccuracy.best : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 12),
        ),
      );
      last = LatLng(p.latitude, p.longitude);
      return last;
    } catch (_) {
      return last;
    }
  }

  /// يفتح إعدادات التطبيق (بعد رفض دائم) أو إعدادات خدمة الموقع (إن كانت مطفأة).
  static Future<bool> openSettings() async {
    final o = openSettingsOverride;
    if (o != null) return o();
    try {
      return serviceDisabled ? await Geolocator.openLocationSettings() : await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// لأغراض الاختبار.
  static void resetForTest() {
    _flight = null;
    status = LocationStatus.unknown;
  }
}
