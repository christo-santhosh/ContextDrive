import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

enum CarlaConnectionStatus {
  idle,         // Server not started
  listening,    // Server running, waiting for initial packet
  active,       // Telemetry streaming and simulation time progressing
  paused,       // Telemetry packets arriving but simulation clock/frame is frozen (>1s)
  disconnected, // Telemetry packet stream timed out (>1s)
}

class CarlaTelemetry {
  final int protocolVersion;
  final String? scenarioRunId;
  final int? sequenceNumber;
  final double? simulationTime;
  final int? simulationFrame;
  final double speedKmh;
  final double latitude;
  final double longitude;
  final double accelX;
  final double accelY;
  final double accelZ;
  /// Direction-of-travel projected acceleration in m/s². It is optional for
  /// legacy senders, and positive means acceleration in travel direction.
  final double? longitudinalAcceleration;
  final int? speedLimit;
  final bool? isRaining;
  final bool? isNight;
  final String? visibilityCategory;
  final bool? isErratic;
  final DateTime receivedAt;

  CarlaTelemetry({
    this.protocolVersion = 1,
    this.scenarioRunId,
    this.sequenceNumber,
    this.simulationTime,
    this.simulationFrame,
    required this.speedKmh,
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    this.longitudinalAcceleration,
    this.speedLimit,
    this.isRaining,
    this.isNight,
    this.visibilityCategory,
    this.isErratic,
    required this.receivedAt,
  });

  /// Invariant Euclidean magnitude of the actor acceleration vector
  double get accelMagnitude =>
      sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);

  bool get isStale =>
      DateTime.now().difference(receivedAt).inMilliseconds > 1000;
}

/// A lightweight HTTP server that receives telemetry from CARLA or the demo controller.
/// Flexible: Supports both raw physical measurements (speed, coords, IMU) and high-level scenario overrides.
class CarlaDemoService extends ChangeNotifier {
  HttpServer? _server;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  CarlaConnectionStatus _connectionStatus = CarlaConnectionStatus.idle;
  CarlaConnectionStatus get connectionStatus => _connectionStatus;

  bool get isCarlaActive => _connectionStatus == CarlaConnectionStatus.active;

  String _statusMessage = 'Idle';
  String get statusMessage => _statusMessage;

  String _localIp = '127.0.0.1';
  String get localIp => _localIp;

  int _packetsReceived = 0;
  int get packetsReceived => _packetsReceived;

  int _droppedPackets = 0;
  int get droppedPackets => _droppedPackets;

  CarlaTelemetry? _latestTelemetry;
  CarlaTelemetry? get latestTelemetry => _latestTelemetry;

  DateTime? _lastPacketReceivedAt;
  DateTime? _lastSimProgressAt;
  double? _lastSimulationTime;
  int? _lastSimulationFrame;
  String? _currentRunId;
  int? _lastSequenceNumber;

  Timer? _watchdogTimer;

  static const int port = 8080;

