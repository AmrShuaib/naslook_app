import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/admin_api.dart';
import '../../api/biz_models.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/share/legal_links.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart' show openBusiness;
import '../business/owner/business_dashboard_page.dart';
import 'admin_shell.dart';

/// الدوائر التجارية في الإدارة: قسمان، «الدوائر» (القائمة وطلبات الملكية والتعيين) و«التوثيق» (طابور السجل التجاري
/// ووثيقة العمل الحر). القسم المفتوح في [adminBizSegmentProvider] حتى تفتحه بطاقة النظرة العامة مباشرة.
class AdminBizPage extends ConsumerStatefulWidget {
  const AdminBizPage({super.key});
  @override
  ConsumerState<AdminBizPage> createState() => _AdminBizPageState();
}

class _AdminBizPageState extends ConsumerState<AdminBizPage> {
  String filter = 'all';
  String q = '';
  @override
  Widget build(BuildContext context) {
    final segment = ref.watch(adminBizSegmentProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: SegmentedButton<String>(
          key: const Key('biz-segments'),
          segments: const [
            ButtonSegment(value: 'list', icon: Icon(Icons.storefront_outlined, size: 18), label: Text('الدوائر', key: Key('biz-seg-list'))),
            ButtonSegment(value: 'verifications', icon: Icon(Icons.verified_outlined, size: 18), label: Text('التوثيق', key: Key('biz-seg-verifications'))),
          ],
          selected: {segment == 'verifications' ? 'verifications' : 'list'},
          showSelectedIcon: false,
          onSelectionChanged: (s) => ref.read(adminBizSegmentProvider.notifier).state = s.first,
        ),
      ),
      Expanded(child: segment == 'verifications' ? const _VerificationQueue() : _list()),
    ]);
  }

  Widget _list() {
    final list = ref.watch(adminBizProvider);
    final claims = ref.watch(adminClaimsProvider);
    return list.when(
      data: (all) {
        var items = all.where((b) => switch (filter) { 'active' => b.active, 'inactive' => !b.active, 'unowned' => b.ownerId == null, 'owned' => b.ownerId != null, _ => true }).toList();
        if (q.isNotEmpty) items = items.where((b) => b.name.contains(q) || b.latin.toLowerCase().contains(q.toLowerCase()) || b.id.contains(q)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
          claims.when(
            data: (cl) => cl.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('طلبات الملكية · ${cl.length}'),
              for (final c in cl)
                JoyCard(child: Row(children: [
                  if (c['user'] is Map) ProfileAvatar(person: Person.fromJson(asMap(c['user'])), size: 40),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${asMap(c['user'])['nickname'] ?? ''} يطلب ملكية ${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)), if ((c['note'] ?? '').toString().isNotEmpty) Text(c['note'].toString(), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))])),
                  IconButton(tooltip: 'قبول', onPressed: () => _decide(c, true), icon: const Icon(Icons.check_circle_rounded, color: Joy.success)),
                  IconButton(tooltip: 'رفض', onPressed: () => _decide(c, false), icon: const Icon(Icons.cancel_rounded, color: Joy.danger)),
                ])),
              const SizedBox(height: 8),
            ]),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(hintText: 'ابحث باسم الدائرة', prefixIcon: Icon(Icons.search_rounded, color: Joy.textMuted), isDense: true)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final (k, l) in [('all', 'الكل'), ('active', 'منشورة'), ('inactive', 'موقوفة'), ('owned', 'مملوكة'), ('unowned', 'بلا مالك')])
              ChoiceChip(label: Text(l, style: TextStyle(color: filter == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: filter == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => filter = k)),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'لا دوائر مطابقة'),
          for (final b in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _BizCard(b: b)),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(adminBizProvider)),
    );
  }

  Future<void> _decide(Map<String, dynamic> c, bool approve) async {
    try {
      await ref.read(apiClientProvider).adminClaimDecide(c['bizId'].toString(), asMap(c['user'])['id'].toString(), approve: approve);
      invalidateAdmin(ref);
      if (mounted) toast(context, approve ? 'مُنحت الملكية' : 'رُفض الطلب');
    } catch (e) {
      if (mounted) toast(context, adminErrText(e), error: true);
    }
  }
}

