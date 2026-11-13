import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../ui/profile_avatar.dart';
import '../../../ui/widgets.dart';
import 'business_editor.dart' show ownerErrText;

/// سجل نشاط الدائرة: من فعل ماذا ومتى (الفريق، القائمة والأسعار، العروض، الطلبات، بيانات الدائرة، المنشورات، الردود).
/// للمالك ومن يحمل «إدارة الفريق». الأحدث أولاً، ويُحمَّل الأقدم عند الطلب.
class BizActivityPage extends ConsumerStatefulWidget {
  final String bizId;
  const BizActivityPage({super.key, required this.bizId});
  @override
  ConsumerState<BizActivityPage> createState() => _BizActivityPageState();
}

class _BizActivityPageState extends ConsumerState<BizActivityPage> {
  final items = <BizActivity>[];
  String? next;
  int keepDays = 180;
  bool loading = true, more = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool older = false}) async {
    setState(() { if (older) { more = true; } else { loading = true; error = null; } });
    try {
      final page = await ref.read(apiClientProvider).bizActivity(widget.bizId, before: older ? next : null);
      if (!mounted) return;
      setState(() {
        if (!older) items.clear();
        items.addAll(page.items);
        next = page.next;
        keepDays = page.keepDays;
      });
    } catch (e) {
      if (!mounted) return;
      if (older) { toast(context, ownerErrText(e), error: true); } else { setState(() => error = e); }
    } finally {
      if (mounted) setState(() { loading = false; more = false; });
    }
  }

  static IconData _icon(String group) => switch (group) {
        'team' || 'owner' => Icons.groups_outlined,
        'item' => Icons.inventory_2_outlined,
        'offer' => Icons.local_offer_outlined,
        'order' => Icons.receipt_long_outlined,
        'profile' || 'verification' => Icons.badge_outlined,
        'post' => Icons.campaign_outlined,
        'review' => Icons.star_outline_rounded,
        _ => Icons.history_rounded,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('سجل النشاط')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? ErrorState(error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(key: const Key('activity-list'), padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
                      Text('ما فعله الفريق في الدائرة. يُحفظ $keepDays يوماً.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      if (items.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'لا نشاط بعد', subtitle: 'يظهر هنا كل تعديل على الفريق والقائمة والعروض والطلبات.'),
                      for (final a in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: JoyCard(
                            key: Key('activity-${a.id}'),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              a.actor == null ? const CircleAvatar(radius: 18, backgroundColor: Joy.surface2, child: Icon(Icons.person_outline_rounded, size: 18, color: Joy.textMuted)) : ProfileAvatar(person: a.actor!, size: 36),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(a.actor == null || a.actor!.nickname.isEmpty ? 'عضو سابق' : a.actor!.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  Icon(_icon(a.group), size: 15, color: Joy.textMuted),
                                  const SizedBox(width: 4),
                                  Text(timeAgo(a.at), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                                ]),
                                const SizedBox(height: 2),
                                Text(a.summary, style: const TextStyle(fontSize: 13.5, height: 1.5)),
                              ])),
                            ]),
                          ),
                        ),
                      if (next != null)
                        OutlinedButton(key: const Key('activity-more'), onPressed: more ? null : () => _load(older: true), child: Text(more ? 'جارٍ التحميل…' : 'الأقدم')),
                    ]),
                  ),
      );
}
