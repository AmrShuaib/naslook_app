import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart' show dayLabel, shortDate, bizErrText, openBusiness;

/// مستويات تنبيه العضو: كل العروض، القريبة فقط (الافتراضي)، بلا تنبيهات.
const notifyLevels = [
  ('all', 'كل العروض', 'يصلك تنبيه بكل عرض جديد من هذه الدائرة', Icons.notifications_active_outlined),
  ('near', 'القريبة فقط', 'يصلك التنبيه حين تكون قريباً من المكان', Icons.near_me_outlined),
  ('none', 'بلا تنبيهات', 'تشاهد العروض بنفسك في الدائرة ومحفظتك', Icons.notifications_off_outlined),
];

String notifyLevelLabel(String? level) => notifyLevels.where((l) => l.$1 == level).firstOrNull?.$2 ?? 'القريبة فقط';

/// ورقة اختيار مستوى تنبيهات الدائرة. تعيد المستوى الجديد أو null إن لم يتغيّر.
Future<String?> showNotifyLevelSheet(BuildContext context, WidgetRef ref, {required String bizId, required String current}) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 6), child: Text('كيف تصلك عروض هذه الدائرة؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        for (final (id, label, hint, icon) in notifyLevels)
          ListTile(
            key: Key('notify-$id'),
            leading: Icon(icon, color: current == id ? Joy.primary : Joy.textMuted),
            title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: current == id ? Joy.primary : Joy.text)),
            subtitle: Text(hint, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
            trailing: current == id ? const Icon(Icons.check_rounded, color: Joy.primary) : null,
            onTap: () => Navigator.pop(ctx, id),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (picked == null || picked == current || !context.mounted) return null;
  try {
    final level = await ref.read(apiClientProvider).setBizNotify(bizId, picked);
    ref.invalidate(bizOffersProvider(bizId));
    if (context.mounted) toast(context, 'تنبيهات العروض: ${notifyLevelLabel(level)}');
    return level;
  } catch (e) {
    if (context.mounted) toast(context, bizErrText(e), error: true);
    return null;
  }
}

/// حوار إرسال كوبون لصديق لديه حساب في ناس لايف (ينتقل كاملاً مرة واحدة).
Future<bool> sendOfferDialog(BuildContext context, WidgetRef ref, BizOffer offer) async {
  final contacts = ref.read(contactsProvider).value ?? const <Person>[];
  final handle = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('أرسل العرض لصديق'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(offer.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('ينتقل العرض كاملاً إلى صديقك ولا يبقى لك، ويطبّق شروطه نفسها.', style: TextStyle(fontSize: 12.5, color: Joy.textMuted, height: 1.5)),
        const SizedBox(height: 10),
        if (contacts.isNotEmpty)
          SizedBox(
            height: 74,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in contacts)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: InkWell(onTap: () => handle.text = c.nickname, child: Column(children: [Avatar(name: c.nickname, url: c.avatarUrl, size: 44), const SizedBox(height: 4), Text(c.nickname, style: const TextStyle(fontSize: 11))])),
                ),
            ]),
          ),
        TextField(key: const Key('send-offer-to'), controller: handle, autofocus: contacts.isEmpty, decoration: const InputDecoration(labelText: 'إلى (النك نيم أو المعرّف)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('send-offer-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال'))],
    ),
  );
  if (ok != true || !context.mounted) return false;
  var id = handle.text.trim();
  if (id.isEmpty) {
    toast(context, 'اكتب النك نيم أو المعرّف', error: true);
    return false;
  }
  try {
    final api = ref.read(apiClientProvider);
    if (!RegExp(r'^[A-Za-z]{2}\d{7}$').hasMatch(id)) id = (await api.userByHandle(id.toLowerCase().replaceFirst('@', ''))).id;
    await api.sendOffer(offer.bizId, offer.id, id);
    ref.invalidate(bizOffersProvider(offer.bizId));
    ref.invalidate(myOffersProvider);
    if (context.mounted) toast(context, 'أُرسل «${offer.title}»');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, bizErrText(e), error: true);
    return false;
  }
}

