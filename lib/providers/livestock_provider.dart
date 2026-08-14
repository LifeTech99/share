import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/livestock_websocket_service.dart';
import '../models/gps_data.dart';


final livestockWebSocketProvider =
    Provider<LivestockWebSocketService>(
  (ref) {

    final service =
        LivestockWebSocketService();


    ref.onDispose(() {
      service.dispose();
    });


    return service;
  },
);


final livestockDataProvider =
    StreamProvider<GpsData>((ref) {

  final service =
      ref.watch(
        livestockWebSocketProvider,
      );


  return service.dataStream;
});