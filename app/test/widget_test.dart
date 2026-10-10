import 'package:app/engine/risk_engine.dart';
import 'package:app/models/context_vector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured assessment preserves event, explanation and action', () {
    final assessment = RiskEngine().assessRisk(ContextVector(
      currentSpeed: 85,
      currentSpeedLimit: 60,
      weatherCategory: WeatherCategory.rain,
      daylightCondition: DaylightCondition.night,
      visibilityMeters: 500,
      isWeatherAvailable: true,
      nearbyVehicles: 0,
      closestVehicleDistance: 1,
      isClosingIn: false,
      motion: MotionClassification.normal,
    ));
    expect(assessment.level, RiskLevel.high);
    expect(assessment.whatHappened, isNotEmpty);
    expect(assessment.whyExplanation, isNotEmpty);
    expect(assessment.recommendation, isNotEmpty);
    expect(assessment.advisories, isNotEmpty);
  });
}
