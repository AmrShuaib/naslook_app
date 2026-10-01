import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/live_api.dart';
import 'app_state.dart';

/// «القناة الحية»: حلقة انتظار طويل على /live/wait تعمل ما دام أحد يستمع (الخط الزمني، خريطة الرئيسية) وتتوقف وحدها حين
/// يغادر آخر مستمع. الطلب يبقى محجوزاً عند الخادم حتى يصل حدث أو تنقضي المهلة ثم يُعاد فتحه فوراً، فيصل الجديد في لحظته
/// بتكلفة طلب واحد كل ~25 ثانية للجهاز الصامت. عند الخطأ تراجع أسّي (4…32 ث) ويبقى الجلب الدوري في الصفحات احتياطاً.
class LiveChannel {
  LiveChannel(this._api, {this.waitSeconds = 25, this.gap = const Duration(seconds: 1)});
  final ApiClient _api;
  final int waitSeconds;
  /// استراحة بعد ردّ فارغ حتى لا تدور الحلقة بلا توقف لو عاد الخادم فوراً (خادم وهمي أو وسيط يقطع الانتظار)
  final Duration gap;
  /// آخر طلب نجح: النقطة الحمراء في الخط الزمني تنبض معه وتبهت حين تنقطع القناة
  final online = ValueNotifier<bool>(false);
  late final StreamController<LiveEvent> _ctrl = StreamController<LiveEvent>.broadcast(onListen: _start, onCancel: _wake);
  int? _cursor;
  bool _running = false, _closed = false;
  int _fails = 0;
  Timer? _sleep;
  Completer<void>? _sleeping;

  Stream<LiveEvent> get events => _ctrl.stream;
  int? get cursor => _cursor;
  bool get running => _running;

  void _start() {
    if (!_running && !_closed) _run();
  }

  Future<void> _run() async {
    _running = true;
    while (!_closed && _ctrl.hasListener) {
      LiveBatch b;
      try {
        b = await _api.liveWait(after: _cursor, timeoutSec: waitSeconds);
      } catch (_) {
        if (_closed) break;
        _fails = min(_fails + 1, 4);
        if (online.value) online.value = false;
        await _pause(Duration(seconds: 2 << _fails));
        continue;
      }
      if (_closed) break;
      _fails = 0;
      _cursor = b.seq;
      if (!online.value) online.value = true;
      if (_ctrl.hasListener) {
        if (b.reset) _ctrl.add(LiveEvent.reset);
        for (final e in b.events) {
          _ctrl.add(e);
        }
      }
      if (b.retryIn != null) {
        await _pause(Duration(seconds: b.retryIn!.clamp(1, 60)));
      } else if (b.events.isEmpty && !b.reset) {
        await _pause(gap);
      }
    }
    _running = false;
  }

  /// نوم قابل للإيقاظ: مغادرة آخر مستمع أو الإغلاق يقطعه فوراً فلا يبقى مؤقّت معلّق
  Future<void> _pause(Duration d) {
    final c = Completer<void>();
    _sleeping = c;
    _sleep = Timer(d, () { if (!c.isCompleted) c.complete(); });
    return c.future;
  }

  void _wake() {
    _sleep?.cancel();
    _sleep = null;
    final c = _sleeping;
    _sleeping = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  void dispose() {
    _closed = true;
    _wake();
    _ctrl.close();
    online.dispose();
  }
}

/// قناة واحدة للجلسة؛ تُعاد مع تغيّر الحساب لأن عميل الواجهة يتغيّر معه.
final liveChannelProvider = Provider<LiveChannel>((ref) {
  final c = LiveChannel(ref.watch(apiClientProvider));
  ref.onDispose(c.dispose);
  return c;
});
