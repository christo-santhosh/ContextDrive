import 'package:app/engine/risk_engine.dart';
import 'package:app/models/context_vector.dart';
import 'package:flutter_test/flutter_test.dart';

ContextVector context({
  double? speed = 50,
  int? limit = 60,
  WeatherCategory weather = WeatherCategory.clear,
  DaylightCondition daylight = DaylightCondition.day,
  int? visibility = 10000,
  bool weatherAvailable = true,
  int vehicles = 0,
  double closest = 1,
  bool closing = false,
  MotionClassification motion = MotionClassification.normal,
  double? longitudinalAcceleration,
  bool fresh = true,
}) => ContextVector(
  currentSpeed: speed,
  currentSpeedLimit: limit,
  weatherCategory: weather,
  daylightCondition: daylight,
  visibilityMeters: visibility,
  isWeatherAvailable: weatherAvailable,
  nearbyVehicles: vehicles,
  closestVehicleDistance: closest,
  isClosingIn: closing,
  motion: motion,
  longitudinalAcceleration: longitudinalAcceleration,
  telemetryFresh: fresh,
);

void main() {
  final engine = RiskEngine();

  group('motion classifier', () {
    test('classifies signed CARLA longitudinal acceleration', () {
      expect(MotionClassifier.classify(speedKmh: 50, longitudinalAcceleration: -3.5), MotionClassification.hardBraking);
      expect(MotionClassifier.classify(speedKmh: 50, longitudinalAcceleration: 3.0), MotionClassification.rapidAcceleration);
      expect(MotionClassifier.classify(speedKmh: 50, longitudinalAcceleration: 0.5), MotionClassification.normal);
      expect(MotionClassifier.classify(speedKmh: 4.9, longitudinalAcceleration: -5), MotionClassification.unknown);
    });
  });

  group('hazards and severity', () {
    test('hard braking and rapid acceleration are distinct', () {
      final braking = engine.assessRisk(context(motion: MotionClassification.hardBraking, longitudinalAcceleration: -4));
      final accelerating = engine.assessRisk(context(motion: MotionClassification.rapidAcceleration, longitudinalAcceleration: 4));
      expect(braking.level, RiskLevel.moderate);
      expect(braking.primaryReason, 'Hard braking');
      expect(braking.whatHappened, contains('Strong deceleration'));
      expect(accelerating.level, RiskLevel.moderate);
      expect(accelerating.primaryReason, 'Rapid acceleration');
      expect(accelerating.recommendation, contains('smoother throttle'));
    });

    test('very close closing traffic is high and retains rain advisory', () {
      final assessment = engine.assessRisk(context(
        weather: WeatherCategory.rain, vehicles: 1, closest: 0.1, closing: true,
      ));
      expect(assessment.level, RiskLevel.high);
      expect(assessment.primaryReason, 'Rapid optical approach at close range');
      expect(assessment.advisories.single, contains('Rain is reported'));
    });

    test('critical requires close, closing, braking and adverse context', () {
      final assessment = engine.assessRisk(context(
        weather: WeatherCategory.heavyRain,
        vehicles: 1,
        closest: 0.1,
        closing: true,
        motion: MotionClassification.hardBraking,
        longitudinalAcceleration: -4,
      ));
      expect(assessment.level, RiskLevel.critical);
      expect(assessment.activeEvents, contains('Hard braking near tracked traffic'));
    });

    test('significant speeding in adverse context is high', () {
      final assessment = engine.assessRisk(context(speed: 91, limit: 60, weather: WeatherCategory.rain));
      expect(assessment.level, RiskLevel.high);
      expect(assessment.primaryReason, 'Significant speeding in adverse conditions');
      expect(assessment.recommendation, contains('60 km/h'));
    });

    test('speed threshold equality does not trigger speeding', () {
      expect(engine.assessRisk(context(speed: 70, limit: 60)).level, RiskLevel.low);
      expect(engine.assessRisk(context(speed: 70.1, limit: 60)).primaryReason, 'Speed limit exceeded');
    });
  });

  group('quality and advisories', () {
    test('weather and night are advisories, not collision events', () {
      final assessment = engine.assessRisk(context(weather: WeatherCategory.rain, daylight: DaylightCondition.night));
      expect(assessment.level, RiskLevel.low);
      expect(assessment.advisories.length, 2);
      expect(assessment.dataQualityStatus, AssessmentDataQuality.good);
    });

    test('missing weather remains limited and does not imply clear conditions', () {
      final assessment = engine.assessRisk(context(weather: WeatherCategory.unknown, weatherAvailable: false, visibility: null));
      expect(assessment.level, RiskLevel.low);
      expect(assessment.dataQualityStatus, AssessmentDataQuality.limited);
      expect(assessment.contextModifiers, contains('Visibility conditions unknown'));
    });

    test('a known hazard remains high despite missing speed', () {
      final assessment = engine.assessRisk(context(speed: null, vehicles: 1, closest: 0.1, closing: true));
      expect(assessment.level, RiskLevel.high);
      expect(assessment.dataQualityStatus, AssessmentDataQuality.limited);
    });

    test('stale telemetry is separate from severity', () {
      final assessment = engine.assessRisk(context(fresh: false, motion: MotionClassification.hardBraking, longitudinalAcceleration: -4));
      expect(assessment.level, RiskLevel.moderate);
      expect(assessment.dataQualityStatus, AssessmentDataQuality.stale);
    });
  });
}
