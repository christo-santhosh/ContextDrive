import 'context_vector.dart';

/// A short in-memory record of an elevated-risk decision for the session.
/// It is deliberately not persisted or uploaded in this MVP.
class RiskEvent {
  const RiskEvent({
    required this.level,
    required this.reason,
    required this.recommendation,
    required this.evidence,
    required this.timestamp,
  });

  final RiskLevel level;
  final String reason;
  final String recommendation;
  final List<String> evidence;
  final DateTime timestamp;
}
