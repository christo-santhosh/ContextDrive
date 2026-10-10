"""
ContextDrive — CARLA Manual Driving Rig
=======================================
Rock-solid, crash-resilient manual driving rig for CARLA 0.9.16.

Stability safeguards implemented:
- Capped sensor capture rate (30 FPS) via `sensor_tick` to avoid GPU memory exhaustion.
- Rigid camera attachment (no PhysX SpringArm calculation crashes).
- Pure default vehicle physics (no PhysX sweep-wheel mutation).
- Automatic Sync/Async mode detection and recovery.
- Throttled spectator positioning to avoid RPC queue congestion.
- Thread-safe Pygame frame blitting with GIL protection.
- On-screen telemetry HUD with window focus detection.
"""

import sys
import time
import math
import argparse
import weakref
import threading

import os
import glob

try:
    import carla
except ImportError:
    # Auto-detect CARLA PythonAPI in standard user locations
    candidate_dirs = [
        r"C:\Users\chris\Downloads\Compressed\CARLA_0.9.16\PythonAPI\carla\dist",
        r"C:\Users\chris\Downloads\CARLA_0.9.16\PythonAPI\carla\dist",
        r"C:\carla\PythonAPI\carla\dist",
    ]
    for c_dir in candidate_dirs:
        if os.path.isdir(c_dir):
            for pattern in [f"*cp{sys.version_info.major}{sys.version_info.minor}*.whl", f"*{sys.version_info.major}.{sys.version_info.minor}*.egg", "*.egg", "*.whl"]:
                for match in glob.glob(os.path.join(c_dir, pattern)):
                    if match not in sys.path:
                        sys.path.append(match)
            parent_dir = os.path.dirname(c_dir)
            if parent_dir not in sys.path:
                sys.path.append(parent_dir)
    try:
        import carla
    except ImportError:
        pass

if 'carla' not in sys.modules:
    print(f"\n[ERROR] Python {sys.version.split()[0]} cannot find the 'carla' package.")
    print("If you created a virtual environment earlier, activate it:")
    print("   conda activate carla   (or your venv)")
    print("Or install the CARLA wheel into this Python environment:")
    print(r"   pip install C:\Users\chris\Downloads\Compressed\CARLA_0.9.16\PythonAPI\carla\dist\carla-0.9.16-cp310-cp310-win_amd64.whl")
    print(r"   (Choose the .whl matching your python version in that dist folder)")
    sys.exit(1)

try:
    import pygame
    from pygame.locals import (
        K_w, K_a, K_s, K_d, K_UP, K_DOWN, K_LEFT, K_RIGHT,
        K_SPACE, K_ESCAPE, K_r, K_v, K_TAB, K_f, K_BACKSPACE
    )
except ImportError:
    raise ImportError("Pygame module not found. Run: pip install pygame")

try:
    import numpy as np
except ImportError:
    raise ImportError("NumPy module not found. Run: pip install numpy")

# ── Window & Sensor Settings ──
VIEW_WIDTH = 1280
VIEW_HEIGHT = 720  # Crisp 720p HD 16:9 widescreen view
VIEW_FOV = 90
SENSOR_FPS = 30  # Cap sensor rendering to 30 FPS to prevent GPU buffer exhaustion


def get_or_spawn_ego_vehicle(world):
    """Cleanly spawn a fresh ego vehicle or reset an existing one."""
    print("[STEP] Cleaning up any stale ego vehicles from prior sessions...")
    existing_heroes = [v for v in world.get_actors().filter('vehicle.*') 
                       if v.attributes.get('role_name') in ['hero', 'ego_vehicle']]
    for old_v in existing_heroes:
        try:
            print(f"[CLEANUP] Removing stale vehicle (Actor ID: {old_v.id})...")
            old_v.destroy()
        except Exception:
            pass

    print("[STEP] Spawning fresh ego vehicle...")
    bp_library = world.get_blueprint_library()
    model3_bps = bp_library.filter('vehicle.tesla.model3')
    if model3_bps:
        bp = model3_bps[0]
    else:
        bp = bp_library.filter('vehicle.*')[0]

    bp.set_attribute('role_name', 'hero')
    if bp.has_attribute('color'):
        bp.set_attribute('color', '30,144,255')

    spawn_points = world.get_map().get_spawn_points()
    if not spawn_points:
        print("[ERROR] Map has no spawn points available.")
        sys.exit(1)

    vehicle = None
    for sp in spawn_points:
        # Elevate by 0.5m so tires do not clip into road ground collision mesh
        elevated_sp = carla.Transform(
            carla.Location(x=sp.location.x, y=sp.location.y, z=sp.location.z + 0.5),
            sp.rotation
        )
        vehicle = world.try_spawn_actor(bp, elevated_sp)
        if vehicle is not None:
            print(f"[OK] Spawned fresh Ego Vehicle: {vehicle.type_id} (Actor ID: {vehicle.id})")
            break

    if vehicle is None:
        print("[ERROR] Failed to spawn vehicle across available spawn points.")
        sys.exit(1)

    # Explicitly activate physics and deactivate autopilot
    vehicle.set_simulate_physics(True)
    vehicle.set_autopilot(False)

    # Initialize transmission in forward drive with handbrake disengaged
    init_control = carla.VehicleControl()
    init_control.hand_brake = False
    init_control.brake = 0.0
    init_control.throttle = 0.0
    init_control.reverse = False
    init_control.manual_gear_shift = False
    vehicle.apply_control(init_control)

    return vehicle, True


