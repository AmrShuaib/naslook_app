import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

class ChatThreadPage extends ConsumerStatefulWidget {
  final Person peer;
  const ChatThreadPage({super.key, required this.peer});
  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  Object? _error;
  bool _peerTyping = false;
  bool _online = false;
  StreamSubscription? _sub;
  Timer? _typingTimer, _presenceTimer;

  String get myId => ref.read(appStateProvider).user?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    final s = ref.read(socketProvider);
    _sub = s?.events.listen(_onEvent);
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) => _presence());
    _presence();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _presence() async {
    try {
      final p = await ref.read(apiClientProvider).presenceOf(widget.peer.id);
      if (mounted) setState(() => _online = p['online'] == true);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final list = await api.messages(widget.peer.id);
      if (!mounted) return;
      setState(() { _messages = list; _loading = false; _error = null; });
      _jump();
      await api.markRead(widget.peer.id);
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    var ev = e['event'];
    if (ev == null && e['id'] != null && e['senderId'] != null && e['content'] != null) ev = 'message';
    final peerId = e['peerId'] ?? e['from'] ?? e['senderId'] ?? asMap(e['message'])['sender_id'];
    if (ev == 'message' || ev == 'new-message') {
      final m = e['message'] is Map ? Message.fromJson(asMap(e['message'])) : Message.fromJson(e);
      if (m.senderId == widget.peer.id || peerId == widget.peer.id) {
        setState(() { _messages = [..._messages, m]; _peerTyping = false; });
        _jump();
        ref.read(apiClientProvider).markRead(widget.peer.id).catchError((_) => <String, dynamic>{});
      }
      ref.invalidate(chatsProvider);
    } else if (ev == 'typing' && peerId == widget.peer.id) {
      setState(() => _peerTyping = true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => _peerTyping = false); });
    } else if ((ev == 'read' || ev == 'delivered') && peerId == widget.peer.id) {
      final at = DateTime.tryParse(e['at']?.toString() ?? '') ?? DateTime.now();
      setState(() => _messages = [for (final m in _messages) m.senderId == myId ? (ev == 'read' ? m.copyWith(readAt: at, deliveredAt: m.deliveredAt ?? at) : m.copyWith(deliveredAt: at)) : m]);
    }
  }

  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      final m = await ref.read(apiClientProvider).sendMessage(widget.peer.id, t);
      setState(() => _messages = [..._messages, m.senderId.isEmpty || m.senderId == 'me' ? Message(id: m.id, senderId: myId, type: 'text', content: t, sentAt: DateTime.now()) : m]);
      _jump();
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(name: widget.peer.nickname, url: widget.peer.avatarUrl, size: 38, online: _online),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.peer.nickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(_peerTyping ? 'يكتب…' : (_online ? 'متصل الآن' : 'غير متصل'), style: TextStyle(fontSize: 12, color: _online || _peerTyping ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w400)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(_error!, onRetry: _load)
                  : _messages.isEmpty
                      ? EmptyState(icon: Icons.waving_hand_rounded, title: 'قل مرحباً لـ ${widget.peer.nickname}')
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _Bubble(_messages[i], mine: _messages[i].senderId == myId, showDate: i == 0 || !_sameDay(_messages[i - 1].sentAt, _messages[i].sentAt)),
                        ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1, maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => ref.read(socketProvider)?.typing(widget.peer.id),
                  decoration: InputDecoration(hintText: 'اكتب رسالة…', border: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: Joy.control)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: Joy.control)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: Joy.primary, width: 1.5)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Joy.primary, shape: const CircleBorder(),
                child: InkWell(customBorder: const CircleBorder(), onTap: _send, child: const SizedBox(width: 46, height: 46, child: Icon(Icons.send_rounded, color: Joy.primaryOn, size: 20))),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bubble extends StatelessWidget {
  final Message m;
  final bool mine;
  final bool showDate;
  const _Bubble(this.m, {required this.mine, required this.showDate});
  @override
  Widget build(BuildContext context) {
    final t = m.sentAt;
    final dateLabel = t == null ? '' : (DateTime.now().difference(t).inDays == 0 ? 'اليوم' : '${t.day}/${t.month}');
    final ticks = !mine ? null : (m.readAt != null ? Icons.done_all_rounded : m.deliveredAt != null ? Icons.done_all_rounded : Icons.done_rounded);
    return Column(children: [
      if (showDate && dateLabel.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(dateLabel, style: const TextStyle(fontSize: 11, color: Joy.textMuted)))),
      Align(
        // رسائلي على اليسار في RTL، رسائل الطرف الآخر على اليمين
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
            decoration: BoxDecoration(
              color: mine ? Joy.bubbleOut : Joy.surface,
              border: mine ? null : Border.all(color: Joy.line),
              borderRadius: BorderRadiusDirectional.only(topStart: const Radius.circular(14), topEnd: const Radius.circular(14), bottomStart: Radius.circular(mine ? 14 : 4), bottomEnd: Radius.circular(mine ? 4 : 14)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m.type == 'text' ? m.content : 'مرفق: ${m.content}', style: TextStyle(fontSize: 14.5, height: 1.55, color: mine ? Joy.bubbleOutText : Joy.text)),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(clockOf(m.sentAt), style: const TextStyle(fontSize: 10.5, color: Joy.textMuted)),
                if (ticks != null) ...[const SizedBox(width: 3), Icon(ticks, size: 14, color: m.readAt != null ? Joy.primary : Joy.textMuted)],
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}
