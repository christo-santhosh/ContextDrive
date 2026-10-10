# ContextDrive v4 risk policy

This is a deterministic driving-assistance policy, not a collision-probability
model or an autonomous-driving controller. Visual proximity is a normalised
bounding-box-area proxy, not a distance in metres.

## Assessment outputs

| Output | Meaning |
| --- | --- |
| LOW | No configured hazard rule is active in the available data. |
| MODERATE | One observed event warrants caution. |
| HIGH | A severe observed event or an observed event with adverse context warrants urgent action. |
| CRITICAL | Only: hard braking + visually very-close closing vehicle + adverse context. It does not predict a collision. |
| LIMITED / STALE DATA | Separate data-quality status. It never hides a known observed hazard. |

## Provisional rule limits

| Limit | Value |
| --- | --- |
| Very-close / near visual proxy | <= 0.10 / <= 0.30 |
| Moderate / significant speed excess | > 10 / > 20 km/h |
| High speed with poor visibility | > 80 km/h |
| Poor provider visibility | < 1000 m |
| CARLA hard braking / rapid acceleration | <= -3.5 / >= +3.0 m/s² |
| Minimum speed for CARLA motion classification | 5 km/h |
| CARLA motion persistence | 350 ms |
| Hazard presentation persistence | 1 s |

These limits are heuristic starting points and require scenario and road-data
validation before any real-world safety claim.

## Context policy

Rain, heavy rain/fog, night, and dawn/dusk are advisories. They do not by
themselves become a collision event. Rain means rain was reported for the
current area; it does not assert that the road surface is wet. Missing weather
or time context is UNKNOWN and makes the assessment limited rather than clear.

CARLA sends authoritative `scenarioContext` and `longitudinalAccelMps2`; those
values are kept separate from physical GPS/weather/IMU. The phone IMU remains
directionally unavailable until phone-mount orientation calibration exists.

## Repeatable CARLA demo scenarios

First enable CARLA mode in the app, note the phone's Wi-Fi IP, start CARLA,
then run each command from the repository root. These commands use the actual
`manual_driving_rig.py` CLI; replace `PHONE_IP` with the IP displayed on the
phone. Hold each condition for at least one second. The camera rules require
the phone camera to see a suitable vehicle on the CARLA monitor; the script
does not inject object detections.

| ID | Command | Expected primary result | Camera requirement | Verification |
| --- | --- | --- | --- | --- |
| C1 | `python carla/manual_driving_rig.py --stream --phone PHONE_IP --scenario BENIGN --speed-limit 60` | LOW with no configured hazard (assuming no visual close/closing vehicle) | No | Manual runtime |
| C2 | `python carla/manual_driving_rig.py --stream --phone PHONE_IP --scenario RAIN --speed-limit 60 --rain` | Rain advisory; not a hazard by itself | No | Manual runtime |
| C3 | `python carla/manual_driving_rig.py --stream --phone PHONE_IP --scenario NIGHT --speed-limit 60 --night` | Night advisory; not a hazard by itself | No | Manual runtime |
| C4 | `python carla/manual_driving_rig.py --stream --phone PHONE_IP --scenario HEAVY_RAIN --speed-limit 60 --rain --visibility poor` | At >80 km/h, moderate high-speed/poor-visibility event; at >80 km/h over limit, high speeding-in-adverse-conditions event | No | Rule unit test / manual runtime |
| C5 | same as C1; accelerate above 5 km/h, then brake firmly | After 350 ms of signed deceleration <= -3.5 m/s²: moderate hard-braking event | No | Contract test / manual runtime |
| C6 | same as C1; accelerate firmly above 5 km/h | After 350 ms of signed acceleration >= +3.0 m/s²: moderate rapid-acceleration event | No | Contract test / manual runtime |
| C7 | C5 or C6 while the phone camera sees a close tracked vehicle | High hard-braking-near-traffic or high rapid-acceleration-with-context, depending on telemetry/context | Yes | Manual runtime |
| C8 | C4; brake firmly while the phone camera sees a visually very-close vehicle that is growing in view | CRITICAL only when hard braking + very-close + closing + adverse context all hold | Yes | Rule unit test / manual runtime |

The exact UI wording comes from the assessment's **What happened**, **Why it
matters**, and **Advice** fields. C5/C6 are directionally classified only by
the new `longitudinalAccelMps2` value, not by acceleration magnitude.

## Manual Nothing Phone (2a) check

1. Launch with `flutter run --dart-define=WEATHER_API_KEY=...` only when
   weather verification is intended; no key must show limited weather data.
2. Grant Camera and Location permission. Mount the phone rigidly and keep it
   stationary for camera demonstrations.
3. Check that the risk card labels unavailable weather/time as limited data;
   it must not show a false clear/"day" condition.
4. Use the debug hard-braking toggle only as a labeled UI demonstration. It is
   not physical phone-IMU evidence.
5. Test CARLA/voice only on a closed, stationary setup. Never operate the
   phone or rely on these alerts while driving on public roads.
