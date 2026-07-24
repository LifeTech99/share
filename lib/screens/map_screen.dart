import 'dart:async';
import '/services/tile_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/connectivity_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/geofence_panel.dart';
import '../services/location_service.dart';
import '../controllers/map_state_controller.dart';
import '../services/map_download_service.dart';
import '../models/download_progress.dart';
import '../widgets/download_progress_dialog.dart';


class OnlineMapScreen extends StatefulWidget {
  const OnlineMapScreen({super.key});
  
  @override
  State<OnlineMapScreen> createState() => _OnlineMapScreenState();
}

class _OnlineMapScreenState extends State<OnlineMapScreen> {
  bool selectingArea = false;
  final MapController mapController = MapController();
  final LocationService locationService = LocationService();
  StreamSubscription<Position>? positionStream;
  final mapState = MapStateController();
  String? tileDirectory;
  bool isOnline = true;
  final connectivityService = ConnectivityService();
  final downloader = MapDownloadService();
  final ValueNotifier<DownloadProgress?> progressNotifier =
    ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    loadTileDirectory();
    loadConnectivity();
    listenToLocation();
    connectivityService.connectivityStream.listen((connected) {
      if (!mounted) return;

      setState(() {
        isOnline = connected;
      });

      debugPrint('Internet Available: $connected');
    });
  }

  Future<void> loadConnectivity() async {
    isOnline = await connectivityService.isConnected();

    if (mounted) {
      setState(() {});
    }
  }
  Future<void> loadTileDirectory() async {
    tileDirectory = await TileCacheService.getTileDirectoryPath();

    if (mounted) {
      setState(() {});
    }

    debugPrint('Tile Directory: $tileDirectory');
  }

  void listenToLocation() {
    positionStream =locationService.getPositionStream().listen((position) {
      final newLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      mapState.updateCurrentLocation(newLocation);
      setState(() {});
      mapController.move(
        newLocation,
        mapController.camera.zoom,
      );
    });
  }


  @override
  void dispose() {
    positionStream?.cancel();
    progressNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Livestock Tracker"),
      ),
      drawer: AppDrawer(
        onGeoFenceTap: () {
          mapState.showPanel();
          setState(() {});

        },
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.crop_square),
        onPressed: () {
          final center = mapController.camera.center;
          const double offset = 0.01;
          mapState.updateSelectedBounds(
            LatLngBounds(
              LatLng(
                center.latitude - offset,
                center.longitude - offset,
              ),
              LatLng(
                center.latitude + offset,
                center.longitude + offset,
              ),
            ),
          );

          setState(() {});
        },
      ),
      bottomNavigationBar:
      mapState.selectedBounds == null
      ? null
      : Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          onPressed: () async {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => DownloadProgressDialog(
                progressNotifier: progressNotifier,
                onCancel: () {
                  downloader.cancelDownload();
                },
              ),
            );
            await downloader.downloadArea(
              bounds: mapState.selectedBounds!,
              minZoom: 13,
              maxZoom: 17,
              onProgress: (progress) {
                progressNotifier.value = progress;
              },
            );
            if (mounted) {
              Navigator.of(this.context).pop();
            }
            if (!mounted) return;
            if (downloader.isCancelled) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Download cancelled'),
                ),
              );
            } else {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Map downloaded successfully'),
                ),
              );
            }
             
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
                  mapState.currentLocation ??
                  const LatLng(
                    27.7172,
                    85.3240,
                  ),
              initialZoom: 16,
            ),
      
            children: [
      
              if (isOnline)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.livestock_tracker',
                )
              else if (tileDirectory != null)
                TileLayer(
                  tileProvider: FileTileProvider(),
                  urlTemplate: '$tileDirectory/{z}/{x}/{y}.png',
                ),
      
              if (mapState.selectedBounds != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: [
                        mapState.selectedBounds!.northWest,
      
                        LatLng(
                          mapState.selectedBounds!.north,
                          mapState.selectedBounds!.east,
                        ),
      
                        mapState.selectedBounds!.southEast,
      
                        LatLng(
                          mapState.selectedBounds!.south,
                          mapState.selectedBounds!.west,
                        ),
                      ],
                      color:Colors.blue.withValues(alpha: 0.25),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
      
              if (mapState.currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: mapState.currentLocation!,
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
          GeofencePanel(
            visible: mapState.showGeofencePanel,
            onCancel: () {
              mapState.hidePanel();
            },
            onSave: () {
            },
            onDelete: () {
            },
          ),

        ],
      ),
    );
  }
}