/// نصّ الفترة: «ينتهي بعد ساعتين» أو «حتى الخميس 3 أكتوبر» أو «يبدأ غداً».
String offerWhen(BizOffer o) {
  final now = DateTime.now();
  if (o.state == 'upcoming' && o.startsAt != null) return 'يبدأ ${dayLabel(o.startsAt!)}${_sameDay(o.startsAt!, now) ? ' ${_clock(o.startsAt!)}' : ''}';
  final e = o.endsAt;
  if (e == null) return o.kind == 'loyalty' ? 'دائم' : '';
  if (o.state == 'ended') return 'انتهى ${dayLabel(e)}';
  final left = e.difference(now);
  if (left.inMinutes < 60) return 'ينتهي خلال ${left.inMinutes.clamp(1, 59)} دقيقة';
  if (left.inHours < 24) return 'ينتهي بعد ${hoursLabel(left.inHours)}';
  return 'حتى ${dayLabel(e)} ${shortDate(e)}';
}

/// «ساعة» أو «ساعتين» أو «3 ساعات» أو «11 ساعة».
String hoursLabel(int h) => h == 1 ? 'ساعة' : h == 2 ? 'ساعتين' : h <= 10 ? '$h ساعات' : '$h ساعة';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// بطاقة العرض الموحدة: تُستخدم في صفحة الدائرة، وشاشة عروض الدائرة، ومحفظة «عروضي».
/// السطر الأول النوع والوقت، ثم العنوان والقيمة والشرط، ثم حالة الأهلية وزر الإجراء الوحيد.
class OfferCard extends ConsumerWidget {
  final BizOffer offer;
  final bool member, showBiz, compact;
  final VoidCallback? onJoin;
  const OfferCard({super.key, required this.offer, this.member = false, this.showBiz = false, this.compact = false, this.onJoin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = offer;
    final dim = o.state == 'ended' || o.state == 'off';
    final locked = !o.eligible;
    final needsJoin = o.lockedReason == 'members' && !member;
    final kindColor = switch (o.kind) { 'checkin' => Joy.accent, 'loyalty' => Joy.warning, 'deal' => Joy.success, _ => Joy.primary };
    return Opacity(
      opacity: dim ? .62 : 1,
      child: JoyCard(
        key: Key('offer-${o.id}'),
        padding: EdgeInsets.all(compact ? 12 : 14),
        onTap: showBiz && o.biz != null ? () => openBusiness(context, o.biz!.id) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: kindColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
              child: Text(o.kindLabel, style: TextStyle(color: kindColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            if (o.membersOnly && o.kind != 'loyalty') ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: const Text('للأعضاء', style: TextStyle(color: Joy.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ],
            const Spacer(),
            if (o.state != 'off')
              Text(offerWhen(o), style: TextStyle(color: o.endingSoon && o.state == 'active' ? Joy.danger : Joy.textMuted, fontSize: 11.5, fontWeight: o.endingSoon ? FontWeight.w700 : FontWeight.w500))
            else
              const Text('متوقف', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ]),
          const SizedBox(height: 8),
          if (showBiz && o.biz != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                _BizDot(o.biz!),
                const SizedBox(width: 6),
                Flexible(child: Text(o.biz!.name, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          Text(o.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 15 : 16.5)),
          const SizedBox(height: 2),
          Text(o.valueLabel, style: TextStyle(color: kindColor, fontWeight: FontWeight.w700, fontSize: 14)),
          if (o.description.isNotEmpty && !compact) Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5), maxLines: 3, overflow: TextOverflow.ellipsis)),
          if (o.conditionLabel.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.conditionLabel, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
          if (o.loyalty != null) Padding(padding: const EdgeInsets.only(top: 8), child: _LoyaltyBar(o.loyalty!)),
          if (o.grant != null) Padding(padding: const EdgeInsets.only(top: 6), child: _GrantLine(o.grant!)),
          if (!dim) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: needsJoin
                    ? const _Status(icon: Icons.lock_outline_rounded, text: 'للأعضاء · انضم لتستخدمه', color: Joy.textMuted)
                    : o.state == 'upcoming'
                        ? const _Status(icon: Icons.schedule_rounded, text: 'يُفتح في موعده', color: Joy.textMuted)
                        : locked
                            ? _Status(icon: o.usedByMe ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded, text: o.lockedLabel.isEmpty ? (o.note ?? 'غير متاح الآن') : o.lockedLabel, color: Joy.textMuted)
                            : _Status(icon: Icons.bolt_rounded, text: o.note?.isNotEmpty == true ? o.note! : (o.kind == 'checkin' ? 'يُطبّق تلقائياً عند الطلب وأنت هنا' : 'يُطبّق تلقائياً على طلبك'), color: Joy.success),
              ),
              if (needsJoin && onJoin != null)
                FilledButton(key: Key('offer-join-${o.id}'), style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact), onPressed: onJoin, child: const Text('انضم'))
              else if (o.canSend)
                OutlinedButton.icon(
                  key: Key('offer-send-${o.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
                  onPressed: () => sendOfferDialog(context, ref, o),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: const Text('أرسله لصديق'),
                ),
            ]),
          ] else if (o.usedByMe)
            const Padding(padding: EdgeInsets.only(top: 8), child: _Status(icon: Icons.check_circle_outline_rounded, text: 'استخدمته', color: Joy.textMuted)),
        ]),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Status({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);
}

class _LoyaltyBar extends StatelessWidget {
  final LoyaltyProgress p;
  const _LoyaltyBar(this.p);
  @override
  Widget build(BuildContext context) {
    final every = p.every < 1 ? 1 : p.every;
    final left = every - p.count;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: (p.count / every).clamp(0, 1), minHeight: 8, backgroundColor: Joy.surface2, color: Joy.warning)),
      const SizedBox(height: 4),
      Text(left <= 0 ? 'اكتملت المكافأة' : '${p.count} من $every · بقي ${left == 1 ? 'طلب واحد' : left == 2 ? 'طلبان' : '$left طلبات'}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
    ]);
  }
}

