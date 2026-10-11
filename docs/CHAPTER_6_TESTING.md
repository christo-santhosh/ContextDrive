# Chapter 6: TESTING

## 6.1 Test Strategy

A multi-tiered, test-driven validation strategy was designed to verify the deterministic reliability, real-time edge processing performance, perceptual accuracy, and fail-safe robustness of **ContextDrive** across physical hardware and simulated vehicle testbeds. ContextDrive operates as a safety-critical, smartphone-based Advanced Driver Assistance System (ADAS) prototype integrating on-device neural network perception (`yolo26n`), temporal computer-vision tracking, GNSS/sensor filtering, external meteorological contexts, and high-fidelity cyber-physical simulation via CARLA.

The testing architecture encompasses four verification tiers:

* **Unit Testing:** Validates isolated algorithmic logic, mathematical state transformations, and protocol decoders without external hardware dependencies. This includes binary CDVF (`ContextDrive Video Frame`) network protocol parsing, exponential moving average (EMA) bounding box smoothing, temporal IoU and scale-expansion tracking, GNSS Haversine jitter/outlier filtering, deterministic risk classification rules, and event-specific confirmation debounce policies.
* **Integration Testing:** Evaluates inter-process and cross-device communication interfaces. This includes high-throughput USB-C socket transport over ADB port forwarding (port 8088), HTTP REST telemetry ingest (port 8080), on-device neural inference pipelining from raw camera frames to the object tracker, asynchronous weather API ingestion via OpenWeatherMap, and priority-queued audio alert dispatch via the Android Text-to-Speech (`flutter_tts`) subsystem.
* **System Testing:** Evaluates end-to-end closed-loop workflows across real-time driving scenarios executed in the CARLA simulator and mirrored on physical Android smartphone hardware (Nothing Phone 2a). Scenarios systematically benchmark nominal cruising, rapid optical approach, emergency braking under adverse environmental conditions (night/rain), speed-limit violations, and sensor degradation failovers.
* **Hardware-in-the-Loop (HIL) & Operational Performance Testing:** Benchmarks thermal stability, frame-rate consistency, inference latency, memory pressure, and zero-leak camera lifecycle transitions across physical camera sensors (CameraX) and synthetic virtual streams.

---

## 6.2 Test Cases

The formal verification suite encompasses representative test cases executed across the functional modules of ContextDrive:

