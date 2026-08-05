import '../services/geofence_service.dart';
import 'dart:convert';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import '../database/database_helper.dart';
import 'package:latlong2/latlong.dart';
import '../screens/alerts_screen.dart';
import '../services/tile_cache_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/geofence_panel.dart';
import '../services/location_service.dart';
import '../controllers/map_state_controller.dart';
import '../services/map_download_service.dart';
import '../models/download_progress.dart';
import '../widgets/download_progress_dialog.dart';
import '../services/wifi_service.dart';
import '../geofence/geofence.dart';
import '../geofence/map_layers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notification_provider.dart';

class OnlineMapScreen extends ConsumerStatefulWidget {
  const OnlineMapScreen({super.key});

  @override
  ConsumerState<OnlineMapScreen> createState() =>
      _OnlineMapScreenState();
}

class _OnlineMapScreenState extends ConsumerState<OnlineMapScreen> {
  final MapController mapController = MapController();
  final LocationService locationService = LocationService();
  StreamSubscription<Position>? positionStream;
  Timer? _refreshTimer;
  final mapState = MapStateController();
  String? tileDirectory;
  bool isOnline = true;
  final connectivityService = ConnectivityService();
  final downloader = MapDownloadService();
  final ValueNotifier<DownloadProgress?> progressNotifier = ValueNotifier(null);
  Map<String, LatLng> livestockLocations = {};
  final WifiService wifi = WifiService();
  bool robotConnected = false;
  bool ledOn = false;
  final geofence = GeofenceController();
  Map<String, bool> lastGeofenceStatus = {};
  Map<String, int> lastBattery = {};

  Future<void> loadLivestockLocations() async {
  final animals = await DatabaseHelper.instance.getDashboard();

  if (!mounted) return;

  setState(() {
    livestockLocations.clear();

    for (final animal in animals) {
      livestockLocations[animal["Animal_ID"] as String] = LatLng(
        (animal["Latitude"] as num).toDouble(),
        (animal["Longitude"] as num).toDouble(),
      );
    }
  });
}

  @override
  void initState() {
    super.initState();

    loadTileDirectory();
    loadConnectivity();
    loadLivestockLocations();


      _refreshTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => loadLivestockLocations(),
  );




    listenToLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await geofence.loadGeofence();
      setState(() {});
    });
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
    positionStream = locationService.getPositionStream().listen((position) {
      final newLocation = LatLng(position.latitude, position.longitude);

      mapState.updateCurrentLocation(newLocation);
      setState(() {});
      mapController.move(newLocation, mapController.camera.zoom);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    positionStream?.cancel();
    progressNotifier.dispose();
    wifi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        ref.listen<List<LogEvent>>(notificationProvider, (previous, next) {
          if (next.isNotEmpty && next.length != (previous?.length ?? 0)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(next.last.message)));
          }
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text("Livestock Tracker"),
            actions: [
                        IconButton(
            icon: Icon(
              Icons.notifications,
            ),
            onPressed:  () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AlertsScreen()),
              );
            },
          ),
            ],
          ),

drawer: AppDrawer(
  robotConnected: robotConnected,
  ledOn: ledOn,
  onLedPressed: () {
    if (!robotConnected) return;

    if (ledOn) {
      wifi.send("LED_OFF");
    } else {
      wifi.send("LED_ON");
    }

    setState(() {
      ledOn = !ledOn;
    });
  },

  onGeoFenceTap: () async {
    await geofence.startEditing(mapController.camera.center);
    setState(() {});
  },
),

          floatingActionButton: AnimatedPadding(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: EdgeInsets.only(
              bottom: geofence.showPanel ? 85 : 0,
            ),
            child:  FloatingActionButton(
            child: const Icon(Icons.crop_square),
            onPressed: () {
              final center = mapController.camera.center;
              const double offset = 0.01;
              mapState.updateSelectedBounds(
                LatLngBounds(
                  LatLng(center.latitude - offset, center.longitude - offset),
                  LatLng(center.latitude + offset, center.longitude + offset),
                ),
              );

              setState(() {});
            },
          ),
          ),
          bottomNavigationBar: mapState.selectedBounds == null
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
                          const SnackBar(content: Text('Download cancelled')),
                        );
                      } else {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Map downloaded successfully'),
                          ),
                        );
                        ref
                            .read(notificationProvider.notifier)
                            .log(
                              LogEventType.mapDownloaded,
                              "Offline map downloaded (zoom up to 17)",
                            );
                      }
                      mapState.clearSelectedBounds();
                      setState(() {});
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
                      const LatLng(27.7172, 85.3240),
                  initialZoom: 15,
                  maxZoom: 17,
                ),

                children: [
                  if (isOnline)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.livestock_tracker',
                    )
                  else if (tileDirectory != null)
                    TileLayer(
                      tileProvider: FileTileProvider(),
                      urlTemplate: '$tileDirectory/{z}/{x}/{y}.png',
                    ),
                      CurrentLocationLayer(
  alignPositionOnUpdate: AlignOnUpdate.never,
  alignDirectionOnUpdate: AlignOnUpdate.never,

  style: LocationMarkerStyle(
    marker: const DefaultLocationMarker(
      color: Colors.blue,
    ),

    markerSize: const Size(24, 24),

    headingSectorColor: Colors.blue.withValues(alpha: 0.4),

    headingSectorRadius: 80,

  ),
),

                  MapLayers(
                    geofence: geofence,
                    currentLocation: mapState.currentLocation,
                    selectedBounds: mapState.selectedBounds,
                    refresh: () {
                      setState(() {});
                    },
                  ),
                  MarkerLayer(
  markers: livestockLocations.entries.map((entry) {
    return Marker(
      point: entry.value,
      width: 60,
      height: 60,
child: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    // Blue circular marker
    Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
    ),
const SizedBox(height: 4),
    Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 3,
            color: Colors.black26,
          ),
        ],
      ),
      child: Text(
        entry.key, // Animal_ID
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ],
)
    );
  }).toList(),
),
                ],
              ),

              GeofencePanel(
                showGeofencePanel: geofence.showPanel,
                geofence: geofence,
                refresh: () {
                  setState(() {});
                },
              ),
              // Bottom panel goes here
            ],
          ),
        );
      },
    );
  }
}
