import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/posts_api.dart';
import '../../api/profile_v2_api.dart';
import '../../api/profile_v2_models.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/nav_provider.dart';
import '../../core/require_account.dart';
import '../../core/share/share_links.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/profile_v2_providers.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../admin/user_admin_sheet.dart';
import '../chat/chat_thread_page.dart';
import '../market/market_page.dart';
import '../posts/overlay_canvas.dart';
import '../posts/post_viewer.dart';
import 'edit_profile_page.dart';
import 'intro_card.dart';
import 'profile_bits.dart';

/// يفتح الملف الشخصي لأي مستخدم (وصاحب الحساب يرى ملفه كما يراه الزوار).
void openProfile(BuildContext context, Person person) {
  if (person.id.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(person: person)));
}

/// بديل للاختبارات: يُستدعى بدل فتح رابط تعريفي خارجياً.
Future<void> Function(Uri)? profileLinkOpenOverride;

final userProfileProvider = FutureProvider.family<Profile, String>((ref, id) => ref.watch(apiClientProvider).profileOf(id));
final userPresenceProvider = FutureProvider.family<bool, String>((ref, id) async {
  try {
    return (await ref.watch(apiClientProvider).presenceOf(id))['online'] == true;
  } catch (_) {
    return false;
  }
});

const _tabs = <(String, String)>[('posts', 'المنشورات'), ('market', 'السوق'), ('services', 'الخدمات'), ('circles', 'الدوائر'), ('reviews', 'التقييمات'), ('about', 'عنه')];

/// ملف المستخدم كما يراه الزائر: غلاف وصورة وأزرار «مراسلة» و«متابعة» والصداقة، الاسم والتوثيق والمسمى، النبذة
/// والروابط وبطاقة «يعرّف بنفسه»، الأرقام وشارات الثقة، ثم ست تبويبات. يعمل بملف النواة وحده إن غاب v2 على الخادم.
class UserProfilePage extends ConsumerStatefulWidget {
  final Person person;
  const UserProfilePage({super.key, required this.person});
  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  String _tab = 'posts';
  // تجاوزات متفائلة للمتابعة حتى يصل ردّ الخادم
  bool? _following;
  int? _followers;
  bool _busyFollow = false;

  Person get person => widget.person;
  String get id => person.id;

