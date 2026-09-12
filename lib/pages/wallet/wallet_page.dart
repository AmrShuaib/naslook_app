import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/session.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/my_bookings_page.dart';
import '../events/events_page.dart';

final walletProvider = FutureProvider<Wallet>((ref) => ref.watch(apiClientProvider).wallet());
final walletTxProvider = FutureProvider<List<WalletTx>>((ref) => ref.watch(apiClientProvider).walletTransactions());

class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final me = ref.watch(appStateProvider.select((s) => s.user));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('المحفظة'), actions: [IconButton(icon: const Icon(Icons.qr_code_2_rounded), tooltip: 'رمزي', onPressed: () => _myQr(context, me))]),
      body: w.when(
        data: (wallet) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(walletProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(color: Joy.primary, borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('الرصيد المتاح', style: TextStyle(color: Joy.primaryOn, fontSize: 12.5)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shield_outlined, size: 13, color: Joy.primaryOn), SizedBox(width: 4), Text('محمي بالرقم السري', style: TextStyle(color: Joy.primaryOn, fontSize: 11))])),
                  ]),
                  const SizedBox(height: 6),
                  Text(money(wallet.balance), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Joy.primaryOn, fontSize: 34)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('نقاط ناس لايف · ${wallet.points}', style: const TextStyle(color: Joy.primaryOn, fontSize: 12)),
                    const Spacer(),
                    Text(me?.id ?? '', style: const TextStyle(color: Joy.primaryOn, fontSize: 11.5)),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                _action(Icons.send_rounded, 'تحويل', () => _transfer(context, ref)),
                _action(Icons.qr_code_scanner_rounded, 'دفع', () => _pay(context, ref)),
                _action(Icons.confirmation_number_outlined, 'تذاكري', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage()))),
                _action(Icons.receipt_long_outlined, 'حجوزاتي', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage()))),
                if (wallet.testTopup) _action(Icons.add_rounded, 'شحن', () => _topup(context, ref)),
              ]),
              const SizedBox(height: 18),
              SectionTitle('آخر الحركات', action: 'كشف الحساب', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatementPage()))),
              if (wallet.recent.isEmpty) const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'لا حركات بعد', subtitle: 'رصيدك يُشحن عبر الإدارة حالياً، وتظهر هنا مشترياتك وتحويلاتك.'),
              JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, t) in wallet.recent.indexed) TxRow(t, last: i == wallet.recent.length - 1)])),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(walletProvider)),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            Container(width: 54, height: 54, decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Joy.line)), child: Icon(icon, color: Joy.primary)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
      );

  void _myQr(BuildContext context, SessionUser? me) {
    if (me == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اعرض هذا الرمز ليدفع لك أو يحوّل إليك', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: QrImageView(data: 'naslife:pay:${me.id}', size: 200)),
          const SizedBox(height: 10),
          Text('${me.nickname} · ${me.id}', style: const TextStyle(color: Joy.textMuted)),
        ]),
      ),
    );
  }

  Future<void> _transfer(BuildContext context, WidgetRef ref, {String? to}) async {
    final contacts = ref.read(contactsProvider).value ?? const <Person>[];
    final handle = TextEditingController(text: to ?? ''), amount = TextEditingController(), note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (contacts.isNotEmpty)
            SizedBox(height: 74, child: ListView(scrollDirection: Axis.horizontal, children: [for (final c in contacts) Padding(padding: const EdgeInsets.only(left: 10), child: InkWell(onTap: () => handle.text = c.nickname, child: Column(children: [Avatar(name: c.nickname, url: c.avatarUrl, size: 44), Text(c.nickname, style: const TextStyle(fontSize: 11))])))])),
          TextField(controller: handle, decoration: const InputDecoration(labelText: 'إلى (النك نيم أو المعرّف)')),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ بالريال')),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تحويل'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    final halalas = ((double.tryParse(amount.text.replaceAll('،', '.')) ?? 0) * 100).round();
    if (halalas <= 0) { toast(context, 'أدخل مبلغاً صحيحاً', error: true); return; }
    try {
      final api = ref.read(apiClientProvider);
      var id = handle.text.trim();
      if (!RegExp(r'^[A-Z]{2}\d{7}$').hasMatch(id)) id = (await api.userByHandle(id.toLowerCase())).id;
      await api.walletTransfer(id, halalas, note: note.text.trim());
      ref.invalidate(walletProvider);
      if (context.mounted) toast(context, 'تم تحويل ${money(halalas)}');
    } catch (e) {
      if (context.mounted) toast(context, _err(e), error: true);
    }
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final code = await askText(context, title: 'الدفع', hint: 'الصق رمز المستلم (naslife:pay:…) أو نك نيمه', confirm: 'متابعة', maxLines: 1);
    if (code == null || code.isEmpty) return;
    final to = code.startsWith('naslife:pay:') ? code.substring('naslife:pay:'.length) : code;
    if (context.mounted) await _transfer(context, ref, to: to);
  }

  Future<void> _topup(BuildContext context, WidgetRef ref) async {
    final v = await askText(context, title: 'شحن تجريبي', hint: 'المبلغ بالريال', confirm: 'شحن', maxLines: 1);
    final halalas = ((double.tryParse(v ?? '') ?? 0) * 100).round();
    if (halalas <= 0) return;
    try {
      await ref.read(apiClientProvider).walletTopup(halalas);
      ref.invalidate(walletProvider);
    } catch (e) {
      if (context.mounted) toast(context, _err(e), error: true);
    }
  }
}

String _err(Object e) {
  final s = e.toString();
  if (s.contains('insufficient-funds')) return 'الرصيد غير كافٍ';
  if (s.contains('topup-disabled')) return 'الشحن غير مفعّل';
  if (s.contains('not-found')) return 'المستلم غير موجود';
  return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
}

class TxRow extends StatelessWidget {
  final WalletTx t;
  final bool last;
  const TxRow(this.t, {super.key, this.last = false});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Joy.line))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          t.peer != null && t.peer!.nickname.isNotEmpty
              ? ProfileAvatar(person: t.peer!, size: 40)
              : Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(_icon(t.kind), size: 20, color: Joy.text)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.note?.isNotEmpty == true ? t.note! : t.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${t.label}${t.peer != null && t.peer!.nickname.isNotEmpty ? ' · ${t.peer!.nickname}' : ''} · ${timeAgo(t.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ])),
          Text('${t.positive ? '+' : '−'}${money(t.amount.abs())}', style: TextStyle(fontWeight: FontWeight.w700, color: t.positive ? Joy.success : Joy.text)),
        ]),
      );
  IconData _icon(String k) => switch (k) { 'ticket' || 'ticket_sale' => Icons.confirmation_number_outlined, 'market' || 'market_sale' => Icons.shopping_bag_outlined, 'topup' || 'credit' => Icons.add_rounded, 'refund' || 'biz_refund' => Icons.replay_rounded, 'biz' => Icons.storefront_outlined, _ => Icons.swap_horiz_rounded };
}

class StatementPage extends ConsumerWidget {
  const StatementPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = ref.watch(walletTxProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('كشف الحساب')),
      body: tx.when(
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا حركات بعد')
            : ListView(padding: const EdgeInsets.all(20), children: [JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, t) in list.indexed) TxRow(t, last: i == list.length - 1)]))]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(walletTxProvider)),
      ),
    );
  }
}
