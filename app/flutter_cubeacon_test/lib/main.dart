import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io' show Platform;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cubeacon Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Inter', // Applying Inter font as per instructions
      ),
      home: const BeaconRangingPage(),
    );
  }
}

class BeaconRangingPage extends StatefulWidget {
  const BeaconRangingPage({super.key});

  @override
  State<BeaconRangingPage> createState() => _BeaconRangingPageState();
}

class _BeaconRangingPageState extends State<BeaconRangingPage> {
  // List to store detected beacons
  List<Beacon> _beacons = [];
  // Stream subscription for ranging results
  StreamSubscription<RangingResult>? _streamRanging;
  // State variables for UI feedback
  String _bluetoothState = 'Unknown';
  bool _locationGranted = false;
  bool _bluetoothEnabled = false;
  bool _isScanning = false;

  // Completer to ensure Bluetooth state is known before proceeding
  Completer<void>? _bluetoothCompleter;

  @override
  void initState() {
    super.initState();
    // Initialize beacon service when the widget is created
    _initBeaconService();
  }

  @override
  void dispose() {
    // Cancel the ranging stream when the widget is disposed to prevent memory leaks
    _streamRanging?.cancel();
    super.dispose();
  }

  /// Initializes the beacon service, checks permissions, and starts listeners.
  Future<void> _initBeaconService() async {
    // 1. Request location permission first
    await _checkLocationPermission();

    // 2. Initialize a completer to wait for the first Bluetooth state update
    _bluetoothCompleter = Completer<void>();

    // 3. Listen for Bluetooth state changes
    flutterBeacon.bluetoothStateChanged.listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state.toString();
        _bluetoothEnabled = state == BluetoothState.stateOn;
      });
      print('Bluetooth state changed: $state');

      // Complete the completer once Bluetooth state is known for the first time
      if (_bluetoothCompleter != null && !_bluetoothCompleter!.isCompleted) {
        _bluetoothCompleter!.complete();
      }

      // Automatically start/stop ranging based on state changes later on
      if (_bluetoothEnabled && _locationGranted && !_isScanning) {
        _startRanging();
      } else if (!_bluetoothEnabled && _isScanning) {
        _stopRanging();
      }
    });

    // 4. Wait for the initial Bluetooth state to be delivered by the stream
    // This is important because checkBluetoothState() is not available in 0.5.1
    await _bluetoothCompleter!.future;

    // 5. After both permissions are checked and Bluetooth state is known,
    //    attempt to start ranging if conditions met.
    if (_locationGranted && _bluetoothEnabled) {
      try {
        // In flutter_beacon 0.5.1, `initializeScanning()` might not be explicit
        // or might be handled internally by `ranging()`. We'll rely on `ranging()`
        // to handle the necessary native initialization.
        print('Beacon service ready for ranging (0.5.1 compatibility).');
        _startRanging(); // Attempt to start ranging if conditions met
      } catch (e) {
        print('Error during beacon service setup: $e');
      }
    } else {
      print('Permissions or Bluetooth not fully ready. Cannot start scanning.');
    }
  }

  /// Checks and requests Location permission.
  Future<void> _checkLocationPermission() async {
    var locationStatus = await Permission.locationWhenInUse.status;
    if (locationStatus.isDenied || locationStatus.isRestricted || locationStatus.isPermanentlyDenied) {
      locationStatus = await Permission.locationWhenInUse.request();
    }
    setState(() {
      _locationGranted = locationStatus.isGranted;
    });

    if (Platform.isAndroid && !_locationGranted) {
      // On Android, if location permission isn't granted, beacon scanning won't work.
      // You might want to show a custom dialog here to inform the user.
      print('Location permission not granted on Android. Beacon scanning will not work.');
    }
  }

  /// Starts ranging for beacons.
  void _startRanging() {
    if (_streamRanging != null) {
      print('Ranging already started.');
      return;
    }
    if (!_locationGranted || !_bluetoothEnabled) {
      print('Cannot start ranging: Location permission or Bluetooth not enabled.');
      return;
    }

    // Define a region to scan for beacons.
    // IMPORTANT: For flutter_beacon 0.5.1, 'uuid' is NOT a named parameter.
    // You MUST use 'proximityUUID' instead.
    final regions = <Region>[
      Region(
        identifier: 'CubeaconRegion', // Identifier for your region
        proximityUUID: 'cb10023f-a318-3394-4199-a8730c7c1aec', // Use proximityUUID for 0.5.1
        major: 1234, // Optional major value
        minor: 5678, // Optional minor value
      ),
      // Add more regions here if you want to range multiple specific beacons
    ];

    _streamRanging = flutterBeacon.ranging(regions).listen((RangingResult result) {
      if (mounted) {
        setState(() {
          _beacons = result.beacons;
        });
      }
    });
    setState(() {
      _isScanning = true;
    });
    print('Ranging started for regions: ${regions.map((e) => e.identifier).join(', ')}');
  }

  /// Stops ranging for beacons.
  void _stopRanging() {
    _streamRanging?.cancel();
    _streamRanging = null;
    setState(() {
      _isScanning = false;
      _beacons = []; // Clear beacons when stopping
    });
    print('Ranging stopped.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cubeacon Detector'),
        backgroundColor: const Color(0xFF005982), // Primary color from Cubeacon sample
      ),
      body: Container(
        color: const Color(0xFFE0F7FA), // Light blue background
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(context),
              const SizedBox(height: 16),
              _buildControlButtons(context),
              const SizedBox(height: 16),
              Expanded(
                child: _beacons.isEmpty && _isScanning
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF0095DA)),
                            SizedBox(height: 16),
                            Text(
                              'Scanning for beacons...',
                              style: TextStyle(fontSize: 18, color: Colors.black54),
                            ),
                          ],
                        ),
                      )
                    : _beacons.isEmpty && !_isScanning
                        ? const Center(
                            child: Text(
                              'Start scanning to find beacons.',
                              style: TextStyle(fontSize: 18, color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _beacons.length,
                            itemBuilder: (context, index) {
                              final beacon = _beacons[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Beacon: ${beacon.proximityUUID?.toUpperCase()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFF003b57),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Major: ${beacon.major ?? 'N/A'}, Minor: ${beacon.minor ?? 'N/A'}',
                                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                                      ),
                                      Text(
                                        'RSSI: ${beacon.rssi ?? 'N/A'}',
                                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                                      ),
                                      Text(
                                        'Accuracy: ${beacon.accuracy != null ? '${beacon.accuracy!.toStringAsFixed(2)} m' : 'N/A'}',
                                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003b57),
              ),
            ),
            const SizedBox(height: 8),
            _buildStatusRow('Location Permission:', _locationGranted ? 'Granted' : 'Denied', _locationGranted ? Colors.green : Colors.red),
            _buildStatusRow('Bluetooth State:', _bluetoothState, _bluetoothEnabled ? Colors.green : Colors.red),
            _buildStatusRow('Scanning:', _isScanning ? 'Active' : 'Inactive', _isScanning ? Colors.green : Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _startRanging,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Start Scan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0095DA), // Light blue from Cubeacon sample
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 5,
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isScanning ? _stopRanging : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop Scan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 5,
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
