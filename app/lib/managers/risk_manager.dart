import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../engine/risk_engine.dart';
import '../models/context_vector.dart';
import '../models/detected_object.dart';
import '../services/gps_service.dart';
import '../services/weather_service.dart';
import '../services/time_context_service.dart';
import '../services/imu_service.dart';
import '../services/speed_limit_service.dart';
import '../services/risk_alert_service.dart';
import '../models/risk_event.dart';
import '../models/tracked_object.dart';
import 'object_tracker.dart';

class RiskManager extends ChangeNotifier {
  final GpsService _gpsService;
  final WeatherService _weatherService;
  final TimeContextService _timeContextService;
  final ImuService _imuService = ImuService();
  final SpeedLimitService _speedLimitService = SpeedLimitService();
  final RiskAlertService _riskAlertService = RiskAlertService();
  final RiskEngine _riskEngine = RiskEngine();
  final ObjectTracker _tracker = ObjectTracker();

  RiskAssessment _currentAssessment = RiskAssessment(
    level: RiskLevel.low,
    howExplanation: "Initializing...",
    whyExplanation: "Gathering sensor data.",
    recommendation: "Please wait.",
  );

  RiskAssessment get currentAssessment => _currentAssessment;
  final List<RiskEvent> _recentAlerts = [];
  List<RiskEvent> get recentAlerts => List.unmodifiable(_recentAlerts);
  bool _voiceAlertsEnabled = true;
  bool get voiceAlertsEnabled => _voiceAlertsEnabled;
  
  ContextVector _lastContextVector = ContextVector(
      currentSpeed: null,
      currentSpeedLimit: null,
      isRaining: false,
      isNight: false,
      visibility: 10000,
      isWeatherAvailable: false,
      nearbyVehicles: 0,
      closestVehicleDistance: 1.0,
      isClosingIn: false,
      isErraticDriving: false,
  );
  
  ContextVector get contextVector => _lastContextVector;

  double? _currentSpeed;
  DateTime? _lastSpeedTimestamp;
  SpeedReading? _latestSpeedReading;
  int _consecutiveInvalidReadings = 0;
  bool _isRaining = false;
  int _visibility = 10000;
  List<TrackedObject> _currentTracks = [];

  DateTime? _elevatedStartTime;
  RiskLevel? _elevatedLevel;
  DateTime? _cooldownEndTime;

  bool _isWeatherAvailable = false;
  DateTime? _weatherLastUpdated;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;
  bool _isStarted = false;

  RiskManager(this._gpsService, this._weatherService, this._timeContextService);

