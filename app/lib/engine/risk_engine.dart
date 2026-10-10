import '../models/context_vector.dart';

class _Candidate {
  const _Candidate({required this.severity, required this.name, required this.what, required this.why, required this.action, required this.evidence});
  final RiskLevel severity;
  final String name;
  final String what;
  final String why;
  final String action;
  final List<String> evidence;
}

/// Deterministic, explainable rule engine. It evaluates all applicable rules,
/// selects the highest severity for the HUD, and keeps availability separate.
class RiskEngine {
  RiskAssessment assessRisk(ContextVector context) {
    final quality = <String>[];
    final modifiers = <String>[];
    final advisories = <String>[];
    final candidates = <_Candidate>[];
    final hasSpeed = context.currentSpeed != null;

    if (!context.telemetryFresh) quality.add('Telemetry is stale or disconnected');
    if (hasSpeed) {
      quality.add('Speed current');
      modifiers.add('Speed ${context.currentSpeed!.toStringAsFixed(0)} km/h');
    } else {
      quality.add(context.speedQualityReason ?? 'Speed unavailable');
    }
    if (context.isWeatherAvailable) {
      quality.add('Weather current');
    } else {
      quality.add(context.weatherQualityReason ?? 'Weather unavailable');
    }
    if (context.daylightCondition == DaylightCondition.unknown) {
      quality.add(context.timeQualityReason ?? 'Time-of-day context unavailable');
    }

    final poorVisibility = context.visibilityAssessment == VisibilityAssessment.poor;
    final adverse = poorVisibility || context.isRaining || context.daylightCondition == DaylightCondition.night;
    switch (context.weatherCategory) {
      case WeatherCategory.rain:
        modifiers.add('Rain reported for the current area');
        advisories.add('Rain is reported for the current area. Wet-road grip may be reduced; drive smoothly and allow more stopping distance.');
        break;
      case WeatherCategory.heavyRain:
        modifiers.add('Heavy rain reported for the current area');
        advisories.add('Heavy rain or poor visibility is indicated. Reduce speed and increase following distance. If the journey is not essential, consider delaying travel until conditions improve.');
        break;
      case WeatherCategory.fog:
        modifiers.add('Fog or poor visibility reported');
        advisories.add('Poor visibility is reported. Reduce speed and increase following distance.');
        break;
      case WeatherCategory.clear:
      case WeatherCategory.unknown:
        break;
    }
    if (context.daylightCondition == DaylightCondition.night) {
      modifiers.add('Night conditions');
      advisories.add('Night driving conditions. Visibility can be reduced; reduce speed as needed and leave additional following distance.');
    } else if (context.daylightCondition == DaylightCondition.dawnDusk) {
      modifiers.add('Dawn/dusk conditions');
      advisories.add('Dawn or dusk conditions can reduce contrast. Drive at a speed appropriate for visibility.');
    }
    if (context.visibilityAssessment == VisibilityAssessment.unknown) modifiers.add('Visibility conditions unknown');

    final veryNear = context.nearbyVehicles > 0 && context.closestVehicleDistance <= RiskThresholds.veryNearVisualProxy;
    final near = context.nearbyVehicles > 0 && context.closestVehicleDistance <= RiskThresholds.nearVisualProxy;
    final excess = hasSpeed && context.currentSpeedLimit != null ? context.currentSpeed! - context.currentSpeedLimit! : null;
    final speeding = excess != null && excess > RiskThresholds.speedLimitModerateExcessKmh;
    final significantSpeeding = excess != null && excess > RiskThresholds.speedLimitHighExcessKmh;

    // Critical is intentionally narrow: three independent observed inputs and
    // adverse context. It does not claim a collision probability.
    if (veryNear && context.isClosingIn && context.motion == MotionClassification.hardBraking && adverse) {
      candidates.add(const _Candidate(
        severity: RiskLevel.critical,
        name: 'Close closing vehicle during hard braking in adverse conditions',
        what: 'Strong deceleration was detected while a visually very close vehicle was closing in under adverse conditions.',
        why: 'The forward visual buffer is reducing while braking and visibility or weather conditions may reduce the available margin.',
        action: 'Focus on the road ahead, brake smoothly if safe, and increase following distance.',
        evidence: ['Hard braking', 'Very close tracked vehicle', 'Closing visual track', 'Adverse environmental context'],
      ));
    }
    if (veryNear && context.isClosingIn) {
      candidates.add(const _Candidate(
        severity: RiskLevel.high,
        name: 'Rapid optical approach at close range',
        what: 'A visually very close tracked vehicle is growing in view.',
        why: 'The forward visual buffer appears minimal and is reducing.',
        action: 'Increase following distance immediately when safe.',
        evidence: ['Very close tracked vehicle', 'Bounding-area growth indicates closing'],
      ));
    }
    if (context.motion == MotionClassification.hardBraking) {
      candidates.add(_Candidate(
        severity: near ? RiskLevel.high : RiskLevel.moderate,
        name: near ? 'Hard braking near tracked traffic' : 'Hard braking',
        what: near ? 'Strong deceleration was detected while a tracked vehicle is visually close.' : 'Strong deceleration was detected.',
        why: near ? 'Abrupt braking with limited visual headway reduces the available traffic margin.' : 'Strong deceleration can reduce vehicle stability and indicates a sudden change in driving conditions.',
        action: near ? 'Maintain control, reassess traffic ahead, and increase clearance when safe.' : 'Maintain control and reassess the traffic ahead.',
        evidence: ['Signed longitudinal acceleration ${context.longitudinalAcceleration?.toStringAsFixed(1) ?? 'available'} m/s²', if (near) 'Tracked vehicle within visual proximity threshold'],
      ));
    }
    if (context.motion == MotionClassification.rapidAcceleration) {
      final elevated = speeding || poorVisibility;
      candidates.add(_Candidate(
        severity: elevated ? RiskLevel.high : RiskLevel.moderate,
        name: elevated ? 'Rapid acceleration with speed or visibility context' : 'Rapid acceleration',
        what: 'Strong forward acceleration was detected${speeding ? ' while above the configured speed limit' : poorVisibility ? ' under poor visibility' : ''}.',
        why: elevated ? 'Rapid acceleration combined with speed or visibility context reduces the available response margin.' : 'Strong acceleration can quickly increase speed and reduce the time available to respond.',
        action: elevated ? 'Ease off the throttle, check your speed, and leave additional space.' : 'Apply smoother throttle input and check your speed against the applicable limit.',
        evidence: ['Signed longitudinal acceleration ${context.longitudinalAcceleration?.toStringAsFixed(1) ?? 'available'} m/s²', if (speeding) 'Speed exceeds configured limit by more than 10 km/h', if (poorVisibility) 'Poor visibility context active'],
      ));
    }
    if (near && context.isClosingIn) {
      candidates.add(_Candidate(
        severity: adverse ? RiskLevel.high : RiskLevel.moderate,
        name: adverse ? 'Closing vehicle in adverse conditions' : 'Tracked vehicle closing in',
        what: 'A visually close tracked vehicle is growing in view.',
        why: adverse ? 'The forward visual buffer is reducing while weather, darkness, or visibility may reduce the available margin.' : 'The forward visual headway appears to be diminishing.',
        action: 'Monitor the road ahead and increase following distance.',
        evidence: ['Tracked vehicle within visual proximity threshold', 'Bounding-area growth indicates closing'],
      ));
    } else if (veryNear) {
      candidates.add(const _Candidate(
        severity: RiskLevel.moderate,
        name: 'Very close tracked vehicle',
        what: 'A detected vehicle exceeds the configured visual-proximity threshold.',
        why: 'The current visual headway appears compact.',
        action: 'Increase following distance when safe.',
        evidence: ['Tracked vehicle within very-close visual proximity threshold'],
      ));
    }
    if (hasSpeed && poorVisibility && context.currentSpeed! > RiskThresholds.highSpeedPoorVisibilityKmh) {
      candidates.add(const _Candidate(
        severity: RiskLevel.moderate,
        name: 'High speed in poor visibility',
        what: 'Speed exceeds 80 km/h while poor visibility is indicated.',
        why: 'Reduced visibility can reduce the time available to identify and respond to hazards.',
        action: 'Reduce speed to match visibility conditions.',
        evidence: ['Speed exceeds 80 km/h', 'Poor visibility context active'],
      ));
    }
    if (speeding) {
      final severe = significantSpeeding && adverse;
      candidates.add(_Candidate(
        severity: severe ? RiskLevel.high : RiskLevel.moderate,
        name: severe ? 'Significant speeding in adverse conditions' : 'Speed limit exceeded',
        what: 'Speed is ${context.currentSpeed!.toStringAsFixed(0)} km/h against a configured ${context.currentSpeedLimit} km/h limit${context.isRaining ? ' while rain is reported' : ''}.',
        why: severe ? 'A significant speed-limit excess combined with adverse conditions reduces the available response margin.' : 'Traveling above the configured road speed limit reduces the available response margin.',
        action: 'Reduce speed to ${context.currentSpeedLimit} km/h and allow additional following distance.',
        evidence: ['Speed exceeds configured limit by ${excess.toStringAsFixed(0)} km/h'],
      ));
    }

    candidates.sort((a, b) => _severity(b.severity).compareTo(_severity(a.severity)));
    final dataStatus = !context.telemetryFresh
        ? AssessmentDataQuality.stale
        : (!hasSpeed ||
                !context.isWeatherAvailable ||
                context.visibilityAssessment == VisibilityAssessment.unknown ||
                context.daylightCondition == DaylightCondition.unknown)
            ? AssessmentDataQuality.limited
            : AssessmentDataQuality.good;
    if (candidates.isEmpty) {
      final limited = dataStatus != AssessmentDataQuality.good;
      return RiskAssessment(
        level: RiskLevel.low,
        dataQualityStatus: dataStatus,
        whatHappened: limited ? 'No configured hazard rule is currently triggered, but some inputs are limited.' : 'No configured risk rule is currently triggered by the available inputs.',
        whyExplanation: limited ? 'This is not an all-clear: unavailable or stale inputs limit the assessment.' : 'The available inputs do not meet any configured hazard rule.',
        recommendation: limited ? 'Drive with caution while assistance inputs are limited.' : 'Continue driving safely.',
        primaryReason: limited ? 'Limited assessment data' : 'No configured risk rule triggered',
        contextModifiers: modifiers,
        dataQuality: quality,
        advisories: advisories,
      );
    }
    final primary = candidates.first;
    return RiskAssessment(
      level: primary.severity,
      dataQualityStatus: dataStatus,
      whatHappened: primary.what,
      whyExplanation: primary.why,
      recommendation: primary.action,
      primaryReason: primary.name,
      evidenceReasons: candidates.expand((candidate) => candidate.evidence).toSet().toList(),
      contextModifiers: modifiers,
      dataQuality: quality,
      advisories: advisories,
      activeEvents: candidates.map((candidate) => candidate.name).toList(),
    );
  }

  int _severity(RiskLevel level) => switch (level) {
    RiskLevel.low => 0,
    RiskLevel.moderate => 1,
    RiskLevel.high => 2,
    RiskLevel.critical => 3,
  };
}
