import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/speech/dictation.dart';
import '../../../ui/widgets.dart';
import '../chat_cards.dart';
import 'audio_bubble.dart' show fmtDuration;
import 'bubble.dart' show QuoteBox;

/// إجراء في قائمة المرفقات (صورة، كاميرا، فيديو… أو ما يضيفه المدمج مثل «مشاركة موقعي الحي»).
class AttachAction {
  final Key? key;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const AttachAction({this.key, required this.icon, required this.label, this.color = Joy.primary, required this.onTap});
}

/// مؤلّف الرسائل: حقل حبّة يكبر إلى خمسة أسطر، زر المرفقات، زر الإملاء (حين يكون مدعوماً)، زر ميكروفون/إرسال
/// يتبدّل بتكبير 150 مللي ثانية، تسجيل بالضغط المطوّل مع السحب للإلغاء والقفل بالسحب لأعلى (والنقرة تبدأ التسجيل
/// كما كانت)، شريط الرد المقتبس، وفتحة [above] فوق الحقل لشرائح الاقتراحات.
class ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;
  /// يُستدعى مع كل تغيير في النص (لإرسال «يكتب…»).
  final ValueChanged<String>? onChanged;
  /// الإجراءات المدمجة في قائمة المرفقات بعد شبكة الرموز الذكية.
  final List<AttachAction> attachActions;
  /// نقطة توسعة للمدمج: إجراءات تُعرض بعد المدمجة (مثل «مشاركة موقعي الحي»).
  final List<AttachAction> extraAttachActions;
  /// اختيار من شبكة الرموز الذكية داخل قائمة المرفقات.
  final ValueChanged<String> onCode;
  /// شريط اقتراحات الرموز (@ و# و/) الذي تبنيه الصفحة.
  final Widget? codeSuggestions;
  /// فتحة فوق الحقل: شرائح الردود المقترحة يمرّرها المدمج.
  final Widget? above;
  final String? replyName, replyText;
  final VoidCallback? onCancelReply;
  final bool recording;
  final Duration recElapsed, maxRecord;
  final VoidCallback onStartRecording;
  final void Function({required bool send}) onStopRecording;
  const ChatComposer({
    super.key,
    required this.controller,
    this.hint = 'اكتب رسالة…',
    required this.onSend,
    this.onChanged,
    this.attachActions = const [],
    this.extraAttachActions = const [],
    required this.onCode,
    this.codeSuggestions,
    this.above,
    this.replyName,
    this.replyText,
    this.onCancelReply,
    this.recording = false,
    this.recElapsed = Duration.zero,
    this.maxRecord = const Duration(minutes: 5),
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  static const _cancelDistance = 80.0, _lockDistance = 60.0;
  late bool _hasText = widget.controller.text.trim().isNotEmpty;
  // الإملاء
  Dictation? _dict;
  bool _dictating = false;
  String _dictBase = '';
  // التسجيل بالضغط المطوّل
  bool _hold = false, _locked = false, _releasedEarly = false;
  double _cancelDx = 0, _lockDy = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (widget.recording && !old.recording && _releasedEarly) {
      // رفع الإصبع قبل أن يبدأ التسجيل فعلاً (انتظار إذن الميكروفون): لا نترك تسجيلاً مفتوحاً
      _releasedEarly = false;
      widget.onStopRecording(send: false);
    }
    if (!widget.recording && old.recording) {
      _hold = false;
      _locked = false;
      _cancelDx = 0;
      _lockDy = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _dict?.dispose();
    super.dispose();
  }

  void _onText() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _setText(String s) {
    widget.controller.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    widget.onChanged?.call(s);
  }

  // ---- الإملاء: الجزئي يُلحق بالنص الموجود، والنهائي يحل محل الجزئي
  Future<void> _toggleDictation() async {
    if (_dictating) {
      await _dict?.stop();
      if (mounted) setState(() => _dictating = false);
      return;
    }
    final d = _dict ??= Dictation();
    var base = widget.controller.text;
    if (base.isNotEmpty && !base.endsWith(' ') && !base.endsWith('\n')) base += ' ';
    _dictBase = base;
    setState(() => _dictating = true);
    try {
      await d.start(
        onText: (t, isFinal) {
          if (!mounted) return;
          _setText('$_dictBase$t${isFinal ? ' ' : ''}');
          if (isFinal) _dictBase = widget.controller.text;
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _dictating = false);
          toast(context, 'تعذّر الإملاء، حاول مرة أخرى', error: true);
        },
        onEnd: () {
          if (mounted) setState(() => _dictating = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _dictating = false);
      toast(context, 'تعذّر بدء الإملاء', error: true);
    }
  }

  // ---- قائمة المرفقات: الرموز الذكية ثم الإجراءات المدمجة ثم إجراءات المدمج
  Future<void> _openAttach() => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              CodesMenuGrid(onPick: (r) {
                Navigator.pop(ctx);
                widget.onCode(r);
              }),
              const Divider(height: 8),
              for (final a in [...widget.attachActions, ...widget.extraAttachActions])
                ListTile(
                  key: a.key,
                  leading: Icon(a.icon, color: a.color),
                  title: Text(a.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      );

  // ---- الضغط المطوّل على الميكروفون
  void _holdStart(LongPressStartDetails _) {
    if (_hasText || widget.recording) return;
    _hold = true;
    _locked = false;
    _releasedEarly = false;
    _cancelDx = 0;
    _lockDy = 0;
    HapticFeedback.mediumImpact();
    setState(() {});
    widget.onStartRecording();
  }

  void _holdMove(LongPressMoveUpdateDetails d) {
    if (!_hold) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // الإلغاء بالسحب نحو المنتصف (بعيداً عن حافة الزر)، والقفل بالسحب لأعلى
    final cancel = d.offsetFromOrigin.dx * (rtl ? 1 : -1);
    final lock = -d.offsetFromOrigin.dy;
    if (cancel >= _cancelDistance) {
      _hold = false;
      setState(() => _cancelDx = 0);
      if (widget.recording) widget.onStopRecording(send: false);
      return;
    }
    if (lock >= _lockDistance && !_locked) {
      _locked = true;
      HapticFeedback.mediumImpact();
    }
    setState(() {
      _cancelDx = cancel.clamp(0.0, _cancelDistance);
      _lockDy = lock.clamp(0.0, _lockDistance);
    });
  }

  void _holdEnd(LongPressEndDetails _) => _release();

  void _release() {
    if (!_hold) return;
    _hold = false;
    if (!widget.recording) {
      _releasedEarly = true;
    } else if (!_locked) {
      widget.onStopRecording(send: true);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recording;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!rec && widget.codeSuggestions != null) widget.codeSuggestions!,
          if (!rec && widget.above != null) widget.above!,
          if (widget.replyName != null)
            Container(
              key: const Key('reply-strip'),
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
              child: Row(children: [
                Expanded(child: QuoteBox(name: widget.replyName!, text: widget.replyText ?? '', compact: true)),
                IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'إلغاء الرد', onPressed: widget.onCancelReply),
              ]),
            ),
          Padding(
            key: const ValueKey('composer-row'),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (rec)
                IconButton(tooltip: 'إلغاء التسجيل', onPressed: () => widget.onStopRecording(send: false), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger, size: 26))
              else
                IconButton(tooltip: 'إرفاق', onPressed: _openAttach, icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.textMuted, size: 28)),
              Expanded(child: rec ? _recordingRow() : _field()),
              const SizedBox(width: 8),
              _mainButton(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _field() {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none);
    final dictate = Dictation.supported
        ? IconButton(
            key: const Key('dictate'),
            tooltip: _dictating ? 'إيقاف الإملاء' : 'إملاء صوتي',
            onPressed: _toggleDictation,
            iconSize: 22,
            icon: Stack(clipBehavior: Clip.none, children: [
              Icon(_dictating ? Icons.graphic_eq_rounded : Icons.keyboard_voice_outlined, color: _dictating ? Joy.primary : Joy.textMuted),
              if (_dictating) const Positioned(top: -2, right: -2, child: _Blink(child: SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Joy.danger, shape: BoxShape.circle))))),
            ]),
          )
        : null;
    return TextField(
      key: const Key('composer-field'),
      controller: widget.controller,
      style: const TextStyle(fontSize: 16),
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => widget.onSend(),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        filled: true,
        fillColor: Joy.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        suffixIcon: dictate,
        suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }

  Widget _recordingRow() {
    final sliding = _hold && !_locked;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      height: 46,
      child: Row(children: [
        const _Blink(child: SizedBox(width: 10, height: 10, child: DecoratedBox(decoration: BoxDecoration(color: Joy.danger, shape: BoxShape.circle)))),
        const SizedBox(width: 8),
        Text('${fmtDuration(widget.recElapsed)} / ${fmtDuration(widget.maxRecord)}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: sliding
              ? Transform.translate(
                  // النص يتبع الإصبع ويتلاشى كلما اقترب من حدّ الإلغاء
                  offset: Offset(_cancelDx * (rtl ? 1 : -1) * .6, 0),
                  child: Opacity(
                    opacity: 1 - (_cancelDx / _cancelDistance).clamp(0.0, .85),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 18, color: Joy.textMuted),
                      const Flexible(child: Text('اسحب للإلغاء', key: Key('slide-cancel'), style: TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Transform.translate(offset: Offset(0, -_lockDy * .25), child: Icon(_lockDy > 0 ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: _lockDy >= _lockDistance * .9 ? Joy.primary : Joy.textMuted)),
                    ]),
                  ),
                )
              : Text(_locked ? 'التسجيل مقفول… اضغط إرسال عند الانتهاء' : 'جارٍ التسجيل… اضغط إرسال عند الانتهاء', key: const Key('rec-hint'), style: const TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  /// زر الميكروفون/الإرسال: عنصر واحد يبقى مثبتاً في الشجرة حتى لا ينقطع الضغط المطوّل حين يتبدّل الصف.
  Widget _mainButton() {
    final rec = widget.recording;
    final holding = rec && _hold && !_locked;
    final showSend = _hasText || (rec && !holding);
    return GestureDetector(
      key: const Key('composer-main'),
      behavior: HitTestBehavior.opaque,
      onTap: rec ? () => widget.onStopRecording(send: true) : (_hasText ? widget.onSend : widget.onStartRecording),
      onLongPressStart: _holdStart,
      onLongPressMoveUpdate: _holdMove,
      onLongPressEnd: _holdEnd,
      onLongPressCancel: _release,
      child: AnimatedScale(
        scale: holding ? 1.25 : 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: holding ? Joy.danger : Joy.primary,
          shape: const CircleBorder(),
          elevation: holding ? 4 : 0,
          child: SizedBox(
            width: 46,
            height: 46,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              // تكبير من 0.6 لا من الصفر مع تلاشٍ: الأيقونة الجديدة تستقبل اللمس من أول إطار
              transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
              child: Icon(showSend ? Icons.send_rounded : Icons.mic_rounded, key: ValueKey(showSend), color: Joy.primaryOn, size: showSend ? 20 : 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// وميض بطيء (نقطة التسجيل والإملاء).
class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: .35, end: 1.0).animate(_ctl), child: widget.child);
}
