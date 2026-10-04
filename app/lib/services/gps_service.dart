import 'package:geolocator/geolocator.dart';

class SpeedReading {
  final double valueKmh;
  final bool isValid;
  final DateTime timestamp;
  final String? rejectionReason;

  SpeedReading({
    required this.valueKmh,
    required this.isValid,
    required this.timestamp,
    this.rejectionReason,
  });
}

class GpsService {
  final List<double> _speedBuffer = [0.0, 0.0, 0.0];
  Position? _lastAcceptedPosition;

  Future<bool> requestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // continuous 1Hz updates to feed the median filter
      ),
    );
  }

  SpeedReading processPosition(Position position, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();

    if (position.speed < 0) {
      return SpeedReading(valueKmh: 0, isValid: false, timestamp: now, rejectionReason: "Negative speed");
    }

    if (position.accuracy > 20.0) {
      return SpeedReading(valueKmh: 0, isValid: false, timestamp: now, rejectionReason: "Poor horizontal accuracy");
    }
    if (position.speedAccuracy > 2.0) {
      return SpeedReading(valueKmh: 0, isValid: false, timestamp: now, rejectionReason: "Poor speed accuracy");
    }

    if (now.difference(position.timestamp).inSeconds > 2) {
      return SpeedReading(valueKmh: 0, isValid: false, timestamp: now, rejectionReason: "Stale GNSS timestamp");
    }

    double rawKmh = position.speed * 3.6;

    if (_lastAcceptedPosition != null) {
      double timeDiff = position.timestamp.difference(_lastAcceptedPosition!.timestamp).inMilliseconds / 1000.0;
      if (timeDiff > 0.0) {
        double speedDiffMs = (position.speed - _lastAcceptedPosition!.speed).abs();
        double accel = speedDiffMs / timeDiff;
        if (accel > 10.0) { // > 1G acceleration is impossible for normal cars
          return SpeedReading(valueKmh: 0, isValid: false, timestamp: now, rejectionReason: "Impossible acceleration");
        }
      }
    }

    _speedBuffer.add(rawKmh);
    if (_speedBuffer.length > 5) {
      _speedBuffer.removeAt(0);
    }

    List<double> sorted = List.from(_speedBuffer)..sort();
    double medianKmh = sorted[sorted.length ~/ 2];

    if (medianKmh < 3.0) {
      medianKmh = 0.0;
    }

    _lastAcceptedPosition = position;
    return SpeedReading(valueKmh: medianKmh, isValid: true, timestamp: now);
  }
}
