import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../engine/risk_engine.dart';
import '../models/context_vector.dart';
import '../models/detected_object.dart';
import '../services/gps_service.dart';
import '../services/weather_service.dart';
import '../services/time_context_service.dart';

class RiskManager extends ChangeNotifier {
  final GpsService _gpsService;
  final WeatherService _weatherService;
  final TimeContextService _timeContextService;
  final RiskEngine _riskEngine = RiskEngine();

  RiskAssessment _currentAssessment = RiskAssessment(
    level: RiskLevel.low,
    howExplanation: "Initializing...",
    whyExplanation: "Gathering sensor data.",
    recommendation: "Please wait.",
  );

  RiskAssessment get currentAssessment => _currentAssessment;

  double _currentSpeed = 0.0;
  bool _isRaining = false;
  int _visibility = 10000;
  List<DetectedObject> _recentDetections = [];

  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;

  RiskManager(this._gpsService, this._weatherService, this._timeContextService);

  Future<void> start() async {
    bool hasLocation = await _gpsService.requestPermission();
    if (hasLocation) {
      _positionSubscription = _gpsService.getPositionStream().listen((pos) {
        _currentSpeed = _gpsService.getSpeedKmh(pos);
      });
    }

    // Mock initial location for weather fetch
    final weather = await _weatherService.getWeather(0, 0);
    if (weather != null) {
      _isRaining = weather.isRaining;
      _visibility = weather.visibilityMeters;
    }

    // Evaluate risk periodically based on latest state
    _evaluationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _evaluateRisk();
    });
  }

  void updateDetections(List<DetectedObject> detections) {
    _recentDetections = detections;
  }

  void _evaluateRisk() {
    final now = DateTime.now();
    final isNight = _timeContextService.isNight(now);

    // Simple heuristic to extract proximity from bounding boxes (larger box = closer)
    double closestDist = 1.0; 
    for (var d in _recentDetections) {
      if (d.label == 'car' || d.label == 'truck' || d.label == 'bus') {
        // approximate distance inverse based on bounding box area
        double area = d.boundingBox.width * d.boundingBox.height;
        // Assume max area is 1.0 (covers whole screen). 
        // A box covering 50% of the screen is very close (e.g., 0.1 dist)
        double estimatedDistance = 1.0 - area.clamp(0.0, 1.0);
        if (estimatedDistance < closestDist) {
          closestDist = estimatedDistance;
        }
      }
    }

    final contextVector = ContextVector(
      currentSpeed: _currentSpeed,
      isRaining: _isRaining,
      isNight: isNight,
      visibility: _visibility,
      nearbyVehicles: _recentDetections.length,
      closestVehicleDistance: closestDist,
      isClosingIn: false, // Needs temporal tracking of objects across frames
    );

    final newAssessment = _riskEngine.assessRisk(contextVector);
    if (_currentAssessment.level != newAssessment.level || 
        _currentAssessment.howExplanation != newAssessment.howExplanation) {
      _currentAssessment = newAssessment;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _evaluationTimer?.cancel();
    super.dispose();
  }
}
