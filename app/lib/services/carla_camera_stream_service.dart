import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum CarlaStreamStatus {
  idle,         // Server not started
  listening,    // Server running, waiting for Python sender to connect
  connected,    // Connected and receiving frames
  stale,        // Connected but no frame received for > 1s
  disconnected, // Socket closed or lost connection
}

class CarlaVideoFrame {
  final int protocolVersion;
  final String scenarioRunId;
  final int sequenceNumber;
  final double simulationTime;
  final int simulationFrame;
  final int width;
  final int height;
  final String format;
  final Uint8List imageBytes;
  final DateTime receivedAt;

  CarlaVideoFrame({
    required this.protocolVersion,
    required this.scenarioRunId,
    required this.sequenceNumber,
    required this.simulationTime,
    required this.simulationFrame,
    required this.width,
    required this.height,
    required this.format,
    required this.imageBytes,
    required this.receivedAt,
  });

  bool get isStale =>
      DateTime.now().difference(receivedAt).inMilliseconds > 1000;
}

/// Lightweight TCP receiver for CARLA virtual camera frames streamed over USB (ADB reverse).
///
/// Framing specification:
/// [0..3]   Magic bytes: 'C', 'D', 'V', 'F' (0x43, 0x44, 0x56, 0x46)
/// [4..5]   Protocol Version: uint16 big-endian (1)
/// [6..9]   Meta Length: uint32 big-endian
/// [10..13] Image Length: uint32 big-endian
/// [14..14+MetaLength-1] UTF-8 JSON Metadata
/// [14+MetaLength..14+MetaLength+ImageLength-1] Binary Image Payload (e.g. JPEG)
class CarlaCameraStreamService extends ChangeNotifier {
  static const int defaultPort = 8088;
  static const List<int> magicBytes = [0x43, 0x44, 0x56, 0x46]; // "CDVF"
  static const int headerSize = 14;
  static const int maxMetaSize = 65536; // 64 KB
  static const int maxImageSize = 5242880; // 5 MB

  ServerSocket? _server;
  Socket? _activeClient;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  CarlaStreamStatus _status = CarlaStreamStatus.idle;
  CarlaStreamStatus get status => _status;

  String _statusMessage = 'Idle';
  String get statusMessage => _statusMessage;

  int _port = defaultPort;
  int get port => _port;

  CarlaVideoFrame? _latestFrame;
  CarlaVideoFrame? get latestFrame => _latestFrame;

  int _framesReceived = 0;
  int get framesReceived => _framesReceived;

  int _framesDropped = 0;
  int get framesDropped => _framesDropped;

  double _currentFps = 0.0;
  double get currentFps => _currentFps;

  String? _currentRunId;
  String? get currentRunId => _currentRunId;

  int? _lastSequenceNumber;
  DateTime? _lastFrameReceivedAt;
  final List<DateTime> _frameTimestamps = [];
  Timer? _watchdogTimer;

  // Buffer for incoming packet chunks
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  Future<void> start({int port = defaultPort}) async {
    if (_isRunning) return;
    _port = port;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      _status = CarlaStreamStatus.listening;
      _statusMessage = 'Listening for CARLA camera on port $port';
      _framesReceived = 0;
      _framesDropped = 0;
      _currentFps = 0.0;
      _latestFrame = null;
      _currentRunId = null;
      _lastSequenceNumber = null;
      _buffer.clear();
      _frameTimestamps.clear();

      _watchdogTimer?.cancel();
      _watchdogTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => checkWatchdog(),
      );

      _server!.listen(_handleClientConnection, onError: (e) {
        debugPrint('CarlaCameraStreamService server error: $e');
      });

