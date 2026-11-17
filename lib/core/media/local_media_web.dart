import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> createLocalUrl(Uint8List bytes, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime.isEmpty ? 'video/mp4' : mime));
  return web.URL.createObjectURL(blob);
}

void releaseLocalUrl(String url) => web.URL.revokeObjectURL(url);
