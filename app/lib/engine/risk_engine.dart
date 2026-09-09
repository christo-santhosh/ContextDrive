import '../models/context_vector.dart';

class RiskEngine {
  /// Deterministic rule engine to calculate risk level based on the current ContextVector
  RiskAssessment assessRisk(ContextVector context) {
    RiskLevel level = RiskLevel.low;
    String how = "Normal driving conditions.";
    String why = "Your speed and environment are stable.";
    String recommendation = "Continue driving safely.";

    // Example deterministic rules based on PRD
    bool highSpeed = context.currentSpeed > 80.0;
    bool poorVisibility = context.isRaining || context.visibility < 1000 || context.isNight;
    bool vehicleClose = context.closestVehicleDistance > 0 && context.closestVehicleDistance < 0.2; // 0 to 1 scale

    if (highSpeed && vehicleClose && poorVisibility) {
      level = RiskLevel.high;
      how = "Risk increased because your speed is high and a vehicle is close ahead.";
      why = "Poor visibility (rain/night) reduces available safety margin, making this combination very dangerous.";
      recommendation = "Reduce speed immediately and increase following distance.";
    } else if (highSpeed && vehicleClose) {
      level = RiskLevel.moderate;
      how = "High speed combined with a close vehicle ahead.";
      why = "You have less time to react if the vehicle in front brakes abruptly.";
      recommendation = "Reduce speed and increase following distance.";
    } else if (vehicleClose && context.isClosingIn) {
      level = RiskLevel.moderate;
      how = "You are rapidly approaching the vehicle ahead.";
      why = "Your closing speed is too high for the current following distance.";
      recommendation = "Brake gently to increase gap.";
    } else if (poorVisibility && highSpeed) {
      level = RiskLevel.moderate;
      how = "High speed in poor visibility conditions.";
      why = "You cannot see far enough ahead to stop safely at this speed.";
      recommendation = "Reduce speed to match visibility conditions.";
    }

    return RiskAssessment(
      level: level,
      howExplanation: how,
      whyExplanation: why,
      recommendation: recommendation,
    );
  }
}
