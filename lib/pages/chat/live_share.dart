// مشاركة موقعي المباشر من المحادثة: ورقة تختار المدة (15 دقيقة / ساعة / 8 ساعات) وتشرح من يرى ماذا، ثم تنشئ جلسة في
// server/chat_live.js وترسل رسالة "/live <id>" عادية (تظهر بطاقة عند الطرفين) وتدفع موقع الجهاز كل عشر ثوانٍ ما دام التطبيق
// مفتوحاً. المتحكّم واحد لكل طرف (singleton) حتى لا تتكرر المؤقّتات عند الخروج من المحادثة والعودة إليها.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/chat_live_api.dart';
import '../../api/client.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/location.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

String _errText(Object e) => e is ApiException ? e.message : e.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');

/// المدد المتاحة بالدقائق وتسمياتها.
const liveShareMinutes = [(15, '15 دقيقة'), (60, 'ساعة'), (480, '8 ساعات')];

String liveDurationLabel(int minutes) => liveShareMinutes.firstWhere((e) => e.$1 == minutes, orElse: () => (minutes, '$minutes دقيقة')).$2;

/// يدفع موقع الجهاز إلى جلسة نشطة كل [pushEvery]؛ واحد لكل طرف.
class LiveShareController extends ChangeNotifier {
  static final _byPeer = <String, LiveShareController>{};
  /// فاصل الدفع (ثابت للتطبيق؛ الاختبارات تحرّك الزمن الوهمي).
  static const pushEvery = Duration(seconds: 10);

  final String peerId;
  LiveShareController._(this.peerId);

  static LiveShareController of(String peerId) => _byPeer.putIfAbsent(peerId, () => LiveShareController._(peerId));
  /// المتحكّم النشط مع هذا الطرف إن وُجد.
  static LiveShareController? activeFor(String peerId) { final c = _byPeer[peerId]; return c != null && c.active ? c : null; }
  /// يوقف جلسة بمعرّفها من أي شاشة (بطاقة المُشارِك): عبر متحكّمها إن كان حياً، وإلا بطلب DELETE مباشر.
  static Future<void> stopSession(ApiClient api, String id) async {
    for (final c in _byPeer.values) {
      if (c.id == id) return c.stop();
    }
    await api.liveStop(id);
  }
  /// يوقف كل المشاركات مع كل الأطراف: يستدعيه الدامج عند تسجيل الخروج (قبل مسح رمز الجلسة حتى يُغلق الخادم الجلسات أيضاً؛
  /// بعده تبقى مفتوحة حتى `until` لكن الدفع وقراءة GPS يتوقفان هنا على أي حال).
  static Future<void> stopAll({bool notifyServer = true}) async {
    final open = _byPeer.values.where((c) => c.id != null).toList();
    await Future.wait(open.map((c) => c.stop(notifyServer: notifyServer)));
  }
  /// للاختبارات: يلغي كل المؤقّتات وينسى المتحكّمات.
  static void resetForTests() { for (final c in _byPeer.values) { c._timer?.cancel(); } _byPeer.clear(); }

  ApiClient? _api;
  String? id;
  DateTime? until;
  Timer? _timer;
  bool _pushing = false;
  int pushes = 0;

  bool get active => id != null && until != null && until!.isAfter(DateTime.now());

  /// ينشئ الجلسة، يرسل رسالة `/live <id>`، يدفع الموقع الأول، ويبدأ المؤقّت. لا يصير المتحكّم «نشطاً» إلا بعد وصول الرسالة:
  /// إن فشل إرسالها تُغلق الجلسة فوراً (DELETE) ويُعاد الخطأ، فلا تبقى جلسة مفتوحة على الخادم بلا بطاقة عند الطرف الآخر.
  Future<LiveSession> start(ApiClient api, int minutes, LatLng first) async {
    if (id != null) await stop();
    _api = api;
    final s = await api.liveStart(peerId, minutes);
    try {
      await api.sendMessage(peerId, liveCode(s.id));
    } catch (_) {
      try { await api.liveStop(s.id); } catch (_) { /* الخادم يغلقها عند until على أي حال */ }
      rethrow;
    }
    id = s.id; until = s.until;
    await _push(first);
    if (active) _timer = Timer.periodic(pushEvery, (_) => _tick());
    notifyListeners();
    return s;
  }

  Future<void> _tick() async {
    if (!active) return stop(notifyServer: false);
    if (_pushing) return;
    _pushing = true;
    try {
      final loc = await DeviceLocation.current(timeout: const Duration(seconds: 8));
      if (loc != null && active) await _push(loc);
    } finally { _pushing = false; }
  }

  Future<void> _push(LatLng p) async {
    final api = _api, sid = id;
    if (api == null || sid == null) return;
    try {
      await api.livePush(sid, p.latitude, p.longitude);
      pushes++;
    } on ApiException catch (e) {
      // 409 انتهت أو أُوقفت من جهاز آخر، 404 حُذفت، 401/403 خرج من الحساب أو فُقدت الصلاحية: نكفّ عن الدفع وعن قراءة GPS
      if (e.statusCode == 409 || e.statusCode == 404 || e.isUnauthorized) await stop(notifyServer: false);
    } catch (_) { /* شبكة: نحاول في الدفعة التالية */ }
  }

