import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'camera.dart';

bool get supported {
  try {
    return web.window.navigator.mediaDevices.isDefinedAndNotNull && web.window.isSecureContext;
  } catch (_) {
    return false;
  }
}

LiveCamera createCamera() => _WebCamera();

int _seq = 0;
const _maxSide = 1600;

class _WebCamera implements LiveCamera {
  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  web.MediaRecorder? _rec;
  final _chunks = <web.Blob>[];
  String _recMime = '';
  DateTime? _recStart;
  bool _front = false;
  late final String _viewId = 'naslife-camera-${_seq++}';
  bool _registered = false;
  // التقريب: بصري عبر قيد zoom على مسار الفيديو حين يعرضه المتصفح (أندرويد كروم، وسفاري الحديث)، وإلا رقمي بقصّ مركز
  // الإطار: المعاينة بـ transform، والصورة بقصّ عند الالتقاط، والفيديو برسم الإطارات المقصوصة في canvas يُسجَّل بثّه.
  final _zoom = ValueNotifier<double>(1);
  double _maxZoom = 1, _minZoom = 1;
  bool _nativeZoom = false;
  bool _listenersOn = false;
  double _pinchStartDist = 0, _pinchStartZoom = 1;
  Timer? _cropTimer;
  web.MediaStream? _cropStream;

  @override
  bool get front => _front;
  @override
  bool get recording => _rec != null;
  @override
  double get maxZoom => _maxZoom;
  @override
  double get zoom => _zoom.value;
  @override
  ValueListenable<double> get zoomListenable => _zoom;
  double get _digital => _nativeZoom ? 1 : _zoom.value;

  @override
  Future<void> start({bool front = false}) async {
    _front = front;
    await _open();
  }

  Future<void> _open() async {
    _stopTracks();
    final constraints = web.MediaStreamConstraints(
      video: {'facingMode': _front ? 'user' : 'environment', 'width': {'ideal': 1280}, 'height': {'ideal': 1920}}.jsify()!,
      audio: true.toJS,
    );
    try {
      _stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
    } catch (_) {
      // بعض الأجهزة ترفض القيود الدقيقة: نعيد المحاولة بأبسط طلب
      _stream = await web.window.navigator.mediaDevices.getUserMedia(web.MediaStreamConstraints(video: true.toJS, audio: true.toJS)).toDart;
    }
    final v = _video ??= web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..background = '#000';
    v.srcObject = _stream;
    try {
      await v.play().toDart;
    } catch (_) {
      // autoplay يعمل لأن العنصر صامت؛ إن رُفض نتركه يبدأ عند أول تفاعل
    }
    _probeZoom();
    _attachGestures(v);
  }

  /// يقرأ مدى التقريب البصري من قدرات المسار إن وُجد؛ وإلا تقريب رقمي حتى ٣×.
  void _probeZoom() {
    _nativeZoom = false;
    _minZoom = 1;
    _maxZoom = 3;
    try {
      final track = _stream?.getVideoTracks().toDart.firstOrNull;
      final caps = track == null ? null : (track as JSObject).callMethod<JSAny?>('getCapabilities'.toJS);
      final z = caps == null || caps.isUndefinedOrNull ? null : (caps as JSObject).getProperty<JSAny?>('zoom'.toJS);
      if (z != null && !z.isUndefinedOrNull) {
        final o = z as JSObject;
        final min = (o.getProperty<JSNumber?>('min'.toJS)?.toDartDouble ?? 1), max = (o.getProperty<JSNumber?>('max'.toJS)?.toDartDouble ?? 1);
        if (max > min + .05) {
          _nativeZoom = true;
          _minZoom = math.max(1, min);
          _maxZoom = math.min(max, 8);
        }
      }
    } catch (_) { /* لا قدرات: تقريب رقمي */ }
    _zoom.value = 1;
    _applyPreview();
  }

  @override
  Future<void> setZoom(double zoom) async {
    final z = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((z - _zoom.value).abs() < .001) return;
    _zoom.value = z;
    if (_nativeZoom) {
      try {
        final track = _stream?.getVideoTracks().toDart.firstOrNull;
        if (track != null) await track.applyConstraints({'advanced': [{'zoom': z}]}.jsify()! as web.MediaTrackConstraints).toDart;
        return;
      } catch (_) {
        // المتصفح أعلن القدرة ثم رفض القيد: نكمل رقمياً
        _nativeZoom = false;
        _maxZoom = 3;
        _zoom.value = z.clamp(1, 3).toDouble();
      }
    }
    _applyPreview();
  }

