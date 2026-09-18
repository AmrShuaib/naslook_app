import 'dart:typed_data';
import 'dart:ui' as ui;

import 'encode.dart';

Future<EncodedImage> encodeImage(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('encode failed');
  return (bytes: data.buffer.asUint8List(), mime: 'image/png');
}

Future<({Uint8List bytes, String mime, String name})> trimAudio(Uint8List bytes, String mime, {required Duration start, required Duration end}) async =>
    (bytes: bytes, mime: mime, name: 'voice.${mime == 'audio/mp4' ? 'm4a' : mime == 'audio/ogg' ? 'ogg' : 'weba'}');
