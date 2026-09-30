import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SensorService {
  // Singleton pattern
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // Stream controllers
  Stream<Position>? _locationStream;
  Stream<AccelerometerEvent>? _accelerometerStream;

  Future<bool> initializeServices() async {
    try {
      // Request location permissions
      final locationStatus = await Permission.location.request();
      if (locationStatus.isDenied) {
        return false;
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      // Initialize location updates
      _locationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      );

      // Initialize accelerometer
      _accelerometerStream = accelerometerEvents;

      return true;
    } catch (e) {
      print('Error initializing sensors: $e');
      return false;
    }
  }

  // Get current speed in km/h
  Stream<double> get speedStream {
    return _locationStream?.map((position) {
      // Convert m/s to km/h
      return (position.speed * 3.6).clamp(0.0, double.infinity);
    }) ?? Stream.value(0.0);
  }

  // Get accelerometer data
  Stream<AccelerometerEvent> get accelerometerStream {
    return _accelerometerStream ?? Stream.empty();
  }

  // Calculate if there's sudden acceleration
  bool isSuddenAcceleration(AccelerometerEvent event, double threshold) {
    // Positive Y acceleration indicates forward acceleration
    return event.y > threshold;
  }

  // Calculate if there's sudden braking
  bool isSuddenBraking(AccelerometerEvent event, double threshold) {
    // Negative Y acceleration indicates braking
    return event.y < threshold;
  }

  // Calculate if there's sharp turning
  bool isSharpTurn(AccelerometerEvent event, double threshold) {
    // Lateral acceleration (x-axis)
    return event.x.abs() > threshold;
  }

  Future<void> dispose() async {
    // Clean up resources if needed
  }
} 