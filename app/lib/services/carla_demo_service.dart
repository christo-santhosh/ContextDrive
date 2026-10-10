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
  final int? speedLimit;
  final bool? isRaining;
  final bool? isNight;
  final bool? isErratic;
  final DateTime receivedAt;

  CarlaTelemetry({
    required this.speedKmh,
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    this.speedLimit,
    this.isRaining,
    this.isNight,
    this.isErratic,
    required this.receivedAt,
  });
  
  bool get isStale => DateTime.now().difference(receivedAt).inSeconds > 3;
}

/// A lightweight HTTP server that receives telemetry from CARLA or the demo controller.
/// Flexible: Supports both raw physical measurements (speed, coords, IMU) and high-level scenario overrides.
class CarlaDemoService extends ChangeNotifier {
  HttpServer? _server;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _statusMessage = 'Idle';
  String get statusMessage => _statusMessage;

  String _localIp = '127.0.0.1';
  String get localIp => _localIp;

  int _packetsReceived = 0;
  int get packetsReceived => _packetsReceived;

  CarlaTelemetry? _latestTelemetry;
  CarlaTelemetry? get latestTelemetry => _latestTelemetry;

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
      _statusMessage = 'Listening on $_localIp:$port';
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

        final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
        final lat = (data['latitude'] as num?)?.toDouble() ?? 9.9312;
        final lon = (data['longitude'] as num?)?.toDouble() ?? 76.2673;
        final ax = (data['accelX'] as num?)?.toDouble() ?? 0.0;
        final ay = (data['accelY'] as num?)?.toDouble() ?? 0.0;
        final az = (data['accelZ'] as num?)?.toDouble() ?? 0.0;

        final speedLimit = (data['speedLimit'] as num?)?.toInt();
        final isRaining = data['isRaining'] as bool?;
        final isNight = data['isNight'] as bool?;
        final isErratic = data['isErratic'] as bool?;

        _latestTelemetry = CarlaTelemetry(
          speedKmh: speed,
          latitude: lat,
          longitude: lon,
          accelX: ax,
          accelY: ay,
          accelZ: az,
          speedLimit: speedLimit,
          isRaining: isRaining,
          isNight: isNight,
          isErratic: isErratic,
          receivedAt: DateTime.now(),
        );

        _packetsReceived++;
        _statusMessage = 'Connected — $_packetsReceived packets';
        notifyListeners();

        request.response.statusCode = HttpStatus.ok;
        request.response.write('{"status":"ok"}');
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
    stop();
    super.dispose();
  }
}
