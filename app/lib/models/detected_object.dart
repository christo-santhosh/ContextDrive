import 'dart:ui';

class DetectedObject {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final int trackingId;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.trackingId = 0,
  });
}
