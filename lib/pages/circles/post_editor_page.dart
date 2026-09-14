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
import '../../core/text/markup_edit.dart';
import '../../core/text/post_markup.dart';
import '../../ui/markup_toolbar.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

export '../../core/text/markup_edit.dart' show MarkupEdit;

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

  Widget _toolbar(int chars) => MarkupToolbar(
        controller: _body,
        focusNode: _bodyFocus,
        enabled: !_preview,
        trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$chars حرف', style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
          if (_draftState.isNotEmpty) Text(_draftState, key: const Key('editor-draft-state'), style: const TextStyle(fontSize: 10.5, color: Joy.success, fontWeight: FontWeight.w600)),
        ]),
      );
}
