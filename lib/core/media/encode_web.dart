import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

import 'encode.dart';

/// JPEG عبر canvas: نقرأ RGBA من dart:ui ونضعها في ImageData ثم toBlob('image/jpeg').
Future<EncodedImage> encodeImage(ui.Image image) async {
  final w = image.width, h = image.height;
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) throw StateError('encode failed');
  try {
    final canvas = web.HTMLCanvasElement()..width = w..height = h;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    final clamped = raw.buffer.asUint8ClampedList(raw.offsetInBytes, raw.lengthInBytes);
    final data = web.ImageData(clamped.toJS, w, h.toJS);
    ctx.putImageData(data, 0, 0);
    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', 0.88.toJS);
    final blob = await done.future;
    if (blob != null) return (bytes: (await blob.arrayBuffer().toDart).toDart.asUint8List(), mime: 'image/jpeg');
  } catch (_) {
    // نعود إلى PNG أدناه
  }
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) throw StateError('encode failed');
  return (bytes: png.buffer.asUint8List(), mime: 'image/png');
}

/// قصّ الصوت: فكّ عبر AudioContext.decodeAudioData ثم أخذ العينات بين الحدّين وترميز WAV (16-bit mono).
Future<({Uint8List bytes, String mime, String name})> trimAudio(Uint8List bytes, String mime, {required Duration start, required Duration end}) async {
  try {
    final ctx = web.AudioContext();
    final buf = await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
    final rate = buf.sampleRate.round();
    final total = buf.length;
    final s = ((start.inMilliseconds / 1000) * rate).round().clamp(0, total);
    final e = ((end.inMilliseconds / 1000) * rate).round().clamp(s, total);
    final n = e - s;
    if (n <= 0) return (bytes: bytes, mime: mime, name: 'voice.weba');
    // متوسط القنوات إلى قناة واحدة
    final channels = buf.numberOfChannels;
    final mono = Float32List(n);
    for (var c = 0; c < channels; c++) {
      final data = buf.getChannelData(c).toDart;
      for (var i = 0; i < n; i++) {
        mono[i] += data[s + i] / channels;
      }
    }
    await ctx.close().toDart;
    return (bytes: _wav(mono, rate), mime: 'audio/wav', name: 'voice.wav');
  } catch (_) {
    return (bytes: bytes, mime: mime, name: 'voice.weba');
  }
}

Uint8List _wav(Float32List samples, int rate) {
  final n = samples.length;
  final out = ByteData(44 + n * 2);
  void str(int o, String s) { for (var i = 0; i < s.length; i++) { out.setUint8(o + i, s.codeUnitAt(i)); } }
  str(0, 'RIFF'); out.setUint32(4, 36 + n * 2, Endian.little); str(8, 'WAVE'); str(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); out.setUint16(20, 1, Endian.little); out.setUint16(22, 1, Endian.little);
  out.setUint32(24, rate, Endian.little); out.setUint32(28, rate * 2, Endian.little); out.setUint16(32, 2, Endian.little); out.setUint16(34, 16, Endian.little);
  str(36, 'data'); out.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, v, Endian.little);
  }
  return out.buffer.asUint8List();
}
