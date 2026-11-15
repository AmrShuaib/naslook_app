import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/ticket_share_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'events_page.dart';

final _claimPreviewProvider = FutureProvider.autoDispose.family<TicketClaimPreview, String>((ref, token) => ref.watch(apiClientProvider).ticketClaimPreview(token));

/// وجهة رابط تذكرة (`naslife.app/t/<رمز>`) بعد الدخول: معاينة التذكرة ومن أرسلها ثم «استلم التذكرة».
/// الرابط لشخص واحد، فمن يفتحه بعد استلامه أو استرجاعه يرى أنه لم يعد متاحاً.
class TicketClaimPage extends ConsumerStatefulWidget {
  final String token;
  const TicketClaimPage({super.key, required this.token});

  @override
  ConsumerState<TicketClaimPage> createState() => _TicketClaimPageState();
}

class _TicketClaimPageState extends ConsumerState<TicketClaimPage> {
  bool _busy = false, _done = false;
  // رمز الرفض من الخادم عند الاستلام: gone | self | not-found
  String? _fail;

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).claimTicket(widget.token);
      ref.invalidate(ticketsProvider);
      ref.invalidate(ticketSharesProvider);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      final code = e is ApiException ? '${e.body?['error'] ?? ''}' : '';
      if (!mounted) return;
      if (const {'gone', 'self', 'not-found'}.contains(code)) {
        setState(() => _fail = code);
      } else {
        toast(context, ticketShareErrText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _myTickets() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MyTicketsPage()));

  @override
  Widget build(BuildContext context) {
    final pv = ref.watch(_claimPreviewProvider(widget.token));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('تذكرة لك')),
      body: pv.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is ApiException && e.statusCode == 404
            ? _state(Icons.link_off_rounded, 'الرابط غير صحيح', 'لم نجد تذكرة بهذا الرابط. اطلب من صاحبك أن يرسله من جديد.', key: 'claim-not-found')
            : ErrorState(e, onRetry: () => ref.invalidate(_claimPreviewProvider(widget.token))),
        data: (p) {
          if (_done) return _state(Icons.check_circle_rounded, 'التذكرة صارت لك', 'تجدها في «تذاكري» برمز دخول جديد خاص بك.', key: 'claim-done', color: Joy.success, tickets: true);
          if (_fail == 'self') return _state(Icons.person_rounded, 'هذه تذكرتك أنت', 'هذا رابط تذكرة أرسلتها أنت. أرسله لمن تريد أن يحضر معك.', key: 'claim-self', tickets: true);
          if (_fail == 'not-found') return _state(Icons.link_off_rounded, 'الرابط غير صحيح', 'لم نجد تذكرة بهذا الرابط. اطلب من صاحبك أن يرسله من جديد.', key: 'claim-not-found');
          if (_fail == 'gone' || !p.pending) return _state(Icons.block_rounded, 'التذكرة لم تعد متاحة', 'استلمها شخص آخر أو استرجعها صاحبها. الرابط لشخص واحد.', key: 'claim-gone');
          return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            JoyCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(name: p.fromName, url: p.fromAvatar, size: 44),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${p.fromName.isEmpty ? 'صاحبك' : p.fromName} أرسل لك تذكرة', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                ]),
                const Divider(height: 24),
                Text(p.title, key: const Key('claim-title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                const SizedBox(height: 6),
                Text([p.tier, when(p.startsAt), p.placeName ?? ''].where((s) => s.isNotEmpty).join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.6)),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(key: const Key('claim-accept'), onPressed: _busy ? null : _claim, icon: const Icon(Icons.confirmation_number_outlined), label: Text(_busy ? 'جارٍ الاستلام…' : 'استلم التذكرة')),
            const SizedBox(height: 10),
            const Text('الاستلام مجاني. بعده تصير التذكرة في حسابك برمز دخول جديد.', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ]);
        },
      ),
    );
  }

  Widget _state(IconData icon, String title, String sub, {required String key, Color color = Joy.textMuted, bool tickets = false}) => Center(
        key: Key(key),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, height: 1.6)),
            if (tickets) ...[
              const SizedBox(height: 16),
              FilledButton(key: const Key('claim-my-tickets'), onPressed: _myTickets, child: const Text('تذاكري')),
            ],
          ]),
        ),
      );
}
