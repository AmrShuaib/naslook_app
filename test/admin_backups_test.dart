// بطاقة «النسخ الاحتياطي» في نظرة عامة الإدارة (server/backups.js): النموذج BackupsInfo، وثلاث حالات في الشاشة: لم يُثبَّت
// (تلميح التثبيت بلا سطر تمرين)، سليم وحديث مع نسخة خارج الخادم وتمرين ناجح (بلا تلميح كهرماني)، وفاشل بنص الخطأ بلا تمرين
// وبلا نسخة خارج الخادم (تلميح الضبط)، ثم نسخة ناجحة لكنها قديمة (نص أحمر) وتمرين فاشل.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/admin_api.dart';
import 'package:naslook/api/client.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/core/app_theme.dart';
import 'package:naslook/pages/admin/admin_overview.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _overview() => {
      'users': {'total': 120, 'new7': 9, 'suspended': 1, 'admins': 1},
      'orders7': {'count': 14, 'revenue': 250000},
      'circles': {'active': 22, 'inactive': 0, 'owned': 2, 'claims': 1},
      'reports': {'open': 2, 'available': true},
      'wallets': {'accounts': 40, 'balance': 990000},
      'daily': [for (var i = 13; i >= 0; i--) {'day': DateTime.now().subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'users': i % 3, 'orders': i % 4, 'revenue': (i % 4) * 1000}],
      'server': {'node': 'v22', 'uptimeSec': 600, 'tables': ['users']},
    };

/// رد /adminapi/backups كما يبنيه الخادم: الحالة الخام من last.json مع الحقول المحسوبة.
Map<String, dynamic> _backups({bool installed = true, bool ok = true, double ageHours = 5, bool stale = false, String? error, bool offsite = true, String? offsiteError, Map<String, dynamic>? drill, bool drillStale = true}) => {
      'installed': installed,
      'status': installed
          ? {
              'version': 1, 'startedAt': _iso(Duration(hours: ageHours.round())), 'finishedAt': _iso(Duration(hours: ageHours.round())), 'ok': ok, 'error': error, 'durationSec': 41,
              'db': {'file': '/opt/naslife/backups/db/naslife-20261021-0330.dump', 'bytes': 38 * 1048576, 'sha256': 'ab12'},
              'media': {'source': '/opt/naslife/media', 'dir': '/opt/naslife/backups/media/20261021-0330', 'files': 1840, 'bytes': 2100000000},
              'config': {'files': ['auth-key', 'Caddyfile']},
              'offsite': {'kind': offsite ? 'rclone' : 'none', 'ok': offsite, 'error': offsiteError},
              'kept': {'dumps': 14, 'mediaSnapshots': 7},
              'drill': drill,
            }
          : null,
      'ageHours': installed ? ageHours : null,
      'stale': stale,
      'offsite': offsite,
      'offsiteError': offsiteError,
      'drill': drill == null ? null : {'at': drill['at'], 'ok': drill['ok'], 'ageDays': drill['ageDays'], 'error': drill['error']},
      'drillStale': drillStale,
      'dumps': installed ? [{'file': 'naslife-20261021-0330.dump', 'bytes': 38 * 1048576, 'at': _iso(const Duration(hours: 5))}] : [],
      'dir': '/opt/naslife/backups',
      'error': null,
    };

class _Srv {
  final calls = <String>[];
  Map<String, dynamic> backups = _backups();
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});
  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /adminapi/overview': return _json(_overview());
      case 'GET /adminapi/backups': return _json(backups);
    }
    if (req.url.path.startsWith('/presence/')) return _json({'online': false});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv) async {
  // شاشة طويلة: القائمة كسولة والبطاقة في أسفل الصفحة
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api), socketProvider.overrideWithValue(null), appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore()))],
    child: MaterialApp(home: Scaffold(body: AdminOverviewPage(onGo: (_) {}))),
  ));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? '';
Color? _color(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).style?.color;

