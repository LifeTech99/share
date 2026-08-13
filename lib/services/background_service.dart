import '../providers/provider_container.dart';
import '../providers/notification_provider.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:livestock_tracker/services/geofence_service.dart';
import 'wifi_service.dart';
import '../database/database_helper.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart'; 

final Map<String, bool> _previousGeofenceState = {};
final Map<String, DateTime> _onlineAnimals = {};
final Map<String, int> _lastBatteryNotification = {};
class BackgroundService {
  static final FlutterBackgroundService _service =
      FlutterBackgroundService();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

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

  static Future<void> start() async {
    final started = await _service.startService();
    debugPrint("Background service started: $started");
  }

  static Future<void> stop() async {
    _service.invoke("stop");
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  debugPrint("onStart() called");
   if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    debugPrint("Foreground service requested");
  }

    if (service is AndroidServiceInstance) {
  await service.setForegroundNotificationInfo(
    title: "Livestock Tracker",
    content: "0 animals online",
  );

  debugPrint("Notification updated");
  }


  service.on("stop").listen((event) {
    service.stopSelf();
  });
final wifi = WifiService();

await connectToEsp(wifi);

// Remove offline animals every 10 seconds
Timer.periodic(const Duration(seconds: 10), (timer) async {

 Timer.periodic(const Duration(seconds: 5), (timer) async {
  if (!wifi.isConnected) {
    debugPrint("ESP disconnected. Reconnecting...");
    await connectToEsp(wifi);
  }
});

  final now = DateTime.now();

  final before = _onlineAnimals.length;

  _onlineAnimals.removeWhere(
    (deviceId, lastSeen) =>
        now.difference(lastSeen).inSeconds > 30,
  );

  // Update notification only if the count changed
  if (_onlineAnimals.length != before &&
      service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: "Livestock Tracker",
      content: "${_onlineAnimals.length} animals online",
    );
  }
});

wifi.messages.listen((json) async {
  final deviceId = json["device_id"];

  final before = _onlineAnimals.length;

  _onlineAnimals[deviceId] = DateTime.now();

  // Only update if a NEW animal came online
  if (_onlineAnimals.length != before &&
      service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: "Livestock Tracker",
      content: "${_onlineAnimals.length} animals online",
    );
  }
  final latitude = (json["latitude"] as num).toDouble();
  final longitude = (json["longitude"] as num).toDouble();
  final battery = json["battery"] as int;


  final lastBattery = _lastBatteryNotification[deviceId];

if (battery <= 15 && lastBattery != battery) {
  _lastBatteryNotification[deviceId] = battery;

  await BackgroundService.showAlert(
    title: "Low Battery",
    body: "$deviceId battery is $battery%",
  );

  providerContainer.read(notificationProvider.notifier).log(
  LogEventType.battery,
  "$deviceId battery is $battery%",
); 
}


  final timestamp = json["timestamp"] as String;

final fence = await DatabaseHelper.instance.getGeofence();

if (fence == null) {
  return;
}

final geofenceId = fence["id"] as int;

final polygon =
    await DatabaseHelper.instance.getGeofencePoints(geofenceId);   
  final inside = GeofenceUtils.isPointInsidePolygon(
    LatLng(latitude, longitude),
    polygon,);
    final geofenceStatus = inside ? "inside" : "outside";

  final previous = _previousGeofenceState[deviceId];

if (previous == null) {
  // First GPS received for this animal
  _previousGeofenceState[deviceId] = inside;
} else if (previous != inside) {
  // Status changed
  _previousGeofenceState[deviceId] = inside;

  if (inside) {
    await BackgroundService.showAlert(
    title: "Animal Returned",
    body: "$deviceId entered the geofence.",
  );
  providerContainer.read(notificationProvider.notifier).log(
  LogEventType.geofence,
  "$deviceId entered the geofence.",
);

  } else {
      await BackgroundService.showAlert(
    title: "Geofence Alert",
    body: "$deviceId left the geofence!",
  );
  providerContainer.read(notificationProvider.notifier).log(
  LogEventType.geofence,
  "$deviceId left the geofence!",
);
  }
}


  await DatabaseHelper.instance.updateDashboard(
    animalId: deviceId,
    latitude: latitude,
    longitude: longitude,
    status: geofenceStatus,
    battery: battery,
    timestamp: timestamp,
    geofenceId: geofenceId,
  );

  // 4. Save the history
  await DatabaseHelper.instance.insertDashboardHistory(
    animalId: deviceId,
    latitude: latitude,
    longitude: longitude,
    status: geofenceStatus,
    battery: battery,
    timestamp: timestamp,
    geofenceId: geofenceId,
  );

});

}

Future<void> connectToEsp(WifiService wifi) async {
  while (!wifi.isConnected) {
    debugPrint("Trying to connect...");

    final connected = await wifi.connect();

    if (connected) {
      debugPrint("Connected to ESP8266");
      return;
    }

    await Future.delayed(const Duration(seconds: 5));
  }
}

