// البحث المحفوظ: زر «نبّهني عند ظهور جديد» في صفحة البحث، وصفحة بحوثي المحفوظة (تفعيل/إيقاف، حذف، فتح البحث).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/saved_search_api.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/myspace/saved_searches_page.dart';
import 'package:naslook/pages/search/search_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/notify_providers.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/state/search_providers.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

const _s1 = 'aaaaaaaa-0000-4000-8000-000000000501';

class _Srv {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final saved = <Map<String, dynamic>>[];
  int seq = 10;
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    if ((req.headers['content-type'] ?? '').contains('json') && req.body.startsWith('{')) bodies[key] = jsonDecode(req.body) as Map<String, dynamic>;
    if (key == 'GET /search') return _json({'q': req.url.queryParameters['q'] ?? ''});
    if (key == 'GET /searches/saved') return _json(saved);
    if (key == 'POST /searches/saved') {
      final b = bodies[key]!;
      final s = {'id': 'aaaaaaaa-0000-4000-8000-0000000005${++seq}', 'q': b['q'], 'types': b['types'], 'radiusKm': b['radiusKm'], 'active': true, 'matches': 0};
      saved.insert(0, s);
      return _json(s);
    }
    final m = RegExp(r'^(PATCH|DELETE) /searches/saved/([\w-]+)$').firstMatch(key);
    if (m != null) {
      final i = saved.indexWhere((x) => x['id'] == m.group(2));
      if (i < 0) return _json({'error': 'not-found'}, 404);
      if (m.group(1) == 'DELETE') {
        saved.removeAt(i);
        return _json({'ok': true});
      }
      saved[i] = {...saved[i], ...bodies[key]!};
      return _json(saved[i]);
    }
    if (key == 'GET /notify/unread') return _json({'unread': 0});
    if (key == 'GET /search/recent' || key == 'GET /search/discover') return _json({});
    return _json({'error': 'not-found'}, 404);
  }
}

Future<_Srv> _pump(WidgetTester tester, Widget home, {_Srv? srv}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = srv ?? _Srv();
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(s.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
      notifyPollIntervalProvider.overrideWithValue(null),
      userLocationProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return s;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  test('savedTypesFor maps search chips to watchable types', () {
    expect(savedTypesFor('market'), ['market']);
    expect(savedTypesFor('events'), ['events']);
    expect(savedTypesFor('people'), isNull);
    expect(savedTypesFor(null), isNull);
    expect(const SavedSearch(id: 'x', q: 'شقة', types: ['market'], radiusKm: 5).scopeLabel, 'السوق · ضمن 5 كم');
    expect(const SavedSearch(id: 'x', q: 'شقة').scopeLabel, 'كل الأنواع');
  });

  testWidgets('search page offers to save the query anywhere, then shows it as saved', (tester) async {
    final srv = await _pump(tester, const SearchPage(initialQuery: 'شقة للإيجار'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('save-search')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-search')));
    await _settle(tester);
    expect(find.text('في أي مكان'), findsOneWidget);
    await tester.tap(find.text('في أي مكان'));
    await _settle(tester);
    expect(srv.bodies['POST /searches/saved'], {'q': 'شقة للإيجار'});
    expect(find.textContaining('سننبّهك'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-search')), findsNothing);
    expect(find.textContaining('ستصلك تنبيهات'), findsOneWidget);
  });

  testWidgets('a radius needs a location; without one the user is told and nothing is saved', (tester) async {
    final srv = await _pump(tester, const SearchPage(initialQuery: 'قهوة'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('save-search')));
    await _settle(tester);
    await tester.tap(find.text('ضمن 5 كم من موقعي'));
    await _settle(tester);
    expect(srv.bodies.containsKey('POST /searches/saved'), isFalse);
    expect(find.textContaining('فعّل الموقع'), findsOneWidget);
  });

  testWidgets('saved searches page toggles, deletes and opens the search', (tester) async {
    final srv = _Srv()
      ..saved.addAll([
        {'id': _s1, 'q': 'شقة للإيجار', 'types': null, 'radiusKm': 10, 'active': true, 'matches': 2, 'lastMatchAt': DateTime.now().toUtc().toIso8601String()},
        {'id': 'aaaaaaaa-0000-4000-8000-000000000502', 'q': 'قهوة', 'types': ['events'], 'radiusKm': null, 'active': false, 'matches': 0},
      ]);
    await _pump(tester, const SavedSearchesPage(), srv: srv);
    await _settle(tester);
    expect(find.text('«شقة للإيجار»'), findsOneWidget);
    expect(find.text('كل الأنواع · ضمن 10 كم'), findsOneWidget);
    expect(find.text('فعاليات'), findsOneWidget);
    expect(find.textContaining('2 مطابقة'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await _settle(tester);
    expect(srv.bodies['PATCH /searches/saved/$_s1'], {'active': false});
    await tester.tap(find.byTooltip('حذف').last);
    await _settle(tester);
    expect(srv.calls, contains('DELETE /searches/saved/aaaaaaaa-0000-4000-8000-000000000502'));
    expect(find.text('«قهوة»'), findsNothing);
    await tester.tap(find.text('«شقة للإيجار»'));
    await _settle(tester);
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.widgetWithText(TextField, 'شقة للإيجار'), findsOneWidget);
  });
}
