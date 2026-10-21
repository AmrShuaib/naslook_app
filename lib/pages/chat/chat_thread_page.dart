import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/biz_api.dart';
import '../../api/chat_cards_api.dart';
import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../api/community_api.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/posts_api.dart';
import '../../api/safety_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/location.dart';
import '../../core/media/media.dart';
import '../../core/media/permissions.dart';
import '../../core/media/voice_record.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/pattern_background.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/reactions.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../business/community_page.dart';
import '../events/events_page.dart';
import '../jobs/job_page.dart';
import '../market/market_page.dart';
import '../posts/post_viewer.dart';
import '../profile/public_profile_page.dart';
import '../wallet/wallet_page.dart';
import 'chat_cards.dart';
import 'live_share.dart';
import 'widgets/audio_bubble.dart';
import 'widgets/bubble.dart';
import 'widgets/composer.dart';
import 'widgets/jump_to_latest.dart';
import 'widgets/reaction_bar.dart';
import 'widgets/suggestion_chips.dart';
import 'widgets/typing_indicator.dart';

export 'widgets/audio_bubble.dart' show fmtDuration;
export 'widgets/composer.dart' show AttachAction;

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

/// الحد الأقصى لتسجيل الرسالة الصوتية.
const maxVoiceDuration = Duration(minutes: 5);
const maxMediaBytes = 30 * 1024 * 1024;

/// مسافة الابتعاد عن نهاية القائمة (تقديراً بالبكسل) التي يظهر بعدها زر «إلى الأحدث».
const jumpToLatestDistance = 600.0;

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

typedef _Media = ({Uint8List bytes, String mime, String name});

class ChatThreadPage extends ConsumerStatefulWidget {
  final Person peer;
  /// رسالة يُقفز إليها بعد التحميل (من نتائج البحث مثلاً).
  final String? initialMessageId;
  /// نص يملأ المؤلّف عند الفتح ولا يُرسل تلقائياً (رمز `#job/…` بعد الإجابة على أسئلة التوظيف مثلاً).
  final String? initialText;
  const ChatThreadPage({super.key, required this.peer, this.initialMessageId, this.initialText});
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
  /// آخر جلب للبيانات الإضافية (يُنتظر قبل إعادة إرسال الصندوق حتى تُعرف clientId للرسائل المحمّلة).
  Future<void>? _metaInFlight;
  /// تفاعلات الرسائل بمعرّف الرسالة (تصل مع البيانات الإضافية وتُحدَّث دورياً)، وعدّاد انبثاق القلب لكل رسالة
  final _reactions = <String, List<Reaction>>{};
  final _bursts = <String, int>{};
  Timer? _reactionsTimer;
  /// رموز الاختصار: نص الرسالة محلّلاً (بمفتاح الرسالة)، والبطاقات المحلولة من الخادم (بمفتاح الرمز)، والطلبات المسجّلة (بمعرّف الرسالة)
  final _parsed = <String, ParsedText>{};
  final _cards = <String, ChatCard?>{};
  final _cardsInFlight = <String>{};
  final _requests = <String, ChatRequest>{};
  final _busyCards = <String>{};
  final _requestRetries = <String, int>{};
  Timer? _requestRetryTimer;
  /// قمم الموجة الصوتية بمفتاح الرسالة (تُحسب مرة من extra.peaks حتى لا تُعاد مع كل بناء).
  final _peaks = <String, List<double>?>{};
  /// مشغّلات الرسائل الصوتية لهذه الصفحة وحدها (محادثة متداخلة فوقها لا تصرفها عند إغلاقها).
  final _players = VoiceNotePlayers();
  /// بايتات الوسائط المحلية قبل/أثناء الرفع (للمعاينة وإعادة المحاولة).
  final _localBytes = <String, _Media>{};
  /// مفاتيح الرسائل التي تدخل بحركة (وصلت أو أُرسلت والمحادثة مفتوحة)؛ تُحذف بعد أول عرض.
  final _animateKeys = <String>{};
  bool _loading = true;
  Object? _error;
  bool _peerTyping = false;
  bool _online = false;
  bool _visible = true;
  bool _atBottom = true;
  bool _farFromEnd = false;
  double _listHeight = 600;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _socketDown = false;
  int _unseen = 0;
  String? _highlightKey;
  Timer? _highlightTimer;
  /// آخر رسالة لي قرأها الطرف الآخر (علامة «شوهدت»).
  String? _seenKey;
  Message? _replyTo;
  // البحث داخل المحادثة
  bool _searching = false;
  final _searchCtl = TextEditingController();
  List<int> _matches = const [];
  int _matchIdx = 0;
  // التسجيل الصوتي
  // جلسة مشتركة مع المجتمع والمنشئ: MediaRecorder على الويب وملف m4a مؤقت على iOS/Android
  VoiceRecordSession? _rec;
  bool _recording = false;
  Duration _recElapsed = Duration.zero;
  Timer? _recTimer;
  StreamSubscription? _sub;
  Timer? _typingTimer, _presenceTimer;
  // صندوق الصادر المحفوظ محلياً (آخر نسخة كُتبت حتى لا نكرر الكتابة)
  String? _outboxSaved;

  String get myId => ref.read(appStateProvider).user?.id ?? '';
  /// رسالتي أم رسالة الطرف الآخر؟ (لا تعتمد على اسم حقل المرسل في النواة؛ انظر [Message.isMine])
  bool _mine(Message m) => m.isMine(myId: myId, peerId: _peerId);
  String get myName => ref.read(appStateProvider).user?.nickname ?? '';
  ApiClient get _api => ref.read(apiClientProvider);
  String get _peerId => widget.peer.id;
  /// مفتاح ثابت لعنصر القائمة: المعرّف المحلي يبقى بعد وصول معرّف الخادم فلا تُعاد الفقاعة.
  String _stableKey(Message m) => m.localId ?? m.id;

