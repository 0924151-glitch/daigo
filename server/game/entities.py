"""Game entities: survivors (human or CPU) and the CPU hunter."""
import time
import uuid

from . import config as cfg


def now() -> float:
    return time.time()


class Survivor:
    """A survivor, controlled by a human websocket or by CPU AI."""

    def __init__(self, name: str, is_bot: bool, spawn):
        self.id = uuid.uuid4().hex[:8]
        self.name = name
        self.is_bot = is_bot
        self.x, self.z = spawn
        self.yaw = 0.0            # facing (rad), for renderer
        self.hp = cfg.SURVIVOR_HP
        self.state = "alive"      # alive | downed | eliminated | escaped
        self.decoding_cipher = -1 # index of cipher being decoded, -1 none
        self.speed_boost_until = 0.0
        self.last_input = now()
        # human input (normalized move vector)
        self.in_x = 0.0
        self.in_z = 0.0
        self.in_decode = False
        # bot brain scratch data
        self.bot_target = None    # (x, z) waypoint
        self.bot_cipher = -1
        self.bot_repath_at = 0.0
        # stats
        self.decoded_amount = 0.0

    @property
    def speed(self) -> float:
        s = cfg.SURVIVOR_SPEED
        if now() < self.speed_boost_until:
            s *= cfg.SURVIVOR_HIT_BOOST
        return s

    def hit(self):
        self.hp -= 1
        self.decoding_cipher = -1
        if self.hp <= 0:
            self.state = "eliminated"
        else:
            self.speed_boost_until = now() + cfg.HIT_BOOST_SEC

    def snapshot(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "bot": self.is_bot,
            "x": round(self.x, 2),
            "z": round(self.z, 2),
            "yaw": round(self.yaw, 2),
            "hp": self.hp,
            "state": self.state,
            "decoding": self.decoding_cipher,
            "boost": now() < self.speed_boost_until,
        }


class Hunter:
    """The CPU-controlled hunter."""

    def __init__(self, spawn):
        self.id = "hunter"
        self.name = "ハンター"
        self.x, self.z = spawn
        self.yaw = 0.0
        self.attack_ready_at = 0.0
        self.lunge_until = 0.0
        # brain
        self.target_id = None
        self.patrol_point = None
        self.repath_at = 0.0
        self.last_seen = {}   # survivor_id -> (x, z, t)

    def can_attack(self) -> bool:
        return now() >= self.attack_ready_at

    def did_attack(self, cooldown: float):
        self.attack_ready_at = now() + cooldown
        self.lunge_until = now() + 0.35

    def snapshot(self) -> dict:
        return {
            "x": round(self.x, 2),
            "z": round(self.z, 2),
            "yaw": round(self.yaw, 2),
            "lunge": now() < self.lunge_until,
        }


class Cipher:
    """One decodable cipher machine on the field."""

    def __init__(self, idx: int, pos):
        self.idx = idx
        self.x, self.z = pos
        self.progress = 0.0   # 0..100
        self.done = False

    def add(self, amount: float):
        if self.done:
            return
        self.progress = min(100.0, self.progress + amount)
        if self.progress >= 100.0:
            self.done = True

    def snapshot(self) -> dict:
        return {
            "idx": self.idx,
            "progress": round(self.progress, 1),
            "done": self.done,
        }
