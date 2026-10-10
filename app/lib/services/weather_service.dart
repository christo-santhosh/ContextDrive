import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/context_vector.dart';

class WeatherCondition {
  const WeatherCondition({
    required this.temperature,
    required this.category,
    required this.visibilityMeters,
    required this.description,
    required this.isAvailable,
    required this.lastUpdated,
    this.sourceLatitude,
    this.sourceLongitude,
  });

  final double? temperature;
  final WeatherCategory category;
  final int? visibilityMeters;
  final String description;
  final bool isAvailable;
  final DateTime lastUpdated;
  final double? sourceLatitude;
  final double? sourceLongitude;

  bool get isRaining => category == WeatherCategory.rain || category == WeatherCategory.heavyRain;
}

/// OpenWeather request/cache adapter. The key is build-time configuration, not
/// source code. External weather describes the nearby area; it is never used
/// to assert that the road surface is wet.
class WeatherService {
  static const _refreshInterval = Duration(minutes: 15);
  static const _retryInterval = Duration(minutes: 5);
  final String _apiKey = const String.fromEnvironment('WEATHER_API_KEY');
  WeatherCondition? _cachedWeather;
  DateTime? _nextRetryAt;
  Future<WeatherCondition>? _activeRequest;
  String? lastError;

  bool get isConfigured => _apiKey.isNotEmpty;
  WeatherCondition? get currentWeather => _cachedWeather;

  Future<WeatherCondition> getWeather(double latitude, double longitude, {bool forceRefresh = false}) {
    final now = DateTime.now();
    if (!isConfigured) {
      lastError = 'WEATHER_API_KEY is not configured.';
      return Future.value(_cachedWeather ?? _unavailable(now, latitude, longitude));
    }
    final cached = _cachedWeather;
    final cacheCurrent = cached != null && cached.isAvailable &&
        now.difference(cached.lastUpdated) < _refreshInterval &&
        _distanceMetres(latitude, longitude, cached.sourceLatitude, cached.sourceLongitude) < 5000;
    if (!forceRefresh && cacheCurrent) return Future.value(cached);
    if (!forceRefresh && _nextRetryAt != null && now.isBefore(_nextRetryAt!)) {
      return Future.value(cached ?? _unavailable(now, latitude, longitude));
    }
    return _activeRequest ??= _fetch(latitude, longitude).whenComplete(() => _activeRequest = null);
  }

  Future<WeatherCondition> _fetch(double latitude, double longitude) async {
    final now = DateTime.now();
    try {
      final uri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
        'lat': '$latitude', 'lon': '$longitude', 'appid': _apiKey, 'units': 'metric',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw StateError('OpenWeather HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final weather = (data['weather'] as List?)?.cast<Map<String, dynamic>>();
      final primary = weather != null && weather.isNotEmpty ? weather.first : <String, dynamic>{};
      final id = (primary['id'] as num?)?.toInt();
      final description = primary['description']?.toString() ?? 'Reported conditions';
      _cachedWeather = WeatherCondition(
        temperature: (data['main'] as Map?)?['temp'] is num ? ((data['main'] as Map)['temp'] as num).toDouble() : null,
        category: _categoryFor(id, description),
        visibilityMeters: (data['visibility'] as num?)?.toInt(),
        description: description,
        isAvailable: true,
        lastUpdated: now,
        sourceLatitude: latitude,
        sourceLongitude: longitude,
      );
      lastError = null;
      _nextRetryAt = null;
      return _cachedWeather!;
    } catch (error) {
      lastError = '$error';
      _nextRetryAt = now.add(_retryInterval);
      debugPrint('Weather request failed: $error');
      return _cachedWeather ??= _unavailable(now, latitude, longitude);
    }
  }

  WeatherCondition _unavailable(DateTime now, double latitude, double longitude) => WeatherCondition(
    temperature: null,
    category: WeatherCategory.unknown,
    visibilityMeters: null,
    description: 'Weather unavailable',
    isAvailable: false,
    lastUpdated: now,
    sourceLatitude: latitude,
    sourceLongitude: longitude,
  );

  WeatherCategory _categoryFor(int? id, String description) {
    final text = description.toLowerCase();
    if (id == 741 || text.contains('fog')) return WeatherCategory.fog;
    if (id != null && ((id >= 200 && id < 300) || const {502, 503, 504, 511, 522, 531}.contains(id))) return WeatherCategory.heavyRain;
    if (id != null && id >= 300 && id < 600) return WeatherCategory.rain;
    // Only call ordinary cloud/clear codes clear. Unsupported phenomena (for
    // example snow, smoke, dust or provider changes) remain unknown rather
    // than being silently interpreted as favourable conditions.
    if (id != null && id >= 800 && id < 900) return WeatherCategory.clear;
    return WeatherCategory.unknown;
  }

  double _distanceMetres(double lat, double lon, double? lastLat, double? lastLon) {
    if (lastLat == null || lastLon == null) return double.infinity;
    const earthRadius = 6371000.0;
    final dLat = (lat - lastLat) * pi / 180;
    final dLon = (lon - lastLon) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) + cos(lat * pi / 180) * cos(lastLat * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }
}
