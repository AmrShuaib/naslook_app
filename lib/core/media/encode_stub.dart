import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'encode.dart';

/// JPEG بجودة 85 عبر حزمة image (Dart خالص) في عزلة منفصلة: PNG بالحجم الكامل كان يبلغ عدة ميغابايت للصورة.
Future<EncodedImage> encodeImage(ui.Image image) async {
  final w = image.width, h = image.height;
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) throw StateError('encode failed');
  try {
    final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final jpg = await compute(_jpeg, (w: w, h: h, rgba: rgba));
    return (bytes: jpg, mime: 'image/jpeg');
  } catch (_) {
    // احتياط نادر: PNG من dart:ui
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('encode failed');
    return (bytes: png.buffer.asUint8List(), mime: 'image/png');
  }
}

Uint8List _jpeg(({int w, int h, Uint8List rgba}) a) {
  final im = img.Image.fromBytes(width: a.w, height: a.h, bytes: a.rgba.buffer, bytesOffset: a.rgba.offsetInBytes, numChannels: 4);
  return img.encodeJpg(im, quality: 85);
}

Future<({Uint8List bytes, String mime, String name})> trimAudio(Uint8List bytes, String mime, {required Duration start, required Duration end}) async =>
    (bytes: bytes, mime: mime, name: 'voice.${mime == 'audio/mp4' ? 'm4a' : mime == 'audio/ogg' ? 'ogg' : 'weba'}');

const bool audioTrimSupported = false;
