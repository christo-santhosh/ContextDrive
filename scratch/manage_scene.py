import sys
import glob
import math

for w in glob.glob(r'C:\Users\chris\Downloads\Compressed\CARLA_0.9.16\PythonAPI\carla\dist\*.whl'):
    sys.path.append(w)

import carla

def get_client_and_world():
    client = carla.Client('localhost', 2000)
    client.set_timeout(5.0)
    world = client.get_world()
    return client, world

def get_ego(world):
    heroes = [v for v in world.get_actors().filter('vehicle.*') if v.attributes.get('role_name') == 'hero']
    if heroes:
        return heroes[0]
    return None

def spawn_ahead(distance=12.0):
    client, world = get_client_and_world()
    ego = get_ego(world)
    if not ego:
        print("Ego vehicle not found")
        return None
    
    # Remove any existing spawned target cars
    for a in world.get_actors().filter('vehicle.*'):
        if a.attributes.get('role_name') == 'target_dummy':
            try:
                a.destroy()
                print("Destroyed existing target_dummy")
            except Exception:
                pass

    t = ego.get_transform()
    fwd = t.get_forward_vector()
    target_loc = carla.Location(
        x=t.location.x + fwd.x * distance,
        y=t.location.y + fwd.y * distance,
        z=t.location.z + 0.3
    )
    target_rot = carla.Rotation(pitch=t.rotation.pitch, yaw=t.rotation.yaw, roll=t.rotation.roll)
    target_transform = carla.Transform(target_loc, target_rot)

    bp = world.get_blueprint_library().find('vehicle.audi.tt')
    bp.set_attribute('role_name', 'target_dummy')
    if bp.has_attribute('color'):
        bp.set_attribute('color', '255,0,0')

    npc = world.try_spawn_actor(bp, target_transform)
    if npc:
        print(f"Spawned {npc.type_id} (ID: {npc.id}) {distance}m ahead of ego.")
        return npc.id
    else:
        print("Failed to spawn vehicle directly ahead, trying slightly further...")
        target_loc.z += 0.5
        target_transform.location = target_loc
        npc = world.try_spawn_actor(bp, target_transform)
        if npc:
            print(f"Spawned {npc.type_id} (ID: {npc.id}) with z offset.")
            return npc.id
        print("Could not spawn vehicle.")
        return None

def clear_dummies():
    client, world = get_client_and_world()
    count = 0
    for a in world.get_actors().filter('vehicle.*'):
        if a.attributes.get('role_name') == 'target_dummy':
            try:
                a.destroy()
                count += 1
            except Exception:
                pass
    print(f"Cleared {count} dummy vehicles.")

def set_weather(mode):
    client, world = get_client_and_world()
    if mode == "rain":
        w = carla.WeatherParameters(
            cloudiness=90.0,
            precipitation=85.0,
            precipitation_deposits=80.0,
            wind_intensity=60.0,
            sun_azimuth_angle=0.0,
            sun_altitude_angle=45.0,
            fog_density=20.0,
            fog_distance=10.0,
            wetness=85.0
        )
        world.set_weather(w)
        print("Set CARLA weather to Heavy Rain")
    elif mode == "night":
        w = carla.WeatherParameters(
            cloudiness=20.0,
            precipitation=0.0,
            sun_altitude_angle=-40.0,
            sun_azimuth_angle=0.0
        )
        world.set_weather(w)
        print("Set CARLA weather to Night")
    elif mode == "clear":
        world.set_weather(carla.WeatherParameters.ClearNoon)
        print("Set CARLA weather to ClearNoon")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "spawn":
        dist = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
        spawn_ahead(dist)
    elif cmd == "clear":
        clear_dummies()
    elif cmd == "weather":
        mode = sys.argv[2] if len(sys.argv) > 2 else "clear"
        set_weather(mode)
    elif cmd == "status":
        _, world = get_client_and_world()
        ego = get_ego(world)
        if ego:
            v = ego.get_velocity()
            speed = 3.6 * math.sqrt(v.x**2 + v.y**2 + v.z**2)
            print(f"Ego ID {ego.id}, Speed: {speed:.1f} km/h, Location: {ego.get_transform().location}")
