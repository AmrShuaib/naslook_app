import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// الويب: رفع عبر XMLHttpRequest لأن عميل http (fetch) لا يعطي نسبة ما أُرسل، والمستخدم يحتاج أن يرى رفع الفيديو يتقدّم.
const xhrUploadSupported = true;

/// يرسل [bytes] ويبلّغ [onProgress] بنسبة ما أُرسل (0..1). يعيد الرد كما يعيده عميل http حتى يمر بمعالجة الأخطاء نفسها.
Future<http.Response> xhrPost(Uri uri, Map<String, String> headers, Uint8List bytes, void Function(double sent) onProgress) {
  final done = Completer<http.Response>();
  final xhr = web.XMLHttpRequest();
  xhr.open('POST', uri.toString());
  headers.forEach((k, v) => xhr.setRequestHeader(k, v));
  xhr.upload.onprogress = ((web.ProgressEvent e) {
    if (e.lengthComputable && e.total > 0) onProgress((e.loaded / e.total).clamp(0.0, 1.0).toDouble());
  }).toJS;
  xhr.onload = ((web.Event _) {
    if (done.isCompleted) return;
    final type = xhr.getResponseHeader('content-type');
    done.complete(http.Response.bytes(utf8.encode(xhr.responseText), xhr.status, headers: {if (type != null) 'content-type': type}));
  }).toJS;
  void fail(web.Event _) {
    if (!done.isCompleted) done.completeError(http.ClientException('تعذّر الاتصال بالخادم', uri));
  }
  xhr.onerror = fail.toJS;
  xhr.onabort = fail.toJS;
  xhr.send(bytes.toJS);
  return done.future;
}
