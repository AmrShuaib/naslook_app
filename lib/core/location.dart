import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// موقع الجهاز عبر المتصفح (يطلب الإذن مرة واحدة). يرجع null إن رُفض أو تعذّر.
class DeviceLocation {
  static LatLng? last;

  static Future<LatLng?> current({bool precise = true}) =>
      // مهلة إجمالية: طلب الإذن أو تحديد الموقع قد لا يرد أبداً على بعض المتصفحات
      _current(precise: precise).timeout(const Duration(seconds: 14), onTimeout: () => last);

  static Future<LatLng?> _current({required bool precise}) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
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
}
