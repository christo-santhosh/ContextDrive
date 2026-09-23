import 'dart:ui';
import 'detected_object.dart';

enum ProximityCategory { far, medium, near, veryNear, unknown }
enum ClosingRate { closing, stable, separating, unknown }

class TrackedObject {
  final int trackId;
  final RoadObjectType type;
  final String label;
  
  // Latest stats
  Rect smoothedBox;
  double confidence;
  DateTime lastSeen;
  
  // History for tracking & closing rate
  int framesMissed = 0;
  final List<({DateTime time, double area})> areaHistory = [];
  
  // Estimations
  ProximityCategory proximity = ProximityCategory.unknown;
  ClosingRate closingRate = ClosingRate.unknown;

  TrackedObject({
    required this.trackId,
    required this.type,
    required this.label,
    required this.smoothedBox,
    required this.confidence,
    required this.lastSeen,
  });

  void updateWithDetection(DetectedObject det, DateTime now) {
    confidence = det.confidence;
    lastSeen = now;
    framesMissed = 0;
    
    // EMA smoothing for bounding box
    const double alpha = 0.3;
    smoothedBox = Rect.fromLTRB(
      smoothedBox.left * (1 - alpha) + det.boundingBox.left * alpha,
      smoothedBox.top * (1 - alpha) + det.boundingBox.top * alpha,
      smoothedBox.right * (1 - alpha) + det.boundingBox.right * alpha,
      smoothedBox.bottom * (1 - alpha) + det.boundingBox.bottom * alpha,
    );

    double area = smoothedBox.width * smoothedBox.height;
    areaHistory.add((time: now, area: area));
    
    // Keep history up to 2 seconds
    areaHistory.removeWhere((entry) => now.difference(entry.time).inSeconds > 2);
    
    _updateProximity(area);
    _updateClosingRate();
  }

  void _updateProximity(double area) {
    if (area > 0.4) {
      proximity = ProximityCategory.veryNear;
    } else if (area > 0.15) {
      proximity = ProximityCategory.near;
    } else if (area > 0.05) {
      proximity = ProximityCategory.medium;
    } else {
      proximity = ProximityCategory.far;
    }
  }

  void _updateClosingRate() {
    if (areaHistory.length < 3) {
      closingRate = ClosingRate.unknown;
      return;
    }

    final first = areaHistory.first;
    final last = areaHistory.last;
    
    final dtSeconds = last.time.difference(first.time).inMilliseconds / 1000.0;
    if (dtSeconds < 0.2) {
      // Not enough time passed to judge reliably
      closingRate = ClosingRate.unknown;
      return;
    }

    double growthRatio = last.area / first.area;
    // Normalize ratio per second roughly to avoid hyper-sensitivity over long periods
    double growthPerSecond = (growthRatio - 1.0) / dtSeconds;

    if (growthPerSecond > 0.15) {
      closingRate = ClosingRate.closing;
    } else if (growthPerSecond < -0.15) {
      closingRate = ClosingRate.separating;
    } else {
      closingRate = ClosingRate.stable;
    }
  }
}
