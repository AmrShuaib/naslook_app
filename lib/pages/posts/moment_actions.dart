// أفعال اللحظة في العارض: عمود الحافة كسناب وتيك توك (إعجاب، تفاعل سريع، حفظ في «محفوظاتي»، مشاركة، الخريطة)،
// شريط التفاعلات الأربعة، ورقة المشاركة (محادثة، مشاركة أصلية، نسخ الرابط)، «عرض على الخريطة» و«الاتجاهات»،
// وصفحة رابط اللحظة (`#/m/<id>` أو إشعار التفاعل) التي تجلب اللحظة وتفتح العارض.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/moments_api.dart';
import '../../api/naslife_api.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../core/chat/codes.dart';
import '../../core/directions.dart';
import '../../core/nav_provider.dart';
import '../../core/require_account.dart';
import '../../core/share/share_stub.dart' if (dart.library.js_interop) '../../core/share/share_web.dart' if (dart.library.io) '../../core/share/share_io.dart' as share_impl;
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/providers.dart';
import '../../state/wishlist_providers.dart';
import '../../ui/widgets.dart';
import 'post_viewer.dart';

/// لون أوراق العارض الداكنة (نفس قوائم الخيارات).
const momentSheetColor = Color(0xFF1C1F24);

String _err(Object e) => e is ApiException ? e.message : e.toString();

// -----------------------------------------------------------------------------
// عمود الأفعال
// -----------------------------------------------------------------------------

/// عمود الأفعال على حافة اللحظة. يجلب عدّادات التفاعل حين تظهر اللحظة أول مرة (لا قبل ذلك حتى لا تُطلب لكل صفحة في العارض).
class MomentRail extends ConsumerStatefulWidget {
  final MapPost post;
  final bool active;
  final VoidCallback onLike;
  /// إيقاف التقدّم التلقائي مؤقتاً ما دام شريط التفاعل أو ورقة المشاركة مفتوحين.
  final ValueChanged<bool>? onHold;
  /// شاشة قصيرة: أيقونات بلا تسميات حتى لا يزاحم العمود التعليق.
  final bool compact;
  const MomentRail({super.key, required this.post, required this.active, required this.onLike, this.onHold, this.compact = false});

  @override
  ConsumerState<MomentRail> createState() => _MomentRailState();
}

class _MomentRailState extends ConsumerState<MomentRail> {
  final _anchor = GlobalKey();
  MomentReactions _r = MomentReactions.empty;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(MomentRail old) {
    super.didUpdateWidget(old);
    if (old.post.id != widget.post.id) {
      _r = MomentReactions.empty;
      _loaded = false;
    }
    if (widget.active && !_loaded) _load();
  }

  void _load() {
    _loaded = true;
    final id = widget.post.id;
    ref.read(apiClientProvider).momentReactions(id).then((r) {
      if (mounted && widget.post.id == id) setState(() => _r = r);
    }).catchError((_) {});
  }