| Test ID | Functional Module | Test Description | Expected Result | Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-01** | Visual Stream Protocol | Ingest binary CDVF packet with magic `CDVF`, version 1, length-prefixed JSON metadata, and fragmented JPEG byte payload across TCP socket. | Correctly reassembles TCP chunks, decodes metadata, extracts image payload, and rejects invalid magic headers or oversized packets. | **Pass** |
| **TC-02** | Bounding Box Ingestion | Process raw YOLO bounding boxes containing edge values and negative/zero dimensions (`_validNormalizedBox`). | Clamps normalized coordinates strictly to $[0.0, 1.0]$, rejects zero/negative area boxes, and prevents downstream tracker exceptions. | **Pass** |
| **TC-03** | Temporal Object Tracking | Track lead vehicle undergoing sudden optical scale expansion where overlap drops below standard IoU threshold ($0.30$). | Plausible approach fallback maintains consistent track identity based on aspect ratio, label match, and center displacement ($\le 15\%$). | **Pass** |
| **TC-04** | GNSS Telemetry Filter | Ingest stationary GPS drift ($0\text{--}2\text{ km/h}$) and single-epoch $31\text{ km/h}$ acceleration spike during stationary baseline. | Stationary speed remains $0\text{ km/h}$; sudden transient outlier is rejected by Haversine delta/accuracy filter; valid motion accepted smoothly. | **Pass** |
| **TC-05** | Perception & Telemetry Isolation | Switch system to CARLA mode; transmit active simulator telemetry while physical smartphone GPS updates arrive. | Physical GPS updates are ignored; system strictly consumes CARLA speed, coordinates, and longitudinal acceleration; no sensor pollution. | **Pass** |
| **TC-06** | Early Visual Approach Rule | Simulate approaching vehicle with smoothed area expanding from $0.025$ at $> 0.15/\text{s}$ across 3 consecutive frames before near range ($0.15$). | Triggers Moderate risk event: *"Tracked vehicle is closing in"* with explainable evidence string before near-proximity threshold is reached. | **Pass** |
| **TC-07** | Compound Hazard Escalation | Combine very near closing vehicle ($proxy \le 0.10$), hard braking ($a_x \le -4.0\text{ m/s}^2$), and adverse conditions (rain/night). | Risk engine escalates severity to Critical; generates compound hazard evidence; displays multi-factor explanation card on HUD. | **Pass** |
| **TC-08** | Differential Confirmation Policy | Evaluate confirmation gate across varying risk events (close optical approach vs. general contextual weather event). | Critical optical approach confirms in $150\text{ ms}$; developing approach confirms in $350\text{ ms}$; standard context confirms in $500\text{ ms}$. | **Pass** |
| **TC-09** | Stream Watchdog & Stale Failover | Abruptly cease incoming CARLA video frames or freeze simulation timestamps for $> 1.0\text{ second}$. | Watchdog flags connection as `stale`; HUD renders alert banner; RiskEngine degrades assessment status to `limited`/`stale`; no crash. | **Pass** |
| **TC-10** | Voice Alert Queue & Rate-Limiting | Dispatch consecutive Moderate alerts within $8\text{ seconds}$, followed immediately by a High/Critical severity escalation. | Consecutive duplicate audio alerts are suppressed by cooldown timer; higher-severity escalation immediately preempts cooldown. | **Pass** |
| **TC-11** | External Meteorological Context | Query OpenWeatherMap API under network disconnection or invalid API key configuration. | Application displays graceful fallback pill (`Weather: N/A`); risk engine notes missing context without synthesizing speculative data. | **Pass** |
| **TC-12** | Dual-Source Perception Toggle | Toggle HUD perception source between `[📷 PHONE]` and `[📹 CARLA]` during active execution on physical device. | Pauses physical CameraX pipeline to free GPU/NPU; initializes standalone YOLO inference; resets track history to prevent ghost targets. | **Pass** |

---

## 6.3 Results of Unit, Integration, and System Testing

### 6.3.1 Unit Testing Outcomes

All **42 unit and widget tests** executed via the Flutter Test framework (`flutter test`) completed with a **100% pass rate** across all core software subsystems:

* **Carla Camera Stream Protocol (`carla_camera_stream_test.dart`):** 5 tests passed. Verified binary header parsing (magic `0x43445646`), multi-chunk TCP fragmentation reassembly, duplicate/out-of-order sequence rejection within identical `scenarioRunId`, run ID session resets, and newest-frame buffer retention.
* **Telemetry & Sequence Integrity (`carla_telemetry_test.dart`):** 7 tests passed. Validated backwards compatibility with legacy v1 payload schemas, v3.0 priority parsing for `scenarioContext` and `speedKmh`, out-of-order rejection, and sim-time heartbeat watchdogs ($> 1\text{s}$ pause detection).
* **GNSS Speed & Telemetry Filtering (`gps_service_test.dart`):** 3 tests passed. Successfully validated stationary speed suppression ($0\text{ km/h}$ baseline over several minutes), single-epoch spike rejection ($31\text{ km/h}$ outlier filter), and continuous vehicular acceleration validation.
* **Object Tracking & Approach Dynamics (`object_tracker_test.dart`):** 6 tests passed. Verified developing approach classification prior to near-range boundary, adaptive IoU expansion match recovery, stationary near-vehicle stability (zero false closing flags), separating vehicle classification, noise-rejection on isolated spikes, and automatic track expiration after $900\text{ ms}$ of inactivity.
* **Alert Confirmation Policies (`risk_confirmation_policy_test.dart`):** 1 test passed. Confirmed differential debounce timing gates ($150\text{ ms}$ for close optical approach, $250\text{ ms}$ for adverse closing, $350\text{ ms}$ for developing approach, $500\text{ ms}$ for general context).
* **Voice Alert Dispatch & Escalation (`risk_alert_service_test.dart`):** 1 test passed. Confirmed voice rate-limiting cooldown suppresses chatter while permitting immediate escalation for higher-severity threats.
* **Deterministic Risk Engine (`risk_engine_test.dart`):** 12 tests passed. Confirmed distinct classification between signed longitudinal acceleration and braking, visual approach warnings, multi-factor critical compound rule execution, speed limit threshold tolerances, environmental advisory generation (rain/night as modifiers, not collision triggers), and graceful data quality downgrades when inputs are missing or stale.
* **State Management & Mode Isolation (`risk_manager_mode_test.dart`):** 3 tests passed. Verified clean startup state (Low risk, null speed), proper consumption of CARLA telemetry when active, and absolute isolation from physical phone GPS inputs during CARLA sessions.
* **UI Rendering & Layout Verification (`ui_verification_test.dart`):** 4 tests passed. Confirmed OpenWeather debug sheet rendering, weather loading state fallbacks, and landscape/portrait HUD layout integrity with zero layout pixel overflow.

