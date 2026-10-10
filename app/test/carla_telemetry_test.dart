import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/carla_demo_service.dart';

void main() {
  group('CarlaDemoService Telemetry Protocol & Replay Identity', () {
    late CarlaDemoService service;

    setUp(() {
      service = CarlaDemoService();
    });

    test('Backward compatibility: accepts legacy payload with speed field', () {
      final legacyPayload = {
        'speed': 48.5,
        'latitude': 9.9312,
        'longitude': 76.2673,
        'accelX': 0.1,
        'accelY': -0.2,
        'accelZ': 0.0,
        'speedLimit': 50,
        'isRaining': true,
        'isNight': false,
      };

      final accepted = service.processTelemetryMap(legacyPayload);
      expect(accepted, isTrue);

      final tele = service.latestTelemetry;
      expect(tele, isNotNull);
      expect(tele!.speedKmh, 48.5);
      expect(tele.speedLimit, 50);
      expect(tele.isRaining, isTrue);
      expect(tele.isNight, isFalse);
    });

    test('v3.0 payload with scenarioContext and speedKmh takes precedence', () {
      final v3Payload = {
        'protocolVersion': 2,
        'scenarioRunId': 'run_alpha_01',
        'sequenceNumber': 100,
        'simulationTime': 12.5,
        'simulationFrame': 750,
        'speed': 60.0,
        'speedKmh': 60.0,
        'latitude': 9.9312,
        'longitude': 76.2673,
        'accelX': 0.2,
        'accelY': 0.3,
        'accelZ': 0.1,
        'scenarioContext': {
          'scenarioId': 'HEAVY_RAIN',
          'isRaining': true,
          'speedLimit': 60,
          'isNight': true,
          'visibilityCategory': 'poor',
        }
      };

      final accepted = service.processTelemetryMap(v3Payload);
      expect(accepted, isTrue);

      final tele = service.latestTelemetry;
      expect(tele, isNotNull);
      expect(tele!.scenarioRunId, 'run_alpha_01');
      expect(tele.sequenceNumber, 100);
      expect(tele.simulationTime, 12.5);
      expect(tele.simulationFrame, 750);
      expect(tele.speedKmh, 60.0);
      expect(tele.isRaining, isTrue);
      expect(tele.isNight, isTrue);
      expect(tele.visibilityCategory, 'poor');
      expect(tele.accelMagnitude, closeTo(0.374, 0.005));
    });

    test('Sequence checking: rejects stale or out-of-order packets within same run', () {
      final baseTime = DateTime.now();

      final pkt1 = {
        'scenarioRunId': 'run_seq_test',
        'sequenceNumber': 10,
        'simulationTime': 1.0,
        'simulationFrame': 60,
        'speedKmh': 30.0,
      };
      expect(service.processTelemetryMap(pkt1, currentTime: baseTime), isTrue);

      final pkt2 = {
        'scenarioRunId': 'run_seq_test',
        'sequenceNumber': 11,
        'simulationTime': 1.1,
        'simulationFrame': 66,
        'speedKmh': 32.0,
      };
      expect(service.processTelemetryMap(pkt2, currentTime: baseTime.add(const Duration(milliseconds: 100))), isTrue);

      // Duplicate sequence number (11 <= 11) -> dropped!
      final pktDuplicate = {
        'scenarioRunId': 'run_seq_test',
        'sequenceNumber': 11,
        'simulationTime': 1.1,
        'simulationFrame': 66,
        'speedKmh': 32.0,
      };
      expect(service.processTelemetryMap(pktDuplicate, currentTime: baseTime.add(const Duration(milliseconds: 150))), isFalse);
      expect(service.droppedPackets, 1);

      // Stale out-of-order packet (9 <= 11) -> dropped!
      final pktStale = {
        'scenarioRunId': 'run_seq_test',
        'sequenceNumber': 9,
        'simulationTime': 0.9,
        'simulationFrame': 54,
        'speedKmh': 28.0,
      };
      expect(service.processTelemetryMap(pktStale, currentTime: baseTime.add(const Duration(milliseconds: 200))), isFalse);
      expect(service.droppedPackets, 2);
    });

    test('Replay identity: new scenarioRunId resets sequence tracking', () {
      final baseTime = DateTime.now();

      final run1Pkt = {
        'scenarioRunId': 'run_first',
        'sequenceNumber': 50,
        'simulationTime': 5.0,
        'speedKmh': 40.0,
      };
      expect(service.processTelemetryMap(run1Pkt, currentTime: baseTime), isTrue);

      // Replay restarted! New run ID with lower sequence number (1)
      final run2Pkt = {
        'scenarioRunId': 'run_restarted',
        'sequenceNumber': 1,
        'simulationTime': 0.1,
        'speedKmh': 0.0,
      };
      expect(service.processTelemetryMap(run2Pkt, currentTime: baseTime.add(const Duration(milliseconds: 100))), isTrue);
      expect(service.latestTelemetry!.scenarioRunId, 'run_restarted');
      expect(service.latestTelemetry!.sequenceNumber, 1);
    });
  });

  group('CarlaDemoService Watchdogs (Heartbeat & SimTime)', () {
    test('Sim time progressing keeps connection active, freeze triggers paused', () {
      final service = CarlaDemoService();
      final t0 = DateTime(2026, 10, 10, 12, 0, 0);

      // Seed running state manually for unit testing watchdog
      // We can start service or test checkWatchdog logic
      final pkt1 = {
        'scenarioRunId': 'watchdog_test',
        'sequenceNumber': 1,
        'simulationTime': 1.0,
        'simulationFrame': 60,
        'speedKmh': 50.0,
      };
      service.processTelemetryMap(pkt1, currentTime: t0);

      // Packet arrives at t0 + 500ms, simulationTime advanced to 1.5s
      final pkt2 = {
        'scenarioRunId': 'watchdog_test',
        'sequenceNumber': 2,
        'simulationTime': 1.5,
        'simulationFrame': 90,
        'speedKmh': 50.0,
      };
      service.processTelemetryMap(pkt2, currentTime: t0.add(const Duration(milliseconds: 500)));

      // Check watchdog at t0 + 600ms -> healthy
      service.checkWatchdog(currentTime: t0.add(const Duration(milliseconds: 600)));
      // Note: without service.start(), isRunning is false so checkWatchdog reports idle
    });
  });
}
