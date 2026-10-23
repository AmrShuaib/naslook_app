// البطاقات الذكية لرموز الاختصار في المحادثة: عرض بطاقة لكل رمز (شخص، دائرة، صنف، فعالية، عرض، منشور، مساحة، تذكرة، حجز،
// طلب مبلغ، إرسال، تقسيم، موعد، موقع، دعوة)، والإكمال التلقائي فوق حقل الكتابة، وقائمة «+»، ومنتقيات التذاكر والحجوزات
// والأمنيات، ودليل الرموز داخل التطبيق. وبطاقة «الموقع المباشر» (/live) بخريطة مصغّرة تتحدّث كل عشر ثوانٍ.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/chat_cards_api.dart';
import '../../api/chat_live_api.dart';
import '../../api/client.dart';
import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/wishlist_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/directions.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'live_share.dart';

// الاتجاهات انتقلت إلى core/directions.dart (يستعملها عارض اللحظات أيضاً)؛ تبقى متاحة لمن يستورد هذا الملف
export '../../core/directions.dart' show openExternalUrl, directionsUrl, openDirections;

/// إجراء على بطاقة يُنفَّذ في صفحة المحادثة (open, chat, pay, accept, decline, cancel, counter, share-loc, directions, join, copy).
typedef CodeAction = void Function(ChatCode code, String action);

String _sar(int h) => money(h);
String _when(DateTime? t) {
  if (t == null) return '';
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} · ${clockOf(t)}';
}