  /// المعاينة: المرآة للكاميرا الأمامية، والتكبير الرقمي بـ transform (البصري يغيّر الإطار نفسه فلا حاجة له).
  void _applyPreview() {
    final v = _video;
    if (v == null) return;
    final mirror = _front ? 'scaleX(-1)' : '';
    final zoomT = _digital > 1.001 ? 'scale(${_digital.toStringAsFixed(3)})' : '';
    v.style
      ..transformOrigin = 'center center'
      ..transform = [mirror, zoomT].where((s) => s.isNotEmpty).join(' ').ifEmpty('none');
  }

  /// قرص إصبعين على المعاينة يغيّر التقريب (عنصر <video> يستقبل اللمس مباشرة لا Flutter)، وعجلة الفأرة على الحاسوب.
  void _attachGestures(web.HTMLVideoElement v) {
    if (_listenersOn) return;
    _listenersOn = true;
    v.style.touchAction = 'none';
    double dist(web.TouchList t) {
      final a = t.item(0)!, b = t.item(1)!;
      final dx = (a.clientX - b.clientX).toDouble(), dy = (a.clientY - b.clientY).toDouble();
      return math.sqrt(dx * dx + dy * dy);
    }
    v.addEventListener('touchstart', ((web.TouchEvent e) {
      if (e.touches.length == 2) { _pinchStartDist = dist(e.touches); _pinchStartZoom = _zoom.value; e.preventDefault(); }
    }).toJS, web.AddEventListenerOptions(passive: false));
    v.addEventListener('touchmove', ((web.TouchEvent e) {
      if (e.touches.length == 2 && _pinchStartDist > 0) {
        e.preventDefault();
        final ratio = dist(e.touches) / _pinchStartDist;
        setZoom(_pinchStartZoom * ratio);
      }
    }).toJS, web.AddEventListenerOptions(passive: false));
    v.addEventListener('touchend', ((web.TouchEvent e) { if (e.touches.length < 2) _pinchStartDist = 0; }).toJS);
    v.addEventListener('wheel', ((web.WheelEvent e) {
      e.preventDefault();
      setZoom(_zoom.value * (e.deltaY < 0 ? 1.08 : 1 / 1.08));
    }).toJS, web.AddEventListenerOptions(passive: false));
  }

  /// مستطيل القصّ في إطار الفيديو للتقريب الرقمي (مركز الإطار).
  ({double sx, double sy, double sw, double sh}) _crop(int w, int h) {
    final z = _digital;
    final sw = w / z, sh = h / z;
    return (sx: (w - sw) / 2, sy: (h - sh) / 2, sw: sw, sh: sh);
  }

  void _stopTracks() {
    final s = _stream;
    if (s != null) {
      for (final t in s.getTracks().toDart) {
        t.stop();
      }
    }
    _stream = null;
  }

