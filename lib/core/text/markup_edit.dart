// عمليات تحرير نقية على قيمة حقل نصي بعلامات التنسيق الخفيف (تشاركها منشورات الدوائر ومحرر المدونة).
import 'package:flutter/material.dart';

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