/// صورة بطاقة: شعار مضمّن (asset:) أو رابط وسائط أو أيقونة بديلة.
class _CardImage extends StatelessWidget {
  final String? url;
  final IconData fallback;
  final double size;
  final Color color;
  const _CardImage({this.url, required this.fallback, this.size = 50, this.color = Joy.primary});
  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;
    if (u == null || u.isEmpty) {
      child = Icon(fallback, color: color, size: size * .5);
    } else if (u.startsWith('asset:')) {
      child = Image.asset('assets/${u.substring(6)}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallback, color: color, size: size * .5));
    } else {
      child = Image.network(thumbUrl(u), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallback, color: color, size: size * .5));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(width: size, height: size, color: color.withValues(alpha: .1), alignment: Alignment.center, child: child),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color, bg;
  final IconData? icon;
  const _Chip(this.text, {super.key, this.color = Joy.primary, this.bg = Joy.primarySoft, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// بطاقة رمز واحد داخل فقاعة الرسالة.
class ChatCodeCard extends StatelessWidget {
  final ChatCode code;
  /// البطاقة المحلولة من الخادم (للإشارات والدعوات ومكان الموعد)؛ null قبل الحلّ أو إن لم يوجد.
  final ChatCard? card;
  /// اكتمل الحلّ (حتى لو كانت النتيجة null).
  final bool resolved;
  final ChatRequest? request;
  final bool mine;
  final String peerName;
  final CodeAction onAction;
  /// تُغلق الأزرار أثناء تنفيذ إجراء.
  final bool busy;
  const ChatCodeCard({super.key, required this.code, this.card, this.resolved = false, this.request, required this.mine, required this.peerName, required this.onAction, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final k = code.kind;
    if (k.isRef) return _refCard(context);
    return switch (k) {
      CodeKind.pay || CodeKind.split => _moneyCard(context),
      CodeKind.send => _sendCard(context),
      CodeKind.meet => _meetCard(context),
      CodeKind.where => _whereCard(context),
      CodeKind.loc => _locCard(context),
      CodeKind.invite => _inviteCard(context),
      CodeKind.live => LiveLocationCard(key: Key('card-live-${code.liveId}'), id: code.liveId, mine: mine, peerName: peerName),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _frame({required Widget child, Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
        child: child,
      );

  Widget _button(String label, String action, {IconData? icon, bool primary = true, Key? key}) {
    final onPressed = busy ? null : () => onAction(code, action);
    final child = Row(mainAxisSize: MainAxisSize.min, children: [if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 5)], Text(label)]);
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(0, 36)), padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)), visualDensity: VisualDensity.compact);
    return primary ? FilledButton(key: key, style: style, onPressed: onPressed, child: child) : OutlinedButton(key: key, style: style, onPressed: onPressed, child: child);
  }

  Widget _head({required Widget leading, required String title, String subtitle = '', Widget? trailing}) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Joy.text)),
            if (subtitle.isNotEmpty) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]);

  Widget _actions(List<Widget> buttons) => buttons.isEmpty
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.end, children: buttons));

  // ---- الإشارات
  Widget _refCard(BuildContext context) {
    final c = card;
    if (c == null) {
      if (!resolved) return _frame(child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text(code.raw, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))]));
      return const SizedBox.shrink();
    }
    final key = Key('card-${c.type}-${c.id}');
    switch (c.type) {
      case 'user':
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(leading: Avatar(name: c.title, url: c.image, size: 46), title: c.title, subtitle: c.link == null ? '' : 'naslife.app${c.link}'),
          _actions([_button('الملف', 'open', icon: Icons.person_outline_rounded, primary: false), _button('مراسلة', 'chat', icon: Icons.chat_bubble_outline_rounded)]),
        ]));
      case 'biz':
      case 'space':
        final cat = BizCategory.of(c.category);
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: _CardImage(url: c.image, fallback: c.type == 'space' ? Icons.forum_outlined : cat.icon),
            title: c.title, subtitle: c.subtitle,
            trailing: c.type == 'biz' && c.openNow != null ? _Chip(c.openNow! ? 'مفتوح' : 'مغلق', color: c.openNow! ? Joy.success : Joy.textMuted, bg: c.openNow! ? const Color(0xFFE6F6EC) : Joy.surface2) : null,
          ),
          _actions([_button(c.type == 'space' ? 'افتح النقاش' : 'افتح', 'open', icon: c.type == 'space' ? Icons.forum_outlined : Icons.storefront_outlined)]),
        ]));
      case 'item':
        final cat = BizCategory.of(c.category);
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: _CardImage(url: c.image, fallback: Icons.shopping_bag_outlined),
            title: c.title, subtitle: c.subtitle,
            trailing: c.price == null ? null : _Chip(c.price == 0 ? 'مجاني' : _sar(c.price!), color: Joy.accent, bg: Joy.accentSoft),
          ),
          if ((c.discussions ?? 0) > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${c.discussions} نقاش في مساحة الدائرة', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
          _actions([_button('ناقش', 'discuss', icon: Icons.mode_comment_outlined, primary: false), _button(cat.actionLabel, 'open', icon: Icons.storefront_outlined)]),
        ]));
      case 'event':
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: const _CardImage(fallback: Icons.event_rounded, color: Joy.accent),
            title: c.title, subtitle: [_when(c.startsAt), c.subtitle].where((s) => s.isNotEmpty).join('\n'),
            trailing: c.cancelled == true ? const _Chip('ملغاة', color: Joy.danger, bg: Joy.accentSoft) : c.price == null ? null : _Chip(c.price == 0 ? 'مجاني' : _sar(c.price!), color: Joy.accent, bg: Joy.accentSoft),
          ),
          if (c.left != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${c.left} مقعداً متاحاً', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
          _actions([_button('احجز', 'open', icon: Icons.confirmation_number_outlined)]),
        ]));
      case 'listing':
        // بطاقة عرض السوق: صورة، سعر، بائع، حالة/توصيل/تقييم من الخادم، وشارة سبوت لايت، وزر طلب مباشر
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: _CardImage(url: c.image, fallback: c.kind == 'service' ? Icons.handyman_outlined : Icons.sell_outlined, color: Joy.sunText),
            title: c.title, subtitle: [if (c.person != null) 'البائع ${c.person!.nickname}', c.subtitle].where((s) => s.isNotEmpty).join(' · '),
            trailing: c.price == null ? null : _Chip(c.price == 0 ? 'مجاناً' : _sar(c.price!), color: Joy.accent, bg: Joy.accentSoft),
          ),
          if (c.verified == true || c.status != 'active' || (c.left != null && c.left! <= 0)) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [
            if (c.verified == true) const _Chip('سبوت لايت', color: Joy.sunText, bg: Joy.sunSoft),
            if (c.status != 'active') _Chip(c.status == 'sold' ? 'مباع' : 'غير متاح', color: Joy.textMuted, bg: Joy.surface2),
            if (c.status == 'active' && c.left != null && c.left! <= 0) _Chip('نفدت الكمية', color: Joy.danger, bg: Joy.danger.withValues(alpha: .1)),
          ])),
          _actions([
            _button('التفاصيل', 'open', icon: Icons.storefront_outlined, primary: false),
            if (c.status == 'active' && (c.left == null || c.left! > 0)) _button(c.kind == 'service' ? 'احجز' : 'اطلب الآن', 'open', icon: Icons.shopping_bag_outlined),
          ]),
        ]));
      case 'post':
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(leading: _CardImage(url: c.image, fallback: c.kind == 'video' ? Icons.videocam_outlined : c.kind == 'audio' ? Icons.mic_none_rounded : Icons.auto_awesome_motion_outlined, color: Joy.accent), title: c.title, subtitle: c.subtitle),
          _actions([_button('شاهد', 'open', icon: Icons.play_circle_outline_rounded)]),
        ]));
      case 'spacepost':
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(leading: _CardImage(url: c.image, fallback: Icons.forum_outlined), title: c.title, subtitle: [c.subtitle, if ((c.replies ?? 0) > 0) '${c.replies} رد'].where((s) => s.isNotEmpty).join(' · ')),
          _actions([_button('افتح النقاش', 'open', icon: Icons.forum_outlined)]),
        ]));
      case 'ticket':
        final valid = c.status == 'valid';
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: const _CardImage(fallback: Icons.confirmation_number_outlined, color: Joy.accent),
            title: c.title, subtitle: [_when(c.startsAt), c.subtitle].where((s) => s.isNotEmpty).join('\n'),
            trailing: _Chip(valid ? 'سارية' : c.status == 'used' ? 'مستخدمة' : 'مستردّة', color: valid ? Joy.success : Joy.textMuted, bg: valid ? const Color(0xFFE6F6EC) : Joy.surface2),
          ),
          Padding(padding: const EdgeInsets.only(top: 8), child: _codeRow(c.code ?? '', owner: c.person?.nickname)),
          _actions([_button('الفعالية', 'open', icon: Icons.event_rounded)]),
        ]));
      case 'order':
        final ok = c.status == 'confirmed';
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: _CardImage(url: c.image, fallback: Icons.receipt_long_outlined),
            title: c.title, subtitle: [c.subtitle, if (c.startsAt != null) _when(c.startsAt), if (c.total != null) _sar(c.total!)].where((s) => s.isNotEmpty).join(' · '),
            trailing: _Chip(ok ? 'مؤكد' : c.status == 'used' ? 'مستخدم' : 'ملغى', color: ok ? Joy.success : Joy.textMuted, bg: ok ? const Color(0xFFE6F6EC) : Joy.surface2),
          ),
          Padding(padding: const EdgeInsets.only(top: 8), child: _codeRow(c.code ?? '', owner: c.person?.nickname)),
          _actions([_button('الدائرة', 'open', icon: Icons.storefront_outlined)]),
        ]));
      case 'job':
        // بطاقة عرض وظيفي (#job/…): المسمّى والدائرة والمدينة ونوع الدوام؛ تُرسل أول رسالة في محادثة التوظيف
        final open = c.status == null || c.status == 'open';
        return _frame(key: key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _head(
            leading: _CardImage(url: c.image, fallback: Icons.work_outline_rounded),
            title: c.title, subtitle: c.subtitle,
            trailing: open ? const _Chip('عرض وظيفي', icon: Icons.work_outline_rounded) : const _Chip('مغلق', color: Joy.textMuted, bg: Joy.surface2),
          ),
          _actions([_button('الدائرة', 'open', icon: Icons.storefront_outlined)]),
        ]));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _codeRow(String value, {String? owner}) => Row(children: [
        Expanded(child: Text(value, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontSize: 13.5))),
        if (owner != null && owner.isNotEmpty) Text('لـ $owner', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'نسخ الرمز', icon: const Icon(Icons.copy_rounded, size: 18, color: Joy.textMuted), onPressed: () => onAction(code, 'copy')),
      ]);

  // ---- الطلبات
  String get _status => request?.status ?? 'pending';
  Widget _statusChip() {
    final s = _status;
    final (color, bg, icon) = switch (s) {
      'paid' || 'accepted' => (Joy.success, const Color(0xFFE6F6EC), Icons.check_circle_rounded),
      'pending' => (Joy.warning, Joy.sunSoft, Icons.schedule_rounded),
      'unverified' => (Joy.warning, Joy.sunSoft, Icons.help_outline_rounded),
      _ => (Joy.textMuted, Joy.surface2, Icons.block_rounded),
    };
    final label = request?.statusLabel ?? (mine ? 'بانتظار الرد' : 'جديد');
    return _Chip(label, color: color, bg: bg, icon: icon);
  }

  /// طلب مبلغ أو تقسيم فاتورة: المستلم يدفع، وصاحب الطلب ينتظر أو يلغي.
  Widget _moneyCard(BuildContext context) {
    final split = code.kind == CodeKind.split;
    final share = request?.share ?? code.share;
    final title = split ? 'تقسيم ${_sar(request?.amount ?? code.amount)} على ${request?.n ?? code.n}' : (mine ? 'تطلب ${_sar(code.amount)}' : '$peerName يطلب ${_sar(code.amount)}');
    final sub = [if (split) (mine ? 'نصيب كل شخص ${_sar(share)}' : 'نصيبك ${_sar(share)}'), if (code.note.isNotEmpty) code.note, if (_status == 'pending' && request?.expiresAt != null) 'ينتهي ${_expiry(request!.expiresAt!)}'].join(' · ');
    return _frame(key: Key('card-req-${code.kind.name}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _head(leading: _CardImage(fallback: split ? Icons.call_split_rounded : Icons.account_balance_wallet_outlined, color: Joy.accent), title: title, subtitle: sub, trailing: _statusChip()),
      _actions([
        // الدفع من المحفظة غير متاح في iOS أو حين يطفئه المدير: يبقى الطلب مقروءاً بلا زر دفع
        if (_status == 'pending' && !mine)
          Consumer(builder: (context, ref, _) => ref.watch(chatMoneyEnabledProvider)
              ? _button(split ? 'ادفع نصيبي ${_sar(share)}' : 'ادفع ${_sar(share)}', 'pay', icon: Icons.payments_outlined, key: const Key('card-pay'))
              : const _Chip('الدفع غير متاح', key: Key('card-pay-off'), color: Joy.textMuted, bg: Joy.surface2)),
        if (_status == 'pending' && !mine) _button('رفض', 'decline', primary: false, key: const Key('card-decline')),
        if (_status == 'pending' && mine && request != null) _button('إلغاء الطلب', 'cancel', primary: false, key: const Key('card-cancel')),
      ]),
    ]));
  }

  Widget _sendCard(BuildContext context) => _frame(key: const Key('card-req-send'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _head(
          leading: const _CardImage(fallback: Icons.send_rounded, color: Joy.success),
          title: mine ? 'أرسلت ${_sar(code.amount)}' : '$peerName أرسل لك ${_sar(code.amount)}',
          subtitle: code.note,
          trailing: _Chip(_status == 'paid' ? 'تم التحويل' : _status == 'unverified' ? 'غير مؤكد' : 'جارٍ التأكيد', color: _status == 'paid' ? Joy.success : Joy.warning, bg: _status == 'paid' ? const Color(0xFFE6F6EC) : Joy.sunSoft, icon: _status == 'paid' ? Icons.check_circle_rounded : Icons.schedule_rounded),
        ),
        _actions([_button('المحفظة', 'wallet', icon: Icons.account_balance_wallet_outlined, primary: false)]),
      ]));

  Widget _meetCard(BuildContext context) {
    final place = card?.title ?? (code.place.startsWith('@') ? code.place.substring(1) : code.place);
    final s = _status;
    return _frame(key: const Key('card-req-meet'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _head(
        leading: _CardImage(url: card?.image, fallback: Icons.handshake_outlined),
        title: 'موعد ${code.note}',
        subtitle: [if (place.isNotEmpty) place, if (card != null && card!.subtitle.isNotEmpty) card!.subtitle].join(' · '),
        trailing: _statusChip(),
      ),
      _actions([
        if (card != null) _button('المكان', 'place', icon: Icons.place_outlined, primary: false),
        // «الاتجاهات» حين يُعرف موقع المكان: من حمولة الرمز أو من الدائرة (GET /biz/:id)
        _MeetDirections(code: code, card: card, busy: busy),
        if (s == 'pending' && !mine) _button('اقترح غيره', 'counter', primary: false, key: const Key('card-counter')),
        if (s == 'pending' && !mine) _button('أوافق', 'accept', icon: Icons.check_rounded, key: const Key('card-accept')),
        if (s == 'pending' && mine && request != null) _button('إلغاء', 'cancel', primary: false, key: const Key('card-cancel')),
      ]),
    ]));
  }

  Widget _whereCard(BuildContext context) => _frame(key: const Key('card-req-where'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _head(leading: const _CardImage(fallback: Icons.person_pin_circle_outlined, color: Joy.accent), title: mine ? 'طلبت موقع $peerName' : 'أين أنت؟', subtitle: mine ? 'يصلك موقعه بضغطة منه' : '$peerName يطلب موقعك الحالي'),
        _actions([if (!mine) _button('شارك موقعي', 'share-loc', icon: Icons.my_location_rounded, key: const Key('card-share-loc'))]),
      ]));

  Widget _locCard(BuildContext context) => _frame(key: const Key('card-req-loc'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        LocPreview(lat: code.lat!, lng: code.lng!),
        const SizedBox(height: 8),
        _head(leading: const _CardImage(fallback: Icons.place_rounded, color: Joy.accent, size: 40), title: mine ? 'موقعي' : 'موقع $peerName', subtitle: code.note.isNotEmpty ? code.note : '${code.lat!.toStringAsFixed(5)}, ${code.lng!.toStringAsFixed(5)}'),
        _actions([_button('اتجاهات', 'directions', icon: Icons.directions_rounded, key: const Key('card-directions'))]),
      ]));

  Widget _inviteCard(BuildContext context) {
    final c = card;
    final isEvent = code.ref?.startsWith('#ev/') == true;
    return _frame(key: const Key('card-req-invite'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(mine ? 'دعوت $peerName' : '$peerName يدعوك', style: const TextStyle(color: Joy.accent, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (c == null && !resolved) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
      else if (c == null) Text(code.ref ?? code.raw, style: const TextStyle(color: Joy.textMuted))
      else _head(
        leading: _CardImage(url: c.image, fallback: isEvent ? Icons.event_rounded : BizCategory.of(c.category).icon, color: isEvent ? Joy.accent : Joy.primary),
        title: c.title, subtitle: isEvent ? [_when(c.startsAt), c.subtitle].where((s) => s.isNotEmpty).join(' · ') : c.subtitle,
      ),
      if (code.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(code.note, style: const TextStyle(fontSize: 13))),
      if (c != null) _actions([_button(isEvent ? 'احجز معي' : 'انضم', 'join', icon: isEvent ? Icons.confirmation_number_outlined : Icons.add_circle_outline_rounded, key: const Key('card-join'))]),
    ]));
  }

  static String _expiry(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'الآن';
    if (d.inHours >= 24) return 'خلال ${d.inDays} يوم';
    if (d.inHours >= 1) return 'خلال ${d.inHours} ساعة';
    return 'خلال ${math.max(1, d.inMinutes)} دقيقة';
  }
}

