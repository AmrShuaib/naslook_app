// لوحة «نص» في المحرّر مع لوحة المفاتيح: البطاقة تأخذ المساحة الظاهرة فوقها، صفوف القوالب والألوان والأنماط تختفي
// أثناء الكتابة وتعود بعدها، والخط يصغر ليظهر النص الطويل كاملاً ثم يمرّر داخل البطاقة مع بقاء المؤشر ظاهراً.
// المقاسات بمقاس آيفون (390×844) ولوحة مفاتيح سفاري (336) كما في لقطات المالك.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/api/posts_api.dart';
import 'package:naslook/pages/posts/composer/capture_page.dart';
import 'package:naslook/pages/posts/composer/composer_draft.dart';
import 'package:naslook/pages/posts/composer/edit_page.dart';
import 'package:naslook/pages/posts/composer/text_board.dart';
import 'package:naslook/pages/posts/overlay_canvas.dart';

const _screen = Size(390, 844);
const _keyboard = 336.0;

/// نص عربي طويل (≈٢٤٠ حرفاً) كالذي قُصّ في لقطة المالك
const _long = 'اللهم إنا نسألك رضاك والجنة ونعوذ بك من سخطك والنار، اللهم اغفر لنا ذنوبنا وكفّر عنا سيئاتنا وتوفنا مع الأبرار، '
    'سبحان الله والحمد لله ولا إله إلا الله والله أكبر ولا حول ولا قوة إلا بالله العلي العظيم، وصلى الله على نبينا محمد';

/// يفتح شاشة الالتقاط من زر ثم ينتقل إلى نمط «نص»؛ يعيد دالة تقرأ المسودة التي أعادتها الشاشة عند «التالي»
Future<ComposerDraft? Function()> _openBoard(WidgetTester tester, {FakeViewPadding padding = FakeViewPadding.zero, Size screen = _screen}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);
  ComposerDraft? result;
  Future<void> open(BuildContext ctx) async {
    result = await Navigator.of(ctx).push<ComposerDraft>(MaterialPageRoute(builder: (_) => CapturePage(draft: ComposerDraft(lat: 21.5, lng: 39.2))));
  }

  // التطبيق عربي (من اليمين إلى اليسار) كما على الجهاز
  await tester.pumpWidget(MaterialApp(
    builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => open(ctx), child: const Text('open'))))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('mode-text')));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _keyboardUp(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  await tester.pumpAndSettle();
}

Future<void> _keyboardDown(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();
}

EditableTextState _editable(WidgetTester tester) => tester.state<EditableTextState>(find.descendant(of: find.byKey(const Key('board-text')), matching: find.byType(EditableText)));
ScrollPosition _scroll(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('board-text')), matching: find.byType(Scrollable))).position;

Rect _globalRect(RenderBox b) => b.localToGlobal(Offset.zero) & b.size;

double _boardFont(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('board-text'))).style!.fontSize!;

/// صفوف القوالب والألوان والأنماط ظاهرة (هيئة اللوحة العادية) أم مطوية (هيئة الكتابة)
bool _rowsShown() => find.byKey(const Key('tpl-question')).evaluate().isNotEmpty;

/// خط نص طبقة كما يرسمها `OverlayCanvas` (العارض والمحرّر) ومستطيلها
({double size, Rect rect, bool exceeded}) _overlayText(WidgetTester tester, String text) {
  final f = find.text(text);
  final p = tester.renderObject<RenderParagraph>(f);
  return (size: tester.widget<Text>(f).style!.fontSize!, rect: _globalRect(p), exceeded: p.didExceedMaxLines);
}

Future<void> _pumpCanvas(WidgetTester tester, Size canvas, List<PostOverlay> overlays) async {
  tester.view.physicalSize = canvas;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(body: SizedBox.expand(child: OverlayCanvas(overlays: overlays, shadow: false))),
  ));
}

