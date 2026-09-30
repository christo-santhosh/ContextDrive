import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class ImuService {
  StreamSubscription? _subscription;
  bool _isErratic = false;
  DateTime? _erraticUntil;

  /// Returns true if harsh braking or swerving was detected recently (within last 3 seconds)
  bool get isErratic {
    if (_erraticUntil != null && DateTime.now().isAfter(_erraticUntil!)) {
      _isErratic = false;
      _erraticUntil = null;
    }
    return _isErratic;
  }

  void start() {
    // UserAccelerometerEvent stream excludes gravity, giving pure linear acceleration in m/s^2
    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      // Calculate the magnitude of the 3D acceleration vector
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // Threshold: 4.5 m/s^2 (~0.45 G's) is universally considered harsh/aggressive driving
      if (magnitude > 4.5) {
        _isErratic = true;
        _erraticUntil = DateTime.now().add(const Duration(seconds: 3));
      }
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isErratic = false;
  }
}