  @override
  Widget view() {
    if (!_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        final v = _video ??= web.HTMLVideoElement()
          ..autoplay = true
          ..muted = true
          ..setAttribute('playsinline', 'true');
        v.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'cover'
          ..background = '#000';
        if (_stream != null && v.srcObject == null) v.srcObject = _stream;
        return v;
      });
    }
    return HtmlElementView(viewType: _viewId);
  }

  @override
  Future<void> flip() async {
    _front = !_front;
    await _open();
  }

  @override
  Future<CameraShot?> capturePhoto() async {
    final v = _video;
    if (v == null || v.videoWidth == 0) return null;
    final w = v.videoWidth, h = v.videoHeight;
    final scale = _maxSide / (w > h ? w : h);
    final cw = (w * (scale < 1 ? scale : 1)).round(), ch = (h * (scale < 1 ? scale : 1)).round();
    final canvas = web.HTMLCanvasElement()..width = cw..height = ch;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    if (_front) {
      // الكاميرا الأمامية تُعرض معكوسة كالمرآة؛ نلتقطها كما يراها المستخدم
      ctx.translate(cw.toDouble(), 0);
      ctx.scale(-1, 1);
    }
    // التقريب الرقمي: نرسم مركز الإطار المقصوص على القماش كله
    final c = _crop(w, h);
    ctx.drawImage(v, c.sx, c.sy, c.sw, c.sh, 0, 0, cw.toDouble(), ch.toDouble());
    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', 0.9.toJS);
    final blob = await done.future;
    if (blob == null) return null;
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    return (bytes: bytes, mime: 'image/jpeg', name: 'photo.jpg', durationSec: null);
  }

  static const _videoTypes = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm'];

  /// بث مقصوص للتسجيل مع التقريب الرقمي: إطارات الفيديو تُرسم مقصوصة في canvas (حتى 1280 بكسل) ويُدمج صوت المسار الأصلي.
  web.MediaStream? _croppedStream(web.MediaStream s) {
    final v = _video;
    if (v == null || v.videoWidth == 0 || _digital <= 1.001) return null;
    try {
      final w = v.videoWidth, h = v.videoHeight;
      final scale = math.min(1.0, 1280 / math.max(w, h));
      final cw = (w * scale).round(), ch = (h * scale).round();
      final canvas = web.HTMLCanvasElement()..width = cw..height = ch;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      void draw() {
        final c = _crop(v.videoWidth, v.videoHeight);
        ctx.resetTransform();
        if (_front) { ctx.translate(cw.toDouble(), 0); ctx.scale(-1, 1); }
        ctx.drawImage(v, c.sx, c.sy, c.sw, c.sh, 0, 0, cw.toDouble(), ch.toDouble());
      }
      draw();
      final cs = (canvas as JSObject).callMethod<web.MediaStream>('captureStream'.toJS, 30.toJS);
      final tracks = <web.MediaStreamTrack>[...cs.getVideoTracks().toDart, ...s.getAudioTracks().toDart];
      _cropTimer?.cancel();
      _cropTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => draw());
      return _cropStream = web.MediaStream(tracks.toJS);
    } catch (_) {
      return null; // المتصفح لا يدعم بث القماش: نسجّل الإطار الكامل
    }
  }

  void _stopCrop() {
    _cropTimer?.cancel();
    _cropTimer = null;
    final cs = _cropStream;
    if (cs != null) { for (final t in cs.getVideoTracks().toDart) { t.stop(); } }
    _cropStream = null;
  }

  @override
  Future<void> startVideo() async {
    final s = _stream;
    if (s == null || _rec != null) return;
    _chunks.clear();
    _recMime = _videoTypes.firstWhere((t) => web.MediaRecorder.isTypeSupported(t), orElse: () => '');
    final src = _croppedStream(s) ?? s;
    final rec = _recMime.isEmpty ? web.MediaRecorder(src) : web.MediaRecorder(src, web.MediaRecorderOptions(mimeType: _recMime, videoBitsPerSecond: 2500000));
    rec.ondataavailable = ((web.BlobEvent e) { if (e.data.size > 0) _chunks.add(e.data); }).toJS;
    rec.start(500);
    _rec = rec;
    _recStart = DateTime.now();
  }

  @override
  Future<CameraShot?> stopVideo() async {
    final rec = _rec;
    if (rec == null) return null;
    _rec = null;
    final stopped = Completer<void>();
    rec.onstop = ((web.Event _) { if (!stopped.isCompleted) stopped.complete(); }).toJS;
    if (rec.state != 'inactive') rec.stop();
    await stopped.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    _stopCrop();
    final sec = _recStart == null ? null : DateTime.now().difference(_recStart!).inSeconds;
    _recStart = null;
    if (_chunks.isEmpty) return null;
    final type = (rec.mimeType.isNotEmpty ? rec.mimeType : _recMime).split(';').first.trim();
    final blob = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: type));
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    final mime = type.isEmpty ? 'video/webm' : type;
    return (bytes: bytes, mime: mime, name: mime == 'video/mp4' ? 'clip.mp4' : 'clip.webm', durationSec: sec);
  }

  @override
  void dispose() {
    final rec = _rec;
    if (rec != null && rec.state != 'inactive') rec.stop();
    _rec = null;
    _stopCrop();
    _stopTracks();
    final v = _video;
    if (v != null) {
      v.srcObject = null;
      v.remove();
    }
    _video = null;
  }
}

extension on String {
  String ifEmpty(String alt) => isEmpty ? alt : this;
}
