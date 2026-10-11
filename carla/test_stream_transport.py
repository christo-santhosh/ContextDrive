"""
ContextDrive — Virtual Camera Stream Protocol Test
Sends test frames matching the CDVF protocol to verify USB/network transport.
"""

import sys
import time
import socket
import struct
import json
import numpy as np
import cv2

def create_synthetic_frame(width=640, height=480, frame_num=1):
    # Create an RGB image with gradient and text
    img = np.zeros((height, width, 3), dtype=np.uint8)
    # Gradient background
    for y in range(height):
        img[y, :, 0] = int(255 * (y / height))
        img[y, :, 1] = int(120 * (1.0 - y / height))
        img[y, :, 2] = 200

    # Draw simulated road & vehicle block
    cv2.rectangle(img, (int(width * 0.35), int(height * 0.5)), (int(width * 0.65), int(height * 0.85)), (0, 0, 220), -1)
    cv2.putText(img, f"CARLA VIRTUAL CAM - FRAME {frame_num}", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

    _, encoded = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 75])
    return encoded.tobytes()

def ensure_adb_forward(port=8088):
    import shutil
    import subprocess
    import os
    adb_path = shutil.which("adb")
    if not adb_path:
        for candidate in [
            r"C:\Users\chris\AppData\Local\Android\Sdk\platform-tools\adb.exe",
            os.path.expanduser(r"~\AppData\Local\Android\Sdk\platform-tools\adb.exe"),
        ]:
            if os.path.isfile(candidate):
                adb_path = candidate
                break
    if adb_path:
        try:
            subprocess.run([adb_path, "forward", f"tcp:{port}", f"tcp:{port}"],
                           capture_output=True, timeout=3.0)
        except Exception:
            pass

def send_test_stream(port=8088, num_frames=10, fps=15):
    ensure_adb_forward(port)
    print(f"[TEST] Connecting to 127.0.0.1:{port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.connect(('127.0.0.1', port))
    except Exception as e:
        print(f"[ERROR] Could not connect to 127.0.0.1:{port}: {e}")
        print("Ensure 'adb forward tcp:8088 tcp:8088' is run and app stream server is active.")
        return False

    print(f"[OK] Connected! Streaming {num_frames} frames at ~{fps} FPS...")
    run_id = f"test_run_{int(time.time())}"

    for i in range(1, num_frames + 1):
        jpeg_bytes = create_synthetic_frame(640, 480, i)
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
        print(f" -> Sent frame {i}/{num_frames} (meta: {len(meta_bytes)} B, image: {len(jpeg_bytes)} B)")
        time.sleep(1.0 / fps)

    sock.close()
    print("[OK] Test stream complete.")
    return True

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8088
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    send_test_stream(port=port, num_frames=frames)
