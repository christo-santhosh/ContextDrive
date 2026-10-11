import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/carla_camera_stream_service.dart';

Uint8List createFramePacket({
  String runId = 'test-run-1',
  int seq = 1,
  double simTime = 1.0,
  int simFrame = 10,
  int width = 640,
  int height = 480,
  String format = 'jpeg',
  List<int> imagePayload = const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10], // Sample JPEG header
}) {
  final metaJson = jsonEncode({
    'protocolVersion': 1,
    'scenarioRunId': runId,
    'sequenceNumber': seq,
    'simulationTime': simTime,
    'simulationFrame': simFrame,
    'width': width,
    'height': height,
    'format': format,
  });
  final metaBytes = utf8.encode(metaJson);

  final builder = BytesBuilder();
  // Magic "CDVF"
  builder.add([0x43, 0x44, 0x56, 0x46]);
  // Version 1 (uint16)
  final verData = ByteData(2)..setUint16(0, 1, Endian.big);
  builder.add(verData.buffer.asUint8List());
  // Meta length (uint32)
  final metaLenData = ByteData(4)..setUint32(0, metaBytes.length, Endian.big);
  builder.add(metaLenData.buffer.asUint8List());
  // Image length (uint32)
  final imgLenData = ByteData(4)..setUint32(0, imagePayload.length, Endian.big);
  builder.add(imgLenData.buffer.asUint8List());
  // Metadata
  builder.add(metaBytes);
  // Image payload
  builder.add(imagePayload);

  return builder.toBytes();
}

void main() {
  group('CarlaCameraStreamService Protocol Tests', () {
    late CarlaCameraStreamService service;

    setUp(() {
      service = CarlaCameraStreamService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Parses a complete valid frame packet', () {
      final packet = createFramePacket(
        runId: 'session_101',
        seq: 1,
        simTime: 12.5,
        simFrame: 300,
        width: 640,
        height: 480,
      );

      service.parseBytes(packet);

      expect(service.framesReceived, 1);
      expect(service.latestFrame, isNotNull);
      expect(service.latestFrame!.scenarioRunId, 'session_101');
      expect(service.latestFrame!.sequenceNumber, 1);
      expect(service.latestFrame!.simulationTime, 12.5);
      expect(service.latestFrame!.simulationFrame, 300);
      expect(service.latestFrame!.width, 640);
      expect(service.latestFrame!.height, 480);
      expect(service.latestFrame!.format, 'jpeg');
      expect(service.latestFrame!.imageBytes.length, 6);
      expect(service.framesDropped, 0);
    });

    test('Handles fragmented packets across multiple TCP reads', () {
      final packet = createFramePacket(seq: 2);
      expect(packet.length, greaterThan(20));

      // Split into 3 small chunks
      final chunk1 = packet.sublist(0, 8);
      final chunk2 = packet.sublist(8, 20);
      final chunk3 = packet.sublist(20);

      service.parseBytes(chunk1);
      expect(service.framesReceived, 0); // Not complete yet

      service.parseBytes(chunk2);
      expect(service.framesReceived, 0); // Still not complete

      service.parseBytes(chunk3);
      expect(service.framesReceived, 1); // Completed and parsed!
      expect(service.latestFrame!.sequenceNumber, 2);
    });

    test('Rejects duplicate or out-of-order sequence numbers within same run', () {
      final packet1 = createFramePacket(runId: 'runA', seq: 5);
      final packetOld = createFramePacket(runId: 'runA', seq: 4);
      final packetDup = createFramePacket(runId: 'runA', seq: 5);
      final packetNew = createFramePacket(runId: 'runA', seq: 6);

      service.parseBytes(packet1);
      expect(service.framesReceived, 1);

      service.parseBytes(packetOld);
      expect(service.framesReceived, 1);
      expect(service.framesDropped, 1);

      service.parseBytes(packetDup);
      expect(service.framesReceived, 1);
      expect(service.framesDropped, 2);

      service.parseBytes(packetNew);
      expect(service.framesReceived, 2);
      expect(service.latestFrame!.sequenceNumber, 6);
    });

    test('Accepts lower sequence number if scenarioRunId resets', () {
      final run1Frame = createFramePacket(runId: 'run_alpha', seq: 100);
      final run2Frame = createFramePacket(runId: 'run_beta', seq: 1);

      service.parseBytes(run1Frame);
      expect(service.framesReceived, 1);
      expect(service.latestFrame!.scenarioRunId, 'run_alpha');
      expect(service.latestFrame!.sequenceNumber, 100);

      service.parseBytes(run2Frame);
      expect(service.framesReceived, 2);
      expect(service.latestFrame!.scenarioRunId, 'run_beta');
      expect(service.latestFrame!.sequenceNumber, 1);
    });

    test('Resynchronizes after junk or corrupted leading bytes', () {
      final junk = Uint8List.fromList([0x00, 0x12, 0x45, 0x99, 0xFF]);
      final valid = createFramePacket(seq: 1);

      final combined = Uint8List.fromList([...junk, ...valid]);
      service.parseBytes(combined);

      expect(service.framesReceived, 1);
      expect(service.latestFrame!.sequenceNumber, 1);
    });

    test('Watchdog marks stream as stale after 1s inactivity', () {
      final baseTime = DateTime(2026, 10, 11, 10, 0, 0);
      final packet = createFramePacket(seq: 1);

      service.parseBytes(packet, currentTime: baseTime);
      expect(service.status, CarlaStreamStatus.connected);

      // Check watchdog after 500ms -> still connected
      service.checkWatchdog(currentTime: baseTime.add(const Duration(milliseconds: 500)));
      expect(service.status, CarlaStreamStatus.connected);

      // Check watchdog after 1500ms -> stale
      service.checkWatchdog(currentTime: baseTime.add(const Duration(milliseconds: 1500)));
      expect(service.status, CarlaStreamStatus.stale);
    });
  });
}
