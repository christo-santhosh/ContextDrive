import 'dart:ui';

import 'detected_object.dart';

enum ProximityCategory { far, medium, near, veryNear, unknown }
enum ClosingRate { closing, stable, separating, unknown }

class TrackedObject {
  static const double mediumAreaThreshold = 0.05;
  static const double nearAreaThreshold = 0.15;
  static const double veryNearAreaThreshold = 0.40;
  static const double approachAreaThreshold = 0.025;
  static const double closingGrowthPerSecond = 0.15;

  final int trackId;
  final RoadObjectType type;
  final String label;
  Rect smoothedBox;
  double confidence;
  DateTime lastSeen;
  int framesMissed = 0;
  final List<({DateTime time, double area})> areaHistory = [];
  ProximityCategory proximity = ProximityCategory.unknown;
  ClosingRate closingRate = ClosingRate.unknown;
  double? growthPerSecond;

  TrackedObject({
    required this.trackId,
    required this.type,
    required this.label,
    required this.smoothedBox,
    required this.confidence,
    required this.lastSeen,
  }) {
    _recordMeasurement(lastSeen);
  }

  double get area => smoothedBox.width * smoothedBox.height;
  bool get hasSufficientHistory => areaHistory.length >= 3 && growthPerSecond != null;
  bool get isDevelopingApproach =>
      hasSufficientHistory &&
      area >= approachAreaThreshold &&
      growthPerSecond! > closingGrowthPerSecond &&
      closingRate == ClosingRate.closing;

  void updateWithDetection(DetectedObject detection, DateTime now) {
    confidence = detection.confidence;
    lastSeen = now;
    framesMissed = 0;
    // Keep enough smoothing to reject one-frame jitter but respond faster than
    // the previous alpha=0.3 value during a genuine visual approach.
    const alpha = 0.45;
    smoothedBox = Rect.fromLTRB(
      smoothedBox.left * (1 - alpha) + detection.boundingBox.left * alpha,
      smoothedBox.top * (1 - alpha) + detection.boundingBox.top * alpha,
      smoothedBox.right * (1 - alpha) + detection.boundingBox.right * alpha,
      smoothedBox.bottom * (1 - alpha) + detection.boundingBox.bottom * alpha,
    );
    _recordMeasurement(now);
  }

  void _recordMeasurement(DateTime now) {
    areaHistory.add((time: now, area: area));
    areaHistory.removeWhere((entry) => now.difference(entry.time).inMilliseconds > 1500);
    _updateProximity();
    _updateClosingRate();
  }

  void _updateProximity() {
    if (area > veryNearAreaThreshold) {
      proximity = ProximityCategory.veryNear;
    } else if (area > nearAreaThreshold) {
      proximity = ProximityCategory.near;
    } else if (area > mediumAreaThreshold) {
      proximity = ProximityCategory.medium;
    } else {
      proximity = ProximityCategory.far;
    }
  }

  void _updateClosingRate() {
    growthPerSecond = null;
    if (areaHistory.length < 3) {
      closingRate = ClosingRate.unknown;
      return;
    }
    final first = areaHistory.first;
    final last = areaHistory.last;
    final seconds = last.time.difference(first.time).inMilliseconds / 1000.0;
    if (seconds < 0.20 || first.area <= 0) {
      closingRate = ClosingRate.unknown;
      return;
    }
    growthPerSecond = (last.area / first.area - 1.0) / seconds;
    final recent = areaHistory.sublist(areaHistory.length - 3);
    final consistentlyGrowing =
        recent[1].area > recent[0].area * 1.01 &&
        recent[2].area > recent[1].area * 1.01;
    final consistentlyShrinking =
        recent[1].area < recent[0].area * 0.99 &&
        recent[2].area < recent[1].area * 0.99;
    if (growthPerSecond! > closingGrowthPerSecond && consistentlyGrowing) {
      closingRate = ClosingRate.closing;
    } else if (growthPerSecond! < -closingGrowthPerSecond && consistentlyShrinking) {
      closingRate = ClosingRate.separating;
    } else {
      closingRate = ClosingRate.stable;
    }
  }
}
