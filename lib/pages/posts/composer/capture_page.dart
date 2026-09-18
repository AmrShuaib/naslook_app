import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_theme.dart';
import '../../../core/media/camera.dart';
import '../../../core/media/media.dart';
import '../../../core/media/pick_image.dart';
import '../../../ui/widgets.dart';
import 'composer_draft.dart';
import 'text_board.dart';

/// الحد الأقصى للفيديو القصير.
const int kPostVideoMaxBytes = 25 * 1024 * 1024;
const Duration kPostVideoMax = Duration(seconds: 30);
const int kMaxShots = 8;

/// شاشة الالتقاط: الكاميرا الحية أولاً، وشريط أنماط (صورة، فيديو، نص). ضغطة على الزر تلتقط صورة، وضغطة مطوّلة تسجّل فيديو
/// حتى ٣٠ ثانية، و«متعدد» يجمع عدة صور قبل الانتقال. إن لم تتوفر الكاميرا الحية تظهر كاميرا النظام والمعرض بديلاً.
/// تعيد [ComposerDraft] جاهزاً للمراجعة أو null عند الإغلاق.
class CapturePage extends StatefulWidget {
  final ComposerDraft draft;
  const CapturePage({super.key, required this.draft});
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  LiveCamera? _cam;
  bool camReady = false, camFailed = false, starting = false;
  String mode = 'photo';
  bool multi = false, recording = false, busy = false;
  int recSec = 0;
  Timer? _recTimer;
  final shots = <Shot>[];
  String? camError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && recording) _stopVideo();
  }

  Future<void> _startCamera({bool front = false}) async {
    if (!LiveCamera.supported) {
      setState(() { camFailed = true; camReady = false; });
      return;
    }
    setState(() { starting = true; camFailed = false; });
    try {
      final cam = _cam ??= LiveCamera();
      await cam.start(front: front);
      if (!mounted) return;
      setState(() { camReady = true; starting = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { camFailed = true; camReady = false; starting = false; camError = e.toString(); });
    }
  }

  // ---------------------------------------------------------------- الالتقاط
  Future<void> _shutter() async {
    if (busy || recording) return;
    final cam = _cam;
    if (!camReady || cam == null) return _systemCamera();
    setState(() => busy = true);
    try {
      final s = await cam.capturePhoto();
      if (s == null) { if (mounted) toast(context, 'لم تُلتقط الصورة؛ حاول مرة أخرى', error: true); return; }
      _addShot((bytes: s.bytes, mime: s.mime, name: s.name));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _addShot(Shot s) {
    if (!mounted) return;
    if (multi) {
      if (shots.length >= kMaxShots) { toast(context, 'الحد الأقصى $kMaxShots صور'); return; }
      setState(() => shots.add(s));
    } else {
      _finish(kind: 'image', list: [...shots, s]);
    }
  }

  Future<void> _startVideo() async {
    if (busy || recording || mode == 'text') return;
    final cam = _cam;
    if (!camReady || cam == null) return _systemVideo();
    try {
      await cam.startVideo();
    } catch (e) {
      if (mounted) toast(context, 'تعذر بدء التسجيل: $e', error: true);
      return;
    }
    setState(() { recording = true; recSec = 0; mode = 'video'; });
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => recSec++);
      if (recSec >= kPostVideoMax.inSeconds) _stopVideo();
    });
  }

  Future<void> _stopVideo() async {
    _recTimer?.cancel();
    final cam = _cam;
    if (!recording || cam == null) return;
    setState(() { recording = false; busy = true; });
    try {
      final v = await cam.stopVideo();
      if (v == null || (v.durationSec ?? recSec) < 1) { if (mounted) toast(context, 'المقطع قصير جداً؛ اضغط باستمرار أثناء التصوير'); return; }
      if (v.bytes.length > kPostVideoMaxBytes) { if (mounted) toast(context, 'الفيديو أكبر من 25 م.ب؛ صوّر مقطعاً أقصر', error: true); return; }
      _finish(kind: 'video', video: (bytes: v.bytes, mime: v.mime, name: v.name), videoSec: v.durationSec ?? recSec);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------------------------------------------------------------- البدائل: كاميرا النظام والمعرض
  Future<void> _systemCamera() async {
    final img = await pickImage(camera: true);
    if (img == null) return;
    _addShot((bytes: img.bytes, mime: img.mime, name: img.name));
  }

  Future<void> _gallery() async {
    if (mode == 'video') return _systemVideo();
    final img = await pickImage();
    if (img == null) return;
    _addShot((bytes: img.bytes, mime: img.mime, name: img.name));
  }

  Future<void> _systemVideo() async {
    try {
      Shot? v; int? sec;
      if (kIsWeb && WebMedia.available) {
        final m = await WebMedia.pick('video');
        if (m == null) return;
        v = (bytes: m.bytes, mime: m.mime, name: m.name);
      } else {
        final x = await ImagePicker().pickVideo(source: camReady ? ImageSource.gallery : ImageSource.camera, maxDuration: kPostVideoMax);
        if (x == null) return;
        v = (bytes: await x.readAsBytes(), mime: x.mimeType ?? 'video/mp4', name: x.name);
      }
      if (v.bytes.length > kPostVideoMaxBytes) { if (mounted) toast(context, 'الفيديو أكبر من 25 م.ب؛ اختر مقطعاً أقصر (حتى 30 ثانية)', error: true); return; }
      _finish(kind: 'video', video: v, videoSec: sec);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  void _finish({required String kind, List<Shot>? list, Shot? video, int? videoSec}) {
    final d = widget.draft
      ..kind = kind
      ..shots.clear()
      ..cover = 0
      ..video = video
      ..videoSec = videoSec;
    if (list != null) d.shots.addAll(list);
    _cam?.dispose();
    _cam = null;
    Navigator.pop(context, d);
  }

  void _finishText(ComposerDraft d) {
    _cam?.dispose();
    _cam = null;
    Navigator.pop(context, d);
  }

  // ---------------------------------------------------------------- البناء
  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F1114),
          body: mode == 'text'
              ? TextBoardStage(draft: widget.draft, onClose: () => Navigator.pop(context), onNext: _finishText, modeStrip: _modeStrip())
              : _cameraStage(),
        ),
      );

  Widget _cameraStage() => Stack(fit: StackFit.expand, children: [
        // المعاينة الحية أو شاشة البدائل
        if (camReady && _cam != null) _cam!.view() else _fallback(),
        // تدرّج خفيف أعلى وأسفل ليبقى النص مقروءاً
        IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .45), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: .62)], stops: const [0, .22, .6, 1])))),
        SafeArea(
          child: Column(children: [
            // الشريط العلوي
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                _round(Icons.close_rounded, 'إغلاق', () => Navigator.pop(context)),
                const Spacer(),
                if (recording)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Joy.danger.withValues(alpha: .92), borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)), const SizedBox(width: 8),
                    Text('0:${recSec.toString().padLeft(2, '0')} / 0:30', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()])),
                  ]))
                else if (widget.draft.placeName.isNotEmpty)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.place_outlined, size: 16, color: Colors.white), const SizedBox(width: 6), Text(widget.draft.placeName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))])),
                const Spacer(),
                if (camReady) _round(Icons.cameraswitch_rounded, 'تبديل الكاميرا', () => _startCamera(front: !(_cam?.front ?? false)), key: const Key('cam-flip')) else const SizedBox(width: 44),
              ]),
            ),
            if (recording)
              Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: recSec / kPostVideoMax.inSeconds, minHeight: 4, backgroundColor: Colors.white30, color: Joy.danger))),
            const Spacer(),
            // اللقطات المتعددة
            if (multi && shots.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: shots.length, separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(shots[i].bytes, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: Colors.white24))),
                    Positioned(top: 0, left: 0, child: InkWell(key: Key('shot-remove-$i'), onTap: () => setState(() => shots.removeAt(i)), child: Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black87), child: const Icon(Icons.close_rounded, size: 13, color: Colors.white)))),
                  ]),
                ),
              ),
            const SizedBox(height: 10),
            Text(recording ? 'ارفع إصبعك لإيقاف التسجيل' : mode == 'video' ? 'اضغط باستمرار للتسجيل حتى ٣٠ ثانية' : camReady ? 'اضغط لالتقاط صورة · اضغط باستمرار لتصوير فيديو' : '', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (!recording) _modeStrip(),
            const SizedBox(height: 14),
            // صف الزر
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                SizedBox(width: 64, child: recording ? null : Column(mainAxisSize: MainAxisSize.min, children: [
                  _round(Icons.layers_rounded, 'لقطات متعددة', () => setState(() => multi = !multi), key: const Key('cam-multi'), size: 48, on: multi),
                  const SizedBox(height: 4),
                  Text(multi && shots.isNotEmpty ? '${shots.length} لقطة' : 'متعدد', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ])),
                _Shutter(recording: recording, busy: busy, progress: recSec / kPostVideoMax.inSeconds, onTap: mode == 'video' ? _startVideo : _shutter, onHoldStart: _startVideo, onHoldEnd: _stopVideo),
                SizedBox(width: 64, child: recording ? null : Column(mainAxisSize: MainAxisSize.min, children: [
                  if (multi && shots.isNotEmpty)
                    FilledButton(key: const Key('cam-done'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(56, 48), padding: EdgeInsets.zero), onPressed: () => _finish(kind: 'image', list: List.of(shots)), child: const Icon(Icons.arrow_forward_rounded))
                  else
                    InkWell(key: const Key('cam-gallery'), onTap: _gallery, borderRadius: BorderRadius.circular(14), child: Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white, width: 2), color: Colors.white12), child: const Icon(Icons.photo_library_outlined, color: Colors.white))),
                  const SizedBox(height: 4),
                  Text(multi && shots.isNotEmpty ? 'التالي' : 'المعرض', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ])),
              ]),
            ),
          ]),
        ),
      ]);

  /// بلا كاميرا حية: كاميرا النظام والمعرض بديلاً (أو محاولة إعادة طلب الإذن)
  Widget _fallback() => Container(
        color: const Color(0xFF15181D),
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
        child: starting
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.photo_camera_outlined, size: 56, color: Colors.white38),
                const SizedBox(height: 12),
                Text(LiveCamera.supported ? 'لم يُسمح بالكاميرا داخل ناس لايف' : 'الكاميرا الحية غير متاحة على هذا الجهاز', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(LiveCamera.supported ? 'اسمح بالوصول إلى الكاميرا من إعدادات المتصفح، أو استخدم كاميرا الجهاز.' : 'استخدم كاميرا الجهاز أو اختر من المعرض.', style: const TextStyle(color: Colors.white60, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                  FilledButton.icon(key: const Key('cam-system'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: mode == 'video' ? _systemVideo : _systemCamera, icon: const Icon(Icons.photo_camera_rounded), label: Text(mode == 'video' ? 'صوّر فيديو بكاميرا الجهاز' : 'كاميرا الجهاز')),
                  OutlinedButton.icon(key: const Key('cam-pick'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), onPressed: _gallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('من المعرض')),
                  if (LiveCamera.supported) TextButton(key: const Key('cam-retry'), onPressed: () => _startCamera(), child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white70))),
                ]),
              ]),
      );

  Widget _modeStrip() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final (k, l) in const [('photo', 'صورة'), ('video', 'فيديو'), ('text', 'نص')])
          InkWell(
            key: Key('mode-$k'),
            onTap: recording ? null : () => setState(() => mode = k),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(l, style: TextStyle(color: mode == k ? Colors.white : Colors.white70, fontWeight: mode == k ? FontWeight.w800 : FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 5),
                Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: mode == k ? Joy.sun : Colors.transparent)),
              ]),
            ),
          ),
      ]);

  Widget _round(IconData icon, String tip, VoidCallback onTap, {Key? key, double size = 44, bool on = false}) => Material(
        key: key,
        color: on ? Joy.sun : Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Tooltip(message: tip, child: SizedBox(width: size, height: size, child: Icon(icon, color: on ? Joy.sunText : Colors.white, size: 22)))),
      );
}

