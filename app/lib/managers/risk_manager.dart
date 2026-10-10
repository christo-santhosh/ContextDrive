import 'dart:async';
import 'dart:math';
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
import '../services/carla_demo_service.dart';
import '../models/risk_event.dart';
import '../models/tracked_object.dart';
import 'object_tracker.dart';

class RiskManager extends ChangeNotifier {
  final GpsService _gpsService;
  final WeatherService _weatherService;
  final TimeContextService _timeContextService;
  final CarlaDemoService _carlaDemoService;
  
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

  // Manual overrides from DebugSettingsSheet
  double? overrideSpeed;
  bool? overrideIsRaining;
  bool? overrideIsNight;
  bool? overrideIsErratic;
  int? overrideSpeedLimit;

  List<TrackedObject> _currentTracks = [];

  DateTime? _elevatedStartTime;
  RiskLevel? _elevatedLevel;
  DateTime? _cooldownEndTime;

  bool _isWeatherAvailable = false;
  DateTime? _weatherLastUpdated;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;
  bool _isStarted = false;

  // Track last CARLA coords to avoid spamming APIs
  double? _lastCarlaLat;
  double? _lastCarlaLon;

  RiskManager(this._gpsService, this._weatherService, this._timeContextService, this._carlaDemoService);

  Future<void> start({required bool locationAvailable}) async {
    if (_isStarted) return;
    _isStarted = true;

    _imuService.start();

    if (locationAvailable) {
      _positionSubscription = _gpsService.getPositionStream().listen((pos) {
        // Ignore real GPS updates if CARLA is actively streaming valid telemetry
        if (_isCarlaActive()) return;

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
      _processCarlaUpdates();
      _evaluateRisk();
    });
  }

  bool _isCarlaActive() {
    return _carlaDemoService.isRunning && 
           _carlaDemoService.latestTelemetry != null && 
           !_carlaDemoService.latestTelemetry!.isStale;
  }

  void _processCarlaUpdates() {
    if (!_isCarlaActive()) return;
    
    final tele = _carlaDemoService.latestTelemetry!;
    
    // Only fetch new external API data if CARLA vehicle moved significantly (e.g. > 100m)
    // For simplicity, checking if it changed at all, but throttling should exist in the services.
    if (_lastCarlaLat != tele.latitude || _lastCarlaLon != tele.longitude) {
      _lastCarlaLat = tele.latitude;
      _lastCarlaLon = tele.longitude;
      
      _timeContextService.updateLocation(tele.latitude, tele.longitude);
      _speedLimitService.updateSpeedLimit(tele.latitude, tele.longitude);
      
      _weatherService.getWeather(tele.latitude, tele.longitude).then((weather) {
        _isRaining = weather.isRaining;
        _visibility = weather.visibilityMeters;
        _isWeatherAvailable = weather.isAvailable;
        _weatherLastUpdated = weather.lastUpdated;
      });
    }
  }

  void updateDetections(List<DetectedObject> detections) {
    _currentTracks = _tracker.updateTracks(detections);
  }

  void setVoiceAlertsEnabled(bool enabled) {
    if (_voiceAlertsEnabled == enabled) return;
    _voiceAlertsEnabled = enabled;
    notifyListeners();
    if (enabled) {
      _riskAlertService.announce(_currentAssessment, enabled: true, force: true);
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
    
    double? speedForRisk;
    String? gpsReason;
    bool isErratic = false;

    if (overrideSpeed != null) {
      speedForRisk = overrideSpeed;
      gpsReason = "Manual Override";
    } else if (_isCarlaActive()) {
      final tele = _carlaDemoService.latestTelemetry!;
      speedForRisk = tele.speedKmh;
      gpsReason = "CARLA Simulation Active";
    } else {
      // Use Real Physical Sensors
      if (_consecutiveInvalidReadings >= 3) {
        speedForRisk = null;
        gpsReason = _latestSpeedReading?.rejectionReason;
      } else if (_lastSpeedTimestamp == null || now.difference(_lastSpeedTimestamp!).inSeconds > 5) {
        speedForRisk = null;
        gpsReason = "Stale GNSS timestamp";
      } else {
        speedForRisk = _currentSpeed;
      }
    }

    if (overrideIsErratic != null) {
      isErratic = overrideIsErratic!;
    } else if (_isCarlaActive()) {
      final tele = _carlaDemoService.latestTelemetry!;
      if (tele.isErratic != null) {
        isErratic = tele.isErratic!;
      } else {
        final horizontalMagnitude = sqrt(tele.accelX * tele.accelX + tele.accelY * tele.accelY);
        isErratic = horizontalMagnitude > 4.5;
      }
    } else {
      isErratic = _imuService.isErratic;
    }

    final isNightCalculated = _timeContextService.isNight(now);
    final isNightEffective = overrideIsNight ?? 
        ((_isCarlaActive() && _carlaDemoService.latestTelemetry!.isNight != null) 
            ? _carlaDemoService.latestTelemetry!.isNight! 
            : isNightCalculated);

    final isRainingEffective = overrideIsRaining ?? 
        ((_isCarlaActive() && _carlaDemoService.latestTelemetry!.isRaining != null) 
            ? _carlaDemoService.latestTelemetry!.isRaining! 
            : _isRaining);

    final speedLimitEffective = overrideSpeedLimit ?? 
        ((_isCarlaActive() && _carlaDemoService.latestTelemetry!.speedLimit != null) 
            ? _carlaDemoService.latestTelemetry!.speedLimit 
            : _speedLimitService.currentSpeedLimit);

    double closestDist = 1.0;
    int nearbyVehiclesCount = 0;
    TrackedObject? closestTrack;
    
    for (var track in _currentTracks) {
      final estimatedDistance = _relativeDistance(track.proximity);
      if (track.type == RoadObjectType.roadVehicle) {
        nearbyVehiclesCount++;
        if (estimatedDistance < closestDist) {
          closestDist = estimatedDistance;
          closestTrack = track;
        }
      }
    }

    bool isClosingIn = closestTrack?.closingRate == ClosingRate.closing;

    bool weatherAvailable = _isWeatherAvailable;
    if (_weatherLastUpdated != null && now.difference(_weatherLastUpdated!).inMinutes > 30) {
      weatherAvailable = false;
    }

    _lastContextVector = ContextVector(
      currentSpeed: speedForRisk,
      currentSpeedLimit: speedLimitEffective,
      isRaining: isRainingEffective,
      isNight: isNightEffective,
      visibility: _visibility,
      isWeatherAvailable: weatherAvailable,
      nearbyVehicles: nearbyVehiclesCount,
      closestVehicleDistance: closestDist,
      isClosingIn: isClosingIn,
      isErraticDriving: isErratic,
      gpsQualityReason: gpsReason,
    );

    final newAssessment = _riskEngine.assessRisk(_lastContextVector);
    
    // Hysteresis & Cooldown Logic based on timestamps
    if (newAssessment.level == RiskLevel.high || newAssessment.level == RiskLevel.moderate) {
      if (_elevatedLevel == newAssessment.level) {
        if (_elevatedStartTime != null && now.difference(_elevatedStartTime!).inMilliseconds > 1000) {
          if (_currentAssessment.level != newAssessment.level) {
            _currentAssessment = newAssessment.copyWith(
              raisedAt: now,
              previousLevel: _currentAssessment.level,
            );
            _recordAlert(_currentAssessment);
            _riskAlertService.announce(_currentAssessment, enabled: _voiceAlertsEnabled);
          } else if (_currentAssessment.primaryReason != newAssessment.primaryReason) {
            _currentAssessment = newAssessment.copyWith(
              raisedAt: _currentAssessment.raisedAt ?? now,
              previousLevel: _currentAssessment.previousLevel,
            );
            _recordAlert(_currentAssessment);
            _riskAlertService.announce(_currentAssessment, enabled: _voiceAlertsEnabled);
          }
          _cooldownEndTime = now.add(const Duration(seconds: 3));
        }
      } else {
        _elevatedLevel = newAssessment.level;
        _elevatedStartTime = now;
      }
    } else {
      _elevatedLevel = null;
      _elevatedStartTime = null;
      
      bool canDropRisk = _cooldownEndTime == null || now.isAfter(_cooldownEndTime!);
      
      if (nearbyVehiclesCount == 0) {
        canDropRisk = true;
        _cooldownEndTime = null;
      }
      
      if (canDropRisk) {
        if (_currentAssessment.level != newAssessment.level || 
            _currentAssessment.howExplanation != newAssessment.howExplanation) {
          _currentAssessment = newAssessment;
          _riskAlertService.clearActiveAlert();
        }
      }
    }
    
    notifyListeners();
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
