import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/media.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/pattern_background.dart';
import '../../ui/profile_avatar.dart';
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

String fmtDuration(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// الحد الأقصى لتسجيل الرسالة الصوتية.
const maxVoiceDuration = Duration(minutes: 5);
const maxMediaBytes = 30 * 1024 * 1024;

final _urlRe = RegExp(r'(https?://[^\s<>]+|www\.[^\s<>]+)', caseSensitive: false);

String _mimeOf(String name, [String? given]) {
  if (given != null && given.isNotEmpty && given != 'application/octet-stream') return given.split(';').first.trim();
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp', 'gif' => 'image/gif',
    'mp4' || 'm4v' => 'video/mp4', 'webm' => 'video/webm', 'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg', 'm4a' => 'audio/mp4', 'ogg' || 'oga' => 'audio/ogg', 'wav' => 'audio/wav', 'weba' => 'audio/webm',
    'pdf' => 'application/pdf', _ => 'application/octet-stream',
  };
}

String _kindOf(String mime) => mime.startsWith('image/') ? 'image' : mime.startsWith('video/') ? 'video' : mime.startsWith('audio/') ? 'audio' : 'file';

class ChatThreadPage extends ConsumerStatefulWidget {
  final Person peer;
  /// رسالة يُقفز إليها بعد التحميل (من نتائج البحث مثلاً).
  final String? initialMessageId;
  const ChatThreadPage({super.key, required this.peer, this.initialMessageId});
  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> with WidgetsBindingObserver {
  static const pageSize = 50;
  final _text = TextEditingController();
  final _itemScroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  /// كل الرسائل بمفتاحها (معرّف الخادم أو المحلي) لمنع التكرار.
  final _byKey = <String, Message>{};
  /// مرتبة من الأقدم إلى الأحدث.
  List<Message> _messages = const [];
  final _metaFetched = <String>{};
  /// بايتات الوسائط المحلية قبل/أثناء الرفع (للمعاينة وإعادة المحاولة).
  final _localBytes = <String, ({Uint8List bytes, String mime, String name})>{};
  bool _loading = true;
  Object? _error;
  bool _peerTyping = false;
  bool _online = false;
  bool _visible = true;
  bool _atBottom = true;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _socketDown = false;
  bool _hasText = false;
  int _unseen = 0;
  String? _highlightKey;
  Timer? _highlightTimer;
  Message? _replyTo;
  // البحث داخل المحادثة
  bool _searching = false;
  final _searchCtl = TextEditingController();
  List<int> _matches = const [];
  int _matchIdx = 0;
  // التسجيل الصوتي
  final _recorder = AudioRecorder();
  VoiceRecorder? _webRec;
  bool _recording = false;
  Duration _recElapsed = Duration.zero;
  Timer? _recTimer;
  StreamSubscription? _sub;
  Timer? _typingTimer, _presenceTimer;

  String get myId => ref.read(appStateProvider).user?.id ?? '';
  String get myName => ref.read(appStateProvider).user?.nickname ?? '';
  ApiClient get _api => ref.read(apiClientProvider);
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positions.itemPositions.addListener(_onPositions);
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
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
    _positions.itemPositions.removeListener(_onPositions);
    _sub?.cancel();
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    _highlightTimer?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _text.dispose();
    _searchCtl.dispose();
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
      _resync();
      _presence();
      if (_atBottom) _markRead();
    }
  }

  void _onPositions() {
    final ps = _positions.itemPositions.value;
    if (ps.isEmpty) return;
    var minIdx = 1 << 30, maxIdx = -1;
    for (final p in ps) {
      minIdx = math.min(minIdx, p.index);
      maxIdx = math.max(maxIdx, p.index);
    }
    // القائمة معكوسة: العنصر 0 هو الأحدث (الأسفل)
    final atBottom = minIdx == 0;
    if (atBottom != _atBottom) {
      _atBottom = atBottom;
      if (mounted) setState(() {});
      if (atBottom && _unseen > 0) {
        setState(() => _unseen = 0);
        _markRead();
      }
    }
    if (maxIdx >= _messages.length - 6) _loadOlder();
  }

  int _displayIndex(int msgIdx) => _messages.length - 1 - msgIdx;

  void _jumpToBottom({bool animate = true}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_itemScroll.isAttached || _messages.isEmpty) return;
        if (animate) {
          _itemScroll.scrollTo(index: 0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        } else {
          _itemScroll.jumpTo(index: 0);
        }
      });

  /// يقفز إلى رسالة (بمفتاحها) ويبرزها لحظة؛ يرجع false إن لم تكن محمّلة.
  bool _jumpToKey(String key) {
    final idx = _messages.indexWhere((m) => m.key == key || m.id == key);
    if (idx < 0) return false;
    if (_itemScroll.isAttached) {
      _itemScroll.scrollTo(index: _displayIndex(idx), duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.35);
    }
    _highlightTimer?.cancel();
    setState(() => _highlightKey = _messages[idx].key);
    _highlightTimer = Timer(const Duration(milliseconds: 1800), () { if (mounted) setState(() => _highlightKey = null); });
    return true;
  }

  /// يحمّل صفحات أقدم حتى تظهر الرسالة المطلوبة (بحد أقصى)، ثم يقفز إليها.
  Future<void> _revealMessage(String id, {int maxPages = 6}) async {
    for (var i = 0; i < maxPages; i++) {
      if (_jumpToKey(id)) return;
      if (!_hasMore) break;
      await _loadOlder();
    }
    if (!_jumpToKey(id) && mounted) toast(context, 'الرسالة أقدم من المحمّل حالياً');
  }

  // ---------------------------------------------------------------------------
  // البيانات
  // ---------------------------------------------------------------------------

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
          quote: old.quote ?? m.quote,
          replyTo: old.replyTo ?? m.replyTo,
          forwardedFrom: old.forwardedFrom ?? m.forwardedFrom,
          extra: {...m.extra, ...old.extra},
        );
      }
    }
    _rebuild();
    _fetchMeta();
    return newFromPeer;
  }

  void _rebuild() {
    final l = _byKey.values.toList()
      ..sort((a, b) => (a.sentAt ?? DateTime(2100)).compareTo(b.sentAt ?? DateTime(2100)));
    _messages = l;
    if (_searching) _recomputeMatches(keepIndex: true);
  }

  /// يجلب بيانات الرد/التوجيه/المدة للرسائل التي لم تُجلب لها بعد.
  Future<void> _fetchMeta() async {
    final ids = _messages.where((m) => m.id.isNotEmpty && !m.id.startsWith('local-') && !_metaFetched.contains(m.id)).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    _metaFetched.addAll(ids);
    try {
      final meta = await _api.messageMeta(ids);
      if (!mounted || meta.isEmpty) return;
      setState(() {
        for (final e in meta.entries) {
          final m = _byKey[e.key];
          if (m != null) _byKey[e.key] = m.withMeta(e.value);
        }
        _rebuild();
      });
    } catch (_) {
      _metaFetched.removeAll(ids);
    }
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
      _jumpToBottom(animate: false);
      _markRead();
      final target = widget.initialMessageId;
      if (target != null) WidgetsBinding.instance.addPostFrameCallback((_) => _revealMessage(target));
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
      _jumpToBottom();
      _markRead();
    } else {
      setState(() => _unseen += n);
    }
  }

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
    } else if ((ev == 'deleted' || ev == 'message-deleted') && e['id'] != null) {
      setState(() { _byKey.remove(e['id'].toString()); _rebuild(); });
    }
  }

  // ---------------------------------------------------------------------------
  // الإرسال: نص أو وسائط، متفائل، مع رد مقتبس أو إعادة توجيه
  // ---------------------------------------------------------------------------

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await _send(type: 'text', content: t);
  }

  Future<void> _send({
    required String type,
    required String content,
    ({Uint8List bytes, String mime, String name})? media,
    Map<String, dynamic>? extra,
    Message? retry,
  }) async {
    final quote = retry?.quote ?? (_replyTo == null ? null : MessageQuote(id: _replyTo!.key, senderId: _replyTo!.senderId, senderName: _replyTo!.senderId == myId ? 'أنت' : widget.peer.nickname, type: _replyTo!.mediaKind, content: _replyTo!.mediaKind == 'text' ? _replyTo!.content : ''));
    final local = retry?.copyWith(status: MessageStatus.sending) ??
        Message(id: '', localId: 'local-${DateTime.now().microsecondsSinceEpoch}', senderId: myId, type: type, content: content, sentAt: DateTime.now(),
            status: MessageStatus.sending, quote: quote, replyTo: quote?.id, extra: extra ?? const {});
    if (retry == null && media != null) _localBytes[local.key] = media;
    if (retry == null) setState(() => _replyTo = null);
    setState(() { _byKey[local.key] = local; _rebuild(); });
    _jumpToBottom();
    try {
      var body = local.content;
      final pending = _localBytes[local.key];
      if (body.isEmpty && pending != null) {
        final up = await _api.uploadMedia(pending.bytes, contentType: pending.mime, fileName: pending.name);
        body = up.url;
        if (!mounted) return;
        setState(() { _byKey[local.key] = local.copyWith(content: body); _rebuild(); });
      }
      if (body.isEmpty) throw const ApiException(0, 'لا محتوى للإرسال');
      // الخادم الأساسي يقبل النص فقط: الوسائط تُرسل كرابط مطلق ويُستنتج نوعها من امتداده
      if (local.type != 'text') body = _api.absolute(body);
      final extra = {...local.extra, if (local.type != 'text') 'kind': local.type};
      final m = await _api.sendMessage(_peerId, body, type: 'text', replyTo: local.replyTo, quote: local.quote, forwardedFrom: local.forwardedFrom, extra: extra);
      if (!mounted) return;
      final serverId = m.id.isNotEmpty && m.senderId != 'me' ? m.id : null;
      final sent = (serverId != null ? m : local).copyWith(
        id: serverId ?? local.key, status: MessageStatus.sent, localId: local.localId, sentAt: m.sentAt ?? local.sentAt, content: body,
        quote: local.quote, replyTo: local.replyTo, forwardedFrom: local.forwardedFrom, extra: {...extra, ...m.extra},
      );
      setState(() {
        _byKey.remove(local.key);
        _byKey[sent.key] = sent;
        _metaFetched.add(sent.id);
        _rebuild();
      });
      if (serverId != null && (local.quote != null || local.forwardedFrom != null || extra.isNotEmpty)) {
        _api.setMessageMeta(serverId, replyTo: local.replyTo, quote: local.quote, forwardedFrom: local.forwardedFrom, extra: extra).catchError((_) {});
      }
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() { _byKey[local.key] = _byKey[local.key]!.copyWith(status: MessageStatus.failed); _rebuild(); });
      toast(context, 'لم تُرسل الرسالة: ${errText(e)}', error: true);
    }
  }

  void _discard(Message m) => setState(() { _byKey.remove(m.key); _localBytes.remove(m.key); _rebuild(); });

  // ---- المرفقات
  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: Joy.primary), title: const Text('صورة من المعرض'), onTap: () => Navigator.pop(ctx, 'image')),
          ListTile(leading: const Icon(Icons.photo_camera_outlined, color: Joy.primary), title: const Text('التقاط صورة'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.videocam_outlined, color: Joy.accent), title: const Text('فيديو'), onTap: () => Navigator.pop(ctx, 'video')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      ({Uint8List bytes, String mime, String name}) picked;
      if (kIsWeb && WebMedia.available) {
        // الويب: قراءة مباشرة من المتصفح (روابط blob تفشل على iOS)
        final m = await WebMedia.pick(choice);
        if (m == null) return;
        picked = (bytes: m.bytes, mime: m.mime, name: m.name);
      } else {
        final picker = ImagePicker();
        XFile? x;
        if (choice == 'video') {
          x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
        } else {
          x = await picker.pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
        }
        if (x == null) return;
        picked = (bytes: await x.readAsBytes(), mime: _mimeOf(x.name, x.mimeType), name: x.name);
      }
      if (picked.bytes.length > maxMediaBytes) { if (mounted) toast(context, 'الملف أكبر من 30 ميغابايت', error: true); return; }
      await _send(type: _kindOf(picked.mime), content: '', media: picked);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  // ---- التسجيل الصوتي (5 دقائق كحد أقصى)
  Future<void> _startRecording() async {
    try {
      if (kIsWeb && WebMedia.available) {
        _webRec = VoiceRecorder();
        await _webRec!.start(); // يطلب إذن الميكروفون من المتصفح
      } else {
        if (!await _recorder.hasPermission()) { if (mounted) toast(context, 'اسمح بالوصول إلى الميكروفون أولاً', error: true); return; }
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 48000, numChannels: 1), path: '');
      }
      setState(() { _recording = true; _recElapsed = Duration.zero; });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recElapsed += const Duration(seconds: 1));
        if (_recElapsed >= maxVoiceDuration) _stopRecording(send: true);
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذر بدء التسجيل: ${errText(e)}', error: true);
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final elapsed = _recElapsed;
    if (!_recording) return;
    setState(() => _recording = false);
    try {
      ({Uint8List bytes, String mime, String name})? media;
      if (kIsWeb && _webRec != null) {
        final rec = _webRec!;
        _webRec = null;
        if (!send) { await rec.cancel(); return; }
        final m = await rec.stop();
        if (m != null) media = (bytes: m.bytes, mime: m.mime, name: m.name);
      } else {
        if (!send) { await _recorder.cancel(); return; }
        final path = await _recorder.stop();
        if (path != null) {
          final bytes = await XFile(path).readAsBytes();
          final mime = _mimeOf(path);
          media = (bytes: bytes, mime: mime, name: 'voice.${path.split('.').last}');
        }
      }
      if (media == null || elapsed < const Duration(seconds: 1)) { if (mounted) toast(context, 'التسجيل قصير جداً'); return; }
      await _send(type: 'audio', content: '', media: media, extra: {'durationMs': elapsed.inMilliseconds});
    } catch (e) {
      if (mounted) toast(context, 'تعذر إرسال التسجيل: ${errText(e)}', error: true);
    }
  }

  // ---- إعادة التوجيه
  Future<void> _forward(Message m) async {
    final chats = ref.read(chatsProvider).value ?? const <Chat>[];
    final contacts = ref.read(contactsProvider).value ?? const <Person>[];
    final people = <String, Person>{for (final c in chats) c.peer.id: c.peer, for (final p in contacts) p.id: p};
    final target = await showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PeoplePicker(people: people.values.toList(), title: 'إعادة التوجيه إلى'),
    );
    if (target == null || !mounted) return;
    final from = m.senderId == myId ? myName : widget.peer.nickname;
    try {
      final sent = await _api.sendMessage(target.id, m.type == 'text' ? m.content : _api.absolute(m.content), type: 'text', forwardedFrom: from, extra: m.extra);
      if (sent.id.isNotEmpty && sent.senderId != 'me') {
        _api.setMessageMeta(sent.id, forwardedFrom: from, extra: m.extra.isEmpty ? null : m.extra).catchError((_) {});
        if (target.id == _peerId && mounted) setState(() { _merge([sent.copyWith(forwardedFrom: from, extra: m.extra)]); });
      }
      ref.invalidate(chatsProvider);
      if (mounted) toast(context, 'أُعيد التوجيه إلى ${target.nickname}');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // البحث داخل المحادثة
  // ---------------------------------------------------------------------------

  void _recomputeMatches({bool keepIndex = false}) {
    final q = _searchCtl.text.trim().toLowerCase();
    if (q.isEmpty) { _matches = const []; _matchIdx = 0; return; }
    final hits = <int>[];
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if ((m.mediaKind == 'text' && m.content.toLowerCase().contains(q)) || (m.quote?.content.toLowerCase().contains(q) ?? false)) hits.add(i);
    }
    _matches = hits;
    if (!keepIndex || _matchIdx >= hits.length) _matchIdx = 0;
  }

  void _search(String _) {
    setState(() => _recomputeMatches());
    if (_matches.isNotEmpty) _jumpToKey(_messages[_matches[_matchIdx]].key);
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _matchIdx = (_matchIdx + delta) % _matches.length);
    _jumpToKey(_messages[_matches[_matchIdx]].key);
  }

  // ---------------------------------------------------------------------------
  // الإجراءات
  // ---------------------------------------------------------------------------

  Future<void> _actions(Message m) async {
    final mine = m.senderId == myId;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            if (m.status == MessageStatus.sent) ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('رد'), onTap: () => Navigator.pop(ctx, 'reply')),
            if (m.status == MessageStatus.sent) ListTile(leading: const Icon(Icons.forward_rounded), title: const Text('إعادة توجيه'), onTap: () => Navigator.pop(ctx, 'forward')),
            if (m.mediaKind == 'text') ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('نسخ النص'), onTap: () => Navigator.pop(ctx, 'copy')),
            if (m.isMedia && m.content.isNotEmpty) ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('فتح الملف'), onTap: () => Navigator.pop(ctx, 'open')),
            if (m.status == MessageStatus.failed) ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('إعادة الإرسال'), onTap: () => Navigator.pop(ctx, 'retry')),
            if (m.status == MessageStatus.failed) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('تجاهل الرسالة'), onTap: () => Navigator.pop(ctx, 'discard')),
            if (mine && m.status == MessageStatus.sent && !m.id.startsWith('local-')) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف الرسالة', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
            if (!mine) ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('إبلاغ عن هذه الرسالة'), onTap: () => Navigator.pop(ctx, 'report')),
            if (!mine) ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${widget.peer.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replyTo = m);
      case 'forward':
        await _forward(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (mounted) toast(context, 'نُسخ النص');
      case 'open':
        await launchUrl(Uri.parse(_api.absolute(m.content)), mode: LaunchMode.externalApplication);
      case 'retry':
        await _send(type: m.type, content: m.content, retry: m);
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

  PreferredSizeWidget _appBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_forward_rounded), tooltip: 'إغلاق البحث', onPressed: () => setState(() { _searching = false; _searchCtl.clear(); _matches = const []; })),
        titleSpacing: 0,
        title: TextField(
          controller: _searchCtl,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(hintText: 'ابحث في المحادثة…', border: InputBorder.none, filled: false, isDense: true),
        ),
        actions: [
          Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Center(child: Text(_matches.isEmpty ? (_searchCtl.text.isEmpty ? '' : '0') : '${_matchIdx + 1}/${_matches.length}', style: const TextStyle(color: Joy.textMuted, fontSize: 13)))),
          IconButton(tooltip: 'الأقدم', onPressed: _matches.isEmpty ? null : () => _stepMatch(1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
          IconButton(tooltip: 'الأحدث', onPressed: _matches.isEmpty ? null : () => _stepMatch(-1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          if (_hasMore) TextButton(onPressed: _loadingMore ? null : () async { await _loadOlder(); _search(_searchCtl.text); }, child: Text(_loadingMore ? '…' : 'الأقدم')),
        ],
      );
    }
    return AppBar(
      titleSpacing: 0,
      title: Row(children: [
        ProfileAvatar(person: widget.peer, size: 38, online: _online),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.peer.nickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_peerTyping ? 'يكتب…' : (_online ? 'متصل الآن' : 'غير متصل'), style: TextStyle(fontSize: 12, color: _online || _peerTyping ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w400)),
          ]),
        ),
      ]),
      actions: [
        IconButton(tooltip: 'بحث', icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
        PopupMenuButton<String>(
          tooltip: 'المزيد',
          onSelected: (v) => v == 'report' ? _report() : _block(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ'))),
            PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر', style: TextStyle(color: Joy.danger)))),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: _appBar(),
      body: Column(children: [
        if (_socketDown)
          Container(
            width: double.infinity,
            color: Joy.sunSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Text('انقطع الاتصال المباشر ونعيد المحاولة… قد تتأخر الرسائل الواردة', style: TextStyle(color: Joy.sunText, fontSize: 12)),
          ),
        Expanded(child: NaslifePattern(child: Stack(children: [_list(), if (_unseen > 0) _newMessagesChip()]))),
        _composer(),
      ]),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, onRetry: _load);
    if (_messages.isEmpty) return EmptyState(icon: Icons.waving_hand_rounded, title: 'قل مرحباً لـ ${widget.peer.nickname}');
    final q = _searching ? _searchCtl.text.trim() : '';
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      itemPositionsListener: _positions,
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
          peerName: widget.peer.nickname,
          dateLabel: showDate && m.sentAt != null ? dayLabel(m.sentAt!) : null,
          joinedAbove: prev != null && !showDate && prev.senderId == m.senderId && _close(prev.sentAt, m.sentAt),
          joinedBelow: next != null && _sameDay(m.sentAt, next.sentAt) && next.senderId == m.senderId && _close(m.sentAt, next.sentAt),
          highlighted: _highlightKey == m.key,
          searchQuery: q,
          localBytes: _localBytes[m.key]?.bytes,
          mediaUrl: m.content.isEmpty ? null : _api.absolute(m.content),
          onLongPress: () => _actions(m),
          onRetry: () => _send(type: m.type, content: m.content, retry: m),
          onQuoteTap: m.quote == null ? null : () { if (!_jumpToKey(m.quote!.id)) _revealMessage(m.quote!.id); },
        );
      },
    );
  }

  Widget _newMessagesChip() => Positioned(
        bottom: 10, left: 0, right: 0,
        child: Center(
          child: Material(
            color: Joy.primary, shape: const StadiumBorder(), elevation: 3,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () { setState(() => _unseen = 0); _jumpToBottom(); _markRead(); },
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
      );

  Widget _composer() {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide.none);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
              child: Row(children: [
                Expanded(child: _QuoteBox(name: _replyTo!.senderId == myId ? 'أنت' : widget.peer.nickname, text: _replyTo!.preview, compact: true)),
                IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'إلغاء الرد', onPressed: () => setState(() => _replyTo = null)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: _recording ? _recordingRow() : Row(children: [
              IconButton(tooltip: 'إرفاق', onPressed: _attach, icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.textMuted, size: 28)),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1, maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendText(),
                  onChanged: (v) { if (v.isNotEmpty) ref.read(socketProvider)?.typing(_peerId); },
                  decoration: InputDecoration(hintText: 'اكتب رسالة…', border: border, enabledBorder: border, focusedBorder: border, filled: true, fillColor: Joy.surface2, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Joy.primary, shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _hasText ? _sendText : _startRecording,
                  child: SizedBox(width: 46, height: 46, child: Icon(_hasText ? Icons.send_rounded : Icons.mic_rounded, color: Joy.primaryOn, size: _hasText ? 20 : 24)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _recordingRow() => Row(children: [
        IconButton(tooltip: 'إلغاء التسجيل', onPressed: () => _stopRecording(send: false), icon: const Icon(Icons.delete_outline_rounded, color: Joy.danger, size: 26)),
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Joy.danger, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('${fmtDuration(_recElapsed)} / ${fmtDuration(maxVoiceDuration)}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const Expanded(child: Text('جارٍ التسجيل… اضغط إرسال عند الانتهاء', style: TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
        Material(
          color: Joy.primary, shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: () => _stopRecording(send: true), child: const SizedBox(width: 46, height: 46, child: Icon(Icons.send_rounded, color: Joy.primaryOn, size: 20))),
        ),
      ]);

  bool _sameDay(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;
  bool _close(DateTime? a, DateTime? b) => a != null && b != null && b.difference(a).abs() < const Duration(minutes: 5);
}

/// اختيار شخص من المحادثات وجهات الاتصال (لإعادة التوجيه).
class _PeoplePicker extends StatefulWidget {
  final List<Person> people;
  final String title;
  const _PeoplePicker({required this.people, required this.title});
  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.people.where((p) => q.isEmpty || p.nickname.toLowerCase().contains(q) || p.id.toLowerCase().contains(q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: Row(children: [Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context))])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(autofocus: true, onChanged: (v) => setState(() => q = v.trim().toLowerCase()), decoration: const InputDecoration(hintText: 'ابحث بالاسم', prefixIcon: Icon(Icons.search_rounded)))),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.person_search_rounded, title: 'لا أحد بهذا الاسم')
                  : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => ListTile(leading: Avatar(name: list[i].nickname, url: list[i].avatarUrl, size: 40), title: Text(list[i].nickname), subtitle: Text(list[i].id, style: const TextStyle(fontSize: 11)), onTap: () => Navigator.pop(context, list[i]))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// صندوق الاقتباس داخل الفقاعة أو فوق حقل الكتابة.
class _QuoteBox extends StatelessWidget {
  final String name, text;
  final bool compact, onDark;
  final VoidCallback? onTap;
  const _QuoteBox({required this.name, required this.text, this.compact = false, this.onDark = false, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: onDark ? Colors.black.withValues(alpha: .06) : Joy.primarySoft.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(10),
            border: const BorderDirectional(start: BorderSide(color: Joy.primary, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Joy.primary)),
            Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted)),
          ]),
        ),
      );
}

/// فقاعة رسالة: نص أو وسائط، اقتباس، إعادة توجيه، حالة الإرسال، روابط، ضغط مطوّل.
class _Bubble extends StatefulWidget {
  final Message m;
  final bool mine;
  final String peerName;
  final String? dateLabel;
  final bool joinedAbove, joinedBelow, highlighted;
  final String searchQuery;
  final Uint8List? localBytes;
  final String? mediaUrl;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final VoidCallback? onQuoteTap;
  const _Bubble(this.m, {required this.mine, required this.peerName, this.dateLabel, this.joinedAbove = false, this.joinedBelow = false, this.highlighted = false,
      this.searchQuery = '', this.localBytes, this.mediaUrl, required this.onLongPress, required this.onRetry, this.onQuoteTap});
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

  List<InlineSpan> _rich(String text, TextStyle style) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final q = widget.searchQuery.toLowerCase();
    final hl = style.copyWith(backgroundColor: Joy.sun.withValues(alpha: .55));
    List<InlineSpan> plain(String s) {
      if (q.isEmpty) return [TextSpan(text: s)];
      final out = <InlineSpan>[];
      var i = 0;
      final lower = s.toLowerCase();
      while (true) {
        final j = lower.indexOf(q, i);
        if (j < 0) { out.add(TextSpan(text: s.substring(i))); break; }
        if (j > i) out.add(TextSpan(text: s.substring(i, j)));
        out.add(TextSpan(text: s.substring(j, j + q.length), style: hl));
        i = j + q.length;
      }
      return out;
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _urlRe.allMatches(text)) {
      if (match.start > last) spans.addAll(plain(text.substring(last, match.start)));
      final raw = match.group(0)!;
      final url = raw.startsWith('www.') ? 'https://$raw' : raw;
      final rec = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(rec);
      spans.add(TextSpan(text: raw, style: style.copyWith(decoration: TextDecoration.underline, color: widget.mine ? Joy.bubbleOutText : Joy.primary, fontWeight: FontWeight.w600), recognizer: rec));
      last = match.end;
    }
    if (last < text.length) spans.addAll(plain(text.substring(last)));
    return spans;
  }

  Widget _media(Message m) {
    final url = widget.mediaUrl;
    switch (m.mediaKind) {
      case 'image':
        final img = widget.localBytes != null
            ? Image.memory(widget.localBytes!, fit: BoxFit.cover)
            : url == null
                ? const SizedBox(width: 200, height: 120)
                : Image.network(url, fit: BoxFit.cover, loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(width: 200, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))), errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 120, child: Icon(Icons.broken_image_outlined, color: Joy.textMuted)));
        return GestureDetector(
          onTap: url == null ? null : () => _viewImage(context, url, widget.localBytes),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320), child: img)),
        );
      case 'audio':
        return _AudioBubble(url: url, durationMs: m.durationMs, mine: widget.mine, pending: m.isPending);
      case 'video':
        return InkWell(
          onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(width: 220, height: 130, decoration: BoxDecoration(color: Colors.black.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_fill_rounded, size: 44, color: Joy.primary), SizedBox(height: 4), Text('فيديو · اضغط للتشغيل', style: TextStyle(fontSize: 12, color: Joy.textMuted))])),
        );
      default:
        return InkWell(
          onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.attach_file_rounded, size: 18, color: Joy.textMuted), const SizedBox(width: 6), Text(m.content.split('/').last, style: const TextStyle(decoration: TextDecoration.underline))]),
        );
    }
  }

  void _viewImage(BuildContext context, String url, Uint8List? bytes) => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(children: [
            Center(child: InteractiveViewer(maxScale: 5, child: bytes != null ? Image.memory(bytes) : Image.network(url))),
            Positioned(top: 8, left: 8, child: SafeArea(child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => Navigator.pop(ctx)))),
            Positioned(top: 8, right: 8, child: SafeArea(child: IconButton(tooltip: 'فتح في تبويب', icon: const Icon(Icons.open_in_new_rounded, color: Colors.white), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final mine = widget.mine;
    final style = TextStyle(fontSize: 14.5, height: 1.55, color: mine ? Joy.bubbleOutText : Joy.text);
    final failed = m.status == MessageStatus.failed;
    final tail = Radius.circular(widget.joinedBelow ? 6 : 4);
    const joined = Radius.circular(6);
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
    final baseColor = mine ? Joy.bubbleOut : Joy.surface2;
    return Column(children: [
      if (widget.dateLabel != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: Text(widget.dateLabel!, style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
        ),
      Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            onTap: failed ? widget.onRetry : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: m.status == MessageStatus.sending ? 0.7 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                margin: EdgeInsets.only(top: widget.joinedAbove ? 1.5 : 4, bottom: widget.joinedBelow ? 1.5 : 4),
                padding: EdgeInsets.fromLTRB(m.mediaKind == 'image' ? 6 : 14, m.mediaKind == 'image' ? 6 : 9, m.mediaKind == 'image' ? 6 : 14, 7),
                decoration: BoxDecoration(
                  color: widget.highlighted ? Joy.sun.withValues(alpha: .7) : baseColor,
                  border: failed ? Border.all(color: Joy.danger) : null,
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: !mine && widget.joinedAbove ? joined : full,
                    topEnd: mine && widget.joinedAbove ? joined : full,
                    bottomStart: mine ? full : tail,
                    bottomEnd: mine ? tail : full,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (m.forwardedFrom != null)
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.forward_rounded, size: 14, color: Joy.textMuted), const SizedBox(width: 4), Text('معاد توجيهها من ${m.forwardedFrom}', style: const TextStyle(fontSize: 11, color: Joy.textMuted, fontStyle: FontStyle.italic))])),
                  if (m.quote != null) _QuoteBox(name: m.quote!.senderName.isNotEmpty ? m.quote!.senderName : widget.peerName, text: m.quote!.preview, onDark: mine, onTap: widget.onQuoteTap),
                  if (m.mediaKind == 'text') Text.rich(TextSpan(style: style, children: _rich(m.content, style))) else _media(m),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (failed)
                      const Text('لم تُرسل · اضغط لإعادة المحاولة', style: TextStyle(fontSize: 10.5, color: Joy.danger, fontWeight: FontWeight.w600))
                    else if (m.status == MessageStatus.sending && m.isMedia)
                      const Text('جارٍ الرفع…', style: TextStyle(fontSize: 10.5, color: Joy.textMuted))
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

/// مشغّل رسالة صوتية: تشغيل/إيقاف، شريط تقدّم، والمدة.
class _AudioBubble extends StatefulWidget {
  final String? url;
  final int? durationMs;
  final bool mine, pending;
  const _AudioBubble({required this.url, this.durationMs, required this.mine, this.pending = false});
  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  AudioPlayer? _player;
  bool _loading = false;
  Object? _err;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url == null) return;
    try {
      if (_player == null) {
        setState(() => _loading = true);
        final p = AudioPlayer();
        await p.setUrl(widget.url!);
        p.playerStateStream.listen((s) { if (s.processingState == ProcessingState.completed) { p.seek(Duration.zero); p.pause(); } });
        setState(() { _player = p; _loading = false; });
      }
      final p = _player!;
      if (p.playing) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _err = e; });
      if (mounted) {
        toast(context, 'تعذر تشغيل التسجيل على هذا الجهاز، سيُفتح في تبويب جديد', error: true);
        launchUrl(Uri.parse(widget.url!), mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.mine ? Joy.bubbleOutText : Joy.text;
    final total = widget.durationMs != null ? Duration(milliseconds: widget.durationMs!) : null;
    final p = _player;
    return SizedBox(
      width: 220,
      child: Row(children: [
        Material(
          color: Joy.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.pending || widget.url == null ? null : _toggle,
            child: SizedBox(
              width: 40, height: 40,
              child: _loading || widget.pending
                  ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2))
                  : StreamBuilder<PlayerState>(
                      stream: p?.playerStateStream,
                      builder: (_, s) => Icon(_err != null ? Icons.error_outline_rounded : (s.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Joy.primary, size: 26),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: p?.positionStream,
            builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = p?.duration ?? total ?? Duration.zero;
              final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                SliderTheme(
                  data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: SliderComponentShape.noOverlay, activeTrackColor: Joy.primary, inactiveTrackColor: color.withValues(alpha: .2), thumbColor: Joy.primary),
                  child: Slider(value: frac, onChanged: p == null ? null : (v) => p.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()))),
                ),
                Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: Text('${fmtDuration(pos)} / ${fmtDuration(dur)}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: color.withValues(alpha: .75)))),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
