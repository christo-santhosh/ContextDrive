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

  test('voice speaks only the advice recommendation and not the whole alert', () async {
    final spokenMessages = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('contextdrive/voice_alerts'),
      (call) async {
        if (call.method == 'speak') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          spokenMessages.add(args?['message'] as String);
        }
        return null;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('contextdrive/voice_alerts'), null));

    final service = RiskAlertService();
    await service.announce(
      const RiskAssessment(
        level: RiskLevel.critical,
        dataQualityStatus: AssessmentDataQuality.good,
        whatHappened: 'Strong deceleration was detected while a tracked vehicle was closing in.',
        whyExplanation: 'The forward visual buffer is reducing while braking.',
        recommendation: 'Brake smoothly and increase following distance.',
        primaryReason: 'Close closing vehicle during hard braking',
      ),
      enabled: true,
    );

    expect(spokenMessages, ['Brake smoothly and increase following distance.']);
  });
}
