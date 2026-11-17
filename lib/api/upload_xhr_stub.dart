import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// خارج الويب لا رفع بنسبة تقدّم: المستدعي يستخدم عميل http العادي.
const xhrUploadSupported = false;

Future<http.Response> xhrPost(Uri uri, Map<String, String> headers, Uint8List bytes, void Function(double sent) onProgress) => throw UnsupportedError('xhr');
