"""Machine data store with JSON file persistence.

Keeps all cipher machine state in memory and persists to data.json
so that a server restart does not lose festival progress.
"""
import json
import os
import time
import uuid
import threading

DATA_FILE = os.path.join(os.path.dirname(__file__), "data.json")

_lock = threading.Lock()


def _now_ms() -> int:
    return int(time.time() * 1000)


class MachineStore:
    def __init__(self):
        self.machines = {}  # id -> dict
        self.events = []    # recent event log (max 100)
        self._load()

    # ---------- persistence ----------
    def _load(self):
        if os.path.exists(DATA_FILE):
            try:
                with open(DATA_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self.machines = data.get("machines", {})
                self.events = data.get("events", [])
                # connections are never persisted
                for m in self.machines.values():
                    m["connected"] = False
                    if m["status"] == "decoding":
                        m["status"] = "paused"
            except Exception:
                self.machines = {}
                self.events = []

    def _save(self):
        try:
            with open(DATA_FILE, "w", encoding="utf-8") as f:
                json.dump(
                    {"machines": self.machines, "events": self.events[-100:]},
                    f, ensure_ascii=False, indent=1,
                )
        except Exception:
            pass

    # ---------- CRUD ----------
    def list_machines(self):
        with _lock:
            return sorted(self.machines.values(), key=lambda m: m["created_at"])

    def get(self, machine_id):
        return self.machines.get(machine_id)

    def create(self, name: str, duration_sec: int = 60):
        with _lock:
            mid = uuid.uuid4().hex[:8]
            machine = {
                "id": mid,
                "name": name or f"暗号機 {len(self.machines) + 1}",
                "duration_sec": max(5, min(3600, int(duration_sec))),
                "progress": 0.0,          # 0-100
                "status": "idle",          # idle / decoding / paused / completed
                "connected": False,
                "skill_success": 0,
                "skill_miss": 0,
                "completed_at": None,
                "created_at": _now_ms(),
                "updated_at": _now_ms(),
            }
            self.machines[mid] = machine
            self._save()
            return machine

    def update_settings(self, machine_id, name=None, duration_sec=None):
        with _lock:
            m = self.machines.get(machine_id)
            if not m:
                return None
            if name is not None and name.strip():
                m["name"] = name.strip()
            if duration_sec is not None:
                m["duration_sec"] = max(5, min(3600, int(duration_sec)))
            m["updated_at"] = _now_ms()
            self._save()
            return m

    def delete(self, machine_id):
        with _lock:
            m = self.machines.pop(machine_id, None)
            self._save()
            return m

    def reset(self, machine_id):
        with _lock:
            m = self.machines.get(machine_id)
            if not m:
                return None
            m["progress"] = 0.0
            m["status"] = "idle"
            m["skill_success"] = 0
            m["skill_miss"] = 0
            m["completed_at"] = None
            m["updated_at"] = _now_ms()
            self._save()
            return m

    # ---------- live updates ----------
    def update_progress(self, machine_id, progress, status):
        with _lock:
            m = self.machines.get(machine_id)
            if not m:
                return None
            m["progress"] = max(0.0, min(100.0, float(progress)))
            if status in ("idle", "decoding", "paused", "completed"):
                m["status"] = status
            if status == "completed" and m["completed_at"] is None:
                m["completed_at"] = _now_ms()
                m["progress"] = 100.0
            m["updated_at"] = _now_ms()
            # save only on significant transitions to reduce disk IO
            if status in ("completed", "paused", "idle"):
                self._save()
            return m

    def record_skill(self, machine_id, success: bool):
        with _lock:
            m = self.machines.get(machine_id)
            if not m:
                return None
            if success:
                m["skill_success"] += 1
            else:
                m["skill_miss"] += 1
            m["updated_at"] = _now_ms()
            return m

    def set_connected(self, machine_id, connected: bool):
        with _lock:
            m = self.machines.get(machine_id)
            if not m:
                return None
            m["connected"] = connected
            if not connected and m["status"] == "decoding":
                m["status"] = "paused"
            m["updated_at"] = _now_ms()
            return m

    # ---------- event log ----------
    def add_event(self, machine_id, event_type, message):
        with _lock:
            ev = {
                "machine_id": machine_id,
                "type": event_type,
                "message": message,
                "at": _now_ms(),
            }
            self.events.append(ev)
            self.events = self.events[-100:]
            return ev

    def all_completed(self):
        with _lock:
            ms = list(self.machines.values())
            return len(ms) > 0 and all(m["status"] == "completed" for m in ms)


store = MachineStore()
