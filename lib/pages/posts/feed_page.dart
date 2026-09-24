import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/commerce_models.dart';
import '../../api/naslife_api.dart';
import '../../api/posts_api.dart';
import '../../api/safety_api.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../../ui/wish_button.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import 'overlay_canvas.dart';
import 'my_posts_page.dart';
import 'post_media.dart';
import 'post_stats.dart';
import 'post_viewer.dart';

/// البث العمودي «الآن حولك»: لحظات المدينة بالتمرير الرأسي، الأقرب والأحدث أولاً (server/map_posts.js: /mapposts/feed)،
/// مع تصفية اختيارية بمكان واحد (من الأماكن الرائجة). يعمل الفيديو للصفحة الظاهرة فقط، ونقرتان تعجبان.
class FeedPage extends ConsumerStatefulWidget {
  final String? placeKey, placeName;
  const FeedPage({super.key, this.placeKey, this.placeName});

  static Future<void> open(BuildContext context, {String? placeKey, String? placeName}) =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => FeedPage(placeKey: placeKey, placeName: placeName)));

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _ctl = PageController();
  List<MapPost> items = [];
  int? next;
  int index = 0;
  bool loading = true, more = false, located = false;
  Object? error;
  LatLng? origin;
  final _viewed = <String>{};
  // المرشّحات السريعة: نوع اللحظة ('' = الكل)، نصف القطر بالكيلومتر، أصدقائي فقط (تُحفظ محلياً)
  String tag = '';
  double radius = 30;
  bool friends = false;
  List<String>? _friendIds;

  static const tagChips = [('', 'الكل'), ('moment', 'لحظات'), ('offer', 'عروض'), ('event', 'فعاليات'), ('job', 'وظائف'), ('ad', 'إعلانات'), ('invest', 'استثمار')];
  static const radiusChips = [(2.0, 'قريب جداً'), (30.0, 'حولي'), (150.0, 'المدينة كلها')];

  @override
  void initState() {
    super.initState();
    _restore().then((_) => _load());
  }

  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      radius = sp.getDouble('feed_radius') ?? 30;
      friends = sp.getBool('feed_friends') ?? false;
      if (!radiusChips.any((c) => c.$1 == radius)) radius = 30;
    } catch (_) { /* لا تخزين محلي */ }
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('feed_radius', radius);
      await sp.setBool('feed_friends', friends);
    } catch (_) { /* تجاهل */ }
  }

  void _setTag(String v) { if (tag == v) return; setState(() => tag = v); _load(); }
  void _setRadius(double v) { if (radius == v) return; setState(() => radius = v); _persist(); _load(); }
  void _toggleFriends() { setState(() => friends = !friends); _persist(); _load(); }

  /// معرّفات أصدقائي (جهات الاتصال) عند تفعيل «أصدقائي فقط».
  Future<List<String>?> _authors() async {
    if (!friends) return null;
    _friendIds ??= (await ref.read(contactsProvider.future)).map((p) => p.id).toList();
    return _friendIds;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// يبدأ فوراً من آخر موقع معروف (أو موقع الحضور أو مركز الخريطة)، ثم يطلب موقع الجهاز في الخلفية ويعيد التحميل إن اختلف.
  bool _refining = false;
  void _refineOrigin() {
    if (_refining || DeviceLocation.lastBrowse != null) return;
    _refining = true;
    unawaited(DeviceLocation.browse().then((l) {
      if (!mounted || l == null || origin == null) return;
      if (const Distance().distance(l, origin!) > 500) _load();
    }).catchError((_) {}));
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      origin = DeviceLocation.lastBrowse ?? ref.read(feedOriginProvider);
      _refineOrigin();
      final s = await ref.read(apiClientProvider).postsFeed(lat: origin!.latitude, lng: origin!.longitude, place: widget.placeKey, tag: tag, radiusKm: widget.placeKey != null ? 200 : radius, authors: await _authors());
      if (!mounted) return;
      setState(() { items = s.items; next = s.nextCursor; located = s.located; loading = false; index = 0; });
      if (items.isNotEmpty) _markViewed(0);
    } catch (e) {
      if (mounted) setState(() { error = e; loading = false; });
    }
  }

  Future<void> _more() async {
    if (next == null || more || origin == null) return;
    more = true;
    try {
      final s = await ref.read(apiClientProvider).postsFeed(lat: origin!.latitude, lng: origin!.longitude, place: widget.placeKey, cursor: next, tag: tag, radiusKm: widget.placeKey != null ? 200 : radius, authors: await _authors());
      if (!mounted) return;
      final seen = items.map((p) => p.id).toSet();
      setState(() { items.addAll(s.items.where((p) => !seen.contains(p.id))); next = s.nextCursor; });
    } catch (_) {
      // نحاول عند الصفحة التالية
    } finally {
      more = false;
    }
  }

  void _onPage(int i) {
    setState(() => index = i);
    _markViewed(i);
    if (i >= items.length - 3) _more();
  }

  void _markViewed(int i) {
    final p = items[i];
    if (p.mine || !_viewed.add(p.id)) return;
    ref.read(apiClientProvider).viewPost(p.id).then((v) {
      if (mounted && i < items.length && items[i].id == p.id) setState(() => items[i] = items[i].copyWith(views: v));
    }).catchError((_) {});
  }

  Future<void> _like(int i) async {
    final p = items[i];
    setState(() => items[i] = p.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)));
    try {
      final r = await ref.read(apiClientProvider).likePost(p.id);
      if (mounted) setState(() => items[i] = items[i].copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) { setState(() => items[i] = p); toast(context, e.toString(), error: true); }
    }
  }

  Future<void> _menu(int i) async {
    final p = items[i];
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1F24),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.mine) ListTile(leading: const Icon(Icons.insights_outlined, color: Colors.white), title: const Text('الإحصاءات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'stats')),
          ListTile(leading: const Icon(Icons.map_outlined, color: Colors.white), title: const Text('فتح في العارض', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'viewer')),
          if (!p.mine) ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.white), title: const Text('إبلاغ عن اللحظة', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'report')),
          if (!p.mine) ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${p.user.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    final api = ref.read(apiClientProvider);
    try {
      switch (choice) {
        case 'stats': await showPostStats(context, postId: p.id);
        case 'viewer': await PostViewerPage.open(context, items, index: i);
        case 'report':
          final reason = await askText(context, title: 'إبلاغ عن اللحظة', hint: 'ما المشكلة؟ (احتيال، محتوى مسيء، مضلل…)', confirm: 'إرسال البلاغ');
          if (reason == null || reason.isEmpty || !mounted) return;
          final r = await api.reportContent(type: 'post', id: p.id, reason: reason);
          if (mounted) toast(context, r.hidden ? 'وصل بلاغك وأُخفيت اللحظة للمراجعة' : 'وصل بلاغك وسنراجعه');
        case 'block':
          await api.blockUser(p.user.id);
          invalidatePosts(ref);
          if (!mounted) return;
          toast(context, 'تم حظر ${p.user.nickname}');
          setState(() { items.removeWhere((x) => x.user.id == p.user.id); index = index.clamp(0, items.isEmpty ? 0 : items.length - 1); });
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.placeName ?? 'الآن حولك';
    final subtitle = widget.placeKey != null ? 'لحظات هذا المكان' : located ? 'الأقرب والأحدث أولاً' : 'الأحدث أولاً';
    return Theme(
      data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(fit: StackFit.expand, children: [
            if (loading)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (error != null)
              _Message(icon: Icons.cloud_off_rounded, title: 'تعذر جلب اللحظات', body: error.toString().replaceFirst(RegExp(r'^ApiException\(\d+\): '), ''), action: 'إعادة المحاولة', onAction: _load)
            else if (items.isEmpty)
              _Message(
                icon: Icons.auto_awesome_outlined,
                title: widget.placeKey != null ? 'لا لحظات في هذا المكان الآن' : friends ? 'لا لحظات من أصدقائك الآن' : tag.isNotEmpty ? 'لا شيء من هذا النوع حولك الآن' : 'لا لحظات حولك الآن',
                body: friends ? 'أوقف «أصدقائي فقط» لترى الجميع، أو شارك لحظتك' : radius < 30 && widget.placeKey == null ? 'وسّع النطاق إلى «حولي» أو «المدينة كلها»، أو شارك لحظتك' : 'كن أول من يشارك ما يحدث من حولك',
                action: 'لحظتك',
                onAction: () async { await composePostHere(context, ref); if (mounted) _load(); },
              )
            else
              // السحب بالفأرة أيضاً (الويب على الحاسوب) لا باللمس فقط
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad}),
                child: PageView.builder(
                  key: const Key('feed-pages'),
                  controller: _ctl,
                  scrollDirection: Axis.vertical,
                  itemCount: items.length,
                  onPageChanged: _onPage,
                  itemBuilder: (_, i) => FeedItemView(
                    key: ValueKey(items[i].id),
                    post: items[i],
                    active: i == index,
                    filteredPlace: widget.placeKey,
                    onLike: () => _like(i),
                    onMenu: () => _menu(i),
                  ),
                ),
              ),
            // الشريط العلوي: إغلاق، العنوان، الموضع
            Positioned(
              top: 4, left: 8, right: 8,
              child: Row(children: [
                IconButton(key: const Key('feed-close'), tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11.5, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                ])),
                if (items.isNotEmpty)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)), child: Text('${index + 1} / ${items.length}${next != null ? '+' : ''}', textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ),
            // المرشّحات السريعة: النوع، ثم النطاق و«أصدقائي فقط» (لا نطاق عند تصفية مكان واحد)
            Positioned(
              top: 54, left: 0, right: 0,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [for (final c in tagChips) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: _Chip(key: Key('feed-tag-${c.$1.isEmpty ? 'all' : c.$1}'), label: c.$2, selected: tag == c.$1, onTap: () => _setTag(c.$1)))]),
                ),
                if (widget.placeKey == null)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(children: [
                      for (final c in radiusChips) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: _Chip(key: Key('feed-radius-${c.$1.round()}'), label: c.$2, icon: Icons.radar_rounded, selected: radius == c.$1, onTap: () => _setRadius(c.$1))),
                      const SizedBox(width: 6),
                      _Chip(key: const Key('feed-friends'), label: 'أصدقائي فقط', icon: Icons.people_alt_rounded, selected: friends, onTap: _toggleFriends),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, body, action;
  final VoidCallback onAction;
  const _Message({required this.icon, required this.title, required this.body, required this.action, required this.onAction});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(action)),
          ]),
        ),
      );
}