  Future<void> _react() async {
    // الإرسال يحتاج حساباً: الزائر يُدعى للدخول قبل فتح الشريط
    if (!requireAccount(context)) return;
    widget.onHold?.call(true);
    final picked = await _showBar();
    widget.onHold?.call(false);
    if (picked == null || !mounted) return;
    final prev = _r;
    // الضغط على تفاعلي الحالي يزيله
    final next = picked == prev.mine ? null : picked;
    setState(() => _r = prev.withMine(next));
    try {
      final r = await ref.read(apiClientProvider).reactMoment(widget.post.id, next);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _r = prev);
      toast(context, _err(e), error: true);
    }
  }

  /// الشريط بجانب زر التفاعل (بعيداً عن الحافة)، وفي وسط الشاشة إن تعذّر حساب موضعه.
  Future<String?> _showBar() {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final rect = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    final r = _r;
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) {
        final bar = MomentReactionBar(reactions: r, onPick: (e) => Navigator.pop(ctx, e));
        if (rect == null) return Center(child: bar);
        final size = MediaQuery.of(ctx).size;
        final edgeLeft = rect.center.dx < size.width / 2;
        final top = (rect.center.dy - 34).clamp(8.0, (size.height - 80).clamp(8.0, double.infinity));
        // العمود على حافة؛ الشريط يمتد نحو الوسط مهما كان الاتجاه
        return Stack(children: [
          Positioned(
            top: top,
            left: edgeLeft ? rect.right + 6 : null,
            right: edgeLeft ? null : size.width - rect.left + 6,
            child: bar,
          ),
        ]);
      },
      transitionBuilder: (ctx, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: .85, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
      ),
    );
  }

  Future<void> _share() => showMomentShareSheet(context, ref, widget.post, onHold: widget.onHold);

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final signedIn = ref.watch(signedInProvider);
    // الزائر لا يطلب قائمة الأمنيات (مسار حساب)؛ زر الحفظ يدعوه للدخول
    final saved = signedIn && ref.watch(wishKeysProvider).contains('post:${p.id}');
    final total = _r.total;
    final gap = widget.compact ? 4.0 : 10.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _RailButton(
        buttonKey: const Key('moment-like'),
        label: '${p.likes}',
        semantic: p.liked ? 'إلغاء الإعجاب' : 'إعجاب',
        compact: widget.compact,
        onTap: widget.onLike,
        // ضغطة مطوّلة على القلب تفتح التفاعلات كما في التطبيقات المألوفة
        onLongPress: _react,
        child: Icon(p.liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded, size: 26, color: p.liked ? Joy.accent : Colors.white),
      ),
      SizedBox(height: gap),
      _RailButton(
        key: _anchor,
        buttonKey: const Key('moment-react'),
        label: total > 0 ? '$total' : 'تفاعل',
        semantic: 'تفاعل',
        compact: widget.compact,
        highlighted: _r.mine != null,
        onTap: _react,
        child: _r.mine != null
            ? Text(_r.mine!, key: const Key('moment-react-mine'), style: const TextStyle(fontSize: 22, height: 1.1))
            : const Icon(Icons.add_reaction_outlined, size: 25, color: Colors.white),
      ),
      SizedBox(height: gap),
      _RailButton(
        buttonKey: const Key('moment-save'),
        label: saved ? 'محفوظة' : 'حفظ',
        semantic: saved ? 'إزالة من محفوظاتي' : 'حفظ في محفوظاتي',
        compact: widget.compact,
        onTap: () {
          if (!requireAccount(context)) return;
          toggleWish(context, ref, kind: 'post', refId: p.id, added: 'حُفظت في محفوظاتي', removed: 'أُزيلت من محفوظاتي');
        },
        child: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 26, color: saved ? Joy.sun : Colors.white),
      ),
      SizedBox(height: gap),
      _RailButton(
        buttonKey: const Key('moment-share'),
        label: 'مشاركة',
        semantic: 'مشاركة اللحظة',
        compact: widget.compact,
        onTap: _share,
        child: const Icon(Icons.ios_share_rounded, size: 24, color: Colors.white),
      ),
      SizedBox(height: gap),
      _RailButton(
        buttonKey: const Key('moment-map'),
        label: 'الخريطة',
        semantic: 'عرض على الخريطة',
        compact: widget.compact,
        onTap: () => showMomentOnMap(context, ref, p),
        child: const Icon(Icons.place_outlined, size: 25, color: Colors.white),
      ),
    ]);
  }
}

/// زر دائري في العمود مع تسمية صغيرة تحته.
class _RailButton extends StatelessWidget {
  final Key buttonKey;
  final Widget child;
  final String label, semantic;
  final VoidCallback? onTap, onLongPress;
  final bool compact, highlighted;
  const _RailButton({super.key, required this.buttonKey, required this.child, required this.label, required this.semantic, this.onTap, this.onLongPress, this.compact = false, this.highlighted = false});

  static const _shadow = [Shadow(color: Colors.black87, blurRadius: 6)];

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        child: InkResponse(
          key: buttonKey,
          onTap: onTap,
          onLongPress: onLongPress,
          radius: 28,
          child: SizedBox(
            width: 56,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: highlighted ? Joy.accent.withValues(alpha: .35) : Colors.black38,
                  shape: BoxShape.circle,
                  border: highlighted ? Border.all(color: Joy.accent, width: 1.5) : null,
                ),
                child: child,
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: _shadow)),
              ],
            ]),
          ),
        ),
      );
}

/// شريط التفاعلات الأربعة بعدّاد كل منها وإبراز تفاعلي.
class MomentReactionBar extends StatelessWidget {
  final MomentReactions reactions;
  final ValueChanged<String> onPick;
  const MomentReactionBar({super.key, required this.reactions, required this.onPick});

