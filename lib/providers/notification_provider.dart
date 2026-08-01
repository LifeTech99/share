// lib/providers/notification_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/database_helper.dart';
import '../main.dart';

enum LogEventType {
  boundaryCreated,
  boundaryAdjusted,
  boundaryDeleted,
  mapDownloaded,
  boundaryBreached,
  deviceConnected,
  deviceDisconnected,
}

class LogEvent {
  final LogEventType type;
  final String message;
  final DateTime timestamp;

  LogEvent({required this.type, required this.message, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class NotificationNotifier extends Notifier<List<LogEvent>> {
  @override
  List<LogEvent> build() {
    _loadLogs();
    return [];
  }

  Future<void> _loadLogs() async {
    final rows = await DatabaseHelper.instance.getLogs();

    state = rows.map((row) {
      return LogEvent(
        type: LogEventType.values.firstWhere((e) => e.name == row['type']),
        message: row['message'] as String,
        timestamp: DateTime.parse(row['timestamp'] as String),
      );
    }).toList();
  }

  void log(LogEventType type, String message) async {
  final event = LogEvent(type: type, message: message);

  state = [...state, event];

  await DatabaseHelper.instance.insertLog(
    type.name,
    message,
    event.timestamp,
  );

  const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'livestock_channel',
    'Livestock Alerts',
    channelDescription: 'Notifications for livestock events',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails notificationDetails =
      NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'Livestock Tracker',
    message,
    notificationDetails,
  );
}

  void logBoundaryCreated() {
    log(LogEventType.boundaryCreated, "Boundary created");
  }
}

final notificationProvider =
    NotifierProvider<NotificationNotifier, List<LogEvent>>(
      NotificationNotifier.new,
    );
