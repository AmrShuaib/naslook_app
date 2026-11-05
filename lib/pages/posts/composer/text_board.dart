import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/posts_api.dart';
import '../../../core/app_theme.dart';
import '../overlay_canvas.dart';
import 'composer_draft.dart';
import 'voice_layer.dart';

/// لون نص مقروء على لوحة بلون معيّن: أسود على الفاتح وأبيض على الداكن.
String contrastTextColor(String? boardHex) => colorFromHex(boardHex, Colors.white).computeLuminance() > .5 ? '#111111' : '#FFFFFF';

/// مقياس نص اللوحة المحفوظ في المنشور: الطويل أصغر. المعاينة تستخدم القاعدة نفسها حتى تطابق ما يعرضه العارض.
double boardTextScale(String body) => body.length > 80 ? 1.15 : 1.5;

/// أصغر خط يصل إليه التصغير التلقائي أثناء الكتابة؛ بعده يمرّر النص داخل البطاقة.
const double kBoardMinFont = 16;

/// إزاحة لوحة المفاتيح التي تبدأ بها هيئة الكتابة (مع التركيز، وخُمس ارتفاع الشاشة إن كان أكبر): شريط الاختصارات في
/// الآيباد وأجهزة أندرويد اللوحية مع لوحة مفاتيح خارجية (~55–70) ليس لوحة مفاتيح
const double kBoardKeyboardEnter = 120;

/// وتنتهي هيئة الكتابة حين تنزل الإزاحة تحت هذا الحد فقط (تخلّف)، فلا يقفز الشكل في منتصف حركة اللوحة
const double kBoardKeyboardExit = 60;

/// مدة هدوء الإزاحة التي بعدها يُقاس الخط من جديد (iOS وأندرويد الأصليان يرسلان إزاحة جديدة في كل إطار)
const Duration kBoardInsetSettle = Duration(milliseconds: 150);

/// الحد الأقصى لنص اللوحة
const int kBoardMaxChars = 280;

/// العارض (`OverlayContent`) يرسم الخط بعرض القماش × 0.065 × المقياس ويلفّ النص عند 85% من العرض؛ نفس النسبتين هنا
/// تجعلان أسطر المعاينة تنكسر حيث تنكسر بعد النشر.
const double _fontPerWidth = .065, _wrapPerWidth = .85;

/// هامش المؤشر الذي يقتطعه الحقل من عرض النص (فجوة 1 + عرض المؤشر 2) في `RenderEditable`
const double _caretMargin = 3;