  @override
  Widget build(BuildContext context) => Material(
        key: const Key('moment-react-bar'),
        color: momentSheetColor.withValues(alpha: .96),
        elevation: 8,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < momentEmojis.length; i++)
              _emoji(i, momentEmojis[i]),
          ]),
        ),
      );

  Widget _emoji(int i, String e) {
    final mine = reactions.mine == e;
    final n = reactions.count(e);
    return Semantics(
      button: true,
      selected: mine,
      label: mine ? 'إزالة تفاعلك $e' : 'تفاعل $e',
      child: InkResponse(
        key: Key('moment-react-$i'),
        onTap: () => onPick(e),
        radius: 26,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 50,
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: mine ? BoxDecoration(color: Joy.accent.withValues(alpha: .3), shape: BoxShape.circle, border: Border.all(color: Joy.accent, width: 1.5)) : null,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(e, style: TextStyle(fontSize: mine ? 27 : 25, height: 1.15)),
            if (n > 0) Text('$n', key: Key('moment-react-count-$i'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// المشاركة
// -----------------------------------------------------------------------------

/// ورقة مشاركة اللحظة: إرسالها في محادثة (تظهر بطاقتها)، أو المشاركة الأصلية برابطها العام، أو نسخ الرابط.
Future<void> showMomentShareSheet(BuildContext context, WidgetRef ref, MapPost p, {ValueChanged<bool>? onHold}) async {
  onHold?.call(true);
  const white = TextStyle(color: Colors.white);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: momentSheetColor,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4), child: Text('مشاركة اللحظة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
        ListTile(key: const Key('moment-share-chat'), leading: const Icon(Icons.send_rounded, color: Colors.white), title: const Text('إرسال في محادثة', style: white), subtitle: const Text('تظهر بطاقتها داخل الرسالة', style: TextStyle(color: Colors.white60, fontSize: 12)), onTap: () => Navigator.pop(ctx, 'chat')),
        ListTile(key: const Key('moment-share-native'), leading: const Icon(Icons.ios_share_rounded, color: Colors.white), title: const Text('مشاركة…', style: white), onTap: () => Navigator.pop(ctx, 'native')),
        ListTile(key: const Key('moment-share-copy'), leading: const Icon(Icons.link_rounded, color: Colors.white), title: const Text('نسخ الرابط', style: white), onTap: () => Navigator.pop(ctx, 'copy')),
        const SizedBox(height: 8),
      ]),
    ),
  );
  onHold?.call(false);
  if (choice == null || !context.mounted) return;
  final url = momentLink(p.id);
  switch (choice) {
    case 'chat':
      await sendMomentInChat(context, ref, p);
    case 'native':
      final title = p.title.isNotEmpty ? p.title : (p.caption.isNotEmpty ? p.caption : 'لحظة على ناس لايف');
      final place = p.placeName != null && p.placeName!.isNotEmpty ? ' · ${p.placeName}' : '';
      final ok = await share_impl.nativeShare(title: title, text: '${p.user.nickname}$place على ناس لايف', url: url);
      // الويب بلا Web Share أو سطح المكتب: ننسخ الرابط بدل ورقة لا تظهر
      if (!ok && context.mounted) await _copy(context, url);
    case 'copy':
      await _copy(context, url);
  }
}

Future<void> _copy(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) toast(context, 'نُسخ الرابط');
}

/// يرسل رمز اللحظة (`#post/<id>`) إلى شخص من المحادثات وجهات الاتصال فتظهر بطاقتها في المحادثة.
Future<void> sendMomentInChat(BuildContext context, WidgetRef ref, MapPost p) async {
  if (!requireAccount(context)) return;
  final target = await pickChatPerson(context, ref, title: 'إرسال اللحظة إلى');
  if (target == null || !context.mounted) return;
  try {
    await ref.read(apiClientProvider).sendMessage(target.id, postCode(p.id));
    ref.invalidate(chatsProvider);
    if (context.mounted) toast(context, 'أُرسلت اللحظة إلى ${target.nickname}');
  } catch (e) {
    if (context.mounted) toast(context, _err(e), error: true);
  }
}

