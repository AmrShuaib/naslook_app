import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../core/media/permissions.dart' show MediaPermissionDenied;
import 'qr_scanner.dart';

/// المسح الحي يحتاج getUserMedia، وهي متاحة في الصفحات الآمنة فقط (https أو localhost).
bool get liveSupported {
  try {
    return web.window.isSecureContext && web.window.navigator.mediaDevices.isDefinedAndNotNull;
  } catch (_) {
    return false;
  }
}

QrCamera createQrCamera() => _WebQrCamera();

// ---------------------------------------------------------------- BarcodeDetector (كروم أندرويد وماك)

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector(JSObject options);
  external static JSPromise<JSArray<JSString>> getSupportedFormats();
  external JSPromise<JSArray<_Detected>> detect(JSObject source);
}

extension type _Detected._(JSObject _) implements JSObject {
  external String get rawValue;
}

Future<_BarcodeDetector?>? _probe;

/// يُفحص مرة واحدة: سفاري وفايرفوكس وكروم ويندوز بلا BarcodeDetector، فنفكّ هناك بـ zxing2.
Future<_BarcodeDetector?> _barcodeDetector() => _probe ??= () async {
      try {
        if (!globalContext.has('BarcodeDetector')) return null;
        final formats = (await _BarcodeDetector.getSupportedFormats().toDart).toDart.map((s) => s.toDart);
        if (!formats.contains('qr_code')) return null;
        return _BarcodeDetector({'formats': ['qr_code']}.jsify()! as JSObject);
      } catch (_) {
        return null;
      }
    }();

