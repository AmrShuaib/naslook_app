import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/notify_api.dart';
import '../../api/session.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/notify/message_sound.dart';
import '../../core/share/share_links.dart';
import '../../core/media/pick_image.dart';
import '../../core/push/push_service.dart';
import '../../state/admin_providers.dart';
import '../../state/notify_providers.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../business/my_bookings_page.dart';
import '../admin/admin_shell.dart';
import '../business/owner/my_businesses_page.dart';
import '../events/events_page.dart';
import '../market/market_page.dart';
import '../posts/my_posts_page.dart';
import 'safety_page.dart';
import 'saved_searches_page.dart';
import 'wishlist_page.dart';
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
            ListTile(leading: const Icon(Icons.storefront_rounded, color: Joy.primary), title: const Text('نشاطي التجاري'), subtitle: const Text('لوحة تحكم دائرتك: الكتالوج والطلبات والإحصاءات'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBusinessesPage()))),
            if (ref.watch(adminStatusProvider).valueOrNull?.isAdmin == true) ...[
              const Divider(indent: 16, endIndent: 16),
              ListTile(leading: const Icon(Icons.admin_panel_settings_outlined, color: Joy.accent), title: const Text('لوحة الإدارة'), subtitle: const Text('المستخدمون والبلاغات والمالية والإعدادات'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminShell(standalone: false)))),
            ],
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.auto_awesome_motion_outlined, color: Joy.accent), title: const Text('منشوراتي على الخريطة'), subtitle: const Text('صور وفيديو وصوت ونص · تعديل وإخفاء وحذف'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyPostsPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(key: const Key('share-me'), leading: const Icon(Icons.ios_share_rounded, color: Joy.primary), title: const Text('مشاركة حسابي'), subtitle: Text(me == null ? '' : profileLink(me.nickname).replaceFirst(RegExp(r'^https?://'), ''), textDirection: TextDirection.ltr, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: me == null ? null : () => shareLink(context, title: me.nickname, url: profileLink(me.nickname), subtitle: (p?.isPublic ?? true) ? 'حسابك العام على ناس لايف' : 'حسابك خاص: الرابط يعرض اسمك فقط', code: userCode(me.nickname))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.shield_outlined, color: Joy.primary), title: const Text('الخصوصية والأمان'), subtitle: const Text('المحظورون والمحادثات المكتومة'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafetyPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.saved_search_rounded, color: Joy.primary), title: const Text('بحوثي المحفوظة'), subtitle: const Text('تنبيه عند ظهور جديد يطابق ما تبحث عنه'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedSearchesPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.bookmark_added_outlined, color: Joy.accent), title: const Text('قائمة أمنياتي'), subtitle: const Text('منتجات وخدمات وفعاليات ومنشورات أتمناها'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WishlistPage()))),
            const Divider(indent: 16, endIndent: 16, height: 1),
            ListTile(key: const Key('blog-link'), leading: const Icon(Icons.newspaper_outlined, color: Joy.primary), title: const Text('التحديثات والأخبار'), subtitle: const Text('مدونة ناس لايف: كل جديد في التطبيق'), trailing: const Icon(Icons.open_in_new_rounded, color: Joy.textMuted, size: 18), onTap: () => launchUrl(Uri.parse('${publicOrigin()}/blog'), mode: LaunchMode.externalApplication)),
            const Divider(indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.storefront_outlined, color: Joy.sunText), title: const Text('عروضي وطلباتي في السوق'), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersPage(initialTab: 0)))),
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
          const JoyCard(padding: EdgeInsets.zero, child: Column(children: [_PushTile(), Divider(indent: 16, endIndent: 16, height: 1), _SoundTile()])),
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
              const _LoginEmailTile(),
              const Divider(indent: 16, endIndent: 16),
              const _PasswordTile(),
              const Divider(indent: 16, endIndent: 16),
              const _RecoveryTile(),
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

  /// يرفع صورة من الجهاز ويثبّتها صورةً للحساب، ويحدّث الجلسة والملف. يعيد الرابط أو null عند الإلغاء/الفشل.
  Future<String?> _changeAvatar(BuildContext context, WidgetRef ref) async {
    try {
      final img = await pickImage();
      if (img == null) return null;
      final api = ref.read(apiClientProvider);
      final up = await api.uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      final url = await api.setAvatar(up.url);
      await _applyAvatar(ref, url);
      if (context.mounted) toast(context, 'حُدّثت صورتك');
      return url;
    } catch (e) {
      if (context.mounted) toast(context, e.toString().contains('unsupported') ? 'الخادم لا يدعم صور الحساب بعد' : e.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), ''), error: true);
      return null;
    }
  }

  Future<bool> _removeAvatar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiClientProvider).clearAvatar();
      await _applyAvatar(ref, null);
      if (context.mounted) toast(context, 'أُزيلت صورتك');
      return true;
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
      return false;
    }
  }

  Future<void> _applyAvatar(WidgetRef ref, String? url) async {
    final u = ref.read(appStateProvider).user;
    if (u != null) await ref.read(appStateProvider.notifier).updateUser(SessionUser(id: u.id, nickname: u.nickname, displayName: u.displayName, avatarUrl: url));
    ref.invalidate(profileProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Profile? p) async {
    final bio = TextEditingController(text: p?.bio ?? '');
    final skills = TextEditingController(text: p?.skills.join('، ') ?? '');
    final hobbies = TextEditingController(text: p?.hobbies.join('، ') ?? '');
    final looking = TextEditingController(text: p?.lookingFor.join('، ') ?? '');
    final me = ref.read(appStateProvider).user;
    String? avatar = p?.avatarUrl ?? me?.avatarUrl;
    var busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('تعديل الملف'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // صورة الحساب: تُرفع وتُثبَّت فوراً، بمعزل عن زر الحفظ
              Row(children: [
                Avatar(name: me?.nickname ?? '', url: avatar, size: 64, ring: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              setS(() => busy = true);
                              final url = await _changeAvatar(ctx, ref);
                              if (url != null) avatar = url;
                              if (ctx.mounted) setS(() => busy = false);
                            },
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(busy ? 'جارٍ الرفع…' : (avatar == null || avatar!.isEmpty ? 'إضافة صورة' : 'تغيير الصورة')),
                    ),
                    if (avatar != null && avatar!.isNotEmpty)
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                setS(() => busy = true);
                                if (await _removeAvatar(ctx, ref)) avatar = null;
                                if (ctx.mounted) setS(() => busy = false);
                              },
                        style: TextButton.styleFrom(foregroundColor: Joy.danger),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('إزالة الصورة'),
                      ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
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
      ),
    );
    if (ok != true || !context.mounted) return;
    List<String> split(String s) => s.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _save(context, ref, {'bio': bio.text.trim(), 'skills': split(skills.text), 'hobbies': split(hobbies.text), 'lookingFor': split(looking.text)});
    if (context.mounted) toast(context, 'حُفظ ملفك');
  }
}


