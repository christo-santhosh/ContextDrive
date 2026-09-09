import 'package:geolocator/geolocator.dart';

class GpsService {
  /// Check and request location permissions
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

  /// Get a stream of position updates
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // update every 1 meter
      ),
    );
  }

  /// Gets the speed in km/h from a Position object
  double getSpeedKmh(Position position) {
    // position.speed is in m/s
    if (position.speed < 0) return 0;
    return position.speed * 3.6;
  }
}