void main() {
  test('BackupsInfo parses the server shape', () {
    final i = BackupsInfo.fromJson(_backups(ageHours: 7.4, drill: {'at': _iso(const Duration(days: 3)), 'ok': true, 'ageDays': 3.2, 'error': null}, drillStale: false));
    expect(i.installed, isTrue);
    expect(i.ok, isTrue);
    expect(i.stale, isFalse);
    expect(i.ageHours, 7.4);
    expect(i.dbBytes, 38 * 1048576);
    expect(i.dbSizeText, '38.0 م.ب');
    expect(i.mediaFiles, 1840);
    expect(i.dumpsKept, 14);
    expect(i.offsite, isTrue);
    expect(i.drillOk, isTrue);
    expect(i.drillAgeDays, 3);
    expect(i.drillStale, isFalse);
    expect(i.lastAt, isNotNull);
    expect(i.error, isNull);
    final none = BackupsInfo.fromJson(_backups(installed: false, stale: true, offsite: false));
    expect(none.installed, isFalse);
    expect(none.ok, isFalse);
    expect(none.stale, isTrue);
    expect(none.ageHours, isNull);
    expect(none.drillOk, isNull);
    expect(none.drillStale, isTrue);
    final failed = BackupsInfo.fromJson(_backups(ok: false, stale: true, error: 'pg_dump failed (exit 1): connection refused', offsite: false));
    expect(failed.ok, isFalse);
    expect(failed.error, 'pg_dump failed (exit 1): connection refused');
    final unreadable = BackupsInfo.fromJson({'installed': true, 'status': null, 'stale': true, 'error': 'status-unreadable: Unexpected token'});
    expect(unreadable.installed, isTrue);
    expect(unreadable.error, startsWith('status-unreadable'));
  });

  testWidgets('not installed → setup hint, no drill line, no offsite hint', (tester) async {
    final srv = _Srv()..backups = _backups(installed: false, stale: true, offsite: false);
    await _pump(tester, srv);
    expect(srv.calls, contains('GET /adminapi/backups'));
    expect(find.text('النسخ الاحتياطي'), findsOneWidget);
    expect(find.byKey(const Key('backup-card')), findsOneWidget);
    expect(_text(tester, 'backup-state'), 'لم يُثبَّت بعد. شغّل server/install-backup.sh على الخادم مرة واحدة (docs/ops-backup.md)');
    expect(_color(tester, 'backup-state'), Joy.warning);
    expect(find.byKey(const Key('backup-drill')), findsNothing);
    expect(find.byKey(const Key('backup-offsite-hint')), findsNothing);
  });

  testWidgets('fresh backup with an offsite copy and a recent drill', (tester) async {
    final srv = _Srv()..backups = _backups(ageHours: 5, drill: {'at': _iso(const Duration(days: 3)), 'ok': true, 'ageDays': 3, 'error': null}, drillStale: false);
    await _pump(tester, srv);
    expect(_text(tester, 'backup-state'), 'آخر نسخة قبل 5 ساعة · قاعدة البيانات 38.0 م.ب · الوسائط 1840 ملفاً · خارج الخادم: نعم');
    expect(_color(tester, 'backup-state'), Joy.text);
    expect(_text(tester, 'backup-drill'), 'آخر تمرين استعادة: ناجح قبل 3 يوماً');
    expect(_color(tester, 'backup-drill'), Joy.textMuted);
    expect(find.descendant(of: find.byKey(const Key('backup-card')), matching: find.text('14')), findsOneWidget); // نسخ القاعدة المحفوظة
    expect(find.byKey(const Key('backup-offsite-hint')), findsNothing);
  });

  testWidgets('failed run → red error text, no drill yet, amber offsite hint', (tester) async {
    final srv = _Srv()..backups = _backups(ok: false, stale: true, ageHours: 9, error: 'pg_dump failed (exit 1): FATAL: database "naslife" does not exist', offsite: false);
    await _pump(tester, srv);
    expect(_text(tester, 'backup-state'), 'فشلت آخر نسخة (قبل 9 ساعة): pg_dump failed (exit 1): FATAL: database "naslife" does not exist');
    expect(_color(tester, 'backup-state'), Joy.danger);
    expect(_text(tester, 'backup-drill'), 'لم يُجرَ تمرين استعادة بعد');
    expect(_color(tester, 'backup-drill'), Joy.warning);
    expect(_text(tester, 'backup-offsite-hint'), 'لا نسخة خارج الخادم: اضبط BACKUP_RCLONE_REMOTE أو BACKUP_SSH_TARGET');
  });

  testWidgets('stale but successful backup, failed offsite sync and a failed old drill', (tester) async {
    final srv = _Srv()..backups = _backups(ageHours: 52, stale: true, offsite: false, offsiteError: 'rclone: couldn\'t connect', drill: {'at': _iso(const Duration(days: 12)), 'ok': false, 'ageDays': 12, 'error': 'users mismatch: restored 90, live 120'}, drillStale: true);
    await _pump(tester, srv);
    expect(_text(tester, 'backup-state'), startsWith('آخر نسخة ناجحة قديمة (قبل 52 ساعة)'));
    expect(_color(tester, 'backup-state'), Joy.danger);
    expect(_text(tester, 'backup-drill'), 'آخر تمرين استعادة: فشل قبل 12 يوماً · users mismatch: restored 90, live 120');
    expect(_color(tester, 'backup-drill'), Joy.danger);
    expect(_text(tester, 'backup-offsite-hint'), 'فشل النسخ خارج الخادم: rclone: couldn\'t connect');
  });
}
