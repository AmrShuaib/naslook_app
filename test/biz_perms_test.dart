// صلاحيات الدائرة لكل عضو (docs/circle-permissions.md): تبويبات اللوحة وأزرارها تتبع المفاتيح، صفحة مفاتيح العضو بحدودها،
// إضافة عضو، وسجل النشاط.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/biz_models.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/business/owner/biz_activity_page.dart';
import 'package:naslook/pages/business/owner/business_dashboard_page.dart';
import 'package:naslook/pages/business/owner/dashboard_catalog.dart';
import 'package:naslook/pages/business/owner/dashboard_reviews_team.dart';
import 'package:naslook/pages/business/owner/team_member_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

const _all = ['orders', 'orders_cancel', 'catalog', 'offers', 'posts', 'inbox', 'reviews', 'hiring', 'stats', 'profile', 'team'];

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

Map<String, dynamic> _biz({String role = 'owner', List<String>? perms}) => {
      'id': 'biz-cafe', 'name': 'Cafe', 'nameAr': 'مقهى عمرو', 'category': 'cafe', 'sector': 'مقهى', 'description': 'قهوة', 'lat': 21.5, 'lng': 39.2, 'address': 'الروضة، جدة', 'hours': '8-12',
      'verified': true, 'active': true, 'ownerId': role == 'owner' ? 'SA0000001' : 'SA0000009', 'myRole': role, if (perms != null) 'myPerms': perms,
      'followers': 3, 'rating': 4.0, 'ratingCount': 1, 'itemsCount': 1,
      'items': [{'id': 'cafe-latte', 'bizId': 'biz-cafe', 'kind': 'product', 'title': 'لاتيه', 'price': 1500, 'unit': 'item', 'stock': 10, 'meta': {}, 'active': true}],
      'reviews': [{'user': {'id': 'SA0000002', 'nickname': 'sara'}, 'rating': 4, 'text': 'لذيذ', 'createdAt': DateTime.now().toUtc().toIso8601String(), 'mine': false}], 'posts': [], 'myOrders': [],
    };