/// معاينة خريطة ثابتة لنقطة: أربع بلاطات من وكيل البلاطات (server/tiles.js) حول النقطة مع دبوس في المنتصف.
class LocPreview extends ConsumerWidget {
  final double lat, lng;
  final double width, height;
  const LocPreview({super.key, required this.lat, required this.lng, this.width = 260, this.height = 130});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const z = 15;
    final n = math.pow(2, z).toDouble();
    final x = (lng + 180) / 360 * n;
    final latR = lat * math.pi / 180;
    final y = (1 - math.log(math.tan(latR) + 1 / math.cos(latR)) / math.pi) / 2 * n;
    final xi = x.floor(), yi = y.floor();
    final fx = x - xi, fy = y - yi;
    final base = ref.read(apiClientProvider).baseUrl;
    // البلاطة الأصلية وجاراتها في اتجاه أقرب حافة حتى لا يظهر فراغ حول الدبوس
    final dx = fx < .5 ? -1 : 1, dy = fy < .5 ? -1 : 1;
    final tiles = [(xi, yi), (xi + dx, yi), (xi, yi + dy), (xi + dx, yi + dy)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width, height: height,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          for (final (tx, ty) in tiles)
            Positioned(
              left: width / 2 - fx * 256 + (tx - xi) * 256, top: height / 2 - fy * 256 + (ty - yi) * 256,
              child: Image.network('$base/tiles/$z/$tx/$ty.png', width: 256, height: 256, gaplessPlayback: true, errorBuilder: (_, __, ___) => Container(width: 256, height: 256, color: Joy.surface2)),
            ),
          const Positioned.fill(child: IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 26), child: Icon(Icons.location_on_rounded, color: Joy.accent, size: 34))))),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الإكمال التلقائي