/// لحظة واحدة في البث: الوسائط بملء الصفحة، شريط أزرار جانبي، ومعلومات الناشر والمكان في الأسفل.
class FeedItemView extends ConsumerStatefulWidget {
  final MapPost post;
  final bool active;
  final String? filteredPlace;
  final VoidCallback onLike, onMenu;
  const FeedItemView({super.key, required this.post, required this.active, this.filteredPlace, required this.onLike, required this.onMenu});
  @override
  ConsumerState<FeedItemView> createState() => _FeedItemViewState();
}

class _FeedItemViewState extends ConsumerState<FeedItemView> {
  bool _burst = false;
  Timer? _burstTimer;

  @override
  void dispose() {
    _burstTimer?.cancel();
    super.dispose();
  }

  void _doubleTap() {
    if (!widget.post.liked) widget.onLike();
    setState(() => _burst = true);
    _burstTimer?.cancel();
    _burstTimer = Timer(const Duration(milliseconds: 700), () { if (mounted) setState(() => _burst = false); });
  }

  void _openPlace(BuildContext context) {
    final pl = widget.post.place;
    if (pl == null) return;
    if (pl.bizId != null) { openBusiness(context, pl.bizId!); return; }
    if (widget.filteredPlace == pl.key || pl.name == null) return;
    FeedPage.open(context, placeKey: pl.key, placeName: pl.name);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    final place = p.place;
    final placeLabel = place?.name ?? p.placeName;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth);
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: SizedBox(
            width: w, height: box.maxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(box.maxWidth > w + 8 ? 20 : 0),
              child: Stack(fit: StackFit.expand, children: [
                PostMedia(kind: p.kind, url: p.mediaUrl, bg: p.bg, durationSec: p.durationSec, play: widget.active),
                IgnorePointer(child: OverlayCanvas(overlays: p.overlays, shadow: p.kind != 'text')),
                Positioned(top: 0, left: 0, right: 0, height: box.maxHeight * .6, child: GestureDetector(key: Key('feed-tap-${p.id}'), behavior: HitTestBehavior.translucent, onDoubleTap: _doubleTap)),
                if (_burst) const Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: 96, shadows: [Shadow(color: Colors.black54, blurRadius: 16)])),
              ]),
            ),
          ),
        ),
        // شريط الأزرار الجانبي
        PositionedDirectional(
          end: 10, bottom: 96,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Rail(key: Key('feed-like-${p.id}'), icon: p.liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded, label: '${p.likes}', color: p.liked ? Joy.accent : Colors.white, onTap: widget.onLike),
            if (!p.mine && me != null) ...[
              const SizedBox(height: 14),
              _Rail(icon: Icons.chat_bubble_outline_rounded, label: 'مراسلة', onTap: () { unawaited(ref.read(apiClientProvider).trackContact(p.id)); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user))); }),
              const SizedBox(height: 14),
              WishButton(kind: 'post', refId: p.id, dark: true, compact: true),
            ],
            if (p.mine) ...[const SizedBox(height: 14), _Rail(icon: Icons.visibility_outlined, label: '${p.views}', onTap: null)],
            const SizedBox(height: 14),
            _Rail(key: Key('feed-menu-${p.id}'), icon: Icons.more_horiz_rounded, label: '', onTap: widget.onMenu),
          ]),
        ),
        // معلومات الناشر والمكان
        PositionedDirectional(
          start: 12, end: 84, bottom: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => openProfile(context, p.user),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ProfileAvatar(person: p.user, size: 36),
                const SizedBox(width: 8),
                Flexible(child: Text('${p.user.nickname} · ${timeAgo(p.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]))),
                if (p.tag != 'moment') Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: _pill(p.tagLabel, Joy.sun, Joy.sunText)),
              ]),
            ),
            if (placeLabel != null && placeLabel.isNotEmpty || p.distanceKm != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  key: Key('feed-place-${p.id}'),
                  onTap: place == null ? null : () => _openPlace(context),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(place?.bizId != null ? Icons.storefront_rounded : Icons.place_rounded, size: 16, color: Joy.sun),
                      const SizedBox(width: 6),
                      Flexible(child: Text([if (placeLabel != null && placeLabel.isNotEmpty) placeLabel, if (p.distanceKm != null) distanceText(p.distanceKm)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
                      if (place?.bizId != null) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.chevron_left_rounded, size: 16, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
            if (p.title.isNotEmpty || p.price != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  if (p.title.isNotEmpty) Flexible(child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]))),
                  if (p.price != null) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: Text(p.price == 0 ? 'مجاناً' : money(p.price!), style: const TextStyle(color: Joy.sun, fontWeight: FontWeight.w800, fontSize: 15))),
                ]),
              ),
            if (p.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]))),
            if (p.cta != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.tonal(onPressed: () { if (!p.mine) unawaited(ref.read(apiClientProvider).trackCta(p.id)); runPostCta(context, p); }, child: Text(p.cta!.label)),
              ),
          ]),
        ),
      ]);
    });
  }

  Widget _pill(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)));
}

class _Rail extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _Rail({super.key, required this.icon, required this.label, this.color = Colors.white, this.onTap});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: Colors.black45, shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 46, height: 46, child: Icon(icon, color: color, size: 24))),
        ),
        if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]))),
      ]);
}

/// شريحة مرشّح فوق الوسائط: شفافة داكنة، وبيضاء عند الاختيار.
class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({super.key, required this.label, this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Colors.white : Colors.black45,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? Joy.text : Colors.white), const SizedBox(width: 5)],
              Text(label, style: TextStyle(color: selected ? Joy.text : Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
