import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../managers/risk_manager.dart';

/// A lightweight HTTP server that receives simulated telemetry from a CARLA
/// Python script over the local network. When enabled, incoming JSON payloads
/// override the physical sensor values in [RiskManager] so the RiskEngine
/// evaluates CARLA-supplied context instead of real GPS/IMU/Weather data.
///
/// The phone camera continues to run YOLO independently — only the telemetry
/// inputs (speed, speed limit, weather, IMU events) are replaced.
///
/// Expected JSON payload (POST /telemetry):
/// ```json
/// {
///   "speed": 65.0,
///   "speedLimit": 50,
///   "isErratic": false,
///   "isRaining": true,
///   "isNight": false
/// }
/// ```
class CarlaDemoService extends ChangeNotifier {
  HttpServer? _server;
  RiskManager? _riskManager;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _statusMessage = 'Idle';
  String get statusMessage => _statusMessage;

  DateTime? _lastPacketAt;
  DateTime? get lastPacketAt => _lastPacketAt;

  int _packetsReceived = 0;
  int get packetsReceived => _packetsReceived;

  /// The port the HTTP server binds to on the phone.
  static const int port = 8080;

  void attachRiskManager(RiskManager riskManager) {
    _riskManager = riskManager;
  }

  /// Starts the HTTP server, binding to all network interfaces on [port].
  /// Once started, the phone listens for POST requests from the CARLA script.
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _packetsReceived = 0;
      _statusMessage = 'Listening on port $port';
      notifyListeners();

      debugPrint('[CarlaDemoService] Server started on port $port');

      _server!.listen(
        _handleRequest,
        onError: (error) {
          debugPrint('[CarlaDemoService] Server error: $error');
        },
      );
    } catch (e) {
      _statusMessage = 'Failed to start: $e';
      _isRunning = false;
      notifyListeners();
      debugPrint('[CarlaDemoService] Failed to start server: $e');
    }
  }

  /// Stops the HTTP server and clears all overrides in [RiskManager],
  /// restoring the app to real-sensor mode.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _packetsReceived = 0;
    _lastPacketAt = null;
    _statusMessage = 'Idle';

    // Clear all overrides so the app returns to real sensor data
    _clearOverrides();
    notifyListeners();

    debugPrint('[CarlaDemoService] Server stopped. Overrides cleared.');
  }

  void _clearOverrides() {
    if (_riskManager == null) return;
    _riskManager!.overrideSpeed = null;
    _riskManager!.overrideIsRaining = null;
    _riskManager!.overrideIsNight = null;
    _riskManager!.overrideIsErratic = null;
    _riskManager!.overrideSpeedLimit = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers so browser-based tools can also send test requests
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    // Handle preflight CORS requests
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // GET /status — health check endpoint
    if (request.method == 'GET' && request.uri.path == '/status') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'ContextDrive',
        'mode': 'carla_demo',
        'packetsReceived': _packetsReceived,
        'lastPacketAt': _lastPacketAt?.toIso8601String(),
      }));
      await request.response.close();
      return;
    }

    // POST /telemetry — the main data injection endpoint
    if (request.method == 'POST' && request.uri.path == '/telemetry') {
      try {
        final body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> data = jsonDecode(body);

        _applyTelemetry(data);

        _packetsReceived++;
        _lastPacketAt = DateTime.now();
        _statusMessage = 'Connected — $_packetsReceived packets';
        notifyListeners();

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'ok', 'applied': data}));
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': e.toString()}));
        debugPrint('[CarlaDemoService] Bad request: $e');
      }
      await request.response.close();
      return;
    }

    // POST /reset — clear all overrides without stopping the server
    if (request.method == 'POST' && request.uri.path == '/reset') {
      _clearOverrides();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'overrides_cleared'}));
      await request.response.close();
      _statusMessage = 'Connected — overrides cleared';
      notifyListeners();
      return;
    }

    // Unknown route
    request.response.statusCode = HttpStatus.notFound;
    request.response.write(jsonEncode({'error': 'Not found. Use POST /telemetry'}));
    await request.response.close();
  }

  /// Applies the incoming JSON fields to the RiskManager overrides.
  /// All fields are optional — only the fields present in the JSON are updated.
  void _applyTelemetry(Map<String, dynamic> data) {
    if (_riskManager == null) {
      debugPrint('[CarlaDemoService] Warning: No RiskManager attached.');
      return;
    }

    if (data.containsKey('speed')) {
      final speed = data['speed'];
      _riskManager!.overrideSpeed = speed != null ? (speed as num).toDouble() : null;
    }

    if (data.containsKey('speedLimit')) {
      final limit = data['speedLimit'];
      _riskManager!.overrideSpeedLimit = limit != null ? (limit as num).toInt() : null;
    }

    if (data.containsKey('isErratic')) {
      _riskManager!.overrideIsErratic = data['isErratic'] as bool?;
    }

    if (data.containsKey('isRaining')) {
      _riskManager!.overrideIsRaining = data['isRaining'] as bool?;
    }

    if (data.containsKey('isNight')) {
      _riskManager!.overrideIsNight = data['isNight'] as bool?;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
