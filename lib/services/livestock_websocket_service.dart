import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/gps_data.dart';

class LivestockWebSocketService {
  WebSocket? _socket;

  final StreamController<GpsData> _dataController =
      StreamController<GpsData>.broadcast();

  Stream<GpsData> get dataStream => _dataController.stream;

  bool get isConnected => _socket != null;

  Future<bool> connect({
    String host = "192.168.4.1",
    int port = 81,
  }) async {
    if (_socket != null) {
      return true;
    }

    try {
      final url = "ws://$host:$port/";

      print("Connecting to livestock WebSocket...");
      print("URL: $url");

      _socket = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 5));

      print("Livestock WebSocket connected");

      _socket!.listen(
        (message) {

          print("================================");
          print("RAW ESP MESSAGE:");
          print(message);
          print("================================");

          try {

            final json =
                jsonDecode(message)
                    as Map<String, dynamic>;

            final data =
                GpsData.fromJson(json);

            _dataController.add(data);

          } catch (e) {

            print(
              "Invalid livestock data: $e"
            );

          }
        },
      );

      return true;
    } catch (e) {
      print("WebSocket connection failed: $e");

      _socket = null;

      return false;
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}