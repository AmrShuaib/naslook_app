import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart' show ApiException, mediaUrl;
import '../../api/commerce_models.dart';
import '../../api/posts_api.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/video_view.dart' show VideoSuspend, VideoView, VideoViewController;
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import '../market/market_page.dart';
import 'composer/voice_layer.dart';
import 'moment_actions.dart';
import 'overlay_canvas.dart';
import 'post_composer.dart';
import 'post_stats.dart';
import 'post_media.dart';

String _msg(Object e) => e is ApiException ? e.message : e.toString();

/// ينفّذ زر الإجراء في المنشور: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة صاحب المنشور.
Future<void> runPostCta(BuildContext context, MapPost p) async {
  final c = p.cta;
  if (c == null) return;
  try {
    await _runCta(context, c, p);
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر فتح الرابط على هذا الجهاز', error: true);
  }
}

Future<void> _runCta(BuildContext context, PostCta c, MapPost p) async {
  switch (c.type) {
    case 'link':
      await launchUrl(Uri.parse(c.value), mode: LaunchMode.externalApplication);
    case 'whatsapp':
      final d = c.value.replaceAll(RegExp(r'\D'), '');
      final intl = d.startsWith('0') ? '966${d.substring(1)}' : d;
      await launchUrl(Uri.parse('https://wa.me/$intl'), mode: LaunchMode.externalApplication);
    case 'call':
      await launchUrl(Uri.parse('tel:${c.value}'));
    case 'biz':
      if (context.mounted) openBusiness(context, c.value);
    case 'market':
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(c.value)));
    case 'chat':
      // المحادثة تطلب مسارات النواة فوراً؛ الزائر يُدعى للدخول قبل فتحها
      if (context.mounted && requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)));
  }
}

/// عارض منشورات الخريطة بملء الشاشة: تمرير بين المنشورات، تقدّم تلقائي للصور والنصوص، إعجاب ومشاهدات، زر الإجراء، وأدوات صاحب المنشور.
class PostViewerPage extends ConsumerStatefulWidget {
  final List<MapPost> posts;
  final int initial;
  const PostViewerPage({super.key, required this.posts, this.initial = 0});

  static Future<void> open(BuildContext context, List<MapPost> posts, {int index = 0}) {
    if (posts.isEmpty) return Future.value();
    return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PostViewerPage(posts: posts, initial: index.clamp(0, posts.length - 1))));
  }

  @override
  ConsumerState<PostViewerPage> createState() => _PostViewerPageState();
}

class _PostViewerPageState extends ConsumerState<PostViewerPage> {
  static const _autoMs = 7000;
  late final PageController _ctl = PageController(initialPage: widget.initial);
  late List<MapPost> posts = List.of(widget.posts);
  late int index = widget.initial;
  Timer? _auto;
  double progress = 0;
  final _viewed = <String>{};
  /// متحكم فيديو اللحظة النشطة (null لغير الفيديو): يُنشأ مع كل لحظة ويُحرَّر عند مغادرتها
  VideoViewController? _video;
  StreamSubscription<void>? _videoEnded;
  final _warmed = <String>{};
  late final AppLifecycleListener _life;
  /// مسار العارض نفسه: يُقرأ في didChangeDependencies فيصلنا تغيّر «هل هو الأعلى» حين يُفتح فوقه شيء أو يُغلق
  ModalRoute<Object?>? _route;

  // --- «العارض مغطّى»: مصدر واحد يوقف التقدّم التلقائي والفيديو، ويمنع الانتقال أو الإغلاق خلف ما فوقه ---
  /// أفعال مفتوحة من العارض (القوائم، ورقة المشاركة ثم منتقي المحادثة، الحوارات) بما فيها الفجوة بين ورقة وأخرى؛
  /// عدّاد لا علَم حتى لا يُنهي فعلٌ إيقافَ فعل آخر ما زال مفتوحاً
  int _holds = 0;
  /// التطبيق في الخلفية أو التبويب مخفي
  bool _hidden = false;
  /// ضغطة مطوّلة على صورة أو نص: توقف التقدّم فقط (الفيديو له إيماءاته)
  bool _pressed = false;
  /// انتهت اللحظة والعارض مغطّى: ننتقل حين يظهر بدل أن ننتقل أو نُغلق خلف ما فوقه
  bool _pendingNext = false;

