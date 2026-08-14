class GpsData {
  final String deviceId;

  final double latitude;
  final double longitude;

  final double altitude;
  final int satellites;

  final double speed;

  final double battery;

  final bool moving;

  final int counter;

  final int rssi;
  final double snr;

  final int packetSize;

  final double baseBattery;

  final String timestamp;


  GpsData({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.satellites,
    required this.speed,
    required this.battery,
    required this.moving,
    required this.counter,
    required this.rssi,
    required this.snr,
    required this.packetSize,
    required this.baseBattery,
    required this.timestamp,
  });


  factory GpsData.fromJson(
    Map<String, dynamic> json,
  ) {
    return GpsData(
      deviceId:
          json["device_id"]?.toString() ??
          "GPS_NODE_A",

      latitude:
          (json["latitude"] as num).toDouble(),

      longitude:
          (json["longitude"] as num).toDouble(),

      altitude:
          (json["altitude"] as num).toDouble(),

      satellites:
          (json["satellites"] as num).toInt(),

      speed:
          (json["speed"] as num).toDouble(),

      battery:
          (json["battery"] as num).toDouble(),

      moving:
          (json["movement"] as num).toInt() == 1,

      counter:
          (json["counter"] as num).toInt(),

      rssi:
          (json["rssi"] as num).toInt(),

      snr:
          (json["snr"] as num).toDouble(),

      packetSize:
          (json["packetSize"] as num).toInt(),

      baseBattery:
          (json["baseBattery"] as num).toDouble(),

      timestamp:
          json["timestamp"]?.toString() ??
          DateTime.now().toIso8601String(),
    );
  }


  Map<String, dynamic> toMap() {
    return {
      "device_id": deviceId,
      "latitude": latitude,
      "longitude": longitude,
      "altitude": altitude,
      "satellites": satellites,
      "speed": speed,
      "battery": battery,
      "movement": moving ? 1 : 0,
      "counter": counter,
      "rssi": rssi,
      "snr": snr,
      "packetSize": packetSize,
      "baseBattery": baseBattery,
      "timestamp": timestamp,
    };
  }
}