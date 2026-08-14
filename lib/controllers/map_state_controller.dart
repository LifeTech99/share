import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/gps_data.dart';


class MapStateController extends ChangeNotifier {

  LatLng? currentLocation;

  GpsData? animalData;

  LatLngBounds? selectedBounds;

  bool showGeofencePanel = false;

  final List<Marker> animalMarkers = [];


  void updateCurrentLocation(
    LatLng location,
  ) {
    currentLocation = location;

    notifyListeners();
  }


  void updateAnimalData(
    GpsData data,
  ) {

    animalData = data;


    final animalLocation =
        LatLng(
          data.latitude,
          data.longitude,
        );


    final marker = Marker(
      point: animalLocation,

      width: 50,
      height: 50,

      child: const Icon(
        Icons.pets,
        size: 40,
      ),
    );


    animalMarkers
      ..clear()
      ..add(marker);


    notifyListeners();
  }


  void updateSelectedBounds(
    LatLngBounds bounds,
  ) {
    selectedBounds = bounds;

    notifyListeners();
  }


  void clearSelectedBounds() {
    selectedBounds = null;

    notifyListeners();
  }


  void showPanel() {
    showGeofencePanel = true;

    notifyListeners();
  }


  void hidePanel() {
    showGeofencePanel = false;

    notifyListeners();
  }


  void setAnimalMarkers(
    List<Marker> markers,
  ) {
    animalMarkers
      ..clear()
      ..addAll(markers);

    notifyListeners();
  }


  void addAnimalMarker(
    Marker marker,
  ) {
    animalMarkers.add(marker);

    notifyListeners();
  }


  void clearAnimals() {
    animalMarkers.clear();

    animalData = null;

    notifyListeners();
  }
}