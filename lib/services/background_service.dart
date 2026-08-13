import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';

import '../database/database_helper.dart';
import '../providers/notification_provider.dart';
import '../providers/provider_container.dart';
import 'package:livestock_tracker/services/geofence_service.dart';
import 'wifi_service.dart';

final Map<String, bool> _previousGeofenceState = {};
final Map<String, DateTime> _onlineAnimals = {};
final Map<String, int> _lastBatteryNotification = {};

class BackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // ------------------------------------------------------------
  // SHOW ALERT
  // ------------------------------------------------------------

  static Future<void> showAlert({
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      'livestock_alerts',
      'Livestock Alerts',
      channelDescription: 'Geofence alerts',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: android),
    );
  }

  // ------------------------------------------------------------
  // INITIALIZE BACKGROUND SERVICE
  // ------------------------------------------------------------

  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      const InitializationSettings(android: android),
    );

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: 100,
        initialNotificationTitle: 'Livestock Tracker',
        initialNotificationContent: 'Monitoring livestock...',
      ),
      iosConfiguration: IosConfiguration(),
    );
  }

  // ------------------------------------------------------------
  // START SERVICE
  // ------------------------------------------------------------

  static Future<void> start() async {
    final started = await _service.startService();

    debugPrint('Background service started: $started');
  }

  // ------------------------------------------------------------
  // STOP SERVICE
  // ------------------------------------------------------------

  static Future<void> stop() async {
    _service.invoke('stop');
  }
}

