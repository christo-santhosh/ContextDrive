# ContextDrive MVP

ContextDrive is a mobile driver-assistance prototype utilizing real-time computer vision (TensorFlow Lite) to detect and track vehicles, calculate estimated proximity and closing rates, and perform risk assessments based on contextual factors like GPS speed and weather.

> [!WARNING]
> This application is a **prototype assistance tool**, not a certified safety system. Do not rely on this application to prevent collisions. Estimated visual proximity is not a substitute for physical distance measurements like radar or lidar.

## Supported Platform
- **Primary MVP Target:** Android physical devices (A14+ recommended)
- *iOS support is planned for future phases.*

## Required Permissions
- **Camera:** Required for real-time video stream processing.
- **Location (Foreground):** Required for GPS speed to inform risk rules.
- **Network/Internet:** Required to fetch live weather context.

## ML Model Details
- **Model:** Ultralytics YOLOv8 (yolo26n via ultralytics_yolo 0.6.15)
- **Input:** 640x640 RGB (variable based on YOLO export)
- **Labels:** 80 COCO classes. The system filters for vulnerable road users (person, bicycle) and road vehicles (car, truck, bus, motorcycle).

## How to Run

### Flutter App
1. Ensure a physical Android device is connected with USB Debugging enabled.
2. Navigate to the `app/` directory:
   ```bash
   cd app
   flutter pub get
   flutter run
   ```


## Configuration
- **Weather API Key:** (Optional) To use real OpenWeatherMap data instead of the fallback, supply an API key at build time. Note: if not supplied, the app will fall back to an 'unavailable' weather status, gracefully degrading the risk assessment.
  ```bash
  flutter run --dart-define=WEATHER_API_KEY=your_key_here
  ```
