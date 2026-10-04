# ContextDrive: Testing, Demo, and Technical Guide

## Purpose and safety boundary

ContextDrive is an Android **driver-assistance prototype**. It combines phone-camera object detection with filtered GPS speed, optional weather, time of day, and an explainable rule engine. It can show a risk level, explain the decision, recommend a cautious action, speak elevated-risk alerts, and retain the five most recent elevated-risk events for the current session.

> [!IMPORTANT]
> ContextDrive is not a collision-avoidance system. It does not measure physical distance, calculate certified time-to-collision, control a vehicle, or replace the driver. Test while stationary, using a tripod, controlled imagery, or a second person controlling the phone. Never operate it while driving.

## System flow

```text
Camera frames
     |
     v
YOLO26n on-device detection
     |
     +--> retain: car, motorcycle, bus, truck, person, bicycle
     |
     v
Object tracker: IoU matching + smoothing + box-area history
     |                                  GPS ---> filtered speed ----+
     |                                  Map API -> speed limit -----+-->
     |                                  Weather -> rain/visibility -+-->
     |                                  Time -> day/night -----------+-->
     v                                                            |
                     Context vector ------------------------------+
                                 |
                                 v
                   Explainable risk-rule engine
                                 |
              +------------------+------------------+
              v                  v                  v
       Risk card/reasons    Android voice alert   Session history
```

The detector supplies visual evidence. GPS, weather, road-limit, and time services supply context. The rule engine fuses that information into a visible decision; it does not treat one detection as proof that a collision will occur.

## Features and presentation wording

| Feature | What it does | What to say in the demo |
| --- | --- | --- |
| Live camera detection | Runs the `yolo26n` model over live camera frames. | “The phone identifies relevant road objects in real time.” |
| Road-user filtering | Retains cars, motorcycles, buses, trucks, people, and bicycles for risk analysis. | “We filter the general detector output to classes that matter for driving risk.” |
| Object tracking | Matches the same object across frames and smooths its bounding box. | “Tracking prevents one noisy frame from becoming a risk alert.” |
| Relative visual proximity | Uses the normalized bounding-box area as a visual near/far cue. | “Near and very near are image-space estimates, not metres.” |
| Closing cue | Watches whether a tracked box area grows over time. | “A growing box is a cue that an object may be approaching.” |
| GPS speed | Rejects low-quality GNSS readings before they reach risk rules. | “We prefer limited data to a misleading speed.” |
| Map speed limit | Requests nearby OpenStreetMap `maxspeed` data when available. | “This is a map estimate, never a replacement for posted signs.” |
| Weather and time | Adds rain, visibility, and day/night context. | “Unavailable inputs are shown as unavailable; the app does not invent them.” |
| Explainable risk card | Shows level, observed trigger, evidence, context, data quality, and advice. | “Every alert has a visible evidence trail.” |
| Voice alerts | Uses Android text-to-speech for meaningful Moderate/High changes. | “Voice is rate-limited to avoid repeating a noisy warning.” |
| Session history | Keeps the latest five elevated-risk decisions in memory. | “This is a short in-session audit trail, not permanent trip storage.” |

## Before testing or presenting

### Equipment

- Use a physical Android phone; Android 14 or newer is recommended.
- Fully charge it, enable sound, and make sure Android text-to-speech plus an English (US) voice are installed.
- Mount the phone on a tripod or stable holder with a clear forward-facing camera view.
- Give the first launch a reliable internet connection because the official `yolo26n` model may download once and then cache locally.
- Enable Location and grant Camera and Location permissions.
- Provide a weather API key only if weather context is part of the demonstration. Without one, `Weather off` is expected.
- Treat a missing map speed limit as a valid result: the road may not have an OpenStreetMap `maxspeed` tag or the network lookup may fail.

### Commands

