import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/profile_v2_models.dart' show clockText;
import '../../api/profile_voice_api.dart';
import '../../core/app_theme.dart';
import '../../core/platform.dart';
import '../../core/speech/dictation.dart';

/// «عرّف بنفسك بالصوت» (docs/profile-voice.md): زر أعلى حقول تعديل الملف، ورقة موافقة لأول مرة، ثم ورقة «تكلّم الآن»
/// بصندوق نص يُملى فيه أو يُكتب، ثم يعود ما وزّعه الخادم على الحقول إلى الشاشة لتُراجَع. لا شيء يُحفظ هنا.

/// ما تعيده ورقة الكلام إلى شاشة التعديل.
class VoiceFillOutcome {
  /// الحقول المستخرجة، أو null إن أُغلقت الورقة بلا نتيجة.
  final VoiceFillResult? result;

  /// المستخدم سحب موافقته من الورقة: الشاشة تعيد عرض ورقة الموافقة في المرة القادمة.
  final bool withdrew;
  const VoiceFillOutcome({this.result, this.withdrew = false});
}

/// مصدر الموافقة كما يحفظه الخادم.
String get _source => isIosNative ? 'ios' : isAndroidNative ? 'android' : kIsWeb ? 'web' : 'app';

/// الزر البارز أعلى الحقول.
class VoiceFillButton extends StatelessWidget {
  final VoidCallback? onTap;
  const VoiceFillButton({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Joy.primary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('voice-fill'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
                child: const Icon(Icons.mic_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('عرّف بنفسك بالصوت', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  SizedBox(height: 2),
                  Text('تكلّم 30 ثانية ونعبّئ الحقول عنك', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.white),
            ]),
          ),
        ),
      );
}

/// شارة صغيرة فوق الحقل الذي عُبّئ من الكلام: زرقاء «من كلامك»، أو صفراء «تأكّد من الكتابة» لما لم يتأكد منه الخادم.
class VoiceTag extends StatelessWidget {
  final String field;
  final bool unsure;
  const VoiceTag(this.field, {super.key, this.unsure = false});

  static Color fill(bool unsure) => unsure ? Joy.sunSoft : Joy.primarySoft;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('voice-tag-$field'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fill(unsure), borderRadius: BorderRadius.circular(999), border: Border.all(color: unsure ? Joy.sun : Joy.primary)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(unsure ? Icons.error_outline_rounded : Icons.mic_none_rounded, size: 13, color: unsure ? Joy.sunText : Joy.primary),
          const SizedBox(width: 4),
          Flexible(child: Text(unsure ? 'تأكّد من الكتابة' : 'من كلامك', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: unsure ? Joy.sunText : Joy.primary))),
        ]),
      );
}

/// ورقة الموافقة «قبل أن تبدأ»: تظهر مرة واحدة قبل أول استخدام. تعيد true عند الموافقة.
class VoiceConsentSheet extends StatelessWidget {
  const VoiceConsentSheet({super.key});

  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const VoiceConsentSheet());

  Widget _bullet(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_circle_rounded, size: 18, color: Joy.success)),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(height: 1.5))),
        ]),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        key: const Key('voice-consent'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('قبل أن تبدأ', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('سنحوّل كلامك إلى نص، ثم يقرؤه مساعد ذكي (Claude من Anthropic) ليوزعه على حقول ملفك.', style: TextStyle(height: 1.6)),
            const SizedBox(height: 12),
            _bullet('لا يُحفظ شيء قبل أن تراجعه وتضغط «حفظ».'),
            _bullet('النص يُستخدم لتعبئة ملفك فقط.'),
            _bullet('التسجيل نفسه لا يُحتفظ به.'),
            // تحويل الصوت إلى نص ليس عندنا: إفصاح قصير عمّن يقوم به
            const Text('تحويل الصوت إلى نص تقوم به خدمة الإملاء في متصفحك أو لوحة مفاتيحك. وتستطيع سحب موافقتك متى شئت من ورقة الكلام.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 14),
            FilledButton(key: const Key('voice-consent-ok'), onPressed: () => Navigator.of(context).pop(true), child: const Text('موافق، ابدأ')),
            const SizedBox(height: 6),
            TextButton(key: const Key('voice-consent-no'), onPressed: () => Navigator.of(context).pop(false), child: const Text('لا، سأكتب بنفسي')),
          ]),
        ),
      );
}

