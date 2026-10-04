import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app/services/gps_service.dart';

void main() {
  group('GpsService Speed Filtering', () {
    late GpsService gpsService;

    setUp(() {
      gpsService = GpsService();
    });

    Position mockPosition({
      required double speed,
      required double accuracy,
      required double speedAccuracy,
      required DateTime timestamp,
    }) {
      return Position(
        longitude: 0,
        latitude: 0,
        timestamp: timestamp,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: speed,
        speedAccuracy: speedAccuracy,
      );
    }

    test('Stationary phone for several minutes remains 0', () {
      final baseTime = DateTime.now().subtract(const Duration(minutes: 10));
      SpeedReading lastReading = SpeedReading(valueKmh: 0, isValid: false, timestamp: baseTime);

      for (int i = 0; i < 20; i++) {
        final pos = mockPosition(
          speed: 0.1, // Slight GNSS drift
          accuracy: 5.0,
          speedAccuracy: 0.5,
          timestamp: baseTime.add(Duration(seconds: i)),
        );
        lastReading = gpsService.processPosition(pos, currentTime: pos.timestamp);
      }
      
      expect(lastReading.isValid, isTrue);
      expect(lastReading.valueKmh, 0.0, reason: "Speed should be clamped to 0 when median < 3.0 km/h");
    });

    test('Reject single false 31 km/h outlier', () {
      final baseTime = DateTime.now();
      
      // Seed buffer with stationary
      for (int i = 0; i < 4; i++) {
        final pos = mockPosition(
          speed: 0.0,
          accuracy: 5.0,
          speedAccuracy: 0.5,
          timestamp: baseTime.subtract(Duration(seconds: 4 - i)),
        );
        gpsService.processPosition(pos, currentTime: pos.timestamp);
      }

      // Inject outlier (31 km/h = ~8.6 m/s)
      final outlier = mockPosition(
        speed: 8.6,
        accuracy: 25.0, // High inaccuracy
        speedAccuracy: 2.5,
        timestamp: baseTime,
      );
      
      final reading = gpsService.processPosition(outlier, currentTime: baseTime);
      expect(reading.isValid, isFalse);
      expect(reading.rejectionReason, "Poor horizontal accuracy");
      
      // Inject a valid baseline immediately before the acceleration outlier
      final validBaseline = mockPosition(
        speed: 0.0,
        accuracy: 5.0,
        speedAccuracy: 0.5,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      );
      gpsService.processPosition(validBaseline, currentTime: validBaseline.timestamp);

      // Inject outlier with good accuracy but impossible acceleration
      final accelOutlier = mockPosition(
        speed: 8.6,
        accuracy: 5.0,
        speedAccuracy: 0.5,
        timestamp: baseTime.add(const Duration(seconds: 1, milliseconds: 100)), // jumped 8.6 m/s in 0.1 seconds = 86 m/s^2!
      );
      
      final accelReading = gpsService.processPosition(accelOutlier, currentTime: accelOutlier.timestamp);
      expect(accelReading.isValid, isFalse);
      expect(accelReading.rejectionReason, "Impossible acceleration");
    });
    
    test('Vehicle moving normally eventually validates', () {
      final baseTime = DateTime.now();
      SpeedReading lastReading = SpeedReading(valueKmh: 0, isValid: false, timestamp: baseTime);
      
      // 5 consistent samples at 50 km/h (~13.8 m/s)
      for (int i = 0; i < 5; i++) {
        final pos = mockPosition(
          speed: 13.8,
          accuracy: 5.0,
          speedAccuracy: 0.5,
          timestamp: baseTime.add(Duration(seconds: i)),
        );
        lastReading = gpsService.processPosition(pos, currentTime: pos.timestamp);
      }
      
      expect(lastReading.isValid, isTrue);
      expect(lastReading.valueKmh, closeTo(49.68, 0.1));
    });
  });
}