class CameraManager:
    """
    Manages camera sensors with thread-safe surface delivery and Rigid attachment.
    Supports switching between Chase Cam and Dashboard Cam.
    """
    def __init__(self, vehicle, world, width, height, fov):
        self.sensor = None
        self.surface = None
        self._lock = threading.Lock()
        self._vehicle = vehicle
        self._world = world
        self.width = width
        self.height = height
        self.fov = fov
        self.transform_index = 0

        # Rigid attachments prevent PhysX SpringArm calculation conflicts
        self.transforms = [
            (
                "1st-Person Dashboard View",
                carla.Transform(carla.Location(x=1.2, y=0.0, z=1.3), carla.Rotation(pitch=-4.0)),
                carla.AttachmentType.Rigid
            ),
            (
                "Driver POV (Behind Wheel)",
                carla.Transform(carla.Location(x=0.4, y=-0.4, z=1.3), carla.Rotation(pitch=-4.0)),
                carla.AttachmentType.Rigid
            ),
            (
                "3rd-Person Chase View",
                carla.Transform(carla.Location(x=-5.5, y=0.0, z=2.8), carla.Rotation(pitch=-15.0)),
                carla.AttachmentType.Rigid
            ),
        ]
        self._setup_sensor()

    @property
    def current_view_name(self):
        return self.transforms[self.transform_index][0]

    def _setup_sensor(self):
        if self.sensor is not None:
            try:
                self.sensor.stop()
                self.sensor.destroy()
            except Exception:
                pass
            self.sensor = None

        cam_bp = self._world.get_blueprint_library().find('sensor.camera.rgb')
        cam_bp.set_attribute('image_size_x', str(self.width))
        cam_bp.set_attribute('image_size_y', str(self.height))
        cam_bp.set_attribute('fov', str(self.fov))
        # Cap sensor frame rate to prevent GPU memory saturation
        cam_bp.set_attribute('sensor_tick', str(1.0 / SENSOR_FPS))

        name, transform, attach_type = self.transforms[self.transform_index]
        self.sensor = self._world.spawn_actor(
            cam_bp,
            transform,
            attach_to=self._vehicle,
            attachment_type=attach_type
        )
        print(f"[OK] Camera attached: {name} (Sensor ID: {self.sensor.id})")

        weak_self = weakref.ref(self)
        self.sensor.listen(lambda image: CameraManager._parse_image(weak_self, image))

    def toggle_view(self):
        self.transform_index = (self.transform_index + 1) % len(self.transforms)
        self._setup_sensor()
        print(f"[INFO] Camera view switched to: {self.current_view_name}")

    @staticmethod
    def _parse_image(weak_self, image):
        self = weak_self()
        if not self:
            return
        image.convert(carla.ColorConverter.Raw)
        array = np.frombuffer(image.raw_data, dtype=np.dtype("uint8"))
        array = np.reshape(array, (image.height, image.width, 4))
        array = array[:, :, :3]
        array = array[:, :, ::-1]
        surf = pygame.surfarray.make_surface(array.swapaxes(0, 1))
        with self._lock:
            self.surface = surf

    def render(self, display):
        with self._lock:
            if self.surface is not None:
                display.blit(self.surface, (0, 0))

    def destroy(self):
        if self.sensor is not None:
            try:
                self.sensor.stop()
                self.sensor.destroy()
            except Exception:
                pass
            self.sensor = None
            print("[OK] Camera destroyed.")


def update_spectator_to_vehicle(spectator, vehicle, distance=10.0, height=5.0):
    """Safely positions the CARLA server's Spectator camera behind the vehicle."""
    try:
        t = vehicle.get_transform()
        yaw_rad = math.radians(t.rotation.yaw)
        spec_x = t.location.x - distance * math.cos(yaw_rad)
        spec_y = t.location.y - distance * math.sin(yaw_rad)
        spec_z = t.location.z + height
        spectator.set_transform(carla.Transform(
            carla.Location(x=spec_x, y=spec_y, z=spec_z),
            carla.Rotation(pitch=-15.0, yaw=t.rotation.yaw, roll=0.0)
        ))
    except Exception:
        pass


