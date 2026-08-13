import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/map_state_controller.dart';
import '../database/database_helper.dart';
import '../geofence/geofence.dart';
import '../geofence/map_layers.dart';
import '../models/download_progress.dart';
import '../providers/notification_provider.dart';
import '../screens/alerts_screen.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/map_download_service.dart';
import '../services/tile_cache_service.dart';
import '../services/wifi_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/download_progress_dialog.dart';
import '../widgets/geofence_panel.dart';

class OnlineMapScreen extends ConsumerStatefulWidget {
  const OnlineMapScreen({super.key});

  @override
  ConsumerState<OnlineMapScreen> createState() => _OnlineMapScreenState();
}

class _OnlineMapScreenState extends ConsumerState<OnlineMapScreen> {
  final MapController mapController = MapController();
  final LocationService locationService = LocationService();

  StreamSubscription<Position>? positionStream;
  Timer? _refreshTimer;

  final MapStateController mapState = MapStateController();

  String? tileDirectory;

  bool isOnline = true;

  final ConnectivityService connectivityService = ConnectivityService();
  final MapDownloadService downloader = MapDownloadService();

  final ValueNotifier<DownloadProgress?> progressNotifier =
      ValueNotifier<DownloadProgress?>(null);

  Map<String, LatLng> livestockLocations = {};

  final WifiService wifi = WifiService();

  bool robotConnected = false;
  bool ledOn = false;

  final GeofenceController geofence = GeofenceController();

  Map<String, bool> lastGeofenceStatus = {};
  Map<String, int> lastBattery = {};

  // Number of unread notifications.
  int unreadAlerts = 0;

  // ---------------------------------------------------------------------------
  // LIVESTOCK LOCATION
  // ---------------------------------------------------------------------------

