// ماسح رموز QR (نوفمبر 2026): العميل يُظهر رمز طلبه أو تذكرته، وطاقم الدائرة ومضيف الفعالية وبائع السوق يمسحونه بالكاميرا
// بدل كتابته. الويب: معاينة حية عبر getUserMedia وفكّ الإطار بـ BarcodeDetector إن وفّره المتصفح وإلا بـ zxing2 (Dart خالص).
// iOS الأصلي: لا كاميرا حية في التطبيق (LiveCamera للويب فقط)، فتُلتقط صورة بكاميرا النظام (image_picker الموجود) وتُفكّ بـ zxing2
// نفسه، فلا إضافة أصلية جديدة ولا تغيير في توقيع Codemagic. الإدخال اليدوي يبقى في الورقة نفسها دائماً.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../core/app_theme.dart';
import '../core/media/native_io.dart' show isNativeMobile;
import '../core/media/pick_image.dart';
import 'qr_scanner_stub.dart' if (dart.library.js_interop) 'qr_scanner_web.dart' as impl;

/// لا كاميرا تعمل (غير موجودة أو مشغولة بتطبيق آخر أو صفحة غير آمنة): يُعرض الإدخال اليدوي والتقاط صورة.
class QrCameraUnavailable implements Exception {
  final String reason;
  const QrCameraUnavailable([this.reason = '']);
  @override
  String toString() => 'لا كاميرا متاحة${reason.isEmpty ? '' : ' ($reason)'}';
}

/// كاميرا المسح الحية: معاينة، ومحاولة فكّ للإطار الحالي، وكشّاف إن توفر.
/// [factoryOverride] يبدّلها في الاختبارات (`flutter test` لا كاميرا فيه فيعمل بوضع الصورة الثابتة).
abstract class QrCamera {
  static QrCamera Function()? factoryOverride;
  static bool get liveSupported => factoryOverride != null || impl.liveSupported;
  factory QrCamera() => factoryOverride?.call() ?? impl.createQrCamera();

  /// يطلب الإذن ويبدأ البث بالكاميرا الخلفية. يرمي [MediaPermissionDenied] عند الرفض و[QrCameraUnavailable] إن لم تعمل.
  Future<void> start();

  /// المعاينة الحية (تملأ المساحة المتاحة).
  Widget view();

  /// يحاول فكّ رمز من الإطار الحالي؛ null إن لم يُعثر على رمز بعد.
  Future<String?> scan();

  bool get torchAvailable;
  bool get torchOn;
  Future<void> setTorch(bool on);

  void dispose();
}

/// بديل للاختبارات: فكّ صورة ملتقطة (وضع الصورة الثابتة) بدل zxing2.
Future<String?> Function(Uint8List bytes)? decodeQrImageOverride;

/// يفكّ رمز QR من صورة مرمّزة (JPEG/PNG…): على الويب برسمها في canvas، وعلى الجهاز بحزمة image في عزلة منفصلة.
Future<String?> decodeQrImage(Uint8List bytes) {
  final o = decodeQrImageOverride;
  if (o != null) return o(bytes);
  return impl.decodeImageBytes(bytes);
}

// ---------------------------------------------------------------- الفكّ بـ zxing2 (مشترك بين الويب والجهاز)

final _hints = DecodeHints()
  ..put(DecodeHintType.tryHarder)
  ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode]);

/// يفكّ رمزاً من مصفوفة إضاءة (بايت لكل بكسل). [thorough] يجرّب مُثنّياً ثانياً والرمز المعكوس (فاتح على داكن) للصور الثابتة؛
/// إطارات الكاميرا تكتفي بالأسرع لأن الإطار التالي يأتي بعد ثلث ثانية.
String? decodeQrLuminance(Uint8List gray, int width, int height, {bool thorough = false}) {
  if (width < 21 || height < 21 || gray.length < width * height) return null;
  final src = _Gray(Int8List.view(gray.buffer, gray.offsetInBytes, width * height), width, height);
  final tries = <Binarizer>[HybridBinarizer(src), if (thorough) GlobalHistogramBinarizer(src), if (thorough) HybridBinarizer(InvertedLuminanceSource(src))];
  for (final b in tries) {
    try {
      final t = QRCodeReader().decode(BinaryBitmap(b), hints: _hints).text;
      if (t.isNotEmpty) return t;
    } on ReaderException {
      // لا رمز في هذه المحاولة
    } catch (_) {
      // إطار تالف أو حالة حدّية في المكتبة: لا يُسقط المسح
    }
  }
  return null;
}

