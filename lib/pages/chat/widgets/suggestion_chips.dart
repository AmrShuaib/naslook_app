// ردود مقترحة فوق حقل الكتابة: بعد 600 مللي ثانية من آخر رسالة واردة تُطلب ثلاث جمل قصيرة من POST /chat/suggest
// (server/chat_live.js: Claude بمفتاح صندوق البريد أو قواعد محلية) وتُعرض رقائق؛ تختفي حين تكون آخر رسالة لي أو لا اقتراح.
// الضغط على رقاقة يسلّم نصها إلى onPick (صفحة المحادثة تضعه في الحقل).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/chat_live_api.dart';
import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';

class SuggestionChips extends ConsumerStatefulWidget {
  final String peerId;
  /// رسائل المحادثة بترتيب زمني (الأقدم أولاً)؛ تُؤخذ الثماني الأخيرة.
  final List<Message> messages;
  final void Function(String text) onPick;
  /// مهلة الهدوء بعد آخر رسالة واردة قبل الطلب.
  static const debounce = Duration(milliseconds: 600);
  const SuggestionChips({super.key, required this.peerId, required this.messages, required this.onPick});
  @override
  ConsumerState<SuggestionChips> createState() => _SuggestionChipsState();
}

class _SuggestionChipsState extends ConsumerState<SuggestionChips> {
  List<String> _items = const [];
  String? _lastKey;
  Timer? _debounce;
  int _gen = 0;

  @override
  void initState() { super.initState(); _schedule(); }
  @override
  void didUpdateWidget(SuggestionChips old) { super.didUpdateWidget(old); _schedule(); }
  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }

  String get _myId => ref.read(appStateProvider).user?.id ?? '';
  bool _mine(Message m) => m.isMine(myId: _myId, peerId: widget.peerId);

  void _schedule() {
    final msgs = widget.messages;
    final last = msgs.isEmpty ? null : msgs.last;
    // لا اقتراح بلا رسائل أو حين تكون آخر رسالة لي (أنا من يتكلّم الآن)
    if (last == null || _mine(last)) {
      _debounce?.cancel();
      _lastKey = null;
      if (_items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    if (last.key == _lastKey) return;
    _lastKey = last.key;
    _debounce?.cancel();
    final gen = ++_gen;
    _debounce = Timer(SuggestionChips.debounce, () => _fetch(gen));
  }

  Future<void> _fetch(int gen) async {
    final msgs = widget.messages;
    final turns = <SuggestTurn>[for (final m in msgs.length > 8 ? msgs.sublist(msgs.length - 8) : msgs) (mine: _mine(m), text: m.mediaKind == 'text' ? m.content : m.preview)];
    try {
      final r = await ref.read(apiClientProvider).suggestReplies(widget.peerId, turns);
      if (!mounted || gen != _gen) return;
      setState(() => _items = r.suggestions);
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('suggestion-chips'),
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            ActionChip(
              key: Key('suggest-chip-$i'),
              avatar: i == 0 ? const Icon(Icons.auto_awesome_rounded, size: 15, color: Joy.primary) : null,
              label: Text(_items[i], style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Joy.primary)),
              backgroundColor: Joy.primarySoft,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              onPressed: () { final t = _items[i]; setState(() => _items = const []); widget.onPick(t); },
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
