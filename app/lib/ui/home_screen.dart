import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/detected_object.dart';
import '../models/app_state.dart';
import '../models/context_vector.dart';
import '../managers/risk_manager.dart';
import '../services/carla_demo_service.dart';
import 'debug_settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final YOLOViewController _yoloController = YOLOViewController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppFlow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _yoloController.pause();
    } else if (state == AppLifecycleState.resumed) {
      _yoloController.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yoloController.dispose();
    super.dispose();
  }

  Future<void> _startAppFlow() async {
    final appState = context.read<AppStateModel>();
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
        _buildTopBar(isLandscape: false),
        const SizedBox(height: 12),
        Expanded(flex: 3, child: _buildSpeedometer(isLandscape: false)),
        const SizedBox(height: 12),
        Expanded(
          flex: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraFeed(),
              Positioned(
                bottom: 12, left: 12, right: 12,
                child: _buildRiskStatusRing(isLandscape: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildTelemetryCard(isLandscape: false),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left column (Speed + Telemetry)
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(isLandscape: true),
              const SizedBox(height: 8),
              Expanded(flex: 3, child: _buildSpeedometer(isLandscape: true)),
              const SizedBox(height: 8),
              Expanded(flex: 4, child: _buildTelemetryCard(isLandscape: true)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right column (Camera + Overlay Risk)
        Expanded(
          flex: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraFeed(),
              Positioned(
                bottom: 12, left: 12, right: 12,
                child: _buildRiskStatusRing(isLandscape: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraFeed() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: YOLOView(
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
          if (!mounted) return;
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ContextDrive'),
        actions: [
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

  Widget _buildTopBar({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final ctx = riskManager.contextVector;

        String weatherStr;
        IconData weatherIcon;

        switch (ctx.visibilityAssessment) {
          case VisibilityAssessment.poor:
            weatherStr = ctx.isRaining
                ? "Raining"
                : (ctx.isNight ? "Night" : "Low Vis");
            weatherIcon = ctx.isRaining
                ? Icons.water_drop
                : (ctx.isNight ? Icons.nightlight_round : Icons.visibility_off);
            break;
          case VisibilityAssessment.adequate:
            weatherStr = "Clear Vis";
            weatherIcon = Icons.wb_sunny;
            break;
          case VisibilityAssessment.unknown:
            weatherStr = "Vis Unknown";
            weatherIcon = Icons.help_outline;
            break;
        }

        String timeStr = ctx.isNight ? "Night Mode" : "Day Mode";
        IconData timeIcon = ctx.isNight ? Icons.nightlight_round : Icons.brightness_high;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildGlassPill(
              icon: weatherIcon,
              text: weatherStr,
              isLandscape: isLandscape,
            ),
            _buildGlassPill(
              icon: timeIcon,
              text: timeStr,
              isLandscape: isLandscape,
            ),
            _buildVoiceControl(riskManager, isLandscape),
          ],
        );
      },
    );
  }

  Widget _buildSpeedometer({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final speed = riskManager.contextVector.currentSpeed;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            children: [
              Center(
                child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(
                speed != null ? speed.toStringAsFixed(0) : "--",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 56 : 76,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                ),
              ),
              Text(
                "KM/H",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: isLandscape ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTelemetryCard({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final ctx = riskManager.contextVector;
        final vehicleProximity = ctx.closestVehicleDistance < 0.2
            ? 'Vehicle: very near'
            : ctx.closestVehicleDistance < 0.5
                ? 'Vehicle: near'
                : 'Vehicle: clear';
        final riskFocus = vehicleProximity;
          
        return Container(
          padding: EdgeInsets.all(isLandscape ? 8 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTelemetryRow("Vehicles", "${ctx.nearbyVehicles}", Icons.directions_car, isLandscape),

                _buildTelemetryRow("Risk focus", riskFocus, Icons.radar, isLandscape),
                _buildTelemetryRow("Closing", ctx.isClosingIn ? "Yes" : "No", Icons.speed, isLandscape),
                _buildTelemetryRow(
                  "GPS",
                  ctx.currentSpeed != null ? "Valid" : "Waiting",
                  Icons.location_on_outlined,
                  isLandscape,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetryRow(String label, String value, IconData icon, bool isLandscape) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: isLandscape ? 18 : 24),
        SizedBox(width: isLandscape ? 6 : 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: isLandscape ? 13 : 16),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(color: Colors.white, fontSize: isLandscape ? 14 : 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildGlassPill({required IconData icon, required String text, required bool isLandscape}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 12, vertical: isLandscape ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.blueAccent, size: isLandscape ? 14 : 16),
          SizedBox(width: isLandscape ? 4 : 6),
          Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: isLandscape ? 11 : 13)),
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
                                '${_formatTime(event.timestamp)} · ${event.recommendation}',
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
        
        Color riskColor;
        switch (assessment.level) {
          case RiskLevel.high:
            riskColor = Colors.redAccent;
            break;
          case RiskLevel.moderate:
            riskColor = Colors.orangeAccent;
            break;
          case RiskLevel.low:
            riskColor = Colors.greenAccent;
            break;
          case RiskLevel.limited:
            riskColor = Colors.grey;
            break;
        }

        return Container(
          padding: EdgeInsets.symmetric(vertical: isLandscape ? 12 : 16, horizontal: isLandscape ? 12 : 16),
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white30, width: 1),
            boxShadow: [
              if (assessment.level == RiskLevel.high)
                BoxShadow(color: riskColor.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_riskIcon(assessment.level), color: Colors.white, size: isLandscape ? 24 : 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DRIVING RISK',
                          style: TextStyle(color: Colors.white70, fontSize: isLandscape ? 11 : 12, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                        ),
                        Text(
                          _riskTitle(assessment.level),
                          style: TextStyle(color: Colors.white, fontSize: isLandscape ? 17 : 20, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    riskManager.voiceAlertsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    color: Colors.white70,
                    size: isLandscape ? 18 : 20,
                  ),
                ],
              ),
              if (assessment.isStale) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause_circle_outline, size: 13, color: Colors.amberAccent),
                      SizedBox(width: 4),
                      Text(
                        'TELEMETRY INACTIVE / STALE',
                        style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              if (assessment.previousLevel != null && assessment.previousLevel != assessment.level) ...[
                const SizedBox(height: 4),
                Text(
                  'Changed from ${assessment.previousLevel!.name.toUpperCase()} at ${assessment.raisedAt?.hour.toString().padLeft(2, '0')}:${assessment.raisedAt?.minute.toString().padLeft(2, '0')}:${assessment.raisedAt?.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Why: ${assessment.howExplanation}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (assessment.primaryReason.isNotEmpty) ...[
                Text('Observed: ${assessment.primaryReason}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                if (assessment.evidenceReasons.isNotEmpty)
                  Text('Evidence: ${assessment.evidenceReasons.join(" · ")}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
              ],
              if (!isLandscape && assessment.contextModifiers.isNotEmpty) ...[
                Text('Context: ${assessment.contextModifiers.join(" · ")}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 4),
              ],
              Text('Advice: ${assessment.recommendation}', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (!isLandscape)
                Text('Data: ${assessment.dataQuality.join(" · ")}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  String _riskTitle(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return 'HIGH RISK';
      case RiskLevel.moderate:
        return 'CAUTION';
      case RiskLevel.low:
        return 'MONITORING';
      case RiskLevel.limited:
        return 'LIMITED DATA';
    }
  }

  IconData _riskIcon(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return Icons.warning_amber_rounded;
      case RiskLevel.moderate:
        return Icons.warning_rounded;
      case RiskLevel.low:
        return Icons.verified_user_outlined;
      case RiskLevel.limited:
        return Icons.sensors_off_outlined;
    }
  }

  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return Colors.redAccent;
      case RiskLevel.moderate:
        return Colors.orangeAccent;
      case RiskLevel.low:
        return Colors.greenAccent;
      case RiskLevel.limited:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

