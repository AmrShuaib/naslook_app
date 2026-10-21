import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/chat_cards_api.dart';
import '../../../api/client.dart' show mediaUrl, thumbUrl;
import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../core/chat/codes.dart';
import '../../../core/media/native_io.dart' show isNativeMobile;
import '../../../core/media/video_view.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/reactions.dart';
import '../../../ui/widgets.dart';
import '../chat_cards.dart';
import 'audio_bubble.dart';
import 'day_pill.dart';
import 'seen_marker.dart';

final _urlRe = RegExp(r'(https?://[^\s<>]+|www\.[^\s<>]+)', caseSensitive: false);

/// لون علامتي القراءة على الفقاعة الصادرة الداكنة (أزرق مائل إلى الأبيض).
const _tickRead = Color(0xFF9BE8FF);

/// صندوق الاقتباس داخل الفقاعة أو فوق حقل الكتابة؛ [onDark] فوق تدرّج الفقاعة الصادرة.
class QuoteBox extends StatelessWidget {
  final String name, text;
  final bool compact, onDark;
  final VoidCallback? onTap;
  const QuoteBox({super.key, required this.name, required this.text, this.compact = false, this.onDark = false, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: onDark ? Colors.white.withValues(alpha: .14) : Joy.primarySoft.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(10),
            border: BorderDirectional(start: BorderSide(color: onDark ? Colors.white.withValues(alpha: .85) : Joy.primary, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: onDark ? Colors.white : Joy.primary)),
            Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: onDark ? Colors.white.withValues(alpha: .85) : Joy.textMuted)),
          ]),
        ),
      );
}

/// فقاعة رسالة: نص بروابط ورموز، اقتباس، إعادة توجيه، وسائط، حالة الإرسال، تفاعلات، ضغط مطوّل ونقر مزدوج وسحب للرد.
/// الواردة بيضاء بإطار وصورة المرسل بجانب أول فقاعة في مجموعته؛ الصادرة تدرّج فيروزي بنص أبيض بلا صورة.
class ChatBubble extends StatefulWidget {
  final Message m;
  final bool mine;
  final Person peer;
  final String? dateLabel;
  /// الفقاعة ملتصقة بما قبلها/بعدها (المرسل نفسه خلال دقائق): يضبط الفراغ والذيل والصورة.
  final bool joinedAbove, joinedBelow;
  final bool highlighted;
  /// دخول متحرك (تلاشٍ وانزلاق 12 نقطة) للرسائل التي تصل أو تُرسل والمحادثة مفتوحة.
  final bool animateIn;
  /// آخر رسالة لي قرأها الطرف الآخر: تُعرض علامة «شوهدت» تحتها.
  final bool seen;
  final String searchQuery;
  final Uint8List? localBytes;
  final String? mediaUrl;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final VoidCallback? onQuoteTap, onDoubleTap, onSwipeReply, onEntered;
  final ValueChanged<String>? onReactionTap;
  final List<Reaction> reactions;
  final int heartTrigger;
  /// رموز الاختصار في النص وبطاقاتها المحلولة وطلبها المسجّل
  final ParsedText? parsed;
  final Map<String, ChatCard?> cards;
  final Set<String> resolvedRefs;
  final ChatRequest? request;
  final bool busy;
  final CodeAction? onCode;
  /// قمم الموجة الصوتية (من extra.peaks) إن وُجدت.
  final List<double>? peaks;
  const ChatBubble(this.m,
      {super.key,
      required this.mine,
      required this.peer,
      this.dateLabel,
      this.joinedAbove = false,
      this.joinedBelow = false,
      this.highlighted = false,
      this.animateIn = false,
      this.seen = false,
      this.searchQuery = '',
      this.localBytes,
      this.mediaUrl,
      required this.onLongPress,
      required this.onRetry,
      this.onQuoteTap,
      this.onDoubleTap,
      this.onSwipeReply,
      this.onEntered,
      this.onReactionTap,
      this.reactions = const [],
      this.heartTrigger = 0,
      this.parsed,
      this.cards = const {},
      this.resolvedRefs = const {},
      this.request,
      this.busy = false,
      this.onCode,
      this.peaks});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Color get _linkColor => widget.mine ? Joy.primaryOn : Joy.primary;