  /// مسار أو ورقة أو حوار فوق العارض (ومنها دعوة دخول الزائر)، أو فعل مفتوح منه، أو التطبيق مخفي
  bool get _covered => _holds > 0 || _hidden || !(_route?.isCurrent ?? true);
  bool get _frozen => _covered || _pressed;

  /// يطبّق حالة التغطية على الفيديو، وينفّذ الانتقال المؤجّل حين يظهر العارض (بعد الإطار: قد نكون داخل البناء).
  void _syncCovered() {
    if (!mounted) return;
    final covered = _covered;
    _video?.setSuspended(covered, reason: VideoSuspend.viewer);
    if (!covered && _pendingNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _covered || !_pendingNext) return;
        _pendingNext = false;
        _next(auto: true);
      });
    }
  }

  void _hold(bool on) {
    _holds = on ? _holds + 1 : (_holds - 1).clamp(0, 1 << 20);
    _syncCovered();
  }

  /// يوقف العارض طوال [body] (قائمة ثم حوار أو صفحة بعدها) ويعيده بعدها مهما حدث.
  Future<T> _held<T>(Future<T> Function() body) async {
    _hold(true);
    try {
      return await body();
    } finally {
      _hold(false);
    }
  }

  void _onLifecycle(AppLifecycleState s) {
    // المخفي فقط (لا inactive): فقدان التركيز أو سحب مركز التحكم لا يوقف اللحظة
    final hidden = s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached;
    if (hidden == _hidden) return;
    _hidden = hidden;
    _syncCovered();
  }

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onStateChange: _onLifecycle);
    VideoView.prepareSound();
    _onShown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _syncCovered();
  }

  @override
  void dispose() {
    _life.dispose();
    _auto?.cancel();
    _releaseVideo();
    _ctl.dispose();
    super.dispose();
  }

  void _releaseVideo() {
    _videoEnded?.cancel();
    _videoEnded = null;
    _video?.dispose();
    _video = null;
  }

  void _onShown() {
    _markViewed();
    _auto?.cancel();
    _releaseVideo();
    _pendingNext = false;
    progress = 0;
    final p = posts[index];
    if (p.kind == 'image' || p.kind == 'text') {
      _auto = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        // كل نبضة تعيد قراءة التغطية فلا يفوتنا تغيّر لم يصلنا خبره
        _syncCovered();
        if (_frozen) return;
        _timedStep();
      });
    } else if (p.kind == 'video' && (p.mediaUrl ?? '').isNotEmpty) {
      // الفيديو: الشريط يتبع موضع المقطع، وانتهاؤه ينقل إلى التالية؛ وإن تعذّر تشغيله يتقدّم كالصورة حتى لا يعلق العارض
      final c = _video = VideoViewController();
      // لحظة تُعرض والعارض مغطّى (حُذفت سابقتها من قائمة مفتوحة): تنتظر حتى يظهر
      c.setSuspended(_covered, reason: VideoSuspend.viewer);
      _videoEnded = c.onEnded.listen((_) {
        if (mounted && identical(c, _video)) _next(auto: true);
      });
      _auto = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        _syncCovered();
        final v = c.value;
        if (v.failed) {
          if (!_frozen) _timedStep();
          return;
        }
        final d = v.duration;
        final f = d == null || d.inMilliseconds <= 0 ? 0.0 : (c.estimatedPosition.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        if ((f - progress).abs() >= .001) setState(() => progress = f);
      });
    }
    // اللحظة التالية فيديو: غلافها وأول المقطع يُجلبان الآن فتبدأ فوراً حين تصلها (بعد الإطار لأن السياق يلزمه)
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmNext());
  }

  /// خطوة المؤقّت للصورة والنص (والفيديو المتعذّر): عند الامتلاء ينتقل مرة واحدة ويتوقف المؤقّت، فلا يُعاد بدء حركة الانتقال
  /// كل 50 م.ث قبل اكتمالها؛ ظهور اللحظة التالية يبدأ مؤقّتها
  void _timedStep() {
    setState(() => progress += 50 / _autoMs);
    if (progress < 1) return;
    _auto?.cancel();
    _next(auto: true);
  }

  void _warmNext() {
    if (!mounted || index + 1 >= posts.length) return;
    final n = posts[index + 1];
    final media = n.mediaUrl ?? '';
    if (n.kind != 'video' || media.isEmpty || !_warmed.add(n.id)) return;
    warmMomentVideo(context, ref.read(apiClientProvider), media);
  }

  void _markViewed() {
    final p = posts[index];
    if (p.mine || !_viewed.add(p.id)) return;
    ref.read(apiClientProvider).viewPost(p.id).then((v) {
      // بالمعرّف لا بالموضع: العارض قد يكون انتقل إلى لحظة أخرى قبل الرد
      if (mounted) _replace(p.id, (x) => x.copyWith(views: v));
    }).catchError((_) {});
  }

  void _replace(String id, MapPost Function(MapPost p) f) {
    final at = posts.indexWhere((x) => x.id == id);
    if (at >= 0) setState(() => posts[at] = f(posts[at]));
  }

  /// التالية، أو إغلاق العارض بعد الأخيرة. [auto] من انتهاء المقطع أو المؤقّت: لا يحدث والعارض مغطّى (يُؤجَّل حتى يظهر)،
  /// فلا تنتقل اللحظات خلف ورقة ولا يُغلق ما فوق العارض.
  void _next({bool auto = false}) {
    if (!mounted) return;
    if (auto && _covered) {
      _pendingNext = true;
      return;
    }
    if (index + 1 < posts.length) {
      _ctl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _auto?.cancel();
      _close();
    }
  }

  void _prev() {
    if (index > 0) _ctl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  /// يغلق العارض نفسه لا أعلى المستكشف: Navigator.pop كان يغلق الورقة أو الحوار أو الصفحة المفتوحة فوقه.
  void _close() {
    if (!mounted) return;
    final r = _route;
    if (r == null || r.isCurrent) {
      Navigator.of(context).pop();
    } else if (r.isActive) {
      Navigator.of(context).removeRoute(r);
    }
  }

  Future<void> _like(int i) async {
    final p = posts[i];
    _replace(p.id, (_) => p.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)));
    try {
      final r = await ref.read(apiClientProvider).likePost(p.id);
      if (mounted) _replace(p.id, (x) => x.copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) {
        _replace(p.id, (_) => p);
        toast(context, _msg(e), error: true);
      }
    }
  }

  /// قائمة منشور شخص آخر: إبلاغ عن المنشور أو حظر ناشره. العارض موقوف طوال القائمة وما يتبعها (ورقة الأسباب، دعوة الدخول).
  Future<void> _otherMenu(int i) => _held(() async {
        final p = posts[i];
        final choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF1C1F24),
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(key: const Key('moment-directions'), leading: const Icon(Icons.directions_rounded, color: Colors.white), title: const Text('الاتجاهات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'directions')),
              ListTile(key: const Key('moment-report'), leading: const Icon(Icons.flag_outlined, color: Colors.white), title: const Text('إبلاغ عن المنشور', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'report')),
              ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${p.user.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'directions') return openMomentDirections(context, p);
        // الإبلاغ والحظر يحتاجان حساباً: ندعو الزائر للدخول قبل ورقة الأسباب بدل رفض 401 بعدها
        if (!requireAccount(context)) return;
        final api = ref.read(apiClientProvider);
        try {
          if (choice == 'report') {
            final r = await showReportSheet(context, ref, type: 'post', id: p.id, author: p.user, title: 'إبلاغ عن المنشور');
            if (r != null && (r.blocked || r.hidden)) {
              invalidatePosts(ref, removedPostId: r.hidden ? p.id : null);
              if (!mounted) return;
              if (r.blocked) return _close();
              // أُخفي المنشور تلقائياً بالبلاغ: يختفي من العارض كما يختفي من البث
              _remove(p.id);
            }
          } else if (choice == 'block') {
            await api.blockUser(p.user.id);
            // قائمة المحظورين تصفّي منشورات الدوائر وتعليقاتها وحالة الملف؛ بلا تحديثها يبقى محتواه ظاهراً حتى إعادة التشغيل
            ref.invalidate(blockedUsersProvider);
            invalidatePosts(ref);
            if (mounted) {
              toast(context, 'تم حظر ${p.user.nickname}');
              _close();
            }
          }
        } catch (e) {
          if (mounted) toast(context, _msg(e), error: true);
        }
      });

  /// يزيل منشوراً من العارض (حُذف أو أُخفي) بمعرّفه لا بموضعه، ويغلق العارض إن كان الأخير.
  void _remove(String id) {
    final at = posts.indexWhere((x) => x.id == id);
    if (at < 0) return;
    if (posts.length == 1) {
      _auto?.cancel();
      _close();
      return;
    }
    final shown = at == index;
    setState(() {
      posts.removeAt(at);
      if (at < index) index--;
      index = index.clamp(0, posts.length - 1);
    });
    if (shown) {
      _onShown();
    } else {
      _ctl.jumpToPage(index);
    }
  }

  /// قائمة صاحب اللحظة. العارض موقوف طوال القائمة وما يتبعها (الإحصاءات، المحرّر، حوار الحذف)، فلا ينتهي المقطع
  /// خلف حوار الحذف فيغلقه ويُلغى الحذف بصمت.
  Future<void> _menu(int i) => _held(() async {
        final p = posts[i];
        final choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF1C1F24),
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.insights_outlined, color: Colors.white), title: const Text('الإحصاءات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'stats')),
              ListTile(key: const Key('moment-directions'), leading: const Icon(Icons.directions_rounded, color: Colors.white), title: const Text('الاتجاهات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'directions')),
              ListTile(key: const Key('moment-edit'), leading: const Icon(Icons.edit_outlined, color: Colors.white), title: const Text('تعديل المنشور', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(leading: Icon(p.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white), title: Text(p.status == 'active' ? 'إخفاء من الخريطة' : 'إظهار على الخريطة', style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'toggle')),
              ListTile(key: const Key('moment-delete'), leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف المنشور', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'directions') return openMomentDirections(context, p);
        final api = ref.read(apiClientProvider);
        try {
          if (choice == 'stats') {
            await showPostStats(context, postId: p.id);
            return;
          }
          if (choice == 'edit') {
            final updated = await PostComposerPage.open(context, lat: p.lat, lng: p.lng, placeName: p.placeName, edit: p);
            if (updated != null && mounted) _replace(p.id, (_) => updated);
          } else if (choice == 'toggle') {
            if (p.status == 'blocked') {
              toast(context, 'أخفته الإدارة؛ تواصل مع الدعم', error: true);
              return;
            }
            final updated = await api.updatePost(p.id, {'status': p.status == 'active' ? 'hidden' : 'active'});
            invalidatePosts(ref, removedPostId: updated.status == 'active' ? null : p.id);
            if (mounted) _replace(p.id, (_) => updated);
          } else if (choice == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('حذف المنشور'),
                content: const Text('سيُزال من الخريطة نهائياً.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('moment-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
              ),
            );
            if (ok != true || !mounted) return;
            await api.deletePost(p.id);
            invalidatePosts(ref, removedPostId: p.id);
            if (!mounted) return;
            _remove(p.id);
          }
        } catch (e) {
          if (mounted) toast(context, _msg(e), error: true);
        }
      });

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            // متحكم فيديو اللحظة النشطة لوسائطها ومنطقة لمسها
            child: MomentPlayback(controller: _video, child: PageView.builder(
              controller: _ctl,
              itemCount: posts.length,
              onPageChanged: (i) {
                setState(() => index = i);
                _onShown();
              },
              itemBuilder: (_, i) => PostView(
                post: posts[i],
                active: i == index,
                progress: i == index ? progress : 0,
                total: posts.length,
                position: i,
                onPrev: _prev,
                onNext: _next,
                onLike: () => _like(i),
                onMenu: posts[i].mine ? () => _menu(i) : () => _otherMenu(i),
                // الضغطة المطوّلة على صورة أو نص توقف التقدّم؛ وأفعال العمود (التفاعل، المشاركة) توقف العارض حتى تنتهي سلسلتها
                onPress: (h) {
                  _pressed = h;
                  _syncCovered();
                },
                onHold: _hold,
              ),
            )),
          ),
        ),
      );
}

