// موقع الجهاز: الطلبات المتزامنة تشترك في طلب واحد (iOS يرفض طلب إذن ثانياً أثناء الأول)، والطلب الدقيق لا يتزامن مع التقريبي.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/core/location.dart';

void main() {
  tearDown(() {
    DeviceLocation.override = null;
    DeviceLocation.openSettingsOverride = null;
    DeviceLocation.resetForTest();
  });

  test('concurrent callers share one in-flight request', () async {
    var calls = 0;
    final gate = Completer<void>();
    DeviceLocation.override = () async {
      calls++;
      await gate.future;
      return const LatLng(21.5, 39.2);
    };
    final a = DeviceLocation.current(precise: false);
    final b = DeviceLocation.current(precise: false);
    final c = DeviceLocation.current(precise: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1, reason: 'طلب واحد للجميع');
    gate.complete();
    final r = await Future.wait([a, b, c]);
    expect(r, everyElement(const LatLng(21.5, 39.2)));
    // بعد الانتهاء يبدأ طلب جديد
    await DeviceLocation.current(precise: false);
    expect(calls, 2);
  });

  test('a precise request waits for a running coarse one, then runs on its own', () async {
    var calls = 0;
    var running = 0, maxRunning = 0;
    DeviceLocation.override = () async {
      calls++;
      running++;
      if (running > maxRunning) maxRunning = running;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      running--;
      return LatLng(21.0 + calls, 39.0);
    };
    final coarse = DeviceLocation.current(precise: false);
    final fine = DeviceLocation.current(precise: true);
    final fine2 = DeviceLocation.current(precise: true);
    expect(await coarse, const LatLng(22.0, 39.0));
    expect(await fine, const LatLng(23.0, 39.0));
    expect(await fine2, const LatLng(23.0, 39.0), reason: 'الطلب الدقيق الثاني يشارك الأول');
    expect(calls, 2);
    expect(maxRunning, 1, reason: 'لا طلبين متزامنين أبداً');
  });

  test('a hung request falls back to the last known location after the timeout', () async {
    DeviceLocation.last = const LatLng(26.4, 50.1);
    addTearDown(() => DeviceLocation.last = null);
    DeviceLocation.override = () => Completer<LatLng?>().future;
    final r = await DeviceLocation.current(timeout: const Duration(milliseconds: 20));
    expect(r, const LatLng(26.4, 50.1));
  });

  test('denied forever is exposed and openSettings reaches the app settings', () async {
    expect(DeviceLocation.deniedForever, isFalse);
    DeviceLocation.status = LocationStatus.deniedForever;
    expect(DeviceLocation.deniedForever, isTrue);
    var opened = 0;
    DeviceLocation.openSettingsOverride = () async {
      opened++;
      return true;
    };
    expect(await DeviceLocation.openSettings(), isTrue);
    expect(opened, 1);
  });

  test('service area covers Jeddah and Dammam only', () {
    expect(DeviceLocation.inServiceArea(const LatLng(21.49, 39.19)), isTrue);
    expect(DeviceLocation.inServiceArea(const LatLng(26.29, 50.21)), isTrue, reason: 'الخبر ضمن نطاق الدمام');
    expect(DeviceLocation.inServiceArea(const LatLng(24.71, 46.67)), isFalse, reason: 'الرياض خارج منطقة الخدمة الحالية');
    expect(DeviceLocation.inServiceArea(const LatLng(37.33, -122.03)), isFalse);
  });

  test('browse shows Jeddah outside the service area and the real spot inside it', () async {
    DeviceLocation.override = () async => const LatLng(37.33, -122.03); // كوبرتينو (مراجِع أبل)
    expect(await DeviceLocation.browse(), DeviceLocation.jeddah);
    expect(DeviceLocation.outsideServiceArea, isTrue);
    expect(DeviceLocation.lastBrowse, DeviceLocation.jeddah);
    DeviceLocation.resetForTest();
    DeviceLocation.override = () async => const LatLng(26.43, 50.10);
    expect(await DeviceLocation.browse(), const LatLng(26.43, 50.10));
    expect(DeviceLocation.outsideServiceArea, isFalse);
    DeviceLocation.resetForTest();
    DeviceLocation.override = () async => null;
    DeviceLocation.last = null;
    expect(await DeviceLocation.browse(), isNull, reason: 'تعذّر تحديد الموقع: يقرر المستدعي البديل');
  });
}
