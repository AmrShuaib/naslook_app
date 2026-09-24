import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// اتصال WebSocket بخادم Naslife: أول إطار {type:"auth", token}، ثم أحداث JSON.
///
/// يبث أيضاً حدثين محليين لا يأتيان من الخادم حتى تعيد الصفحات مزامنة بياناتها:
///  - {event: "_connected"}    عند نجاح الاتصال (أول مرة وبعد كل انقطاع)
///  - {event: "_disconnected"} عند انقطاعه
class NaslifeSocket {
  final String url;
  final String token;
  WebSocketChannel? _ch;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _ping;
  Timer? _reconnect;
  bool _closed = false;
  bool _wasConnected = false;
  int _attempt = 0;
  final _lastTyping = <String, DateTime>{};

  /// أقل فاصل بين إشعارَي "يكتب" لنفس الشخص.
  static const typingInterval = Duration(milliseconds: 2500);

  NaslifeSocket({required this.url, required this.token});

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get connected => _wasConnected;

  void connect() {
    if (_closed) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _ch = ch;
      ch.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      ch.ready.then((_) {
        if (_closed || _ch != ch) return;
        _attempt = 0;
        _wasConnected = true;
        _events.add({'event': '_connected'});
      }).catchError((_) {});
      // قناة استُبدلت (reconnectNow) لا تُطلق إعادة اتصال عند إغلاقها
      ch.stream.listen((raw) {
        try {
          final j = jsonDecode(raw.toString());
          if (j is Map) _events.add(Map<String, dynamic>.from(j));
        } catch (_) {}
      }, onDone: () { if (_ch == ch) _onLost(); }, onError: (_) { if (_ch == ch) _onLost(); });
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => send({'type': 'ping'}));
    } catch (_) {
      _onLost();
    }
  }

  void _onLost() {
    if (_closed) return;
    if (_wasConnected) {
      _wasConnected = false;
      _events.add({'event': '_disconnected'});
    }
    _reconnect?.cancel();
    // تراجع أسّي: 2، 4، 8 … حتى 30 ثانية
    final delay = Duration(seconds: (2 << _attempt).clamp(2, 30));
    _attempt = (_attempt + 1).clamp(0, 4);
    _reconnect = Timer(delay, connect);
  }

  /// إعادة اتصال فورية بلا انتظار التراجع الأسّي: iOS يعلّق المقابس في الخلفية، فتُستدعى عند عودة التطبيق للواجهة.
  /// [force] يعيد الاتصال حتى لو بدا المقبس متصلاً (قد يكون ميتاً بصمت بعد التعليق).
  void reconnectNow({bool force = false}) {
    if (_closed) return;
    if (_wasConnected && !force) return;
    _attempt = 0;
    _reconnect?.cancel();
    _reconnect = null;
    final old = _ch;
    // نفصل القناة القديمة أولاً فلا يطلق إغلاقها _onLost ولا يجدول إعادة اتصال ثانية
    _ch = null;
    if (_wasConnected) {
      _wasConnected = false;
      _events.add({'event': '_disconnected'});
    }
    try {
      old?.sink.close();
    } catch (_) {}
    connect();
  }

  void send(Map<String, dynamic> msg) {
    try {
      _ch?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  /// إشعار "يكتب" مع تقييد زمني حتى لا يُرسل مع كل حرف.
  void typing(String to) {
    final now = DateTime.now();
    final last = _lastTyping[to];
    if (last != null && now.difference(last) < typingInterval) return;
    _lastTyping[to] = now;
    send({'type': 'typing', 'to': to});
  }

  void close() {
    _closed = true;
    _ping?.cancel();
    _reconnect?.cancel();
    _ch?.sink.close();
    _events.close();
  }
}