  @override
  Widget build(BuildContext context) {
    // الزائر: الملف والحضور وصلاحية الإدارة مسارات نواة ترفض بلا جلسة (401)، فلا نطلبها ونعرض الاسم والصورة فقط
    if (!ref.watch(signedInProvider)) return _guest(context);
    final me = ref.watch(appStateProvider.select((s) => s.user));
    final isMe = me?.id == id;
    final v2 = ref.watch(profileV2Provider(id));
    final core = ref.watch(userProfileProvider(id));
    final p2 = v2.valueOrNull;
    final pc = core.valueOrNull;
    final presence = ref.watch(userPresenceProvider(id)).value ?? false;
    final online = p2?.flags.online ?? presence;
    final contacts = ref.watch(contactsProvider).value ?? const <Person>[];
    final isContact = contacts.any((c) => c.id == id) || p2?.flags.isFriend == true;
    final nickname = p2?.nickname.isNotEmpty == true ? p2!.nickname : (pc?.nickname.isNotEmpty == true ? pc!.nickname : person.nickname);
    final name = p2?.name.isNotEmpty == true ? p2!.name : nickname;
    final avatar = p2?.avatarUrl ?? pc?.avatarUrl ?? person.avatarUrl;
    final blocked = !isMe && isBlockedId(ref.watch(blockedIdsProvider), id);
    final coreErr = core.error;
    final corePrivate = coreErr is ApiException && (coreErr.statusCode == 403 || coreErr.statusCode == 404);
    final private = corePrivate || (p2 != null && p2.flags.isPrivate && !p2.flags.isFriend && !p2.flags.isMe && !isMe);
    final since = p2?.since ?? pc?.createdAt;
    final canMessage = p2?.flags.canMessage ?? true;

    return Scaffold(
      backgroundColor: Joy.bg,
      body: RefreshIndicator(
        onRefresh: () async {
          _following = null;
          _followers = null;
          ref.invalidate(profileV2Provider(id));
          ref.invalidate(userProfileProvider(id));
          ref.invalidate(userPresenceProvider(id));
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Stack(clipBehavior: Clip.none, children: [
              CoverBox(key: const Key('profile-cover'), url: p2?.coverUrl),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (Navigator.of(context).canPop()) CoverButton(icon: Icons.arrow_back_rounded, tooltip: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
                      const Spacer(),
                      CoverButton(key: const Key('share-profile'), icon: Icons.ios_share_rounded, tooltip: 'مشاركة الحساب', onTap: () => _share(context, nickname)),
                      // المدير يدير أي حساب من هنا مباشرة: تعديل، رصيد، إيقاف، حذف نهائي
                      if (!isMe && ref.watch(adminStatusProvider).valueOrNull?.isAdmin == true) ...[
                        const SizedBox(width: 6),
                        CoverButton(key: const Key('admin-user'), icon: Icons.admin_panel_settings_outlined, tooltip: 'إدارة الحساب', color: Joy.sun, onTap: () => showUserAdminSheet(context, ref, id: id, nickname: nickname)),
                      ],
                      if (!isMe) ...[
                        const SizedBox(width: 6),
                        Material(
                          color: Colors.black.withValues(alpha: .28),
                          shape: const CircleBorder(),
                          child: PopupMenuButton<String>(
                            tooltip: 'المزيد',
                            key: const Key('profile-menu'),
                            onSelected: (v) => switch (v) { 'report' => _report(context), 'unblock' => _unblock(context), _ => _block(context) },
                            itemBuilder: (_) => [
                              const PopupMenuItem(key: Key('profile-report'), value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('إبلاغ'))),
                              if (blocked)
                                const PopupMenuItem(key: Key('profile-unblock'), value: 'unblock', child: ListTile(leading: Icon(Icons.lock_open_rounded), title: Text('إلغاء الحظر')))
                              else
                                const PopupMenuItem(key: Key('profile-block'), value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر', style: TextStyle(color: Joy.danger)))),
                            ],
                            child: const SizedBox(width: 40, height: 40, child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22)),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
              PositionedDirectional(bottom: -42, start: 20, child: Avatar(name: name, url: avatar, size: 92, ring: true, online: online)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // الاسم + علامة التوثيق + وسم المسمى للمحترف
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  Text(name, style: Theme.of(context).textTheme.headlineSmall),
                  if (p2?.trust.emailVerified == true) const Icon(Icons.verified_rounded, key: Key('verified-mark'), color: Joy.primary, size: 22),
                  if (p2 != null && p2.isPro && p2.jobTitle.isNotEmpty) ProfileChip(p2.jobTitle, key: const Key('job-tag'), icon: Icons.work_outline_rounded),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    '@$nickname',
                    if (p2 != null && p2.place.isNotEmpty) p2.place,
                    if (online && !isMe) 'متصل الآن' else if (p2 == null && !isMe) 'غير متصل',
                  ].join(' · '),
                  style: TextStyle(color: online && !isMe ? Joy.success : Joy.textMuted, fontSize: 13),
                ),
                // المحظور يبقى ملفه قابلاً للفتح (من رابط أو بحث) فنوضح حالته ونتيح التراجع
                if (blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      key: const Key('blocked-banner'),
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 4, 2),
                      decoration: BoxDecoration(color: Joy.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.block_rounded, size: 16, color: Joy.danger),
                        const SizedBox(width: 6),
                        const Text('محظور', style: TextStyle(color: Joy.danger, fontWeight: FontWeight.w600)),
                        const Text(' · ', style: TextStyle(color: Joy.textMuted)),
                        TextButton(key: const Key('unblock-btn'), onPressed: () => _unblock(context), child: const Text('إلغاء الحظر')),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                if (isMe) ...[
                  Row(children: [
                    Expanded(child: FilledButton.icon(key: const Key('edit-profile-btn'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfilePage())), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('تعديل الملف'))),
                  ]),
                  const SizedBox(height: 6),
                  const Text('هذا ملفك كما يراه الزوار', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                ] else
                  Row(children: [
                    Expanded(
                      child: canMessage
                          ? FilledButton.icon(key: const Key('message-btn'), onPressed: () => _message(context, nickname, avatar), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('مراسلة'))
                          : Container(
                              key: const Key('message-off'),
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)),
                              child: const Text('لا يستقبل رسائل من غير الأصدقاء', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                            ),
                    ),
                    if (p2 != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _followButton(p2)),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: isContact
                          ? OutlinedButton(key: const Key('friend-btn'), onPressed: () => _removeContact(context), child: const Text('صديق'))
                          : OutlinedButton(key: const Key('friend-btn'), onPressed: () => _addContact(context), child: const Text('إضافة صديق')),
                    ),
                  ]),
                const SizedBox(height: 14),
                if ((p2?.bio ?? pc?.bio ?? '').isNotEmpty) ...[
                  Text((p2?.bio.isNotEmpty == true ? p2!.bio : pc!.bio), key: const Key('profile-bio'), style: const TextStyle(height: 1.6)),
                  const SizedBox(height: 10),
                ],
                if (p2 != null && p2.links.isNotEmpty) ...[
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (i, l) in p2.links.indexed) ProfileChip(l.label, key: Key('profile-link-$i'), icon: profileLinkIcon(l.kind), bg: Joy.surface2, fg: Joy.text, onTap: () => _openLink(context, l)),
                  ]),
                  const SizedBox(height: 12),
                ],
                if (p2?.intro != null) ...[ProfileIntroCard(name: name, intro: p2!.intro!), const SizedBox(height: 12)],
                if (p2 != null && !private) ...[
                  JoyCard(
                    key: const Key('stats-row'),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    child: Row(children: [
                      StatCell('${p2.stats.posts}', 'منشور'),
                      StatCell('${_followers ?? p2.stats.followers}', 'متابِع', cellKey: const Key('stat-followers')),
                      StatCell(p2.stats.ratingAvg?.toStringAsFixed(1) ?? '—', p2.stats.ratingCount > 0 ? '${p2.stats.ratingCount} تقييماً' : 'التقييم'),
                      StatCell('${p2.stats.circles}', 'دوائر'),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (p2.trust.emailVerified) const ProfileChip('بريد موثّق', icon: Icons.verified_outlined, bg: Joy.primarySoft, fg: Joy.primary),
                    if (p2.trust.respondsFast == true) const ProfileChip('يرد سريعاً', icon: Icons.bolt_rounded, bg: Joy.sunSoft, fg: Joy.sunText),
                    if (p2.stats.completedOrders > 0) ProfileChip('${p2.stats.completedOrders} طلباً مكتملاً', icon: Icons.check_circle_outline_rounded, bg: Joy.surface2, fg: Joy.text),
                    if (since != null) ProfileChip('عضو منذ ${monthYear(since)}', icon: Icons.schedule_rounded, bg: Joy.surface2, fg: Joy.text),
                  ]),
                  const SizedBox(height: 14),
                ],
                if (private)
                  const EmptyState(key: Key('private-state'), icon: Icons.lock_outline_rounded, title: 'ملف خاص', subtitle: 'تفاصيل هذا المستخدم تظهر لأصدقائه فقط')
                else if (core.isLoading && p2 == null)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (coreErr != null && p2 == null)
                  ErrorState(coreErr, onRetry: () => ref.invalidate(userProfileProvider(id)))
                else ...[
                  _tabBar(),
                  const SizedBox(height: 12),
                  _tabBody(context, p2, pc, isMe: isMe, isFriend: isContact, since: since),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followButton(ProfileV2 p) {
    final following = _following ?? p.flags.isFollowing;
    return following
        ? OutlinedButton.icon(key: const Key('follow-btn'), onPressed: _busyFollow ? null : () => _toggleFollow(p), icon: const Icon(Icons.check_rounded, size: 18, color: Joy.success), label: const Text('تتابعه'))
        : OutlinedButton(key: const Key('follow-btn'), style: OutlinedButton.styleFrom(side: const BorderSide(color: Joy.primary)), onPressed: _busyFollow ? null : () => _toggleFollow(p), child: const Text('متابعة'));
  }

  Widget _tabBar() => SingleChildScrollView(
        key: const Key('profile-tabs'),
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (key, label) in _tabs)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                key: Key('tab-$key'),
                label: Text(label),
                selected: _tab == key,
                showCheckmark: false,
                selectedColor: Joy.primary,
                labelStyle: TextStyle(color: _tab == key ? Joy.primaryOn : Joy.text, fontWeight: FontWeight.w600, fontSize: 13),
                side: BorderSide(color: _tab == key ? Joy.primary : Joy.line),
                onSelected: (_) => setState(() => _tab = key),
              ),
            ),
        ]),
      );