/// كل أسطر النص داخل صندوق الحقل (لا شيء خارج حدوده) والحقل داخل البطاقة الظاهرة
void _expectWholeTextInsideCard(WidgetTester tester, {required double visibleBottom}) {
  final re = _editable(tester).renderEditable;
  final card = tester.getRect(find.byKey(const Key('board-card')));
  final field = _globalRect(re);
  expect(card.bottom, lessThanOrEqualTo(visibleBottom + .5), reason: 'البطاقة كلها فوق لوحة المفاتيح');
  expect(field.top, greaterThanOrEqualTo(card.top - .5));
  expect(field.bottom, lessThanOrEqualTo(card.bottom + .5), reason: 'الحقل لا يخرج من أسفل البطاقة (كان «ولا حول» يُقصّ)');
  expect(field.left, greaterThanOrEqualTo(card.left - .5));
  expect(field.right, lessThanOrEqualTo(card.right + .5));
  final len = re.text!.toPlainText().length;
  final boxes = re.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  expect(boxes, isNotEmpty);
  for (final b in boxes) {
    expect(b.top, greaterThanOrEqualTo(-.5));
    expect(b.bottom, lessThanOrEqualTo(re.size.height + .5), reason: 'سطر خارج الحقل: ${b.toRect()} في ${re.size}');
  }
}

