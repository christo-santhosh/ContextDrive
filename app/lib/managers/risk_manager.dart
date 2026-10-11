import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../engine/risk_engine.dart';
import '../models/context_vector.dart';
import '../models/detected_object.dart';
import '../models/risk_event.dart';
import '../models/tracked_object.dart';
import '../services/carla_demo_service.dart';
import '../services/gps_service.dart';
import '../services/imu_service.dart';
import '../services/risk_alert_service.dart';
import '../services/speed_limit_service.dart';
import '../services/time_context_service.dart';
import '../services/weather_service.dart';
import 'object_tracker.dart';

/// Visual approach already requires multiple timestamped tracker measurements.
/// Confirmation therefore varies by event instead of stacking a one-second
/// generic debounce on top of frame history and the periodic evaluator.
abstract final class RiskConfirmationPolicy {
  static Duration delayFor(RiskAssessment assessment) {
    switch (assessment.primaryReason) {
      case 'Close closing vehicle during hard braking in adverse conditions':
      case 'Rapid optical approach at close range':
        return const Duration(milliseconds: 150);
      case 'Closing vehicle in adverse conditions':
      case 'Tracked vehicle closing in':
        return const Duration(milliseconds: 250);
      case 'Tracked vehicle is closing in':
        return const Duration(milliseconds: 350);
      default:
        return const Duration(milliseconds: 500);
    }
  }
}

class RiskManager extends ChangeNotifier {
  RiskManager(this._gpsService, this._weatherService, this._timeContextService, this._carlaDemoService) {
    _wasCarlaRunning = _carlaDemoService.isRunning;
    _carlaDemoService.addListener(_onCarlaServiceChanged);
  }

  final GpsService _gpsService;
  final WeatherService _weatherService;
  final TimeContextService _timeContextService;
  final CarlaDemoService _carlaDemoService;
  final ImuService _imuService = ImuService();
  final SpeedLimitService _speedLimitService = SpeedLimitService();
  final RiskAlertService _riskAlertService = RiskAlertService();
  final RiskEngine _riskEngine = RiskEngine();
  final ObjectTracker _tracker = ObjectTracker();

  RiskAssessment _currentAssessment = const RiskAssessment(
    level: RiskLevel.low,
    dataQualityStatus: AssessmentDataQuality.limited,
    whatHappened: 'Initializing assessment inputs.',
    whyExplanation: 'No current assessment is available yet.',
    recommendation: 'Wait for available sensor data before relying on assistance.',
    primaryReason: 'Initializing',
  );
  RiskAssessment get currentAssessment => _currentAssessment;

  ContextVector _lastContextVector = ContextVector(
    currentSpeed: null,
    currentSpeedLimit: null,
    weatherCategory: WeatherCategory.unknown,
    daylightCondition: DaylightCondition.unknown,
    visibilityMeters: null,
    isWeatherAvailable: false,
    nearbyVehicles: 0,
    closestVehicleDistance: 1,
    isClosingIn: false,
    motion: MotionClassification.unknown,
  );
  ContextVector get contextVector => _lastContextVector;

  final List<RiskEvent> _recentAlerts = [];
  List<RiskEvent> get recentAlerts => List.unmodifiable(_recentAlerts);
  bool _voiceAlertsEnabled = true;
  bool get voiceAlertsEnabled => _voiceAlertsEnabled;

  // Debug-only overrides. `overrideIsErratic` is retained as a compatibility
  // switch and maps to a simulated hard-braking event; physical IMU is never
  // used to infer it until the phone mount is calibrated.
  double? overrideSpeed;
  bool? overrideIsRaining;
  bool? overrideIsNight;
  bool? overrideIsErratic;
  int? overrideSpeedLimit;
  int _configuredSpeedLimit = 60;
  int get configuredSpeedLimit => overrideSpeedLimit ?? _configuredSpeedLimit;
  set configuredSpeedLimit(int value) {
    _configuredSpeedLimit = value;
    overrideSpeedLimit = value;
    forceReevaluate();
  }

