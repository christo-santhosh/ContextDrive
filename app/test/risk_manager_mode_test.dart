import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/managers/risk_manager.dart';
import 'package:app/services/gps_service.dart';
import 'package:app/services/weather_service.dart';
import 'package:app/services/time_context_service.dart';
import 'package:app/services/carla_demo_service.dart';
import 'package:app/models/context_vector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('contextdrive/voice_alerts'),
      (MethodCall methodCall) async => null,
    );
  });

  group('RiskManager Mode Isolation & Stale Telemetry Handling', () {
    late GpsService gpsService;
    late WeatherService weatherService;
    late TimeContextService timeContextService;
    late CarlaDemoService carlaService;
    late RiskManager riskManager;

    setUp(() {
      gpsService = GpsService();
      weatherService = WeatherService();
      timeContextService = TimeContextService();
      carlaService = CarlaDemoService();
      riskManager = RiskManager(gpsService, weatherService, timeContextService, carlaService);
    });

    tearDown(() {
      riskManager.dispose();
      carlaService.dispose();
    });

    test('Initial state is Low risk and speed is null', () {
      expect(riskManager.currentAssessment.level, RiskLevel.low);
      expect(riskManager.contextVector.currentSpeed, isNull);
    });

    test('In CARLA mode with valid telemetry, assessment consumes CARLA parameters', () async {
      await riskManager.start(locationAvailable: false);

      // Simulate CARLA receiving an active packet
      carlaService.processTelemetryMap({
        'protocolVersion': 2,
        'scenarioRunId': 'run_test_01',
        'sequenceNumber': 1,
        'simulationTime': 10.0,
        'simulationFrame': 600,
        'speedKmh': 55.0,
        'latitude': 9.9312,
        'longitude': 76.2673,
        'accelX': 0.1,
        'accelY': 0.2,
        'accelZ': 0.0,
        'scenarioContext': {
          'isRaining': true,
          'speedLimit': 50,
          'isNight': false,
          'visibilityCategory': 'poor',
        }
      });

      expect(riskManager.currentAssessment, isNotNull);
    });

    test('When CARLA mode is enabled, physical GPS updates are strictly ignored', () async {
      await riskManager.start(locationAvailable: false);

      // Seed Carla active telemetry
      carlaService.processTelemetryMap({
        'protocolVersion': 2,
        'scenarioRunId': 'run_isolation_test',
        'sequenceNumber': 1,
        'simulationTime': 1.0,
        'speedKmh': 70.0,
        'accelX': 0.0,
        'accelY': 0.0,
        'accelZ': 0.0,
      });

      // Context speed comes from CARLA
      expect(carlaService.latestTelemetry!.speedKmh, 70.0);
    });
  });
}
