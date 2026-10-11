"""
Continuous synthetic stream to test Carla Virtual Camera display on Nothing Phone (2a).
Streams frames for N seconds and reports stats.
"""

import sys
import time
import socket
import struct
import json
import numpy as np
import cv2

def make_driving_frame(width=640, height=480, frame_idx=0):
    # Simulated driving perspective
    img = np.zeros((height, width, 3), dtype=np.uint8)
    
    # Sky (blue gradient)
    for y in range(int(height * 0.45)):
        img[y, :, 0] = int(220 + 35 * (y / (height * 0.45)))
        img[y, :, 1] = int(180 + 20 * (y / (height * 0.45)))
        img[y, :, 2] = 120
        
    # Road (dark asphalt)
    for y in range(int(height * 0.45), height):
        factor = (y - height * 0.45) / (height * 0.55)
        val = int(50 + 20 * factor)
        img[y, :, :] = (val, val, val)
        
    # Road lane lines
    horizon_y = int(height * 0.45)
    center_x = int(width * 0.5)
    
    # Center dashed lane line
    dash_cycle = (frame_idx * 5) % 40
    for y in range(horizon_y + 10, height, 40):
        actual_y = y + dash_cycle
        if actual_y < height:
            w_dash = max(2, int(6 * (actual_y - horizon_y) / (height * 0.55)))
            cv2.line(img, (center_x, actual_y), (center_x, min(height, actual_y + 20)), (255, 255, 255), w_dash)
            
    # Simulated lead vehicle (getting closer or moving slightly)
    # Oscillating scale to simulate approaching
    approach_cycle = (frame_idx % 90) / 90.0
    car_w = int(120 + 100 * approach_cycle)
    car_h = int(90 + 75 * approach_cycle)
    car_x = int(center_x - car_w / 2)
    car_y = int(height * 0.72 - car_h / 2)
    
    # Vehicle body (car rear profile)
    cv2.rectangle(img, (car_x, car_y + int(car_h * 0.3)), (car_x + car_w, car_y + car_h), (30, 30, 180), -1)
    # Cabin / roof
    cv2.rectangle(img, (car_x + int(car_w * 0.15), car_y), (car_x + int(car_w * 0.85), car_y + int(car_h * 0.45)), (40, 40, 160), -1)
    # Rear window
    cv2.rectangle(img, (car_x + int(car_w * 0.2), car_y + 4), (car_x + int(car_w * 0.8), car_y + int(car_h * 0.35)), (70, 70, 70), -1)
    # Tail lights
    cv2.rectangle(img, (car_x + 5, car_y + int(car_h * 0.45)), (car_x + int(car_w * 0.25), car_y + int(car_h * 0.65)), (0, 0, 240), -1)
    cv2.rectangle(img, (car_x + int(car_w * 0.75), car_y + int(car_h * 0.45)), (car_x + car_w - 5, car_y + int(car_h * 0.65)), (0, 0, 240), -1)
    # License plate
    cv2.rectangle(img, (car_x + int(car_w * 0.35), car_y + int(car_h * 0.7)), (car_x + int(car_w * 0.65), car_y + int(car_h * 0.85)), (240, 240, 240), -1)
    # Wheels
    cv2.rectangle(img, (car_x + 5, car_y + car_h - 10), (car_x + int(car_w * 0.2), car_y + car_h + 10), (20, 20, 20), -1)
    cv2.rectangle(img, (car_x + int(car_w * 0.8), car_y + car_h - 10), (car_x + car_w - 5, car_y + car_h + 10), (20, 20, 20), -1)

    # HUD text
    cv2.putText(img, f"CARLA VIRTUAL CAMERA - FRAME #{frame_idx}", (15, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
    cv2.putText(img, f"Sim Time: {frame_idx / 15.0:.1f}s | Lead Vehicle Approaching", (15, 55),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (200, 255, 200), 1)

    _, encoded = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return encoded.tobytes()

def run_stream(port=8088, duration_sec=15, fps=15):
    print(f"[STREAM] Connecting to 127.0.0.1:{port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.connect(('127.0.0.1', port))
    except Exception as e:
        print(f"[ERROR] Failed to connect: {e}")
        return False

    print(f"[OK] Connected! Streaming at ~{fps} FPS for {duration_sec} seconds...")
    run_id = f"test_run_{int(time.time())}"
    total_frames = int(duration_sec * fps)
    
    start_time = time.time()
    for i in range(1, total_frames + 1):
        jpeg_bytes = make_driving_frame(640, 480, i)
        meta = {
            "protocolVersion": 1,
            "scenarioRunId": run_id,
            "sequenceNumber": i,
            "simulationTime": round(i / fps, 3),
            "simulationFrame": i * 2,
            "width": 640,
            "height": 480,
            "format": "jpeg"
        }
        meta_bytes = json.dumps(meta).encode('utf-8')
        header = struct.pack('>4sHII', b'CDVF', 1, len(meta_bytes), len(jpeg_bytes))
        sock.sendall(header + meta_bytes + jpeg_bytes)
        
        if i % 15 == 0:
            print(f" -> Sent frame {i}/{total_frames} ({i/fps:.1f}s)")
            
        target_time = start_time + (i / fps)
        sleep_dur = target_time - time.time()
        if sleep_dur > 0:
            time.sleep(sleep_dur)
            
    print("[STREAM] Stream finished cleanly.")
    time.sleep(0.5)
    sock.close()
    return True

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8088
    dur = float(sys.argv[2]) if len(sys.argv) > 2 else 15
    run_stream(port=port, duration_sec=dur)
