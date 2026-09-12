import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../api/client.dart';
import '../../api/naslife_api.dart';

const _swUrl = 'push_sw.js';

bool pushSupported() {
  try {
    return web.window.navigator.has('serviceWorker') && web.window.has('PushManager') && web.window.has('Notification');
  } catch (_) {
    return false;
  }
}

String pushPermission() {
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'denied';
  }
}

Future<web.ServiceWorkerRegistration> _registration() async {
  // التسجيل آمن للتكرار؛ هذا العامل لا يخزّن أي ملفات، فقط يعرض الإشعارات
  await web.window.navigator.serviceWorker.register(_swUrl.toJS).toDart;
  return web.window.navigator.serviceWorker.ready.toDart;
}

Future<web.PushSubscription?> _current() async {
  if (!pushSupported()) return null;
  final reg = await _registration();
  return reg.pushManager.getSubscription().toDart;
}

Map<String, dynamic> _toMap(web.PushSubscription sub) {
  final json = (globalContext['JSON'] as JSObject).callMethod<JSString>('stringify'.toJS, sub.toJSON()).toDart;
  return Map<String, dynamic>.from(jsonDecode(json) as Map);
}

Uint8List _keyBytes(String b64url) {
  var s = b64url.replaceAll('-', '+').replaceAll('_', '/');
  while (s.length % 4 != 0) {
    s += '=';
  }
  return base64.decode(s);
}

Future<bool> pushIsSubscribed() async {
  try {
    return (await _current()) != null;
  } catch (_) {
    return false;
  }
}

Future<bool> pushSubscribe(ApiClient api) async {
  if (!pushSupported()) return false;
  final perm = (await web.Notification.requestPermission().toDart).toDart;
  if (perm != 'granted') return false;
  final reg = await _registration();
  var sub = await reg.pushManager.getSubscription().toDart;
  if (sub == null) {
    final key = await api.pushKey();
    if (key.isEmpty) throw const ApiException(500, 'الخادم لم يُرجع مفتاح الإشعارات');
    sub = await reg.pushManager
        .subscribe(web.PushSubscriptionOptionsInit(userVisibleOnly: true, applicationServerKey: _keyBytes(key).toJS))
        .toDart;
  }
  await api.pushSubscribe(_toMap(sub));
  return true;
}

Future<void> pushUnsubscribe(ApiClient api) async {
  final sub = await _current();
  if (sub == null) return;
  try {
    await api.pushUnsubscribe(sub.endpoint);
  } catch (_) {}
  await sub.unsubscribe().toDart;
}

Future<void> pushResubscribeIfGranted(ApiClient api) async {
  try {
    if (pushPermission() != 'granted') return;
    final sub = await _current();
    if (sub != null) await api.pushSubscribe(_toMap(sub));
  } catch (_) {}
}
