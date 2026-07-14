import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin WebSocket wrapper with JSON messages, auto-reconnect (dashboard only),
/// and a broadcast stream of decoded messages.
class SocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _closed = false;
  final bool autoReconnect;
  final String path; // e.g. /ws/dashboard or /ws/machine/xxx

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  Stream<bool> get connectionStatus => _statusController.stream;
  bool _connected = false;
  bool get isConnected => _connected;

  SocketService(this.path, {this.autoReconnect = false});

  String get _wsUrl {
    final base = Uri.base;
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${base.host}${base.hasPort ? ':${base.port}' : ''}$path';
  }

  void connect() {
    if (_closed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _sub = _channel!.stream.listen(
        (raw) {
          if (!_connected) {
            _connected = true;
            _statusController.add(true);
          }
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller.add(msg);
          } catch (_) {}
        },
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        send({'type': 'ping'});
      });
    } catch (_) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    if (_connected) {
      _connected = false;
      _statusController.add(false);
    }
    _pingTimer?.cancel();
    if (autoReconnect && !_closed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 2), connect);
    }
  }

  void send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void dispose() {
    _closed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
    _statusController.close();
  }
}
