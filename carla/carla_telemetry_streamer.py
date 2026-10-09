"""
ContextDrive — CARLA Raw Telemetry Bridge
=========================================
This script bridges a live CARLA simulation with the ContextDrive app.
Strict compliance: Extracts ONLY physical sensor measurements (velocity, 
geolocation, raw acceleration) from the simulated ego vehicle.

It does NOT send boolean flags (isErratic, isRaining) or risk outcomes. 
The ContextDrive app receives this location and velocity, and queries 
OpenStreetMap and Open-Meteo on its own.

CARLA IMU vs Flutter userAccelerometerEventStream:
Flutter's `userAccelerometerEventStream` returns gravity-free linear 
acceleration in m/s^2. CARLA's `sensor.other.imu` returns acceleration 
in m/s^2, but INCLUDES gravity on the Z-axis (usually ~9.81). 
ContextDrive's RiskManager handles this by calculating the horizontal 
magnitude (X and Y only) to determine erratic driving, intentionally 
ignoring the Z-axis to maintain parity without requiring gravity-subtraction 
math on the Python side.
"""

import argparse
import sys
import time
import math
import requests
import threading

try:
    import carla
except ImportError:
    raise ImportError("CARLA module not found. Run this in your CARLA environment.")

# Global state for IMU reading
imu_lock = threading.Lock()
imu_initialized = False
latest_accel = {'x': 0.0, 'y': 0.0, 'z': 0.0, 'local_time': 0.0, 'sim_time': 0.0}

def imu_callback(imu_measurement):
    """Stores raw acceleration from CARLA's IMU sensor safely."""
    global imu_initialized
    accel = imu_measurement.accelerometer
    
    with imu_lock:
        latest_accel['x'] = accel.x
        latest_accel['y'] = accel.y
        latest_accel['z'] = accel.z
        latest_accel['local_time'] = time.monotonic()
        latest_accel['sim_time'] = imu_measurement.timestamp
        imu_initialized = True

def get_ego_vehicle(world, ego_id=None):
    """Finds the vehicle by explicit ID or role ('hero' / 'ego_vehicle')."""
    vehicles = world.get_actors().filter('vehicle.*')
    
    if ego_id is not None:
        for v in vehicles:
            if v.id == ego_id:
                return v
        return None

    for v in vehicles:
        if v.attributes.get('role_name') in ['hero', 'ego_vehicle']:
            return v
            
    return None

def validate_geolocation(map_name, geo):
    """Provides heuristic validation of the map's geolocation."""
    print(f"\n🌍 Validating Geolocation for map: {map_name}")
    print(f"   Coordinates: {geo.latitude:.6f}, {geo.longitude:.6f}")
    
    if abs(geo.latitude) < 0.1 and abs(geo.longitude) < 0.1:
        print("   ⚠️ WARNING: Coordinates are very close to (0, 0).")
        print("   This is only a heuristic, but often indicates the map is not georeferenced.")
        print("   ContextDrive will fetch real-world data (weather/speed limits) for the ocean.")
        print("   Please verify these coordinates match your intended real-world location.")
    else:
        print("   ✅ Coordinates appear to be away from (0, 0). Verify they match the intended region.\n")

