import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/ticket_share_api.dart';
import '../../core/app_theme.dart';
import '../../core/share/share_stub.dart' if (dart.library.js_interop) '../../core/share/share_web.dart' if (dart.library.io) '../../core/share/share_io.dart' as share;
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'events_page.dart';

/// «وزّع التذاكر»: من اشترى أكثر من تذكرة لفعالية يُبقي واحدة ويرسل كل واحدة من البقية إلى مستخدم (تصل حسابه بعد قبوله)
/// أو برابط لشخص واحد عبر أي تطبيق. التذكرة تبقى لصاحبها حتى تُقبل، وله استرجاعها ما دامت معلّقة.
class TicketSharePage extends ConsumerStatefulWidget {
  final String eventId, title;
  const TicketSharePage({super.key, required this.eventId, required this.title});

  @override
  ConsumerState<TicketSharePage> createState() => _TicketSharePageState();
}

enum _Via { friend, link, copy }

class _TicketSharePageState extends ConsumerState<TicketSharePage> {
  // تذاكر لها طلب جارٍ: زرها يتعطل حتى لا يُرسل الطلب مرتين
  final _busy = <String>{};

  void _refresh() {
    ref.invalidate(ticketsProvider);
    ref.invalidate(ticketSharesProvider);
  }

  Future<void> _run(String ticketId, Future<String?> Function() action) async {
    if (_busy.contains(ticketId)) return;
    setState(() => _busy.add(ticketId));
    try {
      final msg = await action();
      if (mounted && msg != null) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, ticketShareErrText(e), error: true);
    } finally {
      // بعد النجاح والفشل معاً: رفض «already-pending» أو «not-transferable» يعني أن ما على الشاشة قديم
      _refresh();
      if (mounted) setState(() => _busy.remove(ticketId));
    }
  }

  String get _shareText => 'تذكرة لك إلى «${widget.title}» على ناس لايف. افتح الرابط لتستلمها، وهو لشخص واحد فقط.';

  /// يشارك الرابط بورقة النظام؛ حيث لا ورقة (سطح المكتب) يُنسخ الرابط.
  Future<String?> _shareUrl(String url) async {
    final ok = await share.nativeShare(title: 'تذكرة · ${widget.title}', text: _shareText, url: url);
    if (ok) return null;
    await Clipboard.setData(ClipboardData(text: url));
    return 'نُسخ الرابط، الصقه حيث تريد';
  }

  Future<void> _send(Ticket t, Set<String> taken) async {
    final pick = await showModalBottomSheet<({_Via via, Person? friend})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SendSheet(exclude: taken),
    );
    if (pick == null || !mounted) return;
    final api = ref.read(apiClientProvider);
    await _run(t.id, () async {
      switch (pick.via) {
        case _Via.friend:
          final f = pick.friend!;
          await api.sendTicket(t.id, f.id);
          return 'أُرسلت إلى ${f.nickname} · بانتظار القبول';
        case _Via.link:
          final url = (await api.ticketLink(t.id)).url;
          if (url == null) throw const ApiException(500, 'no-url');
          return _shareUrl(url);
        case _Via.copy:
          final url = (await api.ticketLink(t.id)).url;
          if (url == null) throw const ApiException(500, 'no-url');
          await Clipboard.setData(ClipboardData(text: url));
          return 'نُسخ الرابط · أرسله لشخص واحد';
      }
    });
  }

  Future<void> _undo(Ticket t) => _run(t.id, () async {
        await ref.read(apiClientProvider).undoTicketSend(t.id);
        return 'استُرجعت التذكرة';
      });

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final shares = ref.watch(ticketSharesProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('وزّع التذاكر')),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: _refresh),
        data: (all) => shares.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: _refresh),
          data: (sh) => _body([for (final t in all) if (t.eventId == widget.eventId && t.status == 'valid') t], sh),
        ),
      ),
    );
  }

  Widget _body(List<Ticket> mine, TicketShares sh) {
    if (mine.isEmpty) {
      return const EmptyState(icon: Icons.confirmation_number_outlined, title: 'لا تذاكر للتوزيع', subtitle: 'لا تذكرة صالحة لك في هذه الفعالية الآن.');
    }
    final pending = {for (final t in mine) if (sh.pendingOf(t.id) case final p?) t.id: p};
    // أول تذكرة لم تُرسل تبقى لصاحبها
    final myId = mine.where((t) => !pending.containsKey(t.id)).firstOrNull?.id;
    // صديق بانتظار تذكرة من هذه الشاشة لا يُعرض ثانيةً: تذكرة واحدة لكل شخص
    final taken = {for (final p in pending.values) if (p.to != null) p.to!.id};
    final sent = pending.length, n = mine.length;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18), maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
      const Text('تذكرة تبقى لك، وكل تذكرة أخرى ترسلها لصاحب واحد: إلى حسابه في ناس لايف أو برابط عبر أي تطبيق.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6)),
      const SizedBox(height: 14),
      JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('وُزّع $sent من $n', key: const Key('share-progress'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: sent / n, minHeight: 8, backgroundColor: Joy.surface2, color: Joy.primary)),
        ]),
      ),
      const SizedBox(height: 12),
      for (final (i, t) in mine.indexed) Padding(padding: const EdgeInsets.only(bottom: 10), child: _row(i, t, pending[t.id], t.id == myId, taken)),
      const SizedBox(height: 4),
      const Text('الإرسال مجاني. يصلك تنبيه عند القبول أو الرفض، ورمز التذكرة يتغير عند انتقالها فلا يصلح الرمز القديم للدخول.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.6)),
    ]);
  }

  Widget _row(int i, Ticket t, TicketShareOut? p, bool isMine, Set<String> taken) {
    final busy = _busy.contains(t.id);
    final Widget lead, trail;
    final String title, sub;
    if (p != null) {
      final to = p.to;
      lead = to != null ? Avatar(name: to.nickname, url: to.avatarUrl, size: 44) : _badge(Icons.link_rounded, Joy.sunSoft, Joy.sunText);
      title = to != null ? to.nickname : 'رابط';
      sub = to != null ? 'بانتظار القبول' : 'رابط · بانتظار من يستلمه';
      trail = Row(mainAxisSize: MainAxisSize.min, children: [
        // الرابط المعلّق يُعاد إرساله كما هو (الخادم يعيد الرابط نفسه)
        if (p.isLink && p.url != null)
          IconButton(key: Key('ticket-reshare-${t.id}'), tooltip: 'أرسل الرابط مرة أخرى', icon: const Icon(Icons.ios_share_rounded, size: 20), onPressed: busy ? null : () => _run(t.id, () => _shareUrl(p.url!))),
        OutlinedButton(key: Key('ticket-undo-${t.id}'), style: _small, onPressed: busy ? null : () => _undo(t), child: const Text('استرجاع')),
      ]);
    } else if (isMine) {
      lead = _badge(Icons.person_rounded, Joy.primarySoft, Joy.primary);
      title = 'تذكرتي';
      sub = '${t.tier} · تبقى لك';
      // من تعذر حضوره يعطي تذكرته أيضاً، بزر أهدأ من أزرار البقية
      trail = TextButton(key: Key('ticket-send-${t.id}'), style: _small, onPressed: busy ? null : () => _send(t, taken), child: const Text('أعطها لغيري'));
    } else {
      lead = _badge(Icons.confirmation_number_outlined, Joy.accentSoft, Joy.accent);
      title = 'تذكرة ${i + 1}';
      sub = '${t.tier} · لم تُرسل بعد';
      trail = FilledButton(key: Key('ticket-send-${t.id}'), style: _small, onPressed: busy ? null : () => _send(t, taken), child: const Text('أرسل'));
    }
    return JoyCard(
      key: Key('share-row-${t.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        lead,
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          Text(sub, maxLines: 2, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        trail,
      ]),
    );
  }

  static final _small = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(44, 40)), padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)));

  Widget _badge(IconData icon, Color bg, Color fg) => Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: fg, size: 22));
}