  void forceReevaluate() {
    _evaluateRisk();
    notifyListeners();
  }

  double? _currentSpeed;
  DateTime? _lastSpeedTimestamp;
  SpeedReading? _latestSpeedReading;
  int _invalidSpeedReadings = 0;
  WeatherCondition? _weather;
  WeatherCondition? get liveWeather => _weather ?? _weatherService.currentWeather;
  Position? _latestPosition;
  Position? get latestPosition => _latestPosition;

  @visibleForTesting
  void setPositionForTesting(Position position) {
    _latestPosition = position;
    notifyListeners();
  }

  @visibleForTesting
  void setWeatherForTesting(WeatherCondition weather) {
    _weather = weather;
    notifyListeners();
  }
  List<TrackedObject> _currentTracks = [];
  DateTime? _lastVisualObservationAt;
  int? _lastVisualSourceFrame;
  int? _lastVisualSequence;
  double? _lastVisualSimulationTime;
  Duration? _lastVisualFrameAge;
  DateTime? _lastRiskEvaluationAt;
  int _lastRiskEvaluationDurationMs = 0;
  Duration? get lastVisualFrameAge => _lastVisualFrameAge;
  int? get lastVisualSourceFrame => _lastVisualSourceFrame;
  int? get lastVisualSequence => _lastVisualSequence;
  double? get lastVisualSimulationTime => _lastVisualSimulationTime;
  DateTime? get lastRiskEvaluationAt => _lastRiskEvaluationAt;
  int get lastRiskEvaluationDurationMs => _lastRiskEvaluationDurationMs;
  List<TrackedObject> get currentTracks => List.unmodifiable(_currentTracks);
  StreamSubscription<Position>? _positionSubscription;
  Timer? _evaluationTimer;
  bool _isStarted = false;
  bool _wasCarlaRunning = false;
  int _sessionToken = 0;

  MotionClassification _motionCandidate = MotionClassification.unknown;
  MotionClassification _stableMotion = MotionClassification.unknown;
  DateTime? _motionCandidateSince;
  RiskLevel? _pendingLevel;
  String? _pendingReason;
  DateTime? _pendingSince;
  DateTime? _cooldownUntil;

  /// Diagnostic-only state. This is intentionally separate from the displayed
  /// assessment: a candidate is not shown as an accepted warning until its
  /// event-specific confirmation interval has completed.
  RiskLevel? get pendingLevel => _pendingLevel;
  String? get pendingReason => _pendingReason;
  bool get isPendingConfirmation =>
      _pendingLevel != null &&
      _pendingReason != null &&
      (_currentAssessment.level != _pendingLevel ||
          _currentAssessment.primaryReason != _pendingReason);
  Duration? get pendingConfirmationRemaining {
    if (!isPendingConfirmation || _pendingSince == null) return null;
    final candidate = RiskAssessment(
      level: _pendingLevel!,
      dataQualityStatus: AssessmentDataQuality.limited,
      whatHappened: '',
      whyExplanation: '',
      recommendation: '',
      primaryReason: _pendingReason!,
    );
    final remaining = RiskConfirmationPolicy.delayFor(candidate) - DateTime.now().difference(_pendingSince!);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _onCarlaServiceChanged() {
    if (_wasCarlaRunning == _carlaDemoService.isRunning) return;
    _wasCarlaRunning = _carlaDemoService.isRunning;
    _sessionToken++;
    _pendingLevel = null;
    _pendingReason = null;
    _pendingSince = null;
    _cooldownUntil = null;
    _resetMotion();
    _tracker.reset();
    _currentTracks = [];
    _lastVisualObservationAt = null;
    _lastVisualSourceFrame = null;
    _lastVisualSequence = null;
    _lastVisualSimulationTime = null;
    _lastVisualFrameAge = null;
    _riskAlertService.clearActiveAlert();
    notifyListeners();
  }

  Future<void> start({required bool locationAvailable}) async {
    if (_isStarted) return;
    _isStarted = true;
    _imuService.start();
    if (locationAvailable) {
      _positionSubscription = _gpsService.getPositionStream().listen(_onPosition);
    }
    _evaluationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _evaluateRisk());
  }