def main():
    parser = argparse.ArgumentParser(description="CARLA to ContextDrive Telemetry Bridge")
    parser.add_argument('--host', default='192.168.43.1', help='IP address of the phone (ContextDrive app)')
    parser.add_argument('--port', type=int, default=8080, help='Port of the ContextDrive HTTP server')
    parser.add_argument('--rate', type=float, default=5.0, help='Target update rate in Hz')
    parser.add_argument('--ego-id', type=int, default=None, help='Explicit Actor ID of the ego vehicle to attach to')
    args = parser.parse_args()

    if args.rate <= 0:
        print("❌ Error: --rate must be strictly greater than zero.")
        sys.exit(1)

    base_url = f"http://{args.host}:{args.port}/telemetry"

    print("Connecting to CARLA server at localhost:2000...")
    try:
        client = carla.Client('localhost', 2000)
        client.set_timeout(5.0)
        world = client.get_world()
        carla_map = world.get_map()
    except RuntimeError as e:
        print(f"❌ Failed to connect to CARLA: {e}")
        sys.exit(1)
    
    ego_vehicle = get_ego_vehicle(world, args.ego_id)
    if not ego_vehicle:
        print("\n❌ Error: Could not find an ego vehicle in the simulation.")
        print("Ensure a vehicle with role_name='hero' or 'ego_vehicle' is spawned,")
        print("or specify the explicit actor ID using --ego-id.")
        sys.exit(1)
        
    print(f"✅ Found Ego Vehicle: {ego_vehicle.type_id} (ID: {ego_vehicle.id})")

    # Attach IMU
    imu_sensor = None
    try:
        blueprint_library = world.get_blueprint_library()
        imu_bp = blueprint_library.find('sensor.other.imu')
        transform = carla.Transform(carla.Location(x=0, y=0, z=0))
        imu_sensor = world.spawn_actor(imu_bp, transform, attach_to=ego_vehicle)
        imu_sensor.listen(lambda data: imu_callback(data))
    except Exception as e:
        print(f"❌ Failed to spawn or attach IMU sensor: {e}")
        if imu_sensor and imu_sensor.is_alive:
            try:
                imu_sensor.destroy()
            except Exception:
                pass
        sys.exit(1)
    
    print(f"✅ IMU attached. Streaming raw telemetry to {base_url} at target {args.rate} Hz...")

    last_loop_time = time.monotonic()
    try:
        while True:
            loop_start = time.monotonic()
            
            # Safely extract IMU snapshot under the same lock
            with imu_lock:
                initialized = imu_initialized
                accel_x = latest_accel['x']
                accel_y = latest_accel['y']
                accel_z = latest_accel['z']
                imu_local_time = latest_accel['local_time']
            
            # Wait for the first valid IMU sample
            if not initialized:
                time.sleep(0.1)
                continue
                
            # Detect stale IMU using local monotonic time
            if loop_start - imu_local_time > 2.0:
                sys.stdout.write(f"\r⚠️ IMU data is stale. Waiting for simulation to resume...        ")
                sys.stdout.flush()
                time.sleep(0.5)
                continue

            # 1. Raw Velocity
            vel = ego_vehicle.get_velocity()
            speed_kmh = math.sqrt(vel.x**2 + vel.y**2 + vel.z**2) * 3.6
            
            # 2. Raw Geolocation
            loc = ego_vehicle.get_location()
            geo = carla_map.transform_to_geolocation(loc)
            
            # Warn once about geolocation
            if not hasattr(validate_geolocation, "has_warned"):
                validate_geolocation(carla_map.name, geo)
                validate_geolocation.has_warned = True
            
            # 3. Payload Construction
            payload = {
                "speed": speed_kmh,          
                "latitude": geo.latitude,    
                "longitude": geo.longitude,  
                "accelX": accel_x, 
                "accelY": accel_y, 
                "accelZ": accel_z  
            }
            
            # Calculate actual loop rate
            dt = loop_start - last_loop_time
            actual_rate = 1.0 / dt if dt > 0 else 0
            last_loop_time = loop_start

            # 4. Transmission
            try:
                resp = requests.post(base_url, json=payload, timeout=0.1)
                if 200 <= resp.status_code < 300:
                    sys.stdout.write(f"\r🚗 Spd: {payload['speed']:.1f} km/h | Lat: {payload['latitude']:.4f} | AccX: {payload['accelX']:.1f} | Rate: {actual_rate:.1f}Hz    ")
                else:
                    sys.stdout.write(f"\r⚠️ HTTP {resp.status_code}: {resp.text[:30]}                          ")
                sys.stdout.flush()
            except requests.exceptions.RequestException as e:
                sys.stdout.write(f"\r❌ Connection failed: {e.__class__.__name__}                        ")
                sys.stdout.flush()

            # Sleep to maintain target rate
            elapsed = time.monotonic() - loop_start
            sleep_time = max(0, (1.0 / args.rate) - elapsed)
            time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\n\nStopping streamer...")
    except Exception as e:
        print(f"\n\nFatal error: {e}")
    finally:
        print("Cleaning up sensors...")
        if imu_sensor:
            try:
                if imu_sensor.is_alive:
                    imu_sensor.destroy()
                    print("✅ IMU sensor destroyed.")
            except Exception as e:
                print(f"⚠️ Failed to destroy IMU sensor cleanly: {e}")
        print("Done.")

if __name__ == '__main__':
    main()
