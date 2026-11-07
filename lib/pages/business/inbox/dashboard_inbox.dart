// تبويب «الرسائل» في لوحة الدائرة: صندوق مشترك للمالك والمدير والموظف، بفلاتر (مفتوحة، لي، مغلقة، الكل)،
// شارات غير المقروء، والإسناد والإغلاق من الصف نفسه. hr ومدير النظام لا يقرؤون الرسائل (الإدارة عبر البلاغات فقط).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_inbox_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/client.dart' show ApiException;
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import 'biz_inbox_providers.dart';
import 'biz_thread_page.dart';
import 'inbox_widgets.dart';

const _filters = [('open', 'مفتوحة'), ('mine', 'لي'), ('closed', 'مغلقة'), ('all', 'الكل')];

/// عنوان التبويب مع شارة المحادثات غير المقروءة.
class InboxTabLabel extends ConsumerWidget {
  final String bizId;
  const InboxTabLabel({super.key, required this.bizId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(bizInboxUnreadProvider(bizId)).valueOrNull ?? 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.forum_outlined, size: 17),
      const SizedBox(width: 5),
      const Text('الرسائل'),
      if (unread > 0) ...[const SizedBox(width: 5), UnreadBadge(unread, key: const Key('inbox-tab-badge'))],
    ]);
  }
}

class InboxTab extends ConsumerStatefulWidget {
  final Biz biz;
  const InboxTab({super.key, required this.biz});
  @override
  ConsumerState<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends ConsumerState<InboxTab> {
  String _filter = 'open';

  BizInboxKey get _key => (bizId: widget.biz.id, filter: _filter);

  void _refresh() {
    ref.invalidate(bizInboxProvider);
    ref.invalidate(bizInboxUnreadProvider(widget.biz.id));
  }

  Future<void> _open(BizThread t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizThreadPage(threadId: t.id)));
    if (mounted) _refresh();
  }

  Future<void> _act(BizThread t, String action, BizInboxPage page) async {
    final api = ref.read(apiClientProvider);
    final me = ref.read(appStateProvider).user?.id;
    try {
      if (action.startsWith('assign:')) {
        final id = action.substring(7);
        await api.assignBizThread(t.id, id.isEmpty ? null : id);
      } else if (action == 'take') {
        await api.assignBizThread(t.id, me);
      } else if (action == 'leave') {
        await api.assignBizThread(t.id, null);
      } else if (action == 'close') {
        await api.closeBizThread(t.id);
      } else if (action == 'reopen') {
        await api.reopenBizThread(t.id);
      }
      _refresh();
    } catch (e) {
      if (mounted) toast(context, bizInboxErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(bizInboxProvider(_key));
    final page = data.valueOrNull;
    final counts = {'open': page?.open, 'mine': page?.mine, 'closed': page?.closed, 'all': null};
    final err = data.error;
    if (err is ApiException && err.statusCode == 403) {
      return const EmptyState(
        key: Key('inbox-forbidden'),
        icon: Icons.lock_outline_rounded,
        title: 'الرسائل الخاصة لفريق الدائرة',
        subtitle: 'يقرؤها المالك والمدير والموظف فقط. الإدارة لا تطّلع على المحادثات إلا عبر بلاغ.',
      );
    }
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          for (final (f, label) in _filters)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                key: Key('inbox-filter-$f'),
                label: Text(counts[f] != null && counts[f]! > 0 ? '$label · ${counts[f]}' : label, style: TextStyle(color: _filter == f ? Joy.primaryOn : Joy.text)),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: Joy.primary,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ]),
      ),
      Expanded(
        child: data.when(
          skipLoadingOnRefresh: true,
          data: (p) => RefreshIndicator(
            onRefresh: () async {
              _refresh();
              try { await ref.read(bizInboxProvider(_key).future); } catch (_) { /* الخطأ يظهر في القائمة */ }
            },
            child: p.threads.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                    EmptyState(
                      icon: Icons.forum_outlined,
                      title: _filter == 'mine' ? 'لا محادثات مسندة إليك' : _filter == 'closed' ? 'لا محادثات مغلقة' : 'لا رسائل من العملاء بعد',
                      subtitle: 'يراسل العملاء الدائرة من صفحتها العامة بزر «راسل الدائرة»، وتصل رسائلهم هنا للفريق.',
                    ),
                  ])
                : ListView.builder(
                    key: const Key('inbox-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: p.threads.length,
                    itemBuilder: (_, i) => _InboxRow(t: p.threads[i], page: p, divider: i < p.threads.length - 1, onTap: () => _open(p.threads[i]), onAction: (a) => _act(p.threads[i], a, p)),
                  ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(e, onRetry: _refresh),
        ),
      ),
    ]);
  }
}

