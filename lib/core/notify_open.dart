import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notify_api.dart';
import '../pages/admin/admin_shell.dart';
import '../pages/business/business_page.dart';
import '../pages/business/my_bookings_page.dart';
import '../pages/business/owner/business_dashboard_page.dart';
import '../pages/events/events_page.dart';
import '../pages/market/market_page.dart';
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
  final page = notificationTarget(n);
  if (page == null || !context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  return true;
}

/// الوجهة حسب نوع الإشعار وبياناته (bizId, eventId, ...).
Widget? notificationTarget(AppNotification n) {
  final biz = n.str('bizId'), event = n.str('eventId');
  switch (n.kind) {
    case 'biz_order':
    case 'order_cancelled':
      return biz == null ? null : BusinessDashboardPage(id: biz, initialTab: 1);
    case 'biz_review':
      return biz == null ? null : BusinessDashboardPage(id: biz, initialTab: 4);
    case 'biz_owner':
      return biz == null ? null : BusinessDashboardPage(id: biz);
    case 'claim_decided':
      return biz == null ? null : (n.data['approved'] == true ? BusinessDashboardPage(id: biz) : BusinessPage(id: biz));
    case 'review_reply':
      return biz == null ? null : BusinessPage(id: biz);
    case 'order_status':
      return const MyBookingsPage();
    case 'ticket_sale':
    case 'event_cancelled':
      return event == null ? const EventsPage() : EventDetailPage(eventId: event);
    case 'market_order':
    case 'market_status':
      return const OrdersPage();
    case 'listing_hidden':
      return const MarketPage();
    case 'transfer_in':
    case 'wallet_credit':
      return const WalletPage();
    case 'biz_claim':
      return const AdminShell(standalone: false, initialSection: 3);
    case 'report_new':
      return const AdminShell(standalone: false, initialSection: 2);
    case 'admin_granted':
      return const AdminShell(standalone: false);
  }
  return null;
}

/// أيقونة ولون لكل نوع إشعار.
({IconData icon, Color color}) notificationStyle(String kind) {
  switch (kind) {
    case 'biz_order':
    case 'market_order':
      return (icon: Icons.shopping_bag_outlined, color: Joy.primary);
    case 'order_status':
    case 'market_status':
    case 'order_cancelled':
      return (icon: Icons.receipt_long_outlined, color: Joy.accent);
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
      return (icon: Icons.report_gmailerrorred_outlined, color: Joy.danger);
    case 'admin_granted':
    case 'account_restored':
      return (icon: Icons.verified_user_outlined, color: Joy.primary);
  }
  return (icon: Icons.notifications_outlined, color: Joy.textMuted);
}
