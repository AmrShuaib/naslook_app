import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart' show Person;
import '../api/notify_api.dart';
import '../pages/admin/admin_shell.dart';
import '../state/admin_providers.dart';
import '../pages/business/biz_order_page.dart';
import '../pages/business/business_page.dart';
import '../pages/business/community_page.dart';
import '../pages/business/my_bookings_page.dart';
import '../pages/business/offers_page.dart';
import '../pages/chat/chat_thread_page.dart';
import '../pages/circles/circle_detail_page.dart';
import '../pages/profile/user_profile_page.dart';
import '../pages/wallet/my_offers_page.dart';
import '../pages/business/owner/business_dashboard_page.dart';
import '../pages/business/owner/job_candidate_page.dart';
import '../pages/business/owner/job_candidates_page.dart';
import '../pages/business/owner/verify_circle_page.dart';
import '../pages/events/events_page.dart';
import '../pages/jobs/job_offer_page.dart';
import '../pages/jobs/job_offers_page.dart';
import '../pages/market/market_page.dart';
import '../pages/market/wanted_page.dart';
import '../pages/myspace/wishlist_page.dart';
import '../pages/posts/moment_actions.dart';
import '../pages/posts/my_posts_page.dart';
import '../pages/search/search_page.dart';
import '../pages/wallet/wallet_page.dart';
import '../state/notify_providers.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