/// جرس الرسائل الجديدة على الويب: مفتاح تشغيل وزر تجربة.
class _SoundTile extends ConsumerWidget {
  const _SoundTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(messageSoundProvider);
    final supported = MessageSound.supported;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(
        key: const Key('sound-toggle'),
        value: on && supported,
        onChanged: supported ? (v) => ref.read(messageSoundProvider.notifier).set(v) : null,
        title: const Text('صوت الجرس للرسائل الجديدة'),
        subtitle: Text(!supported ? 'متاح في نسخة الويب' : on ? 'يُقرع عند وصول رسالة والتطبيق مفتوح في المتصفح' : 'بلا صوت عند وصول الرسائل'),
        secondary: Icon(Icons.notifications_none_rounded, color: on && supported ? Joy.primary : Joy.text),
      ),
      if (supported)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
            child: TextButton.icon(key: const Key('sound-test'), onPressed: on ? () { MessageSound.play(); toast(context, 'هذا صوت الجرس'); } : null, icon: const Icon(Icons.volume_up_outlined, size: 18), label: const Text('تجربة الصوت')),
          ),
        ),
    ]);
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

  /// يرسل إشعاراً تجريبياً لهذا الحساب: داخل التطبيق دائماً، وللمتصفح إن كان الدفع مهيأً على الخادم.
  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiClientProvider).notifyTest();
      ref.invalidate(notifyUnreadProvider);
      if (!mounted) return;
      if (r.pushed > 0) {
        toast(context, 'أُرسل إشعار تجريبي إلى هذا المتصفح');
      } else if (!r.pushReady) {
        toast(context, 'أُضيف الإشعار داخل التطبيق، لكن الدفع للمتصفح غير مهيأ على الخادم (${r.reason})', error: true);
      } else {
        toast(context, 'أُضيف الإشعار داخل التطبيق ولم يُعثر على اشتراك دفع لهذا الحساب', error: true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = PushService.supported;
    final denied = PushService.permission == 'denied';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(
        value: _on,
        onChanged: !supported || denied || _busy ? null : _toggle,
        title: const Text('الإشعارات الفورية'),
        subtitle: Text(!supported
            ? 'غير مدعومة في هذا المتصفح'
            : denied
                ? 'مرفوضة من المتصفح؛ اسمح بها من إعدادات الموقع'
                : _on
                    ? 'تصلك الرسائل والطلبات والحجوزات حتى والتطبيق مغلق'
                    : 'فعّلها لتصلك الرسائل والطلبات على هذا الجهاز'),
        secondary: Icon(Icons.notifications_active_outlined, color: _on ? Joy.primary : Joy.text),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
          child: TextButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.send_outlined, size: 18), label: const Text('إرسال إشعار تجريبي')),
        ),
      ),
    ]);
  }
}