class _GrantLine extends StatelessWidget {
  final OfferGrant g;
  const _GrantLine(this.g);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(g.reason == 'loyalty' ? Icons.emoji_events_outlined : Icons.card_giftcard_rounded, size: 15, color: Joy.warning),
        const SizedBox(width: 4),
        Flexible(child: Text([g.reason == 'loyalty' ? 'مكافأتك' : 'هدية من ${g.from?.nickname ?? 'صديق'}', if (g.expiresAt != null) 'تنتهي ${dayLabel(g.expiresAt!)} ${shortDate(g.expiresAt!)}'].join(' · '), style: const TextStyle(color: Joy.warning, fontSize: 12, fontWeight: FontWeight.w600))),
      ]);
}

class _BizDot extends StatelessWidget {
  final OfferBizRef b;
  const _BizDot(this.b);
  @override
  Widget build(BuildContext context) {
    final logo = b.logoUrl;
    final letters = b.name.trim().isEmpty ? '؟' : b.name.trim()[0];
    Widget fallback = Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(7)), child: Text(letters, style: const TextStyle(color: Joy.primary, fontSize: 11, fontWeight: FontWeight.w800)));
    if (logo == null || logo.isEmpty) return fallback;
    final img = logo.startsWith('asset:') ? Image.asset('assets/${logo.substring(6)}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback) : Image.network(thumbUrl(logo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    return ClipRRect(borderRadius: BorderRadius.circular(7), child: SizedBox(width: 22, height: 22, child: img));
  }
}

/// بطاقة مختصرة في صفحة الدائرة: عدد العروض السارية وأقربها انتهاءً، تفتح شاشة العروض.
class OffersEntryCard extends ConsumerWidget {
  final Biz biz;
  final VoidCallback onOpen;
  const OffersEntryCard({super.key, required this.biz, required this.onOpen});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(bizOffersProvider(biz.id)).valueOrNull;
    final n = page?.active.length ?? biz.offers;
    if (n == 0 && (page == null || page.upcoming.isEmpty)) return const SizedBox.shrink();
    final first = page?.active.firstOrNull;
    final soon = first?.endsAt ?? biz.offerEndsAt;
    final sub = first != null
        ? [first.title, if (offerWhen(first).isNotEmpty) offerWhen(first)].join(' · ')
        : soon != null
            ? 'أقربها ينتهي ${dayLabel(soon)}'
            : 'اطّلع على العروض';
    return JoyCard(
      key: const Key('offers-entry'),
      onTap: onOpen,
      color: Joy.accentSoft,
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.local_offer_rounded, color: Joy.accent)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n == 0 ? 'عروض قادمة' : n == 1 ? 'عرض واحد ساري' : n == 2 ? 'عرضان ساريان' : '$n عروض سارية', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Joy.accent)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.text, fontSize: 12.5)),
          ]),
        ),
        const Icon(Icons.chevron_left_rounded, color: Joy.accent),
      ]),
    );
  }
}

/// شاشة عروض الدائرة: السارية والقادمة والمنتهية (آخر 30 يوماً) مع سطر العضوية ومستوى التنبيه.
class CircleOffersPage extends ConsumerStatefulWidget {
  final String bizId;
  /// اسم الدائرة إن عُرف؛ وإلا يُقرأ من تفاصيلها.
  final String? title;
  /// يُستدعى حين يضغط الزائر «انضم» على عرض للأعضاء؛ إن غاب يُستخدم الانضمام الافتراضي.
  final Future<void> Function()? onJoin;
  const CircleOffersPage({super.key, required this.bizId, this.title, this.onJoin});
  @override
  ConsumerState<CircleOffersPage> createState() => _CircleOffersPageState();
}