  /// النص مع الروابط، وأجزاء الرموز (إشارات) مميّزة وقابلة للنقر.
  List<InlineSpan> _rich(String text, TextStyle style) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final refs = widget.parsed?.refs ?? const <ChatCode>[];
    if (refs.isEmpty) return _richPlain(text, style);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final c in refs) {
      if (c.start < last) continue;
      if (c.start > last) spans.addAll(_richPlain(text.substring(last, c.start), style));
      final rec = TapGestureRecognizer()..onTap = () => widget.onCode?.call(c, 'open');
      _recognizers.add(rec);
      spans.add(TextSpan(text: text.substring(c.start, c.end), style: style.copyWith(color: _linkColor, fontWeight: FontWeight.w700), recognizer: rec));
      last = c.end;
    }
    if (last < text.length) spans.addAll(_richPlain(text.substring(last), style));
    return spans;
  }

  List<InlineSpan> _richPlain(String text, TextStyle style) {
    final q = widget.searchQuery.toLowerCase();
    final hl = style.copyWith(backgroundColor: Joy.sun.withValues(alpha: .55), color: Joy.text);
    List<InlineSpan> plain(String s) {
      if (q.isEmpty) return [TextSpan(text: s)];
      final out = <InlineSpan>[];
      var i = 0;
      final lower = s.toLowerCase();
      while (true) {
        final j = lower.indexOf(q, i);
        if (j < 0) {
          out.add(TextSpan(text: s.substring(i)));
          break;
        }
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
      spans.add(TextSpan(text: raw, style: style.copyWith(decoration: TextDecoration.underline, decorationColor: _linkColor, color: _linkColor, fontWeight: FontWeight.w600), recognizer: rec));
      last = match.end;
    }
    if (last < text.length) spans.addAll(plain(text.substring(last)));
    return spans;
  }

  Widget _media(Message m) {
    final url = widget.mediaUrl;
    switch (m.mediaKind) {
      case 'image':
        final tag = 'chat-img-${m.key}';
        final img = widget.localBytes != null
            ? Image.memory(widget.localBytes!, fit: BoxFit.cover)
            : url == null
                ? const SizedBox(width: 200, height: 120)
                : Image.network(
                    thumbUrl(url),
                    fit: BoxFit.cover,
                    // تظهر بتلاشٍ عند اكتمال تحميلها بدل القفز
                    frameBuilder: (_, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 280), curve: Curves.easeOut, child: child),
                    loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(width: 200, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 120, child: Icon(Icons.broken_image_outlined, color: Joy.textMuted)),
                  );
        return GestureDetector(
          onTap: url == null ? null : () => _viewImage(context, url, widget.localBytes, tag),
          child: Hero(
            tag: tag,
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320), child: img)),
          ),
        );
      case 'audio':
        return AudioBubble(url: url, durationMs: m.durationMs, mine: widget.mine, pending: m.isPending, peaks: widget.peaks, seed: m.key);
      case 'video':
        // يُشغَّل داخل التطبيق بملء الشاشة بدل فتحه خارجه
        return InkWell(
          key: const Key('chat-video'),
          onTap: url == null ? null : () => isNativeMobile ? openVideoFullScreen(context, url) : launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: 220,
            height: 130,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: widget.mine ? .18 : .06), borderRadius: BorderRadius.circular(14)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_circle_fill_rounded, size: 44, color: widget.mine ? Joy.primaryOn : Joy.primary),
              const SizedBox(height: 4),
              Text('فيديو · اضغط للتشغيل', style: TextStyle(fontSize: 12, color: widget.mine ? Colors.white70 : Joy.textMuted)),
            ]),
          ),
        );
      default:
        final c = widget.mine ? Joy.primaryOn : Joy.text;
        return InkWell(
          onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.attach_file_rounded, size: 18, color: c.withValues(alpha: .7)),
            const SizedBox(width: 6),
            Text(m.content.split('/').last, style: TextStyle(decoration: TextDecoration.underline, color: c)),
          ]),
        );
    }
  }

  void _viewImage(BuildContext context, String url, Uint8List? bytes, String tag) => Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, __) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Center(child: InteractiveViewer(maxScale: 5, child: Hero(tag: tag, child: bytes != null ? Image.memory(bytes) : Image.network(mediaUrl(url))))),
            Positioned(top: 8, left: 8, child: SafeArea(child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => Navigator.pop(ctx)))),
            Positioned(top: 8, right: 8, child: SafeArea(child: IconButton(tooltip: 'فتح خارج التطبيق', icon: const Icon(Icons.open_in_new_rounded, color: Colors.white), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)))),
          ]),
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final mine = widget.mine;
    final style = TextStyle(fontSize: 16, height: 1.45, color: mine ? Joy.primaryOn : Joy.text);
    final failed = m.status == MessageStatus.failed;
    const full = Radius.circular(18);
    const tail = Radius.circular(6);
    // الذيل (زاوية 6 نقاط) على آخر فقاعة في المجموعة فقط
    final radius = BorderRadiusDirectional.only(
      topStart: full,
      topEnd: full,
      bottomStart: !mine && !widget.joinedBelow ? tail : full,
      bottomEnd: mine && !widget.joinedBelow ? tail : full,
    );
    IconData? tick;
    Color tickColor = mine ? Colors.white.withValues(alpha: .75) : Joy.textMuted;
    if (mine) {
      switch (m.status) {
        case MessageStatus.sending:
          tick = Icons.schedule_rounded;
        case MessageStatus.failed:
          tick = Icons.error_outline_rounded;
          tickColor = Joy.danger;
        case MessageStatus.sent:
          tick = m.deliveredAt != null || m.readAt != null ? Icons.done_all_rounded : Icons.done_rounded;
          if (m.readAt != null) tickColor = _tickRead;
      }
    }
    final metaColor = mine ? Colors.white.withValues(alpha: .78) : Joy.textMuted;
    final isImage = m.mediaKind == 'image';
    final hasCards = (widget.parsed?.all ?? const <ChatCode>[]).isNotEmpty;
    final textOnly = m.mediaKind == 'text' && !hasCards && !(widget.parsed?.commandOnly ?? false);
    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      if (failed)
        Text('لم تُرسل · اضغط لإعادة المحاولة', style: TextStyle(fontSize: 10.5, color: mine ? Colors.white : Joy.danger, fontWeight: FontWeight.w600))
      else if (m.status == MessageStatus.sending && m.isMedia)
        Text('جارٍ الرفع…', style: TextStyle(fontSize: 10.5, color: metaColor))
      else
        Text(clockOf(m.sentAt), style: TextStyle(fontSize: 10.5, color: metaColor)),
      if (tick != null) ...[const SizedBox(width: 3), Icon(tick, size: 14, color: tickColor)],
    ]);
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (m.forwardedFrom != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.forward_rounded, size: 14, color: metaColor),
            const SizedBox(width: 4),
            Text('معاد توجيهها من ${m.forwardedFrom}', style: TextStyle(fontSize: 11, color: metaColor, fontStyle: FontStyle.italic)),
          ]),
        ),
      if (m.quote != null) QuoteBox(name: m.quote!.senderName.isNotEmpty ? m.quote!.senderName : widget.peer.nickname, text: m.quote!.preview, onDark: mine, onTap: widget.onQuoteTap),
      if (m.mediaKind == 'text' && !(widget.parsed?.commandOnly ?? false)) Text.rich(TextSpan(style: style, children: _rich(m.content, style))) else if (m.mediaKind != 'text') _media(m),
      for (final c in widget.parsed?.all ?? const <ChatCode>[])
        ChatCodeCard(
          code: c,
          card: c.ref == null ? null : widget.cards[c.ref!],
          resolved: c.ref == null || widget.resolvedRefs.contains(c.ref!),
          request: widget.request,
          mine: mine,
          peerName: widget.peer.nickname,
          busy: widget.busy,
          onAction: (code, a) => widget.onCode?.call(code, a),
        ),
    ]);
    // الوقت والعلامات في الزاوية السفلية: النص يترك لها مكاناً في نهايته، والوسائط والبطاقات تحتها
    final body = Stack(children: [
      Padding(
        padding: textOnly ? EdgeInsetsDirectional.only(end: failed ? 150 : (mine ? 62 : 46)) : const EdgeInsets.only(bottom: 16),
        child: content,
      ),
      PositionedDirectional(bottom: 0, end: 0, child: meta),
    ]);
    final box = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: m.status == MessageStatus.sending ? 0.7 : 1,
      child: AnimatedContainer(
        key: Key('bubble-${m.key}'),
        duration: const Duration(milliseconds: 400),
        padding: EdgeInsets.fromLTRB(isImage ? 5 : 13, isImage ? 5 : 8, isImage ? 5 : 13, isImage ? 5 : 6),
        decoration: BoxDecoration(
          color: widget.highlighted ? Joy.sun.withValues(alpha: .7) : (mine ? null : Joy.bubbleIn),
          gradient: widget.highlighted || !mine ? null : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Joy.bubbleOutGradientStart, Joy.bubbleOutGradientEnd]),
          border: failed ? Border.all(color: Joy.danger, width: 1.2) : (mine ? null : Border.all(color: Joy.bubbleInBorder)),
          borderRadius: radius,
          boxShadow: mine ? [BoxShadow(color: Joy.bubbleOutGradientEnd.withValues(alpha: .18), blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        child: DefaultTextStyle.merge(style: style, child: body),
      ),
    );
    final topGap = widget.dateLabel != null ? 0.0 : (widget.joinedAbove ? 2.0 : 10.0);
    final showAvatar = !mine && !widget.joinedAbove;
    return Column(children: [
      if (widget.dateLabel != null) DayPill(widget.dateLabel!),
      _EnterAnimation(
        enabled: widget.animateIn,
        onDone: widget.onEntered,
        child: Padding(
          padding: EdgeInsets.only(top: topGap),
          child: Align(
            alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!mine) ...[
                SizedBox(width: 28, height: 28, child: showAvatar ? ProfileAvatar(key: Key('avatar-${m.key}'), person: widget.peer, size: 28) : null),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                  child: _SwipeToReply(
                    mine: mine,
                    onReply: widget.onSwipeReply,
                    child: DoubleTapDetector(
                      onDoubleTap: widget.onDoubleTap,
                      child: GestureDetector(
                        onLongPress: widget.onLongPress,
                        onTap: failed ? widget.onRetry : null,
                        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Stack(alignment: Alignment.center, children: [box, HeartBurst(trigger: widget.heartTrigger, size: 64)]),
                          if (widget.reactions.isNotEmpty)
                            Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 2), child: ReactionChips(reactions: widget.reactions, onTap: widget.onReactionTap, compact: true)),
                          if (widget.seen) SeenMarker(peer: widget.peer),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// دخول الرسالة الجديدة: تلاشٍ وانزلاق 12 نقطة خلال 180 مللي ثانية، مرة واحدة فقط.
class _EnterAnimation extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onDone;
  final Widget child;
  const _EnterAnimation({required this.enabled, this.onDone, required this.child});

  @override
  State<_EnterAnimation> createState() => _EnterAnimationState();
}

class _EnterAnimationState extends State<_EnterAnimation> {
  late final bool _animate = widget.enabled;

  @override
  void initState() {
    super.initState();
    // يُبلغ الصفحة أن الدخول عُرض حتى لا يتكرر عند إعادة بناء العنصر
    if (_animate) WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child)),
    );
  }
}

/// سحب الفقاعة نحو المنتصف (60 نقطة فأكثر) يجعلها هدف الرد: أيقونة رد تتبع الإصبع، واهتزازة خفيفة عند العتبة.
class _SwipeToReply extends StatefulWidget {
  final bool mine;
  final VoidCallback? onReply;
  final Widget child;
  const _SwipeToReply({required this.mine, this.onReply, required this.child});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  static const _threshold = 60.0, _max = 84.0;
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  VoidCallback? _tick;
  double _dx = 0;
  bool _fired = false;
  int _sign = 1;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// اتجاه المنتصف بإحداثيات الشاشة: الواردة عند البداية والصادرة عند النهاية، والبداية يمين في العربية.
  int _centreSign() {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return (widget.mine ? -1 : 1) * (rtl ? -1 : 1);
  }

  void _detach() {
    final t = _tick;
    if (t != null) _ctl.removeListener(t);
    _tick = null;
  }

  void _start(DragStartDetails _) {
    _ctl.stop();
    _detach();
    _fired = false;
    _sign = _centreSign();
  }

  void _update(DragUpdateDetails d) {
    final next = (_dx + d.delta.dx * _sign).clamp(0.0, _max);
    if (!_fired && next >= _threshold) {
      _fired = true;
      HapticFeedback.selectionClick();
    }
    setState(() => _dx = next);
  }

  void _end(DragEndDetails _) {
    final fire = _dx >= _threshold;
    // رجوع مرن إلى الصفر
    final anim = Tween<double>(begin: _dx, end: 0).animate(CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic));
    _detach();
    _tick = () {
      if (mounted) setState(() => _dx = anim.value);
    };
    _ctl.addListener(_tick!);
    _ctl.forward(from: 0).whenComplete(() {
      _detach();
      if (mounted) setState(() => _dx = 0);
    });
    if (fire) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final t = _dx * _sign;
    final p = (_dx / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _end(DragEndDetails()),
      child: Stack(clipBehavior: Clip.none, children: [
        Transform.translate(offset: Offset(t, 0), child: widget.child),
        if (_dx > 0)
          Positioned(
            // تظهر في الفراغ الذي تركته الفقاعة وتتبع الإصبع
            left: _sign > 0 ? t - 34 : null,
            right: _sign < 0 ? -t - 34 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * p,
                  child: Container(
                    key: const Key('swipe-reply-icon'),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: p >= 1 ? Joy.primary : Joy.surface2),
                    child: Icon(Icons.reply_rounded, size: 16, color: p >= 1 ? Joy.primaryOn : Joy.textMuted),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
