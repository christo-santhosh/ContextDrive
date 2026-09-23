// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/context_vector.dart';
import 'package:app/engine/risk_engine.dart';

void main() {
  test('Risk engine deterministic test', () {
    final engine = RiskEngine();
    
    // High risk test
    final highRiskContext = ContextVector(
      currentSpeed: 90.0,
      isRaining: true,
      isNight: true,
      visibility: 500,
      isWeatherAvailable: true,
      nearbyVehicles: 2,
      closestVehicleDistance: 0.1,
      isClosingIn: true,
    );
    
    final highAssessment = engine.assessRisk(highRiskContext);
    expect(highAssessment.level, RiskLevel.high);
    
    // Low risk test
    final lowRiskContext = ContextVector(
      currentSpeed: 40.0,
      isRaining: false,
      isNight: false,
      visibility: 10000,
      isWeatherAvailable: true,
      nearbyVehicles: 0,
      closestVehicleDistance: 1.0,
      isClosingIn: false,
    );
    
    final lowAssessment = engine.assessRisk(lowRiskContext);
    expect(lowAssessment.level, RiskLevel.low);
  });
}
