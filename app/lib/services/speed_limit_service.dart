import 'dart:convert';
import 'package:http/http.dart' as http;

class SpeedLimitService {
  int? _currentSpeedLimit;
  DateTime? _lastUpdated;
  
  int? get currentSpeedLimit => _currentSpeedLimit;
  bool get isAvailable => _currentSpeedLimit != null;

  /// Fetches the speed limit for a given coordinate using Overpass API (OpenStreetMap)
  Future<void> updateSpeedLimit(double lat, double lon) async {
    // Only update every 30 seconds to avoid spamming the free API
    if (_lastUpdated != null && DateTime.now().difference(_lastUpdated!).inSeconds < 30) {
      return;
    }
    
    // We search within a 30-meter radius for a road with a maxspeed tag
    final query = '[out:json];way(around:30, $lat, $lon)["maxspeed"];out tags;';
    final uri = Uri.parse('https://overpass-api.de/api/interpreter');
    
    try {
      final response = await http.post(uri, body: query).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['elements'] != null && data['elements'].isNotEmpty) {
          final tags = data['elements'][0]['tags'];
          if (tags != null && tags['maxspeed'] != null) {
            String maxSpeedStr = tags['maxspeed'].toString().toLowerCase();
            
            // Handle different formats (e.g. "50 mph" vs "80")
            if (maxSpeedStr.contains('mph')) {
              int mph = int.tryParse(maxSpeedStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (mph > 0) _currentSpeedLimit = (mph * 1.60934).round();
            } else {
              int kmh = int.tryParse(maxSpeedStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (kmh > 0) _currentSpeedLimit = kmh;
            }
            
            _lastUpdated = DateTime.now();
            return;
          }
        }
      }
    } catch (e) {
      // Failed to fetch (e.g. no internet), let it fallback below
    }
    
    // If we couldn't fetch a new one, invalidate the old one after 2 minutes
    if (_lastUpdated == null || DateTime.now().difference(_lastUpdated!).inMinutes > 2) {
      _currentSpeedLimit = null;
    }
  }
}