/// زر الالتقاط: حلقة بيضاء، تتحول أثناء التسجيل إلى مربع أحمر بحلقة تقدّم.
class _Shutter extends StatelessWidget {
  final bool recording, busy;
  final double progress;
  final VoidCallback onTap, onHoldStart, onHoldEnd;
  const _Shutter({required this.recording, required this.busy, required this.progress, required this.onTap, required this.onHoldStart, required this.onHoldEnd});
  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const Key('shutter'),
        onTap: busy ? null : (recording ? onHoldEnd : onTap),
        onLongPressStart: busy || recording ? null : (_) => onHoldStart(),
        onLongPressEnd: (_) { if (recording) onHoldEnd(); },
        child: SizedBox(
          width: 84, height: 84,
          child: Stack(alignment: Alignment.center, children: [
            if (recording) SizedBox(width: 84, height: 84, child: CircularProgressIndicator(value: progress, strokeWidth: 5, color: Joy.danger, backgroundColor: Colors.white30))
            else Container(width: 84, height: 84, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: recording ? 34 : 62, height: recording ? 34 : 62,
              decoration: BoxDecoration(color: recording ? Joy.danger : Colors.white, borderRadius: BorderRadius.circular(recording ? 8 : 31)),
              child: busy ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : null,
            ),
          ]),
        ),
      );
}
