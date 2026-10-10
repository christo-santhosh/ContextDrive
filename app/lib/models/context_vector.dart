enum VisibilityAssessment {
  poor,
  adequate,
  unknown,
}

class ContextVector {
  final double? currentSpeed;
  final int? currentSpeedLimit;
  final bool isRaining;
  final bool isNight;
  final int visibility;
  final bool isWeatherAvailable;
  final VisibilityAssessment visibilityAssessment;
  final String? visibilityCategory;
  final int nearbyVehicles;
  final double closestVehicleDistance; // smaller = closer
  final bool isClosingIn; // true if the vehicle is getting closer
  final bool isErraticDriving; // true if high-magnitude motion detected
  final String? gpsQualityReason;

  ContextVector({
    required this.currentSpeed,
    required this.currentSpeedLimit,
    required this.isRaining,
    required this.isNight,
    required this.visibility,
    required this.isWeatherAvailable,
    VisibilityAssessment? visibilityAssessment,
    this.visibilityCategory,
    required this.nearbyVehicles,
    required this.closestVehicleDistance,
    required this.isClosingIn,
    this.isErraticDriving = false,
    this.gpsQualityReason,
  }) : visibilityAssessment = visibilityAssessment ??
            calculateVisibility(
              isNight: isNight,
              isRaining: isRaining,
              visibilityMeters: visibility,
              isWeatherAvailable: isWeatherAvailable,
              visibilityCategory: visibilityCategory,
            );

  static VisibilityAssessment calculateVisibility({
    required bool isNight,
    required bool isRaining,
    required int? visibilityMeters,
    required bool isWeatherAvailable,
    String? visibilityCategory,
  }) {
    final cat = visibilityCategory?.toLowerCase().trim();

    // 1. Explicit categorical indication of poor visibility
    if (cat == 'poor' || cat == 'foggy' || cat == 'heavy_rain' || cat == 'dense_fog') {
      return VisibilityAssessment.poor;
    }

    // 2. Definitive physical poor visibility triggers (must not be bypassed by clear category)
    if (isNight) {
      return VisibilityAssessment.poor;
    }
    if (isRaining) {
      return VisibilityAssessment.poor;
    }
    if (isWeatherAvailable && visibilityMeters != null && visibilityMeters < 1000) {
      return VisibilityAssessment.poor;
    }

    // 3. Positive verification of adequate visibility
    if (cat == 'clear' || cat == 'adequate') {
      return VisibilityAssessment.adequate;
    }
    if (isWeatherAvailable && visibilityMeters != null && visibilityMeters >= 1000) {
      return VisibilityAssessment.adequate;
    }

    // 4. Missing or unknown environmental context: NEVER interpret as clear/adequate
    return VisibilityAssessment.unknown;
  }
}

class RiskAssessment {
  final RiskLevel level;
  final String howExplanation;
  final String whyExplanation;
  final String recommendation;
  final String primaryReason;
  final List<String> evidenceReasons;
  final List<String> contextModifiers;
  final List<String> dataQuality;
  final DateTime? raisedAt;
  final RiskLevel? previousLevel;
  final bool isStale;

  RiskAssessment({
    required this.level,
    required this.howExplanation,
    required this.whyExplanation,
    required this.recommendation,
    this.primaryReason = "",
    this.evidenceReasons = const [],
    this.contextModifiers = const [],
    this.dataQuality = const [],
    this.raisedAt,
    this.previousLevel,
    this.isStale = false,
  });

  RiskAssessment copyWith({
    RiskLevel? level,
    String? howExplanation,
    String? whyExplanation,
    String? recommendation,
    String? primaryReason,
    List<String>? evidenceReasons,
    List<String>? contextModifiers,
    List<String>? dataQuality,
    DateTime? raisedAt,
    RiskLevel? previousLevel,
    bool? isStale,
  }) {
    return RiskAssessment(
      level: level ?? this.level,
      howExplanation: howExplanation ?? this.howExplanation,
      whyExplanation: whyExplanation ?? this.whyExplanation,
      recommendation: recommendation ?? this.recommendation,
      primaryReason: primaryReason ?? this.primaryReason,
      evidenceReasons: evidenceReasons ?? this.evidenceReasons,
      contextModifiers: contextModifiers ?? this.contextModifiers,
      dataQuality: dataQuality ?? this.dataQuality,
      raisedAt: raisedAt ?? this.raisedAt,
      previousLevel: previousLevel ?? this.previousLevel,
      isStale: isStale ?? this.isStale,
    );
  }
}

enum RiskLevel { low, moderate, high, limited }