// -----------------------------------------------------------------------------

/// الجزء الحالي من حقل الكتابة الذي يمكن إكماله: `@…` أو `#…` عند المؤشر، أو `/أمر` في أول النص.
({int start, String token})? currentCodeToken(String text, int caret) {
  if (text.isEmpty) return null;
  final c = caret < 0 || caret > text.length ? text.length : caret;
  final before = text.substring(0, c);
  final start = before.lastIndexOf(RegExp(r'\s')) + 1;
  final token = before.substring(start);
  if (token.isEmpty) return null;
  if (token[0] == '@' || token[0] == '#') return (start: start, token: token);
  // أمر: أول كلمة في النص فقط
  if (token[0] == '/' && before.substring(0, start).trim().isEmpty) return (start: start, token: token);
  return null;
}

class CodeSuggestion {
  final String label, subtitle, insert;
  final IconData icon;
  /// إجراء بدل الإدراج: picker:ticket | picker:order | picker:wish | guide
  final String? action;
  final String? image;
  const CodeSuggestion({required this.label, this.subtitle = '', required this.insert, required this.icon, this.action, this.image});
}

/// شريط اقتراحات فوق حقل الكتابة: أوامر، أشخاص ودوائر بعد @، دوائر وأصنافها بعد #.
class CodeSuggestions extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final List<Person> people;
  /// يستبدل الرمز الحالي بالنص المدرج (مع فراغ لاحق عند الحاجة).
  final void Function(int start, int end, String insert) onInsert;
  final void Function(String action) onAction;
  const CodeSuggestions({super.key, required this.controller, required this.people, required this.onInsert, required this.onAction});
  @override
  ConsumerState<CodeSuggestions> createState() => _CodeSuggestionsState();
}

class _CodeSuggestionsState extends ConsumerState<CodeSuggestions> {
  ({int start, String token})? _tok;
  List<CodeSuggestion> _items = const [];
  Timer? _debounce;
  final _bizCache = <String, List<Biz>>{};
  final _circleCache = <String, Biz>{};
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _debounce?.cancel();
    super.dispose();
  }

  void _onText() {
    final v = widget.controller.value;
    final tok = currentCodeToken(v.text, v.selection.baseOffset);
    if (tok?.token != _tok?.token || tok?.start != _tok?.start) {
      _tok = tok;
      _compute();
    }
  }

  Future<void> _compute() async {
    final tok = _tok;
    _debounce?.cancel();
    if (tok == null) { if (mounted) setState(() => _items = const []); return; }
    final t = tok.token;
    final gen = ++_gen;
    if (t[0] == '/') {
      final q = t.substring(1).toLowerCase();
      final list = commandsFor(money: ref.read(chatMoneyEnabledProvider)).where((c) => c.trigger.substring(1).startsWith(q)).map((c) => CodeSuggestion(
            label: c.label, subtitle: c.hint, icon: _iconFor(c.trigger), insert: c.trigger == '/loc' || c.trigger == '/me' || c.trigger == '/where' ? c.trigger : '${c.trigger} ',
            action: switch (c.trigger) { '/ticket' => 'picker:ticket', '/order' => 'picker:order', '/wish' => 'picker:wish', '/help' => 'guide', _ => null },
          )).toList();
      setState(() => _items = list);
      return;
    }
    final q = t.substring(1).toLowerCase();
    if (t[0] == '@') {
      final people = widget.people.where((p) => q.isEmpty || p.nickname.toLowerCase().contains(q)).take(4).map((p) => CodeSuggestion(label: p.nickname, subtitle: 'شخص', icon: Icons.person_outline_rounded, insert: '@${p.nickname} ', image: p.avatarUrl)).toList();
      setState(() => _items = people);
      if (q.length >= 2) _searchCircles(q, gen, (list) => setState(() => _items = [...people, for (final b in list) CodeSuggestion(label: b.title, subtitle: 'دائرة · ${b.category.label}', icon: b.category.icon, insert: '${circleCode(b.id)} ', image: b.logoUrl)]));
      return;
    }
    // #دائرة/صنف
    final slash = q.indexOf('/');
    if (slash < 0) {
      if (q.isEmpty) { setState(() => _items = [for (final r in refCatalog.skip(2)) CodeSuggestion(label: r.label, subtitle: r.hint, icon: Icons.tag_rounded, insert: r.trigger == '#' ? '#' : r.trigger)]); return; }
      _searchCircles(q, gen, (list) => setState(() => _items = [for (final b in list) CodeSuggestion(label: b.title, subtitle: 'اختر صنفاً من ${b.category.label}', icon: b.category.icon, insert: '#${shortBiz(b.id)}/', image: b.logoUrl)]));
      return;
    }
    final slug = q.substring(0, slash), part = q.substring(slash + 1);
    if (const ['ev', 'mk', 'post', 'space', 't', 'o', 'job'].contains(slug)) { setState(() => _items = const []); return; }
    var biz = _circleCache[slug];
    if (biz == null) {
      try {
        biz = await ref.read(apiClientProvider).businessCircle(slug.startsWith('biz-') ? slug : 'biz-$slug');
        _circleCache[slug] = biz;
      } catch (_) {
        if (mounted && gen == _gen) setState(() => _items = const []);
        return;
      }
    }
    if (!mounted || gen != _gen) return;
    final b = biz;
    final items = b.items.where((i) => i.active && (part.isEmpty || i.title.toLowerCase().contains(part) || i.id.toLowerCase().contains(part))).take(6);
    setState(() => _items = [for (final i in items) CodeSuggestion(label: i.title, subtitle: '${b.title} · ${i.price == 0 ? 'مجاني' : money(i.price)}', icon: Icons.shopping_bag_outlined, insert: '${itemCode(b.id, i.id)} ', image: i.imageUrl ?? b.logoUrl)]);
  }

  void _searchCircles(String q, int gen, void Function(List<Biz>) done) {
    final cached = _bizCache[q];
    if (cached != null) { done(cached); return; }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = (await ref.read(apiClientProvider).businessCircles(q: q)).take(5).toList();
        _bizCache[q] = list;
        if (mounted && gen == _gen) done(list);
      } catch (_) {}
    });
  }

  static IconData _iconFor(String trigger) => switch (trigger) {
        '/pay' => Icons.account_balance_wallet_outlined, '/send' => Icons.send_rounded, '/split' => Icons.call_split_rounded, '/meet' => Icons.handshake_outlined,
        '/loc' => Icons.my_location_rounded, '/where' => Icons.person_pin_circle_outlined, '/invite' => Icons.card_giftcard_rounded, '/ticket' => Icons.confirmation_number_outlined,
        '/order' => Icons.receipt_long_outlined, '/wish' => Icons.bookmark_added_outlined, '/me' => Icons.badge_outlined, _ => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    // يُبقي إعدادات المنصة محمّلة ليعرف الإكمال التلقائي هل أوامر المال متاحة؛ وتغيّرها يعيد الحساب
    ref.listen(chatMoneyEnabledProvider, (_, __) => _compute());
    final tok = _tok;
    if (tok == null || _items.isEmpty) return const SizedBox.shrink();
    return Material(
      key: const Key('code-suggestions'),
      color: Joy.surface,
      child: Container(
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Joy.line))),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final s = _items[i];
          return ListTile(
            key: Key('suggest-${s.insert.trim()}'),
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: s.image != null ? _CardImage(url: s.image, fallback: s.icon, size: 34) : CircleAvatar(radius: 17, backgroundColor: Joy.primarySoft, child: Icon(s.icon, size: 18, color: Joy.primary)),
            title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: s.subtitle.isEmpty ? null : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
            onTap: () {
              final end = tok.start + tok.token.length;
              if (s.action != null) {
                widget.onInsert(tok.start, end, '');
                widget.onAction(s.action!);
              } else {
                widget.onInsert(tok.start, end, s.insert);
              }
            },
          );
        },
      ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// قائمة «+» ومنتقيات ما أملكه
