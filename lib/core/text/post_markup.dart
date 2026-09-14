// تنسيق خفيف لمنشورات الدوائر (على غرار ماركداون مبسّط) يُحفظ نصاً عادياً في الخادم ويُعرض منسّقاً في التطبيق:
//   # عنوان        ## عنوان فرعي      - نقطة        1. ترقيم       > اقتباس       ---  فاصل
//   **عريض**       [نص](https://رابط)  والروابط تُكتشف تلقائياً.
// أي تطبيق آخر (أو نسخة قديمة) يعرض النص كما هو فيبقى مقروءاً.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';

enum BlockKind { h1, h2, bullet, number, quote, divider, paragraph }

/// كتلة واحدة من المنشور بعد التحليل.
class MarkupBlock {
  final BlockKind kind;
  final String text;
  /// رقم البند للقوائم المرقّمة.
  final int number;
  const MarkupBlock(this.kind, this.text, {this.number = 0});
  @override
  bool operator ==(Object other) => other is MarkupBlock && other.kind == kind && other.text == text && other.number == number;
  @override
  int get hashCode => Object.hash(kind, text, number);
  @override
  String toString() => 'MarkupBlock($kind, "$text"${number > 0 ? ', $number' : ''})';
}

final _numbered = RegExp(r'^\s*([0-9٠-٩]{1,3})[.)]\s+(.*)$');
final _bullet = RegExp(r'^\s*[-•*]\s+(.*)$');
final _h1 = RegExp(r'^\s*#\s+(.*)$');
final _h2 = RegExp(r'^\s*##\s+(.*)$');
final _quote = RegExp(r'^\s*>\s?(.*)$');
final _divider = RegExp(r'^\s*(-{3,}|_{3,}|\*{3,})\s*$');

/// يحوّل النص إلى كتل: الأسطر المتتالية العادية تُدمج في فقرة واحدة (بأسطرها)، والسطر الفارغ يفصل الفقرات.
List<MarkupBlock> parsePostMarkup(String text) {
  final out = <MarkupBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    out.add(MarkupBlock(BlockKind.paragraph, para.join('\n')));
    para.clear();
  }

  var counter = 0;
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
      counter = 0;
      continue;
    }
    RegExpMatch? m;
    if ((m = _h2.firstMatch(line)) != null) {
      flush();
      counter = 0;
      out.add(MarkupBlock(BlockKind.h2, m!.group(1)!.trim()));
    } else if ((m = _h1.firstMatch(line)) != null) {
      flush();
      counter = 0;
      out.add(MarkupBlock(BlockKind.h1, m!.group(1)!.trim()));
    } else if (_divider.hasMatch(line)) {
      flush();
      counter = 0;
      out.add(const MarkupBlock(BlockKind.divider, ''));
    } else if ((m = _numbered.firstMatch(line)) != null) {
      flush();
      counter += 1;
      out.add(MarkupBlock(BlockKind.number, m!.group(2)!.trim(), number: counter));
    } else if ((m = _bullet.firstMatch(line)) != null) {
      flush();
      counter = 0;
      out.add(MarkupBlock(BlockKind.bullet, m!.group(1)!.trim()));
    } else if ((m = _quote.firstMatch(line)) != null) {
      flush();
      counter = 0;
      out.add(MarkupBlock(BlockKind.quote, m!.group(1)!.trim()));
    } else {
      counter = 0;
      para.add(line.trim());
    }
  }
  flush();
  return out;
}

/// نص خالٍ من علامات التنسيق للمعاينات والإشعارات: العنوان ثم أول سطر.
String plainPostText(String text, {int maxChars = 140}) {
  final blocks = parsePostMarkup(text);
  final buf = StringBuffer();
  for (final b in blocks) {
    if (b.kind == BlockKind.divider) continue;
    final t = _stripInline(b.text).replaceAll('\n', ' ');
    if (buf.isNotEmpty) buf.write(' · ');
    buf.write(b.kind == BlockKind.number ? '${b.number}. $t' : t);
    if (buf.length >= maxChars) break;
  }
  final s = buf.toString();
  return s.length > maxChars ? '${s.substring(0, maxChars).trimRight()}…' : s;
}

/// عنوان المنشور إن بدأ بسطر `#`، وإلا لا شيء.
String? postTitle(String text) {
  final blocks = parsePostMarkup(text);
  return blocks.isNotEmpty && blocks.first.kind == BlockKind.h1 ? blocks.first.text : null;
}

