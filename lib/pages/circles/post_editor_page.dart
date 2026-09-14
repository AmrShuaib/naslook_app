// محرر منشورات الدوائر: صفحة كاملة بعنوان اختياري ونص طويل وشريط تنسيق (عريض، عناوين، نقاط، ترقيم، اقتباس،
// رابط، فاصل) ومعاينة حيّة، ومسودة تُحفظ محلياً تلقائياً فلا يضيع ما كُتب عند الإغلاق أو انقطاع الاتصال.
// التنسيق يُحفظ نصاً عادياً بعلامات بسيطة (انظر core/text/post_markup.dart) فيبقى مقروءاً في أي مكان.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/text/post_markup.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

/// عمليات تحرير نقية على قيمة الحقل (قابلة للاختبار بلا واجهة).
class MarkupEdit {
  /// يلفّ التحديد بالعلامة (مثل `**`)؛ بلا تحديد يدرج العلامتين ويضع المؤشر بينهما؛ وإن كان التحديد ملفوفاً أصلاً أزال اللفّ.
  static TextEditingValue wrap(TextEditingValue v, String marker) {
    final text = v.text;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
    final start = sel.start, end = sel.end;
    if (start == end) {
      final t = text.substring(0, start) + marker + marker + text.substring(end);
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: start + marker.length));
    }
    final selected = text.substring(start, end);
    if (selected.length >= marker.length * 2 && selected.startsWith(marker) && selected.endsWith(marker)) {
      final inner = selected.substring(marker.length, selected.length - marker.length);
      final t = text.substring(0, start) + inner + text.substring(end);
      return TextEditingValue(text: t, selection: TextSelection(baseOffset: start, extentOffset: start + inner.length));
    }
    final t = text.substring(0, start) + marker + selected + marker + text.substring(end);
    return TextEditingValue(text: t, selection: TextSelection(baseOffset: start, extentOffset: end + marker.length * 2));
  }

  /// يضيف بادئة لكل سطر يمسّه التحديد (أو السطر الحالي). إن كانت كل الأسطر تحمل البادئة نفسها أزالها (تبديل).
  /// مع [numbered] تكون البادئة `1. ` `2. ` … بالترتيب.
  static TextEditingValue prefixLines(TextEditingValue v, String prefix, {bool numbered = false}) {
    final text = v.text;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
    final lineStart = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    final nl = text.indexOf('\n', sel.end);
    final lineEnd = nl == -1 ? text.length : nl;
    final segment = text.substring(lineStart, lineEnd);
    final lines = segment.split('\n');
    final numberedRe = RegExp(r'^\s*[0-9]{1,3}[.)]\s+');
    final hasAll = lines.every((l) => numbered ? numberedRe.hasMatch(l) : l.startsWith(prefix));
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (hasAll) {
        out.add(numbered ? l.replaceFirst(numberedRe, '') : l.substring(prefix.length));
      } else {
        final clean = numbered ? l.replaceFirst(numberedRe, '') : l;
        out.add(numbered ? '${i + 1}. $clean' : '$prefix$clean');
      }
    }
    final replaced = out.join('\n');
    final t = text.substring(0, lineStart) + replaced + text.substring(lineEnd);
    // تحديد ممتد يبقى ممتداً على الأسطر نفسها (فضغطة ثانية تعكس العملية)، والمؤشر المفرد يبقى في نهاية سطره
    final selection = sel.isCollapsed ? TextSelection.collapsed(offset: lineStart + replaced.length) : TextSelection(baseOffset: lineStart, extentOffset: lineStart + replaced.length);
    return TextEditingValue(text: t, selection: selection);
  }

  /// يدرج نصاً مكان التحديد ويضع المؤشر بعده (أو عند [cursorAt] من بداية المُدرج).
  static TextEditingValue insert(TextEditingValue v, String s, {int? cursorAt}) {
    final text = v.text;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
    final t = text.substring(0, sel.start) + s + text.substring(sel.end);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + (cursorAt ?? s.length)));
  }

  /// يدرج فاصلاً أفقياً على سطر مستقل.
  static TextEditingValue divider(TextEditingValue v) {
    final text = v.text;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
    final before = text.substring(0, sel.start);
    final needsNl = before.isNotEmpty && !before.endsWith('\n');
    return insert(v, '${needsNl ? '\n' : ''}---\n');
  }

  /// النص النهائي للنشر: العنوان (إن وُجد) سطر `#` ثم النص.
  static String compose({required String title, required String body}) {
    final t = title.trim(), b = body.trim();
    if (t.isEmpty) return b;
    return b.isEmpty ? '# $t' : '# $t\n\n$b';
  }
}

