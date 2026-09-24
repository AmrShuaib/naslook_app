// قسم المدونة في لوحة الإدارة: قائمة المنشورات بعدّادات ومرشّحات (الحالة والنوع) وبحث، وإجراءات لكل منشور (تعديل، نشر
// أو إلغاء نشر، جدولة، معاينة على الموقع، تثبيت، نسخ الرابط، نسخ كمسودة، حذف)، ومحرر كامل: العنوان والملخص والنوع
// وصورة الغلاف (رفع أو رابط) والنص بشريط التنسيق والمعاينة، وخيارات متقدمة (معرّف الرابط، الوسوم، التثبيت، تاريخ النشر).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_blog_api.dart';
import '../../api/chat_tools_api.dart';
import '../../api/client.dart' show mediaUrl, thumbUrl;
import '../../core/app_theme.dart';
import '../../core/media/pick_image.dart';
import '../../core/share/share_links.dart';
import '../../core/text/markup_edit.dart';
import '../../core/text/post_markup.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../ui/markup_toolbar.dart';
import '../../ui/widgets.dart';

String blogErrText(Object e) {
  final s = e.toString();
  if (s.contains('bad-title')) return 'اكتب عنواناً (حتى 160 حرفاً)';
  if (s.contains('bad-slug')) return 'معرّف الرابط: حروف لاتينية صغيرة وأرقام وشرطات فقط';
  if (s.contains('slug-taken')) return 'معرّف الرابط مستخدم لمنشور آخر';
  if (s.contains('bad-cover')) return 'رابط صورة الغلاف غير صالح';
  if (s.contains('bad-date')) return 'التاريخ غير صالح';
  if (s.contains('bad-kind')) return 'نوع المنشور غير معروف';
  if (s.contains('admin-only')) return 'هذا الإجراء لمدير النظام فقط';
  if (s.contains('blog-admin-unavailable')) return 'إدارة المدونة غير متاحة على هذا الخادم';
  if (s.contains('not-found')) return 'المنشور غير موجود';
  return s.replaceFirst(RegExp(r'^ApiException\(\d+\): '), '');
}

String _fmt(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String _fmtDay(DateTime? d) { if (d == null) return ''; final l = d.toLocal(); return '${l.day}/${l.month}/${l.year}'; }

Color _kindColor(String k) => switch (k) { 'news' => Joy.accent, 'post' => Joy.sunText, _ => Joy.primary };
IconData _kindIcon(String k) => switch (k) { 'news' => Icons.campaign_outlined, 'post' => Icons.article_outlined, _ => Icons.new_releases_outlined };

Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(hours: 1));
  final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 365 * 2)), initialDate: start, helpText: 'تاريخ النشر');
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start), helpText: 'وقت النشر');
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// قائمة المدونة.
class AdminBlogPage extends ConsumerStatefulWidget {
  const AdminBlogPage({super.key});
  @override
  ConsumerState<AdminBlogPage> createState() => _AdminBlogPageState();
}

class _AdminBlogPageState extends ConsumerState<AdminBlogPage> {
  final _search = TextEditingController();
  var _q = '', _kind = '', _status = 'all';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  ({String q, String kind, String status}) get _key => (q: _q, kind: _kind, status: _status);