class _CircleOffersPageState extends ConsumerState<CircleOffersPage> {
  bool _busy = false, _showPast = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.onJoin != null) {
        await widget.onJoin!();
      } else {
        await ref.read(apiClientProvider).followBiz(widget.bizId);
        invalidateBiz(ref, widget.bizId);
        if (mounted) toast(context, 'انضممت إلى $_title · تصلك عروضها القريبة');
      }
    } catch (e) {
      if (mounted) toast(context, bizErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title => widget.title ?? ref.read(bizDetailProvider(widget.bizId)).valueOrNull?.title ?? 'الدائرة';

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(bizOffersProvider(widget.bizId));
    final title = widget.title ?? ref.watch(bizDetailProvider(widget.bizId)).valueOrNull?.title ?? 'الدائرة';
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text('عروض $title')),
      body: page.when(
        data: (p) {
          final empty = p.active.isEmpty && p.upcoming.isEmpty && p.past.isEmpty;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(bizOffersProvider(widget.bizId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _MemberLine(member: p.member, notify: p.notify, busy: _busy, onJoin: _join, onNotify: () => showNotifyLevelSheet(context, ref, bizId: widget.bizId, current: p.notify ?? 'near')),
                const SizedBox(height: 12),
                if (empty) const EmptyState(icon: Icons.local_offer_outlined, title: 'لا عروض حالياً', subtitle: 'حين تنشر الدائرة عرضاً يظهر هنا، ويصل الأعضاء حسب مستوى التنبيه الذي اختاروه.'),
                if (p.active.isNotEmpty) ...[
                  const SectionTitle('السارية'),
                  for (final o in p.active) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferCard(offer: o, member: p.member, onJoin: _join)),
                ],
                if (p.upcoming.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const SectionTitle('القادمة'),
                  for (final o in p.upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferCard(offer: o, member: p.member, onJoin: _join)),
                ],
                if (p.past.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SectionTitle('المنتهية', action: _showPast ? 'إخفاء' : 'عرض ${p.past.length}', onAction: () => setState(() => _showPast = !_showPast)),
                  if (_showPast) for (final o in p.past) Padding(padding: const EdgeInsets.only(bottom: 10), child: OfferCard(offer: o, member: p.member, compact: true)),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizOffersProvider(widget.bizId))),
      ),
    );
  }
}

/// سطر العضوية أعلى شاشة العروض: للعضو مستوى التنبيه، ولغيره زر الانضمام مع سطر الإخبار.
class _MemberLine extends StatelessWidget {
  final bool member, busy;
  final String? notify;
  final VoidCallback onJoin, onNotify;
  const _MemberLine({required this.member, required this.notify, required this.busy, required this.onJoin, required this.onNotify});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Joy.line)),
        child: member
            ? Row(children: [
                const Icon(Icons.verified_rounded, color: Joy.success, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('أنت عضو · العروض تظهر في محفظتك', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                TextButton.icon(key: const Key('notify-level'), onPressed: onNotify, icon: const Icon(Icons.tune_rounded, size: 16), label: Text(notifyLevelLabel(notify), style: const TextStyle(fontSize: 12.5))),
              ])
            : Row(children: [
                const Icon(Icons.local_offer_outlined, color: Joy.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('انضم لتحصل على العروض والخصومات في محفظتك', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton(key: const Key('join-circle'), style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: onJoin, child: const Text('انضم')),
              ]),
      );
}

/// صف استخدام عرض في «عروضي»: العرض، الدائرة، المبلغ الموفَّر، ورمز الطلب.
class OfferUseRow extends StatelessWidget {
  final OfferUse u;
  final bool last;
  const OfferUseRow(this.u, {super.key, this.last = false});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openBusiness(context, u.biz.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Joy.line))),
          child: Row(children: [
            _BizDot(u.biz),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text([u.biz.name, if (u.itemTitle != null && u.itemTitle!.isNotEmpty) u.itemTitle!, if (u.orderCode != null) u.orderCode!, if (u.usedAt != null) timeAgo(u.usedAt)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('وفّرت ${money(u.amount)}', style: const TextStyle(color: Joy.success, fontWeight: FontWeight.w800, fontSize: 13)),
              if (u.orderTotal != null) Text('دفعت ${money(u.orderTotal!)}', style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
            ]),
          ]),
        ),
      );
}
