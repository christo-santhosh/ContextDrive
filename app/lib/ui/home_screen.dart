import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/detected_object.dart';
import '../models/app_state.dart';
import '../models/context_vector.dart';
import '../managers/risk_manager.dart';

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startAppFlow() async {
    final appState = context.read<AppStateModel>();
    appState.setState(AppState.starting);

    bool hasPermission = await _requestPermissions(appState);
    if (!hasPermission) return;

    appState.setState(AppState.ready);
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
      case AppState.initializingModel:
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
        controller: _yoloController,
        onResult: (results) {
          if (!mounted) return;
          List<DetectedObject> mappedDetections = [];
          for (var r in results) {
            RoadObjectType type = RoadObjectType.ignored;
            if (r.className == 'person' || r.className == 'bicycle') {
              type = RoadObjectType.vulnerableRoadUser;
            } else if (r.className == 'car' || r.className == 'motorcycle' || 
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
        
        String weatherStr = "Checking...";
        IconData weatherIcon = Icons.cloud;
        
        if (ctx.isWeatherAvailable) {
          weatherStr = ctx.isRaining ? "Raining" : "Clear";
          weatherIcon = ctx.isRaining ? Icons.water_drop : Icons.wb_sunny;
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
                  color: Colors.white.withOpacity(0.5),
                  fontSize: isLandscape ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetryCard({required bool isLandscape}) {
    return Consumer<RiskManager>(
      builder: (context, riskManager, child) {
        final ctx = riskManager.contextVector;
        final proximityStr = ctx.closestVehicleDistance < 0.2 ? "Very Near" 
          : ctx.closestVehicleDistance < 0.5 ? "Near" : "Clear";
          
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
                _buildTelemetryRow("Target", proximityStr, Icons.radar, isLandscape),
                _buildTelemetryRow("Closing", ctx.isClosingIn ? "Yes" : "No", Icons.speed, isLandscape),
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
            color: riskColor.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white30, width: 1),
            boxShadow: [
              if (assessment.level == RiskLevel.high)
                BoxShadow(color: riskColor.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SYSTEM STATUS: ${assessment.level.name.toUpperCase()}', 
                style: TextStyle(color: Colors.white, fontSize: isLandscape ? 16 : 18, fontWeight: FontWeight.w900, letterSpacing: 1.0)
              ),
              const SizedBox(height: 4),
              Text(assessment.recommendation, style: TextStyle(color: Colors.white, fontSize: isLandscape ? 14 : 16, fontWeight: FontWeight.w600)),
              if (!isLandscape) ...[
                const SizedBox(height: 4),
                Text(assessment.howExplanation, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ],
          ),
        );
      },
    );
  }
}