  void _refresh() {
    ref.invalidate(adminBlogProvider);
    ref.invalidate(adminBlogPostProvider);
  }

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    try {
      await f();
      _refresh();
      if (mounted && done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, blogErrText(e), error: true);
    }
  }

  Future<void> _open(BlogPost? p) async {
    final saved = await Navigator.of(context).push<BlogPost>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => BlogEditorPage(initial: p)));
    if (saved != null) {
      _refresh();
      if (mounted) toast(context, saved.effectiveStatus == 'published' ? 'نُشر على المدونة' : saved.effectiveStatus == 'scheduled' ? 'جُدول للنشر في ${_fmt(saved.publishedAt)}' : 'حُفظ كمسودة');
    }
  }

  Future<void> _delete(BlogPost p) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('حذف «${p.title}»؟'), content: const Text('يُحذف المنشور نهائياً من المدونة ولا يمكن التراجع.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), FilledButton(key: const Key('blog-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))]));
    if (ok != true) return;
    await _run(() => ref.read(apiClientProvider).adminBlogDelete(p.id), done: 'حُذف المنشور');
  }

  Future<void> _schedule(BlogPost p) async {
    final at = await pickDateTime(context, initial: p.publishedAt);
    if (at == null) return;
    await _run(() => ref.read(apiClientProvider).adminBlogPublish(p.id, at: at), done: at.isAfter(DateTime.now()) ? 'جُدول للنشر في ${_fmt(at)}' : 'نُشر');
  }

  Future<void> _preview(BlogPost p) async {
    try {
      final url = await ref.read(apiClientProvider).adminBlogPreviewLink(p.id);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) toast(context, blogErrText(e), error: true);
    }
  }

  Future<void> _copyLink(BlogPost p) async {
    await Clipboard.setData(ClipboardData(text: p.url));
    if (mounted) toast(context, 'نُسخ الرابط');
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminBlogProvider(_key));
    final api = ref.read(apiClientProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(key: const Key('blog-new'), onPressed: () => _open(null), icon: const Icon(Icons.add_rounded), label: const Text('منشور جديد')),
        OutlinedButton.icon(key: const Key('blog-open-site'), onPressed: () => launchUrl(Uri.parse('${publicOrigin()}/blog'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('افتح المدونة')),
      ]),
      const SizedBox(height: 12),
      list.maybeWhen(
        data: (l) => Wrap(spacing: 8, runSpacing: 8, children: [
          _Stat(key: const Key('blog-stat-all'), label: 'الكل', value: l.all, color: Joy.text, selected: _status == 'all', onTap: () => setState(() => _status = 'all')),
          _Stat(key: const Key('blog-stat-published'), label: 'منشور', value: l.published, color: Joy.success, selected: _status == 'published', onTap: () => setState(() => _status = 'published')),
          _Stat(key: const Key('blog-stat-draft'), label: 'مسودة', value: l.draft, color: Joy.textMuted, selected: _status == 'draft', onTap: () => setState(() => _status = 'draft')),
          _Stat(key: const Key('blog-stat-scheduled'), label: 'مجدول', value: l.scheduled, color: Joy.warning, selected: _status == 'scheduled', onTap: () => setState(() => _status = 'scheduled')),
          _Stat(key: const Key('blog-stat-views'), label: 'مشاهدة', value: l.views, color: Joy.primary),
        ]),
        orElse: () => const SizedBox.shrink(),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('blog-search'),
        controller: _search,
        decoration: InputDecoration(hintText: 'ابحث في العناوين والنصوص', prefixIcon: const Icon(Icons.search_rounded, color: Joy.textMuted), suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _search.clear(); setState(() => _q = ''); })),
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), () { if (mounted) setState(() => _q = v.trim()); });
        },
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, l) in const [('', 'كل الأنواع'), ('update', 'تحديثات'), ('news', 'أخبار'), ('post', 'تدوينات')])
          ChoiceChip(key: Key('blog-kind-${k.isEmpty ? 'all' : k}'), label: Text(l, style: TextStyle(color: _kind == k ? Joy.primaryOn : Joy.text)), selected: _kind == k, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setState(() => _kind = k)),
      ]),
      const SizedBox(height: 12),
      list.when(
        data: (l) => l.posts.isEmpty
            ? const EmptyState(icon: Icons.newspaper_outlined, title: 'لا منشورات هنا', subtitle: 'غيّر المرشّح أو أنشئ منشوراً جديداً.')
            : JoyCard(padding: EdgeInsets.zero, child: Column(children: [
                for (final (i, p) in l.posts.indexed)
                  ListRow(
                    key: Key('blog-row-${p.id}'),
                    onTap: () => _open(p),
                    leading: p.coverUrl != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(thumbUrl(p.coverUrl!), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _KindBox(p.kind)))
                        : _KindBox(p.kind),
                    title: Row(children: [
                      if (p.pinned) const Padding(padding: EdgeInsetsDirectional.only(end: 4), child: Icon(Icons.push_pin_rounded, size: 14, color: Joy.primary)),
                      Expanded(child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    subtitle: Row(children: [
                      _StatusChip(p.effectiveStatus),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${p.kindLabel} · ${p.effectiveStatus == 'draft' ? 'عُدّل ${timeAgo(p.updatedAt)}' : _fmtDay(p.publishedAt)} · ${p.views} مشاهدة', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    trailing: PopupMenuButton<String>(
                      key: Key('blog-menu-${p.id}'),
                      tooltip: 'إجراءات',
                      onSelected: (a) async {
                        switch (a) {
                          case 'edit': await _open(p);
                          case 'publish': await _run(() => api.adminBlogPublish(p.id), done: 'نُشر على المدونة');
                          case 'unpublish': await _run(() => api.adminBlogUnpublish(p.id), done: 'أُعيد إلى المسودات');
                          case 'schedule': await _schedule(p);
                          case 'preview': await _preview(p);
                          case 'pin': await _run(() => api.adminBlogPin(p.id, pinned: !p.pinned), done: p.pinned ? 'أُلغي التثبيت' : 'ثُبّت في أعلى المدونة');
                          case 'copy': await _copyLink(p);
                          case 'duplicate': await _run(() => api.adminBlogDuplicate(p.id), done: 'أُنشئت نسخة كمسودة');
                          case 'delete': await _delete(p);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
                        if (p.effectiveStatus == 'published') const PopupMenuItem(value: 'unpublish', child: ListTile(dense: true, leading: Icon(Icons.unpublished_outlined), title: Text('إلغاء النشر'))) else const PopupMenuItem(value: 'publish', child: ListTile(dense: true, leading: Icon(Icons.publish_rounded), title: Text('نشر الآن'))),
                        const PopupMenuItem(value: 'schedule', child: ListTile(dense: true, leading: Icon(Icons.schedule_rounded), title: Text('جدولة النشر'))),
                        const PopupMenuItem(value: 'preview', child: ListTile(dense: true, leading: Icon(Icons.visibility_outlined), title: Text('معاينة على الموقع'))),
                        PopupMenuItem(value: 'pin', child: ListTile(dense: true, leading: const Icon(Icons.push_pin_outlined), title: Text(p.pinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'))),
                        const PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.link_rounded), title: Text('نسخ الرابط'))),
                        const PopupMenuItem(value: 'duplicate', child: ListTile(dense: true, leading: Icon(Icons.copy_all_outlined), title: Text('نسخ كمسودة'))),
                        const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline_rounded, color: Joy.danger), title: Text('حذف', style: TextStyle(color: Joy.danger)))),
                      ],
                    ),
                    divider: i < l.posts.length - 1,
                  ),
              ])),
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: _refresh),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  const _Stat({super.key, required this.label, required this.value, required this.color, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: selected ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? Joy.primary : Colors.transparent)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
          ]),
        ),
      );
}

