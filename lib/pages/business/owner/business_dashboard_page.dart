import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/commerce_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/location.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import '../../posts/post_stats.dart';
import '../business_page.dart' show openBusiness, BizLogo, Stars, dayLabel, shortDate;
import 'business_editor.dart';
import 'dashboard_catalog.dart';
import 'dashboard_jobs.dart';
import 'dashboard_orders.dart';
import 'dashboard_offers.dart';
import 'dashboard_posts.dart';
import 'dashboard_reviews_team.dart';
import 'verify_circle_page.dart';

/// لوحة تحكم صاحب النشاط: نظرة عامة، الطلبات، الكتالوج، الأخبار والعروض، التقييمات، الفريق، الملف.
class BusinessDashboardPage extends ConsumerWidget {
  final String id;
  final Biz? initial;
  final int initialTab;
  const BusinessDashboardPage({super.key, required this.id, this.initial, this.initialTab = 0});

  /// فهرس تبويب «التوظيف» (الأخير) للروابط العميقة من الإشعارات.
  static const jobsTab = 8;

  /// فهرس التبويب لمفتاح الخطوة التالية في الاكتمال (profile|catalog|posts|offers)؛ null لما ليس تبويباً (verify).
  static int? tabIndexFor(String tab) => switch (tab) { 'catalog' => 2, 'offers' => 3, 'posts' => 4, 'profile' => 7, _ => null };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(bizDetailProvider(id));
    final biz = detail.valueOrNull ?? initial;
    final tabs = [
      ('نظرة عامة', Icons.insights_outlined),
      ('الطلبات', Icons.receipt_long_outlined),
      (biz?.category.catalogTitle ?? 'الكتالوج', Icons.inventory_2_outlined),
      ('العروض', Icons.local_offer_outlined),
      ('التحديثات', Icons.campaign_outlined),
      ('التقييمات', Icons.star_outline_rounded),
      ('الفريق', Icons.groups_outlined),
      ('الملف', Icons.badge_outlined),
      ('التوظيف', Icons.work_outline_rounded),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialTab.clamp(0, tabs.length - 1),
      child: Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(
          title: Row(children: [
            if (biz != null) BizLogo(biz: biz, size: 32),
            const SizedBox(width: 8),
            Expanded(child: Text(biz?.title ?? 'لوحة التحكم', overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            IconButton(tooltip: 'الصفحة العامة', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openBusiness(context, id)),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Joy.primary,
            unselectedLabelColor: Joy.textMuted,
            indicatorColor: Joy.primary,
            labelStyle: const TextStyle(fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w700, fontSize: 13.5),
            unselectedLabelStyle: const TextStyle(fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w500, fontSize: 13.5),
            tabs: [for (final (label, icon) in tabs) Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17), const SizedBox(width: 5), Text(label)]))],
          ),
        ),
        body: biz == null
            ? detail.when(data: (_) => const SizedBox(), loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizDetailProvider(id))))
            : !biz.canOperate
                ? const EmptyState(icon: Icons.lock_outline_rounded, title: 'ليست لديك صلاحية على هذه الدائرة')
                : TabBarView(children: [
                    OverviewTab(biz: biz),
                    OrdersTab(biz: biz),
                    CatalogTab(biz: biz),
                    OffersTab(biz: biz),
                    PostsTab(biz: biz),
                    ReviewsTab(biz: biz),
                    TeamTab(biz: biz),
                    ProfileTab(biz: biz),
                    JobsTab(biz: biz),
                  ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ نظرة عامة

String _itemNoun(BizCategory c) => switch (c) { BizCategory.brand => 'منتج', BizCategory.cinema => 'فيلم', BizCategory.hotel => 'غرفة', BizCategory.carRental => 'سيارة', BizCategory.hospital => 'عيادة', BizCategory.airport => 'مرفق', BizCategory.cafe => 'صنف', BizCategory.restaurant => 'صنف', BizCategory.company => 'خدمة', BizCategory.university => 'كلية', BizCategory.shop => 'منتج', BizCategory.services => 'خدمة', BizCategory.salon => 'خدمة', BizCategory.clinic => 'عيادة', BizCategory.entertainment => 'فعالية', BizCategory.other => 'خدمة' };

class OverviewTab extends ConsumerWidget {
  final Biz biz;
  const OverviewTab({super.key, required this.biz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(bizStatsProvider(biz.id));
    return RefreshIndicator(
      onRefresh: () async => invalidateBizAll(ref, biz.id),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        // الاكتمال أولاً: الدرجة والنسبة والخطوة التالية، فيعرف صاحب الدائرة ما ينقصه قبل الأرقام
        _CompletenessCard(biz: biz),
        if (biz.hereActive)
          Container(
            key: const Key('here-active'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.location_on_rounded, color: Joy.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('أنت هنا حتى ${clockLabel(biz.here!.until)}', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w600, fontSize: 13))),
              TextButton(key: const Key('here-end-inline'), onPressed: () => _endHere(context, ref), child: const Text('إنهاء')),
            ]),
          ),
        if (!biz.active)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.pause_circle_outline_rounded, color: Joy.accent),
              const SizedBox(width: 8),
              const Expanded(child: Text('الدائرة موقوفة: لا تظهر للعامة ولا تستقبل طلبات', style: TextStyle(color: Joy.accent, fontWeight: FontWeight.w600, fontSize: 13))),
              TextButton(onPressed: () => _toggleActive(context, ref, true), child: const Text('نشر')),
            ]),
          ),
        stats.when(
          data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _Stat(label: 'إيرادات 7 أيام', value: money(s.revenueLast7), icon: Icons.payments_outlined, color: Joy.primary)),
              const SizedBox(width: 8),
              Expanded(child: _Stat(label: 'طلبات 7 أيام', value: '${s.ordersLast7}', icon: Icons.shopping_bag_outlined, color: Joy.accent)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _Stat(label: 'خلال 24 ساعة', value: '${s.next24h}', icon: Icons.schedule_outlined, color: Joy.warning, hint: biz.category == BizCategory.brand ? 'طلبات بموعد' : 'حجوزات قادمة')),
              const SizedBox(width: 8),
              Expanded(child: _Stat(label: 'العملاء', value: '${s.customers}', icon: Icons.people_outline_rounded, color: Joy.success)),
            ]),
            const SizedBox(height: 8),
            JoyCard(
              child: Row(children: [
                _Mini(icon: Icons.favorite_border_rounded, value: '${s.followers}', label: 'متابع'),
                _Mini(icon: Icons.star_rounded, value: s.rating == null ? '—' : s.rating!.toStringAsFixed(1), label: '${s.reviews} تقييم', warn: s.unanswered > 0 ? '${s.unanswered} بلا رد' : null),
                _Mini(icon: Icons.visibility_outlined, value: '${s.views}', label: 'مشاهدة'),
                _Mini(icon: Icons.account_balance_wallet_outlined, value: money(s.revenueTotal), label: 'الإجمالي'),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionTitle('الإيرادات · آخر 14 يوماً'),
            JoyCard(child: RevenueBars(daily: s.daily)),
            _BizPostsCard(bizId: biz.id),
            if (s.byKind.isNotEmpty || s.topItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              const SectionTitle('الأكثر مبيعاً'),
              JoyCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, t) in s.topItems.indexed)
                    ListRow(
                      leading: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: i == 0 ? Joy.sunSoft : Joy.surface2, borderRadius: BorderRadius.circular(12)), child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: i == 0 ? Joy.sunText : Joy.textMuted))),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${t.count} ${t.count == 1 ? 'طلب' : 'طلبات'}'),
                      trailing: Text(money(t.total), style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.primary)),
                      divider: i < s.topItems.length - 1,
                    ),
                  if (s.topItems.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('لا مبيعات بعد', style: TextStyle(color: Joy.textMuted))),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: SectionTitle('الطلبات')),
              Text('مؤكدة ${s.confirmed} · مستخدمة ${s.used} · ملغاة ${s.cancelled}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            ]),
          ]),
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizStatsProvider(biz.id))),
        ),
        const SizedBox(height: 4),
        const SectionTitle('إجراءات سريعة'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // «أنا هنا اليوم» للكل: المتنقلة أساساً، والثابتة حين تشارك في بازار خارج مقرها
          _Action(key: const Key('here-today'), icon: Icons.where_to_vote_outlined, label: biz.hereActive ? 'أنت هنا حتى ${clockLabel(biz.here!.until)}' : 'أنا هنا اليوم', onTap: () => showHereTodaySheet(context, biz)),
          _Action(icon: Icons.qr_code_scanner_rounded, label: 'تأكيد استلام برمز', onTap: () => checkinByCode(context, ref, biz)),
          if (biz.canManage) _Action(key: const Key('verify-entry'), icon: Icons.verified_user_outlined, label: biz.verified ? 'التوثيق ✓' : 'التوثيق', onTap: () => openVerifyCircle(context, biz.id, initial: biz)),
          if (biz.canManage) _Action(icon: Icons.add_box_outlined, label: 'إضافة ${_itemNoun(biz.category)}', onTap: () => openItemEditor(context, biz)),
          if (biz.canManage) _Action(icon: Icons.local_offer_outlined, label: 'عرض جديد', onTap: () => openOfferTemplates(context, biz, ref.read(manageOffersProvider(biz.id)).valueOrNull?.templates ?? const [])),
          if (biz.canManage) _Action(icon: Icons.edit_outlined, label: 'تعديل الملف', onTap: () => openBusinessEditor(context, biz: biz)),
          _Action(icon: Icons.open_in_new_rounded, label: 'الصفحة العامة', onTap: () => openBusiness(context, biz.id)),
        ]),
      ]),
    );
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref, bool active) async {
    try {
      await ref.read(apiClientProvider).updateBiz(biz.id, {'active': active});
      invalidateBizAll(ref, biz.id);
      if (context.mounted) toast(context, active ? 'نُشرت الدائرة' : 'أُوقفت الدائرة');
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }

  Future<void> _endHere(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiClientProvider).clearHere(biz.id);
      invalidateCompleteness(ref, biz.id);
      if (context.mounted) toast(context, 'أُنهي دبوس «هنا اليوم»');
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }
}