class PostEditorPage extends ConsumerStatefulWidget {
  final String vesselId;
  final String? vesselName;
  /// المالك والمشرفون يمكنهم نشر «إعلان» يُبرز بلون مميز.
  final bool canAnnounce;
  const PostEditorPage({super.key, required this.vesselId, this.vesselName, this.canAnnounce = false});

  static String draftKey(String vesselId) => 'post_draft_$vesselId';

  @override
  ConsumerState<PostEditorPage> createState() => _PostEditorPageState();
}

class _PostEditorPageState extends ConsumerState<PostEditorPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  var _kind = 'discussion';
  var _preview = false;
  var _publishing = false;
  var _draftState = ''; // '' | 'مسودة مستعادة' | 'حُفظت مسودة'
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onEdit);
    _body.addListener(_onEdit);
    _restoreDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _hasContent => _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

  Future<void> _restoreDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(PostEditorPage.draftKey(widget.vesselId));
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map;
      _title.text = (j['title'] ?? '') as String;
      _body.text = (j['body'] ?? '') as String;
      _kind = (j['kind'] ?? 'discussion') as String;
      if (_hasContent) setState(() => _draftState = 'مسودة مستعادة');
    } catch (_) {}
  }

  void _onEdit() {
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = PostEditorPage.draftKey(widget.vesselId);
      if (!_hasContent) {
        await p.remove(key);
        if (mounted) setState(() => _draftState = '');
        return;
      }
      await p.setString(key, jsonEncode({'title': _title.text, 'body': _body.text, 'kind': _kind}));
      if (mounted) setState(() => _draftState = 'حُفظت مسودة');
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(PostEditorPage.draftKey(widget.vesselId));
    } catch (_) {}
  }

  void _apply(TextEditingValue Function(TextEditingValue) f) {
    _body.value = f(_body.value);
    _bodyFocus.requestFocus();
  }

  Future<void> _link() async {
    final sel = _body.selection;
    final selected = sel.isValid && !sel.isCollapsed ? _body.text.substring(sel.start, sel.end) : '';
    final url = TextEditingController(text: 'https://');
    final label = TextEditingController(text: selected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدراج رابط'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('link-url'), controller: url, autofocus: true, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الرابط')),
          const SizedBox(height: 10),
          TextField(key: const Key('link-label'), controller: label, decoration: const InputDecoration(labelText: 'النص الظاهر (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(key: const Key('link-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إدراج')),
        ],
      ),
    );
    final u = url.text.trim();
    if (ok != true || u.isEmpty || u == 'https://') return;
    final l = label.text.trim();
    _apply((v) => MarkupEdit.insert(v, l.isEmpty ? u : '[$l]($u)'));
  }

  Future<void> _publish() async {
    if (!_hasContent || _publishing) return;
    setState(() => _publishing = true);
    try {
      final text = MarkupEdit.compose(title: _title.text, body: _body.text);
      final post = await ref.read(apiClientProvider).createPost(widget.vesselId, text, kind: _kind);
      await _clearDraft();
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  void _close() {
    _draftTimer?.cancel();
    if (_hasContent) {
      _saveDraft();
      toast(context, 'حُفظت مسودتك وستجدها عند العودة');
    }
    Navigator.of(context).pop();
  }

  void _help() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('تنسيق المنشور', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('اكتب بحرية، أو استخدم أزرار الشريط. العلامات نفسها يمكن كتابتها يدوياً:', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            for (final (code, meaning) in const [('# عنوان', 'عنوان رئيسي'), ('## عنوان', 'عنوان فرعي'), ('**نص**', 'نص عريض'), ('- بند', 'قائمة نقطية'), ('1. بند', 'قائمة مرقّمة'), ('> نص', 'اقتباس'), ('---', 'فاصل'), ('[نص](https://…)', 'رابط بعنوان')])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(8)), child: Text(code, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Text(meaning, style: const TextStyle(fontSize: 13.5)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final composed = MarkupEdit.compose(title: _title.text, body: _body.text);
    final chars = _body.text.characters.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(
          leading: IconButton(key: const Key('editor-close'), tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded), onPressed: _close),
          title: Text(widget.vesselName == null ? 'منشور جديد' : 'منشور في ${widget.vesselName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: AppTheme.bodyFont)),
          actions: [
            IconButton(
              key: const Key('editor-preview'),
              tooltip: _preview ? 'عودة للكتابة' : 'معاينة',
              icon: Icon(_preview ? Icons.edit_note_rounded : Icons.visibility_outlined, color: _preview ? Joy.primary : null),
              onPressed: () => setState(() => _preview = !_preview),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: FilledButton(
                key: const Key('editor-publish'),
                style: FilledButton.styleFrom(minimumSize: const Size(72, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
                onPressed: _hasContent && !_publishing ? _publish : null,
                child: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('نشر'),
              ),
            ),
          ],
        ),
        body: Column(children: [
          if (widget.canAnnounce)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(children: [
                for (final (k, label, icon) in const [('discussion', 'تحديث', Icons.article_outlined), ('announcement', 'إعلان', Icons.campaign_outlined)])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      key: Key('kind-$k'),
                      avatar: Icon(icon, size: 18, color: _kind == k ? Joy.primaryOn : Joy.textMuted),
                      label: Text(label, style: TextStyle(color: _kind == k ? Joy.primaryOn : Joy.text)),
                      selected: _kind == k,
                      showCheckmark: false,
                      selectedColor: Joy.primary,
                      onSelected: (_) {
                        setState(() => _kind = k);
                        _onEdit();
                      },
                    ),
                  ),
              ]),
            ),
          Expanded(
            child: _preview
                ? SingleChildScrollView(
                    key: const Key('editor-preview-pane'),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: composed.isEmpty
                        ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا شيء للمعاينة بعد', style: TextStyle(color: Joy.textMuted))))
                        : JoyCard(child: PostMarkup(composed, fontSize: 15.5)),
                  )
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: TextField(
                        key: const Key('editor-title'),
                        controller: _title,
                        autofocus: true,
                        maxLength: 80,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _bodyFocus.requestFocus(),
                        style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 23, fontWeight: FontWeight.w700, height: 1.3),
                        decoration: const InputDecoration(hintText: 'العنوان (اختياري)', hintStyle: TextStyle(fontFamily: AppTheme.displayFont, fontSize: 23, fontWeight: FontWeight.w700, color: Joy.control), filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 6)),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(height: 1)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: TextField(
                          key: const Key('editor-body'),
                          controller: _body,
                          focusNode: _bodyFocus,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(fontSize: 16, height: 1.65, fontWeight: FontWeight.w500),
                          decoration: const InputDecoration(hintText: 'اكتب منشورك هنا…\nاستخدم الشريط بالأسفل للعناوين والنقاط والروابط.', hintStyle: TextStyle(color: Joy.control, fontSize: 16, height: 1.65, fontWeight: FontWeight.w500), filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                        ),
                      ),
                    ),
                  ]),
          ),
          _toolbar(chars),
        ]),
      ),
    );
  }

  Widget _toolbar(int chars) {
    final tools = <(String, IconData, String, VoidCallback)>[
      ('bold', Icons.format_bold_rounded, 'عريض', () => _apply((v) => MarkupEdit.wrap(v, '**'))),
      ('h1', Icons.title_rounded, 'عنوان', () => _apply((v) => MarkupEdit.prefixLines(v, '# '))),
      ('h2', Icons.text_fields_rounded, 'عنوان فرعي', () => _apply((v) => MarkupEdit.prefixLines(v, '## '))),
      ('bullet', Icons.format_list_bulleted_rounded, 'نقاط', () => _apply((v) => MarkupEdit.prefixLines(v, '- '))),
      ('number', Icons.format_list_numbered_rounded, 'ترقيم', () => _apply((v) => MarkupEdit.prefixLines(v, '', numbered: true))),
      ('quote', Icons.format_quote_rounded, 'اقتباس', () => _apply((v) => MarkupEdit.prefixLines(v, '> '))),
      ('link', Icons.link_rounded, 'رابط', _link),
      ('divider', Icons.horizontal_rule_rounded, 'فاصل', () => _apply(MarkupEdit.divider)),
    ];
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('editor-toolbar'),
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (id, icon, tip, fn) in tools)
                  IconButton(key: Key('tool-$id'), tooltip: tip, icon: Icon(icon), color: Joy.text, onPressed: _preview ? null : fn, visualDensity: VisualDensity.compact),
                IconButton(key: const Key('editor-help'), tooltip: 'كيف أنسّق؟', icon: const Icon(Icons.help_outline_rounded), color: Joy.textMuted, onPressed: _help, visualDensity: VisualDensity.compact),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$chars حرف', style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
              if (_draftState.isNotEmpty) Text(_draftState, key: const Key('editor-draft-state'), style: const TextStyle(fontSize: 10.5, color: Joy.success, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}
