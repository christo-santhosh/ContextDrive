import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/context_vector.dart';

/// Speaks only meaningful risk changes. The cooldown prevents a noisy camera
/// stream from repeating the same warning on every evaluation cycle.
class RiskAlertService {
  static const MethodChannel _channel = MethodChannel('contextdrive/voice_alerts');
  DateTime? _lastAnnouncementAt;
  RiskLevel? _lastAnnouncedLevel;
  String? _lastAnnouncedReason;

  Future<void> announce(
    RiskAssessment assessment, {
    required bool enabled,
    bool force = false,
  }) async {
    if (!enabled ||
        (!assessment.hasHazard || assessment.isStale)) {
      return;
    }

    final now = DateTime.now();
    final reason = assessment.primaryReason.isNotEmpty
        ? assessment.primaryReason
        : assessment.howExplanation;
    final isEscalation = _lastAnnouncedLevel == null ||
        _severity(assessment.level) > _severity(_lastAnnouncedLevel!);
    final reasonChanged = reason != _lastAnnouncedReason;
    final cooldown = (assessment.level == RiskLevel.high ||
            assessment.level == RiskLevel.critical)
        ? const Duration(seconds: 6)
        : const Duration(seconds: 12);
    final recentlyAnnounced = _lastAnnouncementAt != null &&
        now.difference(_lastAnnouncementAt!) < cooldown;

    if (!force && recentlyAnnounced && !isEscalation && !reasonChanged) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('speak', {
        'message': _voiceMessage(assessment),
      });
      _lastAnnouncementAt = now;
      _lastAnnouncedLevel = assessment.level;
      _lastAnnouncedReason = reason;
    } catch (error) {
      // A missing or disabled system TTS engine must never stop the driving UI.
      debugPrint('Voice alert unavailable: $error');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Unable to stop voice alert: $error');
    }
  }

  void clearActiveAlert() {
    _lastAnnouncedLevel = null;
    _lastAnnouncedReason = null;
  }

  Future<void> dispose() => stop();

  int _severity(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return 0;
      case RiskLevel.moderate:
        return 1;
      case RiskLevel.high:
        return 2;
      case RiskLevel.critical:
        return 3;
    }
  }

  String _voiceMessage(RiskAssessment assessment) {
    final prefix = assessment.level == RiskLevel.critical
        ? 'Critical warning.'
        : assessment.level == RiskLevel.high
            ? 'High risk.'
            : 'Caution.';
    return '$prefix ${assessment.howExplanation} ${assessment.recommendation}';
  }
}