// ============================================================================
// BACKGROUND SERVICE ENTRY POINT
// ============================================================================

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  debugPrint('onStart() called');

  // ------------------------------------------------------------
  // ANDROID FOREGROUND SERVICE
  // ------------------------------------------------------------

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    debugPrint('Foreground service requested');

    await service.setForegroundNotificationInfo(
      title: 'Livestock Tracker',
      content: '0 animals online',
    );

    debugPrint('Foreground notification initialized');
  }

  // ------------------------------------------------------------
  // WIFI SERVICE
  // ------------------------------------------------------------

  final wifi = WifiService();

  // Initial connection attempt.
  await connectToEsp(wifi);

  // ============================================================
  // TIMER 1 — ESP RECONNECT
  // ============================================================
  //
  // This timer ONLY handles ESP connection.
  //
  // It checks every 5 seconds whether the ESP is connected.
  //
  // IMPORTANT:
  // Do NOT put another Timer.periodic inside this timer.
  //
  // ============================================================

  final reconnectTimer = Timer.periodic(const Duration(seconds: 5), (
    timer,
  ) async {
    try {
      if (!wifi.isConnected) {
        debugPrint('ESP disconnected. Reconnecting...');

        await connectToEsp(wifi);
      }
    } catch (e, stackTrace) {
      debugPrint('Reconnect timer error: $e');

      debugPrint('$stackTrace');
    }
  });

  // ============================================================
  // TIMER 2 — ONLINE ANIMAL CLEANUP
  // ============================================================
  //
  // This timer ONLY handles online animal timeout.
  //
  // Every 10 seconds:
  //
  // - Check the last-seen time of every animal.
  // - Remove animals not seen for more than 30 seconds.
  // - Update foreground notification if the count changed.
  //
  // ============================================================

  final cleanupTimer = Timer.periodic(const Duration(seconds: 10), (
    timer,
  ) async {
    try {
      final now = DateTime.now();

      final before = _onlineAnimals.length;

      _onlineAnimals.removeWhere((deviceId, lastSeen) {
        final elapsed = now.difference(lastSeen).inSeconds;

        return elapsed > 30;
      });

      final after = _onlineAnimals.length;

      // --------------------------------------------------------
      // LOG ONLINE ANIMAL COUNT
      // --------------------------------------------------------

      debugPrint('Online animals: $after');

      // --------------------------------------------------------
      // UPDATE FOREGROUND NOTIFICATION
      // ONLY WHEN COUNT CHANGED
      // --------------------------------------------------------

      if (after != before && service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Livestock Tracker',
          content: '$after animals online',
        );

        debugPrint(
          'Foreground notification updated: '
          '$after animals online',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Cleanup timer error: $e');

      debugPrint('$stackTrace');
    }
  });

  // ============================================================
  // STOP SERVICE
  // ============================================================

  service.on('stop').listen((event) {
    debugPrint('Stopping background service...');

    // Cancel both timers.
    reconnectTimer.cancel();
    cleanupTimer.cancel();

    debugPrint('Reconnect timer cancelled');

    debugPrint('Cleanup timer cancelled');

    service.stopSelf();
  });

  // ============================================================
  // WIFI MESSAGE LISTENER
  // ============================================================

  wifi.messages.listen(
    (json) async {
      try {
        debugPrint('Received ESP message: $json');

        // --------------------------------------------------------
        // DEVICE ID
        // --------------------------------------------------------

        final deviceId = json['device_id'];

        if (deviceId == null) {
          debugPrint('Received message without device_id');

          return;
        }

        final String animalId = deviceId.toString();

        // --------------------------------------------------------
        // UPDATE ONLINE ANIMAL
        // --------------------------------------------------------

        final before = _onlineAnimals.length;

        _onlineAnimals[animalId] = DateTime.now();

        final after = _onlineAnimals.length;

        // --------------------------------------------------------
        // UPDATE FOREGROUND NOTIFICATION
        // ONLY WHEN A NEW ANIMAL COMES ONLINE
        // --------------------------------------------------------

        if (after != before && service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'Livestock Tracker',
            content: '$after animals online',
          );

          debugPrint(
            'Foreground notification updated: '
            '$after animals online',
          );
        }

        // --------------------------------------------------------
        // GPS DATA
        // --------------------------------------------------------

        final latitude = (json['latitude'] as num).toDouble();

        final longitude = (json['longitude'] as num).toDouble();

        // --------------------------------------------------------
        // BATTERY
        // --------------------------------------------------------

        final battery = (json['battery'] as num).toInt();

        // --------------------------------------------------------
        // LOW BATTERY NOTIFICATION
        // --------------------------------------------------------

        final lastBattery = _lastBatteryNotification[animalId];

        if (battery <= 15 && lastBattery != battery) {
          _lastBatteryNotification[animalId] = battery;

          providerContainer
              .read(notificationProvider.notifier)
              .log(LogEventType.battery, '$animalId battery is $battery%');

          debugPrint(
            'Low battery notification: '
            '$animalId = $battery%',
          );
        }

        // --------------------------------------------------------
        // TIMESTAMP
        // --------------------------------------------------------

        final timestamp = json['timestamp'] as String;

        // --------------------------------------------------------
        // GET GEOFENCE
        // --------------------------------------------------------

        final fence = await DatabaseHelper.instance.getGeofence();

        if (fence == null) {
          debugPrint('No geofence configured.');

          return;
        }

        final geofenceId = fence['id'] as int;

        // --------------------------------------------------------
        // GET GEOFENCE POLYGON
        // --------------------------------------------------------

        final polygon = await DatabaseHelper.instance.getGeofencePoints(
          geofenceId,
        );

        // --------------------------------------------------------
        // POINT-IN-POLYGON CHECK
        // --------------------------------------------------------

        final inside = GeofenceUtils.isPointInsidePolygon(
          LatLng(latitude, longitude),
          polygon,
        );

        final geofenceStatus = inside ? 'inside' : 'outside';

        debugPrint(
          '$animalId is $geofenceStatus '
          'the geofence',
        );

        // --------------------------------------------------------
        // PREVIOUS GEOFENCE STATE
        // --------------------------------------------------------

        final previous = _previousGeofenceState[animalId];

        // --------------------------------------------------------
        // FIRST GPS LOCATION
        // --------------------------------------------------------

        if (previous == null) {
          _previousGeofenceState[animalId] = inside;

          debugPrint(
            'Initial geofence state for '
            '$animalId: $geofenceStatus',
          );
        }
        // --------------------------------------------------------
        // GEOFENCE STATE CHANGED
        // --------------------------------------------------------
        else if (previous != inside) {
          _previousGeofenceState[animalId] = inside;

          if (inside) {
            providerContainer
                .read(notificationProvider.notifier)
                .log(LogEventType.geofence, '$animalId entered the geofence.');

            debugPrint('$animalId entered the geofence');
          } else {
            providerContainer
                .read(notificationProvider.notifier)
                .log(LogEventType.geofence, '$animalId left the geofence!');

            debugPrint('$animalId left the geofence');
          }
        }

        // --------------------------------------------------------
        // UPDATE DASHBOARD
        // --------------------------------------------------------

        await DatabaseHelper.instance.updateDashboard(
          animalId: animalId,
          latitude: latitude,
          longitude: longitude,
          status: geofenceStatus,
          battery: battery,
          timestamp: timestamp,
          geofenceId: geofenceId,
        );

        // --------------------------------------------------------
        // SAVE LOCATION HISTORY
        // --------------------------------------------------------

        await DatabaseHelper.instance.insertDashboardHistory(
          animalId: animalId,
          latitude: latitude,
          longitude: longitude,
          status: geofenceStatus,
          battery: battery,
          timestamp: timestamp,
          geofenceId: geofenceId,
        );

        debugPrint(
          'Dashboard/history updated for '
          '$animalId',
        );
      } catch (e, stackTrace) {
        debugPrint('Error processing ESP message: $e');

        debugPrint('$stackTrace');
      }
    },
    onError: (error) {
      debugPrint('WiFi message stream error: $error');
    },
  );
}

// ============================================================================
// ESP CONNECTION
// ============================================================================

Future<void> connectToEsp(WifiService wifi) async {
  while (!wifi.isConnected) {
    try {
      debugPrint('Trying to connect to ESP...');

      final connected = await wifi.connect();

      if (connected) {
        debugPrint('Connected to ESP8266');

        return;
      }

      debugPrint(
        'ESP connection failed. '
        'Retrying in 5 seconds...',
      );
    } catch (e) {
      debugPrint('ESP connection error: $e');
    }

    await Future.delayed(const Duration(seconds: 5));
  }
}
