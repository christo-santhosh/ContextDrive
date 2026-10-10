"""Pure, testable CARLA vehicle-motion helpers."""

import math
from typing import Optional


def signed_longitudinal_acceleration(
    velocity: tuple[float, float, float],
    forward: tuple[float, float, float],
    acceleration: tuple[float, float, float],
    minimum_speed_mps: float = 1.4,
) -> Optional[float]:
    """Return acceleration projected onto direction of travel in m/s².

    CARLA's forward vector is the vehicle-facing axis. Reverse travel flips
    that axis, so positive still means increasing speed in the actual travel
    direction. Near standstill the direction cannot be inferred reliably.
    """
    speed_mps = math.sqrt(sum(component * component for component in velocity))
    if speed_mps < minimum_speed_mps:
        return None
    forward_speed = sum(v * f for v, f in zip(velocity, forward))
    travel_sign = 1.0 if forward_speed >= 0 else -1.0
    return travel_sign * sum(a * f for a, f in zip(acceleration, forward))