  /// طلب ثانوي لا ننتظره ونتجاهل خطأه. (لا `catchError((_) {})`: `setMessageMeta` مُعلنة `Future<void>` لكن
  /// الكائن الفعلي `Future<Map>` فيرمي المعالج ArgumentError عند أول فشل بدل أن يبتلعه.)
  static Future<void> _quiet(Future<void> f) async {
    try {
      await f;
    } catch (_) {}
  }

  /// نقطة توسعة للمدمج: إجراءات إضافية في قائمة المرفقات (مثل «مشاركة موقعي الحي» عبر showLiveShareSheet).
  List<AttachAction> get _extraAttachActions => [
        AttachAction(key: const Key('attach-live'), icon: Icons.my_location_rounded, label: 'موقعي الحي', onTap: () => showLiveShareSheet(context, ref, _peerId)),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positions.itemPositions.addListener(_onPositions);
    final draft = widget.initialText;
    if (draft != null && draft.trim().isNotEmpty) _text.text = draft;
    _load();
    final s = ref.read(socketProvider);
    _sub = s?.events.listen(_onEvent);
    _socketDown = s != null && !s.connected;
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) => _presence());
    _reactionsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshReactions());
    _presence();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    _sub?.cancel();
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    _reactionsTimer?.cancel();
    _requestRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _recTimer?.cancel();
    _rec?.dispose();
    _text.dispose();
    _searchCtl.dispose();
    _players.disposeAll();
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
    var frac = 0.0;
    for (final p in ps) {
      minIdx = math.min(minIdx, p.index);
      maxIdx = math.max(maxIdx, p.index);
      frac += (p.itemTrailingEdge - p.itemLeadingEdge).abs();
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
    // تقدير البعد عن النهاية: العناصر المخفية تحت النافذة × متوسط ارتفاع العنصر الظاهر
    final far = minIdx * (frac / ps.length) * _listHeight > jumpToLatestDistance;
    if (far != _farFromEnd && mounted) setState(() => _farFromEnd = far);
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

  /// يدمج رسائل واردة؛ [animate] للرسائل التي تصل والمحادثة مفتوحة (لا عند التحميل الأول ولا الصفحات الأقدم).
  int _merge(Iterable<Message> incoming, {bool animate = false}) {
    var newFromPeer = 0;
    for (final m in incoming) {
      final k = m.key;
      if (k.isEmpty) continue;
      final old = _byKey[k];
      if (old == null) {
        _byKey[k] = m;
        if (!_mine(m)) newFromPeer++;
        if (animate) _animateKeys.add(_stableKey(m));
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
    for (final m in l) {
      if (m.mediaKind == 'text') _parsed.putIfAbsent(m.key, () => parseChatText(m.content));
    }
    // علامة «شوهدت»: أحدث رسالة لي قرأها الطرف الآخر
    String? seen;
    for (var i = l.length - 1; i >= 0; i--) {
      final m = l[i];
      if (m.readAt != null && m.status == MessageStatus.sent && _mine(m)) {
        seen = m.key;
        break;
      }
    }
    _seenKey = seen;
    if (_searching) _recomputeMatches(keepIndex: true);
    _resolveCards();
    _persistOutbox();
  }

  ParsedText _parsedOf(Message m) => _parsed[m.key] ??= parseChatText(m.content);

  List<double>? _peaksOf(Message m) {
    if (_peaks.containsKey(m.key)) return _peaks[m.key];
    return _peaks[m.key] = peaksFromExtra(m.extra);
  }

  /// يحلّ الإشارات غير المحلولة بعد (ومكان الموعد إن كان دائرة) دفعة واحدة عبر الخادم.
  Future<void> _resolveCards() async {
    final refs = <String>{};
    for (final p in _parsed.values) {
      for (final r in p.refKeys) {
        if (!_cards.containsKey(r) && !_cardsInFlight.contains(r)) refs.add(r);
      }
    }
    if (refs.isEmpty) return;
    final batch = refs.take(40).toList();
    _cardsInFlight.addAll(batch);
    try {
      final res = await _api.chatCards(batch);
      if (!mounted) return;
      setState(() => _cards.addAll(res));
    } catch (_) {
      // تُعاد المحاولة مع أول إعادة بناء
    } finally {
      _cardsInFlight.removeAll(batch);
    }
    if (refs.length > batch.length && mounted) _resolveCards();
  }

  void _noteRequest(String id, dynamic raw) {
    final r = ChatRequest.maybe(raw);
    if (r != null) {
      _requests[id] = r;
      _requestRetries.remove(id);
      return;
    }
    // رسالة أمر بلا طلب مسجّل بعد (سباق بين وصول الرسالة وتسجيل الطلب): نعيد الجلب بعد قليل
    final m = _byKey[id];
    if (m == null || _requests.containsKey(id)) return;
    final cmd = _parsedOf(m).command;
    if (cmd == null || !cmd.kind.needsRequest) return;
    final tries = _requestRetries[id] ?? 0;
    if (tries >= 4) return;
    _requestRetries[id] = tries + 1;
    _requestRetryTimer?.cancel();
    _requestRetryTimer = Timer(Duration(seconds: 2 + tries * 2), () {
      if (!mounted) return;
      _metaFetched.remove(id);
      _fetchMeta();
    });
  }

  /// يجلب بيانات الرد/التوجيه/المدة للرسائل التي لم تُجلب لها بعد.
  Future<void> _fetchMeta() {
    final ids = _messages.where((m) => m.id.isNotEmpty && !m.id.startsWith('local-') && !_metaFetched.contains(m.id)).map((m) => m.id).toList();
    if (ids.isEmpty) return _metaInFlight ?? Future.value();
    _metaFetched.addAll(ids);
    return _metaInFlight = _fetchMetaFor(ids);
  }

  Future<void> _fetchMetaFor(List<String> ids) async {
    try {
      final meta = await _api.messageMeta(ids);
      if (!mounted || meta.isEmpty) return;
      setState(() {
        for (final e in meta.entries) {
          final m = _byKey[e.key];
          if (m != null) {
            _byKey[e.key] = m.withMeta(e.value);
            _peaks.remove(e.key);
          }
          if (e.value['reactions'] != null) _reactions[e.key] = parseReactions(e.value['reactions']);
          _noteRequest(e.key, e.value['request']);
        }
        for (final id in ids) {
          if (!meta.containsKey(id)) _noteRequest(id, null);
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
      _restoreOutbox();
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
      final n = _merge(list, animate: true);
      setState(() {});
      if (n > 0) _onNewFromPeer(n);
    } catch (_) {}
    _refreshReactions();
  }

  /// يجدّد تفاعلات آخر الرسائل (تفاعلات الطرف الآخر لا تصل عبر المقبس)
  Future<void> _refreshReactions() async {
    final ids = _messages.where((m) => m.id.isNotEmpty && !m.id.startsWith('local-')).map((m) => m.id).toList();
    final recent = ids.length > 60 ? ids.sublist(ids.length - 60) : ids;
    if (recent.isEmpty) return;
    try {
      final meta = await _api.messageMeta(recent);
      if (!mounted) return;
      setState(() {
        for (final id in recent) {
          _reactions[id] = parseReactions(meta[id]?['reactions']);
          final r = ChatRequest.maybe(meta[id]?['request']);
          if (r != null) _requests[id] = r;
        }
      });
    } catch (_) {}
  }

  /// تفاعل بإيموجي على رسالة: يُطبَّق محلياً فوراً ثم يُرسل؛ الإيموجي نفسه مرة ثانية يزيله.
  Future<void> _react(Message m, String emoji) async {
    if (m.id.isEmpty || m.id.startsWith('local-')) return;
    final cur = _reactions[m.id] ?? const <Reaction>[];
    final wasMine = cur.any((r) => r.mine && r.emoji == emoji);
    final next = wasMine ? null : emoji;
    setState(() => _reactions[m.id] = applyMyReaction(cur, next));
    try {
      final rx = await _api.chatReact(m.id, next, peerId: _peerId);
      if (mounted) setState(() => _reactions[m.id] = rx);
    } catch (e) {
      if (mounted) {
        setState(() => _reactions[m.id] = cur);
        toast(context, 'تعذر تسجيل التفاعل', error: true);
      }
    }
  }

  /// نقر مزدوج على رسالة: قلب أحمر ينبثق ويُسجَّل ❤️ إن لم يكن مسجّلاً
  void _doubleTap(Message m) {
    if (m.id.isEmpty || m.id.startsWith('local-')) return;
    setState(() => _bursts[m.id] = (_bursts[m.id] ?? 0) + 1);
    final cur = _reactions[m.id] ?? const <Reaction>[];
    if (!cur.any((r) => r.mine && r.emoji == '❤️')) _react(m, '❤️');
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
      final mineFromOtherDevice = _mine(m) && (peerId == _peerId || e['to']?.toString() == _peerId);
      if (fromPeer || mineFromOtherDevice) {
        final n = _merge([m], animate: true);
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
          if (!_mine(m) || m.isPending) continue;
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
  // صندوق الصادر: النصوص غير المرسلة تُحفظ في SharedPreferences (naslife.outbox.<peerId>) وتُعاد محاولتها عند الفتح
  // ---------------------------------------------------------------------------

  String get _outboxKey => 'naslife.outbox.$_peerId';
  /// لا نكتب الصندوق قبل قراءة المحفوظ منه، وإلا محت أول إعادة بناء (قائمة فارغة) ما نجا من الجلسة السابقة.
  bool _outboxReady = false;

  List<Message> _pendingTexts() => [for (final m in _messages) if (m.isPending && m.type == 'text' && !m.isMedia && m.localId != null && _mine(m)) m];

  Future<void> _persistOutbox() async {
    if (!_outboxReady) return;
    final list = _pendingTexts();
    final json = jsonEncode([
      for (final m in list)
        {
          'localId': m.localId,
          'content': m.content,
          'sentAt': m.sentAt?.toIso8601String(),
          'replyTo': m.replyTo,
          'quote': m.quote?.toJson(),
          'forwardedFrom': m.forwardedFrom,
          'extra': m.extra,
        },
    ]);
    if (json == _outboxSaved) return;
    _outboxSaved = json;
    try {
      final sp = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await sp.remove(_outboxKey);
      } else {
        await sp.setString(_outboxKey, json);
      }
    } catch (_) {
      // لا تخزين محلي (اختبارات أو متصفح يمنعه): الرسالة تبقى في القائمة فقط
    }
  }

  Future<void> _restoreOutbox() async {
    var restored = const <Message>[];
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_outboxKey);
      final list = raw == null || raw.isEmpty ? const [] : jsonDecode(raw);
      if (list is! List) return;
      restored = [
        for (final e in list)
          if (e is Map && (e['content'] ?? '').toString().trim().isNotEmpty)
            Message(
              id: '',
              localId: (e['localId'] ?? 'local-${DateTime.now().microsecondsSinceEpoch}').toString(),
              senderId: myId,
              type: 'text',
              content: e['content'].toString(),
              sentAt: DateTime.tryParse(e['sentAt']?.toString() ?? '') ?? DateTime.now(),
              status: MessageStatus.failed,
              replyTo: e['replyTo']?.toString(),
              quote: e['quote'] is Map ? MessageQuote.fromJson(asMap(e['quote'])) : null,
              forwardedFrom: e['forwardedFrom']?.toString(),
              extra: asMap(e['extra']),
            ),
      ];
    } catch (_) {
      // لا تخزين محلي: نكمل بلا صندوق محفوظ
    } finally {
      _outboxReady = true;
    }
    if (!mounted) return;
    // طلب وصل الخادم وضاع ردّه (مهلة أو 500 بعد الحفظ): النسخة في السجل المحمّل الآن، فلا نرسلها ثانية
    try {
      await _metaInFlight;
    } catch (_) {}
    if (!mounted) return;
    restored = [for (final m in restored) if (!_alreadyDelivered(m)) m];
    if (restored.isEmpty) {
      _persistOutbox();
      return;
    }
    setState(() {
      for (final m in restored) {
        _byKey.putIfAbsent(m.key, () => m);
      }
      _rebuild();
    });
    for (final m in restored) {
      if (!mounted) return;
      final cur = _byKey[m.key];
      if (cur == null || !cur.isPending) continue;
      await _send(type: 'text', content: cur.content, retry: cur, quiet: true);
    }
  }

  /// نافذة مطابقة النص عند غياب clientId: رسالة مُرسلة بالنص نفسه من لحظة الإرسال المحلي (بتسامح ثوانٍ لفرق
  /// الساعات) حتى عشر دقائق بعدها.
  static const _deliveredBefore = Duration(seconds: 30), _deliveredAfter = Duration(minutes: 10);

  /// هل توجد نسخة مُرسلة من رسالة الصندوق [local] في السجل المحمّل؟ بمعرّفها المحلي في `extra.clientId` إن أعاده
  /// الخادم، وإلا بالنص نفسه ضمن النافذة الزمنية.
  bool _alreadyDelivered(Message local) {
    final text = local.content.trim();
    final at = local.sentAt;
    for (final m in _messages) {
      if (m.isPending || !_mine(m)) continue;
      if (local.localId != null && m.extra['clientId'] == local.localId) return true;
      if (m.mediaKind != 'text' || m.content.trim() != text) continue;
      final srvAt = m.sentAt;
      if (at == null || srvAt == null) return true;
      final d = srvAt.difference(at);
      if (d >= -_deliveredBefore && d <= _deliveredAfter) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // الإرسال: نص أو وسائط، متفائل، مع رد مقتبس أو إعادة توجيه
  // ---------------------------------------------------------------------------

  Future<void> _sendText() async {
    var t = _text.text.trim();
    if (t.isEmpty) return;
    // تحقق مسبق من الكلمات المحظورة (رسائل النواة لا تمر بفلتر الخادم)
    final banned = bannedWordIn(t, ref.read(bannedWordsProvider).valueOrNull ?? const []);
    if (banned != null) {
      toast(context, 'الرسالة تحتوي كلمة غير مسموحة: «$banned»', error: true);
      return;
    }
    if (t.startsWith('/')) {
      final prepared = await _prepareCommand(t);
      if (prepared == null || !mounted) return;
      t = prepared;
    }
    _text.clear();
    final cmd = parseCommand(t);
    await _send(type: 'text', content: t, onSent: cmd != null && cmd.kind.needsRequest ? (id) => _registerRequest(id, cmd) : null);
  }

  // ---------------------------------------------------------------------------
  // رموز الاختصار: تحضير الأوامر قبل الإرسال، تسجيل الطلبات، وإجراءات البطاقات
  // ---------------------------------------------------------------------------

  /// يوسّع الأوامر التي تحتاج شيئاً من الجهاز أو المستخدم قبل الإرسال (/me، /loc، /ticket، /order، /wish، /send، /help)،
  /// ويتحقق من حجج البقية. يرجع النص الجاهز للإرسال أو null للإلغاء.
  Future<String?> _prepareCommand(String t) async {
    final m = RegExp(r'^/([a-zA-Z؀-ۿ]+)\s*(.*)$', dotAll: true).firstMatch(t);
    if (m == null) return t;
    final cmd = m.group(1)!.toLowerCase();
    final rest = m.group(2)!.trim();
    // أوامر المال مغلقة في iOS أو بقرار المنصة: لا تُرسل ولا تُسجَّل
    if (isMoneyCommand(t) && !ref.read(chatMoneyEnabledProvider)) {
      toast(context, 'غير متاح', error: true);
      return null;
    }
    switch (cmd) {
      case 'help':
      case 'دليل':
        await _openGuide();
        return null;
      case 'me':
        if (myName.isEmpty) { toast(context, 'لا يوجد نك نيم لحسابك', error: true); return null; }
        return '@$myName${rest.isEmpty ? '' : ' $rest'}';
      case 'loc':
        if (rest.isNotEmpty && parseCommand(t) != null) return t;
        final loc = await DeviceLocation.current();
        if (!mounted) return null;
        if (loc == null) { toast(context, 'تعذّر تحديد موقعك؛ اسمح بالوصول إلى الموقع ثم أعد المحاولة', error: true); return null; }
        return '/loc ${loc.latitude.toStringAsFixed(5)},${loc.longitude.toStringAsFixed(5)}${rest.isEmpty ? '' : ' $rest'}';
      case 'ticket':
        return pickTicketCode(context, _api);
      case 'order':
        return pickOrderCode(context, _api);
      case 'wish':
        return pickWishCode(context, _api);
      case 'send':
        final code = parseCommand(t);
        if (code == null) { toast(context, 'الصيغة: /send المبلغ [السبب]', error: true); return null; }
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد التحويل'),
            content: Text('تحويل ${money(code.amount)} من محفظتك إلى ${widget.peer.nickname}${code.note.isEmpty ? '' : ' · ${code.note}'}؟'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('send-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('حوّل'))],
          ),
        );
        if (ok != true || !mounted) return null;
        try {
          await _api.walletTransfer(_peerId, code.amount, note: code.note);
        } catch (e) {
          if (mounted) toast(context, e is ApiException && e.message.contains('insufficient') ? 'رصيد محفظتك لا يكفي' : 'لم يتم التحويل: ${errText(e)}', error: true);
          return null;
        }
        return t;
      case 'pay':
      case 'split':
      case 'meet':
      case 'invite':
        if (parseCommand(t) != null) return t;
        final e = commandCatalog.firstWhere((c) => c.trigger == '/$cmd');
        toast(context, 'الصيغة: ${e.hint} · مثال: ${e.example}', error: true);
        return null;
      default:
        return t;
    }
  }

  /// بعد وصول معرّف الرسالة من الخادم: يسجّل الطلب (مبلغ/تقسيم/موعد/إرسال) حتى يتمكن الطرف الآخر من الرد بزر واحد.
  Future<void> _registerRequest(String messageId, ChatCode code) async {
    try {
      final r = await _api.chatRequest(messageId: messageId, peerId: _peerId, kind: code.kind.name, amount: code.amount, n: code.n, note: code.note, when: code.kind == CodeKind.meet ? code.note : '', place: code.place);
      if (mounted) setState(() => _requests[messageId] = r);
    } catch (e) {
      if (mounted) toast(context, 'أُرسلت الرسالة لكن لم يُسجَّل الطلب: ${errText(e)}', error: true);
    }
  }

  Future<void> _openGuide() async {
    final s = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ChatCodesGuidePage(canInsert: true)));
    if (s != null && mounted) _insertText(s);
  }

  /// يضع نصاً في حقل الكتابة (يستبدل الحالي) ويضع المؤشر في نهايته.
  void _insertText(String s) {
    _text.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }

  /// يستبدل جزءاً من النص الحالي (اقتراح الإكمال).
  void _replaceRange(int start, int end, String insert) {
    final t = _text.text;
    final a = start.clamp(0, t.length), b = end.clamp(a, t.length);
    final next = t.replaceRange(a, b, insert);
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: a + insert.length));
  }

  Future<void> _codeMenu(String result) async {
    if (result == 'guide') return _openGuide();
    if (result.startsWith('insert:')) {
      final s = result.substring(7);
      final cur = _text.text;
      _insertText(cur.isEmpty || s.startsWith('/') ? s : '$cur${cur.endsWith(' ') ? '' : ' '}$s');
      return;
    }
    String? code;
    switch (result) {
      case 'picker:ticket': code = await pickTicketCode(context, _api);
      case 'picker:order': code = await pickOrderCode(context, _api);
      case 'picker:wish': code = await pickWishCode(context, _api);
    }
    if (code != null && mounted) _insertText(code);
  }

  Future<void> _runCard(String key, Future<void> Function() fn) async {
    if (_busyCards.contains(key)) return;
    setState(() => _busyCards.add(key));
    try {
      await fn();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyCards.remove(key));
    }
  }

  /// إجراء من بطاقة رمز داخل رسالة.
  Future<void> _onCode(Message m, ChatCode code, String action) async {
    final card = code.ref == null ? null : _cards[code.ref!];
    final nav = Navigator.of(context);
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: card?.code ?? code.raw));
        if (mounted) toast(context, 'نُسخ');
      case 'directions':
        if (code.lat != null) await openDirections(code.lat!, code.lng!);
      case 'wallet':
        nav.push(MaterialPageRoute(builder: (_) => const WalletPage()));
      case 'share-loc':
        final loc = await DeviceLocation.current();
        if (!mounted) return;
        if (loc == null) { toast(context, 'تعذّر تحديد موقعك', error: true); return; }
        await _send(type: 'text', content: '/loc ${loc.latitude.toStringAsFixed(5)},${loc.longitude.toStringAsFixed(5)}');
      case 'counter':
        _insertText('/meet ');
      case 'pay':
        if (!ref.read(chatMoneyEnabledProvider)) { toast(context, 'غير متاح', error: true); return; }
        final r = _requests[m.id];
        if (r == null) { toast(context, 'الطلب لم يُسجَّل بعد، حاول بعد لحظة'); _metaFetched.remove(m.id); _fetchMeta(); return; }
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الدفع'),
            content: Text('دفع ${money(r.share)} من محفظتك إلى ${widget.peer.nickname}${r.note.isEmpty ? '' : ' · ${r.note}'}؟'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('pay-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('ادفع'))],
          ),
        );
        if (ok != true || !mounted) return;
        await _runCard(m.id, () async {
          try {
            final res = await _api.chatRequestPay(m.id);
            if (mounted) { setState(() => _requests[m.id] = res); toast(context, 'تم الدفع ✓'); }
          } on ApiException catch (e) {
            if (!mounted) return;
            if (e.message.contains('insufficient')) { toast(context, 'رصيد محفظتك لا يكفي', error: true); } else { rethrow; }
          }
        });
      case 'accept':
      case 'decline':
      case 'cancel':
        if (!_requests.containsKey(m.id)) { toast(context, 'الطلب لم يُسجَّل بعد، حاول بعد لحظة'); return; }
        await _runCard(m.id, () async {
          final res = switch (action) { 'accept' => await _api.chatRequestAccept(m.id), 'decline' => await _api.chatRequestDecline(m.id), _ => await _api.chatRequestCancel(m.id) };
          if (mounted) setState(() => _requests[m.id] = res);
        });
      case 'join':
        if (card == null) return;
        if (card.type == 'event') { nav.push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: card.id))); return; }
        await _runCard(code.raw, () async {
          try { await _api.followBiz(card.id); invalidateBiz(ref, card.id); } catch (_) {}
          if (mounted) nav.push(MaterialPageRoute(builder: (_) => BusinessPage(id: card.id)));
        });
      case 'chat':
        if (card?.type != 'user') return;
        if (card!.id == _peerId) { toast(context, 'أنت في محادثته الآن'); return; }
        if (card.id == myId) { toast(context, 'هذا حسابك'); return; }
        nav.push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: Person(id: card.id, nickname: card.title, avatarUrl: card.image))));
      case 'discuss':
        if (card?.type != 'item' || card!.bizId == null) return;
        nav.push(MaterialPageRoute(builder: (_) => CommunityPage(bizId: card.bizId!, title: card.subtitle, initialItem: CommunityItemRef(id: card.id, title: card.title, price: card.price ?? 0, unit: card.kind ?? 'item', kind: card.kind ?? 'product', imageUrl: card.image))));
      case 'place':
      case 'open':
        if (card == null) return;
        switch (card.type) {
          case 'user': nav.push(MaterialPageRoute(builder: (_) => PublicProfilePage(handle: card.title)));
          case 'biz': nav.push(MaterialPageRoute(builder: (_) => BusinessPage(id: card.id)));
          case 'item': nav.push(MaterialPageRoute(builder: (_) => BusinessPage(id: card.bizId ?? card.id)));
          case 'order': nav.push(MaterialPageRoute(builder: (_) => BusinessPage(id: card.bizId ?? card.id)));
          case 'event': nav.push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: card.id)));
          case 'ticket': nav.push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: card.eventId ?? card.id)));
          case 'listing': nav.push(MaterialPageRoute(builder: (_) => ListingPage(card.id)));
          case 'job': nav.push(MaterialPageRoute(builder: (_) => JobPage(id: card.id)));
          case 'space': nav.push(MaterialPageRoute(builder: (_) => CommunityPage(bizId: card.bizId ?? card.id, title: card.title)));
          case 'spacepost': nav.push(MaterialPageRoute(builder: (_) => CommunityPage(bizId: card.bizId ?? '', title: card.subtitle, initialPostId: card.id)));
          case 'post':
            await _runCard(code.raw, () async {
              final p = await _api.mapPost(card.id);
              if (mounted) await PostViewerPage.open(context, [p]);
            });
        }
    }
  }

  /// يرفع ملف وسائط؛ للصوت يقرأ قمم الموجة من ردّ الخادم الخام (extra.peaks) إن أعادها.
  Future<({String url, List<double>? peaks})> _upload(_Media media) async {
    if (!media.mime.startsWith('audio/')) {
      final up = await _api.uploadMedia(media.bytes, contentType: media.mime, fileName: media.name);
      return (url: up.url, peaks: null);
    }
    // اسم لاتيني فقط في الترويسة (كما في uploadMedia)
    final safeName = RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(media.name) ? media.name : null;
    Map<String, dynamic> d;
    try {
      d = await _api.postBytes('/chat/upload', media.bytes, contentType: media.mime, headers: {if (safeName != null) 'x-file-name': safeName}, timeout: const Duration(minutes: 3));
    } on ApiException catch (e) {
      if (!e.isNetwork || safeName == null) rethrow;
      d = await _api.postBytes('/chat/upload', media.bytes, contentType: media.mime, timeout: const Duration(minutes: 3));
    }
    final url = (d['url'] ?? '').toString();
    if (url.isEmpty) throw const ApiException(500, 'الخادم لم يُرجع رابط الملف');
    final raw = d['peaks'];
    final peaks = raw is List ? [for (final v in raw) if (v is num) v.toDouble().clamp(0.0, 1.0)] : const <double>[];
    return (url: url, peaks: peaks.length >= 8 ? peaks : null);
  }

  Future<void> _send({
    required String type,
    required String content,
    _Media? media,
    Map<String, dynamic>? extra,
    Message? retry,
    Future<void> Function(String serverId)? onSent,
    bool quiet = false,
  }) async {
    final quote = retry?.quote ?? (_replyTo == null ? null : MessageQuote(id: _replyTo!.key, senderId: _replyTo!.senderId, senderName: _mine(_replyTo!) ? 'أنت' : widget.peer.nickname, type: _replyTo!.mediaKind, content: _replyTo!.mediaKind == 'text' ? _replyTo!.content : ''));
    final local = retry?.copyWith(status: MessageStatus.sending) ??
        Message(id: '', localId: 'local-${DateTime.now().microsecondsSinceEpoch}', senderId: myId, type: type, content: content, sentAt: DateTime.now(),
            status: MessageStatus.sending, quote: quote, replyTo: quote?.id, extra: extra ?? const {});
    if (retry == null && media != null) _localBytes[local.key] = media;
    if (retry == null) {
      _animateKeys.add(_stableKey(local));
      setState(() => _replyTo = null);
    }
    setState(() { _byKey[local.key] = local; _rebuild(); });
    _jumpToBottom();
    try {
      var body = local.content;
      var localExtra = local.extra;
      final pending = _localBytes[local.key];
      if (body.isEmpty && pending != null) {
        final up = await _upload(pending);
        body = up.url;
        if (!mounted) return;
        if (up.peaks != null) localExtra = {...localExtra, 'peaks': up.peaks};
        setState(() { _byKey[local.key] = local.copyWith(content: body, extra: localExtra); _rebuild(); });
      }
      if (body.isEmpty) throw const ApiException(0, 'لا محتوى للإرسال');
      // الخادم الأساسي يقبل النص فقط: الوسائط تُرسل كرابط مطلق ويُستنتج نوعها من امتداده
      if (local.type != 'text') body = _api.absolute(body);
      // clientId = المعرّف المحلي: يميّز النسخ عند إعادة الإرسال من الصندوق (ويتيح للخادم إزالة التكرار لاحقاً)
      final extra = {...localExtra, if (local.type != 'text') 'kind': local.type, if (local.localId != null) 'clientId': local.localId};
      final m = await _api.sendMessage(_peerId, body, type: 'text', replyTo: local.replyTo, quote: local.quote, forwardedFrom: local.forwardedFrom, extra: extra);
      if (!mounted) return;
      final serverId = m.id.isNotEmpty && m.senderId != 'me' ? m.id : null;
      final sent = (serverId != null ? m : local).copyWith(
        id: serverId ?? local.key, status: MessageStatus.sent, localId: local.localId, sentAt: m.sentAt ?? local.sentAt, content: body,
        quote: local.quote, replyTo: local.replyTo, forwardedFrom: local.forwardedFrom, extra: {...extra, ...m.extra},
      );
      setState(() {
        _byKey.remove(local.key);
        _peaks.remove(local.key);
        _byKey[sent.key] = sent;
        _metaFetched.add(sent.id);
        _rebuild();
      });
      if (serverId != null && (local.quote != null || local.forwardedFrom != null || extra.isNotEmpty)) {
        _quiet(_api.setMessageMeta(serverId, peerId: _peerId, replyTo: local.replyTo, quote: local.quote, forwardedFrom: local.forwardedFrom, extra: extra));
      }
      if (serverId != null && onSent != null) await onSent(serverId);
      ref.invalidate(chatsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() { _byKey[local.key] = _byKey[local.key]!.copyWith(status: MessageStatus.failed); _rebuild(); });
      if (!quiet) toast(context, 'لم تُرسل الرسالة: ${errText(e)}', error: true);
    }
  }

  void _discard(Message m) => setState(() { _byKey.remove(m.key); _localBytes.remove(m.key); _rebuild(); });

  // ---- المرفقات (قائمتها في ChatComposer: الرموز الذكية ثم هذه الإجراءات ثم نقطة توسعة المدمج)
  List<AttachAction> get _attachActions => [
        AttachAction(icon: Icons.photo_library_outlined, label: 'صورة من المعرض', onTap: () => _pickAndSend('image')),
        AttachAction(icon: Icons.photo_camera_outlined, label: 'التقاط صورة', onTap: () => _pickAndSend('camera')),
        AttachAction(icon: Icons.videocam_outlined, label: 'فيديو', color: Joy.accent, onTap: () => _pickAndSend('video')),
      ];

  Future<void> _pickAndSend(String choice) async {
    try {
      _Media picked;
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
  /// يبدأ التسجيل ويرجع true إن بدأ فعلاً (المؤلّف يلغي فوراً إن رُفع الإصبع قبل ذلك، ويتجاهل الفشل).
  Future<bool> _startRecording() async {
    if (_recording) return false;
    try {
      final rec = _rec ??= VoiceRecordSession();
      await rec.start(); // يطلب إذن الميكروفون أولاً
      if (!mounted) {
        await rec.cancel();
        return false;
      }
      setState(() { _recording = true; _recElapsed = Duration.zero; });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recElapsed += const Duration(seconds: 1));
        if (_recElapsed >= maxVoiceDuration) _stopRecording(send: true);
      });
      return true;
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return false;
      toast(context, 'تعذر بدء التسجيل: ${errText(e)}', error: true);
      return false;
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final elapsed = _recElapsed;
    if (!_recording) return;
    setState(() => _recording = false);
    try {
      _Media? media;
      final rec = _rec;
      if (rec == null) return;
      if (!send) { await rec.cancel(); return; }
      final v = await rec.stop();
      if (v != null) media = (bytes: v.bytes, mime: v.mime, name: v.name);
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
    final from = _mine(m) ? myName : widget.peer.nickname;
    // النسخة المعاد توجيهها رسالة جديدة: لا تحمل clientId الأصل
    final extra = {...m.extra}..remove('clientId');
    try {
      final sent = await _api.sendMessage(target.id, m.type == 'text' ? m.content : _api.absolute(m.content), type: 'text', forwardedFrom: from, extra: extra);
      if (sent.id.isNotEmpty && sent.senderId != 'me') {
        _quiet(_api.setMessageMeta(sent.id, peerId: target.id, forwardedFrom: from, extra: extra.isEmpty ? null : extra));
        if (target.id == _peerId && mounted) setState(() { _merge([sent.copyWith(forwardedFrom: from, extra: extra)], animate: true); });
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
    final mine = _mine(m);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            // شريط التفاعلات أعلى الخيارات (كما في واتساب)
            if (m.status == MessageStatus.sent && !m.id.startsWith('local-'))
              ReactionBar(
                selected: (_reactions[m.id] ?? const <Reaction>[]).where((r) => r.mine).firstOrNull?.emoji,
                onPick: (e) => Navigator.pop(ctx, 'react:$e'),
              ),
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
    if (action.startsWith('react:')) return _react(m, action.substring(6));
    switch (action) {
      case 'reply':
        setState(() => _replyTo = m);
      case 'forward':
        await _forward(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (mounted) toast(context, 'نُسخ النص');
      case 'open':
        await launchUrl(Uri.parse(_api.media(m.content)), mode: LaunchMode.externalApplication);
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
    final r = await showReportSheet(context, ref, type: kReportUser, id: _peerId, author: widget.peer, messageId: messageId,
        title: messageId != null ? 'إبلاغ عن الرسالة' : 'إبلاغ عن ${widget.peer.nickname}');
    if (r != null && r.blocked && mounted) {
      ref.invalidate(chatsProvider);
      ref.invalidate(contactsProvider);
      Navigator.of(context).pop();
    }
  }

  /// كتم إشعارات هذه المحادثة (بلا شارة) لمدة أو دائماً، أو إلغاء الكتم.
  Future<void> _toggleMute() async {
    final muted = ref.read(mutedPeersProvider).contains(_peerId);
    try {
      if (muted) {
        await _api.unmute(_peerId);
        ref.invalidate(mutesProvider);
        if (mounted) toast(context, 'أُلغي كتم ${widget.peer.nickname}');
        return;
      }
      final hours = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('كتم الإشعارات', style: TextStyle(fontWeight: FontWeight.w700))),
            ListTile(leading: const Icon(Icons.schedule_rounded), title: const Text('8 ساعات'), onTap: () => Navigator.pop(ctx, 8)),
            ListTile(leading: const Icon(Icons.calendar_view_week_rounded), title: const Text('أسبوع'), onTap: () => Navigator.pop(ctx, 24 * 7)),
            ListTile(leading: const Icon(Icons.volume_off_rounded), title: const Text('دائماً'), onTap: () => Navigator.pop(ctx, 0)),
          ]),
        ),
      );
      if (hours == null || !mounted) return;
      await _api.mute(_peerId, hours: hours == 0 ? null : hours);
      ref.invalidate(mutesProvider);
      if (mounted) toast(context, 'كُتمت إشعارات ${widget.peer.nickname}');
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
      // قائمة المحظورين تصفّي منشورات الدوائر وتعليقاتها وشارة «محظور» في الملف، فتُحدَّث فوراً
      ref.invalidate(blockedUsersProvider);
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
          child: InkWell(
            onTap: () => openProfile(context, widget.peer),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.peer.nickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_peerTyping ? 'يكتب…' : (_online ? 'متصل الآن' : 'غير متصل'), style: TextStyle(fontSize: 12, color: _online || _peerTyping ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w400)),
            ]),
          ),
        ),
      ]),
      actions: [
        IconButton(tooltip: 'بحث', icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
        PopupMenuButton<String>(
          tooltip: 'المزيد',
          onSelected: (v) => v == 'report' ? _report() : v == 'mute' ? _toggleMute() : _block(),
          itemBuilder: (_) {
            final muted = ref.read(mutedPeersProvider).contains(_peerId);
            return [
              PopupMenuItem(value: 'mute', child: ListTile(leading: Icon(muted ? Icons.volume_up_outlined : Icons.volume_off_outlined), title: Text(muted ? 'إلغاء كتم الإشعارات' : 'كتم الإشعارات'))),
              const PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ'))),
              const PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر', style: TextStyle(color: Joy.danger)))),
            ];
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bannedWordsProvider); // تُجلب مبكراً حتى يعمل التحقق المسبق عند أول رسالة
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
        Expanded(
          child: NaslifePattern(
            child: Stack(children: [
              LayoutBuilder(builder: (_, c) {
                _listHeight = c.maxHeight.isFinite && c.maxHeight > 0 ? c.maxHeight : _listHeight;
                return _list();
              }),
              PositionedDirectional(
                bottom: 12,
                end: 14,
                child: JumpToLatest(
                  visible: !_loading && (_farFromEnd || _unseen > 0),
                  count: _unseen,
                  onTap: () { setState(() => _unseen = 0); _jumpToBottom(); _markRead(); },
                ),
              ),
            ]),
          ),
        ),
        // «يكتب…» كفقاعة واردة بثلاث نقاط أسفل القائمة
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _peerTyping ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: TypingIndicator(peer: widget.peer)) : const SizedBox(width: double.infinity),
        ),
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
        final stable = _stableKey(m);
        return ChatBubble(
          m,
          key: ValueKey(stable),
          mine: _mine(m),
          peer: widget.peer,
          dateLabel: showDate && m.sentAt != null ? dayLabel(m.sentAt!) : null,
          joinedAbove: prev != null && !showDate && prev.senderId == m.senderId && _close(prev.sentAt, m.sentAt),
          joinedBelow: next != null && _sameDay(m.sentAt, next.sentAt) && next.senderId == m.senderId && _close(m.sentAt, next.sentAt),
          highlighted: _highlightKey == m.key,
          animateIn: _animateKeys.contains(stable),
          onEntered: () => _animateKeys.remove(stable),
          seen: _seenKey == m.key,
          searchQuery: q,
          localBytes: _localBytes[m.key]?.bytes,
          mediaUrl: m.content.isEmpty ? null : _api.media(m.content),
          onLongPress: () => _actions(m),
          onDoubleTap: () => _doubleTap(m),
          onSwipeReply: m.status == MessageStatus.sent ? () => setState(() => _replyTo = m) : null,
          onReactionTap: (e) => _react(m, e),
          reactions: _reactions[m.id] ?? const <Reaction>[],
          heartTrigger: _bursts[m.id] ?? 0,
          onRetry: () => _send(type: m.type, content: m.content, retry: m),
          onQuoteTap: m.quote == null ? null : () { if (!_jumpToKey(m.quote!.id)) _revealMessage(m.quote!.id); },
          parsed: m.mediaKind == 'text' ? _parsedOf(m) : null,
          peaks: m.mediaKind == 'audio' ? _peaksOf(m) : null,
          players: _players,
          cards: _cards,
          resolvedRefs: _cards.keys.toSet(),
          request: _requests[m.id],
          busy: _busyCards.contains(m.id),
          onCode: (c, a) => _onCode(m, c, a),
        );
      },
    );
  }

  Widget _composer() => ChatComposer(
        controller: _text,
        onSend: _sendText,
        onChanged: (v) { if (v.isNotEmpty) ref.read(socketProvider)?.typing(_peerId); },
        attachActions: _attachActions,
        extraAttachActions: _extraAttachActions,
        onCode: _codeMenu,
        codeSuggestions: CodeSuggestions(
          controller: _text,
          people: _people(),
          onInsert: _replaceRange,
          onAction: (a) => _codeMenu(a == 'guide' ? 'guide' : a),
        ),
        // ردود مقترحة (ثلاث رقائق عربية) تظهر بعد رسالة من الطرف الآخر؛ اختيار رقاقة يضعها في الحقل
        above: SuggestionChips(peerId: _peerId, messages: _messages, onPick: _insertText),
        replyName: _replyTo == null ? null : (_mine(_replyTo!) ? 'أنت' : widget.peer.nickname),
        replyText: _replyTo?.preview,
        onCancelReply: () => setState(() => _replyTo = null),
        recording: _recording,
        recElapsed: _recElapsed,
        maxRecord: maxVoiceDuration,
        onStartRecording: _startRecording,
        onStopRecording: ({required bool send}) => _stopRecording(send: send),
      );

  /// الأشخاص المعروفون للإكمال بعد @: الطرف الآخر وجهات الاتصال والمحادثات.
  List<Person> _people() {
    final chats = ref.read(chatsProvider).valueOrNull ?? const <Chat>[];
    final contacts = ref.read(contactsProvider).valueOrNull ?? const <Person>[];
    final people = <String, Person>{widget.peer.id: widget.peer, for (final c in chats) c.peer.id: c.peer, for (final p in contacts) p.id: p};
    return people.values.toList();
  }

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
