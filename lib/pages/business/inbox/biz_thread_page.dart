// محادثة خاصة مع دائرة (server/biz_inbox.js) لجهتيها: العميل يرى ردود الفريق باسم الدائرة وشعارها، والفريق يرى العميل
// ومن كتب كل رد منهم، ويسند المحادثة ويغلقها. الصور عبر /chat/upload (حتى 4)، وبطاقة مرجع لطلب العميل في الدائرة.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_inbox_api.dart';
import '../../../api/chat_tools_api.dart';
import '../../../api/client.dart' show thumbUrl, mediaUrl;
import '../../../api/commerce_models.dart' show money;
import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/report_sheet.dart';
import '../../../ui/widgets.dart';
import '../biz_order_page.dart';
import '../business_page.dart' show openBusiness;
import 'biz_inbox_providers.dart';
import 'inbox_widgets.dart';

class BizThreadPage extends ConsumerStatefulWidget {
  /// إحداهما: [bizId] لمحادثتي مع دائرة (تُنشأ بأول رسالة)، أو [threadId] لمحادثة قائمة (للعميل أو للفريق).
  final String? bizId, threadId;
  /// الدائرة للعنوان قبل التحميل.
  final BizInboxCircle? circle;
  /// مرجع يُرفق بأول رسالة (مثلاً «راسل الدائرة عن هذا الطلب»).
  final BizMsgRef? initialRef;
  const BizThreadPage({super.key, this.bizId, this.threadId, this.circle, this.initialRef}) : assert(bizId != null || threadId != null);

  /// فترة جلب الجديد والمحادثة مفتوحة (لا بث حيّ لهذه الرسائل)؛ null يوقفه (الاختبارات).
  static Duration? pollEvery = const Duration(seconds: 15);

  @override
  ConsumerState<BizThreadPage> createState() => _BizThreadPageState();
}

class _BizThreadPageState extends ConsumerState<BizThreadPage> {
  final _input = TextEditingController();
  final _rnd = Random();
  BizThreadView? _view;
  BizThread? _thread;
  List<BizThreadMessage> _msgs = const [];
  Object? _error;
  bool _sending = false, _uploading = false, _loadingOlder = false;
  final _photos = <String>[];
  BizMsgRef? _ref;
  Timer? _poll;

  String? get _bizId => _view?.biz.id ?? widget.bizId ?? widget.circle?.id;

