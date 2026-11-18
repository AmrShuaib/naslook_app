import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/invite_api.dart';
import '../../core/app_theme.dart';
import '../../core/share/share_links.dart';
import '../../ui/launch_splash.dart';
import '../../ui/widgets.dart';

/// بطاقة الدعوة: يُبرزها المستخدم لمن أمامه فيمسح الرمز بكاميرا جواله، وتُفتح له صفحة الترحيب ثم التسجيل
/// (server/invite.js). الرمز ثابت للمستخدم، ومن يسجّل به يُحتسب له.
class InviteCardPage extends ConsumerWidget {
  const InviteCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(myInviteProvider);
    return Scaffold(
      key: const Key('invite-card-page'),
      appBar: AppBar(title: const Text('بطاقة الدعوة')),
      body: info.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.wifi_off_rounded, title: 'تعذّر تحميل بطاقتك', subtitle: 'تحقق من الاتصال ثم حاول مرة أخرى.', actionLabel: 'إعادة المحاولة', onAction: () => ref.invalidate(myInviteProvider), actionKey: const Key('invite-retry')),
        data: (i) => ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: InviteCard(url: i.url))),
          const SizedBox(height: 18),
          Text(
            i.joined == 0 ? 'أبرز البطاقة لمن أمامك ليمسح الرمز بكاميرا جواله.' : 'انضم بدعوتك: ${i.joined}',
            key: const Key('invite-joined'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: i.joined == 0 ? Joy.textMuted : Joy.text, fontWeight: i.joined == 0 ? FontWeight.w400 : FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              key: const Key('invite-share'),
              onPressed: () => shareLink(context, title: 'انضم إليّ في ناس لايف', url: i.url, subtitle: 'رابط دعوتك'),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('أرسل الرابط'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// وجه البطاقة: الشعار والاسم والجملة، ثم الرمز على أرضية داكنة، وشريط ألوان الشعار في الأسفل.
class InviteCard extends StatelessWidget {
  final String url;
  const InviteCard({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('invite-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x29141E2D), blurRadius: 34, offset: Offset(0, 14))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(children: [
            Image.asset(LaunchSplash.asset, width: 150, errorBuilder: (_, __, ___) => const SizedBox(height: 8)),
            const SizedBox(height: 6),
            const Text('ناسك وأماكنك في خريطة واحدة', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Joy.textMuted, height: 1.6)),
          ]),
        ),
        Container(
          width: double.infinity,
          color: Joy.text,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(key: const Key('invite-qr'), data: url, size: 210, errorCorrectionLevel: QrErrorCorrectLevel.Q),
            ),
            const SizedBox(height: 14),
            const Text('امسح وانضم', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.3)),
            const Text('وجّه كاميرا جوالك إلى الرمز', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 15)),
          ]),
        ),
        SizedBox(height: 6, child: Row(children: [for (final c in const [Joy.primary, Joy.success, Joy.sun, Joy.accent]) Expanded(child: ColoredBox(color: c))])),
      ]),
    );
  }
}