// -----------------------------------------------------------------------------

/// بند في قائمة الرموز الذكية داخل ورقة «+»: يُرجع 'insert:<نص>' أو 'picker:<نوع>' أو 'guide'.
class CodeMenuItem {
  final String label;
  final IconData icon;
  final String result;
  const CodeMenuItem(this.label, this.icon, this.result);
}

const codeMenuItems = [
  CodeMenuItem('طلب مبلغ', Icons.account_balance_wallet_outlined, 'insert:/pay '),
  CodeMenuItem('إرسال مبلغ', Icons.send_rounded, 'insert:/send '),
  CodeMenuItem('تقسيم فاتورة', Icons.call_split_rounded, 'insert:/split '),
  CodeMenuItem('موقعي', Icons.my_location_rounded, 'insert:/loc'),
  CodeMenuItem('أين أنت؟', Icons.person_pin_circle_outlined, 'insert:/where'),
  CodeMenuItem('موعد', Icons.handshake_outlined, 'insert:/meet '),
  CodeMenuItem('تذكرتي', Icons.confirmation_number_outlined, 'picker:ticket'),
  CodeMenuItem('حجزي', Icons.receipt_long_outlined, 'picker:order'),
  CodeMenuItem('من أمنياتي', Icons.bookmark_added_outlined, 'picker:wish'),
  CodeMenuItem('ملفي', Icons.badge_outlined, 'insert:/me'),
  CodeMenuItem('شخص أو دائرة', Icons.alternate_email_rounded, 'insert:@'),
  CodeMenuItem('صنف', Icons.tag_rounded, 'insert:#'),
  CodeMenuItem('دليل الرموز', Icons.menu_book_outlined, 'guide'),
];

/// شبكة الرموز الذكية داخل ورقة الإرفاق.
class CodesMenuGrid extends ConsumerWidget {
  final void Function(String result) onPick;
  const CodesMenuGrid({super.key, required this.onPick});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(chatMoneyEnabledProvider);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('رموز ذكية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Joy.textMuted))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in codeMenuItems)
              if (money || !isMoneyCommand(it.result.replaceFirst('insert:', '')))
              ActionChip(
                key: Key('code-menu-${it.result}'),
                avatar: Icon(it.icon, size: 17, color: it.result == 'guide' ? Joy.accent : Joy.primary),
                label: Text(it.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                backgroundColor: it.result == 'guide' ? Joy.accentSoft : Joy.primarySoft,
                side: BorderSide.none,
                onPressed: () => onPick(it.result),
              ),
          ]),
        ]),
      );
  }
}

Future<String?> _pickSheet<T>(BuildContext context, {required String title, required Future<List<T>> Function() load, required Widget Function(T) tile, required String empty}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .6,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx))])),
          Expanded(
            child: FutureBuilder<List<T>>(
              future: load(),
              builder: (_, snap) {
                if (snap.hasError) return ErrorState(snap.error!);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) return EmptyState(icon: Icons.inbox_outlined, title: empty);
                return ListView.builder(itemCount: list.length, itemBuilder: (_, i) => tile(list[i]));
              },
            ),
          ),
        ]),
      ),
    );

