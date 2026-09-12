import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:naslook/api/client.dart';
import 'package:naslook/api/models.dart';
import 'package:naslook/api/session.dart';
import 'package:naslook/pages/profile/user_profile_page.dart';
import 'package:naslook/state/app_state.dart';
import 'package:naslook/state/providers.dart';
import 'package:naslook/ui/profile_avatar.dart';

class _SignedIn extends AppStateNotifier {
  _SignedIn(super.api, super.store) {
    state = const AppState(status: AuthStatus.signedIn, session: Session(token: 't', user: SessionUser(id: 'SA0000001', nickname: 'amr')));
  }
}

class _Srv {
  final calls = <String>[];
  bool private = false;
  final contacts = <String>[];
  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (req.method == 'GET' && path == '/profiles/SA0000002') {
      if (private) return _json({'error': 'forbidden'}, 403);
      return _json({
        'id': 'SA0000002', 'nickname': 'sara', 'bio': 'أحب القهوة', 'skills': ['تصوير'], 'hobbies': ['قراءة'], 'lookingFor': [],
        'offerings': [{'name': 'قهوة مختصة', 'description': 'حبوب'}], 'isPublic': true, 'createdAt': '2025-03-01T00:00:00Z',
      });
    }
    if (req.method == 'GET' && path == '/profiles/SA0000001') return _json({'id': 'SA0000001', 'nickname': 'amr'});
    if (path.startsWith('/presence/')) return _json({'online': true});
    if (req.method == 'GET' && path == '/contacts') return _json([for (final c in contacts) {'id': c, 'nickname': 'x'}]);
    if (req.method == 'POST' && path == '/contacts') { contacts.add((jsonDecode(req.body) as Map)['contactId'] as String); return _json({'ok': true}); }
    return _json({'error': 'not-found'}, 404);
  }
}

Future<void> _pump(WidgetTester tester, _Srv srv, Widget home) async {
  final api = ApiClient(baseUrl: 'https://test.local', httpClient: MockClient(srv.handle));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(null),
      appStateProvider.overrideWith((ref) => _SignedIn(api, SessionStore())),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

const _sara = Person(id: 'SA0000002', nickname: 'sara');

void main() {
  testWidgets('tapping a ProfileAvatar opens the user profile page', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: Center(child: ProfileAvatar(person: _sara, size: 40))));
    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(srv.calls, contains('GET /profiles/SA0000002'));
    expect(find.text('أحب القهوة'), findsOneWidget);
    expect(find.text('تصوير'), findsOneWidget);
    expect(find.text('قهوة مختصة'), findsOneWidget);
    expect(find.text('مراسلة'), findsOneWidget);
    expect(find.text('إضافة صديق'), findsOneWidget);
  });

  testWidgets('adding a friend from the profile calls the contacts API', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const UserProfilePage(person: _sara));
    await tester.tap(find.text('إضافة صديق'));
    await tester.pumpAndSettle();
    expect(srv.contacts, ['SA0000002']);
    expect(find.text('صديق'), findsOneWidget);
  });

  testWidgets('a private profile shows a locked state instead of an error', (tester) async {
    final srv = _Srv()..private = true;
    await _pump(tester, srv, const UserProfilePage(person: _sara));
    expect(find.text('ملف خاص'), findsOneWidget);
    expect(find.text('مراسلة'), findsOneWidget);
  });

  testWidgets('my own profile points to MySpace instead of chat/add buttons', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const UserProfilePage(person: Person(id: 'SA0000001', nickname: 'amr')));
    expect(find.textContaining('هذا ملفك'), findsOneWidget);
    expect(find.text('إضافة صديق'), findsNothing);
  });

  testWidgets('a person without an id is not tappable', (tester) async {
    final srv = _Srv();
    await _pump(tester, srv, const Scaffold(body: ProfileAvatar(person: Person(id: '', nickname: 'ghost'))));
    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsNothing);
  });
}