void main() {
  testWidgets('keyboard open: rows collapse, the card takes the visible height and long Arabic text shrinks to show in full; rows return after «تم»', (tester) async {
    final draft = await _openBoard(tester);
    expect(find.byKey(const Key('tpl-question')), findsOneWidget);
    expect(find.byKey(const Key('board-voice')), findsOneWidget);
    expect(find.byKey(const Key('mode-photo')), findsOneWidget);
    final cardClosed = tester.getRect(find.byKey(const Key('board-card')));

    await _keyboardUp(tester);
    await tester.enterText(find.byKey(const Key('board-text')), _long);
    await tester.pumpAndSettle();

    // صفوف القوالب والألوان والأنماط مطوية حتى تُغلق لوحة المفاتيح
    for (final k in ['tpl-plain', 'tpl-question', 'board-#FFFFFF', 'board-voice', 'mode-photo', 'mode-text']) {
      expect(find.byKey(Key(k)), findsNothing, reason: '$k مخفي أثناء الكتابة');
    }
    expect(find.byKey(const Key('board-done')), findsOneWidget);
    expect(find.byKey(const Key('text-next')), findsOneWidget, reason: '«التالي» يبقى متاحاً');

    // البطاقة بلا نسبة ثابتة: بعرض الشاشة تقريباً وبكل الارتفاع الظاهر فوق اللوحة
    final card = tester.getRect(find.byKey(const Key('board-card')));
    expect(card.width, greaterThan(cardClosed.width), reason: 'أعرض من بطاقة ٩:١٦');
    expect(card.width, greaterThan(_screen.width - 40));
    expect(card.bottom, lessThanOrEqualTo(_screen.height - _keyboard));
    expect(card.bottom, greaterThan(_screen.height - _keyboard - 30), reason: 'تمتد حتى لوحة المفاتيح');

    // الخط صغُر ليتسع النص كله بلا تمرير (فوق الحد الأدنى المقروء)
    final style = tester.widget<TextField>(find.byKey(const Key('board-text'))).style!;
    final base = card.width * .065 * boardTextScale(_long);
    expect(style.fontSize, lessThan(base), reason: 'تصغير تلقائي');
    expect(style.fontSize, greaterThanOrEqualTo(kBoardMinFont));
    expect(_scroll(tester).maxScrollExtent, 0, reason: 'النص كله ظاهر دون تمرير');
    _expectWholeTextInsideCard(tester, visibleBottom: _screen.height - _keyboard);

    // «تم» تغلق لوحة المفاتيح فتعود الصفوف والبطاقة بنسبتها
    await tester.tap(find.byKey(const Key('board-done')));
    await tester.pump();
    expect(_editable(tester).widget.focusNode.hasFocus, isFalse);
    await _keyboardDown(tester);
    for (final k in ['tpl-plain', 'tpl-question', 'board-#FFFFFF', 'board-voice', 'mode-photo', 'mode-text']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: '$k عاد بعد إغلاق لوحة المفاتيح');
    }
    expect(find.byKey(const Key('board-done')), findsNothing);
    expect(tester.getRect(find.byKey(const Key('board-card'))), cardClosed);
    _expectWholeTextInsideCard(tester, visibleBottom: _screen.height);

    // البيانات المحفوظة لم تتغير: القاعدة نفسها لحجم النص الطويل وموضعه
    await tester.tap(find.byKey(const Key('text-next')));
    await tester.pumpAndSettle();
    final d = draft()!;
    final body = d.overlays.singleWhere((o) => o.font != 'badge');
    expect(body.text, _long);
    expect(body.scale, 1.15);
    expect((body.x, body.y), (.5, .5));
  });

  testWidgets('text beyond the minimum font scrolls inside the card and keeps the caret in view', (tester) async {
    await _openBoard(tester);
    await _keyboardUp(tester);
    // ٤٠ سطراً قصيراً لا تتسع حتى بأصغر خط
    final many = List.generate(40, (i) => 'سطر ${i + 1}').join('\n');
    await tester.enterText(find.byKey(const Key('board-text')), many);
    await tester.pumpAndSettle();
    final style = tester.widget<TextField>(find.byKey(const Key('board-text'))).style!;
    expect(style.fontSize, kBoardMinFont, reason: 'يتوقف التصغير عند الحد الأدنى');
    final re = _editable(tester).renderEditable;
    final card = tester.getRect(find.byKey(const Key('board-card')));
    final field = _globalRect(re);
    expect(field.bottom, lessThanOrEqualTo(card.bottom + .5), reason: 'الحقل محدود بالبطاقة ويمرّر داخلها');
    expect(card.bottom, lessThanOrEqualTo(_screen.height - _keyboard));
    final pos = _scroll(tester);
    expect(pos.maxScrollExtent, greaterThan(0));
    // المؤشر في آخر النص ظاهر داخل الحقل
    final caret = re.getLocalRectForCaret(TextPosition(offset: many.length));
    expect(caret.top, greaterThanOrEqualTo(-.5));
    expect(caret.bottom, lessThanOrEqualTo(re.size.height + .5), reason: 'المؤشر داخل المساحة الظاهرة: $caret في ${re.size}');
  });

  testWidgets('with the keyboard closed the board previews the published size: card width × 0.065 × scale and 85% wrap width', (tester) async {
    await _openBoard(tester);
    await tester.enterText(find.byKey(const Key('board-text')), 'من يجي معي للحرم الجمعة؟');
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const Key('board-card')));
    expect(card.width / card.height, closeTo(9 / 16, .02), reason: 'نسبة ٩:١٦ حين تكون لوحة المفاتيح مغلقة');
    final style = tester.widget<TextField>(find.byKey(const Key('board-text'))).style!;
    // العارض (OverlayContent): الخط = عرض القماش × 0.065 × المقياس، والنص يلتف عند 85% من العرض
    expect(style.fontSize, closeTo(card.width * .065 * 1.5, .01));
    final re = _editable(tester).renderEditable;
    expect(re.size.width - 3, closeTo(card.width * .85, .5), reason: 'عرض الالتفاف كالعارض (بعد هامش المؤشر)');
    expect(find.byKey(const Key('tpl-question')), findsOneWidget, reason: 'بلا لوحة مفاتيح تبقى الصفوف ظاهرة');
  });

  testWidgets('iPhone safe areas and a template badge: the card sits between the notch and the keyboard with the whole text', (tester) async {
    // الحافة العلوية (الجزيرة) والسفلية (شريط الرجوع) كآيفون؛ الحافة السفلية جزء مما تغطيه لوحة المفاتيح فلا تُحسب مرتين
    await _openBoard(tester, padding: const FakeViewPadding(top: 47, bottom: 34));
    await tester.tap(find.byKey(const Key('tpl-quote')));
    await tester.pump();
    await _keyboardUp(tester);
    await tester.enterText(find.byKey(const Key('board-text')), _long);
    await tester.pumpAndSettle();
    expect(find.text('اقتباس'), findsOneWidget, reason: 'شارة القالب تبقى أعلى البطاقة');
    final card = tester.getRect(find.byKey(const Key('board-card')));
    expect(card.top, greaterThan(47));
    expect(card.bottom, greaterThan(_screen.height - _keyboard - 30));
    expect(find.byKey(const Key('tpl-quote')), findsNothing);
    expect(_scroll(tester).maxScrollExtent, 0);
    _expectWholeTextInsideCard(tester, visibleBottom: _screen.height - _keyboard);
    expect(tester.widget<Text>(find.byKey(const Key('board-count'))).data, '${_long.characters.length}/280', reason: 'عدّاد الأحرف (كما يعدّها حدّ الحقل) مكان العنوان أثناء الكتابة');
  });

  test('fitBoardFont keeps the base size when the text fits and never goes below the minimum', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const style = TextStyle(fontSize: 30, height: 1.25);
    final fits = fitBoardFont(text: 'قصير', style: style, maxWidth: 300, maxHeight: 400, base: 30);
    expect(fits, (size: 30.0, fits: true));
    final shrunk = fitBoardFont(text: _long, style: style, maxWidth: 300, maxHeight: 300, base: 30);
    expect(shrunk.fits, isTrue);
    expect(shrunk.size, inExclusiveRange(kBoardMinFont, 30));
    final floor = fitBoardFont(text: List.filled(60, 'سطر').join('\n'), style: style, maxWidth: 300, maxHeight: 200, base: 30);
    expect(floor, (size: kBoardMinFont, fits: false));
  });

  testWidgets('Android back hides the keyboard while focused: editing ends, and a tap anywhere on the card opens a new input connection (the web engine ignores TextInput.show mid-edit)', (tester) async {
    await _openBoard(tester);
    final field = find.byKey(const Key('board-text'));
    const typed = 'من يجي معي للحرم الجمعة؟';
    for (final where in ['padding', 'field']) {
      await _keyboardUp(tester);
      await tester.enterText(field, typed);
      await tester.pumpAndSettle();
      expect(_rowsShown(), isFalse);
      // زر الرجوع: تنزل اللوحة دون أن يُلغى التركيز
      await _keyboardDown(tester);
      expect(_editable(tester).widget.focusNode.hasFocus, isFalse, reason: 'انتهى التحرير مع نزول اللوحة');
      expect(_rowsShown(), isTrue);
      expect(_editable(tester).widget.controller.text, typed);
      final card = tester.getRect(find.byKey(const Key('board-card')));
      final box = tester.getRect(field);
      // الحقل يملأ داخل البطاقة (هدف النقر) والنص في وسطه رأسياً؛ مستطيل البطاقة يشمل هامشها 8 أعلى وأسفل وحشوتها 24
      expect(box.width, closeTo(card.width * .85 + 3, .5));
      expect(box.height, closeTo(card.height - 16 - 48, .5));
      expect(_globalRect(_editable(tester).renderEditable).center.dy, closeTo(box.center.dy, 1));
      tester.testTextInput.log.clear();
      // حشوة البطاقة العليا، أو داخل الحقل بعيداً عن سطر النص
      await tester.tapAt(where == 'padding' ? Offset(card.center.dx, card.top + 8 + 12) : Offset(card.center.dx, box.top + 8));
      await tester.pump();
      expect(_editable(tester).widget.focusNode.hasFocus, isTrue, reason: where);
      expect(tester.testTextInput.log.map((c) => c.method), containsAllInOrder(['TextInput.setClient', 'TextInput.show']), reason: 'اتصال جديد يعيد لوحة المفاتيح على الويب أيضاً ($where)');
    }
  });

  testWidgets('a tablet shortcut bar is not a keyboard; typing needs focus and a real keyboard, and ends only once it is down (hysteresis)', (tester) async {
    const ipad = Size(820, 1180);
    await _openBoard(tester, screen: ipad);
    expect(_editable(tester).widget.focusNode.hasFocus, isTrue);
    final closed = tester.getRect(find.byKey(const Key('board-card')));
    // شريط اختصارات iPadOS مع لوحة مفاتيح خارجية
    tester.view.viewInsets = const FakeViewPadding(bottom: 55);
    await tester.pumpAndSettle();
    expect(_rowsShown(), isTrue, reason: 'الصفوف تبقى مع شريط الاختصارات');
    expect(find.byKey(const Key('board-done')), findsNothing);
    final card = tester.getRect(find.byKey(const Key('board-card')));
    expect(card.width / card.height, closeTo(9 / 16, .02), reason: 'البطاقة بنسبتها لا بعرض الشاشة');
    expect(card.width, lessThan(closed.width));
    expect(card.bottom, lessThanOrEqualTo(ipad.height - 55), reason: 'وفوق الشريط');
    // لوحة مفاتيح حقيقية
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(_rowsShown(), isFalse);
    // اللوحة تنزل (بعد «تم»): الهيئة تبقى حتى تنزل تحت 60 فعلاً بدل أن تعود الصفوف فوق لوحة ما زالت ظاهرة
    await tester.tap(find.byKey(const Key('board-done')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 100);
    await tester.pumpAndSettle();
    expect(_rowsShown(), isFalse, reason: 'تخلّف: 100 ما زالت لوحة مفاتيح تنزل');
    tester.view.viewInsets = const FakeViewPadding(bottom: 50);
    await tester.pumpAndSettle();
    expect(_rowsShown(), isTrue);
    // إزاحة كبيرة بلا تركيز ليست كتابة في لوحتنا
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(_editable(tester).widget.focusNode.hasFocus, isFalse);
    expect(_rowsShown(), isTrue);
  });

  testWidgets('the font is fitted once the keyboard settles, not on every frame of its native animation; a web resize fits at once', (tester) async {
    await _openBoard(tester);
    await tester.enterText(find.byKey(const Key('board-text')), _long);
    await tester.pumpAndSettle();
    final f0 = _boardFont(tester);
    // iOS وأندرويد الأصليان: إزاحة جديدة في كل إطار (16 م.ث)
    final fonts = <double>[];
    for (final v in const <double>[12, 41, 50, 80, 120, 200, 260, 300, 336]) {
      tester.view.viewInsets = FakeViewPadding(bottom: v);
      await tester.pump(const Duration(milliseconds: 16));
      fonts.add(_boardFont(tester));
    }
    expect(_rowsShown(), isFalse, reason: 'هيئة الكتابة بدأت في منتصف الحركة');
    expect(fonts.toSet(), {f0}, reason: 'الخط ثابت والأسطر لا تتحرك أثناء صعود اللوحة');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    final settled = _boardFont(tester);
    expect(settled, isNot(f0), reason: 'يُقاس مرة واحدة بعد أن تهدأ');
    expect(_scroll(tester).maxScrollExtent, 0);
    _expectWholeTextInsideCard(tester, visibleBottom: _screen.height - _keyboard);
    // والنزول كذلك: لا تغيّر حتى تهدأ ثم تعود البطاقة بخط المعاينة
    fonts.clear();
    for (final v in const <double>[300, 200, 120, 59, 20, 0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: v);
      await tester.pump(const Duration(milliseconds: 16));
      fonts.add(_boardFont(tester));
    }
    expect(fonts.toSet(), {settled});
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_boardFont(tester), f0, reason: 'بعد الهدوء: خط البطاقة المغلقة نفسه كما بدأ');
    // سفاري والويب: نقرة تعيد التركيز (نزول اللوحة أنهى التحرير) ثم تغيير حجم واحد بحجم لوحة المفاتيح يُقاس في الإطار نفسه
    expect(_editable(tester).widget.focusNode.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('board-text')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pump();
    expect(_boardFont(tester), settled);
    await tester.pumpAndSettle();
  });

  testWidgets('the viewer never clips a long text post: the font shrinks to fit the canvas like the closed preview', (tester) async {
    final many = List.generate(40, (i) => 'سطر ${i + 1}').join('\n');
    // الهاتف (أطول من ٩:١٦) وسطح المكتب (٩:١٦ بالضبط)
    final ratios = <double>[];
    for (final canvas in const [Size(390, 844), Size(506, 900)]) {
      await _pumpCanvas(tester, canvas, [PostOverlay(type: 'text', text: many, scale: boardTextScale(many), color: '#111111')]);
      final t = _overlayText(tester, many);
      expect(t.exceeded, isFalse);
      expect(t.rect.top, greaterThanOrEqualTo(0), reason: 'أول سطر داخل القماش $canvas');
      expect(t.rect.bottom, lessThanOrEqualTo(canvas.height), reason: 'آخر سطر داخل القماش $canvas');
      expect(t.rect.height, lessThanOrEqualTo(kOverlayTextRoom * canvas.width * 16 / 9 + .5));
      expect(t.size, lessThan(canvas.width * .065 * boardTextScale(many)), reason: 'صغُر الخط');
      ratios.add(t.size / canvas.width);
    }
    // الخط نسبةً إلى العرض واحد على الجهازين (القياس على ٩:١٦)
    expect(ratios[0], closeTo(ratios[1], .5 / 390 + .5 / 506));
    // النص العادي بحجمه كما كان: عرض القماش × 0.065 × المقياس
    await _pumpCanvas(tester, const Size(390, 844), [const PostOverlay(type: 'text', text: 'من يجي معي للحرم الجمعة؟', scale: 1.5, color: '#111111')]);
    expect(_overlayText(tester, 'من يجي معي للحرم الجمعة؟').size, closeTo(390 * .065 * 1.5, 1e-9));

    // معاينة اللوحة بلا لوحة مفاتيح بالخط نفسه نسبةً إلى عرض البطاقة، فلا يُقصّ بعد النشر ما ظهر قبله
    await _openBoard(tester);
    await tester.enterText(find.byKey(const Key('board-text')), many);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const Key('board-card')));
    expect(_boardFont(tester) / card.width, closeTo(ratios[0], .5 / card.width + .5 / 390));
    expect(_scroll(tester).maxScrollExtent, 0, reason: 'المعاينة تعرض النص كله كما سيظهر');
    _expectWholeTextInsideCard(tester, visibleBottom: _screen.height);
  });

  testWidgets('EditPage keeps a long board text when it is edited again (no 140-character cut, new lines allowed)', (tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = '${_long.substring(0, 200)}\n${_long.substring(0, 49)}';
    expect(long.length, 250);
    final draft = ComposerDraft(lat: 21.5, lng: 39.2, kind: 'text', overlays: [PostOverlay(type: 'text', text: long, scale: boardTextScale(long), color: '#111111')]);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => EditPage(draft: draft))), child: const Text('open'))))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final shown = _overlayText(tester, long).size;
    // نقرتان على الطبقة تفتحان تعديلها
    final layer = find.byKey(const ValueKey('ov0'));
    await tester.tap(layer);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(layer);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('inline-text')));
    expect(field.maxLength, kBoardMaxChars);
    expect(field.textInputAction, TextInputAction.newline);
    expect(field.style!.fontSize, shown, reason: 'حقل التعديل بخط الطبقة نفسه فلا يقفز عند «تم»');
    // حرف واحد بعد النص: كان الحد 140 يقصّ الباقي
    await tester.enterText(find.byKey(const Key('inline-text')), '$longا');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tray-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-next')));
    await tester.pumpAndSettle();
    expect(draft.overlays.single.text, '$longا');
  });
}