  Future<void> start({required bool locationAvailable}) async {
    if (_isStarted) return;
    _isStarted = true;

    _imuService.start();

    if (locationAvailable) {
      _positionSubscription = _gpsService.getPositionStream().listen((pos) {
        _latestSpeedReading = _gpsService.processPosition(pos);
        if (_latestSpeedReading!.isValid) {
          _currentSpeed = _latestSpeedReading!.valueKmh;
          _lastSpeedTimestamp = _latestSpeedReading!.timestamp;
          _consecutiveInvalidReadings = 0;
        } else {
          _consecutiveInvalidReadings++;
        }

        _timeContextService.updateLocation(pos.latitude, pos.longitude);
        _speedLimitService.updateSpeedLimit(pos.latitude, pos.longitude);

        _weatherService.getWeather(pos.latitude, pos.longitude).then((weather) {
          _isRaining = weather.isRaining;
          _visibility = weather.visibilityMeters;
          _isWeatherAvailable = weather.isAvailable;
          _weatherLastUpdated = weather.lastUpdated;
        });
      });
    }

    // Evaluate risk periodically based on latest state
    _evaluationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _evaluateRisk();
    });
  }

  void updateDetections(List<DetectedObject> detections) {
    _currentTracks = _tracker.updateTracks(detections);
  }

  void setVoiceAlertsEnabled(bool enabled) {
    if (_voiceAlertsEnabled == enabled) return;
    _voiceAlertsEnabled = enabled;
    notifyListeners();

    if (enabled) {
      _riskAlertService.announce(
        _currentAssessment,
        enabled: true,
        force: true,
      );
    } else {
      _riskAlertService.stop();
    }
  }

  void clearRecentAlerts() {
    if (_recentAlerts.isEmpty) return;
    _recentAlerts.clear();
    notifyListeners();
  }

  void _evaluateRisk() {
    final now = DateTime.now();
    
    // Check speed staleness (5 seconds) or repeated invalid readings
    double? speedForRisk = _currentSpeed;
    String? gpsReason;
    if (_consecutiveInvalidReadings >= 3) {
      speedForRisk = null;
      gpsReason = _latestSpeedReading?.rejectionReason;
    } else if (_lastSpeedTimestamp == null || now.difference(_lastSpeedTimestamp!).inSeconds > 5) {
      speedForRisk = null; // Stale or unavailable
      gpsReason = "Stale GNSS timestamp";
    }

    final isNight = _timeContextService.isNight(now);

    double closestDist = 1.0;
    int nearbyVehiclesCount = 0;
    TrackedObject? closestTrack;
    double closestVulnerableRoadUserDistance = 1.0;
    int nearbyVulnerableRoadUsersCount = 0;
    TrackedObject? closestVulnerableRoadUser;
    
    for (var track in _currentTracks) {
      final estimatedDistance = _relativeDistance(track.proximity);
      if (track.type == RoadObjectType.roadVehicle) {
        nearbyVehiclesCount++;
        if (estimatedDistance < closestDist) {
          closestDist = estimatedDistance;
          closestTrack = track;
        }
      } else if (track.type == RoadObjectType.vulnerableRoadUser) {
        nearbyVulnerableRoadUsersCount++;
        if (estimatedDistance < closestVulnerableRoadUserDistance) {
          closestVulnerableRoadUserDistance = estimatedDistance;
          closestVulnerableRoadUser = track;
        }
      }
    }

    bool isClosingIn = closestTrack?.closingRate == ClosingRate.closing;
    bool isVulnerableRoadUserClosing =
        closestVulnerableRoadUser?.closingRate == ClosingRate.closing;

    bool weatherAvailable = _isWeatherAvailable;
    if (_weatherLastUpdated != null && now.difference(_weatherLastUpdated!).inMinutes > 30) {
      weatherAvailable = false;
    }

    _lastContextVector = ContextVector(
      currentSpeed: speedForRisk,
      currentSpeedLimit: _speedLimitService.currentSpeedLimit,
      isRaining: _isRaining,
      isNight: isNight,
      visibility: _visibility,
      isWeatherAvailable: weatherAvailable,
      nearbyVehicles: nearbyVehiclesCount,
      closestVehicleDistance: closestDist,
      isClosingIn: isClosingIn,
      nearbyVulnerableRoadUsers: nearbyVulnerableRoadUsersCount,
      closestVulnerableRoadUserDistance: closestVulnerableRoadUserDistance,
      isVulnerableRoadUserClosing: isVulnerableRoadUserClosing,
      isErraticDriving: _imuService.isErratic,
      gpsQualityReason: gpsReason,
    );

    final newAssessment = _riskEngine.assessRisk(_lastContextVector);
    
    // Hysteresis & Cooldown Logic based on timestamps
    if (newAssessment.level == RiskLevel.high || newAssessment.level == RiskLevel.moderate) {
      if (_elevatedLevel == newAssessment.level) {
        if (_elevatedStartTime != null && now.difference(_elevatedStartTime!).inMilliseconds > 1000) {
          // Elevated for 1 second continuously
          if (_currentAssessment.level != newAssessment.level) {
            _currentAssessment = newAssessment.copyWith(
              raisedAt: now,
              previousLevel: _currentAssessment.level,
            );
            _recordAlert(_currentAssessment);
            notifyListeners();
            _riskAlertService.announce(
              _currentAssessment,
              enabled: _voiceAlertsEnabled,
            );
          } else if (_currentAssessment.primaryReason != newAssessment.primaryReason) {
            _currentAssessment = newAssessment.copyWith(
              raisedAt: _currentAssessment.raisedAt ?? now,
              previousLevel: _currentAssessment.previousLevel,
            );
            _recordAlert(_currentAssessment);
            notifyListeners();
            _riskAlertService.announce(
              _currentAssessment,
              enabled: _voiceAlertsEnabled,
            );
          }
          // Set cooldown when dropping back down (brief dropout protection)
          _cooldownEndTime = now.add(const Duration(seconds: 3));
        }
      } else {
        _elevatedLevel = newAssessment.level;
        _elevatedStartTime = now;
      }
    } else {
      // Dropping risk to LOW or LIMITED
      _elevatedLevel = null;
      _elevatedStartTime = null;
      
      bool canDropRisk = _cooldownEndTime == null || now.isAfter(_cooldownEndTime!);
      
      // Clear rule: if no vehicles are nearby at all, we bypass cooldown to drop risk immediately
      if (nearbyVehiclesCount + nearbyVulnerableRoadUsersCount == 0) {
        canDropRisk = true;
        _cooldownEndTime = null;
      }
      
      if (canDropRisk) {
        if (_currentAssessment.level != newAssessment.level || 
            _currentAssessment.howExplanation != newAssessment.howExplanation) {
          _currentAssessment = newAssessment;
          _riskAlertService.clearActiveAlert();
          notifyListeners();
        }
      }
    }
  }

  double _relativeDistance(ProximityCategory proximity) {
    switch (proximity) {
      case ProximityCategory.veryNear:
        return 0.1;
      case ProximityCategory.near:
        return 0.3;
      case ProximityCategory.medium:
        return 0.6;
      case ProximityCategory.far:
      case ProximityCategory.unknown:
        return 1.0;
    }
  }

  void _recordAlert(RiskAssessment assessment) {
    final event = RiskEvent(
      level: assessment.level,
      reason: assessment.primaryReason.isNotEmpty
          ? assessment.primaryReason
          : assessment.howExplanation,
      recommendation: assessment.recommendation,
      evidence: List.unmodifiable(assessment.evidenceReasons),
      timestamp: assessment.raisedAt ?? DateTime.now(),
    );
    _recentAlerts.insert(0, event);
    if (_recentAlerts.length > 5) {
      _recentAlerts.removeLast();
    }
  }

  @override
  void dispose() {
    _imuService.stop();
    _positionSubscription?.cancel();
    _evaluationTimer?.cancel();
    _riskAlertService.dispose();
    super.dispose();
  }
}
