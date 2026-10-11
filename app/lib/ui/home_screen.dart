import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/detected_object.dart';
import '../models/app_state.dart';
import '../models/context_vector.dart';
import '../managers/risk_manager.dart';
import '../services/carla_demo_service.dart';
import '../services/carla_camera_stream_service.dart';
import 'debug_settings_sheet.dart';

enum PerceptionSource {
  phoneCamera,
  carlaVirtualCamera,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final YOLOViewController _yoloController = YOLOViewController();

  PerceptionSource _perceptionSource = PerceptionSource.phoneCamera;
  YOLO? _carlaYolo;
  bool _isCarlaYoloInitialized = false;
  bool _isProcessingCarlaFrame = false;
  List<DetectedObject> _carlaDetections = [];
  int? _lastProcessedSequence;
  CarlaCameraStreamService? _streamService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppFlow();
      try {
        _streamService = context.read<CarlaCameraStreamService>();
        _streamService?.addListener(_onCarlaStreamFrame);
      } catch (_) {
        // Stream service optional in test harness
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_perceptionSource == PerceptionSource.phoneCamera) {
        _yoloController.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_perceptionSource == PerceptionSource.phoneCamera) {
        _yoloController.resume();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamService?.removeListener(_onCarlaStreamFrame);
    _yoloController.dispose();
    super.dispose();
  }

  Future<void> _startAppFlow() async {
    final appState = context.read<AppStateModel>();
    if (appState.currentState == AppState.ready) return;
    appState.setState(AppState.starting);

    bool hasPermission = await _requestPermissions(appState);
    if (!hasPermission) return;

    appState.setState(AppState.initializingModel);
  }