/// يدير الرحلة كلها من زر الشاشة: الموافقة إن لزمت (وتسجيلها في الخادم) ثم ورقة الكلام.
/// [onConsented] يُستدعى حين تُسجَّل الموافقة حتى لا تُعرض ورقتها ثانية ولو أُغلقت ورقة الكلام بلا نتيجة.
Future<VoiceFillOutcome> runVoiceFill(BuildContext context, ApiClient api, VoiceFillStatus status, {void Function()? onConsented}) async {
  if (!status.consented) {
    final ok = await VoiceConsentSheet.show(context);
    if (ok != true) return const VoiceFillOutcome();
    try {
      await api.giveAiConsent(profileVoiceFeature, source: _source);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('تعذّر حفظ موافقتك. أعد المحاولة.'), backgroundColor: Joy.danger));
      return const VoiceFillOutcome();
    }
    onConsented?.call();
    if (!context.mounted) return const VoiceFillOutcome();
  }
  final out = await showModalBottomSheet<VoiceFillOutcome>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => VoiceTalkSheet(api: api, status: status));
  return out ?? const VoiceFillOutcome();
}

/// ورقة «تكلّم الآن»: صندوق نص يُعدَّل دائماً (كتابة أو لصق أو إملاء لوحة المفاتيح)، وزر ميكروفون حين يدعم المتصفح الإملاء،
/// ومؤقّت حتى الدقيقة، ثم «رتّب في الحقول» يرسل النص ويعيد الحقول إلى الشاشة.
class VoiceTalkSheet extends StatefulWidget {
  final ApiClient api;
  final VoiceFillStatus status;
  const VoiceTalkSheet({super.key, required this.api, required this.status});
  @override
  State<VoiceTalkSheet> createState() => _VoiceTalkSheetState();
}