  Widget _tabBody(BuildContext context, ProfileV2? p2, Profile? pc, {required bool isMe, required bool isFriend, DateTime? since}) => switch (_tab) {
        'posts' => _PostsTab(id: id, count: p2?.stats.posts ?? 0),
        'market' => _MarketTab(id: id),
        'services' => _services(pc),
        'circles' => JoyCard(
            key: const Key('circles-tab'),
            child: Row(children: [
              const Icon(Icons.groups_2_outlined, color: Joy.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(p2 == null || p2.stats.circles == 0 ? 'ليس عضواً في دوائر عامة بعد' : 'عضو في ${p2.stats.circles} دوائر', style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        'reviews' => _reviews(p2),
        _ => _about(p2, pc, isMe: isMe, isFriend: isFriend, since: since),
      };

  Widget _services(Profile? pc) {
    final offers = pc?.offerings ?? const [];
    if (offers.isEmpty) return const EmptyState(icon: Icons.handshake_outlined, title: 'لا خدمات بعد');
    return Column(key: const Key('services-tab'), children: [
      for (final o in offers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: JoyCard(child: Row(children: [
            if (o.imageUrl != null && o.imageUrl!.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(o.imageUrl!), width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52))) else const Icon(Icons.local_offer_outlined, color: Joy.primary),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(o.name, style: const TextStyle(fontWeight: FontWeight.w600)), if (o.description.isNotEmpty) Text(o.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)])),
          ])),
        ),
    ]);
  }

