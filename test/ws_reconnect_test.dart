// إعادة الاتصال الفورية عند عودة التطبيق من الخلفية: اتصال جديد واحد بلا انتظار التراجع الأسّي، ولا اتصال مكرر من إغلاق القديم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/api/ws.dart';

void main() {
  test('reconnectNow opens exactly one fresh connection and emits disconnected/connected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    final sockets = <WebSocket>[];
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      connections++;
      sockets.add(ws);
      ws.listen((_) {});
    });
    final s = NaslifeSocket(url: 'ws://127.0.0.1:${server.port}/ws', token: 't');
    final events = <String>[];
    final sub = s.events.listen((e) => events.add('${e['event']}'));
    s.connect();
    await _until(() => s.connected);
    expect(connections, 1);

    s.reconnectNow(); // متصل: لا شيء بلا force
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connections, 1);

    s.reconnectNow(force: true);
    await _until(() => connections == 2 && s.connected);
    // مهلة تتجاوز أول تراجع (ثانيتان) لو أطلق إغلاق القناة القديمة إعادة اتصال إضافية
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(connections, 2, reason: 'إغلاق القناة المستبدلة لا يجدول اتصالاً ثالثاً');
    expect(events, containsAllInOrder(['_connected', '_disconnected', '_connected']));

    s.close();
    await sub.cancel();
    for (final w in sockets) {
      await w.close();
    }
    await server.close(force: true);
  });
}

Future<void> _until(bool Function() ok) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timeout');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
