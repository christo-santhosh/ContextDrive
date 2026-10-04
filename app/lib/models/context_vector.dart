class ContextVector {
  final double? currentSpeed;
  final int? currentSpeedLimit;
  final bool isRaining;
  final bool isNight;
  final int visibility;
  final bool isWeatherAvailable;
  final int nearbyVehicles;
  final double closestVehicleDistance; // smaller = closer
  final bool isClosingIn; // true if the vehicle is getting closer
  final int nearbyVulnerableRoadUsers;
  final double closestVulnerableRoadUserDistance;
  final bool isVulnerableRoadUserClosing;
  final bool isErraticDriving; // true if harsh braking or swerving detected
  final String? gpsQualityReason;

  ContextVector({
    required this.currentSpeed,
    required this.currentSpeedLimit,
    required this.isRaining,
    required this.isNight,
    required this.visibility,
    required this.isWeatherAvailable,
    required this.nearbyVehicles,
    required this.closestVehicleDistance,
    required this.isClosingIn,
    this.nearbyVulnerableRoadUsers = 0,
    this.closestVulnerableRoadUserDistance = 1.0,
    this.isVulnerableRoadUserClosing = false,
    this.isErraticDriving = false,
    this.gpsQualityReason,
  });
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
    );
  }
}

enum RiskLevel { low, moderate, high, limited }
