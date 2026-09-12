import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show dayLabel, shortDate;
import 'business_editor.dart';
import '../../../api/client.dart';

/// الأخبار والعروض التي تنشرها الدائرة في صفحتها.
class PostsTab extends ConsumerWidget {
  final Biz biz;
  const PostsTab({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = biz.posts;
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: biz.canManage ? FloatingActionButton.extended(onPressed: () => openPostEditor(context, biz), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.campaign_outlined), label: const Text('منشور جديد')) : null,
      body: posts.isEmpty
          ? const EmptyState(icon: Icons.campaign_outlined, title: 'لا أخبار أو عروض بعد', subtitle: 'انشر عرضاً بتاريخ انتهاء أو خبراً عن نشاطك ليظهر في صفحتك ولمتابعيك.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => PostCard(post: posts[i], biz: biz, editable: biz.canManage),
            ),
    );
  }
}

/// بطاقة خبر/عرض (تُستخدم في الصفحة العامة ولوحة التحكم).
class PostCard extends ConsumerWidget {
  final BizPost post;
  final Biz biz;
  final bool editable;
  const PostCard({super.key, required this.post, required this.biz, this.editable = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = !post.active || post.expired;
    return Opacity(
      opacity: off && editable ? .6 : 1,
      child: JoyCard(
        padding: EdgeInsets.zero,
        onTap: editable ? () => openPostEditor(context, biz, post: post) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (post.imageUrl != null)
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: Image.network(mediaUrl(post.imageUrl!), height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: post.isOffer ? Joy.accentSoft : Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Text(post.isOffer ? 'عرض' : 'خبر', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: post.isOffer ? Joy.accent : Joy.primary))),
                const SizedBox(width: 8),
                Expanded(child: Text(post.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (editable && off) Text(post.expired ? 'منتهٍ' : 'مخفي', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
              ]),
              if (post.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(post.body, style: const TextStyle(height: 1.5, fontSize: 13.5))),
              const SizedBox(height: 6),
              Text([if (post.endsAt != null) 'حتى ${dayLabel(post.endsAt!)} ${shortDate(post.endsAt!)}', timeAgo(post.createdAt)].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<void> openPostEditor(BuildContext context, Biz biz, {BizPost? post, String kind = 'news'}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      builder: (_) => _PostEditor(biz: biz, post: post, initialKind: kind),
    );

class _PostEditor extends ConsumerStatefulWidget {
  final Biz biz;
  final BizPost? post;
  final String initialKind;
  const _PostEditor({required this.biz, this.post, required this.initialKind});
  @override
  ConsumerState<_PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends ConsumerState<_PostEditor> {
  late final TextEditingController title, body;
  late String kind;
  DateTime? endsAt;
  String? imageUrl;
  bool active = true, busy = false, uploading = false;
  BizPost? get p => widget.post;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: p?.title ?? '');
    body = TextEditingController(text: p?.body ?? '');
    kind = p?.kind ?? widget.initialKind;
    endsAt = p?.endsAt;
    imageUrl = p?.imageUrl;
    active = p?.active ?? true;
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p == null ? 'منشور جديد' : 'تعديل المنشور', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 10),
        Row(children: [
          for (final (k, label, icon) in [('news', 'خبر', Icons.newspaper_rounded), ('offer', 'عرض', Icons.local_offer_outlined)])
            Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(avatar: Icon(icon, size: 16, color: kind == k ? Joy.primaryOn : Joy.textMuted), label: Text(label, style: TextStyle(color: kind == k ? Joy.primaryOn : Joy.text)), selected: kind == k, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setState(() => kind = k))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: title, decoration: InputDecoration(labelText: 'العنوان', hintText: kind == 'offer' ? 'خصم 20% على كل المشروبات' : 'افتتاح فرع جديد')),
        const SizedBox(height: 10),
        TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'التفاصيل')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: endsAt ?? DateTime.now().add(const Duration(days: 7)), helpText: 'تاريخ انتهاء العرض');
                if (d != null) setState(() => endsAt = DateTime(d.year, d.month, d.day, 23, 59));
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(endsAt == null ? 'بلا تاريخ انتهاء' : 'ينتهي ${shortDate(endsAt!)}'),
            ),
          ),
          if (endsAt != null) IconButton(onPressed: () => setState(() => endsAt = null), icon: const Icon(Icons.close_rounded)),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: uploading ? null : _upload, icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_outlined, size: 18), label: Text(imageUrl == null ? 'صورة' : 'تغيير')),
        ]),
        if (imageUrl != null) Padding(padding: const EdgeInsets.only(top: 10), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(mediaUrl(imageUrl!), height: 120, width: double.infinity, fit: BoxFit.cover))),
        if (p != null) SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v), title: const Text('ظاهر في الصفحة')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.send_rounded), label: Text(p == null ? 'نشر' : 'حفظ'))),
          if (p != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : () async {
                try {
                  await ref.read(apiClientProvider).deleteBizPost(widget.biz.id, p!.id);
                  invalidateBizAll(ref, widget.biz.id);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) { if (context.mounted) toast(context, ownerErrText(e), error: true); }
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger),
              label: const Text('حذف', style: TextStyle(color: Joy.danger)),
            ),
          ],
        ]),
      ]),
    );
  }

  Future<void> _upload() async {
    try {
      final img = await pickImage();
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => imageUrl = up.url);
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) { toast(context, 'اكتب العنوان', error: true); return; }
    setState(() => busy = true);
    final data = {'kind': kind, 'title': title.text.trim(), 'body': body.text.trim(), 'imageUrl': imageUrl, 'endsAt': endsAt?.toUtc().toIso8601String(), 'active': active};
    try {
      final api = ref.read(apiClientProvider);
      if (p == null) {
        await api.createBizPost(widget.biz.id, data);
      } else {
        await api.updateBizPost(widget.biz.id, p!.id, data);
      }
      invalidateBizAll(ref, widget.biz.id);
      if (mounted) { Navigator.pop(context); toast(context, p == null ? 'نُشر' : 'حُفظ'); }
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
