# ContextDrive MVP

ContextDrive is an Android driver-assistance prototype that uses real-time YOLO26n computer vision to detect and track road vehicles, people, and bicycles; estimate relative visual proximity and approach; and perform explainable rule-based risk assessments using GPS speed and available weather context. Elevated-risk changes can trigger an Android text-to-speech warning and are retained in a short, in-memory session history.

> [!WARNING]
> This application is a **prototype assistance tool**, not a certified safety system. Do not rely on this application to prevent collisions. It uses relative bounding-box size and growth as visual cues, not physical distance measurements, radar, lidar, or time-to-collision estimates.

## Supported Platform
- **Primary MVP Target:** Android physical devices (A14+ recommended)
- *iOS support is planned for future phases.*

## Required Permissions
- **Camera:** Required for real-time video stream processing.
- **Location (Foreground):** Required for GPS speed to inform risk rules.
- **Network/Internet:** Required to fetch live weather context.

## ML Model Details
- **Model:** Ultralytics YOLO26n (`yolo26n` via `ultralytics_yolo`)
- **Input:** 640x640 RGB (variable based on YOLO export)
- **Labels:** 80 COCO classes. The system filters for vulnerable road users (person, bicycle) and road vehicles (car, truck, bus, motorcycle).
- **Risk outputs:** low, moderate, high, or limited-data status with the observed trigger, visual evidence, available context, a recommended action, and optional voice alerts.

## How to Run

### Flutter App
1. Ensure a physical Android device is connected with USB Debugging enabled.
2. Navigate to the `app/` directory:
   ```bash
   cd app
   flutter pub get
   flutter run
   ```

## Demo and Testing Guide

For the presentation script, device test plan, feature explanations, risk-rule
reference, and known limitations, see
[DEMO_AND_TESTING_GUIDE.md](DEMO_AND_TESTING_GUIDE.md).


## Configuration
- **Weather API Key:** (Optional) To use real OpenWeatherMap data instead of the fallback, supply an API key at build time. Note: if not supplied, the app will fall back to an 'unavailable' weather status, gracefully degrading the risk assessment.
  ```bash
  flutter run --dart-define=WEATHER_API_KEY=your_key_here
  ```
