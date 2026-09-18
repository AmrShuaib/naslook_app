import 'package:flutter/material.dart';

import '../../../api/posts_api.dart';
import '../../../core/app_theme.dart';
import '../overlay_canvas.dart';
import 'composer_draft.dart';
import 'voice_layer.dart';

/// لون نص مقروء على لوحة بلون معيّن: أسود على الفاتح وأبيض على الداكن.
String contrastTextColor(String? boardHex) => colorFromHex(boardHex, Colors.white).computeLuminance() > .5 ? '#111111' : '#FFFFFF';

/// نمط «نص»: لوحة ملونة تكتب عليها مباشرة، مع قالب (عادي، سؤال، تنبيه، اقتباس) وخمسة ألوان وزر صوت.
/// النص المكتوب يصبح طبقة نصية في المنشور حتى يعرضها العارض كما هي.
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
  late String board = widget.draft.board;
  late String template = widget.draft.template;
  late VoiceLayer? voice = widget.draft.voice;

  @override
  void dispose() {
    text.dispose();
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

  void _next() {
    final body = text.text.trim();
    if (body.isEmpty && voice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب شيئاً أو أضف تسجيلاً صوتياً')));
      return;
    }
    final t = boardTemplates.firstWhere((x) => x.id == template);
    final color = contrastTextColor(board);
    final overlays = <PostOverlay>[
      if (t.badge.isNotEmpty) PostOverlay(type: 'text', text: t.badge, x: .5, y: .18, scale: .8, color: '#FFFFFF', bg: '#0A6E78', font: 'badge'),
      if (body.isNotEmpty) PostOverlay(type: 'text', text: body, x: .5, y: .5, scale: body.length > 80 ? 1.15 : 1.5, color: color, font: template == 'quote' ? 'serif' : 'bold'),
    ];
    widget.onNext(widget.draft
      ..kind = 'text'
      ..board = board
      ..template = template
      ..overlays = overlays
      ..voice = voice
      ..shots.clear()
      ..video = null);
  }

  @override
  Widget build(BuildContext context) {
    final boardColor = colorFromHex(board, Colors.white);
    final fg = colorFromHex(contrastTextColor(board));
    final t = boardTemplates.firstWhere((x) => x.id == template);
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Material(color: Colors.black38, shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: widget.onClose, child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Colors.white)))),
            const Expanded(child: Center(child: Text('نص', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)))),
            FilledButton(key: const Key('text-next'), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: _next, child: const Text('التالي')),
          ]),
        ),
        Expanded(
          child: Center(
            child: LayoutBuilder(builder: (context, box) {
              final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth - 40);
              return Container(
                width: w, height: box.maxHeight - 16, margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: boardColor, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))]),
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (t.badge.isNotEmpty) Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(999)), child: Text(t.badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                  TextField(
                    key: const Key('board-text'),
                    controller: text, autofocus: true, maxLines: null, maxLength: 280, textAlign: TextAlign.center,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: TextStyle(color: fg, fontSize: 26, height: 1.4, fontWeight: FontWeight.w800, fontFamily: template == 'quote' ? 'serif' : null),
                    cursorColor: fg,
                    decoration: InputDecoration.collapsed(hintText: switch (template) { 'question' => 'اطرح سؤالك على من حولك…', 'alert' => 'ما الذي يجب أن يعرفه الجميع؟', 'quote' => 'اكتب الاقتباس…', _ => 'اكتب هنا…' }, hintStyle: TextStyle(color: fg.withValues(alpha: .4))),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (voice != null) Padding(padding: const EdgeInsets.only(top: 16), child: VoiceChip(layer: voice, light: fg == const Color(0xFF111111))),
                ]),
              );
            }),
          ),
        ),
        // القوالب والألوان والصوت
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
        const SizedBox(height: 22),
      ]),
    );
  }
}