// ------------------------------------------------------------------ الاكتمال

/// بطاقة الاكتمال: الدرجة (منشورة/مكتملة/موثّقة/نشطة)، النسبة، الخطوة التالية بزر يفتح تبويبها، وقائمة بنود مختصرة.
/// تُخفى صامتة إن تعذّر جلبها (خادم قديم بلا المسار) حتى لا تعطّل اللوحة.
class _CompletenessCard extends ConsumerWidget {
  final Biz biz;
  const _CompletenessCard({required this.biz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(bizCompletenessProvider(biz.id)).valueOrNull;
    if (c == null) return const SizedBox.shrink();
    final k = c.checks;
    final next = c.next;
    final tierColor = switch (c.tier) { 'active' => Joy.success, 'verified' => Joy.primary, 'complete' => Joy.accent, _ => Joy.textMuted };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      JoyCard(
        key: const Key('completeness-card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              key: const Key('completeness-tier'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: tierColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
              child: Text(c.tierLabel, style: TextStyle(color: tierColor, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('اكتمال الدائرة', style: TextStyle(fontWeight: FontWeight.w700))),
            Text('${c.percent}٪', key: const Key('completeness-percent'), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: c.percent / 100, minHeight: 8, backgroundColor: Joy.surface2, color: tierColor)),
          if (!c.canSell)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(key: const Key('completeness-locked'), children: const [
                Icon(Icons.lock_outline_rounded, size: 16, color: Joy.warning),
                SizedBox(width: 6),
                Expanded(child: Text('البيع والحجز مقفلان حتى التوثيق', style: TextStyle(color: Joy.warning, fontWeight: FontWeight.w600, fontSize: 12.5))),
              ]),
            ),
          if (next != null)
            Container(
              key: const Key('completeness-next'),
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الخطوة التالية: ${next.title} · ${next.minutes} دقيقة', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  if (next.hint.isNotEmpty) Text(next.hint, style: const TextStyle(color: Joy.text, fontSize: 12, height: 1.4)),
                ])),
                const SizedBox(width: 8),
                FilledButton(key: const Key('completeness-go'), style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact), onPressed: () => _go(context, next.tab), child: const Text('ابدأ')),
              ]),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Check('الشعار', k.logo),
            _Check('الموقع', k.location),
            _Check('الجوال', k.phone),
            _Check(biz.isMobile ? 'نطاق الخدمة' : 'ساعات العمل', k.hours),
            _Check('الوصف', k.description),
            _Check('الصور ${k.photosHave}/${k.photosNeed}', k.photos),
            _Check('الكتالوج ${k.catalogHave}/${k.catalogNeed}', k.catalog),
            _Check(k.entityStatus == 'pending' ? 'التوثيق · قيد المراجعة' : 'التوثيق', k.entity),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
    ]);
  }

  void _go(BuildContext context, String tab) {
    if (tab == 'verify') { openVerifyCircle(context, biz.id, initial: biz); return; }
    final i = BusinessDashboardPage.tabIndexFor(tab);
    if (i != null) DefaultTabController.maybeOf(context)?.animateTo(i);
  }
}