class _InboxRow extends ConsumerWidget {
  final BizThread t;
  final BizInboxPage page;
  final bool divider;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  const _InboxRow({required this.t, required this.page, required this.divider, required this.onTap, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    final c = t.customer;
    final unread = t.unread > 0;
    return InkWell(
      key: Key('inbox-row-${t.id}'),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 10),
          child: Row(children: [
            if (c != null) ProfileAvatar(person: c, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c == null ? 'عميل' : (c.nickname.isEmpty ? c.id : c.nickname), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 15))),
                  if (t.closed) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Text('مغلقة', style: TextStyle(fontSize: 11, color: Joy.textMuted))),
                ]),
                const SizedBox(height: 2),
                Text('${t.lastSide == 'team' ? 'الفريق: ' : ''}${t.lastText}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: unread ? Joy.text : Joy.textMuted, fontWeight: unread ? FontWeight.w600 : FontWeight.w500)),
                if (t.assignee != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      const Icon(Icons.assignment_ind_outlined, size: 13, color: Joy.accent),
                      const SizedBox(width: 3),
                      Text(t.assignee!.id == me ? 'مسندة إليك' : t.assignee!.nickname, key: Key('inbox-assignee-${t.id}'), style: const TextStyle(fontSize: 11.5, color: Joy.accent, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(timeAgo(t.lastAt), style: TextStyle(fontSize: 11.5, color: unread ? Joy.primary : Joy.textMuted)),
              const SizedBox(height: 5),
              if (unread) UnreadBadge(t.unread, key: Key('inbox-unread-${t.id}')) else const SizedBox(height: 18),
            ]),
            PopupMenuButton<String>(
              key: Key('inbox-menu-${t.id}'),
              tooltip: 'خيارات',
              icon: const Icon(Icons.more_vert_rounded, color: Joy.textMuted),
              onSelected: onAction,
              itemBuilder: (_) => [
                if (page.canAssignOthers) ...[
                  for (final m in page.team)
                    PopupMenuItem(key: Key('inbox-assign-${t.id}-${m.person.id}'), value: 'assign:${m.person.id}', child: Text('إسناد إلى ${m.person.id == me ? 'نفسي' : (m.person.nickname.isEmpty ? m.person.id : m.person.nickname)}')),
                  if (t.assignee != null) PopupMenuItem(key: Key('inbox-unassign-${t.id}'), value: 'assign:', child: const Text('بلا مسؤول')),
                ] else if (t.assignee?.id == me)
                  PopupMenuItem(key: Key('inbox-leave-${t.id}'), value: 'leave', child: const Text('اترك المحادثة'))
                else
                  PopupMenuItem(key: Key('inbox-take-${t.id}'), value: 'take', child: const Text('خذ المحادثة')),
                if (t.closed)
                  PopupMenuItem(key: Key('inbox-reopen-${t.id}'), value: 'reopen', child: const Text('إعادة فتح'))
                else
                  PopupMenuItem(key: Key('inbox-close-${t.id}'), value: 'close', child: const Text('إغلاق')),
              ],
            ),
          ]),
        ),
        if (divider) const Padding(padding: EdgeInsetsDirectional.only(start: 74), child: Divider(height: 1)),
      ]),
    );
  }
}
