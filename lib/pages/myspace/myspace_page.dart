import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/chat_tools_api.dart';
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


/// بريد الدخول البديل: يُستخدم في شاشة الدخول بدل النك نيم بكلمة السر نفسها (server/auth_alias.js).
class _LoginEmailTile extends ConsumerStatefulWidget {
  const _LoginEmailTile();
  @override
  ConsumerState<_LoginEmailTile> createState() => _LoginEmailTileState();
}

class _LoginEmailTileState extends ConsumerState<_LoginEmailTile> {
  String? _email;
  var _loaded = false, _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await ref.read(apiClientProvider).loginEmail();
      if (mounted) setState(() { _email = e; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() { _unavailable = true; _loaded = true; });
    }
  }

  Future<void> _edit() async {
    final c = TextEditingController(text: _email ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('بريد الدخول'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ستدخل بهذا البريد بدل النك نيم، وبالرقم السري نفسه.', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(key: const Key('login-email-field'), controller: c, autofocus: true, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(hintText: 'name@example.com')),
        ]),
        actions: [
          if (_email != null) TextButton(key: const Key('login-email-clear'), onPressed: () => Navigator.pop(d, false), child: const Text('إزالة البريد', style: TextStyle(color: Joy.danger))),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(key: const Key('login-email-save'), onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == null) return;
    try {
      if (ok) {
        final e = await ref.read(apiClientProvider).setLoginEmail(c.text);
        setState(() => _email = e);
        if (mounted) toast(context, 'صار بإمكانك الدخول بـ $e');
      } else {
        await ref.read(apiClientProvider).clearLoginEmail();
        setState(() => _email = null);
        if (mounted) toast(context, 'أُزيل بريد الدخول');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('email-taken') ? 'هذا البريد مستخدم لحساب آخر' : e.toString().contains('bad-email') ? 'صيغة البريد غير صحيحة' : e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('login-email'),
        leading: const Icon(Icons.alternate_email_rounded, color: Joy.primary),
        title: const Text('بريد الدخول'),
        subtitle: Text(!_loaded ? '…' : _unavailable ? 'غير متاح على هذا الخادم' : (_email ?? 'أضف بريداً لتدخل به بدل النك نيم'), textDirection: _email != null ? TextDirection.ltr : null, textAlign: _email != null ? TextAlign.right : null),
        trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
        onTap: _unavailable ? null : _edit,
      );
}
