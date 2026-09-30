import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safe_drive_monitor/services/sensor_service.dart';
import 'package:safe_drive_monitor/services/database_service.dart';
import 'package:safe_drive_monitor/models/driving_record.dart';
import 'dart:math';
import 'package:safe_drive_monitor/config/app_config.dart';
import 'dart:async';
import 'package:safe_drive_monitor/pages/settings_page.dart';
import 'package:safe_drive_monitor/pages/drive_list_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safe_drive_monitor/services/telegram_service.dart';
import 'package:safe_drive_monitor/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await AppConfig.init();
  await AppConfig.loadSettings();
  // Disable most framework logging
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message?.contains('SDM_LOG:') ?? false) {
      print(message);
    }
  };
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SensorService _sensorService = SensorService();
  final DatabaseService _dbService = DatabaseService();
  final TelegramService _telegramService = TelegramService();
  double _x = 0.0;
  double _y = 0.0;
  double _z = 0.0;
  double _totalAcceleration = 0.0;
  double _currentSpeed = 0.0;
  double _latitude = 0.0;
  double _longitude = 0.0;
  AccelerometerEvent? _currentAccEvent;

  @override
  void initState() {
    super.initState();
    AppConfig.loadSettings();
    _requestPermissions();
    _initializeLocationUpdates();
    _initializeAccelerometer();
    BackgroundService.startService();  // Start background service
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.activityRecognition.request();
    await Permission.sensors.request();
    await Geolocator.requestPermission();
  }

  void _initializeAccelerometer() {
    accelerometerEvents.listen((AccelerometerEvent event) async {
      if (!mounted) return;
      
      setState(() {
        _currentAccEvent = event;
        _x = event.x;
        _y = event.y;
        _z = event.z;
        _totalAcceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      });

      // Check for alerts when moving (outside setState)
      if (_currentSpeed > 0) {
        await _checkAndSendAlerts(event, _currentSpeed);
      }
    });
  }

  Future<void> _checkAndSendAlerts(AccelerometerEvent event, double speed) async {
    if (speed > AppConfig.speedThreshold) {
      await _telegramService.sendSpeedAlert(speed);
    }

    if (_sensorService.isSuddenAcceleration(event, AppConfig.suddenAccelerationThreshold)) {
      await _telegramService.sendSuddenEventAlert('acceleration', _totalAcceleration);
    }

    if (_sensorService.isSuddenBraking(event, AppConfig.suddenBrakingThreshold)) {
      await _telegramService.sendSuddenEventAlert('braking', _totalAcceleration);
    }

    if (_sensorService.isSharpTurn(event, AppConfig.sharpTurnThreshold)) {
      await _telegramService.sendSuddenEventAlert('turn', _totalAcceleration);
    }
  }

  void _log(String message) {
    print('SDM_LOG: $message');
  }

  void _initializeLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log('Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _log('Location permissions are denied');
        return;
      }
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      if (_dbService.shouldSample(position.speed * 3.6)) {
        final record = DrivingRecord(
          timestamp: DateTime.now(),
          speed: position.speed * 3.6,
          latitude: position.latitude,
          longitude: position.longitude,
          accelerationX: _x,
          accelerationY: _y,
          accelerationZ: _z,
          totalAcceleration: _totalAcceleration,
          isSuddenAcceleration: _currentAccEvent != null ? _sensorService.isSuddenAcceleration(_currentAccEvent!, AppConfig.suddenAccelerationThreshold) : false,
          isSuddenBraking: _currentAccEvent != null ? _sensorService.isSuddenBraking(_currentAccEvent!, AppConfig.suddenBrakingThreshold) : false,
          isSharpTurn: _currentAccEvent != null ? _sensorService.isSharpTurn(_currentAccEvent!, AppConfig.sharpTurnThreshold) : false,
        );
        _dbService.insertRecord(record);
      }
      setState(() {
        _currentSpeed = position.speed <= 0 ? 0.0 : (position.speed * 3.6).clamp(0, 200);
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOverSpeed = _currentSpeed > AppConfig.speedThreshold;
    final speedProgress = (_currentSpeed / AppConfig.speedThreshold).clamp(0.0, 1.5);
    final screenSize = MediaQuery.of(context).size;
    final speedometerSize = screenSize.width * 0.75;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Speed Display
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0, end: _currentSpeed),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, double speed, child) {
                      return Container(
                        width: speedometerSize,
                        height: speedometerSize,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[900],
                          boxShadow: [
                            BoxShadow(
                              color: isOverSpeed 
                                  ? Colors.red.withOpacity(0.3) 
                                  : Colors.blue.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: speedProgress,
                              strokeWidth: 15,
                              backgroundColor: Colors.grey[800],
                              color: isOverSpeed ? Colors.red : Colors.green,
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    speed.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: speedometerSize * 0.2,
                                      fontWeight: FontWeight.bold,
                                      color: isOverSpeed ? Colors.red : Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'km/h',
                                    style: TextStyle(
                                      fontSize: speedometerSize * 0.08,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Speed Limit Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOverSpeed ? Colors.red : Colors.grey,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed,
                          color: isOverSpeed ? Colors.red : Colors.grey[400],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Speed Limit: ${AppConfig.speedThreshold.toStringAsFixed(0)} km/h',
                          style: TextStyle(
                            color: isOverSpeed ? Colors.red : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Location Info
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900]?.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      '${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            // Settings and History Buttons
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.grey[900],
                    child: const Icon(Icons.history, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DriveListPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.grey[900],
                    child: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
