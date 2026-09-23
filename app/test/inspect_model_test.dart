import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
void main() {
  testWidgets('Inspect model', (WidgetTester tester) async {
    final interpreter = await Interpreter.fromAsset('assets/detect.tflite');
    print('Outputs:');
    for (var i = 0; i < interpreter.getOutputTensors().length; i++) {
      final t = interpreter.getOutputTensor(i);
      print('Index $i: ${t.name} shape ${t.shape} type ${t.type}');
    }
  });
}
