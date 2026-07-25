import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

class OnlineMapScreen extends StatefulWidget {
  const OnlineMapScreen({super.key});

  @override
  State<OnlineMapScreen> createState() => _OnlineMapScreenState();
}

class _OnlineMapScreenState extends State<OnlineMapScreen> {
  final MapController mapController = MapController();
  final LocationService locationService = LocationService();
  StreamSubscription<Position>? positionStream;
  final mapState = MapStateController();
  String? tileDirectory;
  bool isOnline = true;
  final connectivityService = ConnectivityService();
  final downloader = MapDownloadService();
  final ValueNotifier<DownloadProgress?> progressNotifier = ValueNotifier(null);
  LatLng? livestockLocation;
  final WifiService wifi = WifiService();
  bool robotConnected = false;
  bool ledOn = false;
  final geofence = GeofenceController();

  @override
  void initState() {
    super.initState();
    loadTileDirectory();
    loadConnectivity();
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
    wifi.messages.listen((msg) {
      debugPrint("ESP -> $msg");
      if (msg.startsWith("GPS:")) {
        final data = msg.substring(4).split(",");

        if (data.length == 2) {
          final lat = double.tryParse(data[0]);
          final lng = double.tryParse(data[1]);

          if (lat != null && lng != null) {
            setState(() {
              livestockLocation = LatLng(lat, lng);
            });
          }
        }
      }

      if (msg.contains("CONNECTED")) {
        setState(() {
          robotConnected = true;
        });
      }

      if (msg.contains("LED:ON")) {
        setState(() {
          ledOn = true;
        });
      }

      if (msg.contains("LED:OFF")) {
        setState(() {
          ledOn = false;
        });
      }
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
              Icon(
                robotConnected ? Icons.wifi : Icons.wifi_off,
                color: robotConnected ? Colors.green : Colors.red,
              ),

              IconButton(
                icon: const Icon(Icons.link),

                onPressed: () async {
                  bool ok = await wifi.connect();
                  if (!context.mounted) return;

                  if (ok) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("Connected")));
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.lightbulb,
                  color: ledOn ? Colors.yellow : Colors.grey,
                ),
                onPressed: () {
                  if (!robotConnected) return;

                  if (ledOn) {
                    wifi.send("LED_OFF");
                  } else {
                    wifi.send("LED_ON");
                  }
                },
              ),
            ],
          ),
          drawer: AppDrawer(
            onGeoFenceTap: () async {
              await geofence.startEditing(mapController.camera.center);

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
                  LatLng(center.latitude - offset, center.longitude - offset),
                  LatLng(center.latitude + offset, center.longitude + offset),
                ),
              );

              setState(() {});
            },
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
                  initialZoom: 16,
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

                  MapLayers(
                    geofence: geofence,
                    currentLocation: mapState.currentLocation,
                    selectedBounds: mapState.selectedBounds,
                    refresh: () {
                      setState(() {});
                    },
                  ),
                  if (livestockLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: livestockLocation!,
                          width: 60,
                          height: 60,
                          child: const Icon(
                            Icons.pets,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
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