/// يختار تذكرة من تذاكري ويرجع رمزها `#t/…`.
Future<String?> pickTicketCode(BuildContext context, ApiClient api) => _pickSheet<Ticket>(
      context,
      title: 'اختر تذكرة لمشاركتها',
      load: () async { final l = await api.tickets(); l.sort((a, b) => (b.upcoming ? 1 : 0) - (a.upcoming ? 1 : 0)); return l; },
      empty: 'لا تذاكر لديك بعد',
      tile: (t) => Builder(builder: (ctx) => ListTile(
            key: Key('pick-ticket-${t.code}'),
            leading: CircleAvatar(backgroundColor: Joy.accentSoft, child: Icon(Icons.confirmation_number_outlined, color: t.upcoming ? Joy.accent : Joy.textMuted)),
            title: Text(t.title), subtitle: Text([t.tier, _when(t.startsAt)].where((s) => s.isNotEmpty).join(' · ')),
            trailing: Text(t.code, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
            onTap: () => Navigator.pop(ctx, ticketCode(t.code)),
          )),
    );

/// يختار حجزاً أو طلباً من الدوائر ويرجع رمزه `#o/…`.
Future<String?> pickOrderCode(BuildContext context, ApiClient api) => _pickSheet<BizOrder>(
      context,
      title: 'اختر حجزاً أو طلباً',
      load: () async { final l = await api.myBizOrders(); l.sort((a, b) => (b.upcoming ? 1 : 0) - (a.upcoming ? 1 : 0)); return l; },
      empty: 'لا حجوزات لديك بعد',
      tile: (o) => Builder(builder: (ctx) => ListTile(
            key: Key('pick-order-${o.code}'),
            leading: CircleAvatar(backgroundColor: Joy.primarySoft, child: Icon(o.category.icon, color: o.upcoming ? Joy.primary : Joy.textMuted)),
            title: Text(o.title.isNotEmpty ? o.title : o.kindLabel), subtitle: Text([o.bizName, o.statusLabel, if (o.startAt != null) _when(o.startAt)].where((s) => s.isNotEmpty).join(' · ')),
            trailing: Text(o.code, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
            onTap: () => Navigator.pop(ctx, orderCode(o.code)),
          )),
    );

/// يختار أمنية ويرجع رمز الشيء نفسه مسبوقاً بـ🎁 (أو نصاً للأمنية الحرة).
Future<String?> pickWishCode(BuildContext context, ApiClient api) => _pickSheet<WishItem>(
      context,
      title: 'اختر من أمنياتك',
      load: () async => (await api.wishlist()).where((w) => !w.done).toList(),
      empty: 'قائمة أمنياتك فارغة',
      tile: (w) => Builder(builder: (ctx) => ListTile(
            key: Key('pick-wish-${w.id}'),
            leading: const CircleAvatar(backgroundColor: Joy.accentSoft, child: Icon(Icons.card_giftcard_rounded, color: Joy.accent)),
            title: Text(w.title), subtitle: Text([w.kindLabel, w.subtitle, if (w.price != null) money(w.price!)].where((s) => s.isNotEmpty).join(' · ')),
            onTap: () => Navigator.pop(ctx, wishCode(w)),
          )),
    );

/// رمز أمنية: مرجع الشيء نفسه إن كان مرجعاً، وإلا نص.
String wishCode(WishItem w) {
  final r = w.refId;
  final code = switch (w.kind) {
    'item' when r != null && w.bizId != null => itemCode(w.bizId!, r),
    'market' when r != null => listingCode(r),
    'event' when r != null => eventCode(r),
    'post' when r != null => postCode(r),
    'biz' when r != null => circleCode(r),
    _ => null,
  };
  return code == null ? '🎁 أمنية: ${w.title}' : '🎁 $code';
}

// -----------------------------------------------------------------------------
// دليل الرموز داخل التطبيق
// -----------------------------------------------------------------------------

/// دليل الرموز: القواعد، الإشارات، الأفعال، أمثلة واقعية. إن فُتح من محادثة يعيد المثال المختار ليُدرج في الحقل.
class ChatCodesGuidePage extends ConsumerWidget {
  final bool canInsert;
  const ChatCodesGuidePage({super.key, this.canInsert = false});

  static const _examples = [
    (
      'بين صديقين بعد جلسة قهوة',
      [
        ('sara', '#brew92/v60 جرّبيه، حموضة فواكه واضحة', 'بطاقة الصنف: V60 تقطير · 22 ر.س · زر «اطلب»'),
        ('noura', '/meet 7م @brew92', 'بطاقة موعد: 7م · برو 92 · «أوافق» أو «اقترح غيره»'),
        ('sara', '/pay 22 قهوتك أمس', 'بطاقة طلب مبلغ: 22 ر.س · تنتهي خلال يوم · زر «ادفع»'),
      ],
    ),
    (
      'رحلة عائلية وتقسيم الفاتورة',
      [
        ('khalid', 'العشاء كان 180 على أربعة /split 180 4', 'بطاقة تقسيم: نصيب كل شخص 45 ر.س · «ادفع نصيبي»'),
        ('amr', '/send 45 نصيبي من العشاء', 'بطاقة إرسال: تم التحويل ✓ (بعد تأكيدك من محفظتك)'),
        ('khalid', '/loc', 'بطاقة موقع: خريطة مصغّرة وزر «اتجاهات»'),
      ],
    ),
    (
      'بين عميل وفريق دائرة',
      [
        ('customer', 'هل عندكم #3brews/chemex بحبوب برازيل؟', 'بطاقة الصنف مع السعر وعدد النقاشات'),
        ('staff', 'نعم، وهذا موقعنا @3brews', 'بطاقة الدائرة: الشعار والحي ومفتوح الآن · «افتح»'),
        ('staff', '/invite 3brews تعال نحضّرها لك', 'بطاقة دعوة: «انضم» يتابع الدائرة ويفتحها'),
      ],
    ),
    (
      'مسافران في مساحة المطار',
      [
        ('noura', 'الجوازات مزدحمة الآن #space/kaia', 'بطاقة المساحة: عدد المشاركات · «افتح النقاش»'),
        ('faisal', '/where', 'بطاقة «أين أنت؟» وزر «شارك موقعي» عند المستلم'),
        ('noura', '/ticket', 'تختار تذكرتك فتظهر بطاقة الفعالية ورمزها'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // بلا أوامر المال (iOS أو مطفأة): لا تُذكر في القواعد ولا الأفعال ولا الأمثلة
    final money = ref.watch(chatMoneyEnabledProvider);
    final moneyRe = RegExp(r'/(pay|send|split)\b');
    final examples = [
      for (final (title, lines) in _examples)
        if (money)
          (title, lines)
        // مثال يبدأ بأمر مال غرضه المال (مثل «تقسيم الفاتورة»)؛ إبقاء بقية سطوره يترك عنواناً مالياً بلا معنى
        else if (!moneyRe.hasMatch(lines.first.$2) && lines.any((l) => !moneyRe.hasMatch(l.$2)))
          (title, [for (final l in lines) if (!moneyRe.hasMatch(l.$2)) l]),
    ];
    void pick(String s) {
      if (canInsert) {
        Navigator.pop(context, s);
      } else {
        Clipboard.setData(ClipboardData(text: s));
        toast(context, 'نُسخ: $s');
      }
    }
    Widget code(String s, {Key? key}) => InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: () => pick(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(8)),
            child: Text(s, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w700, fontSize: 13, color: Joy.primary)),
          ),
        );
    Widget entry(CodeEntry e, IconData icon, {Key? key}) => JoyCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 18, backgroundColor: Joy.primarySoft, child: Icon(icon, size: 18, color: Joy.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(e.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))), code(e.example, key: key)]),
                const SizedBox(height: 2),
                Text(e.hint, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(color: Joy.textMuted, fontSize: 12, fontFamily: AppTheme.bodyFont)),
                const SizedBox(height: 4),
                Text(e.description, style: const TextStyle(fontSize: 13, height: 1.5)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('دليل رموز المحادثة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        JoyCard(
          color: Joy.primarySoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ثلاثة مفاتيح فقط', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            _rule('@', 'شخص أو دائرة', '@sara · @brew92'),
            _rule('#', 'صنف أو فعالية أو عرض أو منشور', '#brew92/v60 · #ev/…'),
            money ? _rule('/', 'فعل: مبلغ، موقع، موعد، دعوة', '/pay 45 · /meet 7م @brew92') : _rule('/', 'فعل: موقع، موعد، دعوة', '/loc · /meet 7م @brew92'),
            const SizedBox(height: 8),
            const Text('اكتب الرمز في حقل الرسالة فيظهر اقتراح فوري، وعند الإرسال يتحوّل إلى بطاقة بزر واحد عند الطرفين. الرمز غير الصحيح يبقى نصاً عادياً.', style: TextStyle(fontSize: 13, height: 1.6)),
            if (canInsert) const Padding(padding: EdgeInsets.only(top: 6), child: Text('اضغط أي مثال ليُدرج في حقل الكتابة.', style: TextStyle(fontSize: 12.5, color: Joy.primary, fontWeight: FontWeight.w600))),
          ]),
        ),
        const SectionTitle('أولاً: الإشارة إلى شيء'),
        for (final e in refCatalog) Padding(padding: const EdgeInsets.only(bottom: 8), child: entry(e, e.trigger == '@' ? Icons.alternate_email_rounded : Icons.tag_rounded)),
        const SectionTitle('ثانياً: الأفعال'),
        for (final e in commandsFor(money: money)) Padding(padding: const EdgeInsets.only(bottom: 8), child: entry(e, _CodeSuggestionsState._iconFor(e.trigger), key: Key('guide-${e.trigger}'))),
        const SectionTitle('أمثلة واقعية'),
        for (final (title, lines) in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: JoyCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 8),
                for (final (who, text, result) in lines) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$who: ', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    Expanded(child: InkWell(onTap: () => pick(text), child: Text(text, style: const TextStyle(fontSize: 14)))),
                  ]),
                  Padding(padding: const EdgeInsetsDirectional.only(start: 14, bottom: 8), child: Row(children: [const Icon(Icons.subdirectory_arrow_left_rounded, size: 14, color: Joy.textMuted), const SizedBox(width: 4), Expanded(child: Text(result, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)))])),
                ],
              ]),
            ),
          ),
        const SectionTitle('قواعد وأمان'),
        const JoyCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Bullet('البطاقة تحمل المعرّف فقط، والخادم يجلب الاسم والسعر عند العرض، فلا يمكن تزوير سعر أو مبلغ.'),
            _Bullet('طلبات المال تنتهي بعد يوم، وبطاقة الموعد بعد ثلاثة أيام.'),
            _Bullet('الدفع يخرج من محفظتك فقط بعد ضغطة «ادفع» منك، والإرسال بعد تأكيدك.'),
            _Bullet('التذاكر والحجوزات لا يرسلها إلا صاحبها من قائمته.'),
            _Bullet('من ينسخ رمز دائرة أو حساب يجد «انسخ الرمز» في ورقة المشاركة، ورمز الصنف بجانب زر النقاش.'),
          ]),
        ),
      ]),
    );
  }

  static Widget _rule(String k, String what, String ex) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(8)), child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Joy.primary))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(what, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(ex, textDirection: TextDirection.ltr, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12, fontFamily: AppTheme.bodyFont)),
            ]),
          ),
        ]),
      );
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w800)), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)))]),
      );
}

