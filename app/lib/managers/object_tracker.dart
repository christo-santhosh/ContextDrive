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
  static const maxTrackAge = Duration(milliseconds: 900);

  List<TrackedObject> updateTracks(List<DetectedObject> detections, {DateTime? observationTime}) {
    final now = observationTime ?? DateTime.now();
    expireStale(now);

    // 1. Predict (none for MVP, just assume stationary for 1 frame)
    
    // 2. Match detections to existing tracks using IoU
    List<bool> matchedDetections = List.filled(detections.length, false);
    
    for (var track in _tracks) {
      // A normal IoU match is preferred.  The small fallback score allows a
      // smoothly expanding lead-vehicle box to retain its identity when its
      // overlap with the *smoothed* previous box drops below the IoU limit.
      // It is deliberately bounded by label, centre movement and area ratio.
      double bestScore = -1.0;
      int bestDetectionIdx = -1;

      for (int i = 0; i < detections.length; i++) {
        if (matchedDetections[i]) continue;
        if (detections[i].type != track.type) continue; // Only match same type
        if (detections[i].label != track.label) continue; // Only match same class (e.g. car -> car)

        final iou = _calculateIoU(track.smoothedBox, detections[i].boundingBox);
        final isIoUMatch = iou > iouThreshold;
        final isApproachMatch = _isPlausibleApproachMatch(track, detections[i]);
        if (!isIoUMatch && !isApproachMatch) continue;

        // Never let an approach fallback beat a real IoU match.
        final score = isIoUMatch ? iou + 1.0 : iou;
        if (score > bestScore) {
          bestScore = score;
          bestDetectionIdx = i;
        }
      }

      if (bestDetectionIdx != -1) {
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
          label: detections[i].label,
          smoothedBox: detections[i].boundingBox,
          confidence: detections[i].confidence,
          lastSeen: now,
        ));
      }
    }

    // 4. Remove stale tracks
    _tracks.removeWhere((t) => t.framesMissed >= maxMissedFrames);

    return _tracks;
  }

  /// Expires tracks by wall-clock age as well as missed inference frames. This
  /// prevents a frozen camera stream from leaving a stale visual hazard active.
  void expireStale(DateTime now) {
    _tracks.removeWhere((track) => now.difference(track.lastSeen) > maxTrackAge);
  }

  bool _isPlausibleApproachMatch(TrackedObject track, DetectedObject detection) {
    if (track.label != detection.label || track.type != detection.type) return false;
    final oldArea = track.area;
    final newArea = detection.boundingBox.width * detection.boundingBox.height;
    if (oldArea <= 0 || newArea <= 0) return false;
    final ratio = newArea / oldArea;
    if (ratio < 0.25 || ratio > 4.0) return false;
    final dx = track.smoothedBox.center.dx - detection.boundingBox.center.dx;
    final dy = track.smoothedBox.center.dy - detection.boundingBox.center.dy;
    return dx * dx + dy * dy <= 0.0225; // centre movement <= 15% of frame
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

  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }
}
