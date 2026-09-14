// محرر منشورات الدوائر وتنسيقها: تحليل العلامات، عمليات التحرير النقية، صفحة المحرر (شريط الأدوات، المعاينة، المسودة،
// النشر)، ورقة إنشاء الدائرة، وطيّ المنشورات الطويلة في الرئيسية.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/text/post_markup.dart';
import 'package:naslook/pages/circles/circles_page.dart';
import 'package:naslook/pages/circles/post_editor_page.dart';
import 'package:naslook/pages/home/home_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

TextEditingValue _v(String text, [int? start, int? end]) => TextEditingValue(text: text, selection: start == null ? TextSelection.collapsed(offset: text.length) : TextSelection(baseOffset: start, extentOffset: end ?? start));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parsePostMarkup', () {
    test('splits headings, lists, quotes, dividers and paragraphs', () {
      final blocks = parsePostMarkup('# تحديث 1\n\nأول سطر\nثاني سطر\n\n- نقطة أ\n- نقطة ب\n\n1. أول\n2) ثاني\n\n> اقتباس\n---\n## فرعي');
      expect(blocks, [
        const MarkupBlock(BlockKind.h1, 'تحديث 1'),
        const MarkupBlock(BlockKind.paragraph, 'أول سطر\nثاني سطر'),
        const MarkupBlock(BlockKind.bullet, 'نقطة أ'),
        const MarkupBlock(BlockKind.bullet, 'نقطة ب'),
        const MarkupBlock(BlockKind.number, 'أول', number: 1),
        const MarkupBlock(BlockKind.number, 'ثاني', number: 2),
        const MarkupBlock(BlockKind.quote, 'اقتباس'),
        const MarkupBlock(BlockKind.divider, ''),
        const MarkupBlock(BlockKind.h2, 'فرعي'),
      ]);
      expect(postTitle('# عنوان\nنص'), 'عنوان');
      expect(postTitle('نص بلا عنوان'), isNull);
      expect(plainPostText('# عنوان\n\n**عريض** و[رابط](https://naslife.app)\n- بند'), 'عنوان · عريض ورابط · بند');
    });

    test('inline spans: bold, labelled links and bare urls', () {
      final spans = inlineSpans('نص **مهم** انظر https://naslife.app/c/x و[الدليل](https://naslife.app/g)', const TextStyle());
      expect(spans.length, 6);
      expect((spans[1] as TextSpan).text, 'مهم');
      expect((spans[1] as TextSpan).style!.fontWeight, FontWeight.w800);
      expect((spans[3] as TextSpan).text, 'https://naslife.app/c/x');
      expect((spans[3] as TextSpan).recognizer, isNotNull);
      expect((spans[5] as TextSpan).text, 'الدليل');
    });
  });

  group('MarkupEdit', () {
    test('wrap inserts markers, wraps a selection and unwraps it again', () {
      final empty = MarkupEdit.wrap(_v('نص '), '**');
      expect(empty.text, 'نص ****');
      expect(empty.selection.baseOffset, 5);
      final wrapped = MarkupEdit.wrap(_v('كلمة مهمة هنا', 5, 9), '**');
      expect(wrapped.text, 'كلمة **مهمة** هنا');
      expect(wrapped.selection.start, 5);
      expect(wrapped.selection.end, 13);
      final unwrapped = MarkupEdit.wrap(wrapped, '**');
      expect(unwrapped.text, 'كلمة مهمة هنا');
    });

    test('prefixLines toggles bullets on the current line and numbers a multi-line selection', () {
      final b = MarkupEdit.prefixLines(_v('أول\nثاني', 6), '- ');
      expect(b.text, 'أول\n- ثاني');
      expect(MarkupEdit.prefixLines(b, '- ').text, 'أول\nثاني', reason: 'التبديل يزيل البادئة');
      final n = MarkupEdit.prefixLines(_v('أ\nب\nج', 0, 5), '', numbered: true);
      expect(n.text, '1. أ\n2. ب\n3. ج');
      expect(MarkupEdit.prefixLines(n, '', numbered: true).text, 'أ\nب\nج');
      expect(MarkupEdit.divider(_v('نص')).text, 'نص\n---\n');
      expect(MarkupEdit.compose(title: ' عنوان ', body: 'نص'), '# عنوان\n\nنص');
      expect(MarkupEdit.compose(title: '', body: 'نص'), 'نص');
      expect(MarkupEdit.compose(title: 'فقط', body: ''), '# فقط');
    });
  });

  group('PostEditorPage', () {
    Map<String, dynamic>? posted;
    Future<http.Response> handle(http.Request req) async {
      final key = '${req.method} ${req.url.path}';
      if (key == 'POST /vessels/v1/posts') {
        posted = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'id': 'p9', 'vesselId': 'v1', 'type': 'text', 'content': posted!['content'], 'caption': '', 'kind': posted!['kind'], 'author': {'id': 'SA0000001', 'nickname': 'amr'}, 'createdAt': DateTime.now().toIso8601String(), 'supports': 0, 'comments': 0});
      }
      if (req.method == 'GET') return _json([]);
      return _json({'ok': true});
    }

    Future<Post?> pump(WidgetTester tester, {bool canAnnounce = true}) async {
      posted = null;
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(handle));
      Post? result;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          socketProvider.overrideWithValue(null),
          appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
          notifyPollIntervalProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: FilledButton(
            key: const Key('open'),
            onPressed: () async => result = await Navigator.of(ctx).push<Post>(MaterialPageRoute(builder: (_) => PostEditorPage(vesselId: 'v1', vesselName: 'ناس لايف', canAnnounce: canAnnounce))),
            child: const Text('افتح'),
          )))),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('toolbar formats the body, preview renders it, and publishing sends title + body + kind', (tester) async {
      await pump(tester);
      expect(find.text('منشور في ناس لايف'), findsOneWidget);
      final publish = tester.widget<FilledButton>(find.byKey(const Key('editor-publish')));
      expect(publish.onPressed, isNull, reason: 'لا نشر بلا محتوى');
      await tester.enterText(find.byKey(const Key('editor-title')), 'تحديث اليوم');
      await tester.enterText(find.byKey(const Key('editor-body')), 'أول بند\nثاني بند');
      await tester.pump();
      // ترقيم السطر الحالي (المؤشر في النهاية → السطر الثاني)
      await tester.tap(find.byKey(const Key('tool-bullet')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('editor-body'))).controller!.text, 'أول بند\n- ثاني بند');
      await tester.tap(find.byKey(const Key('tool-divider')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('editor-body'))).controller!.text, 'أول بند\n- ثاني بند\n---\n');
      await tester.tap(find.byKey(const Key('kind-announcement')));
      await tester.pump();
      // المعاينة تُظهر العنوان والنقطة
      await tester.tap(find.byKey(const Key('editor-preview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-preview-pane')), findsOneWidget);
      expect(find.text('تحديث اليوم'), findsOneWidget);
      expect(find.text('ثاني بند'), findsOneWidget);
      expect(find.byType(Divider), findsWidgets);
      await tester.tap(find.byKey(const Key('editor-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-publish')));
      await tester.pumpAndSettle();
      expect(posted, isNotNull);
      expect(posted!['content'], '# تحديث اليوم\n\nأول بند\n- ثاني بند\n---');
      expect(posted!['kind'], 'announcement');
      expect(find.byKey(const Key('editor-body')), findsNothing, reason: 'أُغلق المحرر بعد النشر');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PostEditorPage.draftKey('v1')), isNull, reason: 'المسودة تُمسح بعد النشر');
    });

    testWidgets('draft is saved on close and restored on reopen', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('editor-body')), 'نص لم يُنشر');
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(const Key('editor-draft-state')), findsOneWidget);
      await tester.tap(find.byKey(const Key('editor-close')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(PostEditorPage.draftKey('v1'))!)['body'], 'نص لم يُنشر');
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('editor-body'))).controller!.text, 'نص لم يُنشر');
      expect(find.text('مسودة مستعادة'), findsOneWidget);
    });

    testWidgets('link dialog inserts a labelled link', (tester) async {
      await pump(tester, canAnnounce: false);
      expect(find.byKey(const Key('kind-announcement')), findsNothing);
      await tester.tap(find.byKey(const Key('tool-link')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('link-url')), 'https://naslife.app');
      await tester.enterText(find.byKey(const Key('link-label')), 'الموقع');
      await tester.tap(find.byKey(const Key('link-ok')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('editor-body'))).controller!.text, '[الموقع](https://naslife.app)');
    });
  });

  testWidgets('create-circle sheet requires a name and returns the chosen visibility', (tester) async {
    NewCircle? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: FilledButton(key: const Key('open'), onPressed: () async => result = await showCreateCircleSheet(ctx), child: const Text('افتح'))))),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('circle-create'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('circle-name')), 'ناس لايف · التحديثات');
    await tester.enterText(find.byKey(const Key('circle-topic')), 'كل جديد في التطبيق');
    await tester.tap(find.byKey(const Key('circle-private')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('circle-create')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.name, 'ناس لايف · التحديثات');
    expect(result!.topic, 'كل جديد في التطبيق');
    expect(result!.isPublic, isFalse);
  });

  testWidgets('feed card collapses a long formatted post with a read-more link', (tester) async {
    final long = '# عنوان\n\n${List.generate(10, (i) => '- بند رقم $i').join('\n')}';
    final post = Post(id: 'p', vesselId: 'v', vesselName: 'د', author: const Person(id: 'SA0000002', nickname: 'sara'), type: 'text', content: long, caption: '', kind: 'discussion', comments: 0, supports: 0, supported: false, unread: false, createdAt: DateTime.now());
    await tester.pumpWidget(ProviderScope(child: MaterialApp(locale: const Locale('ar'), home: Scaffold(body: ListView(children: [PostCard(post)])))));
    await tester.pump();
    expect(find.text('عنوان'), findsOneWidget);
    expect(find.byKey(const Key('post-more')), findsOneWidget);
    expect(find.text('بند رقم 9'), findsNothing);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(locale: const Locale('ar'), home: Scaffold(body: ListView(children: [PostCard(post, showVessel: false)])))));
    await tester.pump();
    expect(find.byKey(const Key('post-more')), findsNothing);
    expect(find.text('بند رقم 9'), findsOneWidget);
  });
}