class _BizCard extends ConsumerWidget {
  final AdminBiz b;
  const _BizCard({required this.b});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = BizCategory.of(b.category);
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(cat.icon, color: Joy.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              if (b.verified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified_rounded, size: 16, color: Joy.primary)),
              if (!b.active) Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(999)), child: const Text('موقوفة', style: TextStyle(color: Joy.accent, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            Text('${cat.label}${b.sector.isNotEmpty ? ' · ${b.sector}' : ''} · ${b.owner != null ? 'المالك ${b.owner!.nickname}' : 'بلا مالك'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text('${b.orders} طلب · ${money(b.revenue)} · ${b.followers} متابع · ${b.items} عنصر · ${b.views} مشاهدة', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: b.id))), icon: const Icon(Icons.dashboard_customize_outlined, size: 18), label: const Text('لوحة التحكم')),
          OutlinedButton.icon(onPressed: () => openBusiness(context, b.id), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('الصفحة')),
          FilledButton.tonalIcon(onPressed: () => _update(context, ref, verified: !b.verified), icon: Icon(b.verified ? Icons.remove_circle_outline_rounded : Icons.verified_outlined, size: 18), label: Text(b.verified ? 'سحب التوثيق' : 'توثيق')),
          FilledButton.tonalIcon(onPressed: () => _update(context, ref, active: !b.active), icon: Icon(b.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, size: 18), label: Text(b.active ? 'إيقاف' : 'نشر')),
          FilledButton.tonalIcon(onPressed: () => _owner(context, ref), icon: const Icon(Icons.person_pin_circle_outlined, size: 18), label: Text(b.ownerId == null ? 'تعيين مالك' : 'تغيير المالك')),
        ]),
      ]),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, {bool? verified, bool? active}) async {
    try {
      await ref.read(apiClientProvider).adminBizUpdate(b.id, verified: verified, active: active);
      invalidateAdmin(ref);
      invalidateBizAll(ref, b.id);
      if (context.mounted) toast(context, 'تم');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }

  Future<void> _owner(BuildContext context, WidgetRef ref) async {
    final handle = await askText(context, title: 'مالك ${b.name}', hint: 'النك نيم أو المعرّف SA… (اتركه فارغاً لإزالة المالك)', confirm: 'حفظ', maxLines: 1, initial: b.ownerId);
    if (handle == null) return;
    var id = handle.trim().toUpperCase();
    if (id.isNotEmpty && !RegExp(r'^[A-Z]{2}\d{7}$').hasMatch(id)) {
      try { id = (await ref.read(apiClientProvider).userByHandle(handle.trim().toLowerCase())).id; } catch (_) { if (context.mounted) toast(context, 'لم نجد هذا المستخدم', error: true); return; }
    }
    try {
      await ref.read(apiClientProvider).adminBizUpdate(b.id, ownerId: id.isEmpty ? null : id, clearOwner: id.isEmpty);
      invalidateAdmin(ref);
      invalidateBizAll(ref, b.id);
      if (context.mounted) toast(context, id.isEmpty ? 'أُزيل المالك' : 'عُيّن المالك');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}

// ------------------------------------------------------------------ طابور التوثيق

/// اسم فئة الدائرة: من [BizCategory] إن عرفتها، وإلا أسماء فئات التسجيل الجديدة (متجر، خدمات، صالون، عيادة، ترفيه، أخرى).
/// مكرّرة هنا مؤقتاً حتى تُضاف الفئات إلى biz_models.dart مع حزمة التسجيل؛ عندها يكفي `BizCategory.of(key).label`.
String adminBizCategoryLabel(String key) {
  final c = BizCategory.of(key);
  if (c.key == key) return c.label;
  return const {'shop': 'متجر', 'services': 'خدمات وورش', 'salon': 'صالون وتجميل', 'clinic': 'عيادة', 'entertainment': 'ترفيه', 'other': 'أخرى'}[key] ?? key;
}

/// فتح رابط خارجي من الإدارة (الاستعلام الرسمي): البديل الاختباري نفسه الذي تستخدمه صفحات الخصوصية والدعم.
Future<void> _openExternal(Uri u) async {
  final o = LegalLinks.openOverride;
  if (o != null) return o(u);
  await launchUrl(u, mode: LaunchMode.externalApplication);
}

/// قائمة طلبات التوثيق بحسب الحالة: بانتظار القرار افتراضياً، وفلاتر للموثّقة والمرفوضة والكل.
class _VerificationQueue extends ConsumerStatefulWidget {
  const _VerificationQueue();
  @override
  ConsumerState<_VerificationQueue> createState() => _VerificationQueueState();
}

class _VerificationQueueState extends ConsumerState<_VerificationQueue> {
  String status = 'pending';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminBizVerificationsProvider(status));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      const Text('توثيق الدوائر: طابق رقم السجل التجاري أو وثيقة العمل الحر مع المستند عبر الاستعلام الرسمي، ثم «مطابق» أو «مرفوض» بسبب يصل المالك. البيع والحجز وربط الدفع تُفتح بعد التوثيق فقط.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final (k, l) in [('pending', 'بانتظار القرار'), ('approved', 'موثّقة'), ('rejected', 'مرفوضة'), ('all', 'الكل')])
          ChoiceChip(key: Key('verif-filter-$k'), label: Text(l, style: TextStyle(color: status == k ? Joy.primaryOn : Joy.text, fontSize: 12.5)), selected: status == k, showCheckmark: false, selectedColor: Joy.primary, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => status = k)),
      ]),
      const SizedBox(height: 10),
      ...list.when(
        data: (rows) => rows.isEmpty
            ? [EmptyState(icon: Icons.verified_outlined, title: status == 'pending' ? 'لا طلبات توثيق بانتظار القرار' : 'لا طلبات توثيق هنا')]
            : [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: _VerificationCard(r: r))],
        loading: () => const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [ErrorState(e, onRetry: () => ref.invalidate(adminBizVerificationsProvider(status)))],
      ),
    ]);
  }
}

