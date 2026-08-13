class GpsData {
  final String deviceId;
  final double latitude;
  final double longitude;
  final int battery;
  final String timestamp;

  GpsData({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.battery,
    required this.timestamp,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      deviceId: json["device_id"],
      latitude: (json["latitude"] as num).toDouble(),
      longitude: (json["longitude"] as num).toDouble(),
      battery: json["battery"],
      timestamp: json["timestamp"],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "device_id": deviceId,
      "latitude": latitude,
      "longitude": longitude,
      "battery": battery,
      "timestamp": timestamp,
    };
  }
}