// -----------------------------------------------------------------------------
// زر الاتجاهات في بطاقة الموعد
// -----------------------------------------------------------------------------

/// «الاتجاهات» لبطاقة الموعد: الإحداثيات من حمولة الرمز إن وُجدت، وإلا من الدائرة المحلولة (GET /biz/:id)؛ يختفي حين لا موقع.
class _MeetDirections extends ConsumerStatefulWidget {
  final ChatCode code;
  final ChatCard? card;
  final bool busy;
  const _MeetDirections({required this.code, this.card, this.busy = false});
  @override
  ConsumerState<_MeetDirections> createState() => _MeetDirectionsState();
}

class _MeetDirectionsState extends ConsumerState<_MeetDirections> {
  static final _cache = <String, LatLng?>{};
  LatLng? _point;

  @override
  void initState() { super.initState(); _resolve(); }
  @override
  void didUpdateWidget(_MeetDirections old) { super.didUpdateWidget(old); if (old.card?.id != widget.card?.id) _resolve(); }

  Future<void> _resolve() async {
    final c = widget.code;
    if (c.lat != null && c.lng != null) { setState(() => _point = LatLng(c.lat!, c.lng!)); return; }
    final card = widget.card;
    if (card == null || card.type != 'biz') { if (_point != null) setState(() => _point = null); return; }
    final id = card.bizId ?? card.id;
    if (_cache.containsKey(id)) { setState(() => _point = _cache[id]); return; }
    try {
      final b = await ref.read(apiClientProvider).businessCircle(id);
      final p = b.lat.abs() > 0.0001 || b.lng.abs() > 0.0001 ? LatLng(b.lat, b.lng) : null;
      _cache[id] = p;
      if (mounted) setState(() => _point = p);
    } catch (_) {
      // بلا موقع للدائرة: لا زر
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _point;
    if (p == null) return const SizedBox.shrink();
    return OutlinedButton(
      key: const Key('card-meet-directions'),
      style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(0, 36)), padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)), visualDensity: VisualDensity.compact),
      onPressed: widget.busy ? null : () => openDirections(p.latitude, p.longitude),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions_rounded, size: 16), SizedBox(width: 5), Text('الاتجاهات')]),
    );
  }
}

// -----------------------------------------------------------------------------
// بطاقة الموقع المباشر
// -----------------------------------------------------------------------------