/// يعلّم الإشعار مقروءاً ويفتح وجهته. يعيد false إن لم يكن لنوعه وجهة.
Future<bool> openNotification(BuildContext context, WidgetRef ref, AppNotification n) async {
  if (n.unread) {
    ref.read(apiClientProvider).notifyRead(ids: [n.id]).then((_) {
      ref.invalidate(notifyUnreadProvider);
      ref.invalidate(notificationsProvider);
    }).catchError((_) {});
  }
  // طلب توثيق جديد: يُفتح قسم الدوائر على طابور التوثيق مباشرة
  if (n.kind == 'biz_verification') ref.read(adminBizSegmentProvider.notifier).state = 'verifications';
  final page = notificationTarget(n);
  if (page == null || !context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  return true;
}

/// الوجهة حسب نوع الإشعار وبياناته (bizId, eventId, ...).
Widget? notificationTarget(AppNotification n) {
  final biz = n.str('bizId'), event = n.str('eventId');
  // التوظيف من جهة الدائرة: الإشعارات الموسومة manage تفتح المرشح نفسه إن عُرف، وإلا لوحة مرشحي العرض.
  // الأنواع نفسها بلا manage تخص الباحث عن عمل وتُعالج في switch أدناه.
  final job = n.str('jobId'), match = n.str('matchId');
  final listing = n.str('listingId'), order = n.str('orderId');
  if (n.data['manage'] == true && biz != null && job != null && const {'job_accept', 'job_answers', 'job_apply', 'job_stage', 'job_interview'}.contains(n.kind)) {
    return match != null ? JobCandidatePage(bizId: biz, jobId: job, matchId: match) : JobCandidatesPage(bizId: biz, jobId: job);
  }
  switch (n.kind) {
    // مراجعة العروض: للفريق (manage) لوحة توظيف الدائرة؛ وللمشرفين (بانتظار الموافقة) قسم التوظيف في الإدارة
    case 'job_review':
      if (n.data['manage'] != true) return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'jobs').clamp(0, adminSections.length - 1));
      return biz == null ? null : BusinessDashboardPage(id: biz, initialTab: BusinessDashboardPage.jobsTab);
    case 'biz_order':
    case 'order_cancelled':
      return biz == null ? null : BusinessDashboardPage(id: biz, initialTab: 1);
    case 'biz_review':
      return biz == null ? null : BusinessDashboardPage(id: biz, initialTab: 5);
    case 'biz_owner':
      return biz == null ? null : BusinessDashboardPage(id: biz);
    // قرار التوثيق (قبول أو رفض بسبب): صفحة التوثيق في لوحة الدائرة
    case 'biz_verified':
    case 'biz_verification_rejected':
      return biz == null ? null : VerifyCirclePage(bizId: biz);
    case 'claim_decided':
      return biz == null ? null : (n.data['approved'] == true ? BusinessDashboardPage(id: biz) : BusinessPage(id: biz));
    case 'review_reply':
    case 'biz_update':
      return biz == null ? null : BusinessPage(id: biz);
    case 'biz_offer':
      return biz == null ? const MyOffersPage() : CircleOffersPage(bizId: biz);
    case 'offer_received':
    case 'offer_loyalty':
      return const MyOffersPage();
    case 'order_status':
      return const MyBookingsPage();
    // «لدي مشكلة» على طلب دائرة (business.js): فتحها والرد عليها وحسمها؛ الطلب نفسه لكل طرف (العميل والفريق والإدارة)
    case 'biz_dispute':
      if (order != null) return BizOrderPage(orderId: order);
      if (n.data['side'] == 'admin') return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'market').clamp(0, adminSections.length - 1));
      return n.data['side'] == 'team' && biz != null ? BusinessDashboardPage(id: biz, initialTab: 1) : const MyBookingsPage();
    case 'ticket_sale':
    case 'event_cancelled':
      return event == null ? const EventsPage() : EventDetailPage(eventId: event);
    // السوق (commerce.js وmarket_plus.js وmarket_b.js): كل نوع إلى شاشته من حمولته، والاحتياط «عروضي وطلباتي» حين تغيب
    // الطلب: طلب جديد للبائع، مراحل الطلب، تكليف المندوب أو إلغاؤه، النزاع وحسمه (المدير يرى الطلب أيضاً)
    case 'market_order':
    case 'market_status':
    case 'market_courier':
    case 'market_dispute':
    // الدفع عند الاستلام (commerce.js): طلب جديد للبائع، قبوله للمشتري، واكتماله للطرف الآخر
    case 'market_cod_order':
    case 'market_cod_accepted':
    case 'market_cod_completed':
      return order == null ? const OrdersPage() : OrderPage(order);
    // العرض: جديد من بائع أتابعه، تنبيه يطابق، سؤال أو جواب، سبوت لايت ممنوح، قرار المراجعة، والتقييم أو الرد عليه
    case 'market_new':
    case 'market_alert':
    case 'market_question':
    case 'market_spotlight':
    case 'market_review_result':
    case 'market_review':
      return listing != null ? ListingPage(listing) : order != null ? OrderPage(order) : const OrdersPage(initialTab: 0);
    // عرض بانتظار المراجعة (للمديرين): قسم السوق في الإدارة حيث القبول والرفض
    case 'market_pending':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'market').clamp(0, adminSections.length - 1));
    // «أبحث عن»: طلب مشترٍ يطابق ما أقدّمه، أو عرض وصل على طلبي
    case 'market_wanted':
      final wanted = n.str('wantedId');
      return wanted == null ? const WantedPage() : WantedDetailPage(wanted);
    case 'market_bazaar':
      final bazaar = n.str('bazaarId');
      return bazaar == null ? const MarketPage() : BazaarPage(bazaar);
    // ترقية البائع إلى دائرة أعمال (market_b.js): لوحة الدائرة الجديدة لإكمال ملفها
    case 'biz':
      return biz == null ? null : BusinessDashboardPage(id: biz);
    case 'listing_hidden':
      return const OrdersPage(initialTab: 0);
    case 'transfer_in':
    case 'wallet_credit':
    // شحن المحفظة بالبطاقة (market_b.js)
    case 'wallet':
      return const WalletPage();
    case 'biz_claim':
      return const AdminShell(standalone: false, initialSection: 3);
    // طلب توثيق جديد: قسم الدوائر في الإدارة على طابور التوثيق (المقطع يُضبط عند الفتح في openNotification)
    case 'biz_verification':
      return const AdminShell(standalone: false, initialSection: 3);
    case 'report_new':
      return const AdminShell(standalone: false, initialSection: 2);
    case 'admin_granted':
    case 'team_added':
    case 'team_role':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'team').clamp(0, adminSections.length - 1));
    case 'task_assigned':
    case 'task_status':
    case 'task_comment':
    case 'task_due':
    case 'task_overdue':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'tasks').clamp(0, adminSections.length - 1));
    case 'inbox_message':
    case 'inbox_assigned':
    case 'inbox_note':
    case 'inbox_send_failed':
    case 'inbox_unsnoozed':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'inbox').clamp(0, adminSections.length - 1));
    case 'post_blocked':
      return const MyPostsPage();
    // تفاعل أو إعجاب على لحظتي (moment_extras.js وmap_posts.js): تُفتح اللحظة نفسها في العارض
    case 'moment_react':
    case 'post_like':
      final post = n.str('postId');
      return post == null ? const MyPostsPage() : MomentLinkPage(id: post);
    // لحظة جديدة ممن أتابعهم (profile_ext.js عبر map_posts.js): اللحظة نفسها، وإلا ملف ناشرها
    case 'follow_moment':
      final moment = n.str('postId'), author = n.str('userId');
      if (moment != null) return MomentLinkPage(id: moment);
      return author == null ? null : UserProfilePage(person: Person(id: author, nickname: n.str('nickname') ?? author));
    // حجز فندق مؤكد (hotels.js): «حجوزاتي» وفيها الحجز برقم تأكيده
    case 'hotel_booked':
      return const MyBookingsPage();
    // متابع جديد (profile_ext.js): ملف المتابِع؛ الاسم من الحمولة (أو من العنوان في الإشعارات الأقدم) حتى يُحمَّل الملف
    case 'profile_follow':
      final user = n.str('userId');
      return user == null ? null : UserProfilePage(person: Person(id: user, nickname: n.str('nickname') ?? _nameFromTitle(n.title, ' يتابعك', user)));
    // قبول موعد «نتقابل» (chat_cards.js): المحادثة مع الطرف الآخر عند بطاقة الموعد
    case 'meet_accepted':
      final peer = n.str('peerId');
      return peer == null ? null : ChatThreadPage(peer: Person(id: peer, nickname: n.str('peerNickname') ?? peer), initialMessageId: n.str('messageId'));
    // أزال مشرف الدائرة منشوري (vessel_mod.js أو الإدارة عبر safety.js): الدائرة نفسها
    case 'vessel_post_hidden':
      final vessel = n.str('vesselId');
      return vessel == null ? null : CircleDetailPage(vesselId: vessel);
    // أُعيد إظهار محتوى بعد المراجعة، أو أُخفي محتوى نوعه بلا إشعار خاص (safety.js): المحتوى نفسه أو موضعه
    case 'content_restored':
    case 'content_hidden':
      return _moderatedTarget(n);
    // بلاغات كثيرة على دائرة (لا تُخفى تلقائياً): طابور البلاغات في الإدارة
    case 'content_reported_many':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'reports').clamp(0, adminSections.length - 1));
    // استرداد رصيد حساب محذوف (account_delete.js): المالية في الإدارة
    case 'account_refund':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'finance').clamp(0, adminSections.length - 1));
    case 'wish_price_drop':
    case 'wish_available':
    case 'wish_event_reminder':
      return const WishlistPage();
    case 'saved_search_match':
      return SearchPage(initialQuery: n.str('q') ?? '');
    // إخفاء تلقائي بعد بلاغات، أو بلاغات محتوى جديدة (notify.js): طابور البلاغات (كان الفهرس 5 = المالية بعد إعادة ترتيب الأقسام)
    case 'content_autohidden':
    case 'content_reports_new':
      return AdminShell(standalone: false, initialSection: adminSections.indexWhere((s) => s.$1 == 'reports').clamp(0, adminSections.length - 1));
    case 'community_post':
    case 'community_reply':
    case 'community_hidden':
      return biz == null ? null : CommunityPage(bizId: biz, initialPostId: n.str('postId'));
    // التوظيف من جهة المرشح: بطاقة عرض → صفحة العرض؛ تغيّر المرحلة أو موعد مقابلة → العرض نفسه أو «طلباتي»
    case 'job_offer':
      return match == null ? const JobOffersPage() : JobOfferPage(matchId: match);
    case 'job_stage':
    case 'job_interview':
      return match == null ? const JobOffersPage(initialTab: 1) : JobOfferPage(matchId: match);
    // إشعارات الفريق بلا وسم manage (احتياط): لوحة مرشحي العرض
    case 'job_accept':
    case 'job_answers':
    case 'job_apply':
      return biz == null || job == null ? null : (match == null ? JobCandidatesPage(bizId: biz, jobId: job) : JobCandidatePage(bizId: biz, jobId: job, matchId: match));
  }
  return null;
}

