"""Match manager: single concurrent match, lobby, game loop, results.

Rules:
- Only ONE match runs at any time. While a match is `running`, new players
  cannot join (no mid-join); they wait in a queue screen until it ends.
- Lobby: players join, countdown starts when >=1 human present. Empty
  survivor slots are filled with CPU bots at match start.
- The hunter is always CPU (difficulty set by admins).
"""
import asyncio
import json
import math
import random
import time
import uuid

from . import ai, world
from . import config as cfg
from .config import game_config as gc
from .entities import Cipher, Hunter, Survivor, now


BOT_NAMES = ["幸運児", "医師", "庭師", "泥棒", "冒険家", "空軍"]


class Player:
    """A connected human player (websocket wrapper)."""

    def __init__(self, ws, name: str):
        self.ws = ws
        self.name = name[:12] or "サバイバー"
        self.token = uuid.uuid4().hex[:12]
        self.survivor_id = None  # set when match starts
        self.alive_conn = True

    async def send(self, data: dict):
        if not self.alive_conn:
            return
        try:
            await self.ws.send_text(json.dumps(data, ensure_ascii=False))
        except Exception:
            self.alive_conn = False


class Match:
    """State machine: lobby -> running -> result -> (reset to lobby)."""

    def __init__(self):
        self.phase = "lobby"           # lobby | countdown | running | result
        self.players: dict[str, Player] = {}   # token -> Player
        self.spectators: list = []             # dashboard websockets
        self.countdown_end = 0.0
        self.result = None
        self.result_until = 0.0
        self.match_no = 0
        # live entities (populated at start)
        self.survivors: list[Survivor] = []
        self.hunter: Hunter | None = None
        self.ciphers: list[Cipher] = []
        self.match_end_at = 0.0
        self.gate_open = False
        self.events: list[dict] = []
        self._loop_task = None
        self._lock = asyncio.Lock()

    # ------------------------------------------------------------------
    # lobby / join
    # ------------------------------------------------------------------
    def can_join(self) -> bool:
        return self.phase in ("lobby", "countdown") and \
            len(self.players) < cfg.MAX_SURVIVORS

    async def join(self, ws, name: str) -> Player | None:
        async with self._lock:
            if not self.can_join():
                return None
            p = Player(ws, name)
            self.players[p.token] = p
            if self.phase == "lobby" and gc.auto_start:
                self.phase = "countdown"
                self.countdown_end = now() + cfg.LOBBY_COUNTDOWN_SEC
            await self.broadcast_lobby()
            return p

    async def leave(self, token: str):
        async with self._lock:
            p = self.players.pop(token, None)
            if p and self.phase == "running" and p.survivor_id:
                # replace the leaver's body with a bot brain
                for s in self.survivors:
                    if s.id == p.survivor_id:
                        s.is_bot = True
                        s.name += "(CPU)"
                        break
            if self.phase in ("lobby", "countdown") and not self.players:
                self.phase = "lobby"
            await self.broadcast_lobby()

    # ------------------------------------------------------------------
    # match lifecycle
    # ------------------------------------------------------------------
    async def start_match(self):
        self.match_no += 1
        self.phase = "running"
        self.result = None
        self.events = []
        self.gate_open = False
        rand = random.Random()

        spawns = list(world.SURVIVOR_SPAWNS)
        rand.shuffle(spawns)
        self.survivors = []
        humans = list(self.players.values())
        for i in range(cfg.MAX_SURVIVORS):
            if i < len(humans):
                s = Survivor(humans[i].name, is_bot=False, spawn=spawns[i])
                humans[i].survivor_id = s.id
            else:
                s = Survivor(BOT_NAMES[rand.randrange(len(BOT_NAMES))] + "(CPU)",
                             is_bot=True, spawn=spawns[i])
            self.survivors.append(s)

        self.hunter = Hunter(world.HUNTER_SPAWN)
        self.ciphers = [Cipher(i, p) for i, p in enumerate(world.CIPHER_SPOTS)]
        self.match_end_at = now() + cfg.MATCH_TIME_SEC

        start_msg = {
            "type": "match_start",
            "match_no": self.match_no,
            "map": world.map_payload(),
            "you": None,  # filled per player below
            "time_limit": cfg.MATCH_TIME_SEC,
        }
        for p in self.players.values():
            m = dict(start_msg)
            m["you"] = p.survivor_id
            await p.send(m)
        await self.notify_spectators()

        if self._loop_task is None or self._loop_task.done():
            self._loop_task = asyncio.create_task(self._game_loop())

    async def _game_loop(self):
        dt = 1.0 / cfg.TICK_RATE
        snap_every = cfg.TICK_RATE // cfg.SNAPSHOT_RATE
        tick = 0
        try:
            while self.phase == "running":
                t0 = time.time()
                self._simulate(dt)
                tick += 1
                if tick % snap_every == 0:
                    await self._broadcast_state()
                if self._check_end():
                    await self._finish()
                    break
                await asyncio.sleep(max(0.0, dt - (time.time() - t0)))
        except Exception as e:  # keep server alive on any loop error
            print("game loop error:", e)
            self.phase = "lobby"

    # ------------------------------------------------------------------
    # simulation
    # ------------------------------------------------------------------
    def _simulate(self, dt: float):
        # human inputs
        for p in self.players.values():
            s = self._survivor(p.survivor_id)
            if s is None or s.state != "alive":
                continue
            mag = math.hypot(s.in_x, s.in_z)
            if mag > 0.05:
                mx = s.in_x / max(1.0, mag) * s.speed * dt
                mz = s.in_z / max(1.0, mag) * s.speed * dt
                nx, nz = world.move_with_collision(s.x, s.z, mx, mz)
                if abs(nx - s.x) > 1e-5 or abs(nz - s.z) > 1e-5:
                    s.yaw = math.atan2(nx - s.x, nz - s.z)
                s.x, s.z = nx, nz
                s.decoding_cipher = -1
                s.rescuing_id = None
                self._cancel_skill(s)
            elif s.in_decode:
                # interact: rescue a downed ally takes priority over decoding
                victim = self._nearest_downed(s)
                if victim is not None:
                    s.decoding_cipher = -1
                    s.rescuing_id = victim.id
                    self._cancel_skill(s)
                else:
                    s.rescuing_id = None
                    c = self._nearest_cipher(s)
                    if c is not None:
                        was_decoding = s.decoding_cipher == c.idx
                        s.decoding_cipher = c.idx
                        if not was_decoding:
                            self._schedule_skill(s)
                        amt = (100.0 / cfg.DECODE_TIME_SEC) * dt
                        before_done = c.done
                        c.add(amt)
                        s.decoded_amount += amt
                        if c.done and not before_done:
                            self._event("cipher_done", cipher=c.idx)
                            self._cancel_skill(s)
                        else:
                            self._tick_skill(s, c)
                    else:
                        s.decoding_cipher = -1
                        self._cancel_skill(s)
            else:
                s.decoding_cipher = -1
                s.rescuing_id = None
                self._cancel_skill(s)

        # bots
        for s in self.survivors:
            if s.is_bot:
                ai.tick_bot(s, self.hunter, self.ciphers, dt,
                            survivors=self.survivors)

        # rescues (humans + bots advance progress on their victim)
        self._tick_rescues(dt)

        # bleedout of downed survivors
        for s in self.survivors:
            if s.state == "down" and now() >= s.bleedout_at:
                s.state = "eliminated"
                self._event("eliminated", who=s.name)

        # hunter
        hits = ai.tick_hunter(self.hunter, self.survivors, self.ciphers, dt)
        for sid in hits:
            s = self._survivor(sid)
            kind = "down" if s.state == "down" else "hit"
            self._event(kind, who=s.name)

        # gates
        if not self.gate_open and all(c.done for c in self.ciphers):
            self.gate_open = True
            self._event("gate_open")
        if self.gate_open:
            for s in self.survivors:
                if s.state != "alive":
                    continue
                for gx, gz in world.GATES:
                    if world.dist(s.x, s.z, gx, gz) <= cfg.GATE_RADIUS:
                        s.state = "escaped"
                        self._event("escaped", who=s.name)
                        break

    # ---- rescue helpers ----
    def _nearest_downed(self, s):
        best, bd = None, cfg.RESCUE_RADIUS
        for o in self.survivors:
            if o.id == s.id or o.state != "down":
                continue
            d = world.dist(s.x, s.z, o.x, o.z)
            if d <= bd:
                best, bd = o, d
        return best

    def _tick_rescues(self, dt: float):
        """Advance rescue progress for every downed survivor with a rescuer
        in range; complete at 1.0."""
        rescuers = {}   # victim_id -> rescuer
        for s in self.survivors:
            if s.state == "alive" and s.rescuing_id:
                victim = self._survivor(s.rescuing_id)
                if victim is None or victim.state != "down" or \
                        world.dist(s.x, s.z, victim.x, victim.z) > cfg.RESCUE_RADIUS + 0.4:
                    s.rescuing_id = None
                    continue
                rescuers[victim.id] = s
        for s in self.survivors:
            if s.state != "down":
                continue
            r = rescuers.get(s.id)
            if r is not None:
                s.rescue_progress = min(1.0, s.rescue_progress +
                                        dt / cfg.RESCUE_TIME_SEC)
                if s.rescue_progress >= 1.0:
                    s.rescued()
                    r.rescuing_id = None
                    r.rescues += 1
                    self._event("rescue", who=s.name, by=r.name)
            else:
                s.rescue_progress = max(0.0, s.rescue_progress -
                                        dt / cfg.RESCUE_TIME_SEC * 0.7)

    # ---- skill check helpers (humans only) ----
    def _schedule_skill(self, s):
        s.skill_active = False
        s.skill_at = now() + random.uniform(cfg.SKILL_MIN_GAP_SEC,
                                            cfg.SKILL_MAX_GAP_SEC)

    def _cancel_skill(self, s):
        if s.skill_active:
            s.skill_active = False

    def _tick_skill(self, s, cipher):
        t = now()
        if s.skill_active:
            if t >= s.skill_deadline:      # timed out -> miss
                self._skill_result(s, cipher, False, timeout=True)
            return
        if t >= s.skill_at:
            s.skill_active = True
            s.skill_seq += 1
            s.skill_deadline = t + cfg.SKILL_WINDOW_SEC
            p = self._player_of(s)
            if p:
                asyncio.ensure_future(p.send({
                    "type": "skill_check", "seq": s.skill_seq,
                    "window": cfg.SKILL_WINDOW_SEC,
                }))

    def _skill_result(self, s, cipher, success: bool,
                      great: bool = False, timeout: bool = False):
        s.skill_active = False
        s.skill_at = now() + random.uniform(cfg.SKILL_MIN_GAP_SEC,
                                            cfg.SKILL_MAX_GAP_SEC)
        if cipher is None:
            return
        if success:
            if great:
                cipher.add(cfg.SKILL_GREAT_BONUS)
                s.decoded_amount += cfg.SKILL_GREAT_BONUS
        else:
            cipher.progress = max(0.0, cipher.progress - cfg.SKILL_MISS_PENALTY)
            self._event("skill_miss", who=s.name)

    def handle_skill_reply(self, survivor_id, seq: int,
                           success: bool, great: bool):
        s = self._survivor(survivor_id)
        if s is None or not s.skill_active or seq != s.skill_seq:
            return
        c = self.ciphers[s.decoding_cipher] \
            if 0 <= s.decoding_cipher < len(self.ciphers) else None
        self._skill_result(s, c, success, great)

    def _player_of(self, s):
        for p in self.players.values():
            if p.survivor_id == s.id:
                return p
        return None

    def _nearest_cipher(self, s):
        best, bd = None, cfg.DECODE_RADIUS
        for c in self.ciphers:
            if c.done:
                continue
            d = world.dist(s.x, s.z, c.x, c.z)
            if d <= bd:
                best, bd = c, d
        return best

    def _survivor(self, sid):
        for s in self.survivors:
            if s.id == sid:
                return s
        return None

    def _event(self, kind: str, **kw):
        self.events.append({"t": round(now(), 1), "kind": kind, **kw})
        if len(self.events) > 40:
            self.events = self.events[-40:]

    # ------------------------------------------------------------------
    # end conditions & results
    # ------------------------------------------------------------------
    def _check_end(self) -> bool:
        if now() >= self.match_end_at:
            self.result = self._make_result("time_up")
            return True
        active = [s for s in self.survivors
                  if s.state in ("alive", "down")]
        if not active:
            escaped = sum(1 for s in self.survivors if s.state == "escaped")
            self.result = self._make_result(
                "survivors_win" if escaped >= 2 else "hunter_wins")
            return True
        return False

    def _make_result(self, outcome: str) -> dict:
        return {
            "outcome": outcome,
            "match_no": self.match_no,
            "survivors": [
                {"name": s.name, "bot": s.is_bot, "state": s.state,
                 "decoded": round(s.decoded_amount, 1),
                 "rescues": s.rescues}
                for s in self.survivors
            ],
            "ciphers_done": sum(1 for c in self.ciphers if c.done),
        }

    async def _finish(self):
        self.phase = "result"
        self.result_until = now() + cfg.RESULT_SCREEN_SEC
        msg = {"type": "match_end", "result": self.result}
        await self._send_all(msg)
        await self.notify_spectators()
        await asyncio.sleep(cfg.RESULT_SCREEN_SEC)
        # reset to lobby; players stay connected and can queue again
        self.phase = "lobby"
        for p in self.players.values():
            p.survivor_id = None
        if self.players and gc.auto_start:
            self.phase = "countdown"
            self.countdown_end = now() + cfg.LOBBY_COUNTDOWN_SEC
        await self.broadcast_lobby()
        await self.notify_spectators()

    # ------------------------------------------------------------------
    # broadcasting
    # ------------------------------------------------------------------
    def state_snapshot(self) -> dict:
        return {
            "type": "state",
            "t": round(self.match_end_at - now(), 1),
            "survivors": [s.snapshot() for s in self.survivors],
            "hunter": self.hunter.snapshot() if self.hunter else None,
            "ciphers": [c.snapshot() for c in self.ciphers],
            "gate_open": self.gate_open,
            "events": self.events[-5:],
        }

    def lobby_snapshot(self) -> dict:
        return {
            "type": "lobby",
            "phase": self.phase,
            "players": [p.name for p in self.players.values()],
            "max": cfg.MAX_SURVIVORS,
            "countdown": max(0, round(self.countdown_end - now(), 1))
            if self.phase == "countdown" else None,
            "match_no": self.match_no,
        }

    async def broadcast_lobby(self):
        await self._send_all(self.lobby_snapshot())

    async def _broadcast_state(self):
        await self._send_all(self.state_snapshot())

    async def _send_all(self, data: dict):
        for p in list(self.players.values()):
            await p.send(data)

    # ---- dashboard spectators (lightweight status pushes) ----
    def admin_snapshot(self) -> dict:
        d = {
            "phase": self.phase,
            "match_no": self.match_no,
            "players": [p.name for p in self.players.values()],
            "config": gc.as_dict(),
        }
        if self.phase == "running":
            d["ciphers_done"] = sum(1 for c in self.ciphers if c.done)
            d["alive"] = sum(1 for s in self.survivors if s.state == "alive")
            d["time_left"] = max(0, round(self.match_end_at - now()))
        if self.result:
            d["last_result"] = self.result
        return d

    async def notify_spectators(self):
        msg = json.dumps({"type": "game_status", **self.admin_snapshot()},
                         ensure_ascii=False)
        for ws in list(self.spectators):
            try:
                await ws.send_text(msg)
            except Exception:
                try:
                    self.spectators.remove(ws)
                except ValueError:
                    pass

    # ------------------------------------------------------------------
    # countdown pump (called from a periodic task in main.py)
    # ------------------------------------------------------------------
    async def pump(self):
        if self.phase == "countdown":
            if not self.players:
                self.phase = "lobby"
                await self.broadcast_lobby()
            elif now() >= self.countdown_end:
                await self.start_match()
            else:
                await self.broadcast_lobby()


match = Match()
