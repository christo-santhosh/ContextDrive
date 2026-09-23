import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';

class TimeContextService {
  DateTime? _sunset;
  DateTime? _sunrise;

  /// Update the location to calculate accurate sunrise/sunset times
  void updateLocation(double lat, double lon) {
    final today = DateTime.now();
    var calc = getSunriseSunset(lat, lon, today.timeZoneOffset, today);
    _sunrise = calc.sunrise;
    _sunset = calc.sunset;
  }

  /// Determines if it is currently night time based on accurate local sunrise/sunset if available,
  /// otherwise uses a generic 6 PM - 6 AM heuristic.
  bool isNight(DateTime time) {
    if (_sunrise != null && _sunset != null) {
      // If now is before sunrise OR after sunset, it's night.
      return time.isBefore(_sunrise!) || time.isAfter(_sunset!);
    }
    
    // Simple heuristic: before 6 AM or after 6 PM (18:00)
    return time.hour < 6 || time.hour >= 18;
  }

  /// Determines if the current time is on a weekend
  bool isWeekend(DateTime time) {
    // In Dart, DateTime.weekday is 1 for Monday, 7 for Sunday.
    return time.weekday == DateTime.saturday || time.weekday == DateTime.sunday;
  }
}