/// الاسم من عنوان إشعار قديم بلا الاسم في حمولته («sara يتابعك» ← sara).
String _nameFromTitle(String title, String suffix, String fallback) {
  final t = title.endsWith(suffix) ? title.substring(0, title.length - suffix.length).trim() : '';
  return t.isEmpty ? fallback : t;
}

/// وجهة محتوى أُعيد بعد المراجعة (أو أُخفي) حسب نوعه في safety.js (`targetType`/`targetId` ومعرّفات الأصل في الحمولة).
Widget? _moderatedTarget(AppNotification n) {
  final type = n.str('targetType'), id = n.str('targetId');
  final biz = n.str('bizId'), vessel = n.str('vesselId'), listing = n.str('listingId'), wanted = n.str('wantedId');
  final post = n.str('postId'), parent = n.str('parentId');
  switch (type) {
    case 'post':
      final m = post ?? id;
      return m == null ? const MyPostsPage() : MomentLinkPage(id: m);
    case 'listing':
    case 'listing-question':
    case 'listing-review':
      final l = listing ?? (type == 'listing' ? id : null);
      return l == null ? const OrdersPage(initialTab: 0) : ListingPage(l);
    case 'community':
    case 'community-reply':
      return biz == null ? null : CommunityPage(bizId: biz, initialPostId: type == 'community' ? (post ?? id) : parent);
    case 'vessel-post':
    case 'vessel-comment':
    case 'vessel':
      final v = vessel ?? (type == 'vessel' ? id : null);
      return v == null ? null : CircleDetailPage(vesselId: v, focusPostId: type == 'vessel-post' ? (post ?? id) : type == 'vessel-comment' ? parent : null);
    case 'wanted':
    case 'wanted-reply':
      final w = wanted ?? (type == 'wanted' ? id : null);
      return w == null ? const WantedPage() : WantedDetailPage(w);
    case 'biz':
    case 'biz-review':
    case 'biz-post':
      final b = biz ?? (type == 'biz' ? id : null);
      return b == null ? null : BusinessPage(id: b);
    case 'event':
      return id == null ? const EventsPage() : EventDetailPage(eventId: id);
  }
  return null;
}

