import '../models/context_vector.dart';

class RiskEngine {
  RiskAssessment assessRisk(ContextVector context) {
    RiskLevel level = RiskLevel.low;
    String how = "Normal driving conditions.";
    String why = "No configured risk rule is currently triggered by available inputs.";
    String recommendation = "Continue driving safely.";
    String primaryReason = "No configured risk rule triggered";
    List<String> evidenceReasons = [];
    List<String> contextModifiers = [];
    List<String> dataQuality = [];

    bool hasSpeed = context.currentSpeed != null;
    if (hasSpeed) {
      dataQuality.add("Speed valid");
    } else {
      dataQuality.add(context.gpsQualityReason ?? "Speed settling / unavailable");
    }

    if (context.isWeatherAvailable) {
      dataQuality.add("Weather current");
    } else if (context.visibilityCategory == null) {
      dataQuality.add("Weather unavailable - visibility unknown");
    }

    if (context.isRaining) {
      contextModifiers.add("Rain reported");
    }
    if (context.isNight) {
      contextModifiers.add("Night conditions");
    }
    if (hasSpeed) {
      contextModifiers.add("Speed ${context.currentSpeed!.toStringAsFixed(0)} km/h");
    }

    final visibility = context.visibilityAssessment;
    final bool poorVisibility = visibility == VisibilityAssessment.poor;
    if (poorVisibility) {
      contextModifiers.add("Low visibility");
    } else if (visibility == VisibilityAssessment.unknown) {
      contextModifiers.add("Visibility conditions unknown");
    }

    bool isVeryNear = context.closestVehicleDistance <= 0.1;
    bool isNear = context.closestVehicleDistance <= 0.3 && !isVeryNear;

    bool isSpeeding = hasSpeed &&
        context.currentSpeedLimit != null &&
        context.currentSpeed! > (context.currentSpeedLimit! + 10);

    // Evaluate risk hierarchy (highest to lowest)
    // Rule 1: High-magnitude motion near tracked vehicle (HIGH)
    if (context.isErraticDriving && context.nearbyVehicles > 0 && (isVeryNear || isNear)) {
      level = RiskLevel.high;
      how = "High-magnitude motion detected while a tracked vehicle is visually proximal.";
      why = "Abrupt vehicle dynamics combined with proximal traffic creates elevated hazard.";
      recommendation = "Maintain steady vehicle control and increase clearance.";
      primaryReason = "High-magnitude motion near tracked vehicle";
      evidenceReasons.add("High-magnitude motion heuristic active");
      evidenceReasons.add("Tracked vehicle within proximity threshold");
    }
    // Rule 2: Rapid optical approach at close range (HIGH)
    else if (isVeryNear && context.isClosingIn) {
      level = RiskLevel.high;
      how = "Tracked vehicle bounding area exceeds close-proximity threshold and is expanding rapidly.";
      why = "Forward buffer is minimal and rapidly decreasing.";
      recommendation = "Increase following distance immediately.";
      primaryReason = "Rapid optical approach at close range";
      evidenceReasons.add("Tracked vehicle bounding area exceeds close threshold");
      evidenceReasons.add("Bounding area growth rate indicates closing in");
    }
    // Rule 3: Isolated high-magnitude motion (MODERATE)
    else if (context.isErraticDriving) {
      level = RiskLevel.moderate;
      how = "High-magnitude acceleration detected; direction and cause are not classified.";
      why = "Elevated acceleration forces reduce vehicle stability margin.";
      recommendation = "Drive smoothly to maintain vehicle stability.";
      primaryReason = "High-magnitude motion detected";
      evidenceReasons.add("High-magnitude motion heuristic active");
    }
    // Rule 4: Tracked vehicle closing in at medium range (MODERATE)
    else if (isNear && context.isClosingIn) {
      level = RiskLevel.moderate;
      how = "Tracked vehicle bounding area is growing in view; buffer space is reducing.";
      why = "Forward visual headway is diminishing.";
      recommendation = "Monitor road ahead and prepare to decelerate.";
      primaryReason = "Tracked vehicle closing in";
      evidenceReasons.add("Tracked vehicle in proximity threshold");
      evidenceReasons.add("Bounding area growth rate indicates closing in");
    }
    // Rule 5: Tracked vehicle at close range (static / not closing in) (MODERATE)
    else if (isVeryNear) {
      level = RiskLevel.moderate;
      how = "Detected vehicle exceeds configured visual-proximity threshold.";
      why = "Operating with a compact visual headway to tracked vehicle.";
      recommendation = "Increase following distance.";
      primaryReason = "Detected vehicle exceeds visual-proximity threshold";
      evidenceReasons.add("Tracked vehicle bounding area exceeds close threshold");
    }
    // Rule 6: High speed in poor visibility (MODERATE)
    else if (hasSpeed && context.currentSpeed! > 80.0 && poorVisibility) {
      level = RiskLevel.moderate;
      how = "Speed exceeds 80 km/h under low visibility or active precipitation.";
      why = "Stopping sight distance exceeds visual range under reduced visibility.";
      recommendation = "Reduce speed to match visibility conditions.";
      primaryReason = "High speed in poor visibility";
      evidenceReasons.add("Speed exceeds 80 km/h");
      evidenceReasons.add("Poor visibility conditions active");
    }
    // Rule 7: Speed limit exceeded by >10 km/h (MODERATE)
    else if (isSpeeding) {
      level = RiskLevel.moderate;
      how = "Vehicle speed exceeds configured road speed limit by >10 km/h.";
      why = "Traveling faster than the applicable road speed limit.";
      recommendation = "Reduce speed to ${context.currentSpeedLimit} km/h.";
      primaryReason = "Speed limit exceeded by >10 km/h";
      evidenceReasons.add("Speed ${context.currentSpeed!.toStringAsFixed(0)} km/h vs limit ${context.currentSpeedLimit} km/h");
    }
    // Rule 8: Sensor speed unavailable (LIMITED)
    else if (!hasSpeed) {
      level = RiskLevel.limited;
      how = "Sensor data limited.";
      why = "Speed data is settling, unavailable, or telemetry is disconnected.";
      recommendation = "Drive with caution; assistance features limited.";
      primaryReason = "Sensor speed unavailable";
      evidenceReasons.add(context.gpsQualityReason ?? "Speed data unavailable");
    }
    // Rule 9: Nominal driving conditions (LOW)
    else {
      level = RiskLevel.low;
      how = "Normal driving conditions.";
      why = "No configured risk rule is currently triggered by available inputs.";
      recommendation = "Continue driving safely.";
      primaryReason = "No configured risk rule triggered";
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

