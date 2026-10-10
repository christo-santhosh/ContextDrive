import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/context_vector.dart';
import 'package:app/engine/risk_engine.dart';

void main() {
  late RiskEngine engine;

  setUp(() {
    engine = RiskEngine();
  });

  group('RiskEngine Predicates & Hierarchy (v3.0 Grounded)', () {
    test('Rule 1: High-magnitude motion near tracked vehicle triggers HIGH risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.25, // Near
        isClosingIn: false,
        isErraticDriving: true,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.high);
      expect(assessment.primaryReason, 'High-magnitude motion near tracked vehicle');
      expect(assessment.howExplanation, contains('High-magnitude motion detected while a tracked vehicle is visually proximal'));
      expect(assessment.evidenceReasons, contains('High-magnitude motion heuristic active'));
      expect(assessment.evidenceReasons, contains('Tracked vehicle within proximity threshold'));
    });

    test('Rule 2: Rapid optical approach at close range triggers HIGH risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.08, // Very Near (<= 0.1)
        isClosingIn: true,
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.high);
      expect(assessment.primaryReason, 'Rapid optical approach at close range');
      expect(assessment.howExplanation, contains('Tracked vehicle bounding area exceeds close-proximity threshold and is expanding rapidly'));
      expect(assessment.evidenceReasons, contains('Tracked vehicle bounding area exceeds close threshold'));
      expect(assessment.evidenceReasons, contains('Bounding area growth rate indicates closing in'));
    });

    test('Rule 3: Isolated high-magnitude motion (no vehicles nearby) triggers MODERATE risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
        isErraticDriving: true,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.primaryReason, 'High-magnitude motion detected');
      expect(assessment.howExplanation, contains('High-magnitude acceleration detected; direction and cause are not classified'));
      expect(assessment.evidenceReasons, contains('High-magnitude motion heuristic active'));
    });

    test('Rule 4: Tracked vehicle closing in at medium range triggers MODERATE risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.25, // Near (0.1 < d <= 0.3)
        isClosingIn: true,
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.primaryReason, 'Tracked vehicle closing in');
      expect(assessment.howExplanation, contains('Tracked vehicle bounding area is growing in view; buffer space is reducing'));
    });

    test('Rule 5: Static very-near vehicle (NOT closing in) triggers MODERATE risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.08, // Very Near
        isClosingIn: false, // Static gap!
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.primaryReason, 'Detected vehicle exceeds visual-proximity threshold');
      expect(assessment.howExplanation, contains('Detected vehicle exceeds configured visual-proximity threshold'));
    });

    test('Rule 6: High speed in poor visibility triggers MODERATE risk', () {
      final context = ContextVector(
        currentSpeed: 85.0,
        currentSpeedLimit: 100,
        isRaining: true, // Poor visibility
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.primaryReason, 'High speed in poor visibility');
      expect(assessment.howExplanation, contains('Speed exceeds 80 km/h under low visibility or active precipitation'));
      expect(assessment.evidenceReasons, contains('Speed exceeds 80 km/h'));
      expect(assessment.evidenceReasons, contains('Poor visibility conditions active'));
    });

    test('Rule 7: Speed limit exceeded by >10 km/h triggers MODERATE risk', () {
      final context = ContextVector(
        currentSpeed: 72.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.primaryReason, 'Speed limit exceeded by >10 km/h');
      expect(assessment.howExplanation, contains('Vehicle speed exceeds configured road speed limit by >10 km/h'));
    });

    test('Rule 8: Missing sensor speed triggers LIMITED risk', () {
      final context = ContextVector(
        currentSpeed: null,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
        isErraticDriving: false,
        gpsQualityReason: 'GNSS settling',
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.limited);
      expect(assessment.primaryReason, 'Sensor speed unavailable');
      expect(assessment.howExplanation, contains('Sensor data limited'));
      expect(assessment.evidenceReasons, contains('GNSS settling'));
    });

    test('Rule 9: Nominal conditions triggers LOW risk', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.level, RiskLevel.low);
      expect(assessment.primaryReason, 'No configured risk rule triggered');
      expect(assessment.whyExplanation, 'No configured risk rule is currently triggered by available inputs.');
    });
  });

  group('Threshold Boundary Conditions', () {
    test('Proximity boundary: 0.10 is Very Near, 0.101 is Near', () {
      final ctxVeryNear = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.10, // Exactly at 0.10 threshold
        isClosingIn: false,
      );
      expect(engine.assessRisk(ctxVeryNear).primaryReason, 'Detected vehicle exceeds visual-proximity threshold');

      final ctxNear = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.101, // Just above 0.10
        isClosingIn: false,
      );
      // Not very near and not closing in -> no rule triggered -> Low
      expect(engine.assessRisk(ctxNear).level, RiskLevel.low);
    });

    test('Proximity boundary: 0.30 is Near, 0.301 is Far', () {
      final ctxNearClosing = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.30,
        isClosingIn: true,
      );
      expect(engine.assessRisk(ctxNearClosing).primaryReason, 'Tracked vehicle closing in');

      final ctxFarClosing = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.301,
        isClosingIn: true,
      );
      // Beyond 0.30 -> not proximal -> Low
      expect(engine.assessRisk(ctxFarClosing).level, RiskLevel.low);
    });

    test('Speed boundary for poor visibility: 80.0 km/h is nominal, 80.1 km/h triggers', () {
      final ctx80 = ContextVector(
        currentSpeed: 80.0,
        currentSpeedLimit: 100,
        isRaining: true,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
      );
      expect(engine.assessRisk(ctx80).level, RiskLevel.low);

      final ctx80_1 = ContextVector(
        currentSpeed: 80.1,
        currentSpeedLimit: 100,
        isRaining: true,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
      );
      expect(engine.assessRisk(ctx80_1).primaryReason, 'High speed in poor visibility');
    });

    test('Speed limit boundary: speedLimit + 10 exactly is nominal, + 10.1 triggers', () {
      final ctxAtMargin = ContextVector(
        currentSpeed: 60.0,
        currentSpeedLimit: 50,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
      );
      expect(engine.assessRisk(ctxAtMargin).level, RiskLevel.low);

      final ctxOverMargin = ContextVector(
        currentSpeed: 60.1,
        currentSpeedLimit: 50,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
      );
      expect(engine.assessRisk(ctxOverMargin).primaryReason, 'Speed limit exceeded by >10 km/h');
    });
  });

  group('Rule Precedence Checks', () {
    test('Rule 1 (High motion near vehicle) takes precedence over Rule 2 (Rapid approach)', () {
      final context = ContextVector(
        currentSpeed: 50.0,
        currentSpeedLimit: 60,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.05, // Very near
        isClosingIn: true,            // Closing
        isErraticDriving: true,       // AND Erratic
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.primaryReason, 'High-magnitude motion near tracked vehicle');
    });

    test('Rule 4 (Tracked vehicle closing in) takes precedence over Rule 6 (Poor visibility speed)', () {
      final context = ContextVector(
        currentSpeed: 95.0,
        currentSpeedLimit: 100,
        isRaining: true,
        isNight: false,
        visibility: 500,
        isWeatherAvailable: true,
        nearbyVehicles: 1,
        closestVehicleDistance: 0.25, // Near
        isClosingIn: true,            // Closing
        isErraticDriving: false,
      );

      final assessment = engine.assessRisk(context);
      expect(assessment.primaryReason, 'Tracked vehicle closing in');
    });
  });

  group('Explicit Visibility Representation & Safe Fallback', () {
    test('Night creates POOR visibility regardless of weather availability', () {
      final vis = ContextVector.calculateVisibility(
        isNight: true,
        isRaining: false,
        visibilityMeters: 10000,
        isWeatherAvailable: false,
      );
      expect(vis, VisibilityAssessment.poor);
    });

    test('Rain creates POOR visibility even if categorical says clear (no early-return bypass)', () {
      final vis = ContextVector.calculateVisibility(
        isNight: false,
        isRaining: true,
        visibilityMeters: 10000,
        isWeatherAvailable: true,
        visibilityCategory: 'clear', // Conflict! Physical rain must override clear category
      );
      expect(vis, VisibilityAssessment.poor);
    });

    test('Visibility < 1000m creates POOR visibility even if categorical says clear', () {
      final vis = ContextVector.calculateVisibility(
        isNight: false,
        isRaining: false,
        visibilityMeters: 600,
        isWeatherAvailable: true,
        visibilityCategory: 'clear',
      );
      expect(vis, VisibilityAssessment.poor);
    });

    test('Missing weather and no category results in UNKNOWN, NOT adequate or clear', () {
      final vis = ContextVector.calculateVisibility(
        isNight: false,
        isRaining: false,
        visibilityMeters: null,
        isWeatherAvailable: false,
        visibilityCategory: null,
      );
      expect(vis, VisibilityAssessment.unknown);
    });

    test('High speed with UNKNOWN visibility does NOT trigger poor visibility risk, flags unknown', () {
      final context = ContextVector(
        currentSpeed: 90.0,
        currentSpeedLimit: 100,
        isRaining: false,
        isNight: false,
        visibility: 10000,
        isWeatherAvailable: false, // Weather missing!
        visibilityAssessment: VisibilityAssessment.unknown,
        nearbyVehicles: 0,
        closestVehicleDistance: 1.0,
        isClosingIn: false,
      );

      final assessment = engine.assessRisk(context);
      // Should NOT trigger Rule 6 because visibility is not known to be poor
      expect(assessment.level, RiskLevel.low);
      expect(assessment.contextModifiers, contains('Visibility conditions unknown'));
      expect(assessment.dataQuality, contains('Weather unavailable - visibility unknown'));
    });
  });
}
