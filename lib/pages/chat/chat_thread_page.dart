import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

/// تسمية فاصل اليوم: اليوم، أمس، اسم اليوم خلال الأسبوع، وإلا اليوم والشهر (والسنة إن اختلفت).
String dayLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = DateTime(n.year, n.month, n.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  if (diff > 1 && diff < 7) return days[t.weekday - 1];
  return '${t.day} ${months[t.month - 1]}${t.year != n.year ? ' ${t.year}' : ''}';
}

/// نص الخطأ الصالح للعرض بدل ApiException(...) الخام.
String errText(Object e) => e is ApiException ? e.message : e.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');

final _urlRe = RegExp(r'(https?://[^\s<>]+|www\.[^\s<>]+)', caseSensitive: false);

class ChatThreadPage extends ConsumerStatefulWidget {
  final Person peer;
  const ChatThreadPage({super.key, required this.peer});
  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> with WidgetsBindingObserver {
  static const pageSize = 50;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  /// كل الرسائل بمفتاحها (معرّف الخادم أو المحلي) لمنع التكرار.
  final _byKey = <String, Message>{};
  /// مرتبة من الأقدم إلى الأحدث.
  List<Message> _messages = const [];
  bool _loading = true;
  Object? _error;
  bool _peerTyping = false;
  bool _online = false;
  bool _visible = true;
  bool _atBottom = true;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _socketDown = false;
  int _unseen = 0;
  StreamSubscription? _sub;
  Timer? _typingTimer, _presenceTimer;

  String get myId => ref.read(appStateProvider).user?.id ?? '';
  ApiClient get _api => ref.read(apiClientProvider);
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _load();
    final s = ref.read(socketProvider);
    _sub = s?.events.listen(_onEvent);
    _socketDown = s != null && !s.connected;
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) => _presence());
    _presence();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // الرؤية والتمرير
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      // عاد المستخدم للتبويب: نجلب ما فاتنا ونعلّم المقروء إن كان في الأسفل
      _resync();
      _presence();
      if (_atBottom) _markRead();
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // القائمة معكوسة: الصفر هو الأسفل (الأحدث)
    final atBottom = p.pixels < 80;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
      if (atBottom && _unseen > 0) {
        setState(() => _unseen = 0);
        _markRead();
      }
    }
    if (p.pixels > p.maxScrollExtent - 240) _loadOlder();
  }

  void _jumpToBottom({bool animate = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        if (animate) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        } else {
          _scroll.jumpTo(0);
        }
      });

  // ---------------------------------------------------------------------------
  // البيانات
  // ---------------------------------------------------------------------------

  /// يدمج رسائل قادمة مع الموجود بلا تكرار، ويعيد عدد الرسائل الجديدة من الطرف الآخر.
  int _merge(Iterable<Message> incoming) {
    var newFromPeer = 0;
    for (final m in incoming) {
      final k = m.key;
      if (k.isEmpty) continue;
      final old = _byKey[k];
      if (old == null) {
        _byKey[k] = m;
        if (m.senderId != myId) newFromPeer++;
      } else {
        _byKey[k] = old.copyWith(
          sentAt: old.sentAt ?? m.sentAt,
          deliveredAt: m.deliveredAt ?? old.deliveredAt,
          readAt: m.readAt ?? old.readAt,
          status: m.status == MessageStatus.sent ? MessageStatus.sent : old.status,
        );
      }
    }
    _rebuild();
    return newFromPeer;
  }

  void _rebuild() {
    final l = _byKey.values.toList()
      ..sort((a, b) => (a.sentAt ?? DateTime(2100)).compareTo(b.sentAt ?? DateTime(2100)));
    _messages = l;
  }

  Future<void> _load() async {
    try {
      final list = await _api.messages(_peerId, limit: pageSize);
      if (!mounted) return;
      setState(() {
        _merge(list);
        _loading = false;
        _error = null;
        _hasMore = list.length >= pageSize;
      });
      _jumpToBottom();
      _markRead();
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    final oldest = _messages.first.sentAt;
    if (oldest == null) { _hasMore = false; return; }
    setState(() => _loadingMore = true);
    try {
      final list = await _api.messages(_peerId, before: oldest, limit: pageSize);
      if (!mounted) return;
      final before = _byKey.length;
      _merge(list);
      setState(() {
        _loadingMore = false;
        _hasMore = list.length >= pageSize && _byKey.length > before;
      });
    } catch (_) {
      if (mounted) setState(() { _loadingMore = false; _hasMore = false; });
    }
  }

  /// بعد انقطاع أو عودة للتبويب: نجلب آخر صفحة وندمجها.
  Future<void> _resync() async {
    try {
      final list = await _api.messages(_peerId, limit: pageSize);
      if (!mounted) return;
      final n = _merge(list);
      setState(() {});
      if (n > 0) _onNewFromPeer(n);
    } catch (_) {}
  }

  void _onNewFromPeer(int n) {
    if (_atBottom) {
      _jumpToBottom(animate: true);
      _markRead();
    } else {
      setState(() => _unseen += n);
    }
  }

  /// نعلّم المقروء فقط عندما تكون الصفحة ظاهرة فعلاً.
  void _markRead() {
    if (!_visible || !mounted) return;
    _api.markRead(_peerId).then((_) => ref.invalidate(chatsProvider)).catchError((_) {});
  }

  Future<void> _presence() async {
    try {
      final p = await _api.presenceOf(_peerId);
      if (mounted) setState(() => _online = p['online'] == true);
    } catch (_) {}
  }

  void _onEvent(Map<String, dynamic> e) {
    var ev = e['event']?.toString();
    if (ev == null && e['id'] != null && e['senderId'] != null && e['content'] != null) ev = 'message';
    final peerId = (e['peerId'] ?? e['from'] ?? e['senderId'] ?? e['userId'] ?? asMap(e['message'])['sender_id'])?.toString();
    if (ev == '_connected') {
      if (_socketDown) setState(() => _socketDown = false);
      _resync();
      _presence();
    } else if (ev == '_disconnected') {
      setState(() => _socketDown = true);
    } else if (ev == 'message' || ev == 'new-message') {
      final m = e['message'] is Map ? Message.fromJson(asMap(e['message'])) : Message.fromJson(e);
      final fromPeer = m.senderId == _peerId || peerId == _peerId;
      final mineFromOtherDevice = m.senderId == myId && (peerId == _peerId || e['to']?.toString() == _peerId);
      if (fromPeer || mineFromOtherDevice) {
        final n = _merge([m]);
        setState(() { if (fromPeer) _peerTyping = false; });
        if (n > 0) _onNewFromPeer(n);
      }
      ref.invalidate(chatsProvider);
    } else if (ev == 'typing' && peerId == _peerId) {
      setState(() => _peerTyping = true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => _peerTyping = false); });
    } else if ((ev == 'read' || ev == 'delivered') && peerId == _peerId) {
      final at = DateTime.tryParse(e['at']?.toString() ?? '') ?? DateTime.now();
      setState(() {
        for (final m in _messages) {
          if (m.senderId != myId || m.isPending) continue;
          _byKey[m.key] = ev == 'read' ? m.copyWith(readAt: at, deliveredAt: m.deliveredAt ?? at) : m.copyWith(deliveredAt: at);
        }
        _rebuild();
      });
    } else if (ev == 'presence' && peerId == _peerId) {
      setState(() => _online = e['online'] == true);
    }
  }

  // ---------------------------------------------------------------------------
  // الإرسال (متفائل: تظهر الرسالة فوراً ثم تتأكد أو تفشل مع إعادة محاولة)
  // ---------------------------------------------------------------------------

  Future<void> _send([Message? retry]) async {
    final t = retry?.content ?? _text.text.trim();
    if (t.isEmpty) return;
    final local = retry?.copyWith(status: MessageStatus.sending) ??
        Message(id: '', localId: 'local-${DateTime.now().microsecondsSinceEpoch}', senderId: myId, type: 'text', content: t, sentAt: DateTime.now(), status: MessageStatus.sending);
    if (retry == null) _text.clear();
    setState(() { _byKey[local.key] = local; _rebuild(); });
    _jumpToBottom();
    try {
      final m = await _api.sendMessage(_peerId, t);
      if (!mounted) return;
      final serverId = m.id.isNotEmpty && m.senderId != 'me' ? m.id : null;
      final sent = (serverId != null ? m : local).copyWith(id: serverId ?? local.key, status: MessageStatus.sent, localId: local.localId, sentAt: m.sentAt ?? local.sentAt);
      setState(() {
        _byKey.remove(local.key);
        _byKey[sent.key] = sent;
        _rebuild();
      });
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() { _byKey[local.key] = local.copyWith(status: MessageStatus.failed); _rebuild(); });
      toast(context, 'لم تُرسل الرسالة: ${errText(e)}', error: true);
    }
  }

  void _discard(Message m) => setState(() { _byKey.remove(m.key); _rebuild(); });

  // ---------------------------------------------------------------------------
  // الإجراءات: نسخ، إعادة إرسال، حذف، إبلاغ، حظر
  // ---------------------------------------------------------------------------

  Future<void> _actions(Message m) async {
    final mine = m.senderId == myId;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('نسخ النص'), onTap: () => Navigator.pop(ctx, 'copy')),
          if (m.status == MessageStatus.failed) ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('إعادة الإرسال'), onTap: () => Navigator.pop(ctx, 'retry')),
          if (m.status == MessageStatus.failed) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('تجاهل الرسالة'), onTap: () => Navigator.pop(ctx, 'discard')),
          if (mine && m.status == MessageStatus.sent && !m.id.startsWith('local-')) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف الرسالة', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!mine) ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('إبلاغ عن هذه الرسالة'), onTap: () => Navigator.pop(ctx, 'report')),
          if (!mine) ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${widget.peer.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (mounted) toast(context, 'نُسخ النص');
      case 'retry':
        await _send(m);
      case 'discard':
        _discard(m);
      case 'delete':
        await _delete(m);
      case 'report':
        await _report(messageId: m.id);
      case 'block':
        await _block();
    }
  }

  Future<void> _delete(Message m) async {
    try {
      await _api.deleteMessage(m.id);
      if (!mounted) return;
      _discard(m);
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _report({String? messageId}) async {
    final reason = await askText(context, title: 'إبلاغ عن ${widget.peer.nickname}', hint: 'ما المشكلة؟ (إزعاج، احتيال، محتوى مسيء…)', confirm: 'إرسال البلاغ');
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await _api.reportUser(_peerId, reason, messageId: messageId);
      if (mounted) toast(context, 'وصل بلاغك وسنراجعه');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حظر ${widget.peer.nickname}؟'),
        content: const Text('لن يستطيع مراسلتك أو رؤية لحظاتك. يمكنك إلغاء الحظر لاحقاً من ماي سبيس.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حظر')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.blockUser(_peerId);
      if (!mounted) return;
      ref.invalidate(chatsProvider);
      ref.invalidate(contactsProvider);
      toast(context, 'تم حظر ${widget.peer.nickname}');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // الواجهة
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(name: widget.peer.nickname, url: widget.peer.avatarUrl, size: 38, online: _online),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.peer.nickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_peerTyping ? 'يكتب…' : (_online ? 'متصل الآن' : 'غير متصل'), style: TextStyle(fontSize: 12, color: _online || _peerTyping ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w400)),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ'))),
              PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر', style: TextStyle(color: Joy.danger)))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_socketDown)
          Container(
            width: double.infinity,
            color: Joy.sunSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Text('انقطع الاتصال المباشر ونعيد المحاولة… قد تتأخر الرسائل الواردة', style: TextStyle(color: Joy.sunText, fontSize: 12)),
          ),
        Expanded(
          child: Stack(children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(_error!, onRetry: _load)
                    : _messages.isEmpty
                        ? EmptyState(icon: Icons.waving_hand_rounded, title: 'قل مرحباً لـ ${widget.peer.nickname}')
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            itemCount: _messages.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _messages.length) {
                                return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
                              }
                              final idx = _messages.length - 1 - i;
                              final m = _messages[idx];
                              final prev = idx > 0 ? _messages[idx - 1] : null;
                              final next = idx < _messages.length - 1 ? _messages[idx + 1] : null;
                              final showDate = prev == null || !_sameDay(prev.sentAt, m.sentAt);
                              return _Bubble(
                                m,
                                mine: m.senderId == myId,
                                dateLabel: showDate && m.sentAt != null ? dayLabel(m.sentAt!) : null,
                                joinedAbove: prev != null && !showDate && prev.senderId == m.senderId && _close(prev.sentAt, m.sentAt),
                                joinedBelow: next != null && _sameDay(m.sentAt, next.sentAt) && next.senderId == m.senderId && _close(m.sentAt, next.sentAt),
                                onLongPress: () => _actions(m),
                                onRetry: () => _send(m),
                              );
                            },
                          ),
            if (_unseen > 0)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Joy.primary,
                    shape: const StadiumBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () { setState(() => _unseen = 0); _jumpToBottom(animate: true); _markRead(); },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.arrow_downward_rounded, size: 16, color: Joy.primaryOn),
                          const SizedBox(width: 6),
                          Text(_unseen == 1 ? 'رسالة جديدة' : '$_unseen رسائل جديدة', style: const TextStyle(color: Joy.primaryOn, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
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
                  onChanged: (v) { if (v.isNotEmpty) ref.read(socketProvider)?.typing(_peerId); },
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
  bool _close(DateTime? a, DateTime? b) => a != null && b != null && b.difference(a).abs() < const Duration(minutes: 5);
}

/// فقاعة رسالة: تجميع المتتاليات، حالة الإرسال، روابط قابلة للنقر، ضغط مطوّل للإجراءات.
class _Bubble extends StatefulWidget {
  final Message m;
  final bool mine;
  final String? dateLabel;
  final bool joinedAbove, joinedBelow;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  const _Bubble(this.m, {required this.mine, this.dateLabel, this.joinedAbove = false, this.joinedBelow = false, required this.onLongPress, required this.onRetry});
  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _linkify(String text, TextStyle style) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _urlRe.allMatches(text)) {
      if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
      final raw = match.group(0)!;
      final url = raw.startsWith('www.') ? 'https://$raw' : raw;
      final rec = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(rec);
      spans.add(TextSpan(text: raw, style: style.copyWith(decoration: TextDecoration.underline, color: widget.mine ? Joy.bubbleOutText : Joy.primary, fontWeight: FontWeight.w600), recognizer: rec));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final mine = widget.mine;
    final style = TextStyle(fontSize: 14.5, height: 1.55, color: mine ? Joy.bubbleOutText : Joy.text);
    final failed = m.status == MessageStatus.failed;
    final tail = Radius.circular(widget.joinedBelow ? 6 : 4);
    final joined = const Radius.circular(6);
    const full = Radius.circular(14);
    IconData? tick;
    Color tickColor = Joy.textMuted;
    if (mine) {
      switch (m.status) {
        case MessageStatus.sending:
          tick = Icons.schedule_rounded;
        case MessageStatus.failed:
          tick = Icons.error_outline_rounded;
          tickColor = Joy.danger;
        case MessageStatus.sent:
          tick = m.deliveredAt != null || m.readAt != null ? Icons.done_all_rounded : Icons.done_rounded;
          if (m.readAt != null) tickColor = Joy.primary;
      }
    }
    return Column(children: [
      if (widget.dateLabel != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(widget.dateLabel!, style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
        ),
      Align(
        // رسائلي في نهاية الاتجاه، ورسائل الطرف الآخر في بدايته
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            onTap: failed ? widget.onRetry : null,
            child: Opacity(
              opacity: m.status == MessageStatus.sending ? 0.7 : 1,
              child: Container(
                margin: EdgeInsets.only(top: widget.joinedAbove ? 1.5 : 4, bottom: widget.joinedBelow ? 1.5 : 4),
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
                decoration: BoxDecoration(
                  color: mine ? Joy.bubbleOut : Joy.surface,
                  border: failed ? Border.all(color: Joy.danger) : mine ? null : Border.all(color: Joy.line),
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: !mine && widget.joinedAbove ? joined : full,
                    topEnd: mine && widget.joinedAbove ? joined : full,
                    bottomStart: mine ? full : tail,
                    bottomEnd: mine ? tail : full,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (m.type == 'text') Text.rich(TextSpan(style: style, children: _linkify(m.content, style))) else Text('مرفق: ${m.content}', style: style),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (failed)
                      const Text('لم تُرسل · اضغط لإعادة المحاولة', style: TextStyle(fontSize: 10.5, color: Joy.danger, fontWeight: FontWeight.w600))
                    else
                      Text(clockOf(m.sentAt), style: const TextStyle(fontSize: 10.5, color: Joy.textMuted)),
                    if (tick != null) ...[const SizedBox(width: 3), Icon(tick, size: 14, color: tickColor)],
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
