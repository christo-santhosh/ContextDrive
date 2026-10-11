import 'package:app/models/context_vector.dart';
import 'package:app/services/risk_alert_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

RiskAssessment assessment(RiskLevel level, String reason) => RiskAssessment(
      level: level,
      dataQualityStatus: AssessmentDataQuality.good,
      whatHappened: reason,
      whyExplanation: '',
      recommendation: 'Respond safely.',
      primaryReason: reason,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice cooldown does not suppress a more severe escalation', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('contextdrive/voice_alerts'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('contextdrive/voice_alerts'), null));

    final service = RiskAlertService();
    await service.announce(assessment(RiskLevel.moderate, 'Tracked vehicle is closing in'), enabled: true);
    await service.announce(assessment(RiskLevel.high, 'Rapid optical approach at close range'), enabled: true);

    expect(calls, ['speak', 'speak']);
  });
}