      notifyListeners();
    } catch (e) {
      _status = CarlaStreamStatus.idle;
      _statusMessage = 'Failed to bind port $port: $e';
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _activeClient?.close();
    _activeClient = null;
    await _server?.close();
    _server = null;
    _isRunning = false;
    _status = CarlaStreamStatus.idle;
    _statusMessage = 'Idle';
    _latestFrame = null;
    _buffer.clear();
    _frameTimestamps.clear();
    notifyListeners();
  }

  void resetSession() {
    _currentRunId = null;
    _lastSequenceNumber = null;
    _latestFrame = null;
    _buffer.clear();
    _frameTimestamps.clear();
    _currentFps = 0.0;
    notifyListeners();
  }

  void _handleClientConnection(Socket client) {
    // If another client is already connected, close it and accept the newest
    _activeClient?.destroy();
    _activeClient = client;
    _buffer.clear();
    _status = CarlaStreamStatus.connected;
    _statusMessage = 'Connected to CARLA video streamer';
    notifyListeners();

    client.listen(
      (Uint8List chunk) {
        _handleIncomingData(chunk);
      },
      onError: (e) {
        debugPrint('Client socket error: $e');
        _handleClientDisconnect();
      },
      onDone: () {
        _handleClientDisconnect();
      },
    );
  }

  void _handleClientDisconnect() {
    _activeClient?.destroy();
    _activeClient = null;
    _buffer.clear();
    if (_isRunning) {
      _status = CarlaStreamStatus.listening;
      _statusMessage = 'Listening for CARLA camera on port $_port';
    } else {
      _status = CarlaStreamStatus.idle;
      _statusMessage = 'Idle';
    }
    notifyListeners();
  }

  void checkWatchdog({DateTime? currentTime}) {
    if (!_isRunning && _activeClient == null && _lastFrameReceivedAt == null) return;

    final now = currentTime ?? DateTime.now();
    final prevStatus = _status;

    if (_lastFrameReceivedAt != null) {
      final elapsedMs = now.difference(_lastFrameReceivedAt!).inMilliseconds;
      if (elapsedMs > 1000) {
        _status = CarlaStreamStatus.stale;
        _statusMessage = 'Camera stream stale (>1s)';
      } else {
        _status = CarlaStreamStatus.connected;
        _statusMessage = 'Streaming (${_currentFps.toStringAsFixed(1)} FPS)';
      }
    } else if (_activeClient == null) {
      if (_status != CarlaStreamStatus.listening && _isRunning) {
        _status = CarlaStreamStatus.listening;
        _statusMessage = 'Listening on port $_port';
      }
    } else {
      _status = CarlaStreamStatus.connected;
      _statusMessage = 'Connected (awaiting initial frame)';
    }

    if (prevStatus != _status) {
      notifyListeners();
    }
  }

  /// Appends incoming data to buffer and parses complete frames.
  void _handleIncomingData(Uint8List chunk, {DateTime? currentTime}) {
    _buffer.add(chunk);
    _parseBuffer(currentTime: currentTime);
  }

  /// Parses buffered bytes. Package visibility for unit testing.
  @visibleForTesting
  void parseBytes(Uint8List bytes, {DateTime? currentTime}) {
    _buffer.add(bytes);
    _parseBuffer(currentTime: currentTime);
  }

  void _parseBuffer({DateTime? currentTime}) {
    Uint8List bytes = _buffer.toBytes();

    while (bytes.length >= headerSize) {
      // Find magic bytes
      int magicIndex = -1;
      for (int i = 0; i <= bytes.length - 4; i++) {
        if (bytes[i] == magicBytes[0] &&
            bytes[i + 1] == magicBytes[1] &&
            bytes[i + 2] == magicBytes[2] &&
            bytes[i + 3] == magicBytes[3]) {
          magicIndex = i;
          break;
        }
      }

      if (magicIndex == -1) {
        // No magic bytes found; discard all except last 3 bytes (in case magic is split across chunks)
        _buffer.clear();
        if (bytes.length > 3) {
          _buffer.add(bytes.sublist(bytes.length - 3));
        }
        return;
      }

      if (magicIndex > 0) {
        // Discard junk bytes before magic
        bytes = Uint8List.sublistView(bytes, magicIndex);
      }

      if (bytes.length < headerSize) {
        _buffer.clear();
        _buffer.add(bytes);
        return;
      }

      final ByteData byteData = ByteData.sublistView(bytes);
      final int version = byteData.getUint16(4, Endian.big);
      final int metaLen = byteData.getUint32(6, Endian.big);
      final int imgLen = byteData.getUint32(10, Endian.big);

      // Sanity checks on size
      if (version != 1 || metaLen > maxMetaSize || imgLen > maxImageSize) {
        // Corrupted header, skip past the bad magic to search for next
        _framesDropped++;
        bytes = Uint8List.sublistView(bytes, 4);
        continue;
      }

      final int totalPacketSize = headerSize + metaLen + imgLen;
      if (bytes.length < totalPacketSize) {
        // Incomplete packet; wait for more data
        _buffer.clear();
        _buffer.add(bytes);
        return;
      }

      // Extract metadata
      final Uint8List metaBytes = Uint8List.sublistView(bytes, headerSize, headerSize + metaLen);
      final Uint8List imgBytes = Uint8List.sublistView(bytes, headerSize + metaLen, totalPacketSize);

      _processExtractedFrame(metaBytes, imgBytes, currentTime: currentTime);

      // Advance buffer
      bytes = Uint8List.sublistView(bytes, totalPacketSize);
    }

    _buffer.clear();
    if (bytes.isNotEmpty) {
      _buffer.add(bytes);
    }
  }

  void _processExtractedFrame(Uint8List metaBytes, Uint8List imgBytes, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    try {
      final String metaStr = utf8.decode(metaBytes);
      final Map<String, dynamic> meta = jsonDecode(metaStr);

      final String runId = meta['scenarioRunId'] as String? ?? 'unknown';
      final int seq = (meta['sequenceNumber'] as num?)?.toInt() ?? 0;
      final double simTime = (meta['simulationTime'] as num?)?.toDouble() ?? 0.0;
      final int simFrame = (meta['simulationFrame'] as num?)?.toInt() ?? 0;
      final int width = (meta['width'] as num?)?.toInt() ?? 640;
      final int height = (meta['height'] as num?)?.toInt() ?? 480;
      final String format = (meta['format'] as String?) ?? 'jpeg';
      final int protoVer = (meta['protocolVersion'] as num?)?.toInt() ?? 1;

      // Handle session reset or sequence ordering
      if (_currentRunId == null || _currentRunId != runId) {
        _currentRunId = runId;
        _lastSequenceNumber = seq;
      } else if (_lastSequenceNumber != null && seq <= _lastSequenceNumber!) {
        // Reject out-of-order or duplicate frame
        _framesDropped++;
        return;
      } else {
        _lastSequenceNumber = seq;
      }

      // Update frame statistics and FPS
      _framesReceived++;
      _lastFrameReceivedAt = now;
      _frameTimestamps.add(now);
      while (_frameTimestamps.isNotEmpty &&
          now.difference(_frameTimestamps.first).inMilliseconds > 2000) {
        _frameTimestamps.removeAt(0);
      }
      if (_frameTimestamps.length > 1) {
        final elapsedSec = now.difference(_frameTimestamps.first).inMilliseconds / 1000.0;
        if (elapsedSec > 0.05) {
          _currentFps = (_frameTimestamps.length - 1) / elapsedSec;
        }
      }

      _latestFrame = CarlaVideoFrame(
        protocolVersion: protoVer,
        scenarioRunId: runId,
        sequenceNumber: seq,
        simulationTime: simTime,
        simulationFrame: simFrame,
        width: width,
        height: height,
        format: format,
        imageBytes: Uint8List.fromList(imgBytes),
        receivedAt: now,
      );

      _status = CarlaStreamStatus.connected;
      _statusMessage = 'Streaming (${_currentFps.toStringAsFixed(1)} FPS)';
      notifyListeners();
    } catch (e) {
      _framesDropped++;
      debugPrint('Error parsing extracted frame: $e');
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _activeClient?.destroy();
    _activeClient = null;
    _server?.close();
    _server = null;
    super.dispose();
  }
}