class _VoiceTalkSheetState extends State<VoiceTalkSheet> with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final AnimationController _bars = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final bool _canDictate = Dictation.supported;
  Dictation? _dict;
  String _base = '';
  // _closed: الورقة تُغلق؛ إيقاف الإملاء عند الإغلاق يستدعي onEnd والحالة لم تعد تُحدَّث
  bool _listening = false, _busy = false, _withdrawing = false, _closed = false;
  Timer? _tick;
  // زمن الاستماع المتراكم بعدّ نبضات المؤقّت (ربع ثانية): يتوقف الميكروفون عند الحد، والكتابة تبقى متاحة
  static const _beat = Duration(milliseconds: 250);
  Duration _elapsed = Duration.zero;
  String? _error;

  Duration get _max => Duration(seconds: widget.status.maxSec);

  @override
  void initState() {
    super.initState();
    // الضغط على الزر هو طلب الكلام: يبدأ الاستماع فور فتح الورقة حيث يُدعم
    if (_canDictate) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _closed = true;
    _tick?.cancel();
    if (_listening) _dict?.stop();
    _dict?.dispose();
    _bars.dispose();
    _text.dispose();
    super.dispose();
  }

  void _setText(String s) => _text.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));

  void _halt() {
    _tick?.cancel();
    _bars.stop();
    _listening = false;
  }

  Future<void> _start() async {
    if (!mounted || _listening || _busy || _elapsed >= _max) return;
    final d = _dict ??= Dictation();
    // الجزئي يُلحق بالموجود (ما كتبه المستخدم يبقى)، والنهائي يحل محل الجزئي
    var base = _text.text;
    if (base.isNotEmpty && !base.endsWith(' ') && !base.endsWith('\n')) base += ' ';
    _base = base;
    setState(() {
      _listening = true;
      _error = null;
    });
    _bars.repeat();
    _tick?.cancel();
    _tick = Timer.periodic(_beat, (_) {
      if (!mounted || _closed) return;
      setState(() => _elapsed += _beat);
      if (_elapsed >= _max) _stop();
    });
    try {
      await d.start(
        onText: (t, isFinal) {
          if (!mounted || _closed) return;
          final next = '$_base$t${isFinal ? ' ' : ''}';
          // النص لا يتجاوز حد الخادم: ما زاد يُقص هنا بدل رفض الطلب كله
          _setText(next.length > widget.status.maxChars ? next.substring(0, widget.status.maxChars) : next);
          if (isFinal) _base = _text.text;
        },
        onError: (e) {
          if (!mounted || _closed) return;
          final code = '$e';
          setState(() {
            _halt();
            // صمت أو إيقاف: ليس خطأ يستحق رسالة
            if (code.contains('no-speech') || code.contains('aborted')) return;
            _error = code.contains('not-allowed') ? 'الميكروفون غير مسموح. اسمح به من إعدادات المتصفح، أو اكتب في الصندوق.' : code.contains('network') ? 'الإملاء يحتاج اتصالاً بالإنترنت. اكتب في الصندوق.' : 'تعذّر الإملاء. اكتب في الصندوق أو حاول مرة أخرى.';
          });
        },
        onEnd: () {
          if (mounted && !_closed) setState(_halt);
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _halt();
          _error = 'تعذّر بدء الإملاء. اكتب في الصندوق.';
        });
      }
    }
  }

  Future<void> _stop() async {
    if (!_listening) return;
    setState(_halt);
    try {
      await _dict?.stop();
    } catch (_) {}
  }

  Future<void> _apply() async {
    if (_busy) return;
    await _stop();
    final t = _text.text.trim();
    if (t.length < widget.status.minChars) {
      setState(() => _error = 'الكلام قصير. اذكر اسمك وما تعمله ومدينتك على الأقل.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.profileVoiceFill(t);
      if (!mounted) return;
      if (r.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'لم نفهم من كلامك ما يملأ الحقول. اذكر اسمك وما تعمله ومدينتك ثم أعد المحاولة.';
        });
        return;
      }
      Navigator.of(context).pop(VoiceFillOutcome(result: r));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = profileVoiceErrText(e);
      });
    }
  }

  Future<void> _withdraw() async {
    await _stop();
    setState(() => _withdrawing = true);
    try {
      await widget.api.withdrawAiConsent(profileVoiceFeature);
      if (mounted) Navigator.of(context).pop(const VoiceFillOutcome(withdrew: true));
    } catch (_) {
      if (mounted) {
        setState(() {
          _withdrawing = false;
          _error = 'تعذّر سحب الموافقة. أعد المحاولة.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _max - _elapsed;
    final atLimit = left <= Duration.zero;
    return SafeArea(
      key: const Key('voice-sheet'),
      child: SingleChildScrollView(
        // لوحة المفاتيح ترفع الورقة فلا تغطي الصندوق ولا الزر
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_busy ? 'نرتّب كلامك في الحقول' : (_canDictate ? 'تكلّم الآن' : 'اكتب عن نفسك'), key: const Key('voice-title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            _canDictate ? 'من أنت، ماذا تعمل، أين تسكن، وما حساباتك. تستطيع تعديل النص أو الكتابة بدل الكلام.' : 'من أنت، ماذا تعمل، أين تسكن، وما حساباتك. اكتب بحرية، أو استخدم ميكروفون لوحة المفاتيح لتتكلم.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(key: Key('voice-progress'), padding: EdgeInsets.symmetric(vertical: 18), child: LinearProgressIndicator())
          else if (_canDictate) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Material(
                color: _listening ? Joy.danger : (atLimit ? Joy.control : Joy.primary),
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('voice-mic'),
                  customBorder: const CircleBorder(),
                  onTap: _listening ? _stop : (atLimit ? null : _start),
                  child: Tooltip(message: _listening ? 'إيقاف' : 'تكلّم', child: SizedBox(width: 56, height: 56, child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28))),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(child: SizedBox(width: 120, height: 36, child: _Bars(animation: _bars, on: _listening))),
            ]),
            const SizedBox(height: 6),
            Text('${clockText(_elapsed.inSeconds.clamp(0, _max.inSeconds))} / ${clockText(_max.inSeconds)}', key: const Key('voice-timer'), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: _listening ? Joy.danger : Joy.textMuted)),
            Text(_listening ? 'نسمعك… اضغط للإيقاف' : (atLimit ? 'انتهت الدقيقة. عدّل النص أو أكمل كتابة.' : 'اضغط الميكروفون لتتكلم'), textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            const SizedBox(height: 10),
          ],
          TextField(
            key: const Key('voice-text'),
            controller: _text,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            maxLength: widget.status.maxChars,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: const InputDecoration(hintText: 'مثال: أنا فهد، مصوّر من جدة حي الشاطئ، أصوّر المنتجات والمقاهي. حسابي في انستقرام fahad.shots', hintMaxLines: 4, counterText: ''),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('voice-error'), style: const TextStyle(color: Joy.danger, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5)),
            ),
          const SizedBox(height: 12),
          FilledButton(key: const Key('voice-apply'), onPressed: _busy || _withdrawing ? null : _apply, child: Text(_busy ? 'لحظات…' : 'رتّب في الحقول')),
          const SizedBox(height: 4),
          const Text('لن يُحفظ شيء حتى تراجع الحقول وتضغط «حفظ».', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          TextButton(
            key: const Key('voice-consent-withdraw'),
            onPressed: _busy || _withdrawing ? null : _withdraw,
            style: TextButton.styleFrom(foregroundColor: Joy.textMuted, textStyle: const TextStyle(fontSize: 12)),
            child: Text(_withdrawing ? 'جارٍ السحب…' : 'سحب موافقتي على المساعد الذكي'),
          ),
        ]),
      ),
    );
  }
}

/// أعمدة تتحرك ما دام الاستماع جارياً، وتسكن قصيرة حين يتوقف.
class _Bars extends StatelessWidget {
  final Animation<double> animation;
  final bool on;
  const _Bars({required this.animation, required this.on});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Row(
          key: const Key('voice-bars'),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 9; i++)
              Container(
                width: 5,
                height: on ? 8 + 26 * (0.5 + 0.5 * math.sin(animation.value * 2 * math.pi + i * 0.9)).abs() : 6,
                decoration: BoxDecoration(color: on ? Joy.primary : Joy.control, borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      );
}