/// أكبر خط بين [min] و[base] يجعل [text] يتسع في حقل [maxWidth]×[maxHeight] بقياس الحقل نفسه (عرضه ناقص هامش
/// المؤشر، وارتفاع سطر ثابت من `StrutStyle` كما يفعل `EditableText`). `fits` خطأ حين لا يتسع حتى بالحد الأدنى فيمرّر الحقل.
({double size, bool fits}) fitBoardFont({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double maxHeight,
  required double base,
  double min = kBoardMinFont,
  TextDirection textDirection = TextDirection.rtl,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    fitTextFont(text: text, style: style, width: maxWidth - _caretMargin, maxHeight: maxHeight, base: base, min: min, strut: true, textDirection: textDirection, textScaler: textScaler);

/// نمط «نص»: لوحة ملونة تكتب عليها مباشرة، مع قالب (عادي، سؤال، تنبيه، اقتباس) وخمسة ألوان وزر صوت.
/// النص المكتوب يصبح طبقة نصية في المنشور حتى يعرضها العارض كما هي.
///
/// مع لوحة المفاتيح (`viewInsets`، وعلى سفاري iOS يحسبها Flutter من `visualViewport`) تأخذ البطاقة كل المساحة الظاهرة
/// فوقها بلا نسبة ثابتة، وتُطوى صفوف القوالب والألوان والأنماط حتى «تم»، ويصغر الخط ليظهر النص كله؛ فإن لم يتسع
/// بالحد الأدنى يمرّر داخل البطاقة والمؤشر ظاهر. الشاشة الأم لا تتقلص بنفسها (`resizeToAvoidBottomInset: false`)
/// حتى نرى الإزاحة هنا ونقرر الشكل. بلا لوحة مفاتيح تعرض البطاقة النص بخط العارض نفسه (`overlayFontSize`).
class TextBoardStage extends StatefulWidget {
  final ComposerDraft draft;
  final VoidCallback onClose;
  final ValueChanged<ComposerDraft> onNext;
  final Widget modeStrip;
  const TextBoardStage({super.key, required this.draft, required this.onClose, required this.onNext, required this.modeStrip});
  @override
  State<TextBoardStage> createState() => _TextBoardStageState();
}

class _TextBoardStageState extends State<TextBoardStage> {
  late final TextEditingController text = TextEditingController(text: widget.draft.overlays.where((o) => !o.isSticker && o.font != 'badge').map((o) => o.text).join('\n'));
  final _focus = FocusNode();
  late String board = widget.draft.board;
  late String template = widget.draft.template;
  late VoiceLayer? voice = widget.draft.voice;

  /// هيئة الكتابة (البطاقة بكل المساحة والصفوف مطوية)، تُحسب من الإزاحة والتركيز في [_syncTyping]
  bool _typing = false;
  double? _inset;
  Timer? _insetSettle;
  /// الإزاحة تتحرك إطاراً بإطار: الخط يثبت حتى تهدأ
  bool _insetMoving = false;
  /// آخر قياس للخط ومدخلاته
  ({String text, String template, Object key, double size})? _fit;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom, prev = _inset;
    _inset = inset;
    if (prev != null && inset != prev) {
      // قفزة بحجم لوحة مفاتيح في خطوة واحدة (الويب وسفاري: حدث تغيير حجم واحد) تُقاس فوراً؛ أما الخطوات الصغيرة المتتابعة
      // (حركة اللوحة في iOS وأندرويد الأصليين) فيثبت معها الخط ثم يُقاس مرة واحدة بعد أن تهدأ، بدل أن تنكسر الأسطر في كل إطار
      _insetMoving = (inset - prev).abs() < kBoardKeyboardEnter || (_insetSettle?.isActive ?? false);
      _insetSettle?.cancel();
      _insetSettle = Timer(kBoardInsetSettle, () {
        if (mounted && _insetMoving) setState(() => _insetMoving = false);
      });
    }
    _syncTyping();
  }

  @override
  void dispose() {
    _insetSettle?.cancel();
    _focus.removeListener(_onFocus);
    text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(_syncTyping);
  }

  /// تبدأ الكتابة بالتركيز وإزاحة لوحة مفاتيح حقيقية، وتنتهي حين تنزل الإزاحة تحت [kBoardKeyboardExit] فقط: بعد «تم»
  /// تبقى الهيئة حتى تنزل اللوحة فعلاً بدل أن تعود الصفوف وتنضغط البطاقة فوق لوحة ما زالت ظاهرة
  void _syncTyping() {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final was = _typing;
    _typing = was ? inset > kBoardKeyboardExit : _focus.hasFocus && inset > math.max(kBoardKeyboardEnter, MediaQuery.sizeOf(context).height * .2);
    // نزلت لوحة المفاتيح والحقل ما زال مركّزاً (زر الرجوع في أندرويد): ننهي التحرير حتى تفتح أي نقرة على البطاقة بعدها
    // اتصال إدخال جديداً فتعود اللوحة. على الويب لا طريق غيره: المحرّك يتجاهل `TextInput.show` ما دام التحرير قائماً،
    // وحقل الإدخال المخفي بحجم أسطر النص فقط
    if (was && !_typing && _focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_typing) _focus.unfocus();
      });
    }
  }

  void _pickTemplate(BoardTemplate t) => setState(() {
        template = t.id;
        board = t.board;
      });

  Future<void> _voice() async {
    final v = await showVoiceLayerSheet(context, current: voice);
    if (!mounted) return;
    setState(() => voice = v);
  }

  void _dismissKeyboard() => _focus.unfocus();

  /// نقرة على حشوة البطاقة حول الحقل تبدأ الكتابة (الحقل نفسه يملأ داخلها). نزول لوحة المفاتيح ينهي التحرير
  /// ([_syncTyping])، فيبقى `TextInput.show` للحالة النادرة: حقل مركّز بلا هيئة كتابة (لوحة مفاتيح خارجية مثلاً)
  void _focusText() {
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  void _next() {
    final body = text.text.trim();
    if (body.isEmpty && voice == null) {
      // الشاشة لا تتقلص مع لوحة المفاتيح، فنغلقها أولاً حتى لا يختفي التنبيه خلفها
      _dismissKeyboard();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب شيئاً أو أضف تسجيلاً صوتياً')));
      return;
    }
    final t = boardTemplates.firstWhere((x) => x.id == template);
    final color = contrastTextColor(board);
    final overlays = <PostOverlay>[
      if (t.badge.isNotEmpty) PostOverlay(type: 'text', text: t.badge, x: .5, y: .18, scale: .8, color: '#FFFFFF', bg: '#0A6E78', font: 'badge'),
      if (body.isNotEmpty) PostOverlay(type: 'text', text: body, x: .5, y: .5, scale: boardTextScale(body), color: color, font: template == 'quote' ? 'serif' : 'bold'),
    ];
    _dismissKeyboard();
    widget.onNext(widget.draft
      ..kind = 'text'
      ..board = board
      ..template = template
      ..overlays = overlays
      ..voice = voice
      ..shots.clear()
      ..video = null);
  }

  String get _hint => switch (template) { 'question' => 'اطرح سؤالك على من حولك…', 'alert' => 'ما الذي يجب أن يعرفه الجميع؟', 'quote' => 'اكتب الاقتباس…', _ => 'اكتب هنا…' };

  @override
  Widget build(BuildContext context) {
    final boardColor = colorFromHex(board, Colors.white);
    final fg = colorFromHex(contrastTextColor(board));
    final t = boardTemplates.firstWhere((x) => x.id == template);
    // ما تغطيه لوحة المفاتيح داخل المنطقة الآمنة (SafeArea تحجز الحافة السفلية بنفسها)؛ الإزاحة تُتبع حيّة دائماً
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final kb = (inset - MediaQuery.paddingOf(context).bottom).clamp(0.0, double.infinity);
    final typing = _typing;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, typing ? 6 : 10, 16, 0),
            child: Row(children: [
              Material(color: Colors.black38, shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: widget.onClose, child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Colors.white)))),
              Expanded(
                child: Center(
                  child: typing
                      ? Text('${text.text.characters.length}/$kBoardMaxChars', key: const Key('board-count'), style: const TextStyle(color: Colors.white60, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]))
                      : const Text('نص', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              if (typing)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: TextButton(key: const Key('board-done'), style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white12, shape: const StadiumBorder()), onPressed: _dismissKeyboard, child: const Text('تم')),
                ),
              FilledButton(key: const Key('text-next'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: _next, child: const Text('التالي')),
            ]),
          ),
          Expanded(
            // النقر خارج البطاقة أثناء الكتابة يغلق لوحة المفاتيح (على الويب يفعلها الحقل نفسه)
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: typing ? _dismissKeyboard : null,
              child: LayoutBuilder(builder: (context, box) {
                final double w, h;
                if (typing) {
                  // أثناء الكتابة: كل المساحة الظاهرة بلا نسبة ثابتة
                  w = math.max(0.0, box.maxWidth - 24);
                  h = math.max(0.0, box.maxHeight - 12);
                } else {
                  final fullH = math.max(0.0, box.maxHeight - 16);
                  w = math.max(0.0, math.min(math.max(fullH * 9 / 16, 200.0), box.maxWidth - 40));
                  h = fullH;
                }
                // الحشوة الأفقية تترك للنص 85% من عرض البطاقة (+ هامش المؤشر) كالعارض
                final hp = math.max(0.0, (w - w * _wrapPerWidth - _caretMargin) / 2);
                return Center(
                  child: TextFieldTapRegion(
                    child: GestureDetector(
                      onTap: _focusText,
                      child: Container(
                        key: const Key('board-card'),
                        width: w, height: h, margin: EdgeInsets.symmetric(vertical: typing ? 6 : 8),
                        decoration: BoxDecoration(color: boardColor, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))]),
                        padding: EdgeInsets.symmetric(horizontal: hp, vertical: typing ? 14 : 24),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (t.badge.isNotEmpty) Container(margin: EdgeInsets.only(bottom: typing ? 8 : 14), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)), child: Text(t.badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                          // الحقل يملأ ما بين الشارة والشريحة، والنص في وسطه
                          Expanded(child: LayoutBuilder(builder: (context, c) => _field(context, c, card: Size(w, h), typing: typing, fg: fg))),
                          // الشريحة الصوتية تُخفى أثناء الكتابة لتتسع الأسطر، وتعود بعدها. تصغر لعرض البطاقة الضيقة، وتغيب عن بطاقة
                          // قصيرة (الهاتف بالعرض) لا تتسع فيها مع الشارة والحقل؛ زر «صوت ✓» تحت البطاقة يدل عليها
                          if (voice != null && !typing && h - 48 >= 160) Padding(padding: const EdgeInsets.only(top: 16), child: FittedBox(fit: BoxFit.scaleDown, child: VoiceChip(layer: voice, light: fg == const Color(0xFF111111)))),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // القوالب والألوان والصوت وشريط الأنماط: تُطوى أثناء الكتابة
          if (!typing) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Column(children: [
                Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                  for (final tp in boardTemplates)
                    ChoiceChip(key: Key('tpl-${tp.id}'), label: Text(tp.label, style: TextStyle(color: template == tp.id ? Colors.black : Colors.white, fontSize: 13, fontWeight: template == tp.id ? FontWeight.w700 : FontWeight.w500)), selected: template == tp.id, showCheckmark: false, selectedColor: Colors.white, backgroundColor: Colors.white12, side: BorderSide.none, onSelected: (_) => _pickTemplate(tp)),
                ]),
                const SizedBox(height: 10),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                  const Text('لون اللوحة', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  for (final c in boardColors)
                    InkWell(
                      key: Key('board-$c'), onTap: () => setState(() => board = c), borderRadius: BorderRadius.circular(999),
                      child: Container(width: 30, height: 30, decoration: BoxDecoration(color: colorFromHex(c), shape: BoxShape.circle, border: Border.all(color: board == c ? Joy.sun : Colors.white38, width: board == c ? 3 : 1.5))),
                    ),
                  FilledButton.icon(key: const Key('board-voice'), style: FilledButton.styleFrom(backgroundColor: voice != null ? Joy.sun : Colors.white12, foregroundColor: voice != null ? Joy.sunText : Colors.white, visualDensity: VisualDensity.compact), onPressed: _voice, icon: const Icon(Icons.mic_rounded, size: 18), label: Text(voice != null ? 'صوت ✓' : 'صوت')),
                ]),
              ]),
            ),
            widget.modeStrip,
          ],
          SizedBox(height: typing ? 4 : 22),
        ]),
      ),
    );
  }

  /// حقل الكتابة يملأ المساحة [c] بخط يتسع فيها. يبدأ بحجم المنشور (عرض البطاقة × 0.065 × المقياس)؛ أثناء الكتابة يصغر
  /// حتى [kBoardMinFont] ثم يمرّر داخلياً و`EditableText` يبقي المؤشر ظاهراً، وبلا لوحة مفاتيح يصغر كما يصغر في العارض
  /// (حصة [kOverlayTextRoom] من ارتفاع بطاقة ٩:١٦) فتطابق المعاينة ما سيُنشر.
  Widget _field(BuildContext context, BoxConstraints c, {required Size card, required bool typing, required Color fg}) {
    final body = text.text;
    final base = card.width * _fontPerWidth * boardTextScale(body.trim());
    // النمط الفعلي للحقل (الحقل يدمج bodyLarge من الثيم) حتى يطابق القياسُ التخطيطَ حرفياً؛ تباعد الأحرف كنص العارض
    final style = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).merge(TextStyle(color: fg, fontSize: base, height: 1.25, letterSpacing: .25, fontWeight: FontWeight.w800, fontFamily: template == 'quote' ? 'serif' : null));
    final s = style.copyWith(fontSize: _fontFor(context, c, body: body, base: base, style: style, card: card, typing: typing));
    return TextField(
      key: const Key('board-text'),
      controller: text, focusNode: _focus, autofocus: true, expands: true, maxLines: null, minLines: null, maxLength: kBoardMaxChars,
      textAlign: TextAlign.center, textAlignVertical: TextAlignVertical.center,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      style: s,
      cursorColor: fg,
      decoration: InputDecoration.collapsed(hintText: _hint, hintStyle: s.copyWith(color: fg.withValues(alpha: .4))),
      onChanged: (_) => setState(() {}),
    );
  }

  /// حجم الخط: يُقاس فوراً حين يتغير النص أو القالب أو المساحة، إلا أثناء حركة لوحة المفاتيح ([_insetMoving]) فيبقى
  /// آخر حجم ما لم يتغير النص، ثم يُقاس مرة واحدة حين تهدأ
  double _fontFor(BuildContext context, BoxConstraints c, {required String body, required double base, required TextStyle style, required Size card, required bool typing}) {
    if (!c.maxWidth.isFinite || !c.maxHeight.isFinite) return base;
    final scaler = MediaQuery.textScalerOf(context), dir = Directionality.of(context);
    final key = (base, card, c.maxWidth, c.maxHeight, typing, scaler, dir);
    final last = _fit;
    if (last != null && last.text == body && last.template == template && (last.key == key || _insetMoving)) return last.size;
    double fit({required double maxHeight, required double base, required double min}) =>
        fitBoardFont(text: body.isEmpty ? _hint : body, style: style, maxWidth: c.maxWidth, maxHeight: maxHeight, base: base, min: min, textDirection: dir, textScaler: scaler).size;
    var size = base;
    if (!typing) {
      // خط العارض لهذا النص نسبةً إلى العرض (قماشه المرجعي ٩:١٦ بعرض البطاقة، كما في `overlayFontSize`)
      size = fit(maxHeight: kOverlayTextRoom * card.width * 16 / 9, base: base, min: card.width * kOverlayMinFontPerWidth);
    }
    // ثم أصغر فقط إن لم تتسع له المساحة (أثناء الكتابة، أو بطاقة أقصر من ٩:١٦ في هاتف صغير بخط كبير أو بالعرض) حتى الحد
    // المقروء، وبعده يمرّر
    size = fit(maxHeight: c.maxHeight, base: size, min: math.min(kBoardMinFont, size));
    _fit = (text: body, template: template, key: key, size: size);
    return size;
  }
}