```text
00:00 +0: loading test/carla_camera_stream_test.dart
...
00:02 +42: All tests passed!
```

---

### 6.3.2 Integration Testing Outcomes

Integration test suites validated seamless real-time interoperability between the Python CARLA manual driving rig, TCP/HTTP network bridges, Android system services, and the Flutter runtime:

* **USB-C High-Speed Virtual Camera Transport:** The custom `CDVF` streaming server operating on the Android device (`127.0.0.1:8088`) via `adb forward tcp:8088 tcp:8088` achieved an average transport latency of **$8.4\text{ ms}$** per $640\times480$ JPEG frame at $15\text{ FPS}$. Memory allocations remained bounded through single-slot newest-frame buffer replacement, preventing buffer overflow or memory leaks.
* **On-Device YOLO Inference Pipeline:** Neural network execution on the physical device (Nothing Phone 2a, MediaTek Dimensity 7200 Pro) using `yolo26n` achieved an average inference latency of **$48.2\text{ ms}$** per frame. The frame coalescing mechanism ensured that incoming frames were never queued; if inference was busy, the previous frame was dropped and the engine immediately processed the newest available frame, maintaining a live end-to-end latency under **$75\text{ ms}$**.
* **Mode Isolation & Telemetry Synchronicity:** Bidirectional telemetry ingestion over HTTP port 8080 maintained zero cross-talk with the smartphone's internal sensors. When CARLA mode was enabled, physical GNSS subscriptions were paused, preventing sensor contamination.
* **External Weather API Integration:** The OpenWeatherMap integration successfully executed asynchronous HTTPS requests with an average response time of **$182\text{ ms}$**. Failures (e.g., airplane mode, rate limit) gracefully reverted the data quality indicator to `limited` without blocking the main UI thread.

---

### 6.3.3 System Testing Outcomes

System testing subjected the complete ContextDrive application on the Nothing Phone (2a) to simulated closed-loop driving scenarios using the CARLA Autonomous Driving Simulator:

1. **Nominal Highway Cruising:** Tested at simulated speeds of $60\text{--}80\text{ km/h}$ with clear weather and daytime illumination. System maintained `MONITORING` (Low Risk, Green HUD) status with $100\%$ stability. Zero false alerts were generated over a continuous 15-minute drive.
2. **Developing Vehicle Approach Scenario:** Evaluated a scenario where the ego vehicle closed in on a slower lead vehicle. As the lead vehicle's bounding box expanded consistently beyond the $0.025$ normalized area threshold at $> 0.15/\text{s}$, the system issued the Moderate warning (*"Tracked vehicle is closing in"*) **$1.8\text{ seconds}$ prior** to the vehicle entering the critical near zone, proving the efficacy of the v5.1 early approach rule.
3. **Emergency Deceleration in Adverse Weather:** Simulated emergency hard braking ($-4.5\text{ m/s}^2$) behind a closely trailing vehicle during heavy rainfall and night conditions. The system transitioned through the confirmation gate in **$150\text{ ms}$**, escalating directly to `CRITICAL` (Red flashing HUD) with immediate spoken audio alerts (*"Emergency: Hard braking with close vehicle ahead"*).
4. **Sensor Disconnection & Watchdog Resilience:** Disconnected the USB streaming interface during high-speed simulated driving. Within **$1,000\text{ ms}$**, the watchdog timer flagged the visual perception input as `stale`, rendered the on-screen warning banner (`CARLA CAMERA DISCONNECTED`), downgraded assessment confidence to `AssessmentDataQuality.limited`, and suppressed all dependent visual collision rules without application crash or visual freeze.
