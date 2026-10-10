/// The observed environmental category. `unknown` is deliberately distinct
/// from clear weather: a missing provider response must never imply good
/// conditions.
enum WeatherCategory { unknown, clear, rain, heavyRain, fog }

enum DaylightCondition { unknown, day, dawnDusk, night }

enum VisibilityAssessment { poor, adequate, unknown }

/// Directional motion is only emitted when the source can support it.
/// Physical phone IMU remains [unknown] until mount calibration exists.
enum MotionClassification { unknown, normal, hardBraking, rapidAcceleration }

/// Hazard severity. It is not a probability of collision and is independent
/// from input availability.
enum RiskLevel { low, moderate, high, critical }

/// Quality/status of the inputs used by an assessment. A known hazard remains
/// visible even when this is limited.
enum AssessmentDataQuality { good, limited, stale }

class ContextVector {
  final double? currentSpeed;
  final int? currentSpeedLimit;
  final WeatherCategory weatherCategory;
  final DaylightCondition daylightCondition;
  final int? visibilityMeters;
  final bool isWeatherAvailable;
  final VisibilityAssessment visibilityAssessment;
  final int nearbyVehicles;
  /// Visual proxy derived from a tracked bounding-box area, not metres.
  final double closestVehicleDistance;
  final bool isClosingIn;
  final MotionClassification motion;
  /// Signed longitudinal acceleration in m/s² where available. Positive is
  /// acceleration in the direction of travel; negative is deceleration.
  final double? longitudinalAcceleration;
  final bool telemetryFresh;
  final String? speedQualityReason;
  final String? weatherQualityReason;
  final String? timeQualityReason;

  ContextVector({
    required this.currentSpeed,
    required this.currentSpeedLimit,
    required this.weatherCategory,
    required this.daylightCondition,
    required this.visibilityMeters,
    required this.isWeatherAvailable,
    required this.nearbyVehicles,
    required this.closestVehicleDistance,
    required this.isClosingIn,
    required this.motion,
    this.longitudinalAcceleration,
    this.telemetryFresh = true,
    this.speedQualityReason,
    this.weatherQualityReason,
    this.timeQualityReason,
    VisibilityAssessment? visibilityAssessment,
  }) : visibilityAssessment = visibilityAssessment ??
            calculateVisibility(
              weatherCategory: weatherCategory,
              daylightCondition: daylightCondition,
              visibilityMeters: visibilityMeters,
              isWeatherAvailable: isWeatherAvailable,
            );

  bool get isRaining => weatherCategory == WeatherCategory.rain || weatherCategory == WeatherCategory.heavyRain;
  bool get isNight => daylightCondition == DaylightCondition.night;

  static VisibilityAssessment calculateVisibility({
    required WeatherCategory weatherCategory,
    required DaylightCondition daylightCondition,
    required int? visibilityMeters,
    required bool isWeatherAvailable,
  }) {
    if (weatherCategory == WeatherCategory.fog || weatherCategory == WeatherCategory.heavyRain || daylightCondition == DaylightCondition.night || (isWeatherAvailable && visibilityMeters != null && visibilityMeters < RiskThresholds.poorVisibilityMeters)) {
      return VisibilityAssessment.poor;
    }
    if (isWeatherAvailable && visibilityMeters != null && visibilityMeters >= RiskThresholds.poorVisibilityMeters) {
      return VisibilityAssessment.adequate;
    }
    return VisibilityAssessment.unknown;
  }
}

/// Centralised, provisional deterministic rule limits. They are not claimed
/// to be calibrated road-safety or collision metrics.
abstract final class RiskThresholds {
  static const double veryNearVisualProxy = 0.10;
  static const double nearVisualProxy = 0.30;
  static const int poorVisibilityMeters = 1000;
  static const double speedLimitModerateExcessKmh = 10;
  static const double speedLimitHighExcessKmh = 20;
  static const double highSpeedPoorVisibilityKmh = 80;
  static const double minimumMotionSpeedKmh = 5;
  static const double hardBrakingMps2 = -3.5;
  static const double rapidAccelerationMps2 = 3.0;
}

class MotionClassifier {
  const MotionClassifier._();

  static MotionClassification classify({required double? speedKmh, required double? longitudinalAcceleration}) {
    if (speedKmh == null || speedKmh < RiskThresholds.minimumMotionSpeedKmh || longitudinalAcceleration == null) {
      return MotionClassification.unknown;
    }
    if (longitudinalAcceleration <= RiskThresholds.hardBrakingMps2) return MotionClassification.hardBraking;
    if (longitudinalAcceleration >= RiskThresholds.rapidAccelerationMps2) return MotionClassification.rapidAcceleration;
    return MotionClassification.normal;
  }
}

/// A structured output that keeps hazard, input quality and environmental
/// guidance separate for the HUD and voice-alert lifecycle.
class RiskAssessment {
  final RiskLevel level;
  final AssessmentDataQuality dataQualityStatus;
  final String whatHappened;
  final String whyExplanation;
  final String recommendation;
  final String primaryReason;
  final List<String> evidenceReasons;
  final List<String> contextModifiers;
  final List<String> dataQuality;
  final List<String> advisories;
  final List<String> activeEvents;
  final DateTime? raisedAt;
  final RiskLevel? previousLevel;
  final bool isStale;

  const RiskAssessment({
    required this.level,
    required this.dataQualityStatus,
    required this.whatHappened,
    required this.whyExplanation,
    required this.recommendation,
    this.primaryReason = '',
    this.evidenceReasons = const [],
    this.contextModifiers = const [],
    this.dataQuality = const [],
    this.advisories = const [],
    this.activeEvents = const [],
    this.raisedAt,
    this.previousLevel,
    this.isStale = false,
  });

  /// Compatibility alias used by the existing HUD and event history.
  String get howExplanation => whatHappened;
  bool get hasHazard => level != RiskLevel.low;

  RiskAssessment copyWith({
    RiskLevel? level,
    AssessmentDataQuality? dataQualityStatus,
    String? whatHappened,
    String? whyExplanation,
    String? recommendation,
    String? primaryReason,
    List<String>? evidenceReasons,
    List<String>? contextModifiers,
    List<String>? dataQuality,
    List<String>? advisories,
    List<String>? activeEvents,
    DateTime? raisedAt,
    RiskLevel? previousLevel,
    bool? isStale,
  }) => RiskAssessment(
    level: level ?? this.level,
    dataQualityStatus: dataQualityStatus ?? this.dataQualityStatus,
    whatHappened: whatHappened ?? this.whatHappened,
    whyExplanation: whyExplanation ?? this.whyExplanation,
    recommendation: recommendation ?? this.recommendation,
    primaryReason: primaryReason ?? this.primaryReason,
    evidenceReasons: evidenceReasons ?? this.evidenceReasons,
    contextModifiers: contextModifiers ?? this.contextModifiers,
    dataQuality: dataQuality ?? this.dataQuality,
    advisories: advisories ?? this.advisories,
    activeEvents: activeEvents ?? this.activeEvents,
    raisedAt: raisedAt ?? this.raisedAt,
    previousLevel: previousLevel ?? this.previousLevel,
    isStale: isStale ?? this.isStale,
  );
}