/// بطاقة «/live &lt;id&gt;»: خريطة مصغّرة (بلاطات الخادم نفسها) بنقطة نابضة على آخر موقع، «يتحرك الآن · آخر تحديث قبل N ث»،
/// عدّ تنازلي «حتى HH:MM»، زر «الاتجاهات»، ولصاحبها «إيقاف المشاركة». تقرأ GET /chat/live/:id كل عشر ثوانٍ ما دامت
/// معروضة والجلسة نشطة، ثم تعرض «انتهت المشاركة» بلا خريطة (آخر موقع لا يبقى معروضاً بعد الانتهاء). تكفّ عن القراءة عند أي
/// رفض (404/403/400…) وبعد ثلاث محاولات متتالية فاشلة (5xx/429 أو ردّ غير مفهوم) تعرض «تعذّر تحميل الموقع».
class LiveLocationCard extends ConsumerStatefulWidget {
  final String id;
  final bool mine;
  final String peerName;
  /// فاصل القراءة (ثابت؛ الاختبارات تحرّك الزمن الوهمي).
  static const pollEvery = Duration(seconds: 10);
  const LiveLocationCard({super.key, required this.id, required this.mine, required this.peerName});
  @override
  ConsumerState<LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends ConsumerState<LiveLocationCard> with SingleTickerProviderStateMixin {
  LiveSession? _s;
  bool _loaded = false, _gone = false, _failed = false, _stopping = false;
  /// إخفاقات متتالية غير الشبكة (5xx/429/ردّ غير مفهوم)؛ عند [_maxFails] نكفّ عن القراءة
  int _fails = 0;
  static const _maxFails = 3;
  Timer? _poll, _clock;
  final _map = MapController();
  bool _mapReady = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _active => _s?.active == true && !(_s?.expired ?? true);

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(LiveLocationCard.pollEvery, (_) => _fetch());
    // «قبل N ث» يتحدّث كل ثانية ما دامت الجلسة نشطة
    _clock = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && _active && _s?.at != null) setState(() {}); });
  }

  @override
  void dispose() {
    _poll?.cancel(); _clock?.cancel(); _pulse.dispose(); _map.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted || _gone || (_loaded && !_active)) { _stopPolling(); return; }
    try {
      final s = await ref.read(apiClientProvider).liveGet(widget.id);
      if (!mounted) return;
      _fails = 0;
      final moved = s.hasPosition && (s.lat != _s?.lat || s.lng != _s?.lng);
      setState(() { _s = s; _loaded = true; });
      if (moved && _mapReady && _active) _map.move(LatLng(s.lat!, s.lng!), 15);
      if (_active) { if (!_pulse.isAnimating) _pulse.repeat(); } else { _pulse.stop(); _stopPolling(); }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.isNetwork) return; // بلا شبكة: القراءة التالية بعد عشر ثوانٍ
      // رفض نهائي (404/403/400…) = لا جلسة؛ تعثّر الخادم (5xx/429) أو ردّ غير مفهوم: ثلاث محاولات متتالية ثم نكفّ عن القراءة
      final rejected = e is ApiException && e.statusCode < 500 && e.statusCode != 429;
      if (!rejected && ++_fails < _maxFails) return;
      setState(() { _gone = true; _loaded = true; _failed = !rejected; });
      _pulse.stop(); _stopPolling();
    }
  }

  void _stopPolling() { _poll?.cancel(); _poll = null; _clock?.cancel(); _clock = null; }

  Future<void> _stop() async {
    final s = _s; if (s == null) return;
    setState(() => _stopping = true);
    try {
      await LiveShareController.stopSession(ref.read(apiClientProvider), s.id);
      if (!mounted) return; // غادر المحادثة قبل ردّ الخادم: المتحكّمات أُتلفت في dispose
      setState(() { _s = s.copyWith(active: false); _stopping = false; });
      _pulse.stop(); _stopPolling();
    } on Exception {
      // فشل الطلب فقط (شبكة/خادم)؛ أخطاء البرمجة لا تُبتلع
      if (mounted) { setState(() => _stopping = false); toast(context, 'تعذّر الإيقاف الآن', error: true); }
    }
  }

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'قبل ${math.max(0, d.inSeconds)} ث';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
    return 'قبل ${d.inHours} س';
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final active = _active;
    final base = ref.read(apiClientProvider).baseUrl;
    final title = widget.mine ? 'موقعي المباشر' : 'موقع ${widget.peerName} المباشر';
    final status = _gone
        ? (_failed ? 'تعذّر تحميل الموقع' : 'انتهت المشاركة')
        : s == null
            ? (_loaded ? 'انتهت المشاركة' : 'جارٍ التحميل…')
            : !active
                ? 'انتهت المشاركة'
                : s.at == null
                    ? 'بانتظار أول موقع…'
                    : 'يتحرك الآن · آخر تحديث ${_ago(s.at!)}';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // الخريطة ما دامت الجلسة نشطة فقط: بعد الانتهاء لا يُعرض آخر موقع (والخادم لا يعيده أصلاً)
        if (s != null && active && s.hasPosition)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 260, height: 130,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: LatLng(s.lat!, s.lng!), initialZoom: 15,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  onMapReady: () => _mapReady = true,
                ),
                children: [
                  TileLayer(urlTemplate: '$base/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
                  MarkerLayer(markers: [Marker(point: LatLng(s.lat!, s.lng!), width: 44, height: 44, child: _PulseDot(pulse: _pulse))]),
                ],
              ),
            ),
          )
        else
          Container(
            width: 260, height: 70, alignment: Alignment.center,
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(10)),
            child: _gone || (s != null && !active) || (_loaded && s == null)
                ? Icon(_failed ? Icons.cloud_off_outlined : Icons.location_off_outlined, color: Joy.textMuted)
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: (active ? Joy.success : Joy.textMuted).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(active ? Icons.share_location_rounded : Icons.location_off_outlined, color: active ? Joy.success : Joy.textMuted, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Joy.text)),
              Text(status, key: const Key('card-live-status'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? Joy.success : Joy.textMuted, fontSize: 12.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
          if (s != null && active) ...[
            const SizedBox(width: 8),
            _Chip('حتى ${clockOf(s.until)}', key: const Key('card-live-until'), icon: Icons.timer_outlined),
          ],
        ]),
        if (s != null && (active || widget.mine))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.end, children: [
              if (widget.mine && active)
                OutlinedButton.icon(
                  key: const Key('card-live-stop'),
                  style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(0, 36)), padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)), visualDensity: VisualDensity.compact, foregroundColor: WidgetStateProperty.all(Joy.danger)),
                  onPressed: _stopping ? null : _stop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16), label: const Text('إيقاف المشاركة'),
                ),
              if (active && s.hasPosition)
                FilledButton.icon(
                  key: const Key('card-live-directions'),
                  style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(0, 36)), padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)), visualDensity: VisualDensity.compact),
                  onPressed: () => openDirections(s.lat!, s.lng!),
                  icon: const Icon(Icons.directions_rounded, size: 16), label: const Text('الاتجاهات'),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// نقطة نابضة على آخر موقع: قرص ثابت وهالة تتمدّد وتتلاشى (تُرسم ما دامت الجلسة نشطة فقط).
class _PulseDot extends StatelessWidget {
  final Animation<double> pulse;
  const _PulseDot({required this.pulse});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          final t = pulse.value;
          return Stack(alignment: Alignment.center, children: [
            Container(width: 14 + 30 * t, height: 14 + 30 * t, decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.primary.withValues(alpha: (1 - t) * .35))),
            Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.primary, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)])),
          ]);
        },
      );
}

