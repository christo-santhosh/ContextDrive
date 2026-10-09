import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class CarlaTelemetry {
  final double speedKmh;
  final double latitude;
  final double longitude;
  final double accelX;
  final double accelY;
  final double accelZ;
  final DateTime receivedAt;

  CarlaTelemetry({
    required this.speedKmh,
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.receivedAt,
  });
  
  bool get isStale => DateTime.now().difference(receivedAt).inSeconds > 2;
}

/// A lightweight HTTP server that receives RAW sensor telemetry from a CARLA
/// simulation. It strictly provides measurements (speed, location, acceleration) 
/// and NEVER provides decision flags like isErratic or isRaining. The existing 
/// ContextDrive pipeline uses these measurements to query external APIs and 
/// calculate risk natively.
class CarlaDemoService extends ChangeNotifier {
  HttpServer? _server;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _statusMessage = 'Idle';
  String get statusMessage => _statusMessage;

  int _packetsReceived = 0;
  int get packetsReceived => _packetsReceived;

  CarlaTelemetry? _latestTelemetry;
  CarlaTelemetry? get latestTelemetry => _latestTelemetry;

  static const int port = 8080;

  Future<void> start() async {
    if (_isRunning) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _packetsReceived = 0;
      _statusMessage = 'Listening on port $port';
      notifyListeners();

      _server!.listen(_handleRequest, onError: (e) => debugPrint('Server error: $e'));
    } catch (e) {
      _statusMessage = 'Failed to start: $e';
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _packetsReceived = 0;
    _latestTelemetry = null;
    _statusMessage = 'Idle';
    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    
    if (request.method == 'POST' && request.uri.path == '/telemetry') {
      try {
        final body = await utf8.decoder.bind(request).join();
        final Map<String, dynamic> data = jsonDecode(body);

        _latestTelemetry = CarlaTelemetry(
          speedKmh: (data['speed'] as num).toDouble(),
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
          accelX: (data['accelX'] as num).toDouble(),
          accelY: (data['accelY'] as num).toDouble(),
          accelZ: (data['accelZ'] as num).toDouble(),
          receivedAt: DateTime.now(),
        );

        _packetsReceived++;
        _statusMessage = 'Connected — $_packetsReceived packets';
        notifyListeners();

        request.response.statusCode = HttpStatus.ok;
        request.response.write('{"status":"ok"}');
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"error":"invalid format"}');
      }
      await request.response.close();
      return;
    }
    
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