  Widget _reviews(ProfileV2? p2) {
    final s = p2?.stats;
    if (s == null || s.ratingCount == 0) return const EmptyState(icon: Icons.star_outline_rounded, title: 'لا تقييمات بعد', subtitle: 'تظهر هنا تقييمات المشترين بعد اكتمال الطلبات');
    final avg = s.ratingAvg ?? 0;
    return JoyCard(
      key: const Key('reviews-tab'),
      child: Row(children: [
        Text(avg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 34)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [for (var i = 1; i <= 5; i++) Icon(i <= avg.round() ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: Joy.sunText)]),
          Text('${s.ratingCount} تقييماً', style: const TextStyle(color: Joy.textMuted)),
          if (s.completedOrders > 0) Text('${s.completedOrders} طلباً مكتملاً', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        ]),
      ]),
    );
  }

  Widget _about(ProfileV2? p2, Profile? pc, {required bool isMe, required bool isFriend, DateTime? since}) {
    Widget row(String k, String v, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(key: key, children: [Text(k, style: const TextStyle(color: Joy.textMuted, fontSize: 13)), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))]),
        );
    final accountType = p2?.accountType ?? pc?.accountType ?? 'personal';
    return Column(key: const Key('about-tab'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (pc != null && (pc.skills.isNotEmpty || pc.hobbies.isNotEmpty || pc.lookingFor.isNotEmpty)) ...[
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pc.skills.isNotEmpty) ChipGroup('مهاراته', pc.skills),
          if (pc.hobbies.isNotEmpty) ChipGroup('هواياته', pc.hobbies, bg: Joy.sunSoft, fg: Joy.sunText),
          if (pc.lookingFor.isNotEmpty) ChipGroup('يبحث عن', pc.lookingFor, bg: Joy.accentSoft, fg: Joy.accent),
        ])),
        const SizedBox(height: 10),
      ],
      JoyCard(child: Column(children: [
        row('نوع الحساب', accountType == 'pro' ? 'مهني${p2 != null && p2.jobTitle.isNotEmpty ? ' · ${p2.jobTitle}' : ''}' : 'شخصي'),
        if (p2 != null && p2.place.isNotEmpty) row('المدينة', p2.place),
        if (since != null) row('عضو منذ', monthYear(since)),
        // الرقم SA للأصدقاء فقط دائماً (ويُنسخ من بطاقة الدردشة)
        row('الرقم SA', isMe || isFriend ? id : 'يظهر للأصدقاء فقط', key: const Key('sa-row')),
      ])),
      if (pc == null && p2 == null) const EmptyState(icon: Icons.person_outline_rounded, title: 'لم يضف تفاصيل بعد'),
    ]);
  }

  /// ملف الزائر: الصورة والاسم من [person] وبطاقة تدعو للدخول، بلا إبلاغ ولا مراسلة (كلاهما يحتاج حساباً).
  Widget _guest(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(
          title: Text(person.nickname),
          actions: [
            IconButton(key: const Key('share-profile'), tooltip: 'مشاركة الحساب', icon: const Icon(Icons.ios_share_rounded), onPressed: () => shareLink(context, title: person.nickname, url: profileLink(person.nickname), subtitle: 'حساب على ناس لايف', code: userCode(person.nickname))),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(child: Avatar(name: person.nickname, url: person.avatarUrl, size: 104, ring: true)),
            const SizedBox(height: 12),
            Center(child: Text(person.nickname, style: Theme.of(context).textTheme.headlineSmall)),
            const SizedBox(height: 20),
            JoyCard(
              key: const Key('guest-profile-card'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.lock_outline_rounded, size: 36, color: Joy.primary),
                const SizedBox(height: 8),
                const Text('سجّل الدخول لرؤية الملف', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                const Text('النبذة والعروض والمراسلة متاحة للأعضاء.', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, height: 1.5)),
                const SizedBox(height: 12),
                FilledButton(key: const Key('guest-profile-login'), onPressed: () => requireAccount(context), child: const Text('سجّل الدخول')),
              ]),
            ),
          ],
        ),
      );

  void _share(BuildContext context, String nickname) {
    ref.read(apiClientProvider).profileEvent(id, 'share');
    shareLink(context, title: nickname, url: profileLink(nickname), subtitle: 'حساب على ناس لايف', code: userCode(nickname));
  }

  void _message(BuildContext context, String nickname, String? avatar) {
    if (!requireAccount(context)) return;
    ref.read(apiClientProvider).profileEvent(id, 'message');
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: Person(id: id, nickname: nickname, avatarUrl: avatar))));
  }

  Future<void> _openLink(BuildContext context, ProfileLink l) async {
    ref.read(apiClientProvider).profileEvent(id, 'link');
    final u = Uri.tryParse(l.href);
    if (u == null) return;
    try {
      final o = profileLinkOpenOverride;
      if (o != null) {
        await o(u);
      } else {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) toast(context, 'تعذر فتح الرابط', error: true);
    }
  }

  Future<void> _toggleFollow(ProfileV2 p) async {
    final was = _following ?? p.flags.isFollowing;
    final count = _followers ?? p.stats.followers;
    setState(() {
      _following = !was;
      _followers = was ? (count - 1).clamp(0, 1 << 30) : count + 1;
      _busyFollow = true;
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = was ? await api.unfollow(id) : await api.follow(id);
      if (mounted) setState(() { _following = r.following; _followers = r.followers; });
    } catch (e) {
      if (mounted) {
        setState(() { _following = was; _followers = count; });
        toast(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  Future<void> _addContact(BuildContext context) async {
    try {
      await ref.read(apiClientProvider).addContact(id);
      ref.invalidate(contactsProvider);
      ref.invalidate(requestsProvider);
      if (context.mounted) toast(context, 'أُرسل طلب الصداقة إلى ${person.nickname}');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _removeContact(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إزالة ${person.nickname} من أصدقائك؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إزالة'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).removeContact(id);
      ref.invalidate(contactsProvider);
      ref.invalidate(profileV2Provider(id));
      if (context.mounted) toast(context, 'أُزيل من أصدقائك');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _report(BuildContext context) async {
    final r = await showReportSheet(context, ref, type: kReportUser, id: id, author: person, title: 'إبلاغ عن ${person.nickname}');
    if (r != null && r.blocked) {
      ref.invalidate(contactsProvider);
      ref.invalidate(chatsProvider);
    }
  }

  Future<void> _unblock(BuildContext context) async {
    try {
      await ref.read(apiClientProvider).unblockUser(id);
      ref.invalidate(blockedUsersProvider);
      ref.invalidate(chatsProvider);
      if (context.mounted) toast(context, 'أُلغي حظر ${person.nickname}');
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _block(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حظر ${person.nickname}؟'),
        content: const Text('لن يستطيع مراسلتك أو رؤية لحظاتك.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حظر'))],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).blockUser(id);
      ref.invalidate(blockedUsersProvider);
      ref.invalidate(contactsProvider);
      ref.invalidate(chatsProvider);
      if (context.mounted) { toast(context, 'تم حظر ${person.nickname}'); Navigator.of(context).pop(); }
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }
}

/// تبويب المنشورات: شبكة مصغّرات لمنشورات المستخدم النشطة على الخريطة، والنقر يفتح العارض. وإن تعذّر الجلب
/// يُعرض العدد وزر «عرض على الخريطة».
class _PostsTab extends ConsumerWidget {
  final String id;
  final int count;
  const _PostsTab({required this.id, required this.count});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(userPostsProvider(id));
    return posts.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (_, __) => _fallback(context, ref),
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.auto_awesome_motion_outlined, title: 'لا منشورات نشطة الآن', subtitle: 'المنشورات تبقى على الخريطة حتى 7 أيام')
          : GridView.builder(
              key: const Key('posts-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 3 / 4),
              itemCount: list.length,
              itemBuilder: (_, i) => _PostThumb(list[i], onTap: () => PostViewerPage.open(context, list, index: i)),
            ),
    );
  }

  Widget _fallback(BuildContext context, WidgetRef ref) => JoyCard(
        key: const Key('posts-fallback'),
        child: Row(children: [
          Expanded(child: Text(count == 0 ? 'لا منشورات نشطة الآن' : 'على الخريطة الآن: $count منشوراً نشطاً', style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              ref.read(navIndexProvider.notifier).state = 0;
            },
            child: const Text('عرض على الخريطة'),
          ),
        ]),
      );
}

class _PostThumb extends StatelessWidget {
  final MapPost p;
  final VoidCallback onTap;
  const _PostThumb(this.p, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final icon = switch (p.kind) { 'video' => Icons.play_circle_outline_rounded, 'audio' => Icons.mic_rounded, _ => null };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: p.kind == 'text' ? colorFromHex(p.bg, Joy.primarySoft) : const Color(0xFF14181C), borderRadius: BorderRadius.circular(12)),
        child: Stack(fit: StackFit.expand, children: [
          if ((p.kind == 'image' || p.kind == 'video') && p.mediaUrl != null) Image.network(thumbUrl(p.mediaUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          if (p.kind == 'text') Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(p.summary, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Joy.text)))),
          if (icon != null) Center(child: Icon(icon, color: Colors.white, size: 30)),
          Positioned(bottom: 4, left: 6, child: Row(children: [const Icon(Icons.visibility_outlined, size: 12, color: Colors.white), const SizedBox(width: 2), Text('${p.views}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700))])),
        ]),
      ),
    );
  }
}

/// تبويب السوق: عروض البائع النشطة في شبكة، والنقر يفتح صفحة العرض.
class _MarketTab extends ConsumerWidget {
  final String id;
  const _MarketTab({required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(sellerListingsProvider(id));
    return items.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => JoyCard(child: Text('تعذر جلب عروض السوق', style: const TextStyle(color: Joy.textMuted))),
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.storefront_outlined, title: 'لا عروض في السوق')
          : GridView.builder(
              key: const Key('market-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .72),
              itemCount: list.length,
              itemBuilder: (_, i) => ListingCard(list[i]),
            ),
    );
  }
}