  @override
  void initState() {
    super.initState();
    _ref = widget.initialRef;
    _load();
    final every = BizThreadPage.pollEvery;
    if (every != null) _poll = Timer.periodic(every, (_) { if (mounted && !_sending) _load(silent: true); });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final api = ref.read(apiClientProvider);
    try {
      final tid = _thread?.id ?? widget.threadId;
      final v = tid != null ? await api.bizThread(tid) : await api.bizThreadWith(widget.bizId!);
      if (!mounted) return;
      setState(() {
        _view = v;
        _thread = v.thread;
        // الصفحات الأقدم المحمّلة تبقى؛ آخر خمسين من الخادم تحلّ محل ما يقابلها. كل محمّلة ليست بينها أقدم منها
        // (الرسائل لا تُحذف)، فلا مقارنة بالوقت: وقت JSON مقطوع إلى الميلي ثانية فتسقط رسالة في الميلي ثانية نفسها
        final fresh = {for (final m in v.messages) m.id};
        final older = v.messages.isEmpty ? const <BizThreadMessage>[] : _msgs.where((m) => !fresh.contains(m.id)).toList();
        _msgs = [...older, ...v.messages];
        _error = null;
      });
      final t = v.thread;
      if (t != null && t.unread > 0) {
        await api.readBizThread(t.id).catchError((_) {});
        if (mounted) {
          setState(() => _thread = BizThread(id: t.id, bizId: t.bizId, status: t.status, lastText: t.lastText, lastSide: t.lastSide, lastAt: t.lastAt, createdAt: t.createdAt, closedAt: t.closedAt, seenAt: t.seenAt, biz: t.biz, customer: t.customer, assignee: t.assignee));
          invalidateBizInbox(ref, v.biz.id);
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e);
    }
  }

  Future<void> _older() async {
    final t = _thread;
    if (t == null || _msgs.isEmpty || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final v = await ref.read(apiClientProvider).bizThread(t.id, beforeId: _msgs.first.id);
      if (!mounted) return;
      final have = {for (final m in _msgs) m.id};
      setState(() {
        _msgs = [...v.messages.where((m) => !have.contains(m.id)), ..._msgs];
        _view = BizThreadView(viewer: _view!.viewer, role: _view!.role, reason: _view!.reason, biz: _view!.biz, thread: _view!.thread, messages: _view!.messages, hasMore: v.hasMore,
            canSend: _view!.canSend, canAssignOthers: _view!.canAssignOthers, orders: _view!.orders, team: _view!.team);
      });
    } catch (e) {
      if (mounted) toast(context, bizInboxErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 4) return;
    try {
      final img = await pickImage();
      if (img == null) return;
      setState(() => _uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => _photos.add(up.url));
    } catch (e) {
      if (mounted) toast(context, bizInboxErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickRef() async {
    final orders = _view?.orders ?? const <BizMsgRef>[];
    if (orders.isEmpty) return;
    final picked = await showModalBottomSheet<BizMsgRef>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('أرفق طلباً', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          for (final o in orders)
            ListTile(
              key: Key('biz-ref-option-${o.id}'),
              leading: const Icon(Icons.receipt_long_outlined, color: Joy.primary),
              title: Text(o.title.isEmpty ? 'طلب' : o.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([o.code, o.statusLabel, if (o.total != null) money(o.total!)].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
              onTap: () => Navigator.pop(ctx, o),
            ),
        ]),
      ),
    );
    if (picked != null && mounted) setState(() => _ref = picked);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final bizId = _bizId;
    if ((text.isEmpty && _photos.isEmpty) || _sending || bizId == null) return;
    // معرّف العميل يمنع التكرار إن أُعيد الإرسال بعد انقطاع (الخادم يعيد الرسالة المحفوظة)
    final clientId = 'b${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 30).toRadixString(36)}';
    setState(() => _sending = true);
    final api = ref.read(apiClientProvider);
    try {
      final t = _thread;
      final r = t == null
          ? await api.sendToBiz(bizId, text: text, photos: List.of(_photos), ref: _ref, clientId: clientId)
          : await api.sendBizThread(t.id, text: text, photos: List.of(_photos), ref: _ref, clientId: clientId);
      if (!mounted) return;
      setState(() {
        _thread = r.thread;
        _msgs = [..._msgs.where((m) => m.id != r.message.id), r.message];
        _input.clear();
        _photos.clear();
        _ref = null;
      });
      invalidateBizInbox(ref, bizId);
    } catch (e) {
      if (mounted) toast(context, bizInboxErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---- أفعال الفريق: الإسناد والإغلاق
  Future<void> _teamAction(String action) async {
    final t = _thread, v = _view;
    if (t == null || v == null) return;
    final api = ref.read(apiClientProvider);
    final me = ref.read(appStateProvider).user?.id;
    try {
      BizThread? out;
      switch (action) {
        case 'assign':
          final pick = await _pickAssignee(v.team, t.assignee?.id);
          if (pick == null) return;
          out = await api.assignBizThread(t.id, pick.isEmpty ? null : pick);
        case 'take':
          out = await api.assignBizThread(t.id, me);
        case 'leave':
          out = await api.assignBizThread(t.id, null);
        case 'close':
          out = await api.closeBizThread(t.id);
        case 'reopen':
          out = await api.reopenBizThread(t.id);
      }
      if (out != null && mounted) {
        setState(() => _thread = out);
        invalidateBizInbox(ref, t.bizId);
        toast(context, switch (action) { 'close' => 'أُغلقت المحادثة', 'reopen' => 'أُعيد فتح المحادثة', 'leave' => 'تركت المحادثة', _ => out.assignee == null ? 'المحادثة بلا مسؤول' : 'المسؤول: ${out.assignee!.nickname}' });
      }
    } catch (e) {
      if (mounted) toast(context, bizInboxErrText(e), error: true);
    }
  }

  /// يعيد معرّف العضو، أو '' لإلغاء الإسناد، أو null عند الإلغاء.
  Future<String?> _pickAssignee(List<BizInboxMember> team, String? current) => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('إسناد المحادثة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            for (final m in team)
              ListTile(
                key: Key('assign-${m.person.id}'),
                leading: ProfileAvatar(person: m.person, size: 36),
                title: Text(m.person.nickname.isEmpty ? m.person.id : m.person.nickname),
                subtitle: Text(m.roleLabel),
                trailing: m.person.id == current ? const Icon(Icons.check_rounded, color: Joy.success) : null,
                onTap: () => Navigator.pop(ctx, m.person.id),
              ),
            if (current != null) ListTile(key: const Key('assign-none'), leading: const Icon(Icons.person_off_outlined), title: const Text('بلا مسؤول'), onTap: () => Navigator.pop(ctx, '')),
          ]),
        ),
      );

  Future<void> _report(BizThreadMessage m) async {
    final v = _view;
    if (v == null || m.hidden) return;
    // العميل يبلغ عن رد الدائرة (بلا حظر لأن الكاتب يمثّل الدائرة)، والفريق عن رسالة العميل (مع خيار حظره)
    final r = await showReportSheet(context, ref, type: 'biz-msg', id: m.id, author: v.isTeam ? _thread?.customer : null, title: 'إبلاغ عن رسالة');
    if (r != null && r.blocked && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    final team = v?.isTeam ?? false;
    final circle = v?.biz ?? widget.circle;
    final t = _thread;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: team ? _teamTitle(t) : _customerTitle(circle),
        actions: [
          if (team && t != null)
            PopupMenuButton<String>(
              key: const Key('biz-thread-menu'),
              onSelected: _teamAction,
              itemBuilder: (_) => [
                if (v!.canAssignOthers) const PopupMenuItem(key: Key('biz-thread-assign'), value: 'assign', child: Text('إسناد…')),
                if (!v.canAssignOthers && t.assignee?.id != me) const PopupMenuItem(key: Key('biz-thread-take'), value: 'take', child: Text('خذ المحادثة')),
                if (!v.canAssignOthers && t.assignee?.id == me) const PopupMenuItem(key: Key('biz-thread-leave'), value: 'leave', child: Text('اترك المحادثة')),
                if (t.closed) const PopupMenuItem(key: Key('biz-thread-reopen'), value: 'reopen', child: Text('إعادة فتح')) else const PopupMenuItem(key: Key('biz-thread-close'), value: 'close', child: Text('إغلاق المحادثة')),
              ],
            ),
        ],
      ),
      body: v == null
          ? (_error != null ? ErrorState(_error!, onRetry: () { setState(() => _error = null); _load(); }) : const Center(child: CircularProgressIndicator()))
          : Column(children: [
              if (!team && !v.biz.verified) const _UnverifiedBanner(),
              if (t != null && t.closed)
                Container(
                  key: const Key('biz-thread-closed'),
                  width: double.infinity,
                  color: Joy.surface2,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(team ? 'المحادثة مغلقة؛ رسالة جديدة من أي طرف تعيد فتحها' : 'أغلقت الدائرة هذه المحادثة؛ رسالتك الجديدة تعيد فتحها',
                      style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                ),
              if (team && t?.assignee != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(children: [
                    const Icon(Icons.assignment_ind_outlined, size: 16, color: Joy.accent),
                    const SizedBox(width: 4),
                    Text('المسؤول: ${t!.assignee!.nickname}', key: const Key('biz-thread-assignee'), style: const TextStyle(color: Joy.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              Expanded(child: _messages(v, team)),
              _composer(v),
            ]),
    );
  }

  Widget _customerTitle(BizInboxCircle? c) => InkWell(
        onTap: c == null ? null : () => openBusiness(context, c.id),
        child: Row(children: [
          if (c != null) BizCircleLogo(circle: c, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(child: Text(c?.name ?? 'الدائرة', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                if (c?.verified == true) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.verified_rounded, size: 16, color: Joy.success)),
              ]),
              const Text('رسائل خاصة مع فريق الدائرة', style: TextStyle(fontSize: 11.5, color: Joy.textMuted)),
            ]),
          ),
        ]),
      );

  Widget _teamTitle(BizThread? t) {
    final c = t?.customer;
    return Row(children: [
      if (c != null) ProfileAvatar(person: c, size: 34),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(c?.nickname.isNotEmpty == true ? c!.nickname : (c?.id ?? 'محادثة'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('عميل · ${_view?.biz.name ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
        ]),
      ),
    ]);
  }

  Widget _messages(BizThreadView v, bool team) {
    if (_msgs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            team ? 'لا رسائل بعد' : 'اكتب سؤالك لفريق ${v.biz.name}. تصلهم وحدهم ولا تظهر في مساحة الدائرة العامة.',
            key: const Key('biz-thread-empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Joy.textMuted, height: 1.6),
          ),
        ),
      );
    }
    final ourSide = team ? 'team' : 'customer';
    // آخر رسالة من جهتي قرأها الطرف الآخر: «شوهدت» تحتها
    final seenAt = _thread?.seenAt;
    String? seenId;
    for (final m in _msgs.reversed) {
      if (m.side == ourSide) { if (seenAt != null && m.createdAt != null && !m.createdAt!.isAfter(seenAt)) seenId = m.id; break; }
    }
    final items = _msgs.reversed.toList();
    return ListView.builder(
      key: const Key('biz-thread-list'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: items.length + (v.hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == items.length) {
          return Center(child: TextButton(key: const Key('biz-thread-older'), onPressed: _loadingOlder ? null : _older, child: const Text('رسائل أقدم')));
        }
        final m = items[i];
        final prev = i + 1 < items.length ? items[i + 1] : null; // الأقدم منها مباشرة
        return _Bubble(
          m: m,
          ours: m.side == ourSide,
          team: team,
          circle: v.biz,
          customer: _thread?.customer,
          firstOfGroup: prev == null || prev.side != m.side || (team && prev.sender?.id != m.sender?.id),
          seen: m.id == seenId,
          onLongPress: m.side == ourSide ? null : () => _report(m),
        );
      },
    );
  }

  Widget _composer(BizThreadView v) {
    if (!v.canSend) {
      return SafeArea(
        top: false,
        child: Container(
          key: const Key('biz-thread-reason'),
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
          child: Text(bizInboxReasonText(v.reason) ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
        ),
      );
    }
    final canRef = v.orders.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.surface2))),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_photos.isNotEmpty || _ref != null)
            SizedBox(
              height: 60,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                if (_ref != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: InputChip(
                      key: const Key('biz-thread-ref-chip'),
                      avatar: const Icon(Icons.receipt_long_outlined, size: 16, color: Joy.primary),
                      label: Text(_ref!.code ?? _ref!.title, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => setState(() => _ref = null),
                    ),
                  ),
                for (final (i, p) in _photos.indexed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Stack(children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(p), key: Key('biz-thread-pending-$i'), width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: Joy.surface2))),
                      PositionedDirectional(top: 0, end: 0, child: InkWell(onTap: () => setState(() => _photos.removeAt(i)), child: const Icon(Icons.cancel_rounded, size: 18, color: Joy.danger))),
                    ]),
                  ),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              key: const Key('biz-thread-photo'),
              tooltip: 'صورة',
              onPressed: _uploading || _photos.length >= 4 ? null : _addPhoto,
              icon: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_photo_alternate_outlined, color: Joy.primary),
            ),
            if (canRef) IconButton(key: const Key('biz-thread-ref'), tooltip: 'أرفق طلباً', onPressed: _pickRef, icon: const Icon(Icons.receipt_long_outlined, color: Joy.primary)),
            Expanded(
              child: TextField(
                key: const Key('biz-thread-input'),
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: 'اكتب رسالة', counterText: '', isDense: true),
              ),
            ),
            IconButton(
              key: const Key('biz-thread-send'),
              tooltip: 'إرسال',
              onPressed: _sending || _uploading ? null : _send,
              icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, color: Joy.primary),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _UnverifiedBanner extends StatelessWidget {
  const _UnverifiedBanner();
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('biz-thread-unverified'),
        width: double.infinity,
        color: Joy.sunSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.gpp_maybe_outlined, size: 18, color: Joy.sunText),
          SizedBox(width: 6),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'دائرة غير موثّقة. ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: 'لم تتحقق ناس لايف من سجلها بعد؛ لا تدفع خارج التطبيق ولا تشارك بيانات بطاقتك.'),
            ]), style: TextStyle(color: Joy.sunText, fontSize: 12.5, height: 1.5)),
          ),
        ]),
      );
}

