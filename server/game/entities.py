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
        self.state = "alive"      # alive | down | eliminated | escaped
        self.decoding_cipher = -1 # index of cipher being decoded, -1 none
        self.speed_boost_until = 0.0
        self.last_input = now()
        # human input (normalized move vector)
        self.in_x = 0.0
        self.in_z = 0.0
        self.in_decode = False
        # down / rescue
        self.bleedout_at = 0.0    # when downed: time of elimination
        self.rescue_progress = 0.0  # 0..1 while being rescued
        self.rescuing_id = None   # id of downed ally I'm rescuing
        # skill check QTE
        self.skill_at = 0.0       # when next skill check may fire
        self.skill_active = False # a check is pending on the client
        self.skill_deadline = 0.0
        self.skill_seq = 0        # increments per issued check
        # bot brain scratch data
        self.bot_target = None    # (x, z) waypoint
        self.bot_cipher = -1
        self.bot_repath_at = 0.0
        # stats
        self.decoded_amount = 0.0
        self.rescues = 0

    @property
    def speed(self) -> float:
        s = cfg.SURVIVOR_SPEED
        if now() < self.speed_boost_until:
            s *= cfg.SURVIVOR_HIT_BOOST
        return s

    def hit(self):
        """Take one hit. 0 hp -> downed (bleeding out), not instant death."""
        self.hp -= 1
        self.decoding_cipher = -1
        self.skill_active = False
        if self.hp <= 0:
            self.state = "down"
            self.bleedout_at = now() + cfg.DOWN_BLEEDOUT_SEC
            self.rescue_progress = 0.0
        else:
            self.speed_boost_until = now() + cfg.HIT_BOOST_SEC

    def rescued(self):
        """Picked back up by an ally."""
        self.state = "alive"
        self.hp = cfg.RESCUED_HP
        self.rescue_progress = 0.0
        self.speed_boost_until = now() + cfg.HIT_BOOST_SEC

    def snapshot(self) -> dict:
        d = {
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
            "rescuing": self.rescuing_id,
        }
        if self.state == "down":
            d["bleed"] = max(0.0, round(
                (self.bleedout_at - now()) / cfg.DOWN_BLEEDOUT_SEC, 3))
            d["rescue_p"] = round(self.rescue_progress, 3)
        return d


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
