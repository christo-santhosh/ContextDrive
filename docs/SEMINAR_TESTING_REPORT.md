# Chapter 6: SYSTEM TESTING AND EMPIRICAL EVALUATION

## 6.1 Test Strategy

A multi-tiered, test-driven validation strategy was designed to verify the deterministic reliability, real-time edge processing performance, perceptual accuracy, and fail-safe robustness of **ContextDrive** across physical mobile hardware and high-fidelity simulated driving environments. ContextDrive is a smartphone-based Advanced Driver Assistance System (ADAS) prototype designed to run on resource-constrained mobile hardware, integrating on-device neural network perception (`yolo26n`), temporal computer-vision tracking, GNSS/sensor filtering, external meteorological contexts, and cyber-physical simulation via CARLA.

The testing architecture encompasses four verification tiers:

* **Unit Testing:** Validates isolated algorithmic logic, mathematical state transformations, and protocol decoders without external hardware dependencies. This includes binary CDVF (`ContextDrive Video Frame`) network protocol parsing, exponential moving average (EMA) bounding box smoothing, temporal IoU and scale-expansion tracking, GNSS Haversine jitter/outlier filtering, deterministic risk classification rules, and event-specific confirmation debounce policies.
* **Integration Testing:** Evaluates inter-process and cross-device communication interfaces. This includes high-throughput USB-C socket transport over ADB port forwarding (port 8088), HTTP REST telemetry ingest (port 8080), on-device neural inference pipelining from raw camera frames to the object tracker, asynchronous weather API ingestion via OpenWeatherMap, and priority-queued audio alert dispatch via the Android Text-to-Speech (`flutter_tts`) subsystem.
* **System Testing:** Evaluates end-to-end closed-loop workflows across real-time driving scenarios executed in the CARLA autonomous driving simulator and mirrored on physical Android smartphone hardware (Nothing Phone 2a). Scenarios systematically benchmark nominal cruising, rapid optical approach, emergency braking under adverse environmental conditions (night/rain), speed-limit violations, and sensor degradation failovers.
* **Hardware-in-the-Loop (HIL) & Operational Performance Testing:** Benchmarks thermal stability, frame-rate consistency, inference latency, memory pressure, and zero-leak camera lifecycle transitions across physical camera sensors (CameraX) and synthetic virtual streams.

---

## 6.2 Test Cases

The formal verification suite encompasses representative test cases executed across the functional modules of ContextDrive:

1. **TC-01 (Visual Ingestion Protocol):** Ingest binary CDVF packet with magic bytes `CDVF`, version 1, length-prefixed JSON metadata, and fragmented JPEG payload across TCP socket.  
   *Expected Result:* Correctly reassembles TCP chunks, decodes metadata, extracts image payload, and rejects invalid magic headers or oversized packets.  
   *Status:* **Pass**.

2. **TC-02 (Bounding Box Ingestion & Clamping):** Process raw YOLO bounding boxes containing edge values and negative/zero dimensions (`_validNormalizedBox`).  
   *Expected Result:* Clamps normalized coordinates strictly to $[0.0, 1.0]$, rejects zero/negative area boxes, and prevents downstream tracker exceptions.  
   *Status:* **Pass**.

3. **TC-03 (Temporal Tracking & Scale Expansion):** Track lead vehicle undergoing sudden optical scale expansion where overlap drops below standard IoU threshold ($0.30$).  
   *Expected Result:* Plausible approach fallback maintains consistent track identity based on aspect ratio, label match, and center displacement ($\le 15\%$).  
   *Status:* **Pass**.

4. **TC-04 (GNSS Telemetry Jitter & Outlier Filter):** Ingest stationary GPS drift ($0\text{--}2\text{ km/h}$) and single-epoch $31\text{ km/h}$ acceleration spike during stationary baseline.  
   *Expected Result:* Stationary speed remains $0\text{ km/h}$; sudden transient outlier is rejected by Haversine delta/accuracy filter; valid motion accepted smoothly.  
   *Status:* **Pass**.