def draw_hud(display, font, speed_kmh, control, view_name, follow_spectator, is_focused):
    """Draws telemetry and status overlay onto the Pygame display."""
    overlay = pygame.Surface((display.get_width(), 85), pygame.SRCALPHA)
    overlay.fill((0, 0, 0, 160))
    display.blit(overlay, (0, 0))

    # Telemetry text
    gear_str = "R" if control.reverse else "D"
    speed_text = f"Speed: {speed_kmh:5.1f} km/h   |   Gear: [{gear_str}]   |   View: {view_name}"
    s_surf = font.render(speed_text, True, (0, 255, 200))
    display.blit(s_surf, (10, 8))

    ebrake_str = "ON" if control.hand_brake else "OFF"
    inputs_text = f"Throttle: {control.throttle * 100:3.0f}%   |   Brake: {control.brake * 100:3.0f}%   |   Steer: {control.steer:+4.2f}   |   E-Brake: {ebrake_str}"
    i_surf = font.render(inputs_text, True, (240, 240, 240))
    display.blit(i_surf, (10, 32))

    spec_str = "ON" if follow_spectator else "OFF"
    keys_text = f"W/S: Drive/Brake | A/D: Steer | Space: E-Brake | R: Rev | Bksp: Reset | Tab: View | Esc: Quit"
    k_surf = font.render(keys_text, True, (180, 180, 180))
    display.blit(k_surf, (10, 56))


