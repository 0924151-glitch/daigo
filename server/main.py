"""Cipher Quest backend - FastAPI

Serves:
- REST API      /api/*        (machine CRUD, QR data)
- WebSocket     /ws/machine/{id}   (exclusive; one client per machine)
- WebSocket     /ws/dashboard      (broadcast of all machine states)
- Static files  /              (Flutter web build)

Run: uvicorn main:app --host 0.0.0.0 --port 5060
"""
import asyncio
import os

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from store import store
from connections import manager
from game.routes import router as game_router, pump_loop

app = FastAPI(title="Cipher Quest API")
app.include_router(game_router)


@app.on_event("startup")
async def _startup():
    asyncio.create_task(pump_loop())

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "build", "web")


# ---------- helpers ----------
def machine_public(m: dict) -> dict:
    return {**m, "locked": manager.is_machine_connected(m["id"])}


async def broadcast_state():
    machines = [machine_public(m) for m in store.list_machines()]
    await manager.broadcast_dashboards({
        "type": "state",
        "machines": machines,
        "all_completed": store.all_completed(),
    })


async def broadcast_event(ev: dict):
    await manager.broadcast_dashboards({"type": "event", "event": ev})


# ---------- REST models ----------
class MachineCreate(BaseModel):
    name: str = ""
    duration_sec: int = 60
    design: str = "classic"


class MachineUpdate(BaseModel):
    name: str | None = None
    duration_sec: int | None = None
    design: str | None = None


# ---------- REST endpoints ----------
@app.get("/api/health")
async def health():
    return {"ok": True}


@app.get("/api/machines")
async def list_machines():
    return {"machines": [machine_public(m) for m in store.list_machines()],
            "all_completed": store.all_completed()}


@app.post("/api/machines")
async def create_machine(body: MachineCreate):
    m = store.create(body.name, body.duration_sec, body.design)
    store.add_event(m["id"], "created", f"{m['name']} を設置しました")
    await broadcast_state()
    return machine_public(m)


@app.get("/api/machines/{machine_id}")
async def get_machine(machine_id: str):
    m = store.get(machine_id)
    if not m:
        raise HTTPException(404, "machine not found")
    return machine_public(m)


@app.patch("/api/machines/{machine_id}")
async def update_machine(machine_id: str, body: MachineUpdate):
    m = store.update_settings(machine_id, body.name, body.duration_sec, body.design)
    if not m:
        raise HTTPException(404, "machine not found")
    # notify the live machine page of new settings
    await manager.send_to_machine(machine_id, {"type": "settings", "machine": machine_public(m)})
    await broadcast_state()
    return machine_public(m)


@app.delete("/api/machines/{machine_id}")
async def delete_machine(machine_id: str):
    m = store.delete(machine_id)
    if not m:
        raise HTTPException(404, "machine not found")
    await manager.send_to_machine(machine_id, {"type": "deleted"})
    store.add_event(machine_id, "deleted", f"{m['name']} を撤去しました")
    await broadcast_state()
    return {"ok": True}


@app.post("/api/machines/{machine_id}/reset")
async def reset_machine(machine_id: str):
    m = store.reset(machine_id)
    if not m:
        raise HTTPException(404, "machine not found")
    await manager.send_to_machine(machine_id, {"type": "reset"})
    store.add_event(machine_id, "reset", f"{m['name']} をリセットしました")
    await broadcast_state()
    return machine_public(m)


@app.get("/api/events")
async def get_events():
    return {"events": store.events[-50:]}


# ---------- WebSocket: machine (exclusive) ----------
@app.websocket("/ws/machine/{machine_id}")
async def ws_machine(ws: WebSocket, machine_id: str):
    await ws.accept()
    m = store.get(machine_id)
    if not m:
        await ws.send_json({"type": "error", "reason": "not_found"})
        await ws.close()
        return
    ok = await manager.connect_machine(machine_id, ws)
    if not ok:
        # already open somewhere else -> refuse
        await ws.send_json({"type": "error", "reason": "locked"})
        await ws.close()
        return

    store.set_connected(machine_id, True)
    await ws.send_json({"type": "init", "machine": machine_public(store.get(machine_id))})
    ev = store.add_event(machine_id, "connect", f"{m['name']} がオンラインになりました")
    await broadcast_event(ev)
    await broadcast_state()

    try:
        while True:
            data = await ws.receive_json()
            t = data.get("type")
            if t == "progress":
                st = data.get("status", "decoding")
                prev = store.get(machine_id)
                was_completed = prev and prev["status"] == "completed"
                store.update_progress(machine_id, data.get("progress", 0), st)
                if st == "completed" and not was_completed:
                    ev = store.add_event(
                        machine_id, "completed",
                        f"{m['name']} の解読が完了しました！")
                    await broadcast_event(ev)
                    if store.all_completed():
                        ev2 = store.add_event(
                            machine_id, "all_completed",
                            "全ての暗号機の解読が完了！ゲートが開通しました！")
                        await broadcast_event(ev2)
                await broadcast_state()
            elif t == "skill":
                store.record_skill(machine_id, bool(data.get("success")))
                if not data.get("success"):
                    ev = store.add_event(
                        machine_id, "skill_miss",
                        f"{m['name']} でスキルチェック失敗！")
                    await broadcast_event(ev)
                await broadcast_state()
            elif t == "ping":
                await ws.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        manager.disconnect_machine(machine_id, ws)
        store.set_connected(machine_id, False)
        ev = store.add_event(machine_id, "disconnect", f"{m['name']} がオフラインになりました")
        await broadcast_event(ev)
        await broadcast_state()


# ---------- WebSocket: dashboard ----------
@app.websocket("/ws/dashboard")
async def ws_dashboard(ws: WebSocket):
    await ws.accept()
    await manager.connect_dashboard(ws)
    machines = [machine_public(m) for m in store.list_machines()]
    await ws.send_json({
        "type": "state",
        "machines": machines,
        "all_completed": store.all_completed(),
        "events": store.events[-50:],
    })
    try:
        while True:
            data = await ws.receive_json()
            if data.get("type") == "ping":
                await ws.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        manager.disconnect_dashboard(ws)


# ---------- Static Flutter web ----------
if os.path.isdir(WEB_DIR):
    app.mount("/assets", StaticFiles(directory=os.path.join(WEB_DIR, "assets")), name="assets")
    app.mount("/canvaskit", StaticFiles(directory=os.path.join(WEB_DIR, "canvaskit")), name="canvaskit")

    @app.get("/{path:path}")
    async def serve_web(path: str):
        full = os.path.join(WEB_DIR, path)
        if path and os.path.isfile(full):
            return FileResponse(full)
        # directory index (e.g. /game -> game/index.html)
        if path and os.path.isdir(full):
            idx = os.path.join(full, "index.html")
            if os.path.isfile(idx):
                return FileResponse(idx)
        return FileResponse(os.path.join(WEB_DIR, "index.html"))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5060)
