# CONTEXTDRIVE — COMPLETE CODE FILES & FUNCTIONS DIRECTORY
## Comprehensive Architectural Guide, File Inventory, Method Specifications, and Viva Defense Reference

> **Project Name:** ContextDrive — Context-Aware Smartphone-Based Advanced Driver Assistance System (ADAS)  
> **Repository Root:** `c:\Users\chris\Documents\projects\ContextDrive`  
> **Target Document:** `docs/CODE_FILES_AND_FUNCTIONS.md`  
> **Target Audience:** B.Tech Computer Science project evaluation, project defense, code review, and viva voce preparation.

---

## TABLE OF CONTENTS

1. [Executive Architectural Overview](#1-executive-architectural-overview)
2. [Master File Inventory & Quick Reference](#2-master-file-inventory--quick-reference)
3. [Tier 1: Core Mobile Application (Flutter / Dart)](#3-tier-1-core-mobile-application-flutter--dart)
   - [3.1 Entry Point & App Lifecycle](#31-entry-point--app-lifecycle)
   - [3.2 Deterministic Risk Engine Layer](#32-deterministic-risk-engine-layer)
   - [3.3 Stateful Orchestration & Perception Tracking](#33-stateful-orchestration--perception-tracking)
   - [3.4 Domain Models & Data Structures](#34-domain-models--data-structures)
   - [3.5 Multi-Modal Sensor & Network Services](#35-multi-modal-sensor--network-services)
   - [3.6 User Interface & Live HUD Components](#36-user-interface--live-hud-components)
4. [Tier 2: CARLA Cyber-Physical Simulation & Tooling (Python)](#4-tier-2-carla-cyber-physical-simulation--tooling-python)
   - [4.1 Manual Driving Rig & Hardware Simulation](#41-manual-driving-rig--hardware-simulation)
   - [4.2 Vehicle Motion Mathematics](#42-vehicle-motion-mathematics)
   - [4.3 Scenario Preparation Helpers](#43-scenario-preparation-helpers)
   - [4.4 Telemetry Streaming & Test Controllers](#44-telemetry-streaming--test-controllers)
5. [Tier 3: Automated Verification Test Suites](#5-tier-3-automated-verification-test-suites)
6. [Component Interdependency & Data-Flow Matrix](#6-component-interdependency--data-flow-matrix)
7. [Essential Viva Questions & Model Defense Answers](#7-essential-viva-questions--model-defense-answers)

---

## 1. EXECUTIVE ARCHITECTURAL OVERVIEW

ContextDrive is partitioned into three distinct layers:

```
+-----------------------------------------------------------------------------------+
|                        TIER 1: MOBILE EDGE AI (FLUTTER/DART)                      |
|                                                                                   |
|  [Hardware Sensors]     [On-Device YOLOv8]      [External APIs]     [CARLA Receivers]  |
|  (GNSS, Solar, TTS)     (Google LiteRT Edge)    (OpenWeatherMap)    (TCP 8088, HTTP 8080)
|          │                       │                     │                    │     |
|          └───────────────────────┼─────────────────────┴────────────────────┘     |
|                                  ▼                                                |
|                       [ObjectTracker (Greedy IoU)]                                |
|                                  │                                                |
|                                  ▼                                                |
|                        [ContextVector Fuser]                                      |
|                                  │                                                |
|                                  ▼                                                |
|                    [Deterministic RiskEngine (v5.1)]                              |
|                                  │                                                |
|                   ┌──────────────┴──────────────┐                                 |
|                   ▼                             ▼                                 |
|          [RiskConfirmationPolicy]       [RiskAlertService]                        |
|          (Debounce & Filtering)         (Native Audio TTS)                        |
|                   │                                                               |
|                   ▼                                                               |
|          [Live Driving HUD (HomeScreen)]                                          |
+-----------------------------------------------------------------------------------+
                                   ▲
                                   │  (USB ADB 8088 / Wi-Fi 8080)
+-----------------------------------------------------------------------------------+
|                  TIER 2: SIMULATION & DIGITAL TWIN (PYTHON / CARLA)                |
|                                                                                   |
|   [CARLA 0.9.16 Simulator] ──► [manual_driving_rig.py] ──► [motion_math.py]       |
|            │                              │                                       |
|            ▼                              ▼                                       |
|   [spawn_lead_vehicle.py]        [Virtual Camera (CDVF)]   [Telemetry JSON (HTTP)]|
+-----------------------------------------------------------------------------------+
```

---

## 2. MASTER FILE INVENTORY & QUICK REFERENCE

| Category | File Path | Primary Function / Architectural Role |
| :--- | :--- | :--- |
| **Flutter Core** | [app/lib/main.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/main.dart) | App initialization, landscape locking, DI provider container. |
| **Risk Engine** | [app/lib/engine/risk_engine.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/engine/risk_engine.dart) | Pure rule-based deterministic hazard evaluator (v5.1). |
| **Managers** | [app/lib/managers/risk_manager.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/managers/risk_manager.dart) | Central stateful coordinator, multimodal fusion, alert lifecycle. |
| **Managers** | [app/lib/managers/object_tracker.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/managers/object_tracker.dart) | Temporal bounding-box association using IoU and tracking history. |
| **Models** | [app/lib/models/context_vector.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/context_vector.dart) | Snapshot data model, thresholds, motion classification, risk output. |
| **Models** | [app/lib/models/tracked_object.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/tracked_object.dart) | Single track state: EMA smoothing, proximity proxy, growth rate. |
| **Models** | [app/lib/models/detected_object.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/detected_object.dart) | Raw detection box and classification label from YOLO inference. |
| **Models** | [app/lib/models/risk_event.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/risk_event.dart) | Historical audit log entry for triggered alerts. |
| **Models** | [app/lib/models/app_state.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/app_state.dart) | Top-level application readiness and initialization state. |
| **Services** | [app/lib/services/carla_camera_stream_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/carla_camera_stream_service.dart) | TCP server receiving binary `CDVF` virtual camera JPEG frames (port 8088). |
| **Services** | [app/lib/services/carla_demo_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/carla_demo_service.dart) | HTTP server receiving vehicle telemetry JSON packets (port 8080). |
| **Services** | [app/lib/services/gps_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/gps_service.dart) | Physical smartphone GNSS location, speed parsing, noise rejection. |
| **Services** | [app/lib/services/imu_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/imu_service.dart) | Physical smartphone accelerometer / gyroscope listener. |
| **Services** | [app/lib/services/weather_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/weather_service.dart) | OpenWeatherMap REST API integration with 15-minute caching. |
| **Services** | [app/lib/services/time_context_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/time_context_service.dart) | Solar elevation calculator deriving Day / Dawn-Dusk / Night. |
| **Services** | [app/lib/services/speed_limit_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/speed_limit_service.dart) | Road speed-limit lookup service (defaults to 60 km/h baseline). |
| **Services** | [app/lib/services/risk_alert_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/risk_alert_service.dart) | Android native TTS voice alert announcer with cooldown throttling. |
| **UI** | [app/lib/ui/home_screen.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/home_screen.dart) | Main driving dashboard: HUD, camera feed, telemetry tray, overlays. |
| **UI** | [app/lib/ui/debug_settings_sheet.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/debug_settings_sheet.dart) | Debug overlay: manual overrides, live API status, CARLA controls. |
| **UI** | [app/lib/ui/widgets/diagnostic_panel.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/widgets/diagnostic_panel.dart) | Real-time diagnostic readouts for latency, tracking, and inputs. |
| **Python CARLA** | [carla/manual_driving_rig.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/manual_driving_rig.py) | Interactive CARLA vehicle driving rig, camera streaming, telemetry worker. |
| **Python CARLA** | [carla/motion_math.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/motion_math.py) | Projects CARLA world acceleration onto travel direction (signed m/s²). |
| **Python CARLA** | [carla/spawn_lead_vehicle.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/spawn_lead_vehicle.py) | Standalone helper to spawn stationary lead vehicle at target distance. |
| **Python CARLA** | [carla/carla_telemetry_streamer.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/carla_telemetry_streamer.py) | Headless telemetry streaming client for automated CARLA sessions. |
| **Python CARLA** | [carla/demo_controller.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/demo_controller.py) | CLI utility for injecting synthetic telemetry vectors into phone. |

---

## 3. TIER 1: CORE MOBILE APPLICATION (FLUTTER / DART)

### 3.1 Entry Point & App Lifecycle

#### [app/lib/main.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/main.dart)
* **Architectural Purpose:** Initializes the Flutter engine, enforces UI orientation constraints, sets up Dependency Injection via Provider, and boots the application.
* **Key Classes & Structure:**
  - `ContextDriveApp`: Root `StatelessWidget`.
* **Key Functions & Logic:**
  - `main()`: Calls `WidgetsFlutterBinding.ensureInitialized()`, locks screen orientation to landscape (`DeviceOrientation.landscapeLeft`, `DeviceOrientation.landscapeRight`), and wraps `ContextDriveApp` with a `MultiProvider`.
  - Registered Providers:
    1. `ChangeNotifierProvider(create: (_) => AppStateModel())`
    2. `Provider(create: (_) => GpsService())`
    3. `Provider(create: (_) => WeatherService())`
    4. `Provider(create: (_) => TimeContextService())`
    5. `ChangeNotifierProvider(create: (_) => CarlaDemoService())`
    6. `ChangeNotifierProvider(create: (_) => CarlaCameraStreamService())`
    7. `ChangeNotifierProxyProvider4<...>`: Injects dependencies into `RiskManager`.
* **Viva Note:** *Explain why MultiProvider is used here:* It enables a unidirectional data flow and clean separation of concerns, ensuring sensor services can be mocked easily during automated unit testing.

---

### 3.2 Deterministic Risk Engine Layer

#### [app/lib/engine/risk_engine.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/engine/risk_engine.dart)
* **Architectural Purpose:** The intellectual core of ContextDrive. A pure, side-effect-free expert system that evaluates a multimodal `ContextVector`, matches all applicable rule predicates, and deterministically outputs a structured `RiskAssessment`.
* **Design Philosophy:**
  - **100% Deterministic:** Same input vector always produces the exact same output.
  - **Explainable (XAI):** Generates `whatHappened`, `whyExplanation`, `recommendation`, and concrete `evidenceReasons`.
  - **Zero Black-Box:** No opaque neural network determines risk severity.
* **Key Classes:**
  - `_Candidate`: Internal representation of a matched rule (`severity`, `name`, `what`, `why`, `action`, `evidence`).
  - `RiskEngine`: Public engine class containing the evaluation logic.
* **Key Methods:**
  - `assessRisk(ContextVector context) -> RiskAssessment`:
    1. Audits input freshness and data quality (GNSS, camera perception, weather, solar time).
    2. Constructs environmental modifiers and advisories (Rain, Heavy Rain, Fog, Night, Dawn/Dusk).
    3. Evaluates 9 deterministic hazard rules:
       - **Rule 1 (Critical Hazard):** `veryNear && closingIn && hardBraking && adverse` -> `RiskLevel.critical`.
       - **Rule 2 (High Risk):** `veryNear && closingIn` -> `RiskLevel.high`.
       - **Rule 3 (High / Moderate):** `motion == hardBraking` (`High` if `near` vehicle exists, else `Moderate`).
       - **Rule 4 (High / Moderate):** `motion == rapidAcceleration` (`High` if speeding or poor visibility, else `Moderate`).
       - **Rule 5 (Moderate / Caution):** `isVisualApproachDeveloping` -> `RiskLevel.moderate`.
       - **Rule 6 (High / Moderate):** `near && closingIn` (`High` if `adverse`, else `Moderate`).
       - **Rule 7 (Moderate / Caution):** `veryNear && !closingIn` -> `RiskLevel.moderate`.
       - **Rule 8 (Moderate / Caution):** `speed > 80 km/h && poorVisibility` -> `RiskLevel.moderate`.
       - **Rule 9 (High / Moderate):** `speeding` (`High` if `excess > 20 km/h && adverse`, else `Moderate`).
    4. Sorts candidates by severity descending (`critical (3) > high (2) > moderate (1) > low (0)`).
    5. Returns the primary candidate, or baseline `RiskLevel.low` (`Monitoring`) if no rules matched.
  - `_severity(RiskLevel level) -> int`: Maps enum to integer rank (0 to 3).
* **Viva Note:** *Why are weather and night conditions treated as advisories rather than immediate hazards?* A wet road or darkness is an environmental context modifier, not an acute collision event. ContextDrive treats them as modifiers that elevate other dynamic hazards (e.g., speeding in rain elevates to `HIGH RISK`).

---

### 3.3 Stateful Orchestration & Perception Tracking

#### [app/lib/managers/risk_manager.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/managers/risk_manager.dart)
* **Architectural Purpose:** The central orchestration engine. Bridges async sensor streams, temporal tracking, CARLA telemetry, debounce timers, audio speech dispatch, and the risk engine.
* **Key Classes:**
  - `RiskConfirmationPolicy`: Computes event-specific confirmation debounce delays:
    - Critical / Close Optical Approach: `150 ms`.
    - Closing in near/adverse: `250 ms`.
    - Visual approach developing: `350 ms`.
    - Speeding / Motion rules: `500 ms`.
  - `RiskManager`: `ChangeNotifier` coordinating application state.
* **Key Methods:**
  - `start({required bool locationAvailable})`: Boots GNSS subscription, IMU service, and periodic 500 ms fallback evaluation timer.
  - `updateDetections(List<DetectedObject> detections, ...)`: Ingests raw YOLO bounding boxes, passes them to `ObjectTracker`, updates track list, and immediately triggers `_evaluateRisk()` without waiting for periodic timer.
  - `_evaluateRisk()`: Constructs current `ContextVector` (either from `_carlaContext()` or `_physicalContext()`), runs `_riskEngine.assessRisk()`, and passes result to `_applyAssessment()`.
  - `_trackState()`: Computes proximity proxy of closest vehicle, closing rate status, and developing approach flag.
  - `_persistMotion(MotionClassification candidate, DateTime now)`: Requires candidate motion (`hardBraking` or `rapidAcceleration`) to persist across telemetry packets for at least **350 ms** to eliminate physical noise/jitter.
  - `_applyAssessment(RiskAssessment next, DateTime now)`: Enforces confirmation policy timer. If candidate remains active across confirmation interval, promotes it to `_currentAssessment`, sets a 3-second cooldown, logs to recent alerts, and calls `_riskAlertService.announce()`.
  - `_setStaleCarlaAssessment()`: Safety fallback when CARLA simulation clock or telemetry disconnects (>1s timeout).
* **Viva Note:** *Why does confirmation delay vary by event?* An abrupt high-speed visual approach or hard braking demands rapid warning (150 ms), whereas a speed-limit violation benefits from a 500 ms debounce to prevent transient acceleration spikes from triggering nuisance alerts.

#### [app/lib/managers/object_tracker.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/managers/object_tracker.dart)
* **Architectural Purpose:** Converts frame-by-frame independent YOLO bounding boxes into persistent temporal tracks (`TrackedObject`) using greedy Intersection-over-Union (IoU) association.
* **Key Constants:**
  - `iouThreshold = 0.30`: Minimum bounding-box overlap required to match detections between consecutive frames.
  - `maxTrackAge = Duration(milliseconds: 1200)`: Track expiration window if unseen.
  - `maxMissedFrames = 5`: Missed detection tolerance to prevent UI flickering.
* **Key Methods:**
  - `updateTracks(List<DetectedObject> detections, ...)`: Matches incoming detections with existing tracks via highest IoU. Updates matched tracks; creates new tracks for unmatched detections.
  - `expireStale(DateTime now)`: Prunes tracks not seen for >1200 ms.
  - `_calculateIoU(Rect a, Rect b) -> double`: Computes `Intersection(a, b) / Union(a, b)`.
  - `reset()`: Clears all active tracks upon mode switch.

---

### 3.4 Domain Models & Data Structures

#### [app/lib/models/context_vector.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/context_vector.dart)
* **Architectural Purpose:** Defines data schemas, system thresholds, enumerations, and the assessment contract.
* **Key Enums:**
  - `WeatherCategory`: `unknown`, `clear`, `rain`, `heavyRain`, `fog`.
  - `DaylightCondition`: `unknown`, `day`, `dawnDusk`, `night`.
  - `VisibilityAssessment`: `poor` (<1000m or fog/heavy rain), `adequate`, `unknown`.
  - `MotionClassification`: `unknown`, `normal`, `hardBraking`, `rapidAcceleration`.
  - `RiskLevel`: `low` (0), `moderate` (1), `high` (2), `critical` (3).
  - `AssessmentDataQuality`: `good`, `limited`, `stale`.
* **Key Constants in `RiskThresholds`:**
  - `veryNearVisualProxy = 0.10`: Visual proxy equivalent to >40% screen area.
  - `nearVisualProxy = 0.30`: Visual proxy equivalent to >15% screen area.
  - `speedLimitModerateExcessKmh = 0.0`: Speed exceeds limit by >0 km/h.
  - `speedLimitHighExcessKmh = 20.0`: Significant speeding threshold.
  - `highSpeedPoorVisibilityKmh = 80.0`: High speed cutoff in poor visibility.
  - `hardBrakingMps2 = -3.5`: Longitudinal deceleration threshold in m/s².
  - `rapidAccelerationMps2 = 3.0`: Forward acceleration threshold in m/s².
  - `minimumMotionSpeedKmh = 5.0`: Minimum speed required to evaluate directional motion.
* **Key Classes:**
  - `ContextVector`: Immutable snapshot holding all fused inputs.
  - `MotionClassifier`: Static classifier for signed acceleration.
  - `RiskAssessment`: Complete explainable assessment output for HUD and TTS.

#### [app/lib/models/tracked_object.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/tracked_object.dart)
* **Architectural Purpose:** Encapsulates the multi-frame temporal state of an individual tracked road vehicle.
* **Key Constants:**
  - `approachAreaThreshold = 0.025`: 2.5% screen area minimum for visual approach.
  - `mediumAreaThreshold = 0.05`: 5% screen area.
  - `nearAreaThreshold = 0.15`: 15% screen area.
  - `veryNearAreaThreshold = 0.40`: 40% screen area.
  - `closingGrowthPerSecond = 0.15`: 15% bounding-box area expansion per second.
* **Key Methods:**
  - `updateWithDetection(DetectedObject detection, DateTime now)`: Applies Exponential Moving Average (EMA) box smoothing (`alpha = 0.45`):
    $$\text{box}_{t} = \text{box}_{t-1} \cdot (1 - \alpha) + \text{box}_{\text{YOLO}} \cdot \alpha$$
  - `_recordMeasurement(now)`: Maintains 1.5-second area history sliding window.
  - `_updateClosingRate()`: Computes relative optical expansion rate ($(\text{area}_2 / \text{area}_1 - 1) / \Delta t$) across history.
  - `isDevelopingApproach`: Getter returning true if track is consistently growing across >= 3 frames and exceeds 15% growth/sec.

#### [app/lib/models/detected_object.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/detected_object.dart)
* **Architectural Purpose:** Lightweight value object containing raw YOLO output bounding box (`Rect`), detection confidence (`double`), label (`String`), and classification (`RoadObjectType`).

#### [app/lib/models/risk_event.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/risk_event.dart)
* **Architectural Purpose:** Immutable record capturing an accepted alert (`level`, `reason`, `recommendation`, `evidence`, `timestamp`) for the session audit log.

#### [app/lib/models/app_state.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/models/app_state.dart)
* **Architectural Purpose:** App readiness state (`initializing`, `ready`, `modelFailed`, `cameraPermissionDenied`).

---

### 3.5 Multi-Modal Sensor & Network Services

#### [app/lib/services/carla_camera_stream_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/carla_camera_stream_service.dart)
* **Architectural Purpose:** High-throughput TCP server listening on port `8088`. Ingests virtual camera frames streamed from CARLA over USB via ADB port forwarding.
* **Binary Framing Protocol (`CDVF`):**
  - Bytes 0–3: Magic header `b'CDVF'` (ContextDrive Video Frame).
  - Bytes 4–5: Protocol Version (uint16, big-endian = `1`).
  - Bytes 6–9: JSON Metadata length (uint32, big-endian).
  - Bytes 10–13: JPEG Payload length (uint32, big-endian).
  - Bytes 14 to $14+M$: JSON metadata payload (`simulationTime`, `frame`, `fps`).
  - Bytes $14+M$ to End: JPEG image bytes.
* **Key Logic:**
  - Implements **frame dropping / queue bypass**: If on-device YOLO inference is currently processing a frame, newly arrived frames replace the pending slot rather than accumulating latency.

#### [app/lib/services/carla_demo_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/carla_demo_service.dart)
* **Architectural Purpose:** Lightweight HTTP server on port `8080`. Receives HTTP POST `/telemetry` payloads from CARLA rig or test scripts.
* **Key Logic:**
  - Parses JSON telemetry (`speedKmh`, `latitude`, `longitude`, `accelX/Y/Z`, `longitudinalAcceleration`, `scenarioContext`).
  - Implements **simulation watchdog timer (250 ms check)**:
    - If packets stop for >1s: transitions to `CarlaConnectionStatus.disconnected`.
    - If packets arrive but `simulationTime` does not advance for >1s: transitions to `CarlaConnectionStatus.paused`.
    - Normal operation: `CarlaConnectionStatus.active`.

#### [app/lib/services/gps_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/gps_service.dart)
* **Architectural Purpose:** Interfaces with smartphone GNSS hardware using `geolocator`. Filters stationary jitter, gates physically impossible readings, and provides validated speed readings.
* **Key Classes:**
  - `SpeedReading`: Immutable record (`valueKmh`, `isValid`, `timestamp`, `rejectionReason`).
  - `GpsService`: Core GNSS acquisition and sanitization service.
* **Key Methods & Algorithms:**
  - `Future<bool> requestPermission()`: Verifies system location services are enabled; queries and requests foreground location permissions; safely handles `denied` and `deniedForever`.
  - `Stream<Position> getPositionStream()`: Establishes a 1Hz continuous position update stream (`LocationAccuracy.high`, `distanceFilter: 0`) to feed the filtering pipeline.
  - `SpeedReading processPosition(Position position, {DateTime? currentTime})`: A multi-stage signal conditioning filter:
    1. **Negative Speed Gate:** Rejects readings where `position.speed < 0`.
    2. **Horizontal Accuracy Gate:** Rejects fixes with horizontal accuracy > 20.0 meters.
    3. **Speed Accuracy Gate:** Rejects fixes where speed accuracy estimate > 2.0 m/s.
    4. **Stale Timestamp Gate:** Discards fixes older than 2.0 seconds relative to current clock.
    5. **Physical Kinematic Plausibility Gate:** Computes apparent acceleration $\Delta v / \Delta t$ against the last accepted fix. If apparent acceleration exceeds $10.0\text{ m/s}^2$ (~1G, physically impossible for regular passenger cars), the fix is rejected as multipath GNSS teleportation.
    6. **Running 5-Sample Median Filter:** Maintains a sliding window of the last 5 valid speeds and selects the median value to eliminate transient sensor spikes.
    7. **Stationary Deadband Suppression:** Clamps median speeds below $3.0\text{ km/h}$ to exactly $0.0\text{ km/h}$ to prevent "GPS crawl" when parked or stopped at red lights.

#### [app/lib/services/imu_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/imu_service.dart)
* **Architectural Purpose:** Interfaces with smartphone accelerometer and gyroscope sensors via `sensors_plus`.
* **Key Classes & Methods:**
  - `ImuService`: Exposes `userAccelerometerEventStream` which provides linear acceleration in m/s² with gravity subtracted.
* **Crucial Architectural Safeguard (Viva High-Yield):**
  - *Why directional vehicle motion is NEVER inferred from the uncalibrated phone IMU:* The smartphone can be placed in arbitrary orientations (portrait, landscape, tilted in a cup holder, or shifted by hand). An uncalibrated consumer phone IMU cannot reliably distinguish forward braking from uphill tilting or smartphone handling. Therefore, directional vehicle motion ($a_{\text{long}}$) is strictly coupled to vehicle-aligned sensors (e.g., CARLA telemetry contract), guaranteeing zero false-positive braking alerts caused by phone movement.

#### [app/lib/services/weather_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/weather_service.dart)
* **Architectural Purpose:** REST client calling OpenWeatherMap API using current GPS coordinates to obtain macro-environmental atmospheric conditions.
* **Key Classes:**
  - `WeatherCondition`: Model containing `temperature`, `category` (`WeatherCategory`), `visibilityMeters`, `description`, `isAvailable`, `humidity`, and `windSpeedMps`. Includes `isRaining` getter (`category == rain || category == heavyRain`).
  - `WeatherService`: Caching HTTP client adapter.
* **Key Methods & Logic:**
  - `Future<WeatherCondition> getWeather(double latitude, double longitude, {bool forceRefresh = false})`:
    - Checks API key availability (`WEATHER_API_KEY`).
    - **15-Minute Cache Window:** Reuses cached weather if younger than 15 minutes and the vehicle is within 5,000 meters of the last query point.
    - **Backoff Retry Gate:** Enforces a 5-minute backoff if the previous API request failed to avoid exhausting API quotas.
    - **Request Deduplication:** Coalesces concurrent calls into a single in-flight `Future`.
  - `Future<WeatherCondition> _fetch(double latitude, double longitude)`: Issues HTTPS GET to `api.openweathermap.org/data/2.5/weather` with a strict 5-second timeout; parses JSON response and maps WMO weather codes.
  - `WeatherCategory _categoryFor(int? conditionId, String description)`: Deterministically classifies weather codes:
    - `200..232` (Thunderstorm) & `502..504` (Heavy rain): `WeatherCategory.heavyRain`.
    - `300..321` (Drizzle) & `500..501` (Rain): `WeatherCategory.rain`.
    - `701..741` (Mist, Smoke, Haze, Fog): `WeatherCategory.fog`.
    - Otherwise: `WeatherCategory.clear`.
  - `double _distanceMetres(...)`: Haversine formula computing distance between coordinate pairs to validate cache locality.

#### [app/lib/services/time_context_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/time_context_service.dart)
* **Architectural Purpose:** Calculates solar elevation angles and astronomical twilight based on coordinates and UTC timestamp to determine natural illumination conditions.
* **Key Methods & Logic:**
  - `void updateLocation(double lat, double lon)`: Computes astronomical sunrise and sunset UTC times using the `sunrise_sunset_calc` algorithm, converting to local system time.
  - `bool isNight(DateTime time)`: Compares local time against calculated sunrise and sunset. If solar calculation is unavailable, falls back to an 18:00–06:00 heuristic.
  - `DaylightCondition daylightCondition(DateTime time)`:
    - Evaluates a 30-minute twilight band before/after sunrise and sunset. If current time is within this window, returns `DaylightCondition.dawnDusk`.
    - If outside the twilight band, returns `DaylightCondition.night` or `DaylightCondition.day`.
    - Returns `DaylightCondition.unknown` if GPS coordinates are not yet available.
  - `bool isWeekend(DateTime time)`: Checks if current weekday is Saturday or Sunday.

#### [app/lib/services/speed_limit_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/speed_limit_service.dart)
* **Architectural Purpose:** Dynamic road speed-limit lookup service querying OpenStreetMap (OSM) via the Overpass API.
* **Key Methods & Logic:**
  - `Future<void> updateSpeedLimit(double lat, double lon)`:
    - Implements a 30-second rate-limiting throttle to avoid spamming public OSM Overpass servers.
    - Dispatches an Overpass QL query: `[out:json];way(around:30, lat, lon)["maxspeed"];out tags;` (searches for highways within a 30-meter radius).
    - Parses `maxspeed` tags, supporting both metric ("80", "50 km/h") and imperial ("50 mph" -> multiplied by 1.60934).
    - **2-Minute Invalidation:** If the vehicle leaves mapped areas or network drops for > 2 minutes, sets `_currentSpeedLimit = null` (falls back to configured baseline).

#### [app/lib/services/risk_alert_service.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/services/risk_alert_service.dart)
* **Architectural Purpose:** Manages acoustic voice speech generation via Android native Text-to-Speech (TTS) using a Flutter platform MethodChannel (`contextdrive/voice_alerts`).
* **Key Methods & Throttling Logic:**
  - `Future<void> announce(RiskAssessment assessment, {required bool enabled, bool force = false})`:
    - Drops calls if voice is disabled, assessment has no hazard, or telemetry is stale.
    - **Acoustic Throttling Cooldown:** Enforces a 6-second cooldown for `High`/`Critical` alerts and a 12-second cooldown for `Moderate` alerts to eliminate alert fatigue.
    - **Immediate Escalation Bypass:** Cooldown is immediately bypassed if the risk level escalates (e.g., `Moderate` -> `High`) or the hazard reason changes.
    - Extracts `recommendation` advice text to speak through TTS.
  - `Future<void> stop()`: Immediately interrupts active speech playback.
  - `void clearActiveAlert()`: Clears active alert state memory, allowing subsequent alerts to speak without suppression.
  - `int _severity(RiskLevel level)`: Helper mapping enum to numeric severity (0 to 3) for escalation comparison.

---

### 3.6 User Interface & Live HUD Components

#### [app/lib/ui/home_screen.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/home_screen.dart)
* **Architectural Purpose:** The primary live driving cockpit interface. Designed for glanceability, zero visual clutter, strict landscape operation, and responsive real-time updates.
* **Key State & Lifecycle Methods:**
  - `initState()` / `dispose()`: Attaches `WidgetsBindingObserver`, initializes camera stream service listener, locks screen to landscape.
  - `_startAppFlow()`: Sequentially requests camera/location runtime permissions, boots on-device YOLO edge engine, and initializes location services.
  - `_onCarlaStreamFrame()`: Callback triggered whenever `CarlaCameraStreamService` decodes a new TCP frame. Coordinates frame delivery to YOLO.
  - `_processCarlaFrame()`: Decodes JPEG image, feeds pixel buffer to LiteRT YOLO inference, transforms bounding boxes to normalized coordinates, and updates `RiskManager.updateDetections()`.
* **Key Sub-Widget Builders:**
  - `_buildSpeedDashboard()`: Displays large high-contrast digital speed readout (km/h), speed limit badge, weather glass pill (with animated rain/sun icon), daylight pill, and voice mute/unmute button.
  - `_buildRiskStatusRing()`: Dynamic hazard alert card:
    - Severity header with status icon (`MONITORING`, `CAUTION`, `HIGH RISK`, `CRITICAL HAZARD`).
    - Severity theme colors: Green (`LOW`), Orange (`MODERATE`), Red (`HIGH`), Deep Purple (`CRITICAL`).
    - Data quality badge (`STALE`, `LIMITED`, or none if `GOOD`).
    - `What happened: ...` (Primary factual hazard description in white).
    - `Advice: ...` (Actionable driver guidance in bold accent yellow).
    - Contextual advisory line (Environmental or traffic modifier).
    - Live Telemetry Tray (`X veh`, `Proximity: Very near/Near/Clear`, `Closing: YES/NO`, `GPS: OK`).
  - `_buildCameraFeed()`: Live video surface toggling between smartphone rear camera (via CameraX/Camera2) and CARLA virtual camera feed (port 8088).
  - `_buildBoundingBoxOverlays()`: Custom painter rendering tracked vehicle bounding boxes, track ID labels, and optical proximity reticles overlaid on video feed.
  - Top Navigation Bar: Displays Perception Mode toggle (`PHONE` / `CARLA`), connection status badge (`PHYSICAL`, `CARLA WAITING`, `CARLA ACTIVE`, `CARLA PAUSED`, `CARLA DISCONNECTED`), debug sheet icon, and history sheet icon.

#### [app/lib/ui/debug_settings_sheet.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/debug_settings_sheet.dart)
* **Architectural Purpose:** Modal slide-up sheet designed for evaluators and testing. Allows manual injection of speed overrides, speed limits, weather toggles, and live API diagnostics.
* **Key Methods:**
  - `_applySettings()`: Reads user slider and toggle positions and applies them to `RiskManager`:
    - Speed slider (0–150 km/h).
    - Speed limit selector (30, 40, 50, 60, 80, 100 km/h).
    - Rain toggle (`overrideIsRaining`).
    - Night toggle (`overrideIsNight`).
    - Erratic motion toggle (`overrideIsErratic`).
    - Triggers `riskManager.forceReevaluate()` and dismisses modal.
  - `_clearSettings()`: Clears all manual overrides, returning system to live hardware/CARLA sensor feeds.

#### [app/lib/ui/widgets/diagnostic_panel.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/lib/ui/widgets/diagnostic_panel.dart)
* **Architectural Purpose:** Floating live technical diagnostics widget displaying real-time edge AI metrics:
  - Neural inference latency (milliseconds).
  - Video pipeline throughput (Frames Per Second).
  - Active tracked vehicle count.
  - Memory and dropped frame statistics.

---

## 4. TIER 2: CARLA CYBER-PHYSICAL SIMULATION & TOOLING (PYTHON)

### 4.1 Manual Driving Rig & Hardware Simulation

#### [carla/manual_driving_rig.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/manual_driving_rig.py)
* **Architectural Purpose:** Interactive CARLA 0.9.16 driving simulation rig. Provides keyboard vehicle control, camera sensor mounting, ADB port forward management, JPEG video streaming over USB, and telemetry streaming over Wi-Fi.
* **Key Classes & Methods:**
  - `CameraManager`:
    - `__init__(ego_vehicle, hud, gamma_correction)`: Spawns CARLA RGB camera sensor (`sensor.camera.rgb`, 640x480 resolution at 30 FPS).
    - `set_sensor(index)`: Supports camera view cycling (Dashboard POV, Driver POV, Chase Cam).
    - `render(display)`: Blits camera frame to the local Pygame window.
  - `VirtualCameraStreamer`:
    - `__init__(port=8088)`: Initializes TCP server socket on port `8088`.
    - `_server_loop()`: Listens for incoming phone TCP connection (routed over USB via `adb reverse tcp:8088 tcp:8088`).
    - `send_frame(image_bytes, sim_time, frame_num)`: Formats frame into binary `CDVF` packet (14-byte header + JSON metadata + raw JPEG) and transmits over socket.
  - `_stream_worker()`: Background worker executing at 10 Hz:
    - Queries ego vehicle transform, velocity vector, and acceleration.
    - Computes signed longitudinal acceleration ($a_{\text{long}}$) via `motion_math.py`.
    - Formats JSON telemetry packet containing `speedKmh`, `latitude`, `longitude`, `accelX/Y/Z`, `longitudinalAcceleration`, `simulationTime`, `simulationFrame`.
    - Transmits payload via HTTP POST to `http://<phone_ip>:8080/telemetry`.
  - `main()`: Command-line entry point:
    - Parses arguments (`--host`, `--port`, `--stream`, `--phone`, `--stream-video`, `--video-port`, `--rain`, `--night`, `--visibility`).
    - Connects to CARLA World on port 2000; spawns hero vehicle (`vehicle.tesla.model3`).
    - Executes Pygame keyboard control loop (`W`=Throttle, `S`=Brake/Reverse, `A`/`D`=Steering, `Space`=Handbrake, `Tab`=Camera View, `Q`=Quit).

---

### 4.2 Vehicle Motion Mathematics

#### [carla/motion_math.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/motion_math.py)
* **Architectural Purpose:** Pure mathematical helper resolving CARLA's raw 3D Cartesian acceleration into vehicle-referenced signed longitudinal acceleration ($a_{\text{long}}$).
* **Key Function:**
  - `project_longitudinal_acceleration(accel, forward, velocity) -> float`:
    - Computes forward velocity component: $v_{\text{fwd}} = \mathbf{v} \cdot \mathbf{f} = v_x f_x + v_y f_y + v_z f_z$.
    - Determines motion sign: $\text{sign} = +1$ if $v_{\text{fwd}} \ge 0$, else $-1$.
    - Projects 3D acceleration onto forward unit vector: $a_{\text{proj}} = \mathbf{a} \cdot \mathbf{f} = a_x f_x + a_y f_y + a_z f_z$.
    - Returns signed longitudinal acceleration: $a_{\text{long}} = \text{sign} \cdot a_{\text{proj}}$.
* **Viva Note:** *Why is projection necessary?* CARLA's `ego.get_acceleration()` reports acceleration in global world coordinates ($X, Y, Z$). To evaluate braking vs acceleration, the vector must be projected onto the vehicle's forward vector ($\mathbf{f}$) and signed by travel direction.

---

### 4.3 Scenario Preparation Helpers

#### [carla/spawn_lead_vehicle.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/spawn_lead_vehicle.py)
* **Architectural Purpose:** Standalone scenario helper for repeatable evaluation. Locates the active hero vehicle in the simulation, steps along road lane waypoints to calculate a position exactly $D$ meters ahead in the same driving lane (default 35.0m), and spawns a stationary lead vehicle (`vehicle.nissan.patrol`) with handbrake engaged.
* **Key Functions:**
  - `get_hero_vehicle(world)`: Iterates world actors to find the vehicle with role `hero`.
  - `clear_lead_vehicles(world)`: Clears any previously spawned `lead_vehicle` or `target_dummy` actors to avoid simulation clutter.
  - `spawn_lead_vehicle(distance=35.0, vehicle_type='vehicle.nissan.patrol')`:
    - Gets road waypoint at hero vehicle's current location.
    - Projects $D$ meters ahead along road centerline using `hero_waypoint.next(distance)`.
    - Spawns target blueprint with role `lead_vehicle` and crimson paint.
    - Engages handbrake (`hand_brake=True, brake=1.0`) so the lead vehicle remains perfectly stationary.
  - `main()`: Command-line entry point supporting `--distance`, `--clear`, and `--vehicle`.

---

### 4.4 Telemetry Streaming & Test Controllers

#### [carla/carla_telemetry_streamer.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/carla_telemetry_streamer.py)
* **Architectural Purpose:** Headless telemetry streaming daemon for automated simulation runs without Pygame window.
* **Key Functions:**
  - `imu_callback(imu_measurement)`: Thread-safe callback capturing raw accelerometer readings from CARLA's `sensor.other.imu`.
  - `get_ego_vehicle(world, ego_id=None)`: Searches world for vehicle with role `hero` or `ego_vehicle`.
  - `stream_telemetry()`: Background HTTP POST loop streaming vehicle kinematics to the mobile device.

#### [carla/demo_controller.py](file:///c:/Users/chris/Documents/projects/ContextDrive/carla/demo_controller.py)
* **Architectural Purpose:** Command-line testing utility to send synthetic telemetry packets to verify phone app reception without launching CARLA.
* **Key Functions:**
  - `main()`: Keyboard loop mapping numbers 0–7 to predefined JSON scenario payloads (Normal Driving, Speeding, Rain, Erratic, Night, Reset).

---

---

## 5. TIER 3: AUTOMATED VERIFICATION TEST SUITES

Located in `app/test/`:

1. **[app/test/risk_engine_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart):**
   - Verifies all 9 deterministic risk rules, threshold boundaries, severity sorting, and advisory generation.
2. **[app/test/object_tracker_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart):**
   - Verifies Hungarian/greedy IoU matching, track smoothing, track expiration, and growth-rate calculation.
3. **[app/test/risk_confirmation_policy_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/risk_confirmation_policy_test.dart):**
   - Verifies event-specific debounce durations (150ms for optical approach, 500ms for speeding).
4. **[app/test/carla_camera_stream_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart):**
   - Verifies binary `CDVF` packet parsing, header extraction, and JPEG decoding.
5. **[app/test/carla_telemetry_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart):**
   - Verifies JSON telemetry contract, out-of-order packet rejection, and watchdog state transitions.
6. **[app/test/risk_manager_mode_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart):**
   - Verifies mode switching between Physical and CARLA simulation.
7. **[app/test/gps_service_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/gps_service_test.dart):**
   - Verifies GNSS speed parsing and stationary noise rejection.
8. **[app/test/risk_alert_service_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/risk_alert_service_test.dart):**
   - Verifies audio TTS speech throttling, escalation rules, and cooldown timers.
9. **[app/test/ui_verification_test.dart](file:///c:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart):**
   - Full widget tests verifying hazard cards, risk colors, speed readouts, and badge rendering.

---

## 6. COMPONENT INTERDEPENDENCY & DATA-FLOW MATRIX

```
+-----------------------------------+---------------------------------------------------------+
| Target Component                  | Imports From / Depends On                               |
+-----------------------------------+---------------------------------------------------------+
| app/lib/main.dart                 | home_screen.dart, all services & models                |
| app/lib/engine/risk_engine.dart   | context_vector.dart (Zero other dependencies!)         |
| app/lib/managers/risk_manager.dart| risk_engine.dart, object_tracker.dart, all services     |
| app/lib/managers/object_tracker.dart | detected_object.dart, tracked_object.dart             |
| app/lib/models/tracked_object.dart| detected_object.dart                                    |
| app/lib/ui/home_screen.dart       | risk_manager.dart, carla_camera_stream_service.dart     |
| carla/manual_driving_rig.py       | motion_math.py, CARLA Python API, Pygame                |
| carla/spawn_lead_vehicle.py       | CARLA Python API                                        |
+-----------------------------------+---------------------------------------------------------+
```

---

## 7. ESSENTIAL VIVA QUESTIONS & MODEL DEFENSE ANSWERS

### Q1: Why did you build a deterministic rule engine instead of training an End-to-End Deep Learning model for risk assessment?
**Model Answer:**  
> *"In safety-critical automotive systems (ISO 26262), predictability, explainability, and determinism are paramount. An end-to-end neural network is a black box that suffers from hallucination, distribution shift, and unexplainable failure modes. In ContextDrive, deep learning (YOLOv8) is strictly confined to where it excels—perception and bounding-box detection. Once perception outputs geometric objects, all risk decisions are evaluated by our deterministic expert rule engine (`RiskEngine`), which produces complete auditability, verifiable thresholds, and natural-language explanations (`whatHappened`, `whyExplanation`, `recommendation`)."*

### Q2: How does the system measure the distance to vehicles ahead using only a single smartphone camera?
**Model Answer:**  
> *"ContextDrive does not claim calibrated metric distance estimation from a monocular smartphone camera, as camera height, pitch angles, and focal length vary widely across vehicles. Instead, our system uses a mathematically honest **optical proximity proxy** derived from normalized bounding-box area ($A = W \times H$). Through `TrackedObject`, we compute the temporal growth rate of this area across consecutive frames ($(\Delta A / A_0) / \Delta t$). A rapid optical expansion rate indicates a closing vehicle, which allows us to trigger developing approach warnings reliably without claiming uncalibrated metric distance."*

### Q3: What is the purpose of the 14-byte binary header in the video streaming protocol?
**Model Answer:**  
> *"Streaming raw multipart HTTP or standard WebRTC introduces significant latency and memory overhead on a mobile device. We designed a lightweight binary framing protocol prefixed by `CDVF` (4 bytes magic header, 2 bytes version, 4 bytes metadata length, 4 bytes image length). This allows the mobile TCP receiver in `CarlaCameraStreamService` to read the exact byte lengths directly from the TCP socket buffer in constant time, discard obsolete queued frames if inference is busy, and decode JPEGs at up to 30 FPS with sub-50ms latency."*

### Q4: Why is signed longitudinal acceleration used instead of raw accelerometer magnitude?
**Model Answer:**  
> *"Raw Euclidean acceleration magnitude ($\sqrt{a_x^2 + a_y^2 + a_z^2}$) is always positive and includes gravitational acceleration and lateral cornering forces. It cannot distinguish between hard braking and hard acceleration. In `motion_math.py`, we project the vehicle's acceleration vector onto its heading vector and sign it based on forward travel direction. Negative values represent true longitudinal braking ($a_{\text{long}} \le -3.5\text{ m/s}^2$), while positive values represent forward throttle acceleration ($a_{\text{long}} \ge +3.0\text{ m/s}^2$)."*

### Q5: How does ContextDrive prevent alert fatigue and visual flickering?
**Model Answer:**  
> *"Through a four-layer mitigation pipeline: First, raw YOLO detections are smoothed across frames using an Exponential Moving Average filter (`alpha = 0.45`) in `TrackedObject`. Second, `ObjectTracker` tolerates up to 5 missed frames before destroying a track. Third, `RiskConfirmationPolicy` enforces event-specific debounce timers (150ms to 500ms) before any hazard is promoted to the UI. Fourth, `RiskAlertService` enforces a 6-to-12 second cooldown on TTS voice announcements, ensuring voice guidance is delivered only upon escalation or meaningful risk state changes."*
