import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/media/encode.dart';
import '../../../core/media/permissions.dart';
import '../../../core/media/voice_player.dart';
import '../../../core/media/voice_record.dart';
import '../../../ui/widgets.dart';
import 'composer_draft.dart';

/// الحد الأقصى للطبقة الصوتية على المنشور.
const voiceLayerMax = Duration(seconds: 60);

/// ورقة الطبقة الصوتية: اضغط باستمرار للتسجيل، ثم معاينة بالتشغيل وقصّ البداية والنهاية، ثم «استخدام» أو «إعادة».
/// تعيد [VoiceLayer] أو null عند الإلغاء.
Future<VoiceLayer?> showVoiceLayerSheet(BuildContext context, {VoiceLayer? current}) => showModalBottomSheet<VoiceLayer?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1F24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _VoiceSheet(current: current),
    );

class _VoiceSheet extends StatefulWidget {
  final VoiceLayer? current;
  const _VoiceSheet({this.current});
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  VoiceRecordSession? _rec;
  Timer? _timer;
  bool recording = false, busy = false;
  Duration elapsed = Duration.zero;
  VoiceLayer? take;
  RangeValues? trim;
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  VoiceState _ps = const VoiceState();

  @override
  void initState() {
    super.initState();
    take = widget.current;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec?.dispose();
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (recording) return;
    final rec = _rec ??= VoiceRecordSession();
    try {
      await rec.start();
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return;
      toast(context, 'تعذر بدء التسجيل: ${e.toString().replaceFirst('Bad state: ', '')}', error: true);
      return;
    }
    if (!mounted) return;
    _stopPlayer();
    setState(() { recording = true; elapsed = Duration.zero; take = null; trim = null; });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() => elapsed = rec.elapsed);
      if (elapsed >= voiceLayerMax) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final rec = _rec;
    if (!recording || rec == null) return;
    setState(() => recording = false);
    try {
      final v = await rec.stop();
      if (v == null || v.duration < const Duration(seconds: 1)) {
        if (mounted) toast(context, 'التسجيل قصير جداً؛ اضغط باستمرار أثناء الكلام');
        return;
      }
      if (!mounted) return;
      setState(() {
        take = VoiceLayer(bytes: v.bytes, mime: v.mime, name: v.name, duration: v.duration);
        trim = RangeValues(0, v.duration.inMilliseconds.toDouble());
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر حفظ التسجيل', error: true);
    }
  }

  void _stopPlayer() {
    _sub?.cancel();
    _player?.dispose();
    _player = null;
    _ps = const VoiceState();
  }

  void _togglePlay() {
    final t = take;
    if (t == null) return;
    var p = _player;
    if (p == null) {
      p = VoicePlayer()..setSource(bytes: t.bytes, mime: t.mime);
      _sub = p.changes.listen((s) { if (mounted) setState(() => _ps = s); });
      _player = p;
    }
    if (_ps.playing) {
      p.pause();
    } else {
      final r = trim;
      if (r != null && (_ps.position < Duration(milliseconds: r.start.round()) || _ps.position >= Duration(milliseconds: r.end.round()))) p.seek(Duration(milliseconds: r.start.round()));
      p.play();
    }
  }

  Future<void> _use() async {
    final t = take;
    if (t == null) return;
    final r = trim;
    var out = t;
    // القصّ يعمل على الويب فقط؛ على الجهاز الأصلي لا نزعم قصّاً لم يحدث
    if (audioTrimSupported && r != null && (r.start > 250 || r.end < t.duration.inMilliseconds - 250)) {
      setState(() => busy = true);
      try {
        final cut = await trimAudio(t.bytes, t.mime, start: Duration(milliseconds: r.start.round()), end: Duration(milliseconds: r.end.round()));
        out = VoiceLayer(bytes: cut.bytes, mime: cut.mime, name: cut.name, duration: Duration(milliseconds: (r.end - r.start).round()));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    if (mounted) Navigator.pop(context, out);
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = take;
    final total = t?.duration.inMilliseconds.toDouble() ?? 0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('تعليق صوتي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
            Text(recording ? 'يُسجَّل ${_fmt(elapsed)}' : t != null ? _fmt(t.duration) : 'حتى دقيقة واحدة', style: TextStyle(color: recording ? Joy.sun : Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(t == null ? 'اضغط باستمرار على الميكروفون وتكلّم، وارفع إصبعك للإيقاف.' : audioTrimSupported ? 'اسمعه، وقصّ البداية أو النهاية إن أردت، ثم «استخدام».' : 'اسمعه، ثم «استخدام» أو أعد التسجيل.', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              key: const Key('voice-hold'),
              onLongPressStart: (_) => _start(),
              onLongPressEnd: (_) => _stop(),
              onTap: t == null && !recording ? () => toast(context, 'اضغط باستمرار للتسجيل') : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: recording ? 112 : 96, height: recording ? 112 : 96,
                decoration: BoxDecoration(shape: BoxShape.circle, color: recording ? Joy.danger : Joy.sun, boxShadow: recording ? [BoxShadow(color: Joy.danger.withValues(alpha: .45), blurRadius: 28, spreadRadius: 6)] : null),
                child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, size: 44, color: recording ? Colors.white : Joy.sunText),
              ),
            ),
          ),
          if (t != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              decoration: BoxDecoration(color: const Color(0xFF272B31), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  IconButton(key: const Key('voice-play'), onPressed: _togglePlay, icon: Icon(_ps.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white)),
                  Expanded(child: _Wave(seed: t.duration.inMilliseconds, progress: total == 0 ? 0 : (_ps.position.inMilliseconds / total).clamp(0, 1))),
                  const SizedBox(width: 8),
                  Text(trim == null || !audioTrimSupported ? _fmt(t.duration) : _fmt(Duration(milliseconds: (trim!.end - trim!.start).round())), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
                if (audioTrimSupported && total > 2000)
                  RangeSlider(
                    key: const Key('voice-trim'),
                    values: trim ?? RangeValues(0, total), min: 0, max: total, activeColor: Joy.sun, inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => trim = RangeValues(math.min(v.start, v.end - 1000), math.max(v.end, v.start + 1000))),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(key: const Key('voice-redo'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), onPressed: () => setState(() { _stopPlayer(); take = null; trim = null; }), child: const Text('إعادة التسجيل'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(key: const Key('voice-use'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: busy ? null : _use, child: Text(busy ? 'جارٍ القصّ…' : 'استخدام'))),
            ]),
          ] else if (widget.current != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(key: const Key('voice-remove'), onPressed: () => Navigator.pop(context, null), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger), label: const Text('حذف التسجيل الحالي', style: TextStyle(color: Joy.danger))),
          ],
        ]),
      ),
    );
  }
}

