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
        return Stack(
          fit: StackFit.expand,
          children: [
            YOLOView(
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
                      boundingBox: r.normalizedBox, // normalized 0.0-1.0
                      type: type,
                    ));
                  }
                }
                context.read<RiskManager>().updateDetections(mappedDetections);
              },
            ),
            _buildRiskOverlay(),
          ],
        );
    }
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

  Widget _buildRiskOverlay() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Consumer<RiskManager>(
        builder: (context, riskManager, child) {
          final assessment = riskManager.currentAssessment;
          
          Color riskColor;
          switch (assessment.level) {
            case RiskLevel.high:
              riskColor = Colors.red;
              break;
            case RiskLevel.moderate:
              riskColor = Colors.orange;
              break;
            case RiskLevel.low:
              riskColor = Colors.green;
              break;
            case RiskLevel.limited:
              riskColor = Colors.grey;
              break;
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: riskColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RISK: ${assessment.level.name.toUpperCase()}', 
                  style: TextStyle(color: riskColor, fontSize: 24, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 8),
                Text('⚠ ${assessment.recommendation}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 8),
                Text('How: ${assessment.howExplanation}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Why: ${assessment.whyExplanation}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          );
        },
      ),
    );
  }
}