  Future<bool> _requestPermissions(AppStateModel appState) async {
    appState.setState(AppState.requestingPermissions);
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) appState.setState(AppState.cameraUnavailable, error: "Camera permission denied.");
      return false;
    }

    final locationStatus = await Permission.location.request();
    bool locationAvailable = locationStatus.isGranted;
    
    if (!locationAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied. GPS speed unavailable. Using limited risk assessment.")),
        );
      }
    }
    
    if (mounted) {
      context.read<RiskManager>().start(locationAvailable: locationAvailable);
    }
    
    return true;
  }

  Widget _buildStateUI(AppStateModel state) {
    switch (state.currentState) {
      case AppState.starting:
      case AppState.requestingPermissions:
      case AppState.initializingCamera:
        return const Center(child: CircularProgressIndicator());
      case AppState.cameraUnavailable:
      case AppState.locationUnavailable:
      case AppState.modelFailed:
      case AppState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(state.errorMessage),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _startAppFlow(),
                child: const Text("Retry"),
              )
            ],
          ),
        );
      case AppState.initializingModel:
        return Stack(
          children: [
            Offstage(
              offstage: true,
              child: _buildDashboard(context),
            ),
            Container(
              color: const Color(0xFF0A0A0A),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 24),
                    Text(
                      "Preparing camera & model...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case AppState.ready:
        return _buildDashboard(context);
    }
  }

  Widget _buildDashboard(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      color: const Color(0xFF0A0A0A), // Deep black/slate background
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isLandscape 
              ? _buildLandscapeLayout(context)
              : _buildPortraitLayout(context),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSpeedDashboard(isLandscape: false),
        const SizedBox(height: 8),
        Expanded(
          child: _buildCameraFeed(),
        ),
        const SizedBox(height: 8),
        _buildRiskStatusRing(isLandscape: false),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left column (Speed + Alerts with integrated Telemetry)
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSpeedDashboard(isLandscape: true),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildRiskStatusRing(isLandscape: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Right column (Full unobstructed Camera Feed)
        Expanded(
          flex: 6,
          child: _buildCameraFeed(),
        ),
      ],
    );
  }

  void _onCarlaStreamFrame() {
    if (!mounted || _perceptionSource != PerceptionSource.carlaVirtualCamera) return;
    final streamService = _streamService ?? context.read<CarlaCameraStreamService>();
    final frame = streamService.latestFrame;
    if (frame == null) return;
    if (frame.sequenceNumber == _lastProcessedSequence) return;
    if (_isProcessingCarlaFrame) return;

    _lastProcessedSequence = frame.sequenceNumber;
    _isProcessingCarlaFrame = true;
    _runCarlaYoloInference(frame);
  }

  Future<void> _runCarlaYoloInference(CarlaVideoFrame frame) async {
    try {
      if (_carlaYolo == null || !_isCarlaYoloInitialized) {
        _carlaYolo = YOLO(modelPath: 'yolo26n', task: YOLOTask.detect);
        await _carlaYolo!.loadModel();
        _isCarlaYoloInitialized = true;
      }
      final results = await _carlaYolo!.predict(frame.imageBytes);
      final rawDetections = results['detections'] as List<dynamic>? ?? [];
      List<DetectedObject> mapped = [];
      for (final item in rawDetections) {
        if (item is Map) {
          final yoloRes = YOLOResult.fromMap(item);
          RoadObjectType type = RoadObjectType.ignored;
          if (yoloRes.className == 'car' ||
              yoloRes.className == 'motorcycle' ||
              yoloRes.className == 'bus' ||
              yoloRes.className == 'truck') {
            type = RoadObjectType.roadVehicle;
          }
          if (type != RoadObjectType.ignored) {
            mapped.add(DetectedObject(
              label: yoloRes.className,
              confidence: yoloRes.confidence,
              boundingBox: yoloRes.normalizedBox,
              type: type,
            ));
          }
        }
      }
      if (mounted && _perceptionSource == PerceptionSource.carlaVirtualCamera) {
        context.read<RiskManager>().updateDetections(mapped);
        setState(() {
          _carlaDetections = mapped;
        });
      }
    } catch (e) {
      debugPrint('CARLA YOLO inference error: $e');
    } finally {
      _isProcessingCarlaFrame = false;
    }
  }

  Future<void> _togglePerceptionSource() async {
    if (_perceptionSource == PerceptionSource.phoneCamera) {
      await _switchToCarlaCamera();
    } else {
      await _switchToPhoneCamera();
    }
  }

  Future<void> _switchToCarlaCamera() async {
    final riskManager = context.read<RiskManager>();
    final stream = context.read<CarlaCameraStreamService>();

    setState(() {
      _perceptionSource = PerceptionSource.carlaVirtualCamera;
      _carlaDetections = [];
    });
    // Pause physical camera on Android
    try {
      await _yoloController.pause();
    } catch (e) {
      debugPrint('Error pausing YOLO controller: $e');
    }
    // Clear tracking history to prevent old proximity state from carrying over
    riskManager.resetTracking();

    // Start stream service if not running
    if (!stream.isRunning) {
      await stream.start();
    }

    // Pre-initialize standalone YOLO model for external inference
    if (_carlaYolo == null || !_isCarlaYoloInitialized) {
      try {
        _carlaYolo = YOLO(modelPath: 'yolo26n', task: YOLOTask.detect);
        await _carlaYolo!.loadModel();
        _isCarlaYoloInitialized = true;
      } catch (e) {
        debugPrint('Error loading standalone YOLO model: $e');
      }
    }
  }

  Future<void> _switchToPhoneCamera() async {
    final riskManager = context.read<RiskManager>();
    setState(() {
      _perceptionSource = PerceptionSource.phoneCamera;
      _carlaDetections = [];
      _isProcessingCarlaFrame = false;
    });
    // Clear tracking history
    riskManager.resetTracking();
    // Resume physical camera
    try {
      await _yoloController.resume();
    } catch (e) {
      debugPrint('Error resuming YOLO controller: $e');
    }
  }

  Widget _buildCameraFeed() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _perceptionSource != PerceptionSource.phoneCamera,
            child: _buildPhysicalCameraFeed(),
          ),
          if (_perceptionSource == PerceptionSource.carlaVirtualCamera)
            _buildCarlaVirtualCameraFeed(),
        ],
      ),
    );
  }

  Widget _buildPhysicalCameraFeed() {
    return YOLOView(
      modelPath: 'yolo26n',
      task: YOLOTask.detect,
      controller: _yoloController,
      onModelLoad: (path, task) {
        if (mounted) {
          // Model is successfully loaded and running
          context.read<AppStateModel>().setState(AppState.ready);
        }
      },
      onModelError: (error, path, task) {
        if (mounted) {
          context.read<AppStateModel>().setState(AppState.modelFailed, error: "Failed to load model: $error");
        }
      },
      onResult: (results) {
        if (!mounted || _perceptionSource != PerceptionSource.phoneCamera) return;
        List<DetectedObject> mappedDetections = [];
        for (var r in results) {
          RoadObjectType type = RoadObjectType.ignored;
          if (r.className == 'car' || r.className == 'motorcycle' || 
              r.className == 'bus' || r.className == 'truck') {
            type = RoadObjectType.roadVehicle;
          }

          if (type != RoadObjectType.ignored) {
            mappedDetections.add(DetectedObject(
              label: r.className,
              confidence: r.confidence,
              boundingBox: r.normalizedBox,
              type: type,
            ));
          }
        }
        context.read<RiskManager>().updateDetections(mappedDetections);
      },
    );
  }

  Widget _buildCarlaVirtualCameraFeed() {
    return Consumer<CarlaCameraStreamService>(
      builder: (context, streamService, _) {
        final frame = streamService.latestFrame;
        final status = streamService.status;

        Widget content;
        if (frame != null) {
          content = Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                frame.imageBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              CustomPaint(
                painter: BoundingBoxPainter(detections: _carlaDetections),
              ),
              if (status == CarlaStreamStatus.stale)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'CARLA CAMERA DATA STALE (>1s)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        } else {
          content = Container(
            color: const Color(0xFF10141A),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status == CarlaStreamStatus.listening
                          ? Icons.cable
                          : Icons.videocam_off,
                      size: 44,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      status == CarlaStreamStatus.listening
                          ? 'WAITING FOR CARLA CAMERA STREAM'
                          : 'CARLA CAMERA DISCONNECTED',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Listening on 127.0.0.1:${streamService.port}\nadb reverse tcp:${streamService.port} tcp:${streamService.port}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            content,
            // Diagnostic HUD pill at top-right
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: status == CarlaStreamStatus.connected
                        ? Colors.greenAccent
                        : status == CarlaStreamStatus.stale
                            ? Colors.amberAccent
                            : Colors.white30,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status == CarlaStreamStatus.connected
                            ? Colors.greenAccent
                            : status == CarlaStreamStatus.stale
                                ? Colors.amberAccent
                                : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CARLA USB: ${streamService.currentFps.toStringAsFixed(1)} FPS (${_carlaDetections.length} det)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ContextDrive',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        titleSpacing: 16,
        actions: [
          // ── Perception Source Selector ──
          IconButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
            tooltip: _perceptionSource == PerceptionSource.phoneCamera
                ? 'Perception: Phone Camera (Tap to switch to CARLA Stream)'
                : 'Perception: CARLA Virtual Camera (Tap to switch to Phone)',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _perceptionSource == PerceptionSource.phoneCamera
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.cyanAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _perceptionSource == PerceptionSource.phoneCamera
                      ? Colors.white24
                      : Colors.cyanAccent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _perceptionSource == PerceptionSource.phoneCamera
                        ? Icons.camera_alt_outlined
                        : Icons.videocam,
                    size: 14,
                    color: _perceptionSource == PerceptionSource.phoneCamera
                        ? Colors.white70
                        : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _perceptionSource == PerceptionSource.phoneCamera ? 'PHONE' : 'CARLA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _perceptionSource == PerceptionSource.phoneCamera
                          ? Colors.white70
                          : Colors.cyanAccent,
                    ),
                  ),
                ],
              ),
            ),
            onPressed: _togglePerceptionSource,
          ),
          const SizedBox(width: 4),
          Consumer<CarlaDemoService>(
            builder: (context, carla, _) {
              Color badgeBg;
              Color badgeBorder;
              Color badgeText;
              IconData badgeIcon;
              String badgeLabel;

              if (!carla.isRunning) {
                badgeBg = Colors.white.withValues(alpha: 0.05);
                badgeBorder = Colors.white24;
                badgeText = Colors.white60;
                badgeIcon = Icons.directions_car_outlined;
                badgeLabel = 'PHYSICAL';
              } else {
                switch (carla.connectionStatus) {
                  case CarlaConnectionStatus.active:
                    badgeBg = Colors.blueAccent.withValues(alpha: 0.2);
                    badgeBorder = Colors.blueAccent;
                    badgeText = Colors.lightBlueAccent;
                    badgeIcon = Icons.cloud_done;
                    badgeLabel = 'CARLA ACTIVE (${carla.packetsReceived})';
                    break;
                  case CarlaConnectionStatus.paused:
                    badgeBg = Colors.amber.withValues(alpha: 0.2);
                    badgeBorder = Colors.amber;
                    badgeText = Colors.amberAccent;
                    badgeIcon = Icons.pause_circle_outline;
                    badgeLabel = 'CARLA PAUSED';
                    break;
                  case CarlaConnectionStatus.disconnected:
                    badgeBg = Colors.redAccent.withValues(alpha: 0.2);
                    badgeBorder = Colors.redAccent;
                    badgeText = Colors.redAccent;
                    badgeIcon = Icons.cloud_off;
                    badgeLabel = 'CARLA DISCONNECTED';
                    break;
                  case CarlaConnectionStatus.listening:
                    badgeBg = Colors.white.withValues(alpha: 0.1);
                    badgeBorder = Colors.white30;
                    badgeText = Colors.white70;
                    badgeIcon = Icons.hourglass_empty;
                    badgeLabel = 'CARLA WAITING';
                    break;
                  case CarlaConnectionStatus.idle:
                    badgeBg = Colors.white.withValues(alpha: 0.05);
                    badgeBorder = Colors.white24;
                    badgeText = Colors.white54;
                    badgeIcon = Icons.cloud_off;
                    badgeLabel = 'CARLA IDLE';
                    break;
                }
              }

              return TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: badgeBg,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: badgeBorder),
                  ),
                ),
                icon: Icon(badgeIcon, size: 16, color: badgeText),
                label: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeText,
                  ),
                ),
                onPressed: () {
                  if (carla.isRunning) {
                    carla.stop();
                  } else {
                    carla.start();
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Debug Settings',
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => const DebugSettingsSheet(),
              );
            },
          ),
          IconButton(
            tooltip: 'Recent risk alerts',
            icon: const Icon(Icons.history_rounded),
            onPressed: _showRecentAlerts,
          ),
        ],
      ),
      body: Consumer<AppStateModel>(
        builder: (context, appState, _) {
          return _buildStateUI(appState);
        },
      ),
    );
  }

  Widget _buildSpeedDashboard({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final speed = riskManager.contextVector.currentSpeed;
        final speedLimit = riskManager.contextVector.currentSpeedLimit;
        final ctx = riskManager.contextVector;
        final liveWeather = riskManager.liveWeather;

        // Dedicated Weather indicator (strictly meteorological, NEVER shows Time/Night)
        String weatherStr;
        IconData weatherIcon;
        if (ctx.isRaining) {
          weatherStr = ctx.weatherCategory == WeatherCategory.heavyRain ? "Heavy Rain" : "Raining";
          weatherIcon = ctx.weatherCategory == WeatherCategory.heavyRain ? Icons.thunderstorm : Icons.water_drop;
        } else if (ctx.weatherCategory == WeatherCategory.fog) {
          weatherStr = "Fog";
          weatherIcon = Icons.cloud;
        } else if (liveWeather != null && liveWeather.isAvailable) {
          final desc = liveWeather.description.toLowerCase();
          if (desc.contains('cloud') || desc.contains('overcast')) {
            weatherStr = "Cloudy";
            weatherIcon = Icons.cloud_outlined;
          } else if (desc.contains('clear')) {
            weatherStr = "Clear";
            weatherIcon = Icons.wb_sunny_outlined;
          } else if (desc.contains('rain') || desc.contains('drizzle')) {
            weatherStr = "Rain";
            weatherIcon = Icons.water_drop_outlined;
          } else if (desc.contains('fog') || desc.contains('mist') || desc.contains('haze')) {
            weatherStr = "Hazy";
            weatherIcon = Icons.cloud_outlined;
          } else {
            weatherStr = liveWeather.description.length > 8
                ? liveWeather.description.substring(0, 8)
                : liveWeather.description;
            weatherIcon = Icons.cloud_outlined;
          }
        } else if (ctx.weatherCategory == WeatherCategory.clear) {
          weatherStr = "Clear";
          weatherIcon = Icons.wb_sunny_outlined;
        } else {
          weatherStr = "Weather N/A";
          weatherIcon = Icons.cloud_off_outlined;
        }

        // Dedicated Time indicator (Day vs Night vs Dawn/Dusk)
        String timeStr;
        IconData timeIcon;
        switch (ctx.daylightCondition) {
          case DaylightCondition.night:
            timeStr = 'Night';
            timeIcon = Icons.nightlight_round;
            break;
          case DaylightCondition.day:
            timeStr = 'Day';
            timeIcon = Icons.brightness_high;
            break;
          case DaylightCondition.dawnDusk:
            timeStr = 'Dawn/Dusk';
            timeIcon = Icons.wb_twilight;
            break;
          case DaylightCondition.unknown:
            timeStr = ctx.isNight ? 'Night' : 'Day';
            timeIcon = ctx.isNight ? Icons.nightlight_round : Icons.brightness_high;
            break;
        }

        return Container(
          height: isLandscape ? 48 : 56,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Text(
                speed != null ? speed.toStringAsFixed(0) : "--",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 26 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "KM/H",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              if (speedLimit != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.redAccent, width: 2.5),
                  ),
                  child: Center(
                    child: Text(
                      "$speedLimit",
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildGlassPill(
                          icon: weatherIcon,
                          text: weatherStr,
                          isLandscape: isLandscape,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildGlassPill(
                          icon: timeIcon,
                          text: timeStr,
                          isLandscape: isLandscape,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildVoiceControl(riskManager, isLandscape),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _telemetryChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 12),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildGlassPill({required IconData icon, required String text, required bool isLandscape}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 6 : 8, vertical: isLandscape ? 4 : 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.blueAccent, size: isLandscape ? 12 : 14),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: isLandscape ? 10 : 11)),
        ],
      ),
    );
  }

  Widget _buildVoiceControl(RiskManager riskManager, bool isLandscape) {
    final enabled = riskManager.voiceAlertsEnabled;
    return Tooltip(
      message: enabled ? 'Voice alerts on' : 'Voice alerts off',
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161618),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled ? Colors.blueAccent.withValues(alpha: 0.7) : Colors.white10,
          ),
        ),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => riskManager.setVoiceAlertsEnabled(!enabled),
          icon: Icon(
            enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: enabled ? Colors.blueAccent : Colors.white54,
            size: isLandscape ? 18 : 22,
          ),
        ),
      ),
    );
  }

  void _showRecentAlerts() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161618),
      showDragHandle: true,
      builder: (sheetContext) {
        final riskManager = sheetContext.read<RiskManager>();
        final alerts = riskManager.recentAlerts;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: alerts.isEmpty
                ? const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'No elevated-risk events in this session',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Recent risk alerts',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              riskManager.clearRecentAlerts();
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: alerts.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: Colors.white12),
                          itemBuilder: (context, index) {
                            final event = alerts[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _riskIcon(event.level),
                                color: _riskColor(event.level),
                              ),
                              title: Text(
                                event.reason,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${_formatTime(event.timestamp)} Â· ${event.recommendation}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildRiskStatusRing({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final assessment = riskManager.currentAssessment;
        final ctx = riskManager.contextVector;
        final vehicleProximity = ctx.closestVehicleDistance < 0.2
            ? 'Very near'
            : ctx.closestVehicleDistance < 0.5
                ? 'Near'
                : 'Clear';
        
        Color riskColor;
        switch (assessment.level) {
          case RiskLevel.critical:
            riskColor = Colors.deepPurpleAccent;
            break;
          case RiskLevel.high:
            riskColor = Colors.redAccent;
            break;
          case RiskLevel.moderate:
            riskColor = Colors.orangeAccent;
            break;
          case RiskLevel.low:
            riskColor = Colors.greenAccent;
            break;
        }

        return Container(
          padding: EdgeInsets.symmetric(vertical: isLandscape ? 8 : 10, horizontal: isLandscape ? 10 : 14),
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white30, width: 1),
            boxShadow: [
              if (assessment.level == RiskLevel.high || assessment.level == RiskLevel.critical)
                BoxShadow(color: riskColor.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_riskIcon(assessment.level), color: Colors.white, size: isLandscape ? 18 : 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _riskTitle(assessment.level),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLandscape ? 14 : 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (assessment.isStale)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_outline, size: 10, color: Colors.amberAccent),
                          SizedBox(width: 2),
                          Text(
                            'STALE',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  else if (assessment.dataQualityStatus != AssessmentDataQuality.good)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        assessment.dataQualityStatus == AssessmentDataQuality.limited
                            ? 'LIMITED'
                            : 'STALE',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    riskManager.voiceAlertsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'What happened: ${assessment.whatHappened}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Advice: ${assessment.recommendation}',
                style: const TextStyle(color: Colors.yellowAccent, fontSize: 12, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (assessment.advisories.isNotEmpty || assessment.contextModifiers.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  assessment.advisories.isNotEmpty
                      ? 'Advisory: ${assessment.advisories.first}'
                      : 'Context: ${assessment.contextModifiers.join(" · ")}',
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Integrated Telemetry Tray (Connected directly with zero gap & overflow-proof scaling)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _telemetryChip(Icons.directions_car, "${ctx.nearbyVehicles} veh"),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _telemetryChip(Icons.radar, vehicleProximity),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _telemetryChip(Icons.speed, ctx.isClosingIn ? "Closing: YES" : "Closing: NO"),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _telemetryChip(
                            Icons.location_on_outlined,
                            ctx.currentSpeed != null ? "GPS: OK" : "GPS: Waiting",
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _riskTitle(RiskLevel level) {
    switch (level) {
      case RiskLevel.critical:
        return 'CRITICAL HAZARD';
      case RiskLevel.high:
        return 'HIGH RISK';
      case RiskLevel.moderate:
        return 'CAUTION';
      case RiskLevel.low:
        return 'MONITORING';
    }
  }

  IconData _riskIcon(RiskLevel level) {
    switch (level) {
      case RiskLevel.critical:
        return Icons.crisis_alert_rounded;
      case RiskLevel.high:
        return Icons.warning_amber_rounded;
      case RiskLevel.moderate:
        return Icons.warning_rounded;
      case RiskLevel.low:
        return Icons.verified_user_outlined;
    }
  }

  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.critical:
        return Colors.deepPurpleAccent;
      case RiskLevel.high:
        return Colors.redAccent;
      case RiskLevel.moderate:
        return Colors.orangeAccent;
      case RiskLevel.low:
        return Colors.greenAccent;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;

  BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final boxPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );

    for (final det in detections) {
      final rect = Rect.fromLTRB(
        det.boundingBox.left * size.width,
        det.boundingBox.top * size.height,
        det.boundingBox.right * size.width,
        det.boundingBox.bottom * size.height,
      );

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, boxPaint);

      final labelText = '${det.label} ${(det.confidence * 100).toInt()}%';
      final span = TextSpan(text: labelText, style: textStyle);
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        max(0.0, rect.top - tp.height - 4),
        tp.width + 8,
        tp.height + 4,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(labelRect, const Radius.circular(4)), bgPaint);
      tp.paint(canvas, Offset(labelRect.left + 4, labelRect.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}


