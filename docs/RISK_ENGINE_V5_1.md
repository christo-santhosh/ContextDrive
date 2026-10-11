# ContextDrive v5.1: early visual approach warning

## Scope

This is a CARLA-demo and phone-vision improvement, not a calibrated forward-collision-warning system. The visual measurements are normalized YOLO bounding-box areas. They are never displayed or stored as metres, time-to-collision, collision probability, or physical closing speed.

## Root cause corrected

The old tracker categorised a box as `medium` above `0.05` area, but the risk manager mapped that category to a visual proxy of `0.6`. The existing medium/near closing candidate required a proxy of `<= 0.30`, which is only reached once the box is actually `near` (area `> 0.15`). The intended earlier medium-range warning could therefore not be reached.

The first eligible candidate also had to wait for the 500 ms periodic evaluator and then a generic 1000 ms confirmation interval. The tracker itself required three samples spanning at least 200 ms. These delays could stack. Finally, rapid scale changes could fail the strict IoU match, creating a new track and erasing the short history required to identify approach.

The receiver and CARLA sender already use bounded latest-frame buffers. The receiver retains only `_latestFrame`, and the CARLA producer uses a one-item queue. v5.1 retains that design and schedules the latest received frame after the current inference completes instead of building an inference queue.

## New visual approach rule

The tracker timestamps CARLA observations at phone-frame receipt (rather than
inference completion), so a slow inference cannot make an old scene look new.
It now raises `isDevelopingApproach` only when all of the following hold:

* one road-vehicle track has at least three timestamped observations;
* its normalized, smoothed box area is at least `0.025`;
* the first-to-last area growth is over `0.15` per second across at least `200 ms`;
* the last three observed areas each grow by more than one percent; and
* the track remains fresh for at most `900 ms`.

This creates a `MODERATE` event, **Tracked vehicle is closing in**, before the existing `near` and `veryNear` rules. It remains a short-horizon image-space trend rather than a prediction of impact.

## Timing policy

| Event | Previous confirmation | v5.1 confirmation |
| --- | ---: | ---: |
| Ordinary contextual event | 1000 ms | 500 ms |
| Developing tracked approach | 1000 ms | 350 ms |
| Closing vehicle / adverse conditions | 1000 ms | 250 ms |
| Rapid optical approach at close range | 1000 ms | 150 ms |

The HUD accepts an event as soon as its event-specific confirmation is complete. Audio remains controlled by `RiskAlertService`; it does not gate HUD updates. The existing three-second downward cooldown is retained to avoid flicker.

## Diagnostics

CARLA mode now displays received FPS, inference duration, result frame age, source simulation frame/time, engine evaluation duration, visual area, proximity category, closing classification, growth per second, history length, pending candidate/remaining confirmation, and accepted HUD event. This information is for controlled debugging and uses local monotonic elapsed timers only for within-process durations.

## Repeatable CARLA verification procedure

1. Start the existing CARLA manual rig and its telemetry sender.
2. On the Nothing Phone 2a, connect USB and run the existing `adb reverse` commands for the telemetry and CARLA-camera ports.
3. Select the CARLA virtual-camera source in ContextDrive. Wait until the diagnostic pill shows a non-zero FPS and a current frame age.
4. Set a lead vehicle ahead of the ego vehicle in a controlled CARLA scene; approach it steadily so its detected bounding box grows across at least three fresh frames.
5. Record the source simulation frame/time at first consistent growth, at the first MODERATE **Tracked vehicle is closing in** warning, and at any contact reported by CARLA.
6. Confirm the MODERATE warning occurs before the `near` / `veryNear` box stages and before contact. Then repeat with a stationary/receding lead vehicle and confirm no approach event is accepted.

The current repository cannot generate an actual device/CARLA latency measurement by itself. Do not report a 500 ms pre-contact lead time until the above run is recorded from the phone diagnostics and CARLA timestamps.
