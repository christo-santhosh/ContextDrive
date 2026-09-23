import 'dart:ui';

enum RoadObjectType {
  roadVehicle,
  vulnerableRoadUser,
  ignored,
}

class DetectedObject {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final int trackingId;
  final RoadObjectType type;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.trackingId = 0,
    required this.type,
  });
}
