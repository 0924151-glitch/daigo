"""CPU brains: hunter AI and bot-survivor AI.

Both are stateless tick functions; they mutate entities in place.
Difficulty knobs come from config.game_config (admin adjustable).
"""
import math
import random

from . import world
from .config import game_config as gc
from . import config as cfg
from .entities import now

_rand = random.Random()


# --------------------------------------------------------------------------
# shared movement helper
# --------------------------------------------------------------------------
def _step_towards(ent, tx: float, tz: float, speed: float, dt: float):
    dx, dz = tx - ent.x, tz - ent.z
    d = math.hypot(dx, dz)
    if d < 0.05:
        return
    step = min(speed * dt, d)
    mx, mz = dx / d * step, dz / d * step
    nx, nz = world.move_with_collision(ent.x, ent.z, mx, mz)
    # if stuck against a wall, add a small perpendicular jitter to unstick
    if abs(nx - ent.x) < 1e-4 and abs(nz - ent.z) < 1e-4:
        jx, jz = -dz / d * step, dx / d * step
        if _rand.random() < 0.5:
            jx, jz = -jx, -jz
        nx, nz = world.move_with_collision(ent.x, ent.z, jx, jz)
    if abs(nx - ent.x) > 1e-5 or abs(nz - ent.z) > 1e-5:
        ent.yaw = math.atan2(nx - ent.x, nz - ent.z)
    ent.x, ent.z = nx, nz


# --------------------------------------------------------------------------
# hunter AI
# --------------------------------------------------------------------------
def tick_hunter(hunter, survivors, ciphers, dt: float):
    """One AI tick for the hunter. Returns list of survivor ids hit."""
    alive = [s for s in survivors if s.state == "alive"]
    hits = []
    if not alive:
        return hits

    t = now()
    vision = gc.hunter_vision
    speed = gc.hunter_speed

    # ---- perception: remember last-seen positions of visible survivors ----
    visible = []
    for s in alive:
        d = world.dist(hunter.x, hunter.z, s.x, s.z)
        if d <= vision and world.has_line_of_sight(hunter.x, hunter.z, s.x, s.z):
            visible.append((d, s))
            hunter.last_seen[s.id] = (s.x, s.z, t)

    # ---- target selection ----
    target = None
    if visible:
        visible.sort(key=lambda p: p[0])
        target = visible[0][1]
        hunter.target_id = target.id
    elif hunter.target_id:
        # chase last-seen position for a few seconds
        seen = hunter.last_seen.get(hunter.target_id)
        if seen and t - seen[2] < 4.0:
            _step_towards(hunter, seen[0], seen[1], speed, dt)
            return hits
        hunter.target_id = None

    # ---- attack / chase ----
    if target is not None:
        d = world.dist(hunter.x, hunter.z, target.x, target.z)
        if d <= cfg.ATTACK_RADIUS and hunter.can_attack():
            target.hit()
            hunter.did_attack(gc.hunter_attack_cooldown)
            hits.append(target.id)
        else:
            _step_towards(hunter, target.x, target.z, speed, dt)
        return hits

    # ---- patrol: bias towards ciphers still in progress ----
    if hunter.patrol_point is None or t >= hunter.repath_at or \
            world.dist(hunter.x, hunter.z, *hunter.patrol_point) < 1.5:
        active = [c for c in ciphers if not c.done and c.progress > 1]
        if active and _rand.random() < 0.45 + 0.4 * gc.difficulty:
            c = _rand.choice(active)
            hunter.patrol_point = (c.x + _rand.uniform(-3, 3),
                                   c.z + _rand.uniform(-3, 3))
        else:
            hunter.patrol_point = world.random_open_point(_rand)
        hunter.repath_at = t + _rand.uniform(4.0, 8.0)
    _step_towards(hunter, hunter.patrol_point[0], hunter.patrol_point[1],
                  speed * 0.9, dt)
    return hits


# --------------------------------------------------------------------------
# bot survivor AI
# --------------------------------------------------------------------------
def tick_bot(bot, hunter, ciphers, dt: float):
    """One AI tick for a CPU survivor."""
    if bot.state != "alive":
        return

    t = now()
    hd = world.dist(bot.x, bot.z, hunter.x, hunter.z)
    sees_hunter = hd < 14.0 and world.has_line_of_sight(bot.x, bot.z,
                                                        hunter.x, hunter.z)

    # ---- flee when hunter is close ----
    danger = 6.0 + 8.0 * gc.bot_flee_skill
    if sees_hunter and hd < danger:
        bot.decoding_cipher = -1
        # run away, weaving behind obstacles
        ang = math.atan2(bot.x - hunter.x, bot.z - hunter.z)
        ang += _rand.uniform(-0.5, 0.5) * (1 - gc.bot_flee_skill)
        fx = bot.x + math.sin(ang) * 6
        fz = bot.z + math.cos(ang) * 6
        fx, fz = world.clamp_to_map(fx, fz)
        _step_towards(bot, fx, fz, bot.speed, dt)
        bot.bot_repath_at = 0.0  # force repath after escape
        return

    # ---- pick a cipher to work on ----
    if bot.bot_cipher < 0 or ciphers[bot.bot_cipher].done or t >= bot.bot_repath_at:
        open_c = [c for c in ciphers if not c.done]
        if not open_c:
            bot.bot_cipher = -1
        else:
            # prefer near, avoid hunter's area
            def score(c):
                d = world.dist(bot.x, bot.z, c.x, c.z)
                hz = world.dist(hunter.x, hunter.z, c.x, c.z)
                return d - hz * 0.5
            open_c.sort(key=score)
            bot.bot_cipher = open_c[0].idx
        bot.bot_repath_at = t + _rand.uniform(6.0, 10.0)

    if bot.bot_cipher < 0:
        # all done -> head to nearest gate
        gx, gz = min(world.GATES,
                     key=lambda g: world.dist(bot.x, bot.z, g[0], g[1]))
        _step_towards(bot, gx, gz, bot.speed, dt)
        return

    c = ciphers[bot.bot_cipher]
    d = world.dist(bot.x, bot.z, c.x, c.z)
    if d <= cfg.DECODE_RADIUS:
        # decode (slower on hard difficulty so humans matter)
        bot.decoding_cipher = c.idx
        amount = (100.0 / cfg.DECODE_TIME_SEC) * gc.bot_decode_mult * dt
        c.add(amount)
        bot.decoded_amount += amount
    else:
        bot.decoding_cipher = -1
        _step_towards(bot, c.x, c.z, bot.speed * 0.95, dt)