  Future<void> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            _localIp = addr.address;
            return;
          }
        }
      }
      _localIp = '127.0.0.1';
    } catch (_) {
      _localIp = '127.0.0.1';
    }
  }

  Future<void> start() async {
    if (_isRunning) return;
    try {
      await _detectLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _packetsReceived = 0;
      _droppedPackets = 0;
      _lastPacketReceivedAt = null;
      _lastSimProgressAt = null;
      _lastSimulationTime = null;
      _lastSimulationFrame = null;
      _currentRunId = null;
      _lastSequenceNumber = null;
      _connectionStatus = CarlaConnectionStatus.listening;
      _statusMessage = 'Listening on $_localIp:$port';
      notifyListeners();

      _watchdogTimer?.cancel();
      _watchdogTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => checkWatchdog(),
      );

      _server!.listen(_handleRequest, onError: (e) => debugPrint('Server error: $e'));
    } catch (e) {
      _statusMessage = 'Failed to start: $e';
      _isRunning = false;
      _connectionStatus = CarlaConnectionStatus.idle;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _packetsReceived = 0;
    _droppedPackets = 0;
    _latestTelemetry = null;
    _lastPacketReceivedAt = null;
    _lastSimProgressAt = null;
    _lastSimulationTime = null;
    _lastSimulationFrame = null;
    _currentRunId = null;
    _lastSequenceNumber = null;
    _connectionStatus = CarlaConnectionStatus.idle;
    _statusMessage = 'Idle';
    notifyListeners();
  }

  /// Evaluates connection status based on network heartbeat and simulation time progression.
  void checkWatchdog({DateTime? currentTime}) {
    if (!_isRunning) {
      if (_connectionStatus != CarlaConnectionStatus.idle) {
        _connectionStatus = CarlaConnectionStatus.idle;
        notifyListeners();
      }
      return;
    }

    final prevStatus = _connectionStatus;
    final now = currentTime ?? DateTime.now();

    if (_lastPacketReceivedAt == null) {
      _connectionStatus = CarlaConnectionStatus.listening;
      _statusMessage = 'Listening on $_localIp:$port';
    } else {
      final packetAgeMs = now.difference(_lastPacketReceivedAt!).inMilliseconds;
      if (packetAgeMs > 1000) {
        _connectionStatus = CarlaConnectionStatus.disconnected;
        _statusMessage = 'CARLA Disconnected (>1s timeout)';
      } else if (_lastSimProgressAt != null &&
          now.difference(_lastSimProgressAt!).inMilliseconds > 1000) {
        _connectionStatus = CarlaConnectionStatus.paused;
        _statusMessage = 'CARLA Paused (clock stopped)';
      } else {
        _connectionStatus = CarlaConnectionStatus.active;
        _statusMessage =
            'Connected — $_packetsReceived packets';
      }
    }

    if (prevStatus != _connectionStatus) {
      notifyListeners();
    }
  }

  /// Processes telemetry payload map directly. Returns true if accepted, false if dropped.
  bool processTelemetryMap(Map<String, dynamic> data, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();

    final runId = data['scenarioRunId'] as String?;
    final seq = (data['sequenceNumber'] as num?)?.toInt();
    final simTime = (data['simulationTime'] as num?)?.toDouble();
    final simFrame = (data['simulationFrame'] as num?)?.toInt();

    // Session identity and sequence checking
    if (runId != null && runId != _currentRunId) {
      // New scenario run or replay reset detected
      _currentRunId = runId;
      _lastSequenceNumber = seq;
      _lastSimulationTime = simTime;
      _lastSimulationFrame = simFrame;
      _lastSimProgressAt = now;
    } else if (seq != null && _lastSequenceNumber != null && seq <= _lastSequenceNumber!) {
      // Reject stale or duplicate out-of-order packets
      _droppedPackets++;
      return false;
    } else {
      if (seq != null) _lastSequenceNumber = seq;
    }

    // Check simulation progression
    bool progressed = false;
    if (simTime != null && _lastSimulationTime != null && simTime > _lastSimulationTime!) {
      progressed = true;
    } else if (simFrame != null && _lastSimulationFrame != null && simFrame > _lastSimulationFrame!) {
      progressed = true;
    } else if (_lastSimulationTime == null && _lastSimulationFrame == null) {
      // Legacy packet without simulation clock advances with packet delivery
      progressed = true;
    }

    if (progressed) {
      _lastSimulationTime = simTime ?? _lastSimulationTime;
      _lastSimulationFrame = simFrame ?? _lastSimulationFrame;
      _lastSimProgressAt = now;
    }

    _lastPacketReceivedAt = now;

    // Backward compatibility: support speedKmh ?? speed
    final speed = (data['speedKmh'] as num?)?.toDouble() ??
        (data['speed'] as num?)?.toDouble() ??
        0.0;
    final lat = (data['latitude'] as num?)?.toDouble() ?? 9.9312;
    final lon = (data['longitude'] as num?)?.toDouble() ?? 76.2673;
    final ax = (data['accelX'] as num?)?.toDouble() ?? 0.0;
    final ay = (data['accelY'] as num?)?.toDouble() ?? 0.0;
    final az = (data['accelZ'] as num?)?.toDouble() ?? 0.0;
    final longitudinalAcceleration =
        (data['longitudinalAccelMps2'] as num?)?.toDouble();

    final scenarioContext = data['scenarioContext'] as Map<String, dynamic>?;

    final speedLimit = (scenarioContext?['speedLimit'] as num?)?.toInt() ??
        (data['speedLimit'] as num?)?.toInt();
    final isRaining = (scenarioContext?['isRaining'] as bool?) ??
        (data['isRaining'] as bool?);
    final isNight = (scenarioContext?['isNight'] as bool?) ??
        (data['isNight'] as bool?);
    final visibilityCat = (scenarioContext?['visibilityCategory'] as String?) ??
        (data['visibilityCategory'] as String?);
    final isErratic = (scenarioContext?['isErratic'] as bool?) ??
        (data['isErratic'] as bool?);
    final protocolVersion = (data['protocolVersion'] as num?)?.toInt() ?? 1;

    _latestTelemetry = CarlaTelemetry(
      protocolVersion: protocolVersion,
      scenarioRunId: runId,
      sequenceNumber: seq,
      simulationTime: simTime,
      simulationFrame: simFrame,
      speedKmh: speed,
      latitude: lat,
      longitude: lon,
      accelX: ax,
      accelY: ay,
      accelZ: az,
      longitudinalAcceleration: longitudinalAcceleration,
      speedLimit: speedLimit,
      isRaining: isRaining,
      isNight: isNight,
      visibilityCategory: visibilityCat,
      isErratic: isErratic,
      receivedAt: now,
    );

    _packetsReceived++;
    checkWatchdog(currentTime: now);
    return true;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');

    if (request.method == 'POST' && request.uri.path == '/telemetry') {
      try {
        final body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> data = jsonDecode(body);

        final accepted = processTelemetryMap(data);

        request.response.statusCode = HttpStatus.ok;
        if (accepted) {
          request.response.write('{"status":"ok"}');
        } else {
          request.response.write('{"status":"dropped_out_of_order"}');
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"error":"invalid format: $e"}');
      }
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _server?.close(force: true);
    _server = null;
    super.dispose();
  }
}
