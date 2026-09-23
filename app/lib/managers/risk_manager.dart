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

  DateTime? _elevatedStartTime;
  RiskLevel? _elevatedLevel;
  DateTime? _cooldownEndTime;

  bool _isWeatherAvailable = false;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;

  RiskManager(this._gpsService, this._weatherService, this._timeContextService);

  Future<void> start() async {
    // Permission is already verified by HomeScreen during AppState.requestingPermissions
    _positionSubscription = _gpsService.getPositionStream().listen((pos) {
      _currentSpeed = _gpsService.getSpeedKmh(pos);
      _lastSpeedTimestamp = DateTime.now();

      _timeContextService.updateLocation(pos.latitude, pos.longitude);

      _weatherService.getWeather(pos.latitude, pos.longitude).then((weather) {
        _isRaining = weather.isRaining;
        _visibility = weather.visibilityMeters;
        _isWeatherAvailable = weather.isAvailable;
      });
    });

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
    TrackedObject? closestTrack;
    
    for (var track in _currentTracks) {
      if (track.type == RoadObjectType.roadVehicle) {
        nearbyVehiclesCount++;
        
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
          closestTrack = track;
        }
      }
    }

    bool isClosingIn = closestTrack?.closingRate == ClosingRate.closing;

    final contextVector = ContextVector(
      currentSpeed: speedForRisk,
      isRaining: _isRaining,
      isNight: isNight,
      visibility: _visibility,
      isWeatherAvailable: _isWeatherAvailable,
      nearbyVehicles: nearbyVehiclesCount,
      closestVehicleDistance: closestDist,
      isClosingIn: isClosingIn,
    );

    final newAssessment = _riskEngine.assessRisk(contextVector);
    
    // Hysteresis & Cooldown Logic based on timestamps
    if (newAssessment.level == RiskLevel.high || newAssessment.level == RiskLevel.moderate) {
      bool isTrackFresh = closestTrack != null && now.difference(closestTrack.lastSeen).inMilliseconds < 1000;
      
      if (isTrackFresh) {
        if (_elevatedLevel == newAssessment.level) {
          if (_elevatedStartTime != null && now.difference(_elevatedStartTime!).inMilliseconds > 1000) {
            // Elevated for 1 second continuously based on fresh tracks
            _currentAssessment = newAssessment;
            // Set cooldown when dropping back down (brief dropout protection)
            _cooldownEndTime = now.add(const Duration(seconds: 3));
            notifyListeners();
          }
        } else {
          _elevatedLevel = newAssessment.level;
          _elevatedStartTime = now;
        }
      }
    } else {
      // Dropping risk to LOW or LIMITED
      _elevatedLevel = null;
      _elevatedStartTime = null;
      
      bool canDropRisk = _cooldownEndTime == null || now.isAfter(_cooldownEndTime!);
      
      // Clear rule: if no vehicles are nearby at all, we bypass cooldown to drop risk immediately
      if (nearbyVehiclesCount == 0) {
        canDropRisk = true;
        _cooldownEndTime = null;
      }
      
      if (canDropRisk) {
        if (_currentAssessment.level != newAssessment.level || 
            _currentAssessment.howExplanation != newAssessment.howExplanation) {
          _currentAssessment = newAssessment;
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _evaluationTimer?.cancel();
    super.dispose();
  }
}