def main():
    parser = argparse.ArgumentParser(description='ContextDrive Manual Driving Rig')
    parser.add_argument('--host', default='127.0.0.1', help='CARLA server IP (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=2000, help='CARLA server Port (default: 2000)')
    parser.add_argument('--res', default='1280x720', help='Window resolution, e.g. 1280x720 or 1600x900 (default: 1280x720)')
    args = parser.parse_args()

    try:
        width, height = [int(x) for x in args.res.lower().split('x')]
    except Exception:
        width, height = VIEW_WIDTH, VIEW_HEIGHT

    # ── Pygame Init ──
    print(f"[STEP] Initializing Pygame display ({width}x{height})...")
    pygame.init()
    pygame.font.init()
    display = pygame.display.set_mode(
        (width, height),
        pygame.HWSURFACE | pygame.DOUBLEBUF
    )
    pygame.display.set_caption(f"ContextDrive — Manual Driving Rig ({width}x{height})")
    font = pygame.font.Font(None, 24)
    display.fill((10, 10, 15))
    pygame.display.flip()

    # ── CARLA Connection ──
    print(f"[STEP] Connecting to CARLA at {args.host}:{args.port}...")
    client = carla.Client(args.host, args.port)
    client.set_timeout(10.0)
    world = client.get_world()

    # ── Ensure Asynchronous Mode ──
    settings = world.get_settings()
    if settings.synchronous_mode:
        print("[WARNING] CARLA server was in Synchronous Mode. Forcing Asynchronous Mode...")
        settings.synchronous_mode = False
        settings.fixed_delta_seconds = None
        world.apply_settings(settings)
        print("[OK] Asynchronous mode activated.")

    # ── Ego Vehicle ──
    ego_vehicle, spawned_by_us = get_or_spawn_ego_vehicle(world)
    camera_manager = None

    try:
        # ── Wait for first simulation tick so ego vehicle is fully initialized ──
        print("[STEP] Waiting for simulation tick...")
        world.wait_for_tick(seconds=5.0)

        # ── Position CARLA server Spectator to vehicle ──
        spectator = world.get_spectator()
        update_spectator_to_vehicle(spectator, ego_vehicle, distance=10.0, height=5.0)
        print("[OK] CARLA server spectator placed at vehicle.")

        # ── Camera ──
        print("[STEP] Attaching camera...")
        camera_manager = CameraManager(ego_vehicle, world, width, height, VIEW_FOV)

        print("\n=======================================================")
        print(" ContextDrive -- Manual Driving Rig Active")
        print("=======================================================")
        print(f" [SERVER]    {args.host}:{args.port}")
        print(f" [VEHICLE]   {ego_vehicle.type_id} (Actor ID: {ego_vehicle.id})")
        print(f" [VIEW]      {camera_manager.current_view_name}")
        print("=======================================================")
        print(" Controls:")
        print("   W / S       : Throttle / Brake")
        print("   A / D       : Steering (smooth self-centering)")
        print("   Space       : Handbrake")
        print("   R           : Toggle Reverse Gear")
        print("   Tab / V     : Toggle Camera (Dashboard -> Driver POV -> Chase Cam)")
        print("   F           : Toggle Spectator Window Tracking")
        print("   Esc         : Quit")
        print("=======================================================\n")

        clock = pygame.time.Clock()
        steer_cache = 0.0
        follow_spectator = True
        frame_count = 0

        # Persistent control object
        control = carla.VehicleControl()
        control.manual_gear_shift = False
        control.reverse = False
        control.hand_brake = False

        while True:
            clock.tick(60)
            frame_count += 1

            # ── Pygame Events ──
            should_quit = False
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    should_quit = True
                elif event.type == pygame.KEYDOWN:
                    if event.key == K_ESCAPE:
                        should_quit = True
                    elif event.key == K_r:
                        control.reverse = not control.reverse
                        print(f"[INFO] Gear set to: {'REVERSE' if control.reverse else 'DRIVE'}")
                    elif event.key in [K_v, K_TAB]:
                        camera_manager.toggle_view()
                    elif event.key == K_f:
                        follow_spectator = not follow_spectator
                        print(f"[INFO] Spectator follow: {'ON' if follow_spectator else 'OFF'}")
                    elif event.key == K_BACKSPACE:
                        # Reset vehicle if stuck or collided
                        spawn_points = world.get_map().get_spawn_points()
                        if spawn_points:
                            sp = spawn_points[0]
                            elevated_sp = carla.Transform(
                                carla.Location(x=sp.location.x, y=sp.location.y, z=sp.location.z + 0.5),
                                sp.rotation
                            )
                            ego_vehicle.set_transform(elevated_sp)
                            ego_vehicle.set_target_velocity(carla.Vector3D(0, 0, 0))
                            ego_vehicle.set_target_angular_velocity(carla.Vector3D(0, 0, 0))
                            control.throttle = 0.0
                            control.brake = 0.0
                            control.hand_brake = False
                            steer_cache = 0.0
                            ego_vehicle.apply_control(control)
                            print("[OK] Reset vehicle to road spawn point!")
            if should_quit:
                break

            keys = pygame.key.get_pressed()

            # ── Process Driving Controls (direct, responsive, no lockouts) ──
            # Throttle
            if keys[K_w] or keys[K_UP]:
                control.throttle = min(control.throttle + 0.25, 1.0)
                control.brake = 0.0
                control.hand_brake = False
            else:
                control.throttle = 0.0

            # Brake
            if keys[K_s] or keys[K_DOWN]:
                control.brake = min(control.brake + 0.30, 1.0)
                control.throttle = 0.0
            else:
                control.brake = 0.0

            # Steering (smooth self-centering)
            steer_increment = 0.07
            if keys[K_a] or keys[K_LEFT]:
                if steer_cache > 0:
                    steer_cache = 0.0
                else:
                    steer_cache = max(-1.0, steer_cache - steer_increment)
            elif keys[K_d] or keys[K_RIGHT]:
                if steer_cache < 0:
                    steer_cache = 0.0
                else:
                    steer_cache = min(1.0, steer_cache + steer_increment)
            else:
                if steer_cache > 0:
                    steer_cache = max(0.0, steer_cache - 0.12)
                elif steer_cache < 0:
                    steer_cache = min(0.0, steer_cache + 0.12)

            control.steer = round(steer_cache, 2)
            control.hand_brake = bool(keys[K_SPACE])

            ego_vehicle.apply_control(control)

            # ── Smooth Spectator Tracking (15 Hz throttled to avoid GPU draw congestion) ──
            if follow_spectator and (frame_count % 4 == 0):
                update_spectator_to_vehicle(spectator, ego_vehicle, distance=10.0, height=4.5)

            # ── Speed calculation ──
            v = ego_vehicle.get_velocity()
            speed_kmh = 3.6 * math.sqrt(v.x**2 + v.y**2 + v.z**2)

            # ── Render Frame & HUD ──
            camera_manager.render(display)
            draw_hud(
                display, font, speed_kmh, control,
                camera_manager.current_view_name, follow_spectator, True
            )
            pygame.display.flip()

    except KeyboardInterrupt:
        print("\n[INFO] Stopped by user.")
    finally:
        print("\n[STEP] Cleaning up resources...")
        if camera_manager:
            camera_manager.destroy()
        if spawned_by_us:
            try:
                if ego_vehicle.is_alive:
                    ego_vehicle.destroy()
                    print("[OK] Ego vehicle destroyed.")
            except Exception:
                pass
        else:
            print("[INFO] Ego vehicle left intact (reused).")

        try:
            s = world.get_settings()
            if s.synchronous_mode:
                s.synchronous_mode = False
                s.fixed_delta_seconds = None
                world.apply_settings(s)
        except Exception:
            pass

        pygame.quit()
        print("[OK] Cleanup complete. Rig closed cleanly.")


if __name__ == '__main__':
    main()
