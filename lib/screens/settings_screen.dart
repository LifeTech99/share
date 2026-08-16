import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../services/wifi_service.dart';
import '../providers/notification_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // --------------------------------------------------------------------------
  // WI-FI SERVICE
  // --------------------------------------------------------------------------

  final WifiService wifi = WifiService();

  bool robotConnected = false;
  bool ledOn = false;
  bool _connecting = false;

  // --------------------------------------------------------------------------
  // INIT / DISPOSE
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Connect after the first frame so that the widget is fully initialized.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      connectWifi();
    });
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
    if (_connecting) return;

    if (mounted) {
      setState(() {
        _connecting = true;
      });
    }

    try {
      final connected = await wifi.connect();

      if (!mounted) return;

      setState(() {
        robotConnected = connected;
        _connecting = false;
      });

      if (!connected) {
        _showSnackBar('Base station could not be reached', isError: true);
      }
    } catch (e) {
      debugPrint('Wi-Fi connection error: $e');

      if (!mounted) return;

      setState(() {
        robotConnected = false;
        _connecting = false;
      });

      _showSnackBar('Failed to connect to base station', isError: true);
    }
  }

  // --------------------------------------------------------------------------
  // LED CONTROL
  // --------------------------------------------------------------------------

  Future<void> toggleLed(bool value) async {
    if (!robotConnected) return;

    try {
      final command = value ? 'LED_ON' : 'LED_OFF';

      wifi.send(command);

      if (!mounted) return;

      setState(() {
        ledOn = value;
      });
    } catch (e) {
      debugPrint('LED command error: $e');

      if (!mounted) return;

      _showSnackBar('Failed to control LED', isError: true);
    }
  }

  // --------------------------------------------------------------------------
  // CLEAR HISTORY
  // --------------------------------------------------------------------------

  Future<void> clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear Alert History'),
          content: const Text(
            'This will permanently delete all alert history. '
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await DatabaseHelper.instance.clearLogs();
      if (!mounted) return;
      ref.read(notificationProvider.notifier).clearNotifications();

      _showSnackBar('Alert history cleared successfully');
    } catch (e) {
      debugPrint('Clear history error: $e');

      if (!mounted) return;

      _showSnackBar('Failed to clear alert history', isError: true);
    }
  }

  // --------------------------------------------------------------------------
  // SNACKBAR
  // --------------------------------------------------------------------------

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
        ),
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
          // ==================================================================
          // BASE STATION
          // ==================================================================
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

                  trailing: _connecting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Reconnect',
                          onPressed: connectWifi,
                        ),
                ),

                const Divider(height: 1),

                // ============================================================
                // LED BEACON
                // ============================================================
                SwitchListTile(
                  secondary: Icon(
                    ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
                    color: ledOn ? Colors.amber : Colors.grey,
                  ),

                  title: const Text('LED Beacon'),

                  subtitle: Text(ledOn ? 'On' : 'Off'),

                  value: ledOn,

                  onChanged: robotConnected ? toggleLed : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ==================================================================
          // DATABASE MANAGEMENT
          // ==================================================================
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

          // ==================================================================
          // ABOUT
          // ==================================================================
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
                    'Advanced College of Engineering and '
                    'Management (ACEM)\n'
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
