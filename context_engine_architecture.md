# ContextDrive Engine Architecture & Alert System

> **Superseded for the active implementation:** this historical description
> documents the pre-v4, first-match `isErratic` design. The implemented policy,
> signed CARLA longitudinal acceleration contract, thresholds, and demo matrix
> are in [`docs/RISK_ENGINE_V4.md`](docs/RISK_ENGINE_V4.md). Do not use this
> document to make claims about current motion classification or risk rules.

This document outlines the end-to-end architecture of the ContextDrive safety engine, detailing how raw inputs are collected, processed into a Context Vector, evaluated for risk, and ultimately delivered as alerts to the driver.

---

## 1. Alerts and Notifications

The system delivers multimodal alerts (Visual Dashboard UI + Voice Text-to-Speech) based on a discrete hierarchy of risk levels. Voice alerts are strictly reserved for **High** and **Moderate** risk events and utilize a cooldown mechanism (6 seconds for High, 12 seconds for Moderate) to prevent auditory fatigue.

### 🔴 High Risk Alerts (Requires Immediate Attention)
*Triggers voice alert prefixed with: "High risk."*

*   **Erratic Driving in Traffic**
    *   **Conditions:** The IMU detects a high-G acceleration event (harsh braking, rapid swerving) **AND** the camera is actively tracking at least one nearby vehicle.
    *   **Voice Message:** "High risk. IMU driving event detected near other vehicles. Drive smoothly. Avoid sudden maneuvers."
*   **Tailgating & Closing Rapidly**
    *   **Conditions:** The visual distance proxy classifies the vehicle ahead as "Very Near" (bounding box occupies a massive portion of the frame) **AND** the closing rate proxy is true (the bounding box is expanding rapidly).
    *   **Voice Message:** "High risk. Vehicle ahead is very near and visually approaching. Increase following distance to maintain a safe gap."

### 🟡 Moderate Risk Alerts (Caution Advised)
*Triggers voice alert prefixed with: "Caution."*

*   **Isolated Erratic Driving**
    *   **Conditions:** The IMU detects an erratic driving event, but no vehicles are tracked nearby.
    *   **Voice Message:** "Caution. IMU driving event detected. Drive smoothly. Avoid sudden maneuvers."
*   **Approaching a Nearby Vehicle**
    *   **Conditions:** The vehicle ahead is "Near" (large bounding box) **AND** the gap is closing rapidly.
    *   **Voice Message:** "Caution. A vehicle is near and closing in. Check the road ahead and increase following distance if needed."
*   **Static Tailgating**
    *   **Conditions:** The vehicle ahead is "Very Near" (massive bounding box), but the gap is not actively closing.
    *   **Voice Message:** "Caution. A vehicle is very near. Increase following distance."
*   **High Speed in Poor Visibility**
    *   **Conditions:** The vehicle is traveling faster than 80 km/h **AND** poor visibility is detected (nighttime, raining, or visibility < 1000m).
    *   **Voice Message:** "Caution. High speed in poor visibility conditions. Reduce speed to match visibility conditions."
*   **Speeding**
    *   **Conditions:** GPS speed is >10 km/h over the known legal speed limit.
    *   **Voice Message:** "Caution. Speed limit exceeded by >10 km/h. Reduce your speed."

### ⚪ Limited & Low Risk (Status Indicators)
*No voice alerts triggered. Updates UI only.*

*   **Sensor Blackout (Limited Risk)**
    *   **Conditions:** GPS speed is unavailable, stale (>5 seconds old), or settling.
    *   **UI Status:** "Sensor data limited. Drive with caution."
*   **Normal Driving (Low Risk)**
    *   **Conditions:** None of the dangerous rules above are triggered. Speed is stable, distance is safe, IMU is smooth.
    *   **UI Status:** "Normal driving conditions."

---

## 2. Context Engine Complete Working

The `RiskEngine` does not process raw sensor data directly. Instead, it relies on an abstraction layer called the `ContextVector`. The pipeline operates in a continuous loop evaluated every 500 milliseconds:

### Step 1: Input Aggregation (The ContextVector)
The `RiskManager` continuously listens to all hardware and software services. Every 500ms, it compiles the latest data from the GPS, IMU, Weather API, Speed Limit API, and the YOLO Object Tracker into a single snapshot object known as the `ContextVector`.

