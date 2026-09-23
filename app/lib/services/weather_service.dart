import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WeatherCondition {
  final double temperature;
  final bool isRaining;
  final int visibilityMeters;
  final String description;
  final bool isAvailable;
  final DateTime lastUpdated;

  WeatherCondition({
    required this.temperature,
    required this.isRaining,
    required this.visibilityMeters,
    required this.description,
    required this.isAvailable,
    required this.lastUpdated,
  });
}

class WeatherService {
  final String _apiKey = const String.fromEnvironment('WEATHER_API_KEY');
  
  WeatherCondition? _cachedWeather;
  double? _lastLat;
  double? _lastLon;

  Future<WeatherCondition> getWeather(double lat, double lon) async {
    final now = DateTime.now();
    
    // Refresh if > 15 mins old or moved more than roughly 5km
    bool shouldRefresh = _cachedWeather == null || !_cachedWeather!.isAvailable;
    if (_cachedWeather != null) {
      if (now.difference(_cachedWeather!.lastUpdated).inMinutes > 15) {
        shouldRefresh = true;
      }
      if (_lastLat != null && _lastLon != null) {
        double distLat = (lat - _lastLat!).abs();
        double distLon = (lon - _lastLon!).abs();
        if (distLat > 0.05 || distLon > 0.05) { // Roughly 5km
          shouldRefresh = true;
        }
      }
    }

    if (!shouldRefresh) {
      return _cachedWeather!;
    }

    WeatherCondition unavailableWeather() => WeatherCondition(
      temperature: 20.0,
      isRaining: false,
      visibilityMeters: 10000,
      description: 'Unknown',
      isAvailable: false,
      lastUpdated: now,
    );

    if (_apiKey.isEmpty) {
      debugPrint('No WEATHER_API_KEY provided. Using unavailable weather status.');
      _cachedWeather = unavailableWeather();
      return _cachedWeather!;
    }

    try {
      final url = Uri.parse('https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final temp = (data['main']['temp'] as num).toDouble();
        final visibility = (data['visibility'] as num?)?.toInt() ?? 10000;
        final weatherArray = data['weather'] as List<dynamic>;
        
        bool isRaining = false;
        String desc = '';
        if (weatherArray.isNotEmpty) {
          final id = weatherArray[0]['id'] as int;
          desc = weatherArray[0]['description'] as String;
          // OpenWeatherMap IDs starting with 2, 3, or 5 are rain/drizzle/thunderstorm
          isRaining = (id >= 200 && id < 600);
        }

        _lastLat = lat;
        _lastLon = lon;
        _cachedWeather = WeatherCondition(
          temperature: temp,
          isRaining: isRaining,
          visibilityMeters: visibility,
          description: desc,
          isAvailable: true,
          lastUpdated: now,
        );
        return _cachedWeather!;
      } else {
        debugPrint('Weather API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Weather API exception: $e');
    }
    
    _cachedWeather = unavailableWeather();
    return _cachedWeather!;
  }
}
