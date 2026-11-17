import 'dart:typed_data';

import 'native_io.dart';

Future<String?> createLocalUrl(Uint8List bytes, String mime) async {
  final ext = mime.contains('webm') ? 'webm' : mime.contains('quicktime') ? 'mov' : 'mp4';
  final path = await writeTempFile(bytes, prefix: 'preview', ext: ext);
  return Uri.file(path).toString();
}

void releaseLocalUrl(String url) => deleteQuietly(Uri.parse(url).toFilePath());