/// بريد الدخول البديل: يُستخدم في شاشة الدخول بدل النك نيم بكلمة السر نفسها (server/auth_alias.js)،
/// ويُؤكَّد برمز يصل بالبريد عندما تكون خدمة البريد مفعّلة على الخادم.
class _LoginEmailTile extends ConsumerStatefulWidget {
  const _LoginEmailTile();
  @override
  ConsumerState<_LoginEmailTile> createState() => _LoginEmailTileState();
}

class _LoginEmailTileState extends ConsumerState<_LoginEmailTile> {
  LoginEmailInfo _info = const LoginEmailInfo();
  var _loaded = false, _unavailable = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await ref.read(apiClientProvider).loginEmail();
      if (mounted) setState(() { _info = i; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() { _unavailable = true; _loaded = true; });
    }
  }

  String _err(Object e) {
    final body = e is ApiException ? (e.body ?? const {}) : const <String, dynamic>{};
    final s = '${e.toString()} ${body['error'] ?? ''}';
    if (s.contains('email-taken')) return 'هذا البريد مستخدم لحساب آخر';
    if (s.contains('bad-email')) return 'صيغة البريد غير صحيحة';
    if (s.contains('too-many-attempts')) return 'استُنفدت المحاولات؛ اطلب رمزاً جديداً';
    if (s.contains('code-expired')) return 'انتهت صلاحية الرمز؛ اطلب رمزاً جديداً';
    if (s.contains('bad-code')) return 'الرمز غير صحيح${body['attemptsLeft'] is num ? ' (بقي ${body['attemptsLeft']} محاولات)' : ''}';
    if (s.contains('no-code')) return 'اطلب رمزاً أولاً';
    if (s.contains('too-soon')) return 'انتظر دقيقة قبل إعادة الإرسال';
    if (s.contains('mail-not-configured')) return 'خدمة البريد غير مفعّلة على الخادم بعد';
    if (s.contains('send-failed')) return 'تعذّر إرسال الرسالة الآن؛ حاول لاحقاً';
    if (s.contains('already-verified')) return 'البريد مؤكَّد مسبقاً';
    return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
  }

  Future<void> _edit() async {
    final c = TextEditingController(text: _info.email ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('بريد الدخول'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_info.mailConfigured ? 'تدخل بهذا البريد بدل اسم المستخدم وبكلمة السر نفسها، وتصلك عليه رموز التأكيد واستعادة كلمة السر.' : 'تدخل بهذا البريد بدل اسم المستخدم وبكلمة السر نفسها.', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(key: const Key('login-email-field'), controller: c, autofocus: true, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(hintText: 'name@example.com')),
        ]),
        actions: [
          if (_info.email != null) TextButton(key: const Key('login-email-clear'), onPressed: () => Navigator.pop(d, false), child: const Text('إزالة البريد', style: TextStyle(color: Joy.danger))),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(key: const Key('login-email-save'), onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == null) return;
    try {
      if (ok) {
        final i = await ref.read(apiClientProvider).setLoginEmail(c.text);
        setState(() => _info = i);
        if (!mounted) return;
        if (i.codeSent) {
          toast(context, 'أرسلنا رمز التأكيد إلى ${i.email}');
          await _verifyDialog();
        } else if (i.sendError != null) {
          toast(context, 'حُفظ البريد لكن تعذّر إرسال رمز التأكيد الآن', error: true);
        } else {
          toast(context, 'صار بإمكانك الدخول بـ ${i.email}');
        }
      } else {
        await ref.read(apiClientProvider).clearLoginEmail();
        setState(() => _info = LoginEmailInfo(mailConfigured: _info.mailConfigured));
        if (mounted) toast(context, 'أُزيل بريد الدخول');
      }
    } catch (e) {
      if (mounted) toast(context, _err(e), error: true);
    }
  }

  /// يطلب رمزاً (إن لم يكن هناك رمز صالح) ثم يفتح مربع إدخاله.
  Future<void> _startVerify() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_info.codePending) {
        await ref.read(apiClientProvider).sendLoginEmailCode();
        if (mounted) toast(context, 'أرسلنا رمز التأكيد إلى ${_info.email}');
      }
      if (mounted) await _verifyDialog();
    } catch (e) {
      if (mounted && !e.toString().contains('too-soon')) toast(context, _err(e), error: true);
      if (mounted && e.toString().contains('too-soon')) await _verifyDialog();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyDialog() async {
    final c = TextEditingController();
    String? error;
    var sending = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
        title: const Text('تأكيد البريد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('أدخل الرمز المكوّن من 6 أرقام الذي وصل إلى ${_info.email}. الرمز صالح 15 دقيقة.', style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('login-email-code'), controller: c, autofocus: true, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, textAlign: TextAlign.center, maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: InputDecoration(hintText: '000000', counterText: '', errorText: error),
            onSubmitted: (_) => Navigator.pop(d, true),
          ),
        ]),
        actions: [
          TextButton(
            key: const Key('login-email-code-resend'),
            onPressed: sending ? null : () async {
              setD(() => sending = true);
              try { await ref.read(apiClientProvider).sendLoginEmailCode(); setD(() { error = null; sending = false; }); if (d.mounted) toast(d, 'أُعيد إرسال الرمز'); }
              catch (e) { setD(() { error = _err(e); sending = false; }); }
            },
            child: const Text('إعادة الإرسال'),
          ),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('لاحقاً')),
          FilledButton(key: const Key('login-email-code-ok'), onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد')),
        ],
      )),
    );
    if (ok != true) return;
    try {
      final i = await ref.read(apiClientProvider).verifyLoginEmail(c.text);
      setState(() => _info = i);
      if (mounted) toast(context, i.verified ? 'تم تأكيد بريدك' : 'لم يُؤكَّد البريد');
    } catch (e) {
      if (!mounted) return;
      toast(context, _err(e), error: true);
      if (e is ApiException && e.body?['error'] == 'bad-code') await _verifyDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _info.email;
    final showVerify = email != null && !_info.verified && _info.mailConfigured;
    return ListTile(
      key: const Key('login-email'),
      leading: const Icon(Icons.alternate_email_rounded, color: Joy.primary),
      title: const Text('بريد الدخول'),
      subtitle: !_loaded
          ? const Text('…')
          : _unavailable
              ? const Text('غير متاح على هذا الخادم')
              : email == null
                  ? const Text('أضف بريداً لتدخل به بدل النك نيم')
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(email, textDirection: TextDirection.ltr, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
                        if (_info.verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, key: Key('login-email-verified'), size: 16, color: Joy.success)],
                      ]),
                      if (!_info.verified && _info.mailConfigured)
                        const Text('غير مؤكَّد · اضغط «تأكيد» لإدخال الرمز الذي وصلك', key: Key('login-email-unverified'), style: TextStyle(color: Joy.warning, fontSize: 12)),
                    ]),
      trailing: showVerify
          ? TextButton(key: const Key('login-email-verify'), onPressed: _busy ? null : _startVerify, child: Text(_busy ? '…' : 'تأكيد'))
          : const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
      onTap: _unavailable ? null : _edit,
    );
  }
}

