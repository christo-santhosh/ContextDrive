class ContextVector {
  final double currentSpeed;
  final bool isRaining;
  final bool isNight;
  final int visibility;
  final int nearbyVehicles;
  final double closestVehicleDistance; // smaller = closer
  final bool isClosingIn; // true if the vehicle is getting closer

  ContextVector({
    required this.currentSpeed,
    required this.isRaining,
    required this.isNight,
    required this.visibility,
    required this.nearbyVehicles,
    required this.closestVehicleDistance,
    required this.isClosingIn,
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

enum RiskLevel { low, moderate, high }