/// مصدر إضاءة من مصفوفة بايت جاهزة (zxing2 لا يصدّر PlanarYUVLuminanceSource).
class _Gray extends LuminanceSource {
  final Int8List _px;
  _Gray(this._px, int width, int height) : super(width, height);

  @override
  Int8List getRow(int y, Int8List? row) {
    final r = row == null || row.length < width ? Int8List(width) : row;
    r.setRange(0, width, _px, y * width);
    return r;
  }

  @override
  Int8List getMatrix() => _px;
}

/// يحوّل بكسلات RGBA (من canvas) إلى إضاءة ثم يفكّ.
String? decodeQrRgba(List<int> rgba, int width, int height, {bool thorough = false}) {
  final n = width * height;
  if (rgba.length < n * 4) return null;
  final gray = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    // متوسط يميل للأخضر كما في zxing
    gray[i] = (rgba[j] + 2 * rgba[j + 1] + rgba[j + 2]) >> 2;
  }
  return decodeQrLuminance(gray, width, height, thorough: thorough);
}

/// فكّ صورة مرمّزة بحزمة image (iOS الأصلي والاختبارات): تُصغَّر إلى 1200 بكسل للضلع لأن صورة الكاميرا الكاملة بطيئة ولا تزيد الدقة.
String? decodeQrEncodedSync(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    // بايتات تالفة أو صيغة غير مدعومة: بعض مفكّكات الحزمة ترمي بدل إعادة null
    return null;
  }
  if (im == null) return null;
  const maxSide = 1200;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
  }
  final w = im.width, h = im.height;
  final gray = Uint8List(w * h);
  var i = 0;
  for (final p in im) {
    gray[i++] = ((p.r.toInt() + 2 * p.g.toInt() + p.b.toInt()) >> 2).clamp(0, 255);
  }
  return decodeQrLuminance(gray, w, h, thorough: true);
}

/// على الجهاز الأصلي يُفكّ في عزلة حتى لا تتجمد الواجهة؛ غيره (سطح المكتب والاختبارات) مباشرة.
Future<String?> decodeQrEncoded(Uint8List bytes) async => isNativeMobile ? compute(decodeQrEncodedSync, bytes) : decodeQrEncodedSync(bytes);

// ---------------------------------------------------------------- قراءة الرموز

/// نتيجة فحص النص المقروء: الرمز المعتمد للخادم، أو رسالة رفض تظهر في الورقة نفسها بلا طلب.
typedef QrCheck = ({String? code, String? error});

const _arDigits = '٠١٢٣٤٥٦٧٨٩', _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// يحوّل الأرقام العربية والفارسية إلى لاتينية (لوحة المفاتيح العربية تكتب ٤٣٢١).
String latinDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = _arDigits.indexOf(ch), j = _faDigits.indexOf(ch);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch);
  }
  return b.toString();
}

final _venueRe = RegExp(r'NAS-[A-Z0-9]{2,16}');

/// رمز حجز الدائرة أو تذكرة الفعالية (الخادم يولّده NAS- ثم ثماني خانات). الممسوح يجب أن يحوي النمط (قد يأتي داخل رابط)،
/// والمكتوب يُقبل كما هو بأحرف كبيرة لأن الخادم هو الحكم.
QrCheck checkVenueCode(String raw, {required bool scanned}) {
  final s = latinDigits(raw).trim().toUpperCase();
  if (s.isEmpty) return (code: null, error: 'اكتب الرمز');
  final m = _venueRe.firstMatch(s);
  if (m != null) return (code: m.group(0), error: null);
  if (scanned) return (code: null, error: 'هذا ليس رمز حجز أو تذكرة من ناس لايف');
  // من يكتب الخانات الثماني وحدها (بلا NAS-) يقصد الرمز نفسه
  if (RegExp(r'^[0-9A-F]{8}$').hasMatch(s)) return (code: 'NAS-$s', error: null);
  return (code: s.length > 40 ? s.substring(0, 40) : s, error: null);
}

/// بيانات QR لطلب السوق: معرّف الطلب مع رمزه حتى يعرف البائع أن الرمز لهذا الطلب قبل أي محاولة
/// (المحاولات الخاطئة تُقفل الرمز بعد خمس).
String marketQrData(String orderId, String code) => 'naslife:market:$orderId:$code';