Future<String?> _detect(JSObject source) async {
  final det = await _barcodeDetector();
  if (det == null) return null;
  final list = (await det.detect(source).toDart).toDart;
  for (final d in list) {
    final s = d.rawValue;
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// يرسم المصدر مصغّراً في canvas ويقرأ RGBA ثم يفكّ بـ zxing2. [crop] يقرأ المربع الأوسط (ما تعرضه المعاينة المقصوصة).
String? _zxing(web.HTMLCanvasElement canvas, web.CanvasImageSource src, int sw0, int sh0, {required int maxSide, bool crop = false, bool thorough = false}) {
  if (sw0 <= 0 || sh0 <= 0) return null;
  final side = math.min(sw0, sh0);
  final sw = crop ? side : sw0, sh = crop ? side : sh0;
  final sx = (sw0 - sw) ~/ 2, sy = (sh0 - sh) ~/ 2;
  final scale = math.min(1.0, maxSide / math.max(sw, sh));
  final w = math.max(1, (sw * scale).round()), h = math.max(1, (sh * scale).round());
  if (canvas.width != w) canvas.width = w;
  if (canvas.height != h) canvas.height = h;
  final ctx = canvas.getContext('2d', {'willReadFrequently': true}.jsify()) as web.CanvasRenderingContext2D;
  ctx.drawImage(src, sx, sy, sw, sh, 0, 0, w, h);
  final data = ctx.getImageData(0, 0, w, h).data.toDart;
  return decodeQrRgba(data, w, h, thorough: thorough);
}

/// صورة ملتقطة (وضع الصورة الثابتة على الويب، كصفحة غير آمنة): BarcodeDetector إن وُجد وإلا zxing2.
Future<String?> decodeImageBytes(Uint8List bytes) async {
  try {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    final bmp = await web.window.createImageBitmap(blob).toDart;
    try {
      final s = await _detect(bmp);
      if (s != null && s.isNotEmpty) return s;
    } catch (_) { /* نكمل بـ zxing2 */ }
    return _zxing(web.HTMLCanvasElement(), bmp, bmp.width, bmp.height, maxSide: 1200, thorough: true);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- الكاميرا

int _seq = 0;

class _WebQrCamera implements QrCamera {
  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  final _canvas = web.HTMLCanvasElement();
  late final String _viewId = 'naslife-qr-${_seq++}';
  bool _registered = false, _torchAvail = false, _torchOn = false, _noDetector = false;
  int _frame = 0;

  @override
  bool get torchAvailable => _torchAvail;
  @override
  bool get torchOn => _torchOn;

  static bool _denied(Object e) {
    final s = '$e';
    return s.contains('NotAllowedError') || s.contains('SecurityError') || s.contains('PermissionDenied');
  }

  @override
  Future<void> start() async {
    final md = web.window.navigator.mediaDevices;
    // الخلفية بدقة متوسطة تكفي للرمز وتخفّف الفكّ؛ الصوت غير مطلوب فلا يُطلب إذن الميكروفون
    final ideal = web.MediaStreamConstraints(video: {'facingMode': {'ideal': 'environment'}, 'width': {'ideal': 1280}, 'height': {'ideal': 720}}.jsify()!, audio: false.toJS);
    try {
      _stream = await md.getUserMedia(ideal).toDart;
    } catch (e) {
      if (_denied(e)) throw const MediaPermissionDenied('camera');
      try {
        // بعض الأجهزة ترفض القيود: أبسط طلب
        _stream = await md.getUserMedia(web.MediaStreamConstraints(video: true.toJS, audio: false.toJS)).toDart;
      } catch (e2) {
        if (_denied(e2)) throw const MediaPermissionDenied('camera');
        throw QrCameraUnavailable('$e2'.split(':').first);
      }
    }
    final v = _el();
    v.srcObject = _stream;
    try {
      await v.play().toDart;
    } catch (_) {
      // صامت ومضمّن: يبدأ عند إلحاقه بالصفحة
    }
    _probeTorch();
  }

  web.HTMLVideoElement _el() {
    final cur = _video;
    if (cur != null) return cur;
    final v = _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..background = '#000';
    return v;
  }

  @override
  Widget view() {
    if (!_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int _) {
        final v = _el();
        if (_stream != null && v.srcObject == null) v.srcObject = _stream;
        return v;
      });
    }
    return HtmlElementView(viewType: _viewId);
  }

  @override
  Future<String?> scan() async {
    final v = _video;
    if (v == null || v.readyState < 2 || v.videoWidth == 0) return null;
    if (!_noDetector) {
      try {
        final s = await _detect(v);
        if (s == null) {
          _noDetector = true;
        } else {
          return s.isEmpty ? null : s;
        }
      } catch (_) {
        // المتصفح أعلنه ثم فشل: zxing2 من الآن
        _noDetector = true;
      }
    }
    // المربع الأوسط غالباً (ما تراه العين داخل الإطار)، والإطار كاملاً كل ثالث محاولة لرمز في الطرف
    final full = _frame++ % 3 == 2;
    return _zxing(_canvas, v, v.videoWidth, v.videoHeight, maxSide: 640, crop: !full);
  }

  void _probeTorch() {
    _torchAvail = false;
    try {
      final track = _stream?.getVideoTracks().toDart.firstOrNull;
      if (track == null) return;
      final caps = (track as JSObject).callMethod<JSAny?>('getCapabilities'.toJS);
      if (caps == null || caps.isUndefinedOrNull) return;
      final t = (caps as JSObject).getProperty<JSAny?>('torch'.toJS)?.dartify();
      _torchAvail = t == true || (t is List && t.contains(true));
    } catch (_) {
      // لا getCapabilities (فايرفوكس): لا كشاف
    }
  }

  @override
  Future<void> setTorch(bool on) async {
    final track = _stream?.getVideoTracks().toDart.firstOrNull;
    if (track == null || !_torchAvail) return;
    await track.applyConstraints({'advanced': [{'torch': on}]}.jsify()! as web.MediaTrackConstraints).toDart;
    _torchOn = on;
  }

  @override
  void dispose() {
    final s = _stream;
    if (s != null) {
      for (final t in s.getTracks().toDart) {
        t.stop();
      }
    }
    _stream = null;
    final v = _video;
    if (v != null) {
      v.srcObject = null;
      v.remove();
    }
    _torchOn = false;
  }
}
