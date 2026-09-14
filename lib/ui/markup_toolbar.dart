// شريط تنسيق مشترك لحقول النص الطويل (منشورات الدوائر ومدونة الإدارة): عريض، عناوين، نقاط، ترقيم، اقتباس، رابط،
// فاصل، وزر مساعدة يشرح العلامات. يعمل على أي TextEditingController عبر عمليات MarkupEdit النقية.
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/text/markup_edit.dart';

class MarkupToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  /// عنصر في نهاية الشريط (عدّاد الحروف وحالة المسودة مثلاً).
  final Widget? trailing;
  /// أدوات إضافية بعد أدوات التنسيق (مثل إدراج صورة).
  final List<Widget> extra;
  const MarkupToolbar({super.key, required this.controller, required this.focusNode, this.enabled = true, this.trailing, this.extra = const []});

  void _apply(TextEditingValue Function(TextEditingValue) f) {
    controller.value = f(controller.value);
    focusNode.requestFocus();
  }

  Future<void> _link(BuildContext context) async {
    final sel = controller.selection;
    final selected = sel.isValid && !sel.isCollapsed ? controller.text.substring(sel.start, sel.end) : '';
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

  static void showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('تنسيق النص', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('اكتب بحرية، أو استخدم أزرار الشريط. العلامات نفسها يمكن كتابتها يدوياً:', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            for (final (code, meaning) in const [('# عنوان', 'عنوان رئيسي'), ('## عنوان', 'عنوان فرعي'), ('**نص**', 'نص عريض'), ('- بند', 'قائمة نقطية'), ('1. بند', 'قائمة مرقّمة'), ('> نص', 'اقتباس'), ('---', 'فاصل'), ('[نص](https://…)', 'رابط بعنوان'), ('![وصف](https://…)', 'صورة برابط')])
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
    final tools = <(String, IconData, String, VoidCallback)>[
      ('bold', Icons.format_bold_rounded, 'عريض', () => _apply((v) => MarkupEdit.wrap(v, '**'))),
      ('h1', Icons.title_rounded, 'عنوان', () => _apply((v) => MarkupEdit.prefixLines(v, '# '))),
      ('h2', Icons.text_fields_rounded, 'عنوان فرعي', () => _apply((v) => MarkupEdit.prefixLines(v, '## '))),
      ('bullet', Icons.format_list_bulleted_rounded, 'نقاط', () => _apply((v) => MarkupEdit.prefixLines(v, '- '))),
      ('number', Icons.format_list_numbered_rounded, 'ترقيم', () => _apply((v) => MarkupEdit.prefixLines(v, '', numbered: true))),
      ('quote', Icons.format_quote_rounded, 'اقتباس', () => _apply((v) => MarkupEdit.prefixLines(v, '> '))),
      ('link', Icons.link_rounded, 'رابط', () => _link(context)),
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
                  IconButton(key: Key('tool-$id'), tooltip: tip, icon: Icon(icon), color: Joy.text, onPressed: enabled ? fn : null, visualDensity: VisualDensity.compact),
                ...extra,
                IconButton(key: const Key('editor-help'), tooltip: 'كيف أنسّق؟', icon: const Icon(Icons.help_outline_rounded), color: Joy.textMuted, onPressed: () => showHelp(context), visualDensity: VisualDensity.compact),
              ]),
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsetsDirectional.only(start: 6, end: 4), child: trailing),
        ]),
      ),
    );
  }
}