class _Check extends StatelessWidget {
  final String label;
  final bool done;
  const _Check(this.label, this.done);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: done ? const Color(0xFFE6F6EC) : Joy.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 14, color: done ? Joy.success : Joy.textMuted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: done ? Joy.success : Joy.textMuted, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ------------------------------------------------------------------ «أنا هنا اليوم»

const hereTodayHours = [2, 4, 6, 8, 12];

/// ورقة «أنا هنا اليوم»: اختيار المدة ثم موقع الجهاز ثم دبوس مؤقت؛ وأثناء سريانه تعرض «أنت هنا حتى …» مع «إنهاء».
Future<void> showHereTodaySheet(BuildContext context, Biz biz) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Joy.surface,
      builder: (_) => _HereSheet(biz: biz),
    );

class _HereSheet extends ConsumerStatefulWidget {
  final Biz biz;
  const _HereSheet({required this.biz});
  @override
  ConsumerState<_HereSheet> createState() => _HereSheetState();
}

class _HereSheetState extends ConsumerState<_HereSheet> {
  int hours = 4;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.biz;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('أنا هنا اليوم', style: TextStyle(fontFamily: AppTheme.displayFont, fontWeight: FontWeight.w700, fontSize: 20)),
        const SizedBox(height: 4),
        Text(b.isMobile ? 'يضع دبوساً مؤقتاً في مكانك الحالي فيجدك من حولك على الخريطة وفي الصف.' : 'في بازار أو فعالية خارج مقرك؟ ضع دبوساً مؤقتاً في مكانك الحالي.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 14),
        if (b.hereActive) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.location_on_rounded, color: Joy.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('أنت هنا حتى ${clockLabel(b.here!.until)}', key: const Key('here-until'), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700))),
            ]),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(key: const Key('here-end'), onPressed: busy ? null : _end, icon: const Icon(Icons.stop_circle_outlined, size: 18), label: const Text('إنهاء')),
          const SizedBox(height: 12),
          const Text('أو مدّد المدة من موقعك الحالي:', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 6),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final h in hereTodayHours)
            ChoiceChip(key: Key('here-h-$h'), label: Text('$h ساعات'), selected: hours == h, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: hours == h ? Joy.primaryOn : Joy.text, fontFamily: AppTheme.bodyFont), onSelected: (_) => setState(() => hours = h)),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('here-set'),
          onPressed: busy ? null : _set,
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.my_location_rounded),
          label: Text(b.hereActive ? 'تحديث الدبوس' : 'أنا هنا الآن'),
        ),
      ]),
    );
  }

  Future<void> _set() async {
    setState(() => busy = true);
    try {
      final gps = await DeviceLocation.current();
      if (gps == null) { if (mounted) toast(context, 'لم يُسمح بالوصول إلى الموقع', error: true); return; }
      final pin = await ref.read(apiClientProvider).setHere(widget.biz.id, lat: gps.latitude, lng: gps.longitude, hours: hours);
      invalidateCompleteness(ref, widget.biz.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'وُضع دبوسك حتى ${clockLabel(pin.until)}');
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _end() async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).clearHere(widget.biz.id);
      invalidateCompleteness(ref, widget.biz.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'أُنهي دبوس «هنا اليوم»');
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// منشورات الخريطة التي تروّج للدائرة (زر إجراء «دائرة تجارية»): مشاهدات وضغطات ومراسلات خلال 30 يوماً.
class _BizPostsCard extends ConsumerWidget {
  final String bizId;
  const _BizPostsCard({required this.bizId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(postStatsProvider((postId: null, bizId: bizId, days: 30)));
    final s = stats.valueOrNull;
    if (s == null || s.posts == 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      SectionTitle('منشورات الخريطة عن الدائرة · ${s.posts}', action: 'التفاصيل', onAction: () => showPostStats(context, bizId: bizId)),
      JoyCard(
        child: Row(children: [
          _Mini(icon: Icons.visibility_outlined, value: '${s.totals.views}', label: 'مشاهدة'),
          _Mini(icon: Icons.ads_click_rounded, value: '${s.totals.cta}', label: 'ضغطة إجراء'),
          _Mini(icon: Icons.chat_bubble_outline_rounded, value: '${s.totals.contacts}', label: 'مراسلة'),
          _Mini(icon: Icons.favorite_border_rounded, value: '${s.totals.likes}', label: 'إعجاب'),
        ]),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? hint;
  const _Stat({required this.label, required this.value, required this.icon, required this.color, this.hint});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Joy.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: color))),
          if (hint != null) Text(hint!, style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
        ]),
      );
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final String? warn;
  const _Mini({required this.icon, required this.value, required this.label, this.warn});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, size: 18, color: Joy.textMuted),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (warn != null) Text(warn!, style: const TextStyle(color: Joy.accent, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({super.key, required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 18, color: Joy.primary),
        label: Text(label, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: Joy.text)),
        backgroundColor: Joy.surface,
        side: const BorderSide(color: Joy.line),
        onPressed: onTap,
      );
}