/// فقاعة رسالة: جهتي في البداية (اليمين) بتدرّج العلامة، والطرف الآخر في النهاية بإطار. للعميل يظهر شعار الدائرة بجانب ردودها،
/// وللفريق صورة العميل واسم الزميل الذي كتب الرد.
class _Bubble extends StatelessWidget {
  final BizThreadMessage m;
  final bool ours, team, firstOfGroup, seen;
  final BizInboxCircle circle;
  final Person? customer;
  final VoidCallback? onLongPress;
  const _Bubble({required this.m, required this.ours, required this.team, required this.circle, this.customer, this.firstOfGroup = true, this.seen = false, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final fg = ours ? Joy.primaryOn : Joy.text;
    final meta = ours ? Colors.white.withValues(alpha: .78) : Joy.textMuted;
    final label = team && m.fromTeam && !m.mine && m.sender != null ? 'كتبها ${m.sender!.nickname.isEmpty ? m.sender!.id : m.sender!.nickname}' : null;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (m.hidden)
        Text('أُخفيت هذه الرسالة بعد بلاغ', key: Key('biz-msg-hidden-${m.id}'), style: TextStyle(color: meta, fontStyle: FontStyle.italic, fontSize: 13.5))
      else ...[
        if (m.photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final (i, p) in m.photos.indexed)
                GestureDetector(
                  onTap: () => _openPhoto(context, p),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(thumbUrl(p), key: Key('biz-msg-photo-${m.id}-$i'), width: m.photos.length == 1 ? 200 : 110, height: m.photos.length == 1 ? 200 : 110, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 110, height: 110, color: Joy.surface2, child: const Icon(Icons.broken_image_outlined, color: Joy.textMuted))),
                  ),
                ),
            ]),
          ),
        if (m.ref != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: _RefCard(r: m.ref!, onDark: ours)),
        if (m.text.isNotEmpty) Text(m.text, style: TextStyle(fontSize: 15.5, height: 1.45, color: fg)),
      ],
      const SizedBox(height: 2),
      Text(_when(m.createdAt), style: TextStyle(fontSize: 10.5, color: meta)),
    ]);
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        key: Key('biz-msg-${m.id}'),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: ours ? null : Joy.bubbleIn,
          gradient: ours ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Joy.bubbleOutGradientStart, Joy.bubbleOutGradientEnd]) : null,
          border: ours ? null : Border.all(color: Joy.bubbleInBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        child: content,
      ),
    );
    // صورة الطرف الآخر عند أول فقاعة في مجموعته: شعار الدائرة للعميل، وصورة العميل للفريق
    final Widget? avatar = ours || !firstOfGroup
        ? null
        : team
            ? (customer == null ? null : ProfileAvatar(person: customer!, size: 28))
            : BizCircleLogo(circle: circle, size: 28);
    return Padding(
      padding: EdgeInsets.only(top: firstOfGroup ? 10 : 2),
      child: Column(crossAxisAlignment: ours ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
        if (label != null && firstOfGroup) Padding(padding: const EdgeInsets.only(bottom: 2, left: 6, right: 6), child: Text(label, style: const TextStyle(fontSize: 11, color: Joy.textMuted))),
        if (!team && !ours && firstOfGroup) Padding(padding: const EdgeInsets.only(bottom: 2, left: 36, right: 36), child: Text(circle.name, style: const TextStyle(fontSize: 11, color: Joy.textMuted, fontWeight: FontWeight.w600))),
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: ours
            ? [Flexible(child: bubble)]
            : [Flexible(child: bubble), const SizedBox(width: 6), avatar ?? const SizedBox(width: 28)]),
        if (seen) Padding(padding: const EdgeInsets.only(top: 2, left: 6, right: 6), child: Text('شوهدت', key: const Key('biz-thread-seen'), style: const TextStyle(fontSize: 10.5, color: Joy.textMuted))),
      ]),
    );
  }

  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? clockOf(t) : '${t.day}/${t.month} ${clockOf(t)}';
  }

  void _openPhoto(BuildContext context, String url) => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: InteractiveViewer(child: Image.network(mediaUrl(url), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 200, child: Icon(Icons.broken_image_outlined, color: Colors.white54)))),
        ),
      );
}

/// بطاقة المرجع داخل الفقاعة: الطلب (الرمز والحالة والمبلغ، يُفتح الطلب نفسه) أو الصنف (السعر).
class _RefCard extends StatelessWidget {
  final BizMsgRef r;
  final bool onDark;
  const _RefCard({required this.r, this.onDark = false});
  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : Joy.text;
    final muted = onDark ? Colors.white.withValues(alpha: .8) : Joy.textMuted;
    final sub = r.missing
        ? 'لم يعد متاحاً'
        : r.isOrder
            ? [r.code, r.statusLabel, if (r.total != null) money(r.total!)].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
            : (r.price != null ? money(r.price!) : '');
    return Material(
      color: onDark ? Colors.white.withValues(alpha: .14) : Joy.primarySoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key('biz-ref-${r.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: r.isOrder && !r.missing ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizOrderPage(orderId: r.id))) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(r.isOrder ? Icons.receipt_long_outlined : Icons.inventory_2_outlined, size: 20, color: onDark ? Colors.white : Joy.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(r.title.isEmpty ? (r.isOrder ? 'طلب' : 'صنف') : r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
