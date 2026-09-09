from enum import Enum

class RiskLevel(Enum):
    LOW = 1
    MODERATE = 2
    HIGH = 3

class RiskAssessment:
    def __init__(self, level, recommendation, why_explanation, how_explanation):
        self.level = level
        self.recommendation = recommendation
        self.why_explanation = why_explanation
        self.how_explanation = how_explanation

def evaluate_risk(closest_distance, is_closing_in, current_speed, is_raining, is_night):
    # This mirrors the Dart logic we wrote for ContextDrive

    if closest_distance < 0:
        closest_distance = 1.0  # default safe distance

    # Proximity thresholds
    critical_distance = 0.6  # Alerts when vehicle takes up about ~30% of screen
    warning_distance = 0.85  # Alerts when vehicle takes up about ~10% of screen

    # Baseline logic
    if closest_distance <= critical_distance and is_closing_in:
        return RiskAssessment(
            RiskLevel.HIGH,
            "BRAKE NOW",
            f"Object dangerously close ({closest_distance:.2f}) and closing in rapidly.",
            "Visual proximity breached threshold."
        )

    if current_speed > 60:
        if closest_distance <= warning_distance:
            return RiskAssessment(
                RiskLevel.HIGH,
                "Slow down immediately!",
                "High speed combined with close proximity is highly dangerous.",
                "Speed + Proximity rule triggered."
            )
        
        if is_raining:
            return RiskAssessment(
                RiskLevel.MODERATE,
                "Reduce speed due to rain.",
                "Wet roads increase braking distance at high speeds.",
                "Speed + Weather rule triggered."
            )

    if closest_distance <= warning_distance:
        level = RiskLevel.MODERATE
        if is_raining or is_night:
            level = RiskLevel.HIGH
        
        return RiskAssessment(
            level,
            "Increase following distance.",
            "Vehicle ahead is too close.",
            "Proximity warning."
        )

    return RiskAssessment(
        RiskLevel.LOW,
        "Normal Driving.",
        "Conditions are safe.",
        "No risk factors detected."
    )