/// موجة ثابتة شبه عشوائية من بذرة (تتطابق بين المحرّر والعارض) مع تقدّم التشغيل.
class _Wave extends StatelessWidget {
  final int seed;
  final double progress;
  const _Wave({required this.seed, required this.progress});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: LayoutBuilder(builder: (context, box) {
          final n = (box.maxWidth / 5).floor().clamp(8, 80);
          final rnd = math.Random(seed);
          return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
            for (var i = 0; i < n; i++)
              Container(width: 3, height: 6 + rnd.nextDouble() * 20, decoration: BoxDecoration(color: i / n <= progress ? Joy.sun : Colors.white30, borderRadius: BorderRadius.circular(2))),
          ]);
        }),
      );
}

/// شريحة الطبقة الصوتية كما تظهر على اللوحة أو الصورة في المحرّر والعارض: زر تشغيل وموجة ومدة.
class VoiceChip extends StatefulWidget {
  final String? url;
  final VoiceLayer? layer;
  final int? seconds;
  final bool light;
  const VoiceChip({super.key, this.url, this.layer, this.seconds, this.light = false});
  @override
  State<VoiceChip> createState() => _VoiceChipState();
}

class _VoiceChipState extends State<VoiceChip> {
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  VoiceState _ps = const VoiceState();

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggle() {
    var p = _player;
    if (p == null) {
      final l = widget.layer;
      if (l == null && (widget.url == null || widget.url!.isEmpty)) return;
      p = VoicePlayer()..setSource(url: widget.url, bytes: l?.bytes, mime: l?.mime);
      _sub = p.changes.listen((s) { if (mounted) setState(() => _ps = s); });
      _player = p;
    }
    _ps.playing ? p.pause() : p.play();
  }

  @override
  Widget build(BuildContext context) {
    final sec = widget.layer?.duration.inSeconds ?? widget.seconds ?? 0;
    final known = _ps.duration?.inMilliseconds ?? 0;
    final total = (known > 0 ? known : sec * 1000).toDouble();
    final fg = widget.light ? Colors.black : Colors.white;
    return Material(
      color: widget.light ? const Color(0xFFF2F2F7) : Colors.black.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const Key('voice-chip'),
        onTap: _toggle,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 34, height: 34, decoration: const BoxDecoration(shape: BoxShape.circle, color: Joy.primary), child: Icon(_ps.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 8),
            SizedBox(width: 110, child: _Wave(seed: sec * 1000 + (widget.url?.hashCode ?? 0) % 997, progress: total == 0 ? 0 : (_ps.position.inMilliseconds / total).clamp(0, 1))),
            const SizedBox(width: 8),
            Text('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
