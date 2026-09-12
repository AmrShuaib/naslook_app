import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'media.dart';

bool get available => true;

const _maxSide = 1600;
const _jpegQuality = 0.85;

/// يفتح منتقي الملفات ويقرأ الملف عبر Blob.arrayBuffer مباشرة (بلا XHR على رابط blob).
Future<PickedMedia?> pick(String kind) async {
  final input = web.HTMLInputElement()..type = 'file';
  input.accept = kind == 'video' ? 'video/*' : 'image/*';
  if (kind == 'camera') input.setAttribute('capture', 'environment');
  input.style.display = 'none';
  web.document.body!.append(input);
  final done = Completer<PickedMedia?>();
  Timer? cancelTimer;
  void finish(PickedMedia? v) {
    cancelTimer?.cancel();
    input.remove();
    if (!done.isCompleted) done.complete(v);
  }
  // الدالة المحوّلة إلى JS يجب ألا تعيد Future؛ نبدأ القراءة غير المتزامنة ونعود فوراً
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    _read(file, kind).then(finish, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
      input.remove();
    });
  }).toJS;
  // إن عاد التركيز للنافذة ولم يُختر ملف خلال ثوانٍ فالمستخدم ألغى
  void onFocus(web.Event _) {
    cancelTimer?.cancel();
    cancelTimer = Timer(const Duration(seconds: 4), () { if (input.files?.length == 0) finish(null); });
  }
  final focusHandler = onFocus.toJS;
  web.window.addEventListener('focus', focusHandler);
  input.click();
  try {
    return await done.future.timeout(const Duration(minutes: 5), onTimeout: () => null);
  } finally {
    web.window.removeEventListener('focus', focusHandler);
  }
}

Future<PickedMedia> _read(web.File file, String kind) async {
  final name = file.name.isNotEmpty ? file.name : (kind == 'video' ? 'video' : 'photo.jpg');
  var mime = file.type;
  if (kind != 'video') {
    final small = await _downscale(file);
    if (small != null) return PickedMedia(small, 'image/jpeg', '${name.split('.').first}.jpg');
  }
  final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
  if (mime.isEmpty) mime = kind == 'video' ? 'video/mp4' : 'image/jpeg';
  return PickedMedia(bytes, mime, name);
}

/// يصغّر الصور الكبيرة عبر canvas إلى 1600 بكسل كحد أقصى للضلع (مع احترام اتجاه EXIF).
Future<Uint8List?> _downscale(web.File file) async {
  try {
    final bmp = await web.window.createImageBitmap(file).toDart;
    final w = bmp.width, h = bmp.height;
    if (w <= _maxSide && h <= _maxSide && file.size < 1200000) return null;
    final scale = _maxSide / (w > h ? w : h);
    final cw = (w * (scale < 1 ? scale : 1)).round(), ch = (h * (scale < 1 ? scale : 1)).round();
    final canvas = web.HTMLCanvasElement()..width = cw..height = ch;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(bmp, 0, 0, cw.toDouble(), ch.toDouble());
    final blobDone = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => blobDone.complete(b)).toJS, 'image/jpeg', _jpegQuality.toJS);
    final blob = await blobDone.future;
    if (blob == null) return null;
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

VoiceRecorder createRecorder() => _WebRecorder();

class _WebRecorder implements VoiceRecorder {
  static const _preferred = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus'];
  web.MediaStream? _stream;
  web.MediaRecorder? _rec;
  final _chunks = <web.Blob>[];
  String _mime = '';

  @override
  Future<void> start() async {
    _chunks.clear();
    _stream = await web.window.navigator.mediaDevices.getUserMedia(web.MediaStreamConstraints(audio: true.toJS)).toDart;
    _mime = _preferred.firstWhere((t) => web.MediaRecorder.isTypeSupported(t), orElse: () => '');
    _rec = _mime.isEmpty
        ? web.MediaRecorder(_stream!)
        : web.MediaRecorder(_stream!, web.MediaRecorderOptions(mimeType: _mime, audioBitsPerSecond: 64000));
    _rec!.ondataavailable = ((web.BlobEvent e) { if (e.data.size > 0) _chunks.add(e.data); }).toJS;
    _rec!.start(1000);
  }

  void _release() {
    final s = _stream;
    if (s != null) {
      for (final t in s.getTracks().toDart) {
        t.stop();
      }
    }
    _stream = null;
    _rec = null;
  }

  @override
  Future<PickedMedia?> stop() async {
    final rec = _rec;
    if (rec == null) return null;
    final stopped = Completer<void>();
    rec.onstop = ((web.Event _) { if (!stopped.isCompleted) stopped.complete(); }).toJS;
    if (rec.state != 'inactive') rec.stop();
    await stopped.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    final type = (rec.mimeType.isNotEmpty ? rec.mimeType : _mime).split(';').first.trim();
    _release();
    if (_chunks.isEmpty) return null;
    final blob = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: type));
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    final mime = type.isEmpty ? 'audio/webm' : type;
    final ext = switch (mime) { 'audio/mp4' => 'm4a', 'audio/ogg' => 'ogg', 'audio/mpeg' => 'mp3', _ => 'weba' };
    return PickedMedia(bytes, mime, 'voice.$ext');
  }

  @override
  Future<void> cancel() async {
    final rec = _rec;
    if (rec != null && rec.state != 'inactive') rec.stop();
    _release();
    _chunks.clear();
  }
}