class _KindBox extends StatelessWidget {
  final String kind;
  const _KindBox(this.kind);
  @override
  Widget build(BuildContext context) => Container(width: 48, height: 48, decoration: BoxDecoration(color: _kindColor(kind).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(_kindIcon(kind), color: _kindColor(kind)));
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) { 'published' => ('منشور', Joy.success), 'scheduled' => ('مجدول', Joy.warning), _ => ('مسودة', Joy.textMuted) };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)));
  }
}

/// محرر منشور المدونة.
class BlogEditorPage extends ConsumerStatefulWidget {
  final BlogPost? initial;
  const BlogEditorPage({super.key, this.initial});
  @override
  ConsumerState<BlogEditorPage> createState() => _BlogEditorPageState();
}

class _BlogEditorPageState extends ConsumerState<BlogEditorPage> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _summary = TextEditingController(text: widget.initial?.summary ?? '');
  late final _body = TextEditingController(text: widget.initial?.body ?? '');
  late final _slug = TextEditingController(text: widget.initial?.slug ?? '');
  late final _tags = TextEditingController(text: widget.initial?.tags.join('، ') ?? '');
  final _bodyFocus = FocusNode();
  late String _kind = widget.initial?.kind ?? 'update';
  late bool _pinned = widget.initial?.pinned ?? false;
  late String? _cover = widget.initial?.coverUrl;
  late DateTime? _publishedAt = widget.initial?.publishedAt;
  var _preview = false, _saving = false, _dirty = false, _uploading = false;

  BlogPost? get _p => widget.initial;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _summary, _body, _slug, _tags]) {
      c.addListener(_touch);
    }
  }

  void _touch() => setState(() => _dirty = true);

  @override
  void dispose() {
    for (final c in [_title, _summary, _body, _slug, _tags]) {
      c.dispose();
    }
    _bodyFocus.dispose();
    super.dispose();
  }

  List<String> get _tagList => _tags.text.split(RegExp(r'[،,]')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  Map<String, dynamic> _fields() => {
        'title': _title.text.trim(),
        'kind': _kind,
        'summary': _summary.text.trim(),
        'body': _body.text,
        'coverUrl': _cover,
        'tags': _tagList,
        'pinned': _pinned,
        if (_slug.text.trim().isNotEmpty) 'slug': _slug.text.trim().toLowerCase(),
      };

  /// يحفظ بالحالة المطلوبة: مسودة، نشر الآن، أو جدولة بتاريخ.
  Future<void> _save({required String status, DateTime? at}) async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب عنواناً للمنشور', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    try {
      final fields = {..._fields(), 'status': status, if (at != null) 'publishedAt': at.toUtc().toIso8601String() else if (status == 'published' && _p?.status == 'published' && _publishedAt != null) 'publishedAt': _publishedAt!.toUtc().toIso8601String()};
      final saved = _p == null ? await api.adminBlogCreate(fields) : await api.adminBlogUpdate(_p!.id, fields);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, blogErrText(e), error: true);
      }
    }
  }

  Future<void> _schedule() async {
    final at = await pickDateTime(context, initial: _publishedAt);
    if (at == null) return;
    await _save(status: 'published', at: at);
  }

  Future<void> _uploadCover() async {
    final img = await pickImage();
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      setState(() { _cover = up.url; _dirty = true; });
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _coverByUrl() async {
    final c = TextEditingController(text: _cover ?? 'https://');
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('رابط صورة الغلاف'), content: TextField(key: const Key('blog-cover-url-field'), controller: c, autofocus: true, keyboardType: TextInputType.url, textDirection: TextDirection.ltr), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), FilledButton(key: const Key('blog-cover-url-ok'), onPressed: () => Navigator.pop(d, true), child: const Text('حفظ'))]));
    if (ok != true) return;
    final u = c.text.trim();
    setState(() { _cover = u.isEmpty || u == 'https://' ? null : u; _dirty = true; });
  }

  Future<void> _insertImage() async {
    final img = await pickImage();
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      _body.value = MarkupEdit.insert(_body.value, '\n![](${up.url})\n');
      _bodyFocus.requestFocus();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _close() async {
    if (_dirty && !_saving) {
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('تجاهل التغييرات؟'), content: const Text('لم تُحفظ تعديلاتك بعد.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('متابعة التحرير')), FilledButton(key: const Key('blog-discard'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('تجاهل'))]));
      if (ok != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _previewOnSite() async {
    if (_p == null) return;
    try {
      final url = await ref.read(apiClientProvider).adminBlogPreviewLink(_p!.id);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) toast(context, blogErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final status = p?.effectiveStatus ?? 'draft';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(
          leading: IconButton(key: const Key('blog-close'), tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded), onPressed: _close),
          title: Text(p == null ? 'منشور جديد' : 'تعديل المنشور', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: AppTheme.bodyFont)),
          actions: [
            if (p != null) IconButton(key: const Key('blog-preview-site'), tooltip: 'معاينة على الموقع', icon: const Icon(Icons.open_in_new_rounded), onPressed: _previewOnSite),
            IconButton(key: const Key('blog-preview'), tooltip: _preview ? 'عودة للتحرير' : 'معاينة', icon: Icon(_preview ? Icons.edit_note_rounded : Icons.visibility_outlined, color: _preview ? Joy.primary : null), onPressed: () => setState(() => _preview = !_preview)),
          ],
        ),
        body: Column(children: [
          Expanded(child: _preview ? _previewPane() : _form(status)),
          _actions(status),
          MarkupToolbar(
            controller: _body,
            focusNode: _bodyFocus,
            enabled: !_preview && !_saving,
            extra: [IconButton(key: const Key('tool-image'), tooltip: 'إدراج صورة', icon: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_outlined), color: Joy.text, onPressed: _preview || _uploading ? null : _insertImage, visualDensity: VisualDensity.compact)],
            trailing: Text('${_body.text.characters.length} حرف', style: const TextStyle(fontSize: 11, color: Joy.textMuted)),
          ),
        ]),
      ),
    );
  }

  Widget _actions(String status) {
    final busy = _saving;
    return Container(
      decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Expanded(child: FilledButton.icon(key: const Key('blog-publish-now'), onPressed: busy ? null : () => _save(status: 'published'), icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.publish_rounded, size: 18), label: Text(status == 'published' ? 'حفظ ونشر' : 'نشر الآن'))),
        const SizedBox(width: 8),
        OutlinedButton.icon(key: const Key('blog-schedule'), onPressed: busy ? null : _schedule, icon: const Icon(Icons.schedule_rounded, size: 18), label: const Text('جدولة')),
        const SizedBox(width: 8),
        TextButton(key: const Key('blog-save-draft'), onPressed: busy ? null : () => _save(status: 'draft'), child: const Text('مسودة')),
      ]),
    );
  }

  Widget _form(String status) {
    final p = _p;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 24), children: [
      if (p != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _StatusChip(status),
            const SizedBox(width: 8),
            Expanded(child: Text(switch (status) { 'published' => 'منشور منذ ${_fmt(p.publishedAt)} · ${p.views} مشاهدة', 'scheduled' => 'مجدول للنشر في ${_fmt(p.publishedAt)}', _ => 'مسودة · آخر تعديل ${timeAgo(p.updatedAt)}' }, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted))),
            TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: p.url)); if (mounted) toast(context, 'نُسخ الرابط'); }, child: const Text('نسخ الرابط')),
          ]),
        ),
      Wrap(spacing: 8, children: [
        for (final e in blogKinds.entries)
          ChoiceChip(key: Key('blog-kind-${e.key}'), avatar: Icon(_kindIcon(e.key), size: 18, color: _kind == e.key ? Joy.primaryOn : Joy.textMuted), label: Text(e.value, style: TextStyle(color: _kind == e.key ? Joy.primaryOn : Joy.text)), selected: _kind == e.key, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setState(() { _kind = e.key; _dirty = true; })),
      ]),
      const SizedBox(height: 8),
      TextField(
        key: const Key('blog-title'),
        controller: _title,
        maxLength: 160,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 23, fontWeight: FontWeight.w700, height: 1.3),
        decoration: const InputDecoration(hintText: 'العنوان', hintStyle: TextStyle(fontFamily: AppTheme.displayFont, fontSize: 23, fontWeight: FontWeight.w700, color: Joy.control), filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 6)),
      ),
      const Divider(height: 1),
      const SizedBox(height: 10),
      TextField(key: const Key('blog-summary'), controller: _summary, maxLength: 300, maxLines: 2, minLines: 1, decoration: const InputDecoration(labelText: 'الملخص', hintText: 'سطر يظهر في القائمة وفي معاينة الرابط', alignLabelWithHint: true)),
      const SizedBox(height: 10),
      _coverField(),
      const SizedBox(height: 12),
      TextField(
        key: const Key('blog-body'),
        controller: _body,
        focusNode: _bodyFocus,
        maxLines: null,
        minLines: 10,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 16, height: 1.65, fontWeight: FontWeight.w500),
        decoration: const InputDecoration(hintText: 'نص المنشور…\nاستخدم الشريط بالأسفل للعناوين والنقاط والروابط والصور.', hintStyle: TextStyle(color: Joy.control, fontSize: 16, height: 1.65, fontWeight: FontWeight.w500), alignLabelWithHint: true, contentPadding: EdgeInsets.all(14)),
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        key: const Key('blog-advanced'),
        tilePadding: EdgeInsets.zero,
        title: const Text('خيارات متقدمة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        subtitle: Text('معرّف الرابط${_slug.text.trim().isEmpty ? '' : ': ${_slug.text.trim()}'} · الوسوم${_tagList.isEmpty ? '' : ': ${_tagList.length}'}${_pinned ? ' · مثبّت' : ''}', style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          TextField(key: const Key('blog-slug'), controller: _slug, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'معرّف الرابط (اختياري)', hintText: 'يُولَّد تلقائياً من العنوان', helperText: p == null ? 'حروف لاتينية صغيرة وأرقام وشرطات، مثل ramadan-hours' : 'تغييره يغيّر رابط المنشور المنشور', prefixText: 'naslife.app/blog/ ')),
          const SizedBox(height: 10),
          TextField(key: const Key('blog-tags'), controller: _tags, decoration: const InputDecoration(labelText: 'الوسوم', hintText: 'افصل بينها بفاصلة: رمضان، الدمام، عروض')),
          SwitchListTile(key: const Key('blog-pinned'), contentPadding: EdgeInsets.zero, value: _pinned, onChanged: (v) => setState(() { _pinned = v; _dirty = true; }), title: const Text('تثبيت في أعلى المدونة'), subtitle: const Text('يظهر قبل كل المنشورات')),
          if (p != null && p.publishedAt != null)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_outlined, color: Joy.textMuted), title: const Text('تاريخ النشر'), subtitle: Text(_fmt(_publishedAt)), trailing: TextButton(key: const Key('blog-change-date'), onPressed: () async { final at = await pickDateTime(context, initial: _publishedAt); if (at != null) setState(() { _publishedAt = at; _dirty = true; }); }, child: const Text('تغيير'))),
        ],
      ),
    ]);
  }

  Widget _coverField() {
    final c = _cover;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Joy.line), borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.image_outlined, size: 18, color: Joy.textMuted),
          const SizedBox(width: 6),
          const Text('صورة الغلاف', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          if (c != null) TextButton(key: const Key('blog-cover-remove'), onPressed: () => setState(() { _cover = null; _dirty = true; }), child: const Text('إزالة', style: TextStyle(color: Joy.danger))),
        ]),
        if (c != null)
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(mediaUrl(c), height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 60, alignment: Alignment.center, color: Joy.surface2, child: Text(c, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: Joy.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis))))
        else
          Row(children: [
            OutlinedButton.icon(key: const Key('blog-cover-upload'), onPressed: _uploading ? null : _uploadCover, icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_rounded, size: 18), label: const Text('رفع صورة')),
            const SizedBox(width: 8),
            TextButton.icon(key: const Key('blog-cover-url'), onPressed: _coverByUrl, icon: const Icon(Icons.link_rounded, size: 18), label: const Text('رابط صورة')),
          ]),
      ]),
    );
  }

  Widget _previewPane() {
    final composed = _body.text;
    return SingleChildScrollView(
      key: const Key('blog-preview-pane'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: JoyCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_cover != null) ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: Image.network(mediaUrl(_cover!), height: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), decoration: BoxDecoration(color: _kindColor(_kind).withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(blogKinds[_kind] ?? _kind, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kindColor(_kind)))),
                const SizedBox(width: 8),
                Text(_fmt(_publishedAt ?? DateTime.now()), style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
              ]),
              const SizedBox(height: 8),
              Text(_title.text.trim().isEmpty ? 'بلا عنوان' : _title.text.trim(), style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 24, fontWeight: FontWeight.w700, height: 1.3)),
              if (_summary.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_summary.text.trim(), style: const TextStyle(color: Joy.textMuted, fontSize: 14))),
              if (_tagList.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [for (final t in _tagList) Chip(label: Text(t, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact)])),
              const SizedBox(height: 12),
              composed.trim().isEmpty ? const Text('لا نص بعد', style: TextStyle(color: Joy.textMuted)) : PostMarkup(composed, fontSize: 15.5),
            ]),
          ),
        ]),
      ),
    );
  }
}
