"""
ContextDrive — CARLA Demo Controller
=====================================
This script runs on the laptop alongside CARLA. It sends simulated telemetry
to the ContextDrive app running on the phone over the local network.

Setup:
  1. Turn on your phone's Mobile Hotspot.
  2. Connect your laptop to the phone's hotspot.
  3. In the ContextDrive app, open Debug Settings and enable "CARLA Demo Mode".
  4. Run this script: python demo_controller.py

Usage:
  Press number keys to trigger scenarios:
    1 — Normal driving (LOW risk)
    2 — Speeding (MODERATE risk)
    3 — High speed in rain (MODERATE risk)
    4 — Erratic driving — no traffic (MODERATE risk)
    5 — Erratic driving in traffic (HIGH risk) — requires cars on CARLA screen
    6 — Night driving, fast (MODERATE risk)
    7 — Speeding in rain at night (MODERATE risk)
    0 — Reset all overrides (return to baseline)
    q — Quit

Requirements:
  pip install requests
"""

import requests
import sys
import time

# ── Configuration ──────────────────────────────────────────────────────────
# The phone's IP address when it hosts the hotspot.
# Common Android hotspot gateway IPs: 192.168.43.1 or 192.168.243.1
# Check your phone's hotspot settings if these don't work.
PHONE_IP = "192.168.43.1"
PHONE_PORT = 8080
BASE_URL = f"http://{PHONE_IP}:{PHONE_PORT}"

# ── Scenario Definitions ──────────────────────────────────────────────────
# Each scenario is a dict that maps directly to the ContextVector overrides.
# The phone camera + YOLO still runs independently for vehicle detection.

SCENARIOS = {
    "1": {
        "name": "Normal Driving (LOW)",
        "payload": {
            "speed": 45.0,
            "speedLimit": 60,
            "isErratic": False,
            "isRaining": False,
            "isNight": False,
        },
    },
    "2": {
        "name": "Speeding (MODERATE)",
        "payload": {
            "speed": 75.0,
            "speedLimit": 50,
            "isErratic": False,
            "isRaining": False,
            "isNight": False,
        },
    },
    "3": {
        "name": "High Speed in Rain (MODERATE)",
        "payload": {
            "speed": 85.0,
            "speedLimit": 60,
            "isErratic": False,
            "isRaining": True,
            "isNight": False,
        },
    },
    "4": {
        "name": "Erratic Driving — No Traffic (MODERATE)",
        "payload": {
            "speed": 50.0,
            "speedLimit": 60,
            "isErratic": True,
            "isRaining": False,
            "isNight": False,
        },
    },
    "5": {
        "name": "Erratic Driving in Traffic (HIGH) — Point camera at cars!",
        "payload": {
            "speed": 50.0,
            "speedLimit": 60,
            "isErratic": True,
            "isRaining": False,
            "isNight": False,
        },
    },
    "6": {
        "name": "Night Driving, Fast (MODERATE)",
        "payload": {
            "speed": 85.0,
            "speedLimit": 60,
            "isErratic": False,
            "isRaining": False,
            "isNight": True,
        },
    },
    "7": {
        "name": "Speeding + Rain + Night (MODERATE)",
        "payload": {
            "speed": 90.0,
            "speedLimit": 60,
            "isErratic": False,
            "isRaining": True,
            "isNight": True,
        },
    },
}


def check_connection():
    """Verify the phone is reachable and the CARLA server is active."""
    print(f"\n🔍 Checking connection to {BASE_URL}/status ...")
    try:
        resp = requests.get(f"{BASE_URL}/status", timeout=3)
        if resp.status_code == 200:
            data = resp.json()
            print(f"✅ Connected to {data.get('app', 'Unknown')} — mode: {data.get('mode', '?')}")
            return True
        else:
            print(f"❌ Phone responded with status {resp.status_code}")
            return False
    except requests.ConnectionError:
        print(f"❌ Cannot reach phone at {PHONE_IP}:{PHONE_PORT}")
        print("   Make sure:")
        print("   1. Laptop is connected to the phone's hotspot")
        print("   2. CARLA Demo Mode is enabled in the app")
        return False
    except requests.Timeout:
        print("❌ Connection timed out")
        return False


def send_telemetry(payload):
    """Send a telemetry payload to the phone."""
    try:
        resp = requests.post(
            f"{BASE_URL}/telemetry",
            json=payload,
            timeout=1,
        )
        return resp.status_code == 200
    except Exception as e:
        print(f"   ⚠️  Send failed: {e}")
        return False


def reset_overrides():
    """Clear all overrides on the phone, returning to real sensor mode."""
    try:
        resp = requests.post(f"{BASE_URL}/reset", timeout=1)
        return resp.status_code == 200
    except Exception as e:
        print(f"   ⚠️  Reset failed: {e}")
        return False


def print_menu():
    """Print the scenario selection menu."""
    print("\n" + "=" * 60)
    print("  ContextDrive — CARLA Demo Controller")
    print("=" * 60)
    print()
    for key, scenario in SCENARIOS.items():
        print(f"  [{key}]  {scenario['name']}")
    print()
    print("  [0]  Reset (clear all overrides)")
    print("  [q]  Quit")
    print()


def main():
    # Check connection first
    if not check_connection():
        print("\n💡 Tip: Update PHONE_IP at the top of this script if needed.")
        choice = input("\nRetry? (y/n): ").strip().lower()
        if choice != "y":
            sys.exit(1)
        if not check_connection():
            print("Still cannot connect. Exiting.")
            sys.exit(1)

    print_menu()

    while True:
        try:
            key = input("▶ Select scenario: ").strip().lower()
        except (KeyboardInterrupt, EOFError):
            print("\n\nExiting...")
            reset_overrides()
            break

        if key == "q":
            print("Resetting overrides and exiting...")
            reset_overrides()
            break

        if key == "0":
            if reset_overrides():
                print("   ✅ Overrides cleared — app is back to real sensors")
            continue

        if key in SCENARIOS:
            scenario = SCENARIOS[key]
            print(f"\n   🚗 Triggering: {scenario['name']}")
            payload = scenario["payload"]
            for field, value in payload.items():
                print(f"      {field}: {value}")

            if send_telemetry(payload):
                print("   ✅ Sent successfully")
            else:
                print("   ❌ Failed to send")
            print()
        else:
            print(f"   Unknown key: '{key}'. Use 1-7, 0, or q.")


if __name__ == "__main__":
    main()