  Future<WeatherCondition?> refreshLiveWeather() async {
    Position? pos = _latestPosition;
    if (pos == null) {
      try {
        pos = await Geolocator.getLastKnownPosition();
        pos ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(timeLimit: Duration(seconds: 4)),
        );
        _latestPosition = pos;
      } catch (e) {
        debugPrint('Geolocator exception in refreshLiveWeather: $e');
      }
    }
    if (pos != null) {
      final weather = await _weatherService.getWeather(
        pos.latitude,
        pos.longitude,
        forceRefresh: true,
      );
      _weather = weather;
      _timeContextService.updateLocation(pos.latitude, pos.longitude);
      _speedLimitService.updateSpeedLimit(pos.latitude, pos.longitude);
      notifyListeners();
      return weather;
    }
    return null;
  }

  void _onPosition(Position position) {
    if (_carlaDemoService.isRunning) return;
    _latestPosition = position;
    final session = _sessionToken;
    final reading = _gpsService.processPosition(position);
    _latestSpeedReading = reading;
    if (reading.isValid) {
      _currentSpeed = reading.valueKmh;
      _lastSpeedTimestamp = reading.timestamp;
      _invalidSpeedReadings = 0;
    } else {
      _invalidSpeedReadings++;
    }
    _timeContextService.updateLocation(position.latitude, position.longitude);
    _speedLimitService.updateSpeedLimit(position.latitude, position.longitude);
    _weatherService.getWeather(position.latitude, position.longitude).then((weather) {
      if (session != _sessionToken || _carlaDemoService.isRunning) return;
      _weather = weather;
      notifyListeners();
    });
    notifyListeners();
  }

  void updateDetections(
    List<DetectedObject> detections, {
    DateTime? observationTime,
    int? sourceFrame,
    int? sequenceNumber,
    double? simulationTime,
    Duration? frameAge,
  }) {
    final now = observationTime ?? DateTime.now();
    _currentTracks = _tracker.updateTracks(detections, observationTime: now);
    _lastVisualObservationAt = now;
    _lastVisualSourceFrame = sourceFrame;
    _lastVisualSequence = sequenceNumber;
    _lastVisualSimulationTime = simulationTime;
    _lastVisualFrameAge = frameAge;
    // Do not wait for the 500 ms periodic tick after a fresh YOLO result.
    _evaluateRisk();
    notifyListeners();
  }

  void markVisualInputStale() {
    if (_lastVisualObservationAt == null && _currentTracks.isEmpty) return;
    _lastVisualObservationAt = null;
    _lastVisualSourceFrame = null;
    _lastVisualSequence = null;
    _lastVisualFrameAge = null;
    _lastVisualSimulationTime = null;
    _tracker.reset();
    _currentTracks = [];
    _evaluateRisk();
    notifyListeners();
  }

  void resetTracking() {
    _tracker.reset();
    _currentTracks = [];
    _lastVisualObservationAt = null;
    _lastVisualSourceFrame = null;
    _lastVisualSequence = null;
    _lastVisualFrameAge = null;
    _lastVisualSimulationTime = null;
    notifyListeners();
  }

  void setVoiceAlertsEnabled(bool enabled) {
    if (_voiceAlertsEnabled == enabled) return;
    _voiceAlertsEnabled = enabled;
    if (enabled && _currentAssessment.hasHazard && !_currentAssessment.isStale) {
      _riskAlertService.announce(_currentAssessment, enabled: true, force: true);
    } else if (!enabled) {
      _riskAlertService.stop();
    }
    notifyListeners();
  }

  void clearRecentAlerts() {
    if (_recentAlerts.isEmpty) return;
    _recentAlerts.clear();
    notifyListeners();
  }

  void _evaluateRisk() {
    final now = DateTime.now();
    _lastRiskEvaluationAt = now;
    _tracker.expireStale(now);
    _currentTracks = _currentTracks
        .where((track) => now.difference(track.lastSeen) <= ObjectTracker.maxTrackAge)
        .toList();
    if (_carlaDemoService.isRunning && !_carlaDemoService.isCarlaActive) {
      _setStaleCarlaAssessment();
      return;
    }
    if (_carlaDemoService.isCarlaActive &&
        (_carlaDemoService.latestTelemetry == null ||
            _carlaDemoService.latestTelemetry!.isStale)) {
      _setStaleCarlaAssessment();
      return;
    }
    final trackState = _trackState();
    final context = _carlaDemoService.isCarlaActive
        ? _carlaContext(now, trackState)
        : _physicalContext(now, trackState);
    _lastContextVector = context;
    final engineTimer = Stopwatch()..start();
    final assessment = _riskEngine.assessRisk(context);
    engineTimer.stop();
    _lastRiskEvaluationDurationMs = engineTimer.elapsedMicroseconds ~/ 1000;
    _applyAssessment(assessment, now);
  }

  ({int vehicles, double closest, bool closing, bool developing, double? area, double? growth, bool fresh}) _trackState() {
    var closest = 1.0;
    TrackedObject? closestTrack;
    TrackedObject? developingTrack;
    var vehicles = 0;
    for (final track in _currentTracks) {
      if (track.type != RoadObjectType.roadVehicle) continue;
      vehicles++;
      final visualProxy = _visualProxy(track.proximity);
      if (visualProxy < closest) {
        closest = visualProxy;
        closestTrack = track;
      }
      if (track.isDevelopingApproach &&
          (developingTrack == null || track.area > developingTrack.area)) {
        developingTrack = track;
      }
    }
    final visualFresh = _lastVisualObservationAt != null &&
        DateTime.now().difference(_lastVisualObservationAt!) <= ObjectTracker.maxTrackAge;
    final trendTrack = developingTrack ?? closestTrack;
    return (
      vehicles: vehicles,
      closest: closest,
      closing: closestTrack?.closingRate == ClosingRate.closing,
      developing: developingTrack != null,
      area: trendTrack?.area,
      growth: trendTrack?.growthPerSecond,
      fresh: visualFresh,
    );
  }

  ContextVector _physicalContext(DateTime now, ({int vehicles, double closest, bool closing, bool developing, double? area, double? growth, bool fresh}) tracks) {
    final staleSpeed = _lastSpeedTimestamp == null || now.difference(_lastSpeedTimestamp!).inSeconds > 5;
    final speed = overrideSpeed ?? ((_invalidSpeedReadings >= 3 || staleSpeed) ? null : _currentSpeed);
    final time = overrideIsNight == null
        ? _timeContextService.daylightCondition(now)
        : (overrideIsNight! ? DaylightCondition.night : DaylightCondition.day);
    final weather = overrideIsRaining == null
        ? _weather?.category ?? WeatherCategory.unknown
        : (overrideIsRaining! ? WeatherCategory.rain : WeatherCategory.clear);
    // IMU directional classification is deliberately unavailable until phone
    // mount orientation/calibration is implemented.
    final motion = overrideIsErratic == true ? MotionClassification.hardBraking : MotionClassification.unknown;
    return ContextVector(
      currentSpeed: speed,
      currentSpeedLimit: overrideSpeedLimit ?? _configuredSpeedLimit,
      weatherCategory: weather,
      daylightCondition: time,
      visibilityMeters: _weather?.visibilityMeters,
      isWeatherAvailable: overrideIsRaining != null || (_weather?.isAvailable ?? false),
      nearbyVehicles: tracks.vehicles,
      closestVehicleDistance: tracks.closest,
      isClosingIn: tracks.closing,
      isVisualApproachDeveloping: tracks.developing,
      closestVehicleArea: tracks.area,
      visualGrowthPerSecond: tracks.growth,
      visualDataFresh: tracks.fresh,
      motion: motion,
      telemetryFresh: true,
      speedQualityReason: speed == null ? (_latestSpeedReading?.rejectionReason ?? (staleSpeed ? 'Stale GNSS timestamp' : 'Speed unavailable')) : null,
      weatherQualityReason: _weather?.isAvailable == true ? null : (_weatherService.lastError ?? 'Weather unavailable'),
      timeQualityReason: time == DaylightCondition.unknown ? 'Location-derived day/night context unavailable' : null,
    );
  }

  ContextVector _carlaContext(DateTime now, ({int vehicles, double closest, bool closing, bool developing, double? area, double? growth, bool fresh}) tracks) {
    final telemetry = _carlaDemoService.latestTelemetry!;
    final weather = overrideIsRaining == null
        ? (telemetry.isRaining == null
            ? WeatherCategory.unknown
            : telemetry.isRaining!
                ? WeatherCategory.rain
                : WeatherCategory.clear)
        : (overrideIsRaining! ? WeatherCategory.rain : WeatherCategory.clear);
    final day = overrideIsNight == null
        ? (telemetry.isNight == null ? DaylightCondition.unknown : telemetry.isNight! ? DaylightCondition.night : DaylightCondition.day)
        : (overrideIsNight! ? DaylightCondition.night : DaylightCondition.day);
    final rawMotion = overrideIsErratic == true
        ? MotionClassification.hardBraking
        : MotionClassifier.classify(speedKmh: telemetry.speedKmh, longitudinalAcceleration: telemetry.longitudinalAcceleration);
    final motion = _persistMotion(rawMotion, now);
    return ContextVector(
      currentSpeed: overrideSpeed ?? telemetry.speedKmh,
      currentSpeedLimit: overrideSpeedLimit ?? telemetry.speedLimit ?? _configuredSpeedLimit,
      weatherCategory: weather,
      daylightCondition: day,
      visibilityMeters: _carlaVisibilityMetres(telemetry.visibilityCategory),
      isWeatherAvailable: telemetry.isRaining != null || telemetry.visibilityCategory != null || overrideIsRaining != null,
      visibilityAssessment: _carlaVisibility(telemetry.visibilityCategory, weather, day),
      nearbyVehicles: tracks.vehicles,
      closestVehicleDistance: tracks.closest,
      isClosingIn: tracks.closing,
      isVisualApproachDeveloping: tracks.developing,
      closestVehicleArea: tracks.area,
      visualGrowthPerSecond: tracks.growth,
      visualDataFresh: tracks.fresh,
      motion: motion,
      longitudinalAcceleration: telemetry.longitudinalAcceleration,
      telemetryFresh: !telemetry.isStale,
      weatherQualityReason: 'CARLA scenario weather unavailable',
      timeQualityReason: 'CARLA scenario day/night unavailable',
    );
  }

  VisibilityAssessment _carlaVisibility(String? category, WeatherCategory weather, DaylightCondition day) {
    final normalized = category?.toLowerCase();
    if (normalized == 'poor' || normalized == 'foggy' || normalized == 'heavy_rain') return VisibilityAssessment.poor;
    if (normalized == 'adequate' || normalized == 'clear') return VisibilityAssessment.adequate;
    return ContextVector.calculateVisibility(weatherCategory: weather, daylightCondition: day, visibilityMeters: null, isWeatherAvailable: false);
  }

  int? _carlaVisibilityMetres(String? category) => category?.toLowerCase() == 'poor' ? 500 : null;

  MotionClassification _persistMotion(MotionClassification candidate, DateTime now) {
    if (candidate == MotionClassification.unknown || candidate == MotionClassification.normal) {
      _resetMotion();
      return candidate;
    }
    if (_motionCandidate != candidate) {
      _motionCandidate = candidate;
      _motionCandidateSince = now;
      _stableMotion = MotionClassification.unknown;
      return _stableMotion;
    }
    if (_motionCandidateSince != null && now.difference(_motionCandidateSince!).inMilliseconds >= 350) {
      _stableMotion = candidate;
    }
    return _stableMotion;
  }

  void _resetMotion() {
    _motionCandidate = MotionClassification.unknown;
    _stableMotion = MotionClassification.unknown;
    _motionCandidateSince = null;
  }

  void _applyAssessment(RiskAssessment next, DateTime now) {
    if (!next.hasHazard) {
      _pendingLevel = null;
      _pendingReason = null;
      _pendingSince = null;
      if (_cooldownUntil == null || now.isAfter(_cooldownUntil!)) {
        _currentAssessment = next;
        _riskAlertService.clearActiveAlert();
      }
      notifyListeners();
      return;
    }
    if (_pendingLevel != next.level || _pendingReason != next.primaryReason) {
      _pendingLevel = next.level;
      _pendingReason = next.primaryReason;
      _pendingSince = now;
      notifyListeners();
      return;
    }
    if (_pendingSince != null &&
        now.difference(_pendingSince!) >= RiskConfirmationPolicy.delayFor(next)) {
      final changed = _currentAssessment.level != next.level || _currentAssessment.primaryReason != next.primaryReason;
      _currentAssessment = next.copyWith(raisedAt: changed ? now : _currentAssessment.raisedAt, previousLevel: changed ? _currentAssessment.level : _currentAssessment.previousLevel);
      _cooldownUntil = now.add(const Duration(seconds: 3));
      if (changed) {
        _recordAlert(_currentAssessment);
        _riskAlertService.announce(_currentAssessment, enabled: _voiceAlertsEnabled);
      }
    }
    notifyListeners();
  }

  void _setStaleCarlaAssessment() {
    _lastContextVector = ContextVector(
      currentSpeed: null, currentSpeedLimit: null, weatherCategory: WeatherCategory.unknown,
      daylightCondition: DaylightCondition.unknown, visibilityMeters: null, isWeatherAvailable: false,
      nearbyVehicles: 0, closestVehicleDistance: 1, isClosingIn: false,
      motion: MotionClassification.unknown, telemetryFresh: false,
      visualDataFresh: false,
      speedQualityReason: 'CARLA telemetry unavailable',
    );
    _currentAssessment = const RiskAssessment(
      level: RiskLevel.low,
      dataQualityStatus: AssessmentDataQuality.stale,
      whatHappened: 'CARLA telemetry is paused or disconnected.',
      whyExplanation: 'Assistance cannot evaluate new hazards from stale simulation data.',
      recommendation: 'Verify the CARLA simulation and telemetry connection before relying on assistance.',
      primaryReason: 'CARLA telemetry unavailable',
      isStale: true,
      dataQuality: ['CARLA telemetry unavailable'],
    );
    _pendingLevel = null;
    _pendingReason = null;
    _pendingSince = null;
    _riskAlertService.clearActiveAlert();
    notifyListeners();
  }

  double _visualProxy(ProximityCategory proximity) => switch (proximity) {
    ProximityCategory.veryNear => 0.1,
    ProximityCategory.near => 0.3,
    ProximityCategory.medium => 0.6,
    ProximityCategory.far || ProximityCategory.unknown => 1.0,
  };

  void _recordAlert(RiskAssessment assessment) {
    _recentAlerts.insert(0, RiskEvent(
      level: assessment.level,
      reason: assessment.primaryReason,
      recommendation: assessment.recommendation,
      evidence: List.unmodifiable(assessment.evidenceReasons),
      timestamp: assessment.raisedAt ?? DateTime.now(),
    ));
    if (_recentAlerts.length > 5) _recentAlerts.removeLast();
  }

  @override
  void dispose() {
    _carlaDemoService.removeListener(_onCarlaServiceChanged);
    _imuService.stop();
    _positionSubscription?.cancel();
    _evaluationTimer?.cancel();
    _riskAlertService.dispose();
    super.dispose();
  }
}