final _marketRe = RegExp(r'^naslife:market:([0-9a-fA-F-]{36}):(\d{4,8})$');

/// رمز تسليم السوق: أربعة أرقام مكتوبة، أو QR المشتري لهذا الطلب [orderId].
QrCheck checkMarketCode(String raw, {required String orderId, required bool scanned}) {
  final s = latinDigits(raw).trim();
  if (s.isEmpty) return (code: null, error: 'اكتب الرمز');
  final m = _marketRe.firstMatch(s);
  if (m != null) {
    if (m.group(1)!.toLowerCase() != orderId.toLowerCase()) return (code: null, error: 'هذا رمز طلب آخر، لا هذا الطلب');
    return (code: m.group(2), error: null);
  }
  if (RegExp(r'^\d{4,8}$').hasMatch(s)) return (code: s, error: null);
  return (code: null, error: scanned ? 'هذا ليس رمز استلام من ناس لايف' : 'الرمز أرقام فقط');
}

// ---------------------------------------------------------------- ورقة المسح

/// طريق السماح بالكاميرا بعد رفضها بحسب مكان التشغيل. سفاري iOS لا رمز قفل بجانب عنوانه (الإذن من زر قائمة الصفحة aA)،
/// والتطبيق المثبّت على الشاشة الرئيسية بلا شريط عنوان أصلاً، فإرشاد كروم لا ينفع أكثر جمهور الماسح على الويب.
/// على الويب الصورة بديل دائم: `<input capture>` يفتح كاميرا الجهاز بلا إذن الموقع.
String qrDeniedHelp({required bool web, required bool ios, required bool standalone}) {
  if (!web) return 'افتح الإعدادات ثم ناس لايف ثم الكاميرا وفعّلها، ثم عد وأعد المحاولة. أو اكتب الرمز أدناه.';
  const tail = 'أو التقط صورة للرمز، أو اكتبه أدناه.';
  if (ios && standalone) return 'افتح إعدادات الجوال ← التطبيقات ← Safari ← الكاميرا واختر «سماح» (في iOS الأقدم: الإعدادات ← Safari ← الكاميرا)، ثم أغلق ناس لايف وافتحه من جديد. $tail';
  if (ios) return 'اضغط زر قائمة الصفحة (aA) في شريط العنوان ← إعدادات موقع الويب ← الكاميرا ← سماح، ثم أعد المحاولة. $tail';
  if (standalone) return 'افتح naslife.app في المتصفح، واضغط الرمز بجانب العنوان ← الأذونات ← الكاميرا ← سماح، ثم عد إلى التطبيق وأعد المحاولة. $tail';
  return 'اضغط الرمز بجانب العنوان (القفل أو رمز الإعدادات) ← الكاميرا ← سماح، ثم أعد المحاولة. $tail';
}

/// يفتح ورقة المسح: كاميرا (أو التقاط صورة حيث لا كاميرا حية) وتحتها الإدخال اليدوي. يعيد الرمز المعتمد بعد [check]، أو null عند الإغلاق.
Future<String?> showQrScanSheet(
  BuildContext context, {
  required String title,
  required String manualHint,
  required QrCheck Function(String raw, {required bool scanned}) check,
  String help = 'وجّه الكاميرا إلى رمز QR على جوال العميل',
  TextInputType keyboardType = TextInputType.text,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .94),
      builder: (_) => QrScanSheet(title: title, manualHint: manualHint, check: check, help: help, keyboardType: keyboardType),
    );

class QrScanSheet extends StatefulWidget {
  final String title, manualHint, help;
  final QrCheck Function(String raw, {required bool scanned}) check;
  final TextInputType keyboardType;
  const QrScanSheet({super.key, required this.title, required this.manualHint, required this.check, this.help = '', this.keyboardType = TextInputType.text});
  @override
  State<QrScanSheet> createState() => _QrScanSheetState();
}

enum _Cam { starting, live, denied, unavailable, still }