  /// يوقف المشاركة: يلغي المؤقّت ويبلّغ الخادم (DELETE) ما لم يكن قد أنهاها هو.
  Future<void> stop({bool notifyServer = true}) async {
    _timer?.cancel(); _timer = null;
    final api = _api, sid = id;
    id = null; until = null;
    notifyListeners();
    if (notifyServer && api != null && sid != null) { try { await api.liveStop(sid); } catch (_) {} }
  }
}

/// ورقة «شارك موقعي المباشر» مع [peerId]: تختار المدة، تطلب الموقع (بسياق واضح)، وتبدأ الجلسة.
Future<void> showLiveShareSheet(BuildContext context, WidgetRef ref, String peerId) async {
  if (!requireAccount(context)) return;
  final api = ref.read(apiClientProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _LiveShareSheet(api: api, peerId: peerId),
  );
}

class _LiveShareSheet extends StatefulWidget {
  final ApiClient api;
  final String peerId;
  const _LiveShareSheet({required this.api, required this.peerId});
  @override
  State<_LiveShareSheet> createState() => _LiveShareSheetState();
}

class _LiveShareSheetState extends State<_LiveShareSheet> {
  int _minutes = 60;
  bool _busy = false;
  String? _error;
  bool _deniedForever = false;
  late final LiveShareController _ctl = LiveShareController.of(widget.peerId);

  @override
  void initState() { super.initState(); _ctl.addListener(_onCtl); }
  @override
  void dispose() { _ctl.removeListener(_onCtl); super.dispose(); }
  void _onCtl() { if (mounted) setState(() {}); }

  Future<void> _start() async {
    setState(() { _busy = true; _error = null; _deniedForever = false; });
    try {
      final loc = await DeviceLocation.current();
      if (!mounted) return;
      if (loc == null) {
        setState(() {
          _busy = false;
          _deniedForever = DeviceLocation.deniedForever || DeviceLocation.serviceDisabled;
          _error = DeviceLocation.serviceDisabled ? 'خدمة الموقع مطفأة في الجهاز' : 'تعذّر تحديد موقعك؛ اسمح بالوصول إلى الموقع ثم أعد المحاولة';
        });
        return;
      }
      final s = await _ctl.start(widget.api, _minutes, loc);
      if (!mounted) return;
      // التنبيه قبل الإغلاق: الورقة تُزال بعد الرسوم المتحركة وسياقها يبقى صالحاً الآن
      toast(context, 'بدأت مشاركة موقعك حتى ${clockOf(s.until)}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = _errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _ctl.active;
    // سطر الخطأ يظهر في الحالتين (نشطة أو لا) حتى لا يضيع إن تغيّرت الحالة أثناء المحاولة
    final errorLine = _error == null
        ? null
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Text(_error!, key: const Key('live-error'), style: const TextStyle(color: Joy.danger, fontSize: 12.5)),
            if (_deniedForever) TextButton.icon(onPressed: () => DeviceLocation.openSettings(), icon: const Icon(Icons.settings_outlined, size: 18), label: const Text('افتح الإعدادات')),
          ]);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Joy.primarySoft, child: Icon(Icons.share_location_rounded, color: Joy.primary)),
            const SizedBox(width: 12),
            const Expanded(child: Text('موقعي المباشر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 6),
          if (active) ...[
            JoyCard(
              color: Joy.primarySoft,
              child: Row(children: [
                const Icon(Icons.radio_button_checked_rounded, color: Joy.success),
                const SizedBox(width: 10),
                Expanded(child: Text('تشارك موقعك الآن حتى ${clockOf(_ctl.until)}', key: const Key('live-active-note'), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(key: const Key('live-stop'), onPressed: () async { await _ctl.stop(); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.stop_circle_outlined, color: Joy.danger), label: const Text('إيقاف المشاركة', style: TextStyle(color: Joy.danger)))),
            if (errorLine != null) errorLine,
          ] else ...[
            const Text('يظهر موقعك على خريطة صغيرة داخل المحادثة ويتحدّث كل عشر ثوانٍ ما دام التطبيق مفتوحاً.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final (m, label) in liveShareMinutes)
                ChoiceChip(key: Key('live-min-$m'), label: Text(label), selected: _minutes == m, onSelected: _busy ? null : (_) => setState(() => _minutes = m)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lock_outline_rounded, size: 18, color: Joy.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text('سيرى الطرف الآخر موقعك لمدة ${liveDurationLabel(_minutes)} ثم يتوقف تلقائياً. لا يراه غيره، ويمكنك إيقافه في أي وقت من البطاقة.', key: const Key('live-privacy-note'), style: const TextStyle(fontSize: 12.5, height: 1.5, color: Joy.text))),
              ]),
            ),
            if (errorLine != null) errorLine,
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('live-start'),
                onPressed: _busy ? null : _start,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.my_location_rounded),
                label: Text(_busy ? 'جارٍ تحديد موقعك…' : 'ابدأ المشاركة'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