  Future<void> loadLivestockLocations() async {
    final animals = await DatabaseHelper.instance.getDashboard();

    if (!mounted) return;

    setState(() {
      livestockLocations.clear();

      for (final animal in animals) {
        final animalId = animal["Animal_ID"];

        final latitude = animal["Latitude"];
        final longitude = animal["Longitude"];

        if (animalId == null || latitude == null || longitude == null) {
          continue;
        }

        livestockLocations[animalId as String] = LatLng(
          (latitude as num).toDouble(),
          (longitude as num).toDouble(),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // MAP LOCATION
  // ---------------------------------------------------------------------------

  void recenterToMyLocation() {
    final currentLocation = mapState.currentLocation;

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location is not available yet.')),
      );
      return;
    }

    mapController.move(currentLocation, mapController.camera.zoom);
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    loadTileDirectory();
    loadConnectivity();
    loadLivestockLocations();
    connectWifi();

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      loadLivestockLocations();

      if (mounted && robotConnected != wifi.isConnected) {
        setState(() {
          robotConnected = wifi.isConnected;
        });
      }
    });

    listenToLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await geofence.loadGeofence();

      if (!mounted) return;

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

  // ---------------------------------------------------------------------------
  // WIFI / ROBOT
  // ---------------------------------------------------------------------------

  Future<void> connectWifi() async {
    final connected = await wifi.connect();

    if (!mounted) return;

    setState(() {
      robotConnected = connected;
    });
  }

  // ---------------------------------------------------------------------------
  // CONNECTIVITY
  // ---------------------------------------------------------------------------

  Future<void> loadConnectivity() async {
    isOnline = await connectivityService.isConnected();

    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // TILE DIRECTORY
  // ---------------------------------------------------------------------------

  Future<void> loadTileDirectory() async {
    tileDirectory = await TileCacheService.getTileDirectoryPath();

    if (mounted) {
      setState(() {});
    }

    debugPrint('Tile Directory: $tileDirectory');
  }

  // ---------------------------------------------------------------------------
  // GPS LOCATION
  // ---------------------------------------------------------------------------

  void listenToLocation() {
    positionStream = locationService.getPositionStream().listen((position) {
      final newLocation = LatLng(position.latitude, position.longitude);

      mapState.updateCurrentLocation(newLocation);

      if (mounted) {
        setState(() {});
      }
    });
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _refreshTimer?.cancel();
    positionStream?.cancel();

    progressNotifier.dispose();
    wifi.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // OPEN ALERTS
  // ---------------------------------------------------------------------------

  Future<void> openAlerts() async {
    setState(() {
      unreadAlerts = 0;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlertsScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATION BUTTON
  // ---------------------------------------------------------------------------

  Widget buildNotificationButton() {
    return IconButton(
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications),

          if (unreadAlerts > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadAlerts > 9 ? '9+' : '$unreadAlerts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: openAlerts,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Listen for new notification events.
    //
    // Because this screen is already a ConsumerStatefulWidget,
    // we do not need another Consumer widget around the Scaffold.
    ref.listen<List<LogEvent>>(notificationProvider, (previous, next) {
      if (!mounted) return;

      final previousLength = previous?.length ?? 0;

      if (next.isNotEmpty && next.length != previousLength) {
        final latestEvent = next.last;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(latestEvent.message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        setState(() {
          unreadAlerts++;
        });
      }
    });

    return Scaffold(
      // -----------------------------------------------------------------------
      // APP BAR
      // -----------------------------------------------------------------------
      appBar: AppBar(
        title: const Text('Livestock Tracker'),

        actions: [buildNotificationButton()],
      ),

      // -----------------------------------------------------------------------
      // DRAWER
      // -----------------------------------------------------------------------
      drawer: AppDrawer(
        robotConnected: robotConnected,
        ledOn: ledOn,

        onLedPressed: () {
          if (!robotConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Robot is not connected.')),
            );

            return;
          }

          if (ledOn) {
            wifi.send('LED_OFF');
          } else {
            wifi.send('LED_ON');
          }

          setState(() {
            ledOn = !ledOn;
          });
        },

        onGeoFenceTap: () async {
          await geofence.startEditing(mapController.camera.center);

          if (!mounted) return;

          setState(() {});
        },
      ),

      // -----------------------------------------------------------------------
      // FLOATING ACTION BUTTONS
      // -----------------------------------------------------------------------
      floatingActionButton: AnimatedPadding(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,

        padding: EdgeInsets.only(bottom: geofence.showPanel ? 85 : 0),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -----------------------------------------------------------------
            // CURRENT LOCATION BUTTON
            // -----------------------------------------------------------------
            FloatingActionButton(
              heroTag: 'locateMe',
              tooltip: 'Show my location',
              onPressed: recenterToMyLocation,
              child: const Icon(Icons.my_location),
            ),

            // -----------------------------------------------------------------
            // SELECT MAP DOWNLOAD AREA
            // -----------------------------------------------------------------
            if (isOnline) ...[
              const SizedBox(height: 12),

              FloatingActionButton(
                heroTag: 'selectBounds',
                tooltip: 'Select map area',

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

                child: const Icon(Icons.crop_square),
              ),
            ],
          ],
        ),
      ),

      // -----------------------------------------------------------------------
      // MAP DOWNLOAD BUTTON
      // -----------------------------------------------------------------------
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
                    Navigator.of(context).pop();
                  }

                  if (!mounted) return;

                  if (downloader.isCancelled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download cancelled')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Map downloaded successfully'),
                      ),
                    );

                    ref
                        .read(notificationProvider.notifier)
                        .log(
                          LogEventType.mapDownloaded,
                          'Offline map downloaded '
                          '(zoom up to 17)',
                        );
                  }

                  mapState.clearSelectedBounds();

                  setState(() {});
                },

                child: const Text('Download Area'),
              ),
            ),

      // -----------------------------------------------------------------------
      // BODY
      // -----------------------------------------------------------------------
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // MAP
          // -------------------------------------------------------------------
          FlutterMap(
            mapController: mapController,

            options: MapOptions(
              initialCenter:
                  mapState.currentLocation ?? const LatLng(27.7172, 85.3240),

              initialZoom: 15,

              maxZoom: 17,
            ),

            children: [
              // ---------------------------------------------------------------
              // ONLINE MAP
              // ---------------------------------------------------------------
              if (isOnline)
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/'
                      '{z}/{x}/{y}.png',

                  userAgentPackageName: 'com.example.livestock_tracker',
                )
              // ---------------------------------------------------------------
              // OFFLINE MAP
              // ---------------------------------------------------------------
              else if (tileDirectory != null)
                TileLayer(
                  tileProvider: FileTileProvider(),

                  urlTemplate: '$tileDirectory/{z}/{x}/{y}.png',
                ),

              // ---------------------------------------------------------------
              // CURRENT LOCATION
              // ---------------------------------------------------------------
              CurrentLocationLayer(
                alignPositionOnUpdate: AlignOnUpdate.never,

                alignDirectionOnUpdate: AlignOnUpdate.never,

                style: LocationMarkerStyle(
                  marker: const DefaultLocationMarker(color: Colors.blue),

                  markerSize: const Size(24, 24),

                  headingSectorColor: Colors.blue.withValues(alpha: 0.4),

                  headingSectorRadius: 80,
                ),
              ),

              // ---------------------------------------------------------------
              // GEOFENCE / MAP LAYERS
              // ---------------------------------------------------------------
              MapLayers(
                geofence: geofence,

                currentLocation: mapState.currentLocation,

                selectedBounds: mapState.selectedBounds,

                refresh: () {
                  setState(() {});
                },
              ),

              // ---------------------------------------------------------------
              // LIVESTOCK MARKERS
              // ---------------------------------------------------------------
              MarkerLayer(
                markers: livestockLocations.entries.map((entry) {
                  return Marker(
                    point: entry.value,

                    width: 60,
                    height: 60,

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        // ---------------------------------------------------
                        // ANIMAL MARKER
                        // ---------------------------------------------------
                        Container(
                          width: 22,
                          height: 22,

                          decoration: BoxDecoration(
                            color: Colors.blue,

                            shape: BoxShape.circle,

                            border: Border.all(color: Colors.white, width: 4),

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

                        // ---------------------------------------------------
                        // ANIMAL ID
                        // ---------------------------------------------------
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white,

                            borderRadius: BorderRadius.circular(12),

                            boxShadow: const [
                              BoxShadow(blurRadius: 3, color: Colors.black26),
                            ],
                          ),

                          child: Text(
                            entry.key,

                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // -------------------------------------------------------------------
          // GEOFENCE PANEL
          // -------------------------------------------------------------------
          GeofencePanel(
            showGeofencePanel: geofence.showPanel,

            geofence: geofence,

            refresh: () {
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