/// تغيير كلمة السر بكلمة السر الحالية (server/auth_alias.js يعيد التعيين عبر عبارة الاسترداد المحفوظة ويصدر جلسة جديدة).
class _PasswordTile extends ConsumerWidget {
  const _PasswordTile();

  static String errText(Object e) {
    final s = '${e.toString()} ${e is ApiException ? (e.body?['error'] ?? '') : ''}';
    if (s.contains('bad-password')) return 'كلمة السر الحالية غير صحيحة';
    if (s.contains('no-recovery')) return 'فعّل «الاستعادة بالبريد» أولاً بإدخال عبارة الاسترداد';
    if (s.contains('weak-password')) return 'كلمة السر الجديدة يجب أن تكون 8 خانات على الأقل';
    return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
  }

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final cur = TextEditingController(), next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تغيير كلمة السر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('cp-current'), controller: cur, obscureText: true, autofocus: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة السر الحالية')),
          const SizedBox(height: 10),
          TextField(key: const Key('cp-new'), controller: next, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة', helperText: '8 خانات على الأقل')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(key: const Key('cp-save'), onPressed: () => Navigator.pop(d, true), child: const Text('تغيير')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (next.text.length < 8) { toast(context, 'كلمة السر الجديدة يجب أن تكون 8 خانات على الأقل', error: true); return; }
    try {
      final token = await ref.read(apiClientProvider).changePassword(current: cur.text, next: next.text);
      await ref.read(appStateProvider.notifier).adoptToken(token);
      if (context.mounted) toast(context, 'تم تغيير كلمة السر');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        key: const Key('change-password'),
        leading: const Icon(Icons.password_rounded, color: Joy.primary),
        title: const Text('تغيير كلمة السر'),
        subtitle: const Text('بكلمة السر الحالية'),
        trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        onTap: () => _change(context, ref),
      );
}

/// الاستعادة بالبريد: الحسابات الجديدة مفعّلة تلقائياً، والقديمة تُفعَّل مرة واحدة بإدخال عبارة الاسترداد وكلمة السر.
class _RecoveryTile extends ConsumerStatefulWidget {
  const _RecoveryTile();
  @override
  ConsumerState<_RecoveryTile> createState() => _RecoveryTileState();
}

class _RecoveryTileState extends ConsumerState<_RecoveryTile> {
  RecoveryInfo? _info;
  var _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await ref.read(apiClientProvider).recoveryStatus();
      if (mounted) setState(() => _info = i);
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  Future<void> _enable() async {
    final phrase = TextEditingController(), pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تفعيل الاستعادة بالبريد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل عبارة الاسترداد التي حصلت عليها عند التسجيل وكلمة سرك الحالية. سنحفظ عبارة جديدة مشفّرة على الخادم لتتمكن من إعادة تعيين كلمة السر برمز يصل إلى بريدك.', style: TextStyle(color: Joy.textMuted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 10),
          TextField(key: const Key('recovery-phrase'), controller: phrase, autofocus: true, maxLines: 2, decoration: const InputDecoration(labelText: 'عبارة الاسترداد', hintText: 'ست كلمات مفصولة بمسافات')),
          const SizedBox(height: 10),
          TextField(key: const Key('recovery-password'), controller: pw, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة السر الحالية')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(key: const Key('recovery-save'), onPressed: () => Navigator.pop(d, true), child: const Text('تفعيل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final token = await ref.read(apiClientProvider).enableRecovery(phrase: phrase.text, password: pw.text);
      await ref.read(appStateProvider.notifier).adoptToken(token);
      if (!mounted) return;
      setState(() => _info = RecoveryInfo(enabled: true, email: _info?.email, verified: _info?.verified ?? false, mailConfigured: _info?.mailConfigured ?? false));
      toast(context, 'فُعّلت الاستعادة بالبريد');
    } catch (e) {
      if (!mounted) return;
      final s = '${e.toString()} ${e is ApiException ? (e.body?['error'] ?? '') : ''}';
      toast(context, s.contains('bad-phrase') ? 'عبارة الاسترداد غير صحيحة' : s.contains('bad-password') ? 'كلمة السر غير صحيحة' : s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final subtitle = _unavailable
        ? 'غير متاحة على هذا الخادم'
        : i == null
            ? '…'
            : !i.enabled
                ? 'غير مفعّلة: أدخل عبارة الاسترداد مرة واحدة'
                : i.email == null
                    ? 'مفعّلة، لكن أضف بريد الدخول لتصلك رموز الاستعادة'
                    : 'مفعّلة: يصلك رمز على ${i.email} عند نسيان كلمة السر';
    return ListTile(
      key: const Key('recovery'),
      leading: Icon(i?.enabled == true ? Icons.verified_user_rounded : Icons.shield_outlined, color: i?.enabled == true ? Joy.success : Joy.primary),
      title: const Text('الاستعادة بالبريد'),
      subtitle: Text(subtitle),
      trailing: i != null && !i.enabled ? TextButton(key: const Key('recovery-enable'), onPressed: _enable, child: const Text('تفعيل')) : null,
      onTap: i != null && !i.enabled ? _enable : null,
    );
  }
}