/// أيقونة ولون لكل نوع إشعار.
({IconData icon, Color color}) notificationStyle(String kind) {
  switch (kind) {
    case 'biz_order':
    case 'market_order':
      return (icon: Icons.shopping_bag_outlined, color: Joy.primary);
    case 'market_cod_order':
    case 'market_cod_accepted':
      return (icon: Icons.payments_outlined, color: Joy.sunText);
    case 'market_cod_completed':
      return (icon: Icons.task_alt_rounded, color: Joy.success);
    case 'order_status':
    case 'market_status':
    case 'order_cancelled':
      return (icon: Icons.receipt_long_outlined, color: Joy.accent);
    case 'market_new':
    case 'market_alert':
    case 'market_bazaar':
      return (icon: Icons.storefront_outlined, color: Joy.primary);
    case 'market_question':
      return (icon: Icons.question_answer_outlined, color: Joy.primary);
    case 'market_courier':
      return (icon: Icons.delivery_dining_outlined, color: Joy.accent);
    case 'market_dispute':
    case 'biz_dispute':
      return (icon: Icons.gavel_rounded, color: Joy.danger);
    case 'market_review':
      return (icon: Icons.star_outline_rounded, color: Joy.sunText);
    case 'market_review_result':
    case 'market_pending':
      return (icon: Icons.fact_check_outlined, color: Joy.sunText);
    case 'market_spotlight':
      return (icon: Icons.auto_awesome_outlined, color: Joy.sunText);
    case 'market_wanted':
      return (icon: Icons.campaign_outlined, color: Joy.accent);
    case 'biz':
      return (icon: Icons.add_business_outlined, color: Joy.primary);
    case 'wallet':
      return (icon: Icons.account_balance_wallet_outlined, color: Joy.primary);
    case 'biz_review':
    case 'review_reply':
      return (icon: Icons.star_outline_rounded, color: Joy.sunText);
    case 'ticket_sale':
    case 'event_cancelled':
      return (icon: Icons.event_outlined, color: Joy.accent);
    case 'transfer_in':
    case 'wallet_credit':
      return (icon: Icons.account_balance_wallet_outlined, color: Joy.primary);
    case 'biz_claim':
    case 'claim_decided':
    case 'biz_owner':
      return (icon: Icons.storefront_outlined, color: Joy.primary);
    case 'report_new':
    case 'account_warning':
    case 'account_suspended':
    case 'content_autohidden':
    case 'content_reports_new':
    case 'content_reported_many':
    case 'post_blocked':
      return (icon: Icons.report_gmailerrorred_outlined, color: Joy.danger);
    case 'admin_granted':
    case 'account_restored':
      return (icon: Icons.verified_user_outlined, color: Joy.primary);
    case 'biz_verified':
      return (icon: Icons.verified_rounded, color: Joy.success);
    case 'biz_verification_rejected':
      return (icon: Icons.gpp_bad_outlined, color: Joy.danger);
    case 'biz_verification':
      return (icon: Icons.fact_check_outlined, color: Joy.primary);
    case 'wish_price_drop':
    case 'wish_available':
    case 'wish_event_reminder':
      return (icon: Icons.bookmark_added_outlined, color: Joy.accent);
    case 'moment_react':
      return (icon: Icons.add_reaction_outlined, color: Joy.accent);
    case 'post_like':
      return (icon: Icons.favorite_border_rounded, color: Joy.accent);
    case 'follow_moment':
      return (icon: Icons.auto_awesome_outlined, color: Joy.primary);
    case 'hotel_booked':
      return (icon: Icons.hotel_outlined, color: Joy.primary);
    case 'profile_follow':
      return (icon: Icons.person_add_alt_1_outlined, color: Joy.primary);
    case 'meet_accepted':
      return (icon: Icons.event_available_outlined, color: Joy.success);
    case 'vessel_post_hidden':
    case 'content_hidden':
      return (icon: Icons.visibility_off_outlined, color: Joy.danger);
    case 'content_restored':
      return (icon: Icons.visibility_outlined, color: Joy.success);
    case 'saved_search_match':
      return (icon: Icons.saved_search_rounded, color: Joy.primary);
    case 'community_post':
    case 'community_reply':
      return (icon: Icons.forum_outlined, color: Joy.primary);
    case 'community_hidden':
      return (icon: Icons.visibility_off_outlined, color: Joy.danger);
    case 'job_offer':
      return (icon: Icons.work_outline_rounded, color: Joy.primary);
    case 'job_stage':
      return (icon: Icons.timeline_rounded, color: Joy.accent);
    case 'job_interview':
      return (icon: Icons.event_available_outlined, color: Joy.accent);
    case 'job_accept':
    case 'job_answers':
    case 'job_apply':
      return (icon: Icons.person_add_alt_1_outlined, color: Joy.primary);
    case 'job_review':
      return (icon: Icons.fact_check_outlined, color: Joy.sunText);
  }
  return (icon: Icons.notifications_outlined, color: Joy.textMuted);
}
