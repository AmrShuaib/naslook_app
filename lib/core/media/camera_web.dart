import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

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

  @override
  bool get front => _front;
  @override
  bool get recording => _rec != null;

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
      ..background = '#000'
      ..transform = _front ? 'scaleX(-1)' : 'none';
    v.srcObject = _stream;
    try {
      await v.play().toDart;
    } catch (_) {
      // autoplay يعمل لأن العنصر صامت؛ إن رُفض نتركه يبدأ عند أول تفاعل
    }
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
    ctx.drawImage(v, 0, 0, cw.toDouble(), ch.toDouble());
    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', 0.9.toJS);
    final blob = await done.future;
    if (blob == null) return null;
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    return (bytes: bytes, mime: 'image/jpeg', name: 'photo.jpg', durationSec: null);
  }

  static const _videoTypes = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm'];

  @override
  Future<void> startVideo() async {
    final s = _stream;
    if (s == null || _rec != null) return;
    _chunks.clear();
    _recMime = _videoTypes.firstWhere((t) => web.MediaRecorder.isTypeSupported(t), orElse: () => '');
    final rec = _recMime.isEmpty ? web.MediaRecorder(s) : web.MediaRecorder(s, web.MediaRecorderOptions(mimeType: _recMime, videoBitsPerSecond: 2500000));
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
    _stopTracks();
    final v = _video;
    if (v != null) {
      v.srcObject = null;
      v.remove();
    }
    _video = null;
  }
}