/// اختيار شخص من المحادثات وجهات الاتصال (نفس مصدر «إعادة التوجيه» في المحادثة).
Future<Person?> pickChatPerson(BuildContext context, WidgetRef ref, {String title = 'إرسال إلى'}) async {
  var chats = const <Chat>[];
  var contacts = const <Person>[];
  try {
    chats = await ref.read(chatsProvider.future);
  } catch (_) {}
  try {
    contacts = await ref.read(contactsProvider.future);
  } catch (_) {}
  if (!context.mounted) return null;
  final me = ref.read(appStateProvider).user?.id;
  final people = <String, Person>{for (final c in chats) c.peer.id: c.peer, for (final p in contacts) p.id: p}..remove(me);
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => MomentPeoplePicker(people: people.values.toList(), title: title),
  );
}

/// قائمة الأشخاص مع بحث بالاسم أو المعرّف.
class MomentPeoplePicker extends StatefulWidget {
  final List<Person> people;
  final String title;
  const MomentPeoplePicker({super.key, required this.people, required this.title});
  @override
  State<MomentPeoplePicker> createState() => _MomentPeoplePickerState();
}

class _MomentPeoplePickerState extends State<MomentPeoplePicker> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.people.where((p) => q.isEmpty || p.nickname.toLowerCase().contains(q) || p.id.toLowerCase().contains(q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                IconButton(tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(key: const Key('moment-pick-search'), onChanged: (v) => setState(() => q = v.trim().toLowerCase()), decoration: const InputDecoration(hintText: 'ابحث بالاسم', prefixIcon: Icon(Icons.search_rounded))),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.people.isEmpty
                  ? const EmptyState(icon: Icons.forum_outlined, title: 'لا محادثات بعد', subtitle: 'ابدأ محادثة أو أضف صديقاً لترسل له اللحظة.')
                  : list.isEmpty
                      ? const EmptyState(icon: Icons.person_search_rounded, title: 'لا أحد بهذا الاسم')
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => ListTile(
                            key: Key('moment-pick-${list[i].id}'),
                            leading: Avatar(name: list[i].nickname, url: list[i].avatarUrl, size: 40),
                            title: Text(list[i].nickname),
                            subtitle: Text(list[i].id, style: const TextStyle(fontSize: 11)),
                            onTap: () => Navigator.pop(context, list[i]),
                          ),
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الخريطة والاتجاهات
// -----------------------------------------------------------------------------

/// «عرض على الخريطة»: يغلق العارض ويعود إلى خريطة الرئيسية مركّزة على دبوس اللحظة (map_page يستمع لـ mapFocusProvider).
void showMomentOnMap(BuildContext context, WidgetRef ref, MapPost p) {
  ref.read(mapFocusProvider.notifier).state = (lat: p.lat, lng: p.lng);
  ref.read(navIndexProvider.notifier).state = 0;
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// «الاتجاهات» إلى مكان اللحظة في خرائط جوجل.
Future<void> openMomentDirections(BuildContext context, MapPost p) async {
  try {
    await openDirections(p.lat, p.lng);
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر فتح الخرائط على هذا الجهاز', error: true);
  }
}

// -----------------------------------------------------------------------------
// رابط اللحظة
// -----------------------------------------------------------------------------

/// وجهة رابط اللحظة (`/m/<id>` → `#/m/<id>`) وإشعار التفاعل: تجلب اللحظة (GET /mapposts/:id) وتعرضها في العارض.
class MomentLinkPage extends ConsumerStatefulWidget {
  final String id;
  const MomentLinkPage({super.key, required this.id});

  @override
  ConsumerState<MomentLinkPage> createState() => _MomentLinkPageState();
}

class _MomentLinkPageState extends ConsumerState<MomentLinkPage> {
  late Future<MapPost> _post = ref.read(apiClientProvider).mapPost(widget.id);

  @override
  Widget build(BuildContext context) => FutureBuilder<MapPost>(
        future: _post,
        builder: (context, s) {
          final p = s.data;
          if (p != null) return PostViewerPage(key: Key('moment-link-${p.id}'), posts: [p]);
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              actions: [IconButton(tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.maybePop(context))],
            ),
            body: Center(
              child: s.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.hide_image_outlined, color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        const Text('اللحظة لم تعد متاحة', key: Key('moment-link-missing'), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('ربما انتهت أو أخفاها صاحبها.', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          key: const Key('moment-link-retry'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                          onPressed: () => setState(() {
                            _post = ref.read(apiClientProvider).mapPost(widget.id);
                          }),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ]),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          );
        },
      );
}
