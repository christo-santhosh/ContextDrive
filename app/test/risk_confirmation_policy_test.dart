import 'package:app/managers/risk_manager.dart';
import 'package:app/models/context_vector.dart';
import 'package:flutter_test/flutter_test.dart';

RiskAssessment candidate(String reason, RiskLevel level) => RiskAssessment(
      level: level,
      dataQualityStatus: AssessmentDataQuality.good,
      whatHappened: '',
      whyExplanation: '',
      recommendation: '',
      primaryReason: reason,
    );

void main() {
  test('visual approach confirmation is event-specific instead of the old generic second', () {
    expect(
      RiskConfirmationPolicy.delayFor(candidate('Tracked vehicle is closing in', RiskLevel.moderate)),
      const Duration(milliseconds: 350),
    );
    expect(
      RiskConfirmationPolicy.delayFor(candidate('Rapid optical approach at close range', RiskLevel.high)),
      const Duration(milliseconds: 150),
    );
    expect(
      RiskConfirmationPolicy.delayFor(candidate('Speed limit exceeded', RiskLevel.moderate)),
      const Duration(milliseconds: 500),
    );
  });
}