Map<String, dynamic> _member(String id, String nick, String role, List<String> perms, {bool custom = false, String? lock}) =>
    {'user': {'id': id, 'nickname': nick}, 'role': role, 'since': DateTime.now().toUtc().toIso8601String(), 'perms': perms, 'custom': custom, 'editable': lock == null, 'lock': lock};

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  String role = 'owner';
  List<String>? perms;
  /// «me» في رد الفريق؛ null يحاكي خادماً أقدم لا يرسله.
  Map<String, dynamic>? me = {'id': 'SA0000001', 'role': 'owner', 'perms': _all, 'boss': true};
  List<Map<String, dynamic>> staff = [
    _member('SA0000003', 'khalid', 'staff', ['orders', 'inbox', 'stats']),
    _member('SA0000004', 'nora', 'manager', _all),
  ];
  int? failPatch;
  Map<String, dynamic> failBody = {'error': 'not-held', 'perm': 'stats'};
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    final key = '${req.method} $path';
    calls.add(key);
    if (req.body.isNotEmpty && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /biz/biz-cafe') return _json(_biz(role: role, perms: perms));
    if (key == 'GET /biz/biz-cafe/stats') {
      return _json({'orders': {'total': 5, 'confirmed': 2, 'used': 2, 'cancelled': 1, 'last7': 4, 'next24h': 1, 'customers': 3}, 'revenue': {'total': 9000, 'last7': 6000, 'last30': 9000}, 'byKind': [], 'daily': [], 'topItems': [], 'followers': 3, 'rating': 4.0, 'reviews': 1, 'unanswered': 1, 'views': 7});
    }
    if (key == 'GET /biz/biz-cafe/orders') return _json([]);
    if (key == 'GET /biz/biz-cafe/team') return _json({'owner': {'id': 'SA0000009', 'nickname': 'boss'}, 'staff': staff, 'perms': _all, if (me != null) 'me': me, 'limit': 50});
    if (key == 'POST /biz/biz-cafe/team') return _json({'ok': true});
    if (req.method == 'PATCH' && path.startsWith('/biz/biz-cafe/team/')) return failPatch != null ? _json(failBody, failPatch!) : _json({'ok': true});
    if (req.method == 'DELETE' && path.startsWith('/biz/biz-cafe/team/')) return _json({'ok': true});
    if (key == 'GET /biz/biz-cafe/activity') {
      final before = req.url.queryParameters['before'];
      final at = DateTime.now().toUtc().toIso8601String();
      if (before == null) {
        return _json({'items': [
          {'id': '9', 'action': 'item.price', 'target': 'cafe-latte', 'summary': 'غيّر سعر «لاتيه» من 15 ر.س إلى 18 ر.س', 'at': at, 'actor': {'id': 'SA0000004', 'nickname': 'nora'}},
          {'id': '8', 'action': 'team.add', 'target': 'SA0000003', 'summary': 'أضاف khalid بدور موظف', 'at': at, 'actor': null},
        ], 'next': '8', 'keepDays': 180});
      }
      return _json({'items': [{'id': '7', 'action': 'order.checkin', 'target': 'o1', 'summary': 'أكّد استلام «لاتيه» (NAS-AAAA1111)', 'at': at, 'actor': {'id': 'SA0000003', 'nickname': 'khalid'}}], 'next': null, 'keepDays': 180});
    }
    if (key == 'GET /users/by-handle/majed' || path.contains('majed')) return _json({'id': 'SA0000007', 'nickname': 'majed'});
    if (path.startsWith('/presence/')) return _json({'online': false});
    if (path.endsWith('/inbox/unread')) return _json({'unread': 0, 'open': 0, 'mine': 0});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

Finder _tab(String id) => find.byKey(Key('dash-tab-$id'));
bool _enabled(WidgetTester tester, String perm) => tester.widget<SwitchListTile>(find.byKey(Key('perm-$perm'))).onChanged != null;
bool _value(WidgetTester tester, String perm) => tester.widget<SwitchListTile>(find.byKey(Key('perm-$perm'))).value;

void main() {
  test('Biz permissions: server list wins, role preset is the fallback, legacy getters stay', () {
    final staff = Biz.fromJson(_biz(role: 'staff'));
    expect(staff.perms, ['orders', 'inbox', 'stats']);
    expect(staff.can('orders') && staff.can('stats') && !staff.can('catalog') && !staff.canHire, isTrue);
    expect(staff.canManage, isFalse);
    expect(staff.canOperate, isTrue);
    final plus = Biz.fromJson(_biz(role: 'staff', perms: ['orders', 'catalog']));
    expect(plus.can('catalog') && !plus.can('stats') && !plus.can('inbox'), isTrue);
    expect(plus.canManage, isFalse, reason: 'الدور لم يتغير');
    expect(plus.scoped('catalog').canManage, isTrue, reason: 'تبويب القائمة يتبع المفتاح');
    expect(plus.scoped('offers').canManage, isFalse);
    expect(plus.scoped('catalog').myRole, 'staff');
    final manager = Biz.fromJson(_biz(role: 'manager'));
    expect(manager.perms.length, 11);
    expect(manager.canManage && manager.canHire && !manager.isOwner, isTrue);
    expect(Biz.fromJson(_biz(role: 'manager', perms: ['orders'])).scoped('orders_cancel').canManage, isFalse, reason: 'مدير أُطفئ له الإلغاء');
    expect(Biz.fromJson(_biz(role: 'admin')).can('inbox'), isFalse);
    expect(Biz.fromJson(_biz(role: 'hr')).perms, ['hiring']);
    // تبويبات القراءة تبقى للموظف كما كانت قبل المفاتيح؛ الفعل فيها وحده خلف المفتاح
    expect(BusinessDashboardPage.visibleTabs(staff), ['overview', 'orders', 'catalog', 'posts', 'reviews', 'profile', 'inbox']);
    expect(BusinessDashboardPage.canActIn(staff, 'catalog'), isFalse);
    expect(BusinessDashboardPage.canActIn(plus, 'catalog'), isTrue);
    expect(BusinessDashboardPage.visibleTabs(Biz.fromJson(_biz(role: 'hr'))), ['jobs']);
    expect(BusinessDashboardPage.visibleTabs(manager), BusinessDashboardPage.tabIds);
  });

  test('team parsing: member switches, my limits, old server without «me»', () {
    final t = BizTeam.fromJson({'owner': {'id': 'SA0000009', 'nickname': 'boss'}, 'staff': [_member('SA0000003', 'khalid', 'staff', ['orders'], custom: true, lock: 'team-holder')], 'me': {'role': 'manager', 'perms': ['orders', 'catalog', 'team'], 'boss': false}});
    expect(t.staff.single.custom && t.staff.single.lock == 'team-holder' && t.staff.single.can('orders') && !t.staff.single.can('stats'), isTrue);
    expect(t.grantBlock('catalog'), isNull);
    expect(t.grantBlock('team'), 'يمنحها المالك فقط');
    expect(t.grantBlock('stats'), 'لا تحملها أنت');
    expect(t.canGrantRole('manager'), isFalse);
    expect(t.canGrantRole('staff'), isTrue, reason: 'يُسند الدور بما أحمله من قالبه، والباقي يُرسل مطفأً');
    expect(t.startPerms('staff'), ['orders']);
    expect(t.canGrantRole('hr'), isFalse);
    final old = BizTeam.fromJson({'owner': null, 'staff': [{'user': {'id': 'SA0000003', 'nickname': 'khalid'}, 'role': 'hr'}]});
    expect(old.myRole, isNull);
    expect(old.staff.single.perms, ['hiring'], reason: 'خادم أقدم: قالب الدور');
    final log = BizActivityLog.fromJson({'items': [{'id': 5, 'action': 'item.price', 'summary': 'x', 'at': '2026-11-13T10:00:00Z', 'actor': {'id': 'SA0000001', 'nickname': 'amr'}}], 'next': '5'});
    expect(log.items.single.group, 'item');
    expect(log.next, '5');
    expect(log.keepDays, 180);
  });

  group('dashboard tabs follow the switches', () {
    testWidgets('owner sees every tab', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
      for (final t in BusinessDashboardPage.tabIds) {
        expect(_tab(t), findsOneWidget, reason: t);
      }
      expect(find.text('إيرادات 7 أيام'), findsOneWidget);
    });

    testWidgets('plain staff keep the read-only tabs they had; management tabs need the switch', (tester) async {
      final srv = _Srv()..role = 'staff';
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
      for (final t in ['overview', 'orders', 'catalog', 'posts', 'reviews', 'profile', 'inbox']) {
        expect(_tab(t), findsOneWidget, reason: t);
      }
      for (final t in ['offers', 'team', 'jobs']) {
        expect(_tab(t), findsNothing, reason: t);
      }
      expect(find.text('إيرادات 7 أيام'), findsOneWidget);
      expect(find.byKey(const Key('checkin-scan')), findsOneWidget);
      expect(find.byKey(const Key('quick-add-item')), findsNothing);
      expect(find.byKey(const Key('quick-new-offer')), findsNothing);
      expect(find.byKey(const Key('quick-edit-profile')), findsNothing);
      expect(find.byKey(const Key('verify-entry')), findsNothing);
    });

    testWidgets('staff with stats switched off: no revenue and the stats route is never called', (tester) async {
      final srv = _Srv()..role = 'staff'..perms = ['orders', 'inbox'];
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
      expect(_tab('overview'), findsOneWidget);
      expect(find.text('إيرادات 7 أيام'), findsNothing);
      expect(find.byType(RevenueBars), findsNothing);
      expect(srv.calls, isNot(contains('GET /biz/biz-cafe/stats')));
      expect(find.byKey(const Key('checkin-scan')), findsOneWidget);
    });

    testWidgets('plain staff read the catalog and reviews without add, edit or reply buttons', (tester) async {
      final srv = _Srv()..role = 'staff';
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 2));
      expect(find.byType(CatalogTab), findsOneWidget);
      expect(find.text('لاتيه'), findsWidgets);
      expect(find.byType(FloatingActionButton), findsNothing, reason: 'القراءة فقط بلا «القائمة والأسعار»');
      await tester.tap(_tab('reviews'));
      await tester.pumpAndSettle();
      expect(find.text('لذيذ'), findsOneWidget);
      expect(find.text('رد'), findsNothing);
      await tester.tap(_tab('profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileTab), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('staff with the catalog switch: the catalog tab has its add button', (tester) async {
      final srv = _Srv()..role = 'staff'..perms = ['orders', 'inbox', 'stats', 'catalog'];
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 2));
      expect(_tab('catalog'), findsOneWidget);
      expect(_tab('offers'), findsNothing);
      expect(find.byType(FloatingActionButton), findsWidgets, reason: 'زر الإضافة في تبويب القائمة يتبع المفتاح لا الدور');
      expect(find.text('لاتيه'), findsWidgets);
    });

    testWidgets('a deep link to a hidden tab falls back to the first visible one', (tester) async {
      final srv = _Srv()..role = 'staff';
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      expect(find.byType(TeamTab), findsNothing);
      expect(srv.calls, isNot(contains('GET /biz/biz-cafe/team')));
      expect(find.byType(OverviewTab), findsOneWidget);
    });

    testWidgets('a deep link keeps its tab when earlier tabs are hidden', (tester) async {
      final srv = _Srv()..role = 'manager'..perms = ['orders', 'reviews', 'team'];
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 5));
      expect(find.byType(ReviewsTab), findsOneWidget);
      expect(find.text('رد'), findsOneWidget);
    });

    testWidgets('a notification link to the hiring tab keeps it, locked, for a member without the switch', (tester) async {
      final srv = _Srv()..role = 'staff';
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: BusinessDashboardPage.jobsTab));
      expect(_tab('jobs'), findsOneWidget);
      expect(find.byKey(const Key('jobs-locked')), findsOneWidget);
      expect(_tab('team'), findsNothing);
    });

    testWidgets('hr member: only the hiring tab', (tester) async {
      final srv = _Srv()..role = 'hr';
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
      expect(_tab('jobs'), findsOneWidget);
      for (final t in ['overview', 'orders', 'catalog', 'team', 'inbox']) {
        expect(_tab(t), findsNothing, reason: t);
      }
      expect(srv.calls, isNot(contains('GET /biz/biz-cafe/stats')));
    });

    testWidgets('a member with every switch off sees the lock', (tester) async {
      final srv = _Srv()..role = 'staff'..perms = [];
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe'));
      expect(find.text('ليست لديك صلاحية على هذه الدائرة'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('team tab', () {
    testWidgets('lists members with their preset, corrected help text, add and activity entries', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      expect(find.text('khalid'), findsOneWidget);
      expect(find.textContaining('موظف · منذ'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('team-member-perms-SA0000003'))).data, '3 من 11 صلاحية');
      expect(tester.widget<Text>(find.byKey(const Key('team-member-perms-SA0000004'))).data, '11 من 11 صلاحية');
      final help = tester.widget<Text>(find.byKey(const Key('team-roles-help'))).data!;
      expect(help, contains('الموظف: الطلبات والاستلام، رسائل العملاء، والإحصاءات.'));
      expect(help, isNot(contains('عرض الطلبات وتأكيد الاستلام فقط')));
      expect(find.byKey(const Key('team-add')), findsOneWidget);
      expect(find.byKey(const Key('team-activity')), findsOneWidget);
      expect(find.text('نقل ملكية الدائرة'), findsOneWidget);
    });

    testWidgets('owner opens a member, flips switches and saves the full map', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      await tester.tap(find.byKey(const Key('team-member-SA0000003')));
      await tester.pumpAndSettle();
      expect(find.byType(TeamMemberPage), findsOneWidget);
      for (final (k, label) in bizPerms) {
        expect(find.text(label), findsOneWidget, reason: k);
        expect(_enabled(tester, k), isTrue, reason: 'المالك يعدّل كل مفتاح: $k');
      }
      expect(_value(tester, 'orders') && _value(tester, 'stats') && !_value(tester, 'catalog'), isTrue);
      expect(tester.widget<FilledButton>(find.byKey(const Key('member-save'))).onPressed, isNull, reason: 'لا تغيير بعد');
      await tester.tap(find.byKey(const Key('perm-catalog')));
      await tester.tap(find.byKey(const Key('perm-stats')));
      await tester.pumpAndSettle();
      expect(find.text('معدّل عن قالب الدور'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      final body = srv.bodies['PATCH /biz/biz-cafe/team/SA0000003']!;
      expect(body.containsKey('role'), isFalse, reason: 'الدور لم يتغير');
      final sent = (body['perms'] as Map).cast<String, dynamic>();
      expect(sent.length, 11);
      expect(sent['catalog'], isTrue);
      expect(sent['stats'], isFalse);
      expect(sent['orders'], isTrue);
      expect(sent['team'], isFalse);
      expect(find.byType(TeamMemberPage), findsNothing, reason: 'يعود إلى الفريق بعد الحفظ');
    });

    testWidgets('changing the role resets the switches to its preset and sends the role', (tester) async {
      final srv = _Srv();
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': srv.me});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz()), member: t.staff.first, team: t));
      await tester.tap(find.byKey(const Key('member-role-hr')));
      await tester.pumpAndSettle();
      expect(_value(tester, 'hiring') && !_value(tester, 'orders') && !_value(tester, 'stats'), isTrue);
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      final body = srv.bodies['PATCH /biz/biz-cafe/team/SA0000003']!;
      expect(body['role'], 'hr');
      expect((body['perms'] as Map)['hiring'], isTrue);
    });

    testWidgets('a manager: team switch and unheld switches are disabled with a reason, manager role cannot be picked', (tester) async {
      final srv = _Srv();
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': {'id': 'SA0000001', 'role': 'manager', 'perms': _all.where((p) => p != 'offers').toList(), 'boss': false}});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz(role: 'manager')), member: t.staff.first, team: t));
      expect(find.byKey(const Key('member-locked')), findsNothing);
      expect(_enabled(tester, 'team'), isFalse);
      expect(tester.widget<Text>(find.byKey(const Key('perm-why-team'))).data, 'يمنحها المالك فقط');
      expect(_enabled(tester, 'offers'), isFalse);
      expect(tester.widget<Text>(find.byKey(const Key('perm-why-offers'))).data, 'لا تحملها أنت');
      expect(_enabled(tester, 'catalog'), isTrue);
      expect(_enabled(tester, 'orders'), isTrue, reason: 'إطفاء ما يحمله العضو مسموح');
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('member-role-manager'))).onSelected, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('member-role-hr'))).onSelected, isNotNull);
    });

    testWidgets('a team holder is locked for a manager, and nobody edits themselves', (tester) async {
      final srv = _Srv();
      final me = {'id': 'SA0000001', 'role': 'manager', 'perms': _all, 'boss': false};
      final holder = BizStaff.fromJson(_member('SA0000004', 'nora', 'manager', _all, lock: 'team-holder'));
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': me});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz(role: 'manager')), member: holder, team: t));
      expect(find.text('هذا العضو يدير الفريق. يعدّله المالك فقط'), findsOneWidget);
      for (final (k, _) in bizPerms) {
        expect(_enabled(tester, k), isFalse, reason: k);
      }
      expect(find.byKey(const Key('member-save')), findsNothing);
      expect(find.byKey(const Key('member-remove')), findsNothing);

      final self = BizStaff.fromJson(_member('SA0000001', 'amr', 'manager', _all, lock: 'self'));
      await _pump(tester, srv, TeamMemberPage(key: const Key('self'), biz: Biz.fromJson(_biz(role: 'manager')), member: self, team: t));
      expect(find.text('لا يمكنك تعديل صلاحياتك بنفسك'), findsOneWidget);
      expect(_enabled(tester, 'orders'), isFalse);
      expect(find.byKey(const Key('member-save')), findsNothing);
    });

    testWidgets('a member holding a switch the manager lacks is locked (outranked)', (tester) async {
      final srv = _Srv();
      final me = {'id': 'SA0000001', 'role': 'manager', 'perms': _all.where((p) => p != 'stats').toList(), 'boss': false};
      final above = BizStaff.fromJson(_member('SA0000003', 'khalid', 'staff', ['orders', 'inbox', 'stats'], lock: 'outranked'));
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': me});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz(role: 'manager')), member: above, team: t));
      expect(find.byKey(const Key('member-locked')), findsOneWidget);
      expect(find.text('يحمل هذا العضو صلاحيات لا تحملها. يعدّله المالك'), findsOneWidget);
      for (final (k, _) in bizPerms) {
        expect(_enabled(tester, k), isFalse, reason: k);
      }
      expect(find.byKey(const Key('member-save')), findsNothing);
      expect(find.byKey(const Key('member-remove')), findsNothing);
      expect(teamErrText(const ApiException(403, 'outranked', body: {'error': 'outranked'})), 'يحمل هذا العضو صلاحيات لا تحملها. يعدّله المالك');
    });

    testWidgets('a server refusal is explained and the page stays open', (tester) async {
      final srv = _Srv()..failPatch = 403;
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': srv.me});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz()), member: t.staff.first, team: t));
      await tester.tap(find.byKey(const Key('perm-catalog')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('لا تمنح صلاحية لا تحملها: المبيعات والإحصاءات'), findsOneWidget);
      expect(find.byType(TeamMemberPage), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('remove asks first, then deletes', (tester) async {
      final srv = _Srv();
      final t = BizTeam.fromJson({'staff': srv.staff, 'me': srv.me});
      await _pump(tester, srv, TeamMemberPage(biz: Biz.fromJson(_biz()), member: t.staff.first, team: t));
      await tester.tap(find.byKey(const Key('member-remove')));
      await tester.pumpAndSettle();
      expect(srv.calls, isNot(contains('DELETE /biz/biz-cafe/team/SA0000003')));
      await tester.tap(find.byKey(const Key('member-remove-ok')));
      await tester.pumpAndSettle();
      expect(srv.calls, contains('DELETE /biz/biz-cafe/team/SA0000003'));
    });

    testWidgets('a permitted manager adds a member: manager role disabled, staff posted', (tester) async {
      final srv = _Srv()..role = 'manager'..me = {'id': 'SA0000001', 'role': 'manager', 'perms': _all, 'boss': false};
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      expect(find.text('نقل ملكية الدائرة'), findsNothing, reason: 'نقل الملكية للمالك وحده');
      await tester.tap(find.byKey(const Key('team-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-add-limit')), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-manager'))).onSelected, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-staff'))).onSelected, isNotNull);
      await tester.enterText(find.byKey(const Key('team-add-handle')), 'SA0000007');
      await tester.tap(find.byKey(const Key('team-add-ok')));
      await tester.pumpAndSettle();
      expect(srv.bodies['POST /biz/biz-cafe/team'], {'userId': 'SA0000007', 'role': 'staff'});
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a manager without stats adds a staff member: the role stays selectable and stats is sent off', (tester) async {
      final mine = _all.where((p) => p != 'stats').toList();
      final srv = _Srv()..role = 'manager'..perms = mine..me = {'id': 'SA0000001', 'role': 'manager', 'perms': mine, 'boss': false};
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      await tester.tap(find.byKey(const Key('team-add')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-staff'))).onSelected, isNotNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-staff'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-hr'))).onSelected, isNotNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-add-role-manager'))).onSelected, isNull);
      expect(tester.widget<Text>(find.byKey(const Key('team-add-start'))).data, 'يبدأ بصلاحيات: الطلبات والاستلام، رسائل العملاء');
      expect(tester.widget<Text>(find.byKey(const Key('team-add-dropped'))).data, contains('المبيعات والإحصاءات'));
      await tester.enterText(find.byKey(const Key('team-add-handle')), 'SA0000007');
      await tester.tap(find.byKey(const Key('team-add-ok')));
      await tester.pumpAndSettle();
      expect(srv.bodies['POST /biz/biz-cafe/team'], {'userId': 'SA0000007', 'role': 'staff', 'perms': {'stats': false}});
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    test('grantable roles: one remaining switch is enough, an empty preset is not, manager is owner-only', () {
      BizTeam team(List<String> perms, {bool boss = false}) => BizTeam.fromJson({'staff': const [], 'me': {'id': 'SA0000001', 'role': 'manager', 'perms': perms, 'boss': boss}});
      final noStats = team(_all.where((p) => p != 'stats').toList());
      expect(noStats.startPerms('staff'), ['orders', 'inbox']);
      expect(noStats.canGrantRole('staff') && noStats.canGrantRole('hr') && !noStats.canGrantRole('manager'), isTrue);
      final teamOnly = team(['team']);
      expect(teamOnly.canGrantRole('staff') || teamOnly.canGrantRole('hr') || teamOnly.canGrantRole('manager'), isFalse);
      expect(team(const [], boss: true).canGrantRole('manager'), isTrue);
      final o = BizOrder.fromJson({'id': 'o1', 'status': 'used', 'code': 'NAS-1', 'total': null, 'amountHidden': true, 'payment': 'wallet'});
      expect(o.amountHidden && o.total == 0 && o.payment == 'wallet', isTrue);
    });

    testWidgets('old server without «me»: the owner still manages the team', (tester) async {
      final srv = _Srv()..me = null;
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      expect(find.byKey(const Key('team-add')), findsOneWidget);
    });
  });

  group('activity log', () {
    testWidgets('newest first with the actor, then loads older rows', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const BizActivityPage(bizId: 'biz-cafe'));
      expect(find.text('سجل النشاط'), findsOneWidget);
      expect(find.text('غيّر سعر «لاتيه» من 15 ر.س إلى 18 ر.س'), findsOneWidget);
      expect(find.text('nora'), findsOneWidget);
      expect(find.text('عضو سابق'), findsOneWidget, reason: 'فاعل حُذف حسابه');
      expect(find.textContaining('يُحفظ 180 يوماً'), findsOneWidget);
      expect(find.byKey(const Key('activity-7')), findsNothing);
      await tester.tap(find.byKey(const Key('activity-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-7')), findsOneWidget);
      expect(find.byKey(const Key('activity-more')), findsNothing);
      expect(srv.calls.where((c) => c == 'GET /biz/biz-cafe/activity').length, 2);
    });

    testWidgets('opens from the team tab', (tester) async {
      final srv = _Srv();
      await _pump(tester, srv, const BusinessDashboardPage(id: 'biz-cafe', initialTab: 6));
      await tester.tap(find.byKey(const Key('team-activity')));
      await tester.pumpAndSettle();
      expect(find.byType(BizActivityPage), findsOneWidget);
      expect(find.byKey(const Key('activity-list')), findsOneWidget);
    });
  });
}