/// بطاقة طلب توثيق: الدائرة وفئتها وحضورها ومالكها، نوع الكيان ورقمه (يُنسخ)، مصغّرة المستند (تفتح كاملة)،
/// زر الاستعلام الرسمي، وقرار «مطابق»/«مرفوض» للمعلّقة.
class _VerificationCard extends ConsumerWidget {
  final VerificationRow r;
  const _VerificationCard({required this.r});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = BizCategory.of(r.category);
    final pending = r.status == 'pending';
    final statusColor = switch (r.status) { 'approved' => Joy.success, 'rejected' => Joy.danger, _ => Joy.warning };
    final doc = r.docUrl;
    return JoyCard(
      key: Key('verif-row-${r.bizId}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: r.logoUrl == null
                  ? Container(color: Joy.primarySoft, child: Icon(cat.icon, color: Joy.primary))
                  : Image.network(thumbUrl(r.logoUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Joy.primarySoft, child: Icon(cat.icon, color: Joy.primary))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
              Container(margin: const EdgeInsetsDirectional.only(start: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)), child: Text(r.statusLabel, key: Key('verif-status-${r.bizId}'), style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            Text('${adminBizCategoryLabel(r.category)} · ${r.presenceLabel} · المالك ${r.owner?.nickname ?? r.ownerId ?? '—'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            if (r.submittedAt != null) Text('قُدّم ${timeAgo(r.submittedAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(r.isCr ? Icons.badge_outlined : Icons.workspace_premium_outlined, size: 18, color: Joy.textMuted),
          const SizedBox(width: 6),
          Expanded(child: SelectableText('${r.entityLabel}: ${r.entityNumber}', key: Key('verif-entity-${r.bizId}'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          IconButton(
            key: Key('verif-copy-${r.bizId}'),
            tooltip: 'نسخ الرقم',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.entityNumber));
              if (context.mounted) toast(context, 'نُسخ الرقم');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ]),
        if (doc != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            GestureDetector(
              key: Key('verif-doc-${r.bizId}'),
              onTap: () => _viewDoc(context, doc),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 96, height: 72, child: Image.network(thumbUrl(doc), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Joy.surface2, child: const Icon(Icons.description_outlined, color: Joy.textMuted)))),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('مستند التوثيق: المس المصغّرة لعرضه كاملاً وقارن الاسم والرقم مع الاستعلام الرسمي', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.4))),
          ]),
        ] else
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('بلا مستند مرفق', style: TextStyle(color: Joy.danger, fontSize: 12.5))),
        if (r.status == 'rejected' && r.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('سبب الرفض: ${r.reason}', key: Key('verif-reason-${r.bizId}'), style: const TextStyle(color: Joy.danger, fontSize: 12.5))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (r.lookupUrl != null)
            OutlinedButton.icon(key: Key('verif-lookup-${r.bizId}'), onPressed: () => _openExternal(Uri.parse(r.lookupUrl!)), icon: const Icon(Icons.travel_explore_rounded, size: 18), label: const Text('استعلام رسمي')),
          OutlinedButton.icon(onPressed: () => openBusiness(context, r.bizId), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('الصفحة')),
          if (pending) ...[
            FilledButton.icon(key: Key('verif-approve-${r.bizId}'), onPressed: () => _decide(context, ref, approve: true), icon: const Icon(Icons.verified_rounded, size: 18), label: const Text('مطابق')),
            FilledButton.tonalIcon(key: Key('verif-reject-${r.bizId}'), onPressed: () => _decide(context, ref, approve: false), icon: const Icon(Icons.cancel_outlined, size: 18), label: const Text('مرفوض')),
          ],
        ]),
      ]),
    );
  }

  /// المستند كاملاً بتكبير؛ [doc] مسار الوسيط كما أرسله الخادم ويُحوَّل إلى رابط كامل هنا (يعمل على iOS أيضاً).
  void _viewDoc(BuildContext context, String doc) {
    showDialog<void>(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            key: const Key('verif-doc-view'),
            minScale: .5,
            maxScale: 5,
            child: Image.network(mediaUrl(doc), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(32), child: Text('تعذّر تحميل المستند', style: TextStyle(color: Joy.danger)))),
          ),
          PositionedDirectional(top: 4, end: 4, child: IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded))),
        ]),
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, {required bool approve}) async {
    String? reason;
    if (!approve) {
      // الرفض يحتاج سبباً يصل المالك في الإشعار (الخادم يفرض 3..300 حرفاً)
      final t = await askText(context, title: 'سبب رفض توثيق ${r.title}', hint: 'مثال: رقم السجل لا يطابق اسم المنشأة', confirm: 'رفض');
      if (t == null) return;
      reason = t.trim();
      if (reason.length < 3) { if (context.mounted) toast(context, 'اكتب سبباً من 3 أحرف على الأقل', error: true); return; }
      if (reason.length > 300) { if (context.mounted) toast(context, 'السبب أطول من 300 حرف', error: true); return; }
    }
    try {
      await ref.read(apiClientProvider).decideVerification(r.bizId, approve: approve, reason: reason);
      invalidateAdmin(ref);
      invalidateBizAll(ref, r.bizId);
      if (context.mounted) toast(context, approve ? 'وُثّقت الدائرة وأُبلغ المالك' : 'رُفض التوثيق وأُبلغ المالك بالسبب');
    } catch (e) {
      final code = e is ApiException ? (e.body?['error']?.toString() ?? '') : '';
      if (context.mounted) toast(context, code == 'already-approved' ? 'هذه الدائرة موثّقة أصلاً' : code == 'reason-required' ? 'الرفض يحتاج سبباً' : adminErrText(e), error: true);
    }
  }
}
