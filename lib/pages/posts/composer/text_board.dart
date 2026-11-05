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

/// الحد الأقصى لنص اللوحة
const int kBoardMaxChars = 280;

/// العارض (`OverlayContent`) يرسم الخط بعرض القماش × 0.065 × المقياس ويلفّ النص عند 85% من العرض؛ نفس النسبتين هنا
/// تجعلان أسطر المعاينة تنكسر حيث تنكسر بعد النشر.
const double _fontPerWidth = .065, _wrapPerWidth = .85;

/// هامش المؤشر الذي يقتطعه الحقل من عرض النص (فجوة 1 + عرض المؤشر 2) في `RenderEditable`
const double _caretMargin = 3;

/// أكبر خط بين [min] و[base] يجعل [text] يتسع في [maxWidth]×[maxHeight] بقياس الحقل نفسه (ارتفاع سطر ثابت من
/// `StrutStyle` كما يفعل `EditableText`). `fits` خطأ حين لا يتسع حتى بالحد الأدنى فيمرّر الحقل.
/// الحجم يُقرَّب إلى نصف بكسل حتى لا يرتجف الخط مع كل حرف.
({double size, bool fits}) fitBoardFont({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double maxHeight,
  required double base,
  double min = kBoardMinFont,
  TextDirection textDirection = TextDirection.rtl,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final width = math.max(0.0, maxWidth - _caretMargin);
  double measure(double f) {
    final s = style.copyWith(fontSize: f);
    final tp = TextPainter(text: TextSpan(text: text, style: s), textAlign: TextAlign.center, textDirection: textDirection, textScaler: textScaler, strutStyle: StrutStyle.fromTextStyle(s, forceStrutHeight: true))
      ..layout(minWidth: width, maxWidth: width);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  final lo = math.min(min, base);
  if (measure(base) <= maxHeight) return (size: base, fits: true);
  if (measure(lo) > maxHeight) return (size: lo, fits: false);
  // بحث ثنائي على درجات نصف بكسل فوق lo: الدرجة a تتسع والدرجة b لا تتسع (base نفسه لا يتسع)
  final steps = ((base - lo) * 2).floor();
  var a = 0, b = lo + steps / 2 >= base - 1e-9 ? steps : steps + 1;
  while (b - a > 1) {
    final m = (a + b) >> 1;
    if (measure(lo + m / 2) <= maxHeight) {
      a = m;
    } else {
      b = m;
    }
  }
  return (size: lo + a / 2, fits: true);
}

/// نمط «نص»: لوحة ملونة تكتب عليها مباشرة، مع قالب (عادي، سؤال، تنبيه، اقتباس) وخمسة ألوان وزر صوت.
/// النص المكتوب يصبح طبقة نصية في المنشور حتى يعرضها العارض كما هي.
///
/// مع لوحة المفاتيح (`viewInsets`، وعلى سفاري iOS يحسبها Flutter من `visualViewport`) تأخذ البطاقة كل المساحة الظاهرة
/// فوقها بلا نسبة ثابتة، وتُطوى صفوف القوالب والألوان والأنماط حتى «تم»، ويصغر الخط ليظهر النص كله؛ فإن لم يتسع
/// بالحد الأدنى يمرّر داخل البطاقة والمؤشر ظاهر. الشاشة الأم لا تتقلص بنفسها (`resizeToAvoidBottomInset: false`)
/// حتى نرى الإزاحة هنا ونقرر الشكل.
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

  @override
  void dispose() {
    text.dispose();
    _focus.dispose();
    super.dispose();
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

  /// نقرة على البطاقة خارج الأسطر تبدأ الكتابة، أو تعيد لوحة المفاتيح إن أُخفيت والحقل ما زال مركّزاً (زر الرجوع في أندرويد)
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
    // ما تغطيه لوحة المفاتيح داخل المنطقة الآمنة (SafeArea تحجز الحافة السفلية بنفسها)
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final kb = (inset - MediaQuery.paddingOf(context).bottom).clamp(0.0, double.infinity);
    // عتبة صغيرة حتى لا تُطوى الصفوف لإزاحة عابرة لا تخص لوحة مفاتيح
    final typing = inset > 40;
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
                          Flexible(child: LayoutBuilder(builder: (context, c) => _field(context, c, cardWidth: w, fg: fg))),
                          // الشريحة الصوتية تُخفى أثناء الكتابة لتتسع الأسطر، وتعود بعدها
                          if (voice != null && !typing) Padding(padding: const EdgeInsets.only(top: 16), child: VoiceChip(layer: voice, light: fg == const Color(0xFF111111))),
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

  /// حقل الكتابة بخط يتسع في المساحة [c]: يبدأ بحجم المنشور (عرض البطاقة × 0.065 × المقياس) ويصغر حتى [kBoardMinFont]،
  /// وبعده يُحدّ ارتفاعه فيمرّر داخلياً و`EditableText` يبقي المؤشر ظاهراً.
  Widget _field(BuildContext context, BoxConstraints c, {required double cardWidth, required Color fg}) {
    final body = text.text;
    final base = cardWidth * _fontPerWidth * boardTextScale(body.trim());
    // النمط الفعلي للحقل (الحقل يدمج bodyLarge من الثيم) حتى يطابق القياسُ التخطيطَ حرفياً؛ تباعد الأحرف كنص العارض
    final style = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).merge(TextStyle(color: fg, fontSize: base, height: 1.25, letterSpacing: .25, fontWeight: FontWeight.w800, fontFamily: template == 'quote' ? 'serif' : null));
    final maxH = c.maxHeight.isFinite ? c.maxHeight : double.infinity;
    final fit = maxH.isFinite && c.maxWidth.isFinite
        ? fitBoardFont(text: body.isEmpty ? _hint : body, style: style, maxWidth: c.maxWidth, maxHeight: maxH, base: base, textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
        : (size: base, fits: true);
    final s = style.copyWith(fontSize: fit.size);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: TextField(
        key: const Key('board-text'),
        controller: text, focusNode: _focus, autofocus: true, maxLines: null, maxLength: kBoardMaxChars, textAlign: TextAlign.center,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        style: s,
        cursorColor: fg,
        decoration: InputDecoration.collapsed(hintText: _hint, hintStyle: s.copyWith(color: fg.withValues(alpha: .4))),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
