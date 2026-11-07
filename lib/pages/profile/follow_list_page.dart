import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart' show Person;
import '../../api/profile_v2_api.dart';
import '../../api/profile_v2_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/feed_providers.dart' show onFollowChanged;
import '../../state/profile_v2_providers.dart';
import '../../state/providers.dart' show signedInProvider;
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart' show errText;
import 'user_profile_page.dart';

/// «متابِعون» و«يتابع» لملف [userId] في تبويبين ([followers] يختار المفتوح أولاً): صفحات تُجلب عند الاقتراب من النهاية، والضغط على
/// شخص يفتح ملفه، وزر متابعة لكل شخص غيري. الملف الخاص قائمتاه لصاحبه ومن أضافهم فقط (الخادم يرد 403 فتظهر «القائمة خاصة»).
class FollowListPage extends StatelessWidget {
  final String userId, name;
  final bool followers;
  const FollowListPage({super.key, required this.userId, required this.name, this.followers = true});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: followers ? 0 : 1,
        child: Scaffold(
          backgroundColor: Joy.bg,
          appBar: AppBar(
            title: Text(name),
            bottom: const TabBar(tabs: [Tab(key: Key('follow-tab-followers'), text: 'متابِعون'), Tab(key: Key('follow-tab-following'), text: 'يتابع')]),
          ),
          body: TabBarView(children: [
            FollowListView(key: const Key('follow-list-followers'), userId: userId, followers: true),
            FollowListView(key: const Key('follow-list-following'), userId: userId, followers: false),
          ]),
        ),
      );
}

/// قائمة واحدة بصفحاتها وحالتها المحلية (تُبنى عند أول زيارة للتبويب).
class FollowListView extends ConsumerStatefulWidget {
  final String userId;
  final bool followers;
  const FollowListView({super.key, required this.userId, required this.followers});
  @override
  ConsumerState<FollowListView> createState() => _FollowListViewState();
}

class _FollowListViewState extends ConsumerState<FollowListView> {
  List<FollowPerson> _items = const [];
  String? _next;
  bool _loading = true, _loadingMore = false, _private = false;
  Object? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiClientProvider).followPage(widget.userId, followers: widget.followers);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _next = page.next;
        _loading = false;
        _private = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _private = e is ApiException && e.statusCode == 403;
        _error = _private ? null : e;
      });
    }
  }

  /// الصفحة التالية بالمؤشر؛ لا شيء إن انتهت أو كان طلب جارياً. ما تكرر (متابعة جديدة بين الصفحتين) لا يُضاف مرتين.
  Future<void> _more() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(apiClientProvider).followPage(widget.userId, followers: widget.followers, before: cursor);
      if (!mounted) return;
      final seen = {for (final p in _items) p.id};
      setState(() {
        _items = [..._items, ...page.items.where((p) => !seen.contains(p.id))];
        _next = page.next;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggle(FollowPerson p) async {
    if (_busy.contains(p.id)) return;
    final was = p.isFollowing;
    void set(bool v) => _items = [for (final x in _items) x.id == p.id ? x.copyWith(isFollowing: v) : x];
    setState(() {
      _busy.add(p.id);
      set(!was);
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = was ? await api.unfollow(p.id) : await api.follow(p.id);
      if (mounted) setState(() => set(r.following));
      ref.invalidate(profileV2Provider(p.id));
      onFollowChanged(ref);
    } catch (e) {
      if (mounted) {
        setState(() => set(was));
        toast(context, errText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_private) {
      return const EmptyState(key: Key('follow-private'), icon: Icons.lock_outline_rounded, title: 'القائمة خاصة', subtitle: 'صاحب هذا الملف يُظهر متابِعيه ومن يتابعهم لأصدقائه فقط');
    }
    if (_error != null && _items.isEmpty) return ErrorState(_error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SizedBox(height: 40),
          EmptyState(
            key: const Key('follow-empty'),
            icon: widget.followers ? Icons.people_outline_rounded : Icons.person_search_outlined,
            title: widget.followers ? 'لا متابِعين بعد' : 'لا يتابع أحداً بعد',
          ),
        ]),
      );
    }
    final signedIn = ref.watch(signedInProvider);
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) _more();
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i == _items.length) {
              if (_loadingMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))));
              // صفحة أولى قصيرة لا تمرير فيها: زر صريح بدل انتظار حدث تمرير لا يأتي
              return _next == null ? const SizedBox(height: 24) : Center(child: TextButton(key: const Key('follow-more'), onPressed: _more, child: const Text('عرض المزيد')));
            }
            final p = _items[i];
            final mine = p.isMe || p.id == me;
            return ListTile(
              key: Key('follow-row-${p.id}'),
              leading: Avatar(name: p.name, url: p.avatarUrl, size: 44),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: p.nickname.isEmpty ? null : Text('@${p.nickname}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              trailing: !signedIn || mine
                  ? null
                  : p.isFollowing
                      ? OutlinedButton(key: Key('follow-row-btn-${p.id}'), onPressed: _busy.contains(p.id) ? null : () => _toggle(p), child: const Text('تتابعه'))
                      : FilledButton(key: Key('follow-row-btn-${p.id}'), onPressed: _busy.contains(p.id) ? null : () => _toggle(p), child: const Text('متابعة')),
              onTap: () => openProfile(context, Person(id: p.id, nickname: p.nickname.isEmpty ? p.name : p.nickname, avatarUrl: p.avatarUrl)),
            );
          },
        ),
      ),
    );
  }
}