/// منشور واحد داخل العارض.
class PostView extends ConsumerWidget {
  final MapPost post;
  final bool active;
  final double progress;
  final int total, position;
  final VoidCallback onPrev, onNext, onLike;
  final VoidCallback? onMenu;
  /// ضغطة مطوّلة على صورة أو نص (بدايتها ونهايتها)
  final ValueChanged<bool>? onPress;
  /// فعل من عمود الأفعال بدأ أو انتهى (true ثم false دائماً بأزواج)
  final ValueChanged<bool>? onHold;
  const PostView({super.key, required this.post, required this.active, required this.progress, required this.total, required this.position, required this.onPrev, required this.onNext, required this.onLike, this.onMenu, this.onPress, this.onHold});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = post;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth);
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: SizedBox(
            width: w,
            height: box.maxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(box.maxWidth > w + 8 ? 20 : 0),
              child: Stack(fit: StackFit.expand, children: [
                PostMedia(kind: p.kind, url: p.mediaUrl, bg: p.bg, durationSec: p.durationSec, play: active),
                IgnorePointer(child: OverlayCanvas(overlays: p.overlays, shadow: p.kind != 'text')),
                // الطبقة الصوتية: تعليق صوتي على الصورة أو لوحة النص
                if (p.audioUrl != null && p.audioUrl!.isNotEmpty) Positioned(bottom: 96, left: 0, right: 0, child: Center(child: VoiceChip(url: mediaUrl(p.audioUrl!), seconds: p.audioSec, light: p.kind == 'text' && colorFromHex(p.bg, Colors.white).computeLuminance() > .5))),
                // مناطق النقر للتنقل (النصف الأعلى فقط حتى تبقى أدوات الفيديو والأزرار متاحة)
                if (p.kind != 'video')
                  Positioned(
                    top: 0, left: 0, right: 0, height: box.maxHeight * .55,
                    child: Row(children: [
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onNext : onPrev, onLongPressStart: (_) => onPress?.call(true), onLongPressEnd: (_) => onPress?.call(false))),
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onPrev : onNext, onLongPressStart: (_) => onPress?.call(true), onLongPressEnd: (_) => onPress?.call(false))),
                    ]),
                  )
                // الفيديو بلا أزرار تحكم (كسناب): اللحظة كلها للمس — النقر للتنقل كالصور (الصف أعلاه ينعكس مع الاتجاه فيبقى
                // اليسار الفعلي للسابقة واليمين للتالية)، والضغط المطوّل يسرّع أو يرجّع أو يوقف
                else if (active)
                  Positioned.fill(child: MomentVideoGestures(controller: MomentPlayback.maybeOf(context), onLeftTap: onPrev, onRightTap: onNext)),
              ]),
            ),
          ),
        ),
        // الشريط العلوي: تقدّم، إغلاق، تنقّل، صاحب المنشور
        Positioned(
          top: 6, left: 10, right: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < total; i++)
                Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: i < position ? 1 : i == position ? progress.clamp(0, 1) : 0, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              InkWell(
                onTap: () => openProfile(context, p.user),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ProfileAvatar(person: p.user, size: 38),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.user.nickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                    Text('${timeAgo(p.createdAt)}${p.placeName != null && p.placeName!.isNotEmpty ? ' · ${p.placeName}' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 11.5, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              if (p.tag != 'moment') _pill(p.tagLabel, Joy.sun, Joy.sunText),
              if (p.mine && p.status != 'active') Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: _pill(p.status == 'blocked' ? 'أخفته الإدارة' : 'مخفي', Colors.white24, Colors.white)),
              const Spacer(),
              if (total > 1) ...[
                IconButton(tooltip: 'السابق', onPressed: onPrev, icon: const Icon(Icons.chevron_right_rounded, color: Colors.white)),
                IconButton(tooltip: 'التالي', onPressed: onNext, icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
              ],
              IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ]),
        ),
        // الأسفل: العنوان والسعر والتعليق، وبجانبها عمود الأفعال على الحافة كسناب وتيك توك (إعجاب، تفاعل، حفظ، مشاركة، خريطة)،
        // ثم زر الإجراء، وصف المراسلة والمشاهدات والخيارات
        Positioned(
          bottom: 10, left: 12, right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (p.title.isNotEmpty || p.price != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        if (p.title.isNotEmpty) Expanded(child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                        if (p.price != null) Text(p.price == 0 ? 'مجاناً' : money(p.price!), style: const TextStyle(color: Joy.sun, fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                    ),
                  if (p.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p.caption, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))),
                ]),
              ),
              const SizedBox(width: 8),
              // شاشة قصيرة: أيقونات بلا تسميات حتى يبقى للتعليق مكان
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MomentRail(key: ValueKey('moment-rail-${p.id}'), post: p, active: active, onLike: onLike, onHold: onHold, compact: box.maxHeight < 640),
              ),
            ]),
            if (p.cta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { if (!p.mine) unawaited(ref.read(apiClientProvider).trackCta(p.id)); runPostCta(context, p); }, icon: Icon(_ctaIcon(p.cta!.type)), label: Text(p.cta!.label.isNotEmpty ? p.cta!.label : postCtaTypes[p.cta!.type] ?? ''))),
              ),
            Row(children: [
              if (p.mine) _action(Icons.visibility_outlined, '${p.views}', null),
              if (!p.mine && me != null) ...[
                _action(Icons.chat_bubble_outline_rounded, 'مراسلة', () {
                  if (!requireAccount(context)) return;
                  unawaited(ref.read(apiClientProvider).trackContact(p.id));
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)));
                }),
                const SizedBox(width: 6),
                // «رد خاص»: يفتح المحادثة والحقل مملوء برمز اللحظة (#post/…) فتظهر بطاقتها داخل الرسالة؛ أيقونة فقط لأن الصف ضيّق على الجوال
                _action(Icons.reply_rounded, '', () {
                  if (!requireAccount(context)) return;
                  unawaited(ref.read(apiClientProvider).trackContact(p.id));
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user, initialText: '#post/${p.id} ')));
                }, key: const Key('post-reply-private'), tooltip: 'رد خاص'),
              ],
              const Spacer(),
              if (onMenu != null) IconButton(tooltip: 'خيارات', onPressed: onMenu, icon: const Icon(Icons.more_horiz_rounded, color: Colors.white)),
            ]),
          ]),
        ),
      ]);
    });
  }

  static IconData _ctaIcon(String t) => switch (t) { 'whatsapp' => Icons.chat_rounded, 'call' => Icons.call_rounded, 'biz' => Icons.storefront_rounded, 'market' => Icons.shopping_bag_rounded, 'chat' => Icons.chat_bubble_outline_rounded, _ => Icons.open_in_new_rounded };

  Widget _pill(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)));

  /// زر دائري في صف الأسفل؛ بلا [label] يكون أيقونة فقط (مع [tooltip] لتسميته).
  Widget _action(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white, Key? key, String? tooltip}) {
    final pill = Material(
      key: key,
      color: Colors.black45,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 10 : 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: color),
            if (label.isNotEmpty) ...[const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))],
          ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}
