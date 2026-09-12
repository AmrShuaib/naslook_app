import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/push/push_service.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../business/my_bookings_page.dart';
import '../events/events_page.dart';
import '../market/market_page.dart';
import '../wallet/wallet_page.dart';

class MySpacePage extends ConsumerWidget {
  const MySpacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(appStateProvider.select((s) => s.user));
    final profile = ref.watch(profileProvider);
    final presence = ref.watch(myPresenceProvider);
    final vessels = ref.watch(myVesselsProvider).value ?? const <Vessel>[];
    final contacts = ref.watch(contactsProvider).value ?? const <Person>[];
    final p = profile.value;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(profileProvider);
        ref.invalidate(myPresenceProvider);
        ref.invalidate(contactsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          JoyCard(
            child: Column(children: [
              Row(children: [
                Avatar(name: me?.nickname ?? '', url: p?.avatarUrl ?? me?.avatarUrl, size: 72, ring: true),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me?.nickname ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
                  Text(p?.bio.isNotEmpty == true ? p!.bio : 'أضف نبذة قصيرة عنك', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
                  const SizedBox(height: 6),
                  presence.when(
                    data: (mp) => Row(children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: mp.visible ? Joy.success : Joy.textMuted, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(mp.visible ? 'ظاهر على الخريطة' : 'مخفي عن الخريطة', style: TextStyle(fontSize: 12, color: mp.visible ? Joy.success : Joy.textMuted)),
                    ]),
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                  ),
                ])),
                IconButton(tooltip: 'تعديل', onPressed: () => _edit(context, ref, p), icon: const Icon(Icons.edit_rounded, color: Joy.primary)),
              ]),
              const Divider(height: 24),
              Row(children: [
                _stat('${vessels.length}', 'دوائر'),
                _stat('${contacts.length}', 'أصدقاء'),
                _stat('${p?.skills.length ?? 0}', 'مهارات'),
                _stat('${p?.offerings.length ?? 0}', 'عروض'),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          JoyCard(padding: EdgeInsets.zero, child: Column(children: [
            ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: Joy.primary), title: const Text('المحفظة'), subtitle: const Text('الرصيد والتحويلات والدفع'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.confirmation_number_outlined, color: Joy.accent), title: const Text('تذاكري'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.receipt_long_outlined, color: Joy.primary), title: const Text('حجوزاتي وطلباتي'), subtitle: const Text('فنادق وسيارات وسينما وبراندات'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.storefront_outlined, color: Joy.sunText), title: const Text('عروضي وطلباتي في السوق'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage()))),
          ])),
          const SizedBox(height: 14),
          if (p != null && (p.skills.isNotEmpty || p.hobbies.isNotEmpty || p.lookingFor.isNotEmpty)) ...[
            const SectionTitle('عني'),
            JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (p.skills.isNotEmpty) _chips('مهاراتي', p.skills, Joy.primarySoft, Joy.primary),
              if (p.hobbies.isNotEmpty) _chips('هواياتي', p.hobbies, Joy.sunSoft, Joy.sunText),
              if (p.lookingFor.isNotEmpty) _chips('أبحث عن', p.lookingFor, Joy.accentSoft, Joy.accent),
            ])),
            const SizedBox(height: 14),
          ],
          const SectionTitle('الإشعارات'),
          const JoyCard(padding: EdgeInsets.zero, child: _PushTile()),
          const SizedBox(height: 14),
          const SectionTitle('الخصوصية والموقع'),
          JoyCard(
            padding: EdgeInsets.zero,
            child: presence.when(
              data: (mp) => Column(children: [
                SwitchListTile(
                  value: mp.visible,
                  onChanged: (v) => _toggleVisible(context, ref, mp, v),
                  title: const Text('الظهور على الخريطة'),
                  subtitle: Text(mp.lat == null ? 'حدّد مكانك من الخريطة أولاً (ضغطة مطوّلة)' : (mp.title.isNotEmpty ? mp.title : 'المكان الذي اخترته على الخريطة')),
                  secondary: const Icon(Icons.map_rounded, color: Joy.text),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Joy.text),
                  title: const Text('إخفاء تلقائي'),
                  subtitle: Text(_hoursLabel(mp.hideAfterHours)),
                  trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
                  onTap: () => _pickHours(context, ref, mp),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  value: p?.isPublic ?? true,
                  onChanged: p == null ? null : (v) => _save(context, ref, {'isPublic': v}),
                  title: const Text('ملف عام'),
                  subtitle: const Text('غير العام يراه أصدقاؤك فقط'),
                  secondary: const Icon(Icons.shield_outlined, color: Joy.text),
                ),
              ]),
              loading: () => const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()),
              error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: ErrorState(e, onRetry: () => ref.invalidate(myPresenceProvider))),
            ),
          ),
          const SizedBox(height: 14),
          const SectionTitle('الحساب'),
          JoyCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(leading: const Icon(Icons.person_outline_rounded, color: Joy.text), title: const Text('النك نيم'), subtitle: Text(me?.nickname ?? ''), trailing: Text(me?.id ?? '', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Joy.danger),
                title: const Text('تسجيل الخروج', style: TextStyle(color: Joy.danger)),
                onTap: () => ref.read(appStateProvider.notifier).logout(),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stat(String n, String l) => Expanded(child: Column(children: [Text(n, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)), Text(l, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]));

  Widget _chips(String title, List<String> items, Color bg, Color fg) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in items) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(s, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)))]),
        ]),
      );

  String _hoursLabel(int? h) => switch (h) { null || 0 => 'يبقى حتى تُطفئه', 1 => 'بعد ساعة', 6 => 'بعد 6 ساعات', 24 => 'بعد 24 ساعة', 168 => 'بعد أسبوع', _ => 'بعد $h ساعة' };

  Future<void> _toggleVisible(BuildContext context, WidgetRef ref, MyPresence mp, bool v) async {
    if (v && mp.lat == null) {
      toast(context, 'اضغط مطوّلاً على الخريطة لتحديد مكانك أولاً');
      return;
    }
    try {
      await ref.read(apiClientProvider).setPresence(visible: v);
      ref.invalidate(myPresenceProvider);
      ref.invalidate(presenceProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _pickHours(BuildContext context, WidgetRef ref, MyPresence mp) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final h in [0, 1, 6, 24, 168])
          ListTile(
            leading: Icon((mp.hideAfterHours ?? 0) == h ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: Joy.primary),
            title: Text(_hoursLabel(h)),
            onTap: () => Navigator.pop(context, h),
          ),
      ])),
    );
    if (v == null) return;
    try {
      await ref.read(apiClientProvider).setPresence(hideAfterHours: v);
      ref.invalidate(myPresenceProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref, Map<String, dynamic> patch) async {
    try {
      await ref.read(apiClientProvider).updateProfile(patch);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Profile? p) async {
    final bio = TextEditingController(text: p?.bio ?? '');
    final skills = TextEditingController(text: p?.skills.join('، ') ?? '');
    final hobbies = TextEditingController(text: p?.hobbies.join('، ') ?? '');
    final looking = TextEditingController(text: p?.lookingFor.join('، ') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الملف'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: bio, maxLines: 3, decoration: const InputDecoration(labelText: 'نبذة عني')),
            const SizedBox(height: 10),
            TextField(controller: skills, decoration: const InputDecoration(labelText: 'مهاراتي', helperText: 'افصل بينها بفاصلة')),
            const SizedBox(height: 10),
            TextField(controller: hobbies, decoration: const InputDecoration(labelText: 'هواياتي', helperText: 'افصل بينها بفاصلة')),
            const SizedBox(height: 10),
            TextField(controller: looking, decoration: const InputDecoration(labelText: 'أبحث عن', helperText: 'أصدقاء، شريك ركض، عمل…')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    List<String> split(String s) => s.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _save(context, ref, {'bio': bio.text.trim(), 'skills': split(skills.text), 'hobbies': split(hobbies.text), 'lookingFor': split(looking.text)});
    if (context.mounted) toast(context, 'حُفظ ملفك');
  }
}


/// تفعيل/إيقاف الإشعارات الفورية (Web Push) في هذا المتصفح.
class _PushTile extends ConsumerStatefulWidget {
  const _PushTile();
  @override
  ConsumerState<_PushTile> createState() => _PushTileState();
}

class _PushTileState extends ConsumerState<_PushTile> {
  bool _on = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    PushService.isSubscribed().then((v) { if (mounted) setState(() { _on = v; _busy = false; }); });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      if (v) {
        final ok = await PushService.subscribe(api);
        if (!ok && mounted) toast(context, 'لم يُمنح إذن الإشعارات. فعّله من إعدادات المتصفح ثم أعد المحاولة', error: true);
        if (mounted) setState(() => _on = ok);
      } else {
        await PushService.unsubscribe(api);
        if (mounted) setState(() => _on = false);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = PushService.supported;
    final denied = PushService.permission == 'denied';
    return SwitchListTile(
      value: _on,
      onChanged: !supported || denied || _busy ? null : _toggle,
      title: const Text('الإشعارات الفورية'),
      subtitle: Text(!supported
          ? 'غير مدعومة في هذا المتصفح'
          : denied
              ? 'مرفوضة من المتصفح؛ اسمح بها من إعدادات الموقع'
              : _on
                  ? 'تصلك رسائل جديدة حتى والتطبيق مغلق'
                  : 'فعّلها لتصلك الرسائل الجديدة على هذا الجهاز'),
      secondary: Icon(Icons.notifications_active_outlined, color: _on ? Joy.primary : Joy.text),
    );
  }
}