### Step 2: Derived Context Computation
Before evaluating rules, the `RiskEngine` calculates composite boolean flags from the `ContextVector`:
*   `poorVisibility`: Evaluates to `true` if `isNight` is true, or if `isRaining` is true, or if `visibility` < 1000m.
*   `isVeryNear` / `isNear`: Evaluates visual distance proxies. If the closest vehicle's proximity index is $\le 0.1$, it is `isVeryNear`. If it is $\le 0.3$, it is `isNear`.
*   `isSpeeding`: Evaluates if current speed $>$ (speed limit + 10 km/h).

### Step 3: Hierarchical Risk Generation
Rather than outputting a continuous numerical percentage, the engine uses a deterministic, rule-based expert system (a decision hierarchy). It checks the highest-severity rules first (e.g., Erratic Driving in Traffic).
*   If a rule evaluates to `true`, the engine immediately locks in that `RiskLevel` and skips the remaining checks.
*   If no rules evaluate to `true`, it falls back to `RiskLevel.low`.

### Step 4: Alert Production
The engine returns a `RiskAssessment` object containing the `RiskLevel` and localized, explainable text (`howExplanation`, `whyExplanation`, `recommendation`). 
The `RiskManager` broadcasts this assessment to the UI (which changes color and text) and passes it to the `RiskAlertService`. The alert service checks if the severity is Moderate or High, checks if the cooldown timer has expired, and if so, invokes the native Text-to-Speech (TTS) engine to speak the warning aloud.

---

## 3. Inputs: Collection and Processing

ContextDrive fuses data from three main domains. Here is exactly how each input is sourced and processed before reaching the Context Engine.

### A. Telemetry Inputs (IMU & GPS)
*   **GPS Speed:** 
    *   *Source:* The device's native location services (via the `geolocator` package).
    *   *Processing:* The OS calculates speed using either Doppler shift from satellites or delta-distance over delta-time. The app receives speed in meters/second, converts it to km/h, and validates the reading. If the reading is stale (older than 5 seconds) or accuracy is too low, the speed is marked as `null`, triggering a "Limited Risk" sensor blackout state.
*   **Harsh Braking / Erratic Driving:**
    *   *Source:* The device's internal Accelerometer (via the `sensors_plus` package).
    *   *Processing:* The app listens to the `userAccelerometerEventStream`, which natively filters out the constant force of gravity, leaving only the pure linear acceleration of the phone in $m/s^2$.
    *   *Algorithm:* The service calculates the 3D magnitude of the acceleration vector using the Pythagorean theorem: $Magnitude = \sqrt{x^2 + y^2 + z^2}$. If this magnitude exceeds **4.5 $m/s^2$** (approximately 0.45 G-force—universally recognized as aggressive braking or swerving), the `isErratic` flag is set to `true` for a 3-second window.

### B. Vision Inputs (Camera + YOLO)
*   **Bounding Boxes & Vehicle Count:**
    *   *Source:* The rear camera feeds frames to the local YOLOv8n ONNX model.
    *   *Processing:* The model outputs bounding boxes for detected objects. The `ObjectTracker` uses an Intersection-over-Union (IoU) algorithm to assign stable IDs to vehicles across consecutive frames. The total number of `roadVehicle` tracks yields the `nearbyVehicles` count.
*   **Distance Proxy & Closing Rate:**
    *   *Source:* Mathematical analysis of the tracked bounding boxes.
    *   *Processing:* Because physical depth mapping from a single 2D camera is complex and uncalibrated across devices, ContextDrive uses a relative area proxy. 
        *   **Distance:** The larger the bounding box area relative to the screen size, the smaller the `proximity` value. A very small proximity value indicates the vehicle is very close.
        *   **Closing Rate:** By comparing the area of a specific vehicle's bounding box in the current frame to its area in the previous frames, the engine calculates the expansion rate. If the box is expanding rapidly, the `isClosingIn` flag is set to `true`.

### C. Environmental Inputs (APIs & System)
*   **Weather & Visibility:**
    *   *Source:* Open-Meteo API.
    *   *Processing:* The app sends the current GPS coordinates to the API periodically (every 30 minutes or on major location changes). The API returns precipitation status (setting `isRaining`) and atmospheric visibility in meters.
*   **Speed Limits:**
    *   *Source:* Overpass API (OpenStreetMap).
    *   *Processing:* The app queries OSM for the `maxspeed` tag of the road nearest to the current GPS coordinates.
*   **Day / Night:**
    *   *Source:* System Clock & Location.
    *   *Processing:* The `TimeContextService` calculates localized sunrise and sunset times based on the current GPS coordinates and system time to accurately set the `isNight` boolean.
