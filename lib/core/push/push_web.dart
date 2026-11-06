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

/// الاشتراك القائم إن كان الإذن ممنوحاً (يسجّل عامل الخدمة فيتحدّث مع كل إقلاع)؛ PushService يقرر هل يُعاد إرساله للخادم.
Future<Map<String, dynamic>?> pushGrantedSubscription() async {
  if (pushPermission() != 'granted') return null;
  final sub = await _current();
  return sub == null ? null : _toMap(sub);
}

/// الاشتراك الحالي دون تسجيل عامل الخدمة ولا انتظار جاهزيته (serviceWorker.ready لا يعود أبداً إن لم يُسجَّل عامل):
/// للخروج، حيث لا نريد تسجيل شيء ولا تعليق الخروج.
Future<web.PushSubscription?> _existing() async {
  if (!pushSupported()) return null;
  final reg = await web.window.navigator.serviceWorker.getRegistration().toDart;
  if (reg == null) return null;
  return reg.pushManager.getSubscription().toDart;
}

/// الخروج أو تبديل الحساب: الاشتراك يخص المتصفح لا الحساب، فلو بقي لوصلت إشعارات الحساب السابق لمن يدخل بعده.
/// يُلغى محلياً (الضمان: خدمة الدفع ترد 410 على أي إرسال لاحق فيحذفه الخادم بنفسه)، ويعيد عنوانه ليحذفه PushService من
/// الخادم ما دام الرمز صالحاً. dropped = لا اشتراك على هذا المتصفح بعد الآن.
Future<({String? endpoint, bool dropped})> pushDropLocal() async {
  final sub = await _existing();
  if (sub == null) return (endpoint: null, dropped: true);
  final endpoint = sub.endpoint;
  var dropped = false;
  try {
    dropped = (await sub.unsubscribe().toDart).toDart;
  } catch (_) {}
  return (endpoint: endpoint, dropped: dropped);
}

var _listening = false;

/// نقرة إشعار والتطبيق مفتوح: عامل الخدمة يرسل الرابط برسالة (وينتظر تأكيداً عبر المنفذ وإلا يعيد تحميل التبويب على الرابط)،
/// وتغيّر الجزء إلى `#/n/<id>` (عامل خدمة أقدم ما زال يغيّر الرابط فقط) يُعامل بالطريقة نفسها. [onOpen] يعيد true إن عرف الرابط.
void pushListenOpens(bool Function(String url) onOpen) {
  if (_listening) return;
  _listening = true;
  _dropOpenParam();
  try {
    if (web.window.navigator.has('serviceWorker')) {
      final sw = web.window.navigator.serviceWorker;
      sw.addEventListener(
          'message',
          ((web.MessageEvent e) {
            final d = e.data.dartify();
            if (d is! Map || d['type'] != 'naslife:open') return;
            final ok = onOpen(d['url']?.toString() ?? '');
            final ports = e.ports.toDart;
            if (ok && ports.isNotEmpty) ports.first.postMessage('ok'.toJS);
          }).toJS);
      // الرسائل من عامل الخدمة تنتظر في طابور حتى يبدأ استقبالها
      sw.startMessages();
    }
    web.window.addEventListener('hashchange', ((web.Event _) { onOpen(web.window.location.href); }).toJS);
  } catch (_) {}
}

/// عامل الخدمة يعيد تحميل تبويب لم يرد بإضافة `?open=<وقت>` ليجبر التحميل الكامل؛ بعد الإقلاع (وقد قُرئ الجزء) يُزال من
/// شريط العنوان حتى لا يُنسخ أو يُشارك. المسار والجزء لا يتغيران.
void _dropOpenParam() {
  try {
    final loc = web.window.location;
    final search = loc.search;
    if (!search.contains('open=')) return;
    final kept = search.substring(1).split('&').where((p) => p.isNotEmpty && !p.startsWith('open=')).toList();
    web.window.history.replaceState(web.window.history.state, '', '${loc.pathname}${kept.isEmpty ? '' : '?${kept.join('&')}'}${loc.hash}');
  } catch (_) {}
}