/// ورقة «أرسل»: الأصدقاء أولاً ثم الإرسال برابط عبر تطبيق آخر أو نسخه. تعيد الاختيار والصفحة تنفّذه.
class _SendSheet extends ConsumerWidget {
  final Set<String> exclude;
  const _SendSheet({required this.exclude});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(contactsProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('لمن هذه التذكرة؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('تصل حساب صاحبك وتنتظر قبوله', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            Flexible(
              child: friends.when(
                loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                // تعذر جلب الأصدقاء لا يحبس الإرسال: الرابط يبقى متاحاً
                error: (_, __) => const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('تعذر جلب أصدقائك الآن. أرسلها برابط.', style: TextStyle(color: Joy.textMuted))),
                data: (all) {
                  final list = [for (final f in all) if (!exclude.contains(f.id)) f];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(all.isEmpty ? 'لا أصدقاء في قائمتك بعد. أرسلها برابط.' : 'كل أصدقائك وصلتهم تذكرة. أرسلها برابط.', key: const Key('share-no-friends'), style: const TextStyle(color: Joy.textMuted)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      key: Key('share-friend-${list[i].id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: list[i].nickname, url: list[i].avatarUrl, size: 40),
                      title: Text(list[i].nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.send_rounded, size: 18, color: Joy.primary),
                      onTap: () => Navigator.pop(context, (via: _Via.friend, friend: list[i])),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('share-link'),
                  onPressed: () => Navigator.pop(context, (via: _Via.link, friend: null)),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('أرسل عبر تطبيق آخر'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('share-copy'),
                onPressed: () => Navigator.pop(context, (via: _Via.copy, friend: null)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرابط'),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('الرابط لشخص واحد: أول من يفتحه بحسابه يستلم التذكرة.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