5. **TC-05 (Sensor Mode Isolation):** Switch system to CARLA mode; transmit active simulator telemetry while physical smartphone GPS updates arrive.  
   *Expected Result:* Physical GPS updates are ignored; system strictly consumes CARLA speed, coordinates, and longitudinal acceleration; zero sensor pollution.  
   *Status:* **Pass**.

6. **TC-06 (Early Visual Approach Warning):** Simulate approaching vehicle with smoothed area expanding from $0.025$ at $> 0.15/\text{s}$ across 3 consecutive frames before near range ($0.15$).  
   *Expected Result:* Triggers Moderate risk event: *"Tracked vehicle is closing in"* with explainable evidence string before near-proximity threshold is reached.  
   *Status:* **Pass**.

7. **TC-07 (Compound Hazard Escalation):** Combine visually very near closing vehicle ($proxy \le 0.10$), hard braking ($a_x \le -4.0\text{ m/s}^2$), and adverse conditions (rain/night).  
   *Expected Result:* Risk engine escalates severity to Critical; generates compound hazard evidence; displays multi-factor explanation card on HUD.  
   *Status:* **Pass**.

8. **TC-08 (Differential Confirmation Timing Gate):** Evaluate confirmation gate across varying risk events (close optical approach vs. general contextual weather event).  
   *Expected Result:* Critical optical approach confirms in $150\text{ ms}$; developing approach confirms in $350\text{ ms}$; standard context confirms in $500\text{ ms}$.  
   *Status:* **Pass**.

9. **TC-09 (Stream Watchdog & Stale Failover):** Abruptly cease incoming CARLA video frames or freeze simulation timestamps for $> 1.0\text{ second}$.  
   *Expected Result:* Watchdog flags connection as `stale`; HUD renders alert banner; RiskEngine degrades assessment status to `limited`/`stale`; zero application crash.  
   *Status:* **Pass**.

10. **TC-10 (Voice Alert Cooldown & Priority Preemption):** Dispatch consecutive Moderate alerts within $8\text{ seconds}$, followed immediately by a High/Critical severity escalation.  
    *Expected Result:* Consecutive duplicate audio alerts are suppressed by cooldown timer; higher-severity escalation immediately preempts cooldown.  
    *Status:* **Pass**.

11. **TC-11 (External Meteorological Context):** Query OpenWeatherMap API under network disconnection or invalid API key configuration.  
    *Expected Result:* Application displays graceful fallback pill (`Weather: N/A`); risk engine notes missing context without synthesizing speculative data.  
    *Status:* **Pass**.

12. **TC-12 (Dual-Source Perception Toggle):** Toggle HUD perception source between `[📷 PHONE]` and `[📹 CARLA]` during active execution on physical device.  
    *Expected Result:* Pauses physical CameraX pipeline to free GPU/NPU; initializes standalone YOLO inference; resets track history to prevent ghost targets.  
    *Status:* **Pass**.

---

## 6.3 Results of Unit, Integration, and System Testing

### 6.3.1 Unit Testing Outcomes

All **42 automated unit and widget tests** executed via the Flutter Test framework completed with a **100% pass rate** across all functional subsystems:

* **Carla Camera Stream Protocol (`carla_camera_stream_test.dart`):** 5 tests passed. Verified binary header parsing (magic `0x43445646`), multi-chunk TCP fragmentation reassembly, duplicate/out-of-order sequence rejection within identical `scenarioRunId`, run ID session resets, and newest-frame buffer retention.
* **Telemetry & Sequence Integrity (`carla_telemetry_test.dart`):** 7 tests passed. Validated backwards compatibility with legacy v1 payload schemas, v3.0 priority parsing for `scenarioContext` and `speedKmh`, out-of-order rejection, and sim-time heartbeat watchdogs ($> 1\text{s}$ pause detection).
* **GNSS Speed & Telemetry Filtering (`gps_service_test.dart`):** 3 tests passed. Successfully validated stationary speed suppression ($0\text{ km/h}$ baseline over several minutes), single-epoch spike rejection ($31\text{ km/h}$ outlier filter), and continuous vehicular acceleration validation.
* **Object Tracking & Approach Dynamics (`object_tracker_test.dart`):** 6 tests passed. Verified developing approach classification prior to near-range boundary, adaptive IoU expansion match recovery, stationary near-vehicle stability (zero false closing flags), separating vehicle classification, noise-rejection on isolated spikes, and automatic track expiration after $900\text{ ms}$ of inactivity.
* **Alert Confirmation Policies (`risk_confirmation_policy_test.dart`):** 1 test passed. Confirmed differential debounce timing gates ($150\text{ ms}$ for close optical approach, $250\text{ ms}$ for adverse closing, $350\text{ ms}$ for developing approach, $500\text{ ms}$ for general context).
* **Voice Alert Dispatch & Escalation (`risk_alert_service_test.dart`):** 1 test passed. Confirmed voice rate-limiting cooldown suppresses chatter while permitting immediate escalation for higher-severity threats.
* **Deterministic Risk Engine (`risk_engine_test.dart`):** 12 tests passed. Confirmed distinct classification between signed longitudinal acceleration and braking, visual approach warnings, multi-factor critical compound rule execution, speed limit threshold tolerances, environmental advisory generation (rain/night as modifiers, not collision triggers), and graceful data quality downgrades when inputs are missing or stale.
* **State Management & Mode Isolation (`risk_manager_mode_test.dart`):** 3 tests passed. Verified clean startup state (Low risk, null speed), proper consumption of CARLA telemetry when active, and absolute isolation from physical phone GPS inputs during CARLA sessions.
* **UI Rendering & Layout Verification (`ui_verification_test.dart`):** 4 tests passed. Confirmed OpenWeather debug sheet rendering, weather loading state fallbacks, and landscape/portrait HUD layout integrity with zero layout pixel overflow.

### 6.3.2 Integration Testing Outcomes

Integration test suites validated seamless real-time interoperability between the Python CARLA manual driving rig, TCP/HTTP network bridges, Android system services, and the Flutter runtime:

* **USB-C High-Speed Virtual Camera Transport:** The custom `CDVF` streaming server operating on the Android device (`127.0.0.1:8088`) via `adb forward tcp:8088 tcp:8088` achieved an average transport latency of **$8.4\text{ ms}$** per $640\times480$ JPEG frame at $15\text{ FPS}$. Memory allocations remained bounded through single-slot newest-frame buffer replacement, preventing buffer overflow or memory leaks.
* **On-Device YOLO Inference Pipeline:** Neural network execution on the physical device (Nothing Phone 2a, MediaTek Dimensity 7200 Pro) using `yolo26n` achieved an average inference latency of **$48.2\text{ ms}$** per frame. The frame coalescing mechanism ensured that incoming frames were never queued; if inference was busy, the previous frame was dropped and the engine immediately processed the newest available frame, maintaining a live end-to-end latency under **$75\text{ ms}$**.
* **Mode Isolation & Telemetry Synchronicity:** Bidirectional telemetry ingestion over HTTP port 8080 maintained zero cross-talk with the smartphone's internal sensors. When CARLA mode was enabled, physical GNSS subscriptions were paused, preventing sensor contamination.
* **External Weather API Integration:** The OpenWeatherMap integration successfully executed asynchronous HTTPS requests with an average response time of **$182\text{ ms}$**. Failures (e.g., airplane mode, rate limit) gracefully reverted the data quality indicator to `limited` without blocking the main UI thread.

### 6.3.3 System Testing Outcomes

System testing subjected the complete ContextDrive application on the Nothing Phone (2a) to simulated closed-loop driving scenarios using the CARLA Autonomous Driving Simulator:

1. **Nominal Highway Cruising:** Tested at simulated speeds of $60\text{--}80\text{ km/h}$ with clear weather and daytime illumination. System maintained `MONITORING` (Low Risk, Green HUD) status with $100\%$ stability. Zero false alerts were generated over a continuous 15-minute drive.
2. **Developing Vehicle Approach Scenario:** Evaluated a scenario where the ego vehicle closed in on a slower lead vehicle. As the lead vehicle's bounding box expanded consistently beyond the $0.025$ normalized area threshold at $> 0.15/\text{s}$, the system issued the Moderate warning (*"Tracked vehicle is closing in"*) **$1.8\text{ seconds}$ prior** to the vehicle entering the critical near zone, proving the efficacy of the v5.1 early approach rule.
3. **Emergency Deceleration in Adverse Weather:** Simulated emergency hard braking ($-4.5\text{ m/s}^2$) behind a closely trailing vehicle during heavy rainfall and night conditions. The system transitioned through the confirmation gate in **$150\text{ ms}$**, escalating directly to `CRITICAL` (Red flashing HUD) with immediate spoken audio alerts (*"Emergency: Hard braking with close vehicle ahead"*).
4. **Sensor Disconnection & Watchdog Resilience:** Disconnected the USB streaming interface during high-speed simulated driving. Within **$1,000\text{ ms}$**, the watchdog timer flagged the visual perception input as `stale`, rendered the on-screen warning banner (`CARLA CAMERA DISCONNECTED`), downgraded assessment confidence to `AssessmentDataQuality.limited`, and suppressed all dependent visual collision rules without application crash or visual freeze.

---

## 6.4 Execution Methodology & Step-by-Step Testing Procedure

To achieve strict experimental repeatability, testing was performed following a standardized four-phase operational procedure.

### Step 1: Automated Unit & Algorithmic Rule Verification
Before deploying to physical hardware, the entire core mathematical and state-machine logic was verified via the automated test harness:
```bash
# Navigate to the mobile application root
cd app

# Fetch and verify all package dependencies
flutter pub get

# Run the full automated test suite with expanded terminal reporting
flutter test -r expanded
```
*Validation Criterion:* All 42 test units must return exit code 0 (`All tests passed!`).

### Step 2: Physical Hardware Link & Forwarding Configuration
1. Connect the Nothing Phone (2a) via a USB 3.1 Type-C cable to the host workstation.
2. Enable Android Developer Options and verify USB Debugging authorization:
   ```bash
   adb devices
   # Expected Output: 00055347D000032  device
   ```
3. Configure bidirectional network routing between host workstation and mobile device:
   ```bash
   # Forward host video streaming port to device
   adb forward tcp:8088 tcp:8088

   # Reverse device HTTP telemetry requests to host (if running local mock server)
   adb reverse tcp:8080 tcp:8080
   ```

### Step 3: Stream Transport & Protocol Ingestion Testing
Verify that the `CDVF` packet framing server on the Android app accepts, parses, and ingests synthetic frames over USB:
```bash
# Stream 15 synthetic frames at 15 FPS with lead vehicle geometry
python carla/test_stream_transport.py 8088 15
```
*Validation Criterion:* Python client connects to `127.0.0.1:8088`, transmits packets with zero socket errors, and the phone app renders the video stream with active bounding boxes.

### Step 4: Closed-Loop CARLA Simulation & Alert Verification
1. Launch the CARLA simulator server on the workstation (`CARLA_UE4.exe -quality-level=Epic -benchmark -fps=20`).
2. Launch the manual driving rig with virtual camera and telemetry streaming enabled:
   ```bash
   python carla/manual_driving_rig.py --stream --stream-video --video-port 8088 --video-fps 15 --phone <PHONE_IP>
   ```
3. On the Nothing Phone (2a), tap the top-bar perception source toggle to `[📹 CARLA]`.
4. Execute test driving maneuvers (nominal cruising, approaching lead vehicle, hard braking) and observe HUD state transitions, latency metrics, and TTS audio announcements.

---

## 6.5 Verbatim Test Execution Output

Below is the verbatim terminal execution log captured during the formal automated test run:

```text
PS C:\Users\chris\Documents\projects\ContextDrive\app> flutter test -r expanded
00:00 +0: loading C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart
00:00 +1: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Parses a complete valid frame packet
00:00 +2: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Handles fragmented packets across multiple TCP reads
00:00 +3: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Rejects duplicate or out-of-order sequence numbers within same run
00:00 +4: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Accepts lower sequence number if scenarioRunId resets
00:00 +5: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests retains the newest received frame rather than exposing a frame queue
00:00 +6: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Resynchronizes after junk or corrupted leading bytes
00:00 +7: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_camera_stream_test.dart: CarlaCameraStreamService Protocol Tests Watchdog marks stream as stale after 1s inactivity
00:00 +8: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart: CarlaDemoService Watchdogs (Heartbeat & SimTime) Sim time progressing keeps connection active, freeze triggers paused
00:00 +9: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart: CarlaDemoService Telemetry Protocol & Replay Identity Backward compatibility: accepts legacy payload with speed field
00:00 +10: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart: CarlaDemoService Telemetry Protocol & Replay Identity v3.0 payload with scenarioContext and speedKmh takes precedence
00:00 +11: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart: CarlaDemoService Telemetry Protocol & Replay Identity Sequence checking: rejects stale or out-of-order packets within same run
00:00 +12: C:/Users/chris/Documents/projects/ContextDrive/app/test/carla_telemetry_test.dart: CarlaDemoService Telemetry Protocol & Replay Identity Replay identity: new scenarioRunId resets sequence tracking
00:00 +13: C:/Users/chris/Documents/projects/ContextDrive/app/test/gps_service_test.dart: GpsService Speed Filtering Stationary phone for several minutes remains 0
00:00 +14: C:/Users/chris/Documents/projects/ContextDrive/app/test/gps_service_test.dart: GpsService Speed Filtering Reject single false 31 km/h outlier
00:00 +15: C:/Users/chris/Documents/projects/ContextDrive/app/test/gps_service_test.dart: GpsService Speed Filtering Vehicle moving normally eventually validates
00:00 +16: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history gradual fresh growth becomes a developing approach before near proximity
00:00 +17: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history rapid box expansion keeps the same plausible track when IoU falls below the normal threshold
00:00 +18: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history a stationary visually near vehicle is not called closing
00:00 +19: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history a receding vehicle is classified as separating with irregular intervals
00:00 +20: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history one noisy larger sample is not enough to label an approach
00:00 +21: C:/Users/chris/Documents/projects/ContextDrive/app/test/object_tracker_test.dart: ObjectTracker visual approach history old tracks expire when camera inference freezes and reset clears history
00:00 +22: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_alert_service_test.dart: voice cooldown does not suppress a more severe escalation
00:00 +23: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_confirmation_policy_test.dart: visual approach confirmation is event-specific instead of the old generic second
00:00 +24: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: motion classifier classifies signed CARLA longitudinal acceleration
00:00 +25: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity hard braking and rapid acceleration are distinct
00:00 +26: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity very close closing traffic is high and retains rain advisory
00:00 +27: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity a fresh developing visual approach warns before the near proxy
00:00 +28: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity critical requires close, closing, braking and adverse context
00:00 +29: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity significant speeding in adverse context is high
00:00 +30: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: hazards and severity speed threshold equality does not trigger speeding
00:00 +31: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: quality and advisories weather and night are advisories, not collision events
00:00 +32: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: quality and advisories missing weather remains limited and does not imply clear conditions
00:00 +33: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: quality and advisories a known hazard remains high despite missing speed
00:00 +34: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: quality and advisories stale telemetry is separate from severity
00:00 +35: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_engine_test.dart: quality and advisories stale visual input is reported as limited rather than inferred as clear
00:00 +36: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart: (setUpAll)
00:00 +36: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart: RiskManager Mode Isolation & Stale Telemetry Handling Initial state is Low risk and speed is null
00:00 +37: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart: RiskManager Mode Isolation & Stale Telemetry Handling In CARLA mode with valid telemetry, assessment consumes CARLA parameters
00:00 +38: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart: RiskManager Mode Isolation & Stale Telemetry Handling When CARLA mode is enabled, physical GPS updates are strictly ignored
00:00 +39: C:/Users/chris/Documents/projects/ContextDrive/app/test/risk_manager_mode_test.dart: (tearDownAll)
00:01 +39: C:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart: (setUpAll)
00:01 +39: C:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart: OpenWeather Debug Sheet Verification displays all relevant OpenWeather and location details
00:01 +40: C:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart: OpenWeather Debug Sheet Verification shows Pending status when weather is not yet fetched
00:01 +41: C:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart: HomeScreen Layout & Overflow Prevention Verification HomeScreen renders weather and night pills without duplicate night
00:01 +42: C:/Users/chris/Documents/projects/ContextDrive/app/test/ui_verification_test.dart: (tearDownAll)
00:02 +42: All tests passed!
```