/// أعمدة الإيرادات اليومية بلا مكتبة: عمود لكل يوم، والضغط يعرض القيمة.
class RevenueBars extends StatefulWidget {
  final List<({DateTime day, int orders, int revenue})> daily;
  const RevenueBars({super.key, required this.daily});
  @override
  State<RevenueBars> createState() => _RevenueBarsState();
}

class _RevenueBarsState extends State<RevenueBars> {
  int? picked;
  @override
  Widget build(BuildContext context) {
    final d = widget.daily;
    if (d.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('لا بيانات بعد', style: TextStyle(color: Joy.textMuted)));
    final max = d.fold<int>(0, (m, x) => x.revenue > m ? x.revenue : m);
    final sel = picked == null ? null : d[picked!];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(sel == null ? 'اضغط على عمود لعرض يومه' : '${dayLabel(sel.day)} · ${shortDate(sel.day)} · ${sel.orders} طلب · ${money(sel.revenue)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
      const SizedBox(height: 10),
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, x) in d.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => picked = picked == i ? null : i),
                behavior: HitTestBehavior.opaque,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: max == 0 ? 2 : (2 + 88 * x.revenue / max),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: picked == i ? Joy.accent : (x.revenue == 0 ? Joy.line : Joy.primary), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ),
                  const SizedBox(height: 4),
                  Text('${x.day.day}', style: TextStyle(fontSize: 9.5, height: 1, color: picked == i ? Joy.accent : Joy.textMuted)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ الملف

class ProfileTab extends ConsumerWidget {
  final Biz biz;
  const ProfileTab({super.key, required this.biz});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BizLogo(biz: biz, size: 56),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(biz.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('${biz.category.label}${biz.sector.isNotEmpty ? ' · ${biz.sector}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              const SizedBox(height: 4),
              Stars(rating: biz.rating, count: biz.ratingCount),
            ])),
          ]),
          const Divider(height: 24),
          _kv('الحالة', biz.active ? 'منشورة' : 'موقوفة'),
          _kv('التوثيق', biz.verificationLabel),
          _kv('الحضور', biz.isMobile ? 'متنقل · ${biz.serviceArea?.label ?? 'نطاق خدمة'}' : 'مكان ثابت'),
          _kv('صلاحيتك', biz.roleLabel),
          _kv('العنوان', biz.address.isEmpty ? '—' : biz.address),
          _kv('ساعات العمل', biz.hours.isEmpty ? '—' : biz.hours),
          _kv('الهاتف', biz.phone ?? '—'),
          _kv('الموقع الإلكتروني', biz.website ?? '—'),
          _kv('المميزات', biz.highlights.isEmpty ? '—' : biz.highlights.join(' · ')),
          _kv('المعرّف', biz.id),
        ])),
        const SizedBox(height: 12),
        if (biz.canManage) FilledButton.icon(onPressed: () => openBusinessEditor(context, biz: biz), icon: const Icon(Icons.edit_outlined), label: const Text('تعديل الملف والصور والموقع')),
        const SizedBox(height: 8),
        if (biz.canManage)
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).updateBiz(biz.id, {'active': !biz.active});
                invalidateBizAll(ref, biz.id);
                if (context.mounted) toast(context, biz.active ? 'أُوقفت الدائرة' : 'نُشرت الدائرة');
              } catch (e) {
                if (context.mounted) toast(context, ownerErrText(e), error: true);
              }
            },
            icon: Icon(biz.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
            label: Text(biz.active ? 'إيقاف الدائرة مؤقتاً' : 'نشر الدائرة'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => openBusiness(context, biz.id), icon: const Icon(Icons.open_in_new_rounded), label: const Text('عرض الصفحة العامة')),
        if (biz.canManage) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('profile-verify'), onPressed: () => openVerifyCircle(context, biz.id, initial: biz), icon: Icon(biz.verified ? Icons.verified_rounded : Icons.verified_user_outlined, color: biz.verified ? Joy.success : null), label: Text(biz.verified ? 'الدائرة موثّقة · التفاصيل' : 'وثّق دائرتك لتبدأ البيع')),
        ],
        if (!biz.verified)
          const Padding(padding: EdgeInsets.only(top: 14), child: Text('التوثيق بالسجل التجاري أو وثيقة العمل الحر يفتح البيع والحجز وربط الدفع، وتراجعه الإدارة عادةً خلال يوم عمل.', style: TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5))),
      ]);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Joy.textMuted, fontSize: 13))), Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5)))]),
      );
}
