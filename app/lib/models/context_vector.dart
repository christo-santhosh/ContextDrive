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
  final bool isErraticDriving; // true if harsh braking or swerving detected

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
    this.isErraticDriving = false,
  });
}

class RiskAssessment {
  final RiskLevel level;
  final String howExplanation;
  final String whyExplanation;
  final String recommendation;

  RiskAssessment({
    required this.level,
    required this.howExplanation,
    required this.whyExplanation,
    required this.recommendation,
  });
}

enum RiskLevel { low, moderate, high, limited }
