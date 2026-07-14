"""Static map definition + collision helpers.

The game logic runs on a 2D plane (x, z); the client renders it in 3D.
Map: 60x60m gothic manor courtyard with walls, crates, ruins.
Coordinates: origin at center, +x east, +z south.
"""
import math
import random

MAP_HALF = 30.0  # map is [-30, 30] on both axes

# Axis-aligned box obstacles: (cx, cz, half_w, half_d, height)
# height is only for the 3D renderer.
OBSTACLES = [
    # outer ruin walls (with gaps for movement)
    (-18, -18, 6.0, 0.6, 3.2),
    (18, -18, 6.0, 0.6, 3.2),
    (-18, 18, 6.0, 0.6, 3.2),
    (18, 18, 6.0, 0.6, 3.2),
    (-24, 0, 0.6, 7.0, 3.2),
    (24, 0, 0.6, 7.0, 3.2),
    # central chapel ruin
    (0, 0, 5.0, 0.6, 4.5),
    (-5, 3.5, 0.6, 3.5, 4.5),
    (5, 3.5, 0.6, 3.5, 4.5),
    # scattered crates / carts
    (-12, 6, 1.4, 1.4, 1.6),
    (11, -8, 1.6, 1.2, 1.5),
    (7, 13, 1.3, 1.3, 1.4),
    (-9, -12, 1.5, 1.1, 1.5),
    (16, 7, 1.2, 1.6, 1.6),
    (-15, -4, 1.3, 1.3, 1.4),
    # broken pillars
    (-8, 9, 0.9, 0.9, 5.0),
    (9, -14, 0.9, 0.9, 5.0),
    (14, 14, 0.9, 0.9, 5.0),
    (-14, 14, 0.9, 0.9, 5.0),
    (-20, -10, 0.9, 0.9, 5.0),
    (20, 10, 0.9, 0.9, 5.0),
]

# Cipher machine positions (5) - spread across the map
CIPHER_SPOTS = [
    (-20.0, -20.0),
    (20.0, -19.0),
    (0.0, -6.0),
    (-19.0, 16.0),
    (19.0, 18.0),
]

# Exit gates (2) on opposite edges
GATES = [(0.0, -29.0), (0.0, 29.0)]

SURVIVOR_SPAWNS = [(-26, -26), (26, -26), (-26, 26), (26, 26)]
HUNTER_SPAWN = (0.0, 12.0)

PLAYER_RADIUS = 0.45


def clamp_to_map(x: float, z: float):
    m = MAP_HALF - PLAYER_RADIUS
    return max(-m, min(m, x)), max(-m, min(m, z))


def collides(x: float, z: float) -> bool:
    """Circle vs AABB check against all obstacles."""
    for (cx, cz, hw, hd, _h) in OBSTACLES:
        nx = max(cx - hw, min(x, cx + hw))
        nz = max(cz - hd, min(z, cz + hd))
        dx, dz = x - nx, z - nz
        if dx * dx + dz * dz < PLAYER_RADIUS * PLAYER_RADIUS:
            return True
    return False


def move_with_collision(x: float, z: float, dx: float, dz: float):
    """Try to move; slide along walls if blocked. Returns new (x, z)."""
    nx, nz = clamp_to_map(x + dx, z + dz)
    if not collides(nx, nz):
        return nx, nz
    # slide on x only
    nx2, nz2 = clamp_to_map(x + dx, z)
    if not collides(nx2, nz2):
        return nx2, nz2
    # slide on z only
    nx3, nz3 = clamp_to_map(x, z + dz)
    if not collides(nx3, nz3):
        return nx3, nz3
    return x, z


def dist(ax, az, bx, bz) -> float:
    return math.hypot(ax - bx, az - bz)


def has_line_of_sight(ax, az, bx, bz) -> bool:
    """Sampled raycast between two points against obstacles."""
    d = dist(ax, az, bx, bz)
    if d < 0.001:
        return True
    steps = max(2, int(d / 0.8))
    for i in range(1, steps):
        t = i / steps
        px = ax + (bx - ax) * t
        pz = az + (bz - az) * t
        for (cx, cz, hw, hd, _h) in OBSTACLES:
            if cx - hw <= px <= cx + hw and cz - hd <= pz <= cz + hd:
                return False
    return True


def random_open_point(rand: random.Random):
    for _ in range(50):
        x = rand.uniform(-MAP_HALF + 2, MAP_HALF - 2)
        z = rand.uniform(-MAP_HALF + 2, MAP_HALF - 2)
        if not collides(x, z):
            return x, z
    return 0.0, -20.0


def map_payload() -> dict:
    """Static map data sent to clients once."""
    return {
        "half": MAP_HALF,
        "obstacles": [list(o) for o in OBSTACLES],
        "ciphers": [list(c) for c in CIPHER_SPOTS],
        "gates": [list(g) for g in GATES],
    }