final _inline = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\((https?://[^\s)]+)\)|(https?://[^\s<>()\[\]]+)');
String _stripInline(String s) => s.replaceAllMapped(_inline, (m) => m.group(1) ?? m.group(2) ?? m.group(4) ?? '');

/// أجزاء السطر: عريض، رابط بعنوان، رابط خام، أو نص عادي.
List<InlineSpan> inlineSpans(String text, TextStyle base, {Color linkColor = Joy.primary, List<GestureRecognizer>? recognizers}) {
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w800)));
    } else {
      final label = m.group(2) ?? m.group(4)!;
      final url = m.group(3) ?? m.group(4)!;
      final rec = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      recognizers?.add(rec);
      spans.add(TextSpan(text: label, style: base.copyWith(color: linkColor, decoration: TextDecoration.underline, fontWeight: FontWeight.w600), recognizer: rec));
    }
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}

/// يعرض منشوراً منسّقاً. مع [collapsed] تُعرض أول الكتل فقط مع زر «اقرأ المزيد» عندما يطول المنشور.
class PostMarkup extends StatefulWidget {
  final String text;
  final bool collapsed;
  final VoidCallback? onMore;
  final double fontSize;
  final bool selectable;
  const PostMarkup(this.text, {super.key, this.collapsed = false, this.onMore, this.fontSize = 15, this.selectable = false});

  /// حدود الطيّ: عدد الكتل أو عدد الحروف.
  static const collapseBlocks = 6;
  static const collapseChars = 420;

  @override
  State<PostMarkup> createState() => _PostMarkupState();
}

class _PostMarkupState extends State<PostMarkup> {
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final blocks = parsePostMarkup(widget.text);
    var shown = blocks;
    var truncated = false;
    if (widget.collapsed) {
      var chars = 0;
      final take = <MarkupBlock>[];
      for (final b in blocks) {
        if (take.length >= PostMarkup.collapseBlocks || chars > PostMarkup.collapseChars) {
          truncated = true;
          break;
        }
        take.add(b);
        chars += b.text.length;
      }
      shown = take;
    }
    final base = TextStyle(fontSize: widget.fontSize, height: 1.65, color: Joy.text, fontWeight: FontWeight.w500);
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final b = shown[i];
      final gap = i == 0 ? 0.0 : (b.kind == BlockKind.bullet || b.kind == BlockKind.number) && (shown[i - 1].kind == b.kind) ? 3.0 : 9.0;
      children.add(Padding(padding: EdgeInsets.only(top: gap), child: _block(b, base)));
    }
    if (truncated) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          key: const Key('post-more'),
          onTap: widget.onMore,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('اقرأ المزيد…', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: widget.fontSize - 1)),
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _text(String s, TextStyle style) {
    final span = TextSpan(style: style, children: inlineSpans(s, style, recognizers: _recognizers));
    return widget.selectable ? SelectableText.rich(span) : Text.rich(span);
  }

  Widget _block(MarkupBlock b, TextStyle base) {
    switch (b.kind) {
      case BlockKind.h1:
        return _text(b.text, base.copyWith(fontFamily: AppTheme.displayFont, fontSize: widget.fontSize + 6, fontWeight: FontWeight.w700, height: 1.35));
      case BlockKind.h2:
        return _text(b.text, base.copyWith(fontSize: widget.fontSize + 2, fontWeight: FontWeight.w800, height: 1.4));
      case BlockKind.bullet:
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(top: widget.fontSize * .55, left: 10, right: 4), child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Joy.primary, shape: BoxShape.circle))),
          Expanded(child: _text(b.text, base)),
        ]);
      case BlockKind.number:
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 24, child: Text('${b.number}.', style: base.copyWith(color: Joy.primary, fontWeight: FontWeight.w800))),
          Expanded(child: _text(b.text, base)),
        ]);
      case BlockKind.quote:
        return Container(
          padding: const EdgeInsetsDirectional.only(start: 12, top: 2, bottom: 2),
          decoration: const BoxDecoration(border: BorderDirectional(start: BorderSide(color: Joy.primary, width: 3))),
          child: _text(b.text, base.copyWith(color: Joy.textMuted)),
        );
      case BlockKind.divider:
        return const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1));
      case BlockKind.paragraph:
        return _text(b.text, base);
    }
  }
}
