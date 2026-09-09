class TimeContextService {
  /// Determines if the current time is considered "Night"
  bool isNight(DateTime time) {
    // Simple heuristic: before 6 AM or after 6 PM (18:00)
    // A more advanced version could use Sunrise/Sunset APIs based on GPS
    return time.hour < 6 || time.hour >= 18;
  }

  /// Determines if the current time is on a weekend
  bool isWeekend(DateTime time) {
    // In Dart, DateTime.weekday is 1 for Monday, 7 for Sunday.
    return time.weekday == DateTime.saturday || time.weekday == DateTime.sunday;
  }
}
