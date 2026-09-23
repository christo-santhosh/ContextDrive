import 'dart:math';
import 'dart:ui';
import '../models/detected_object.dart';
import '../models/tracked_object.dart';

class ObjectTracker {
  int _nextTrackId = 1;
  final List<TrackedObject> _tracks = [];

  // MVP tracking thresholds
  final double iouThreshold = 0.3;
  final int maxMissedFrames = 5;

  List<TrackedObject> updateTracks(List<DetectedObject> detections) {
    final now = DateTime.now();

    // 1. Predict (none for MVP, just assume stationary for 1 frame)
    
    // 2. Match detections to existing tracks using IoU
    List<bool> matchedDetections = List.filled(detections.length, false);
    
    for (var track in _tracks) {
      double bestIou = 0.0;
      int bestDetectionIdx = -1;

      for (int i = 0; i < detections.length; i++) {
        if (matchedDetections[i]) continue;
        if (detections[i].type != track.type) continue; // Only match same type

        double iou = _calculateIoU(track.smoothedBox, detections[i].boundingBox);
        if (iou > bestIou) {
          bestIou = iou;
          bestDetectionIdx = i;
        }
      }

      if (bestIou > iouThreshold) {
        // Update track
        track.updateWithDetection(detections[bestDetectionIdx], now);
        matchedDetections[bestDetectionIdx] = true;
      } else {
        // Track missed
        track.framesMissed++;
      }
    }

    // 3. Create new tracks for unmatched detections
    for (int i = 0; i < detections.length; i++) {
      if (!matchedDetections[i]) {
        _tracks.add(TrackedObject(
          trackId: _nextTrackId++,
          type: detections[i].type,
          smoothedBox: detections[i].boundingBox,
          confidence: detections[i].confidence,
          lastSeen: now,
        )..updateWithDetection(detections[i], now)); // Initial stats
      }
    }

    // 4. Remove stale tracks
    _tracks.removeWhere((t) => t.framesMissed >= maxMissedFrames);

    return _tracks;
  }

  double _calculateIoU(Rect boxA, Rect boxB) {
    double xA = max(boxA.left, boxB.left);
    double yA = max(boxA.top, boxB.top);
    double xB = min(boxA.right, boxB.right);
    double yB = min(boxA.bottom, boxB.bottom);

    double intersectionArea = max(0.0, xB - xA) * max(0.0, yB - yA);
    double boxAArea = boxA.width * boxA.height;
    double boxBArea = boxB.width * boxB.height;

    double iou = intersectionArea / (boxAArea + boxBArea - intersectionArea);
    return iou;
  }
}
