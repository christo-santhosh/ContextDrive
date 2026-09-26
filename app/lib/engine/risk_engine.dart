import '../models/context_vector.dart';

class RiskEngine {
  /// Deterministic rule engine to calculate risk level based on the current ContextVector
  RiskAssessment assessRisk(ContextVector context) {
    RiskLevel level = RiskLevel.low;
    String how = "Normal driving conditions.";
    String why = "Your speed and environment are stable.";
    String recommendation = "Continue driving safely.";

    // Example deterministic rules based on PRD
    bool hasSpeed = context.currentSpeed != null;
    bool highSpeed = hasSpeed && context.currentSpeed! > 60.0;
    bool veryHighSpeed = hasSpeed && context.currentSpeed! > 80.0;
    bool poorVisibility = context.isNight || (context.isWeatherAvailable && (context.isRaining || context.visibility < 1000));
    
    // Convert generic distance to categories based on our mapping in RiskManager
    bool isVeryNear = context.closestVehicleDistance <= 0.1;
    bool isNear = context.closestVehicleDistance <= 0.3 && !isVeryNear;

    if (isVeryNear && context.isClosingIn) {
      level = RiskLevel.high;
      how = "Risk increased because a vehicle is very close ahead and closing in.";
      why = "You are closing in rapidly and have minimal time to react.";
      recommendation = "Brake immediately to increase following distance.";
    } else if ((isNear && context.isClosingIn) || (isVeryNear)) {
      level = RiskLevel.moderate;
      how = "A vehicle is near and closing in, or very near.";
      why = "You have less time to react if the vehicle in front brakes abruptly.";
      recommendation = "Reduce speed and increase following distance.";
    } else if (veryHighSpeed && poorVisibility) {
      level = RiskLevel.moderate;
      how = "Very high speed in poor visibility conditions.";
      why = "You cannot see far enough ahead to stop safely at this speed.";
      recommendation = "Reduce speed to match visibility conditions.";
    } else if (!hasSpeed) {
      level = RiskLevel.limited;
      how = "Sensor data limited.";
      why = "GPS speed is unavailable or stale.";
      recommendation = "Drive with caution; assistance features limited.";
    }

    return RiskAssessment(
      level: level,
      howExplanation: how,
      whyExplanation: why,
      recommendation: recommendation,
    );
  }
}
