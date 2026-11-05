// لوحة «نص» في المحرّر مع لوحة المفاتيح: البطاقة تأخذ المساحة الظاهرة فوقها، صفوف القوالب والألوان والأنماط تختفي
// أثناء الكتابة وتعود بعدها، والخط يصغر ليظهر النص الطويل كاملاً ثم يمرّر داخل البطاقة مع بقاء المؤشر ظاهراً.
// المقاسات بمقاس آيفون (390×844) ولوحة مفاتيح سفاري (336) كما في لقطات المالك.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/pages/posts/composer/capture_page.dart';
import 'package:naslook/pages/posts/composer/composer_draft.dart';
import 'package:naslook/pages/posts/composer/text_board.dart';

const _screen = Size(390, 844);
const _keyboard = 336.0;

/// نص عربي طويل (≈٢٤٠ حرفاً) كالذي قُصّ في لقطة المالك
const _long = 'اللهم إنا نسألك رضاك والجنة ونعوذ بك من سخطك والنار، اللهم اغفر لنا ذنوبنا وكفّر عنا سيئاتنا وتوفنا مع الأبرار، '
    'سبحان الله والحمد لله ولا إله إلا الله والله أكبر ولا حول ولا قوة إلا بالله العلي العظيم، وصلى الله على نبينا محمد';

/// يفتح شاشة الالتقاط من زر ثم ينتقل إلى نمط «نص»؛ يعيد دالة تقرأ المسودة التي أعادتها الشاشة عند «التالي»
Future<ComposerDraft? Function()> _openBoard(WidgetTester tester, {FakeViewPadding padding = FakeViewPadding.zero}) async {
  tester.view.physicalSize = _screen;
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
}
