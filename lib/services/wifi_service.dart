import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WifiService {
  static const String host = '192.168.4.1';
  static const int port = 8080;

  Socket? _socket;

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  Stream<String> get messages => _messageController.stream;

  bool get isConnected => _socket != null;

  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      _socket!.listen(
        (data) {
          final msg = utf8.decode(data).trim();
          _messageController.add(msg);
        },
        onDone: disconnect,
        onError: (_) => disconnect(),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  void send(String command) {
    if (_socket != null) {
      _socket!.write("$command\n");
    }
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}