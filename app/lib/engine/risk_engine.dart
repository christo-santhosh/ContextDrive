import '../models/context_vector.dart';

class RiskEngine {
  RiskAssessment assessRisk(ContextVector context) {
    RiskLevel level = RiskLevel.low;
    String how = "Normal driving conditions.";
    String why = "Your speed and environment are stable.";
    String recommendation = "Continue driving safely.";
    String primaryReason = "";
    List<String> evidenceReasons = [];
    List<String> contextModifiers = [];
    List<String> dataQuality = [];

    bool hasSpeed = context.currentSpeed != null;
    if (hasSpeed) {
      dataQuality.add("GPS valid");
    } else {
      dataQuality.add(context.gpsQualityReason ?? "GPS settling / unavailable");
    }

    if (context.isWeatherAvailable) {
      dataQuality.add("Weather current");
    } else {
      dataQuality.add("Weather stale/unavailable");
    }

    if (context.isRaining) {
      contextModifiers.add("Rain reported");
    }
    if (context.isNight) {
      contextModifiers.add("Night conditions");
    }
    if (hasSpeed) {
      contextModifiers.add("GPS speed ${context.currentSpeed!.toStringAsFixed(0)} km/h");
    }

    bool poorVisibility = context.isNight || (context.isWeatherAvailable && (context.isRaining || context.visibility < 1000));
    bool isVeryNear = context.closestVehicleDistance <= 0.1;
    bool isNear = context.closestVehicleDistance <= 0.3 && !isVeryNear;
    bool vulnerableRoadUserVeryNear =
        context.closestVulnerableRoadUserDistance <= 0.1;
    bool vulnerableRoadUserNear =
        context.closestVulnerableRoadUserDistance <= 0.3 &&
            !vulnerableRoadUserVeryNear;

    bool isSpeeding = hasSpeed && context.currentSpeedLimit != null && 
                      context.currentSpeed! > (context.currentSpeedLimit! + 10);

    // Evaluate risk hierarchy (highest to lowest)
    if (context.isErraticDriving && context.nearbyVehicles > 0) {
      level = RiskLevel.high;
      how = "IMU driving event detected near other vehicles.";
      why = "Erratic movements drastically increase the chance of a collision.";
      recommendation = "Drive smoothly. Avoid sudden maneuvers.";
      primaryReason = "Erratic driving near vehicles";
      evidenceReasons.add("IMU detected event");
      evidenceReasons.add("${context.nearbyVehicles} vehicles tracked");
    } else if (vulnerableRoadUserVeryNear &&
        context.isVulnerableRoadUserClosing) {
      level = RiskLevel.high;
      how = "A vulnerable road user is very near and visually approaching.";
      why = "A person or cyclist has little physical protection in a conflict.";
      recommendation = "Slow down and create more space.";
      primaryReason = "Vulnerable road user very near and closing";
      evidenceReasons.add(
        "${context.nearbyVulnerableRoadUsers} vulnerable road user(s) tracked",
      );
      evidenceReasons.add("Tracked object area is increasing");
    } else if (vulnerableRoadUserVeryNear ||
        (vulnerableRoadUserNear &&
            context.isVulnerableRoadUserClosing)) {
      level = RiskLevel.moderate;
      how = "A vulnerable road user is near the vehicle path.";
      why = "Reduced separation leaves less room to react safely.";
      recommendation = "Reduce speed and maintain a wider safety margin.";
      primaryReason = "Vulnerable road user nearby";
      evidenceReasons.add(
        "${context.nearbyVulnerableRoadUsers} vulnerable road user(s) tracked",
      );
      if (context.isVulnerableRoadUserClosing) {
        evidenceReasons.add("Tracked object area is increasing");
      }
    } else if (isVeryNear && context.isClosingIn) {
      level = RiskLevel.high;
      how = "Vehicle ahead is very near and visually approaching.";
      why = "You are closing in rapidly and have minimal time to react.";
      recommendation = "Increase following distance to maintain a safe gap.";
      primaryReason = "Vehicle very near and closing";
      evidenceReasons.add("Tracked vehicle area is increasing");
    } else if (context.isErraticDriving) {
      level = RiskLevel.moderate;
      how = "IMU driving event detected.";
      why = "Sudden movements reduce vehicle stability.";
      recommendation = "Drive smoothly. Avoid sudden maneuvers.";
      primaryReason = "Erratic driving detected";
      evidenceReasons.add("IMU detected event");
    } else if (isNear && context.isClosingIn) {
      level = RiskLevel.moderate;
      how = "A vehicle is near and closing in.";
      why = "You have less time to react if the vehicle in front brakes abruptly.";
      recommendation = "Check the road ahead and increase following distance if needed.";
      primaryReason = "Vehicle near and closing";
      evidenceReasons.add("Large vehicle region in camera view");
      evidenceReasons.add("Tracked vehicle area is increasing");
    } else if (isVeryNear) {
      level = RiskLevel.moderate;
      how = "A vehicle is very near.";
      why = "Following too closely reduces reaction time.";
      recommendation = "Increase following distance.";
      primaryReason = "Vehicle very near";
    } else if (hasSpeed && context.currentSpeed! > 80.0 && poorVisibility) {
      level = RiskLevel.moderate;
      how = "High speed in poor visibility conditions.";
      why = "You cannot see far enough ahead to stop safely at this speed.";
      recommendation = "Reduce speed to match visibility conditions.";
      primaryReason = "High speed in poor visibility";
    } else if (isSpeeding) {
      level = RiskLevel.moderate;
      how = "Speed limit exceeded by >10 km/h.";
      why = "You are traveling faster than the legal or safe limit for this road.";
      recommendation = "Reduce your speed to ${context.currentSpeedLimit} km/h.";
      primaryReason = "Speeding";
    } else if (!hasSpeed) {
      level = RiskLevel.limited;
      how = "Sensor data limited.";
      why = "GPS speed is settling or unavailable.";
      recommendation = "Drive with caution; assistance features limited.";
      primaryReason = "";
    }

    return RiskAssessment(
      level: level,
      howExplanation: how,
      whyExplanation: why,
      recommendation: recommendation,
      primaryReason: primaryReason,
      evidenceReasons: evidenceReasons,
      contextModifiers: contextModifiers,
      dataQuality: dataQuality,
    );
  }
}
