import cv2
import numpy as np
import tensorflow as tf

import time
import os

from context_extractor import DetectedObject, ObjectTracker, calculate_normalized_distance
from risk_engine import evaluate_risk, RiskLevel

# Constants
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(SCRIPT_DIR, "models/ssd_mobilenet_v2_fpnlite_320x320_coco17_tpu-8/saved_model")
INPUT_VIDEO = os.path.join(SCRIPT_DIR, "sample.mp4")
OUTPUT_VIDEO = os.path.join(SCRIPT_DIR, "output.mp4")
CONFIDENCE_THRESHOLD = 0.55

# Standard COCO 2017 IDs
COCO_CLASSES = {
    1: 'person',
    3: 'Vehicle',
    4: 'Vehicle',
    6: 'Vehicle',
    8: 'Vehicle'
}

def run_inference():
    if not os.path.exists(INPUT_VIDEO):
        print(f"ERROR: {INPUT_VIDEO} not found. Please place a sample driving video in the ml/ folder.")
        return

    print("Loading TF2 SavedModel (SSD MobileNet V2 FPN Lite)...")
    model = tf.saved_model.load(MODEL_PATH)
    infer = model.signatures['serving_default']

    tracker = ObjectTracker()
    cap = cv2.VideoCapture(INPUT_VIDEO)
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    orig_w  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(OUTPUT_VIDEO, fourcc, fps, (orig_w, orig_h))

    mock_speed_kmh = 65.0
    mock_is_raining = False
    mock_is_night = False

    print("Processing video...")
    frame_count = 0
    start_time = time.time()
    
    smoothed_distance = 1.0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
            
        frame_count += 1

        # TF2 OD models expect [1, height, width, 3] uint8 tensor
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        input_tensor = tf.convert_to_tensor(np.expand_dims(frame_rgb, 0), dtype=tf.uint8)

        # Run inference
        detections = infer(input_tensor)

        boxes = detections['detection_boxes'][0].numpy()
        classes = detections['detection_classes'][0].numpy()
        scores = detections['detection_scores'][0].numpy()

        detected_objects = []
        min_distance = 1.0
        closing_in = False

        for i in range(len(scores)):
            if scores[i] > CONFIDENCE_THRESHOLD:
                class_id = int(classes[i])
                
                if class_id in COCO_CLASSES:
                    class_name = COCO_CLASSES[class_id]
                    # boxes are [ymin, xmin, ymax, xmax]
                    obj = DetectedObject(None, class_name, boxes[i], scores[i])
                    detected_objects.append(obj)
                    
                    dist = calculate_normalized_distance(boxes[i])
                    if dist < min_distance:
                        min_distance = dist

        # Temporal smoothing to prevent flickering
        if min_distance < smoothed_distance:
            # React quickly to approaching objects
            smoothed_distance = 0.4 * smoothed_distance + 0.6 * min_distance
        else:
            # Recover slowly if detection drops for a frame (prevents flashing)
            smoothed_distance = 0.9 * smoothed_distance + 0.1 * min_distance

        # Track objects
        tracked_objects = tracker.update(detected_objects)

        # Check if any tracked object is closing in
        for obj in tracked_objects:
            if tracker.is_closing_in(obj.obj_id):
                closing_in = True
                break

        # Risk Engine uses smoothed distance
        assessment = evaluate_risk(smoothed_distance, closing_in, mock_speed_kmh, mock_is_raining, mock_is_night)

        # Draw overlays
        for obj in tracked_objects:
            ymin, xmin, ymax, xmax = obj.box
            
            # Convert normalized coordinates to pixel coordinates
            start_point = (int(xmin * orig_w), int(ymin * orig_h))
            end_point = (int(xmax * orig_w), int(ymax * orig_h))
            
            dist_text = f"Dist: {calculate_normalized_distance(obj.box):.2f}"
            label = f"{obj.class_name} [{obj.obj_id}] {dist_text}"

            cv2.rectangle(frame, start_point, end_point, (0, 255, 0), 2)
            cv2.putText(frame, label, (start_point[0], start_point[1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

        # Draw Risk Assessment Overlay
        risk_color = (0, 255, 0)
        if assessment.level == RiskLevel.HIGH:
            risk_color = (0, 0, 255) # BGR
        elif assessment.level == RiskLevel.MODERATE:
            risk_color = (0, 165, 255)
            
        # Draw a much smaller, less intrusive background box
        cv2.rectangle(frame, (10, orig_h - 60), (350, orig_h - 10), (0,0,0), -1)
        
        # Only show the risk level name in bold
        cv2.putText(frame, f"RISK: {assessment.level.name}", (20, orig_h - 35), cv2.FONT_HERSHEY_SIMPLEX, 0.7, risk_color, 2)
        
        # Show distance in smaller text
        cv2.putText(frame, f"Speed: {mock_speed_kmh}km/h | Dist: {smoothed_distance:.2f}", (20, orig_h - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

        # Write to file
        out.write(frame)

        # Display Live Preview
        # Resize preview window if it's too large for the screen
        preview_h = min(orig_h, 800)
        preview_w = int(orig_w * (preview_h / orig_h))
        preview_frame = cv2.resize(frame, (preview_w, preview_h))
        
        cv2.imshow('ContextDrive - Live Simulation (Press Q to quit)', preview_frame)
        
        # Wait 1ms and check if 'q' is pressed
        if cv2.waitKey(1) & 0xFF == ord('q'):
            print("Live simulation stopped early by user.")
            break

    cap.release()
    out.release()
    cv2.destroyAllWindows()
    elapsed = time.time() - start_time
    print(f"Processed {frame_count} frames in {elapsed:.2f} seconds.")
    print(f"Output saved to {OUTPUT_VIDEO}")

if __name__ == '__main__':
    run_inference()
