import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/tflite_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TFLite Service Initialization and Contract Verification', () async {
    final service = TfliteService();
    
    // Test initialization (verifies model contract and tensor mapping)
    await service.init();

    // Create a dummy image
    final dummyImg = img.Image(width: 320, height: 320);
    final tempFile = File('dummy_test.png');
    await tempFile.writeAsBytes(img.encodePng(dummyImg));

    // Process the dummy static image
    final results = await service.processStaticImage(tempFile.path);
    
    // We expect no high-confidence results from a blank image, 
    // but we expect the parsing logic to succeed without crashing
    expect(results, isNotNull);
    
    // Cleanup
    service.dispose();
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
  });
}
