import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../services/wifi_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Wi-Fi
  final WifiService wifi = WifiService();

  bool robotConnected = false;
  bool ledOn = false;
  bool _connecting = false;

  // App Preferences
  double defaultZoom = 15.0;
  int minDownloadZoom = 15;
  int maxDownloadZoom = 19;

  @override
  void initState() {
    super.initState();
    connectWifi();
  }

  @override
  void dispose() {
    wifi.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // WI-FI CONNECTION
  // --------------------------------------------------------------------------

  Future<void> connectWifi() async {
    setState(() => _connecting = true);

    final connected = await wifi.connect();

    if (!mounted) return;

    setState(() {
      robotConnected = connected;
      _connecting = false;
    });
  }

  // --------------------------------------------------------------------------
  // CLEAR HISTORY
  // --------------------------------------------------------------------------

  Future<void> clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'This will permanently delete all livestock history records. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await DatabaseHelper.instance.clearDashboardHistory();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History cleared successfully')),
    );
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          // ====================================================================
          // BASE STATION
          // ====================================================================
          const _SectionHeader(title: 'Base Station'),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    robotConnected ? Icons.wifi : Icons.wifi_off,
                    color: robotConnected ? Colors.green : Colors.red,
                  ),

                  title: Text(
                    robotConnected
                        ? 'Base station connected'
                        : 'Base station offline',
                  ),

                  subtitle: _connecting
                      ? const Text('Connecting...')
                      : Text(robotConnected ? 'Live' : 'Not reachable'),

                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),

                    tooltip: 'Reconnect',

                    onPressed: _connecting ? null : connectWifi,
                  ),
                ),

                const Divider(height: 1),

                SwitchListTile(
                  secondary: Icon(
                    Icons.lightbulb,
                    color: ledOn ? Colors.amber : Colors.grey,
                  ),

                  title: const Text('LED Beacon'),

                  subtitle: Text(ledOn ? 'On' : 'Off'),

                  value: ledOn,

                  onChanged: robotConnected
                      ? (value) {
                          wifi.send(value ? 'LED_ON' : 'LED_OFF');

                          setState(() {
                            ledOn = value;
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================================
          // MAP PREFERENCES
          // ====================================================================
          const _SectionHeader(title: 'Map Preferences'),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.zoom_in),

                  title: const Text('Default Zoom Level'),

                  subtitle: Text(defaultZoom.toStringAsFixed(0)),

                  trailing: SizedBox(
                    width: 180,

                    child: Slider(
                      value: defaultZoom,

                      min: 10,

                      max: 19,

                      divisions: 9,

                      label: defaultZoom.toStringAsFixed(0),

                      onChanged: (value) {
                        setState(() {
                          defaultZoom = value;
                        });
                      },
                    ),
                  ),
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.download),

                  title: const Text('Download Zoom Range'),

                  subtitle: Text(
                    'Min: $minDownloadZoom  →  '
                    'Max: $maxDownloadZoom',
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),

                  child: Row(
                    children: [
                      const Text('Min'),

                      Expanded(
                        child: Slider(
                          value: minDownloadZoom.toDouble(),

                          min: 10,

                          max: 17,

                          divisions: 7,

                          label: '$minDownloadZoom',

                          onChanged: (value) {
                            setState(() {
                              minDownloadZoom = value.toInt();
                            });
                          },
                        ),
                      ),

                      const Text('Max'),

                      Expanded(
                        child: Slider(
                          value: maxDownloadZoom.toDouble(),

                          min: 17,

                          max: 19,

                          divisions: 2,

                          label: '$maxDownloadZoom',

                          onChanged: (value) {
                            setState(() {
                              maxDownloadZoom = value.toInt();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================================
          // DATABASE MANAGEMENT
          // ====================================================================
          const _SectionHeader(title: 'Database Management'),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),

                  title: const Text('Clear Livestock History'),

                  subtitle: const Text(
                    'Permanently deletes all history records',
                  ),

                  trailing: const Icon(Icons.chevron_right),

                  onTap: clearHistory,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ====================================================================
          // ABOUT
          // ====================================================================
          const _SectionHeader(title: 'About'),

          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.pets, color: Colors.green),

                  title: Text('Livestock Tracker'),

                  subtitle: Text('LoRa-Integrated GPS Geo-Fencing System'),
                ),

                Divider(height: 1),

                ListTile(
                  leading: Icon(Icons.school),

                  title: Text('Institution'),

                  subtitle: Text(
                    'Advanced College of Engineering and Management (ACEM)\n'
                    'Tribhuvan University, Nepal',
                  ),

                  isThreeLine: true,
                ),

                Divider(height: 1),

                ListTile(
                  leading: Icon(Icons.info_outline),

                  title: Text('Version'),

                  subtitle: Text('1.0.0'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ==============================================================================
// SECTION HEADER
// ==============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),

      child: Text(
        title,

        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