class _QrScanSheetState extends State<QrScanSheet> with WidgetsBindingObserver {
  QrCamera? _cam;
  _Cam _state = QrCamera.liveSupported ? _Cam.starting : _Cam.still;
  Timer? _loop;
  bool _busy = false, _done = false, _torch = false, _photoBusy = false;
  String? _error;
  String _lastRejected = '';
  final _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_state == _Cam.starting) _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _manual.dispose();
    super.dispose();
  }

  // التطبيق في الخلفية: نحرر الكاميرا (مؤشرها يبقى مضاءً وإلا)، ونعيدها عند العودة.
  // الويب (حيث الكاميرا الحية وحدها) لا يُبلغ paused أبداً: التبويب المخفي يصل hidden، فنوقف عندها أيضاً
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if ((s == AppLifecycleState.hidden || s == AppLifecycleState.paused) && _cam != null) {
      _stop();
      if (mounted) setState(() => _state = _Cam.starting);
    } else if (s == AppLifecycleState.resumed && _state == _Cam.starting && _cam == null && !_done) {
      _start();
    }
  }

  void _stop() {
    _loop?.cancel();
    _loop = null;
    _cam?.dispose();
    _cam = null;
  }

  Future<void> _start() async {
    _stop();
    setState(() { _state = _Cam.starting; _torch = false; });
    final cam = QrCamera();
    _cam = cam;
    try {
      await cam.start();
      if (!mounted || _cam != cam) return cam.dispose();
      setState(() => _state = _Cam.live);
      _loop = Timer.periodic(const Duration(milliseconds: 320), (_) => _tick());
    } on MediaPermissionDenied {
      if (_cam == cam) _cam = null;
      cam.dispose();
      if (mounted) setState(() => _state = _Cam.denied);
    } catch (_) {
      if (_cam == cam) _cam = null;
      cam.dispose();
      if (mounted) setState(() => _state = _Cam.unavailable);
    }
  }

  Future<void> _tick() async {
    final cam = _cam;
    if (_busy || _done || cam == null || _state != _Cam.live) return;
    _busy = true;
    try {
      final raw = await cam.scan();
      if (raw != null && mounted && !_done) _accept(raw, scanned: true);
    } catch (_) {
      // إطار لم يجهز بعد: المحاولة التالية بعد لحظة
    } finally {
      _busy = false;
    }
  }

  void _accept(String raw, {required bool scanned}) {
    final r = widget.check(raw, scanned: scanned);
    if (r.code == null) {
      // الرمز الخاطئ نفسه يبقى أمام الكاميرا: نكتب الرسالة مرة واحدة ولا نهتز في كل إطار
      if (scanned && raw == _lastRejected) return;
      _lastRejected = scanned ? raw : '';
      if (scanned) HapticFeedback.heavyImpact().ignore();
      setState(() => _error = r.error);
      return;
    }
    _done = true;
    if (scanned) HapticFeedback.mediumImpact().ignore();
    _stop();
    Navigator.of(context).pop(r.code);
  }

  Future<void> _photo() async {
    if (_photoBusy) return;
    setState(() { _photoBusy = true; _error = null; });
    try {
      final p = await pickImage(camera: true);
      if (p == null || !mounted) return;
      final raw = await decodeQrImage(p.bytes);
      if (!mounted) return;
      if (raw == null) {
        setState(() => _error = 'لم نجد رمزاً واضحاً في الصورة. قرّب الجوال من الرمز وأعد المحاولة، أو اكتبه أدناه');
      } else {
        _lastRejected = '';
        _accept(raw, scanned: true);
      }
    } on MediaPermissionDenied {
      if (mounted) setState(() => _state = _Cam.denied);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر فتح الكاميرا. اكتب الرمز أدناه');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    try {
      await cam.setTorch(!_torch);
      if (mounted) setState(() => _torch = cam.torchOn);
    } catch (_) {
      if (mounted) setState(() => _torch = false);
    }
  }

  void _submitManual() {
    final t = _manual.text;
    if (t.trim().isEmpty) return setState(() => _error = 'اكتب الرمز');
    _accept(t, scanned: false);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.title, key: const Key('qr-title'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (widget.help.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.help, textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(aspectRatio: 1, child: ColoredBox(color: Colors.black, child: _camArea())),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, key: const Key('qr-error'), textAlign: TextAlign.center, style: const TextStyle(color: Joy.danger, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          const Text('أو اكتب الرمز', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('qr-manual'),
                controller: _manual,
                keyboardType: widget.keyboardType,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitManual(),
                onChanged: (_) { if (_error != null) setState(() => _error = null); },
                decoration: InputDecoration(hintText: widget.manualHint, isDense: true, prefixIcon: const Icon(Icons.keyboard_alt_outlined, color: Joy.textMuted)),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(key: const Key('qr-manual-go'), onPressed: _submitManual, child: const Text('متابعة')),
          ]),
        ]),
      ),
    );
  }

  Widget _camArea() {
    switch (_state) {
      case _Cam.starting:
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      case _Cam.live:
        return Stack(fit: StackFit.expand, children: [
          _cam!.view(),
          // إطار التوجيه في المنتصف فقط للعين؛ الفكّ يقرأ الإطار كله
          IgnorePointer(child: CustomPaint(painter: _FramePainter())),
          if (_cam!.torchAvailable)
            PositionedDirectional(
              top: 10, end: 10,
              child: IconButton.filledTonal(
                key: const Key('qr-torch'),
                tooltip: _torch ? 'إطفاء الكشاف' : 'تشغيل الكشاف',
                onPressed: _toggleTorch,
                icon: Icon(_torch ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded),
              ),
            ),
          const PositionedDirectional(
            bottom: 12, start: 0, end: 0,
            child: Text('يُقرأ الرمز تلقائياً', key: Key('qr-live'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12.5, shadows: [Shadow(blurRadius: 4)])),
          ),
        ]);
      case _Cam.denied:
        return _note(
          key: const Key('qr-denied'),
          icon: Icons.no_photography_outlined,
          title: 'لا إذن للكاميرا',
          body: qrDeniedHelp(web: kIsWeb, ios: defaultTargetPlatform == TargetPlatform.iOS, standalone: kIsWeb && impl.standaloneDisplay),
          actions: [
            if (!kIsWeb) FilledButton.tonal(key: const Key('qr-open-settings'), onPressed: openAppSettings, child: const Text('فتح الإعدادات')),
            // رُفضت الكاميرا الحية: صورة بكاميرا الجهاز (<input capture> على الويب) لا تحتاج إذن الموقع، والمتصفح يرفض إعادة المحاولة فوراً
            // ما دام يتذكر الرفض. حيث لا كاميرا حية جاء الرفض من التقاط الصورة نفسه، فـ«أعد المحاولة» هي الصورة
            if (QrCamera.liveSupported) FilledButton.tonal(key: const Key('qr-photo'), onPressed: _photoBusy ? null : _photo, child: const Text('التقط صورة للرمز')),
            OutlinedButton(key: const Key('qr-retry'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), onPressed: QrCamera.liveSupported ? _start : _photo, child: const Text('أعد المحاولة')),
          ],
        );
      case _Cam.unavailable:
        return _note(
          key: const Key('qr-unavailable'),
          icon: Icons.videocam_off_outlined,
          title: 'الكاميرا غير متاحة',
          body: 'قد تكون مستخدمة في تطبيق آخر أو غير موجودة. التقط صورة للرمز أو اكتبه أدناه.',
          actions: [
            FilledButton.tonal(key: const Key('qr-photo'), onPressed: _photoBusy ? null : _photo, child: const Text('التقط صورة للرمز')),
            OutlinedButton(key: const Key('qr-retry'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), onPressed: _start, child: const Text('أعد المحاولة')),
          ],
        );
      case _Cam.still:
        return _note(
          key: const Key('qr-still'),
          icon: Icons.qr_code_scanner_rounded,
          title: 'صوّر رمز العميل',
          body: 'التقط صورة قريبة وواضحة لرمز QR على جوال العميل، ونقرؤه منها.',
          actions: [
            FilledButton.icon(
              key: const Key('qr-photo'),
              onPressed: _photoBusy ? null : _photo,
              icon: _photoBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined),
              label: const Text('التقط صورة للرمز'),
            ),
          ],
        );
    }
  }

  // المربع على جوال صغير أقصر من نص الإرشاد مع زرّين: يُمرَّر داخله بدل أن يفيض
  Widget _note({required Key key, required IconData icon, required String title, required String body, required List<Widget> actions}) => Center(
        key: key,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 44),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.6)),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: actions),
          ]),
        ),
      );
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * .62;
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const k = 26.0;
    for (final (c, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomLeft, 1.0, -1.0), (r.bottomRight, -1.0, -1.0)]) {
      canvas.drawLine(c, c + Offset(k * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, k * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------- ملخص ما بعد المسح

/// ما يريده المستخدم بعد ورقة الملخص: انتهى، أو تأكيد ثم مسح التالي (بوابة الفعالية)، أو مسح رمز آخر بعد رمز مرفوض.
enum ScanStep { done, next, rescan }

/// ورقة الملخص بعد قراءة الرمز: لمن هو وماذا يخص، ثم «تأكيد» يستدعي [onConfirm] (طلب الخادم نفسه كما في الإدخال اليدوي)
/// ويعيد رسالة النجاح. [blocked] مع [warning] يخفي التأكيد (تذكرة مستخدمة، رمز لدائرة أخرى…).
/// [errFinal]: خطأ لا يتغير بإعادة الرمز نفسه (رمز تسليم خاطئ يُحسب من محاولات القفل) يخفي التأكيد بعده، فلا يبقى إلا
/// «امسح رمزاً آخر» و«إغلاق»؛ بدونه يبقى الزر لإعادة المحاولة (خطأ شبكة مثلاً).
Future<ScanStep> showScanSummary(
  BuildContext context, {
  required String code,
  required Widget header,
  List<(String, String)> rows = const [],
  String? warning,
  bool blocked = false,
  required String confirmLabel,
  required Future<String> Function(BuildContext sheetContext) onConfirm,
  required String Function(Object e) errText,
  bool Function(Object e)? errFinal,
  bool offerNext = true,
}) async {
  final r = await showModalBottomSheet<ScanStep>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
    builder: (_) => _ScanSummary(code: code, header: header, rows: rows, warning: warning, blocked: blocked, confirmLabel: confirmLabel, onConfirm: onConfirm, errText: errText, errFinal: errFinal, offerNext: offerNext),
  );
  return r ?? ScanStep.done;
}

class _ScanSummary extends StatefulWidget {
  final String code, confirmLabel;
  final Widget header;
  final List<(String, String)> rows;
  final String? warning;
  final bool blocked, offerNext;
  final Future<String> Function(BuildContext) onConfirm;
  final String Function(Object) errText;
  final bool Function(Object)? errFinal;
  const _ScanSummary({required this.code, required this.header, required this.rows, required this.warning, required this.blocked, required this.confirmLabel, required this.onConfirm, required this.errText, this.errFinal, required this.offerNext});
  @override
  State<_ScanSummary> createState() => _ScanSummaryState();
}

class _ScanSummaryState extends State<_ScanSummary> {
  bool _busy = false, _final = false;
  String? _ok, _err;

  Future<void> _confirm() async {
    if (_busy || _final) return;
    setState(() { _busy = true; _err = null; });
    try {
      final msg = await widget.onConfirm(context);
      if (mounted) setState(() => _ok = msg);
    } catch (e) {
      if (mounted) setState(() { _err = widget.errText(e); _final = widget.errFinal?.call(e) ?? false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(color: Joy.textMuted)),
            const SizedBox(width: 12),
            Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    final pop = Navigator.of(context).pop;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('scan-summary'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          widget.header,
          const SizedBox(height: 10),
          Text(widget.code, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 16, color: Joy.primary)),
          const SizedBox(height: 6),
          for (final (k, v) in widget.rows) kv(k, v),
          if (widget.warning != null)
            Container(
              key: const Key('scan-warning'),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: (widget.blocked ? Joy.danger : Joy.warning).withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
              child: Text(widget.warning!, style: TextStyle(color: widget.blocked ? Joy.danger : Joy.warning, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, key: const Key('scan-error'), textAlign: TextAlign.center, style: const TextStyle(color: Joy.danger, fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          if (_ok != null) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded, color: Joy.success),
              const SizedBox(width: 6),
              Flexible(child: Text(_ok!, key: const Key('scan-ok'), style: const TextStyle(color: Joy.success, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            if (widget.offerNext) FilledButton.icon(key: const Key('scan-next'), onPressed: () => pop(ScanStep.next), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('امسح التالي')),
            TextButton(key: const Key('scan-done'), onPressed: () => pop(ScanStep.done), child: const Text('تم')),
          ] else if (widget.blocked || _final) ...[
            FilledButton.tonalIcon(key: const Key('scan-rescan'), onPressed: () => pop(ScanStep.rescan), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('امسح رمزاً آخر')),
            TextButton(key: const Key('scan-done'), onPressed: () => pop(ScanStep.done), child: const Text('إغلاق')),
          ] else ...[
            FilledButton.icon(
              key: const Key('scan-confirm'),
              onPressed: _busy ? null : _confirm,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.task_alt_rounded),
              label: Text(widget.confirmLabel),
            ),
            TextButton(key: const Key('scan-rescan'), onPressed: _busy ? null : () => pop(ScanStep.rescan), child: const Text('ليس هذا، امسح غيره')),
          ],
        ]),
      ),
    );
  }
}
