class WeatherCondition {
  final double temperature;
  final bool isRaining;
  final int visibilityMeters;
  final String description;

  WeatherCondition({
    required this.temperature,
    required this.isRaining,
    required this.visibilityMeters,
    required this.description,
  });
}

class WeatherService {
  /// Fetch weather based on lat/lon
  /// Mocked for Phase 1.
  Future<WeatherCondition?> getWeather(double lat, double lon) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Mock data: Assume it's a clear day, no rain, high visibility
    // Future implementation will use the OpenWeather API here.
    return WeatherCondition(
      temperature: 28.0,
      isRaining: false,
      visibilityMeters: 10000,
      description: 'Clear sky',
    );
  }
}
