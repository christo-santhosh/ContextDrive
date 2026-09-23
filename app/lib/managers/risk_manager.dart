import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../engine/risk_engine.dart';
import '../models/context_vector.dart';
import '../models/detected_object.dart';
import '../services/gps_service.dart';
import '../services/weather_service.dart';
import '../services/time_context_service.dart';
import '../models/tracked_object.dart';
import 'object_tracker.dart';

class RiskManager extends ChangeNotifier {
  final GpsService _gpsService;
  final WeatherService _weatherService;
  final TimeContextService _timeContextService;
  final RiskEngine _riskEngine = RiskEngine();
  final ObjectTracker _tracker = ObjectTracker();

  RiskAssessment _currentAssessment = RiskAssessment(
    level: RiskLevel.low,
    howExplanation: "Initializing...",
    whyExplanation: "Gathering sensor data.",
    recommendation: "Please wait.",
  );

  RiskAssessment get currentAssessment => _currentAssessment;

  double? _currentSpeed;
  DateTime? _lastSpeedTimestamp;
  bool _isRaining = false;
  int _visibility = 10000;
  List<TrackedObject> _currentTracks = [];

  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;

  RiskManager(this._gpsService, this._weatherService, this._timeContextService);

  Future<void> start() async {
    bool hasLocation = await _gpsService.requestPermission();
    if (hasLocation) {
      _positionSubscription = _gpsService.getPositionStream().listen((pos) {
        _currentSpeed = _gpsService.getSpeedKmh(pos);
        _lastSpeedTimestamp = DateTime.now();
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
    _currentTracks = _tracker.updateTracks(detections);
  }

  void _evaluateRisk() {
    final now = DateTime.now();
    
    // Check speed staleness (5 seconds)
    double? speedForRisk = _currentSpeed;
    if (_lastSpeedTimestamp == null || now.difference(_lastSpeedTimestamp!).inSeconds > 5) {
      speedForRisk = null; // Stale or unavailable
    }

    final isNight = _timeContextService.isNight(now);

    double closestDist = 1.0;
    int nearbyVehiclesCount = 0;
    bool isClosingIn = false;
    
    for (var track in _currentTracks) {
      if (track.type == RoadObjectType.roadVehicle) {
        nearbyVehiclesCount++;
        
        if (track.closingRate == ClosingRate.closing) {
          isClosingIn = true;
        }

        // Proximity categories mapped to the engine's 0-1 scale expectation (or update engine)
        double estimatedDistance = 1.0;
        switch (track.proximity) {
          case ProximityCategory.veryNear: estimatedDistance = 0.1; break;
          case ProximityCategory.near: estimatedDistance = 0.3; break;
          case ProximityCategory.medium: estimatedDistance = 0.6; break;
          case ProximityCategory.far: 
          case ProximityCategory.unknown: 
            estimatedDistance = 1.0; break;
        }

        if (estimatedDistance < closestDist) {
          closestDist = estimatedDistance;
        }
      }
    }

    final contextVector = ContextVector(
      currentSpeed: speedForRisk,
      isRaining: _isRaining,
      isNight: isNight,
      visibility: _visibility,
      nearbyVehicles: nearbyVehiclesCount,
      closestVehicleDistance: closestDist,
      isClosingIn: isClosingIn,
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