From the repository root:

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=WEATHER_API_KEY=your_key_here
```

Omit the `--dart-define` option to demonstrate graceful weather unavailability. Do not put a real key in source code or commit it.

For a local test APK:

```bash
flutter build apk --debug
```

The current Android release configuration uses debug signing. Do not describe it as a production signing configuration.

### Pre-demo readiness check

Do this once the day before, then again shortly before presenting:

1. Launch with internet enabled and wait for the camera/model to load.
2. Confirm that the dashboard and live detection overlay appear.
3. Restart the app with the same device. Confirm the cached model starts without a new download.
4. Confirm speaker volume and the voice-control icon are on.
5. Confirm GPS speed changes from `--` to a valid reading outdoors.
6. Check whether weather and road speed-limit context are available. If either is unavailable, say so rather than hiding it.

## Functional test plan

| Test | Controlled procedure | Expected result |
| --- | --- | --- |
| Static baseline | Run `flutter analyze` and `flutter test`. | No analyzer issues; all tests pass. |
| Camera permission | Deny Camera, use Retry, then grant it. | A clear failure state appears; retry works after permission is granted. |
| Location permission | Deny Location after granting Camera. | The app continues with a limited assessment instead of crashing. |
| Model startup | First launch online, then restart offline after successful load. | First-use model loads; subsequent launch uses the local cache. |
| Normal scene | Aim at a controlled scene without a large road object. | Green `MONITORING` or grey `LIMITED DATA`; no repeated voice alert. |
| Vehicle risk | While stationary, move a realistic vehicle image/scene closer to the fixed camera. | Vehicle count and visual proximity update; a sustained near/closing cue can elevate risk. |
| Person/bicycle risk | Use a controlled person or bicycle scene; keep the phone fixed. | Vulnerable-road-user count updates and the person/cyclist rule takes priority when near/closing. |
| Voice | Hold a Moderate or High condition for over one second with voice on. | One concise Android spoken warning. The same event is not repeatedly spoken. |
| Voice toggle | Turn voice off during an elevated state, then on again. | Off stops speech; on speaks only if the assessment is currently elevated. |
| History | Create an elevated decision, then tap the history icon. | Recent reason, time, and advice appear; only the last five are retained. |
| GPS quality | Test outdoors, then turn Location off. | Valid GPS provides speed; stale/unavailable GPS produces `LIMITED DATA`, never invented speed. |
| Weather fallback | Run without `WEATHER_API_KEY`; optionally repeat with a valid key. | `Weather off` is shown without a key; current weather can show with a key. |
| Map limit fallback | Test at a known mapped road with network. | The sign appears only after a lookup succeeds; unavailable remains unavailable. |
| Rotation | Rotate after the model is ready. | Portrait and landscape retain a readable camera, risk card, and controls. |

A failure is worth recording, not hiding: camera/model cannot become ready, telemetry appears frozen, a sustained alert cannot be heard, a risk claim does not match visible evidence, or an old object remains counted after leaving view.

## Five-minute demonstration script

All actions should be stationary. Use a tripod, recorded road imagery, or an assistant; do not hold or interact with the phone while driving.

### 0:00–0:30 — Purpose

> “ContextDrive is a warning-only Android driver-assistance prototype. It combines camera perception with speed and environmental context, then shows exactly why it selected a risk level. It is not autonomous driving and it does not replace driver judgement.”

Point out the speedometer, live camera, day/weather pills, risk card, voice icon, and history icon.

### 0:30–1:15 — Data quality

> “The system makes data quality visible. GPS, weather, and road speed limits are inputs, not assumptions. If an input is unavailable, the app says so and limits the assessment rather than fabricating a value.”

Point to the `Data` line. If weather is off or the speed limit is unavailable, explain that it is deliberate graceful degradation.

### 1:15–2:15 — Camera perception

> “YOLO26n processes camera frames on the phone. We retain vehicles, people, and bicycles, then track them across frames. Box size and growth are only relative visual cues, not real-world distance measurements.”

Show a controlled vehicle/person/bicycle scene and the overlay/counters. Keep the phone fixed while the scene changes.

### 2:15–3:15 — Explain an alert

Create a sustained near/closing scene and wait at least one second.

> “The output is explainable. `Observed` names the rule trigger, `Evidence` gives the vision or sensor facts, `Context` gives rain/night/speed modifiers, and `Advice` gives the recommended driver response. The system describes a caution; it does not predict a crash.”

Let voice play once if enabled, then point to the voice icon and explain its cooldown.

### 3:15–4:00 — Auditability

Tap the history icon.

> “Elevated decisions are retained for this session with their time, reason, and recommendation. The MVP stores only five events in memory; it does not upload or permanently store trip data.”

### 4:00–5:00 — Close responsibly

> “The next engineering work is time-based stale-track expiry, continuously refreshed telemetry, model-readiness progress, and a visible system-health panel. Longer-term work includes calibrated distance/TTC estimation, lane understanding, and persistent trip summaries.”

## Inside the engines

### Camera and detection

`YOLOView` runs `yolo26n` and returns a class name, confidence, and normalized bounding box. ContextDrive maps those labels as follows:

| YOLO labels | ContextDrive category |
| --- | --- |
| `car`, `motorcycle`, `bus`, `truck` | Road vehicle |
| `person`, `bicycle` | Vulnerable road user |
| Other COCO classes | Ignored by the risk engine |

The current camera confidence threshold is the package default of `0.25`. It must be tuned with recorded representative scenes before making claims about false-positive or false-negative performance.

### Tracking, visual proximity, and approach

A detection can join an existing track only when its class/category matches and its intersection-over-union (IoU) is above `0.30`. Matched boxes are smoothed with an exponential moving average using `alpha = 0.30`.

The tracker stores up to two seconds of box-area history:

- area > `0.40`: visually **very near**
- area > `0.15`: visually **near**
- area > `0.05`: visually **medium**
- otherwise: visually **far**

After three samples over at least 0.2 seconds, area growth per second above `0.15` means visually closing; below `-0.15` means separating; values between them are stable.

These are image-space heuristics. Mounting angle, field of view, object type, and road geometry affect them. They are not metres, velocity, headway, or time-to-collision measurements.

### GPS speed

`GpsService` rejects:

- negative speed;
- horizontal accuracy worse than 20 m;
- speed accuracy worse than 2 m/s;
- GNSS timestamps older than two seconds;
- acceleration above 10 m/s² compared with the prior accepted reading.

Accepted values are converted to km/h, passed through a five-value median filter, and values below 3 km/h become zero. The risk manager treats speed as unavailable after repeated invalid readings or five seconds of staleness.

That is why `LIMITED DATA` is preferable to displaying an untrustworthy speed.

### Map speed limit

The app sends a request to the Overpass/OpenStreetMap API for a road with a `maxspeed` tag within 30 m. It checks at most every 30 seconds, times out after five seconds, and converts mph to km/h. A stale result is cleared after two minutes without a successful refresh.

This is helpful context but not legal authority: road tags can be missing, nearby parallel roads can be selected, temporary signs are not guaranteed, and network calls can fail.

### Weather and time

Weather is read only when `WEATHER_API_KEY` is supplied. It refreshes after 15 minutes or approximately 5 km of movement. OpenWeather condition codes 200–599 are treated as rain-like conditions; visibility is in metres.

The time service computes local sunrise/sunset after it receives location. Before that it uses a 6 PM–6 AM night fallback. Night, rain, or available weather visibility below 1,000 m contribute to poor-visibility context.

### IMU status

The project contains a phone accelerometer service, but IMU risk detection is deliberately disabled until a phone-mount calibration process exists. Do not present harsh braking or swerving as an active feature.

### Context vector

Every 500 ms, the risk manager assembles a context vector with:

- filtered GPS speed and map speed limit;
- rain, visibility, and weather availability;
- day/night;
- vehicle and vulnerable-road-user count;
- closest visual-proximity category and closing cue for each group;
- IMU status (currently disabled);
- GPS quality reason.

The context vector separates hardware/network collection from decision logic, making risk rules easier to inspect and test.

### Risk rules and priority

Rules are evaluated from highest priority to lowest:

| Priority | Trigger | Output |
| --- | --- | --- |
| 1 | Erratic IMU event near a vehicle | High — inactive while IMU is disabled |
| 2 | Vulnerable road user visually very near and closing | High |
| 3 | Vulnerable road user very near, or near and closing | Moderate |
| 4 | Vehicle visually very near and closing | High |
| 5 | Erratic IMU event | Moderate — inactive while IMU is disabled |
| 6 | Vehicle visually near and closing | Moderate |
| 7 | Vehicle visually very near | Moderate |
| 8 | GPS speed over 80 km/h in poor visibility | Moderate |
| 9 | GPS speed more than 10 km/h over an available map limit | Moderate |
| 10 | No valid GPS speed | Limited data |
| 11 | No rule above | Low / Monitoring |

The first matching high-priority rule wins. This explains why a near, approaching person or cyclist takes precedence over ordinary vehicle or speed conditions.

### Explanations, hysteresis, and voice

Each assessment includes:

- **Why:** plain-language mechanism behind the rule;
- **Observed:** the trigger that matched;
- **Evidence:** vision/sensor facts;
- **Context:** rain, night, and speed modifiers;
- **Data:** availability and quality;
- **Advice:** a cautious recommended action.

Moderate/High candidates must persist for one second before changing the displayed elevated state. A three-second drop cooldown avoids clearing risk because of a momentary lost detection; the state drops immediately when no vehicle or vulnerable road user is tracked.

The voice layer speaks only Moderate/High assessments. It uses a 6-second cooldown for High and 12 seconds for Moderate; severity escalation or a meaningful reason change may speak sooner. Android text-to-speech uses the phone's installed voice engine and must not block the UI if unavailable.

## Questions an examiner may ask

**Is this a collision predictor?**  
No. It is a warning-oriented prototype using visual relative-proximity/approach cues and context. It does not calculate physical distance or certified time to collision.

**Why use a rule engine after YOLO?**  
YOLO identifies objects. The rule engine joins those observations with speed, weather, and time in a transparent way. Each decision has a visible rule, evidence list, and recommendation.

**How are false alerts reduced?**  
Irrelevant classes are filtered, tracks are matched and smoothed, elevated conditions must persist, and voice is rate-limited. Threshold tuning and time-based stale-track expiry are the next reliability work.

**What happens when GPS, weather, or a speed limit is unavailable?**  
The app reports the missing source and uses only the context it can justify. It does not invent unavailable values.

**Is data uploaded?**  
The MVP does not persist or upload trip/event history. Camera inference runs on-device. Weather and map speed-limit lookups are optional network requests.

**Why is IMU driving behaviour not demonstrated?**  
Phone accelerometer readings vary with mount orientation and device placement. The feature is intentionally disabled pending calibration.

## Known limits and next work

- Bounding-box geometry is a relative cue, not a physical-distance or collision-certainty measurement.
- The camera view has no lane/drivable-area understanding or calibrated forward-corridor filter yet.
- Visual-confidence and proximity thresholds need representative device testing.
- First-use model download should show explicit progress/readiness.
- Live telemetry should repaint when data changes even if the risk label does not.
- Tracks should expire by elapsed time as well as missed frame count.
- Map speed limits are best-effort OpenStreetMap data, not legal authority.
- Weather is optional and unavailable without an API key/network.
- Alerts are in memory only; there is no persistent trip summary.
- Public distribution requires resolving the YOLO license path in `LICENSE_YOLO.md`.

## Final presenter checklist

- [ ] `flutter analyze` and `flutter test` are green.
- [ ] The test phone has a cached model and working camera preview.
- [ ] Camera, Location, volume, and Android TTS are enabled.
- [ ] Weather and speed-limit availability were checked and can be explained.
- [ ] A controlled vehicle/person/bicycle scene is ready.
- [ ] The phone is mounted; nobody operates it while driving.
- [ ] You can point to `Observed`, `Evidence`, `Context`, `Data`, and `Advice`.
- [ ] You call it a warning-only prototype, not a safety guarantee.

