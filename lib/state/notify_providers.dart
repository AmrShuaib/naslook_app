import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notify_api.dart';
import '../core/notify/message_sound.dart';
import 'app_state.dart';
import 'safety_providers.dart';

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

/// إعداد جرس الرسائل الجديدة (مفعّل افتراضياً، محفوظ محلياً).
final messageSoundProvider = StateNotifierProvider<MessageSoundSetting, bool>((_) => MessageSoundSetting());

class MessageSoundSetting extends StateNotifier<bool> {
  MessageSoundSetting() : super(true) {
    MessageSound.loadEnabled().then((v) { if (mounted) state = v; });
  }
  Future<void> set(bool v) async {
    state = v;
    await MessageSound.saveEnabled(v);
  }
}

/// يقرع الجرس عند وصول رسالة من شخص آخر عبر الاتصال المباشر (غير مكتوم، والإعداد مفعّل، وبفاصل زمني بين الجرسين).
class MessageBell {
  /// قارئ المزوّدات (WidgetRef.read أو ProviderContainer.read).
  final T Function<T>(ProviderListenable<T> provider) read;
  MessageBell(this.read);

  static bool isMessageEvent(Map<String, dynamic> e) {
    final ev = e['event'];
    return (ev == null && e['senderId'] != null && e['content'] != null) || ev == 'message' || ev == 'new-message';
  }

  static String? senderOf(Map<String, dynamic> e) {
    final m = e['message'];
    final s = e['senderId'] ?? e['sender_id'] ?? e['from'] ?? (m is Map ? (m['sender_id'] ?? m['senderId']) : null);
    return s?.toString();
  }

  /// يرجع true إن قُرع الجرس.
  bool handle(Map<String, dynamic> e) {
    if (!isMessageEvent(e)) return false;
    final myId = read(appStateProvider).user?.id ?? '';
    final ring = MessageSound.shouldRing(enabled: read(messageSoundProvider), senderId: senderOf(e), myId: myId, mutedPeers: read(mutedPeersProvider));
    if (ring) MessageSound.play();
    return ring;
  }
}
