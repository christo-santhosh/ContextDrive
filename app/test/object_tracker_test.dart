import 'dart:ui';

import 'package:app/managers/object_tracker.dart';
import 'package:app/models/detected_object.dart';
import 'package:app/models/tracked_object.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedObject vehicle(double side, {double centerX = .5, double centerY = .5}) => DetectedObject(
      label: 'car',
      confidence: .9,
      boundingBox: Rect.fromCenter(center: Offset(centerX, centerY), width: side, height: side),
      type: RoadObjectType.roadVehicle,
    );

void main() {
  group('ObjectTracker visual approach history', () {
    test('gradual fresh growth becomes a developing approach before near proximity', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      tracker.updateTracks([vehicle(.10)], observationTime: start);
      tracker.updateTracks([vehicle(.15)], observationTime: start.add(const Duration(milliseconds: 300)));
      final tracks = tracker.updateTracks([vehicle(.22)], observationTime: start.add(const Duration(milliseconds: 650)));

      expect(tracks, hasLength(1));
      final track = tracks.single;
      expect(track.proximity, ProximityCategory.far);
      expect(track.closingRate, ClosingRate.closing);
      expect(track.growthPerSecond, greaterThan(TrackedObject.closingGrowthPerSecond));
      expect(track.isDevelopingApproach, isTrue);
    });

    test('rapid box expansion keeps the same plausible track when IoU falls below the normal threshold', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      final first = tracker.updateTracks([vehicle(.10)], observationTime: start).single;
      final tracks = tracker.updateTracks([vehicle(.195)], observationTime: start.add(const Duration(milliseconds: 250)));

      expect(tracks, hasLength(1));
      expect(tracks.single.trackId, first.trackId);
      expect(tracks.single.areaHistory, hasLength(2));
    });

    test('a stationary visually near vehicle is not called closing', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      tracker.updateTracks([vehicle(.48)], observationTime: start);
      tracker.updateTracks([vehicle(.48)], observationTime: start.add(const Duration(milliseconds: 250)));
      final track = tracker.updateTracks([vehicle(.48)], observationTime: start.add(const Duration(milliseconds: 500))).single;

      expect(track.proximity, ProximityCategory.near);
      expect(track.closingRate, ClosingRate.stable);
      expect(track.isDevelopingApproach, isFalse);
    });

    test('a receding vehicle is classified as separating with irregular intervals', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      tracker.updateTracks([vehicle(.30)], observationTime: start);
      tracker.updateTracks([vehicle(.23)], observationTime: start.add(const Duration(milliseconds: 90)));
      final track = tracker.updateTracks([vehicle(.16)], observationTime: start.add(const Duration(milliseconds: 580))).single;

      expect(track.closingRate, ClosingRate.separating);
      expect(track.isDevelopingApproach, isFalse);
    });

    test('one noisy larger sample is not enough to label an approach', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      tracker.updateTracks([vehicle(.12)], observationTime: start);
      tracker.updateTracks([vehicle(.12)], observationTime: start.add(const Duration(milliseconds: 250)));
      final track = tracker.updateTracks([vehicle(.20)], observationTime: start.add(const Duration(milliseconds: 500))).single;

      expect(track.closingRate, isNot(ClosingRate.closing));
      expect(track.isDevelopingApproach, isFalse);
    });

    test('old tracks expire when camera inference freezes and reset clears history', () {
      final tracker = ObjectTracker();
      final start = DateTime(2026, 10, 11, 10);
      tracker.updateTracks([vehicle(.20)], observationTime: start);
      tracker.expireStale(start.add(const Duration(milliseconds: 901)));
      expect(tracker.updateTracks(const [], observationTime: start.add(const Duration(milliseconds: 901))), isEmpty);

      tracker.updateTracks([vehicle(.20)], observationTime: start.add(const Duration(seconds: 2)));
      tracker.reset();
      expect(tracker.updateTracks(const [], observationTime: start.add(const Duration(seconds: 2))), isEmpty);
    });
  });
}
