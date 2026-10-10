import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';
import '../models/context_vector.dart';

class TimeContextService {
  DateTime? _sunset;
  DateTime? _sunrise;

  /// Update the location to calculate accurate sunrise/sunset times
  void updateLocation(double lat, double lon) {
    final today = DateTime.now();
    // Some libraries double-apply offset if passed, or expect 0 for UTC.
    // By passing Duration.zero we get the true UTC event time, then convert toLocal().
    var calc = getSunriseSunset(lat, lon, Duration.zero, today.toUtc());
    _sunrise = calc.sunrise.toLocal();
    _sunset = calc.sunset.toLocal();
  }

  /// Determines if it is currently night time based on accurate local sunrise/sunset if available,
  /// otherwise uses a generic 6 PM - 6 AM heuristic.
  bool isNight(DateTime time) {
    if (_sunrise != null && _sunset != null) {
      // Ensure we compare local time to local time.
      final localSunrise = _sunrise!.toLocal();
      final localSunset = _sunset!.toLocal();
      final localTime = time.toLocal();
      
      return localTime.isBefore(localSunrise) || localTime.isAfter(localSunset);
    }
    
    // Simple heuristic: before 6 AM or after 6 PM (18:00)
    final localTime = time.toLocal();
    return localTime.hour < 6 || localTime.hour >= 18;
  }

  /// Returns dawn/dusk only when location-derived solar times are available.
  /// Without them the service reports unknown rather than presenting a rough
  /// device-clock heuristic as authoritative environmental context.
  DaylightCondition daylightCondition(DateTime time) {
    if (_sunrise == null || _sunset == null) return DaylightCondition.unknown;
    final local = time.toLocal();
    final sunrise = _sunrise!.toLocal();
    final sunset = _sunset!.toLocal();
    const twilight = Duration(minutes: 30);
    if (local.isAfter(sunrise.subtract(twilight)) && local.isBefore(sunrise.add(twilight)) ||
        local.isAfter(sunset.subtract(twilight)) && local.isBefore(sunset.add(twilight))) {
      return DaylightCondition.dawnDusk;
    }
    return local.isBefore(sunrise) || local.isAfter(sunset)
        ? DaylightCondition.night
        : DaylightCondition.day;
  }

  /// Determines if the current time is on a weekend
  bool isWeekend(DateTime time) {
    // In Dart, DateTime.weekday is 1 for Monday, 7 for Sunday.
    return time.weekday == DateTime.saturday || time.weekday == DateTime.sunday;
  }
}
