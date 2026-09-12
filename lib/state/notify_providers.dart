import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notify_api.dart';
import 'app_state.dart';

/// فترة استطلاع عدد الإشعارات غير المقروءة؛ null يعطّل المؤقّت (في الاختبارات).
final notifyPollIntervalProvider = Provider<Duration?>((_) => const Duration(seconds: 45));

/// عدد الإشعارات غير المقروءة: يُجلب فوراً ثم دورياً، ويُعاد جلبه عند invalidate بعد أي إجراء.
final notifyUnreadProvider = StreamProvider<int>((ref) {
  final api = ref.watch(apiClientProvider);
  final ctl = StreamController<int>();
  Future<void> tick() async {
    try {
      final n = await api.notifyUnread();
      if (!ctl.isClosed) ctl.add(n);
    } catch (_) {
      // الخادم غير متاح مؤقتاً: نبقي آخر قيمة
    }
  }
  tick();
  final every = ref.watch(notifyPollIntervalProvider);
  final timer = every == null ? null : Timer.periodic(every, (_) => tick());
  ref.onDispose(() {
    timer?.cancel();
    ctl.close();
  });
  return ctl.stream;
});

final notificationsProvider = FutureProvider<NotifyPage>((ref) => ref.watch(apiClientProvider).notifications());

/// معرّف إشعار وصل عبر رابط إشعار الدفع (`#/n/<id>`) عند الإقلاع؛ يُفتح بعد الدخول ثم يُصفَّر.
String? pendingNotificationId;

/// يُستدعى في main() قبل أن يعيد محرك Flutter كتابة الجزء (#/) من الرابط.
void capturePendingNotification([Uri? uri]) {
  final frag = (uri ?? Uri.base).fragment;
  pendingNotificationId = RegExp(r'^/?n/([0-9a-fA-F-]{36})').firstMatch(frag)?.group(1);
}
