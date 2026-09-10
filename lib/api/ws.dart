import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// اتصال WebSocket بخادم Naslife: أول إطار {type:"auth", token}، ثم أحداث JSON.
class NaslifeSocket {
  final String url;
  final String token;
  WebSocketChannel? _ch;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _ping;
  Timer? _reconnect;
  bool _closed = false;

  NaslifeSocket({required this.url, required this.token});

  Stream<Map<String, dynamic>> get events => _events.stream;

  void connect() {
    if (_closed) return;
    try {
      _ch = WebSocketChannel.connect(Uri.parse(url));
      _ch!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _ch!.stream.listen((raw) {
        try {
          final j = jsonDecode(raw.toString());
          if (j is Map) _events.add(Map<String, dynamic>.from(j));
        } catch (_) {}
      }, onDone: _scheduleReconnect, onError: (_) => _scheduleReconnect());
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => send({'type': 'ping'}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), connect);
  }

  void send(Map<String, dynamic> msg) {
    try {
      _ch?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void typing(String to) => send({'type': 'typing', 'to': to});

  void close() {
    _closed = true;
    _ping?.cancel();
    _reconnect?.cancel();
    _ch?.sink.close();
    _events.close();
  }
}
