import 'dart:async';
import 'services/tile_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'services/tile_calculator.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OnlineMapScreen(),
    );
  }
}

class OnlineMapScreen extends StatefulWidget {
  const OnlineMapScreen({super.key});

  @override
  State<OnlineMapScreen> createState() => _OnlineMapScreenState();
}

class _OnlineMapScreenState extends State<OnlineMapScreen> {
  bool selectingArea = false;

  LatLngBounds? selectedBounds;
  final MapController mapController = MapController();
  bool showGeofencePanel = false;
  LatLng? currentLocation;

  StreamSubscription<Position>? positionStream;

  @override
  void initState() {
    super.initState();
    initializeLocation();
  }

  Future<void> initializeLocation() async {

    bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    positionStream =
        Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen((Position position) {

      final newLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        currentLocation = newLocation;
      });

      mapController.move(
        newLocation,
        mapController.camera.zoom,
      );
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Livestock Tracker"),
     ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
      
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.green,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.pets,
                    size: 60,
                    color: Colors.white,
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Livestock Tracker",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
      
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text("Home"),
              onTap: () {
                Navigator.pop(context);
              },
            ),
      
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text("Map"),
              onTap: () {
                Navigator.pop(context);
              },
            ),
      
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text("Geo-Fence"),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  showGeofencePanel = true;
                });
              },
            ),
      
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text("Alerts"),
              onTap: () {
                Navigator.pop(context);
              },
            ),
      
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("Settings"),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
),
      floatingActionButton: FloatingActionButton(
      child: const Icon(Icons.crop_square),
      onPressed: () {

        final center = mapController.camera.center;

        const double offset = 0.01;

        setState(() {

          selectingArea = true;

          selectedBounds = LatLngBounds(

            LatLng(
              center.latitude - offset,
              center.longitude - offset,
            ),

            LatLng(
              center.latitude + offset,
              center.longitude + offset,
            ),
          );
        });
      },
    ),
      bottomNavigationBar:

      selectedBounds == null

      ? null

      : Padding(

          padding: const EdgeInsets.all(12),

          child: ElevatedButton(

            onPressed: () async {
              final zoom = 15;
          
              final minX =
                  TileCalculator.longitudeToTileX(
                      selectedBounds!.west, zoom);
          
              final maxX =
                  TileCalculator.longitudeToTileX(
                      selectedBounds!.east, zoom);
          
              final minY =
                  TileCalculator.latitudeToTileY(
                      selectedBounds!.north, zoom);
          
              final maxY =
                  TileCalculator.latitudeToTileY(
                      selectedBounds!.south, zoom);
          
              print("X : $minX -> $maxX");
              print("Y : $minY -> $maxY");
          
           
              for (int x = minX; x <= maxX; x++) {
                for (int y = minY; y <= maxY; y++) {
                
                  print("Downloading: $zoom/$x/$y");

                  await TileDownloader.downloadTile(
                    zoom: zoom,
                    x: x,
                    y: y,
                  );
                }
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                   content: Text("Map tile downloaded successfully"),
                    ),
                 );
             
            },
            child: const Text("Download Area"),
          ),

      ),
      body: Stack(
        children: [
      
          FlutterMap(
            mapController: mapController,
      
            options: MapOptions(
              initialCenter:
                  currentLocation ??
                  const LatLng(
                    27.7172,
                    85.3240,
                  ),
              initialZoom: 16,
            ),
      
            children: [
      
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.example.livestock_tracker',
              ),
      
              if (selectedBounds != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: [
                        selectedBounds!.northWest,
      
                        LatLng(
                          selectedBounds!.north,
                          selectedBounds!.east,
                        ),
      
                        selectedBounds!.southEast,
      
                        LatLng(
                          selectedBounds!.south,
                          selectedBounds!.west,
                        ),
                      ],
                      color: Colors.blue.withOpacity(0.25),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
      
              if (currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 45,
                      ),
                    ),
                  ],
                ),
            ],
          ),
      
          // Bottom panel goes here
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            left: 0,
            right: 0,
            bottom: showGeofencePanel ? 0 : -120,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.10,
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        showGeofencePanel = false;
                      });
                    },
                    child: const Text("Cancel"),
                  ),
      
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text("Save"),
                  ),
      
                  TextButton(
                    onPressed: () {},
                    child: const Text("Delete"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}