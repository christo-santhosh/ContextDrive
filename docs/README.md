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
- **Model:** SSD MobileNet V2 (COCO trained)
- **Input:** 320x320 RGB `uint8`
- **Output:** 
  - `detection_boxes`: [1, 100, 4] (normalized [ymin, xmin, ymax, xmax])
  - `detection_classes`: [1, 100] (1-indexed COCO classes)
  - `detection_scores`: [1, 100] (confidence 0.0 - 1.0)
  - `num_detections`: [1] (number of valid detections)
- **Labels:** 90 COCO classes (1-indexed). The system filters for road vehicles (car, truck, bus, motorcycle).

## How to Run

### Flutter App
1. Ensure a physical Android device is connected with USB Debugging enabled.
2. Navigate to the `app/` directory:
   ```bash
   cd app
   flutter pub get
   flutter run
   ```

To run the offline Python prototype on an MP4 video file (place a `sample.mp4` in the `ml/` directory):
```bash
cd ml
pip install -r requirements.txt
python process_video.py
```

### Regenerating the TFLite Model
The TensorFlow model conversion script is in the `ml/` directory.
```bash
cd ml
python convert_to_tflite.py
```
This will produce a new `detect.tflite` model. Copy it to `app/assets/`.

## Configuration
- **Weather API Key:** (Optional) To use real OpenWeatherMap data instead of the fallback, supply an API key at build time. Note: if not supplied, the app will fall back to mocked 'clear sky' data.
  ```bash
  flutter run --dart-define=WEATHER_API_KEY=your_key_here
  ```
