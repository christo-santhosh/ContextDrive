import subprocess
import time

ADB = r"C:\Users\chris\AppData\Local\Android\Sdk\platform-tools\adb.exe"

def main():
    print("Starting continuous stream process...")
    proc = subprocess.Popen(["python", "carla/stream_test_continuous.py", "8088", "15"])
    time.sleep(4)
    print("Capturing screencap while stream is live...")
    subprocess.run([ADB, "shell", "screencap", "-p", "/sdcard/stream_live.png"], check=True)
    subprocess.run([ADB, "pull", "/sdcard/stream_live.png", r"C:\Users\chris\.gemini\antigravity-ide\brain\2fce39b8-5361-4adc-acb9-f2c137160e6e\scratch\phone_streaming_live.png"], check=True)
    print("Screencap captured! Waiting for stream process to finish...")
    proc.wait()
    print("Finished successfully!")

if __name__ == "__main__":
    main()
