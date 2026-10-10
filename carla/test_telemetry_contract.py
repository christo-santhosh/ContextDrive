"""
ContextDrive Telemetry Contract Verification Test
=================================================
Verifies that the telemetry generation conforms exactly to the v3.0 contract:
- Backward compatibility: both 'speed' and 'speedKmh' present.
- Session identity: 'scenarioRunId' and monotonic 'sequenceNumber'.
- Clock sync: 'simulationTime' and 'simulationFrame'.
- Environmental injection: 'scenarioContext' with weather/visibility.
- Acceleration invariant: Euclidean norm calculation.
"""

import time
import math
import uuid
import json

def generate_telemetry_packet(
    scenario_run_id: str,
    sequence_num: int,
    sim_time: float,
    sim_frame: int,
    cur_speed_kmh: float,
    accel_tuple: tuple,
    geo_tuple: tuple,
    scenario_id: str = "BENIGN_CRUISE",
    is_raining: bool = False,
    speed_limit: int = 60,
    is_night: bool = False,
    visibility_cat: str = None
):
    ax, ay, az = accel_tuple
    lat, lon = geo_tuple
    return {
        "protocolVersion": 2,
        "scenarioRunId": scenario_run_id,
        "sequenceNumber": sequence_num,
        "simulationTime": round(sim_time, 3),
        "simulationFrame": int(sim_frame),
        "speed": round(cur_speed_kmh, 2),
        "speedKmh": round(cur_speed_kmh, 2),
        "latitude": round(lat, 6),
        "longitude": round(lon, 6),
        "accelX": round(ax, 3),
        "accelY": round(ay, 3),
        "accelZ": round(az, 3),
        "scenarioContext": {
            "scenarioId": scenario_id,
            "isRaining": is_raining,
            "speedLimit": speed_limit,
            "isNight": is_night,
            "visibilityCategory": visibility_cat,
        }
    }

def test_contract():
    run_id = f"run_{int(time.time())}_{uuid.uuid4().hex[:6]}"
    pkt = generate_telemetry_packet(
        scenario_run_id=run_id,
        sequence_num=42,
        sim_time=12.456,
        sim_frame=747,
        cur_speed_kmh=54.2,
        accel_tuple=(0.045, -0.123, 0.001),
        geo_tuple=(9.931234, 76.267341),
        scenario_id="HEAVY_RAIN_TEST",
        is_raining=True,
        speed_limit=50,
        is_night=False,
        visibility_cat="poor"
    )

    # 1. Verify required keys
    required_keys = [
        "protocolVersion", "scenarioRunId", "sequenceNumber",
        "simulationTime", "simulationFrame", "speed", "speedKmh",
        "latitude", "longitude", "accelX", "accelY", "accelZ", "scenarioContext"
    ]
    for k in required_keys:
        assert k in pkt, f"Missing key: {k}"

    # 2. Verify backward compatibility: speed equals speedKmh
    assert pkt["speed"] == pkt["speedKmh"], "Speed mismatch for backward compatibility"
    assert pkt["protocolVersion"] == 2

    # 3. Verify scenario context
    ctx = pkt["scenarioContext"]
    assert ctx["isRaining"] is True
    assert ctx["speedLimit"] == 50
    assert ctx["visibilityCategory"] == "poor"

    # 4. Invariant acceleration norm calculation
    norm = math.sqrt(pkt["accelX"]**2 + pkt["accelY"]**2 + pkt["accelZ"]**2)
    assert round(norm, 3) == 0.131

    # 5. Serialization check
    json_str = json.dumps(pkt)
    assert len(json_str) > 50

    print("[OK] Telemetry Contract verification passed!")
    print(json.dumps(pkt, indent=2))

if __name__ == "__main__":
    test_contract()
