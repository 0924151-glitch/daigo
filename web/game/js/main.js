/* main.js - game orchestration: net events -> state, render loop,
 * entity interpolation, camera follow, input -> server. */
'use strict';

(() => {
  // ---- module state ----
  let myId = null;          // my survivor id
  let myName = '';
  let phase = 'boot';       // boot | lobby | wait | running | result
  let mapData = null;

  // authoritative snapshots for interpolation
  let prevState = null, curState = null, stateAt = 0;
  const SNAP_MS = 100;      // server snapshot interval (10/s)

  // three.js entity registry: id -> { obj, lastX, lastZ, moving }
  const survivorObjs = new Map();
  let hunterObj = null;

  const canvas = document.getElementById('gl');
  World3D.init(canvas);
  Input.init();

  // ------------------------------------------------------------------
  // boot: name entry -> connect
  // ------------------------------------------------------------------
  Hud.showNameEntry((name) => {
    myName = name;
    Hud.showLobby({ players: [], max: 4 });
    Net.connect(name);
  });

  // ------------------------------------------------------------------
  // net events
  // ------------------------------------------------------------------
  Net.on('joined', (d) => {
    phase = 'lobby';
    Hud.showLobby(d);
  });

  Net.on('lobby', (d) => {
    if (phase === 'running') return;   // late lobby msg during play - ignore
    phase = 'lobby';
    Hud.showLobby(d);
  });

  Net.on('wait', (d) => {
    phase = 'wait';
    Hud.showWait(d.status);
  });

  Net.on('match_start', (d) => {
    phase = 'running';
    myId = d.you;
    mapData = d.map;
    prevState = curState = null;
    clearEntities();
    World3D.buildMap(mapData);
    Hud.resetFeed();
    Hud.showGame();
  });

  Net.on('state', (d) => {
    if (phase !== 'running') return;
    prevState = curState;
    curState = d;
    stateAt = performance.now();
    syncEntities(d);
    Hud.updateHud(d, myId);
    Hud.pushEvents(d.events);
  });

  Net.on('match_end', (d) => {
    phase = 'result';
    const meName = mySurvivorName();
    Hud.showResult(d.result, myId, meName);
  });

  Net.on('close', () => {
    if (phase === 'running') {
      // connection lost mid-match; net.js auto-reconnects -> will get wait/lobby
      phase = 'wait';
      Hud.showWait(null);
    }
  });

  function mySurvivorName() {
    if (!curState) return myName;
    const me = curState.survivors.find(s => s.id === myId);
    return me ? me.name : myName;
  }

  // ------------------------------------------------------------------
  // entity lifecycle & interpolation
  // ------------------------------------------------------------------
  function clearEntities() {
    for (const e of survivorObjs.values()) World3D.scene.remove(e.obj);
    survivorObjs.clear();
    if (hunterObj) { World3D.scene.remove(hunterObj.obj); hunterObj = null; }
  }

  function syncEntities(state) {
    state.survivors.forEach((s, i) => {
      if (!survivorObjs.has(s.id)) {
        const obj = Characters.buildSurvivor(i);
        obj.position.set(s.x, 0, s.z);
        World3D.scene.add(obj);
        survivorObjs.set(s.id, { obj, label: makeLabel(s.name, i), moving: false });
        survivorObjs.get(s.id).obj.add(survivorObjs.get(s.id).label);
      }
    });
    if (state.hunter && !hunterObj) {
      const obj = Characters.buildHunter();
      obj.position.set(state.hunter.x, 0, state.hunter.z);
      World3D.scene.add(obj);
      hunterObj = { obj };
    }
  }

  function makeLabel(name, idx) {
    const cvs = document.createElement('canvas');
    cvs.width = 256; cvs.height = 64;
    const g = cvs.getContext('2d');
    g.font = '600 30px "Cinzel", serif';
    g.textAlign = 'center';
    g.fillStyle = '#' + Characters.SURV_COLORS[idx % 4].toString(16).padStart(6, '0');
    g.shadowColor = 'rgba(0,0,0,0.9)'; g.shadowBlur = 8;
    g.fillText(name.slice(0, 10), 128, 42);
    const tex = new THREE.CanvasTexture(cvs);
    const spr = new THREE.Sprite(new THREE.SpriteMaterial({
      map: tex, transparent: true, depthWrite: false,
    }));
    spr.scale.set(2.4, 0.6, 1);
    spr.position.y = 2.35;
    return spr;
  }

  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerpAngle(a, b, t) {
    let d = b - a;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    return a + d * t;
  }

  function interpolate(time) {
    if (!curState) return;
    const t = prevState ? Math.min(1, (performance.now() - stateAt) / SNAP_MS) : 1;

    for (const s of curState.survivors) {
      const e = survivorObjs.get(s.id);
      if (!e) continue;
      const p = prevState ? prevState.survivors.find(x => x.id === s.id) : null;
      const x = p ? lerp(p.x, s.x, t) : s.x;
      const z = p ? lerp(p.z, s.z, t) : s.z;
      const yaw = p ? lerpAngle(p.yaw, s.yaw, t) : s.yaw;
      e.moving = p ? (Math.abs(s.x - p.x) + Math.abs(s.z - p.z)) > 0.02 : false;
      e.obj.position.x = x;
      e.obj.position.z = z;
      e.obj.rotation.y = yaw;
      // hide label for downed/gone; dim for escaped
      const gone = s.state === 'escaped' || s.state === 'eliminated';
      e.obj.visible = !gone;
      Characters.animateSurvivor(e.obj, e.moving, s.decoding >= 0, s.state === 'down', time);
    }

    if (hunterObj && curState.hunter) {
      const h = curState.hunter;
      const p = prevState ? prevState.hunter : null;
      hunterObj.obj.position.x = p ? lerp(p.x, h.x, t) : h.x;
      hunterObj.obj.position.z = p ? lerp(p.z, h.z, t) : h.z;
      hunterObj.obj.rotation.y = p ? lerpAngle(p.yaw, h.yaw, t) : h.yaw;
      const moving = p ? (Math.abs(h.x - p.x) + Math.abs(h.z - p.z)) > 0.02 : false;
      Characters.animateHunter(hunterObj.obj, moving, h.lunge, time);
    }

    // cipher glow: set of ciphers currently decoded by someone
    const active = new Set();
    for (const s of curState.survivors) if (s.decoding >= 0) active.add(s.decoding);
    World3D.updateCiphers(curState.ciphers, active, time);
    World3D.updateGates(curState.gate_open, time);
  }

  // ------------------------------------------------------------------
  // camera: third-person follow of my survivor (or overview when gone)
  // ------------------------------------------------------------------
  const camPos = new THREE.Vector3(0, 16, 24);
  const camTarget = new THREE.Vector3(0, 0, 0);

  function updateCamera() {
    const cam = World3D.camera;
    let fx = 0, fz = 0, alive = false;
    if (curState && myId) {
      const me = curState.survivors.find(s => s.id === myId);
      if (me && (me.state === 'alive' || me.state === 'down')) {
        const e = survivorObjs.get(me.id);
        if (e) { fx = e.obj.position.x; fz = e.obj.position.z; alive = true; }
      }
    }
    let want;
    if (alive) {
      want = new THREE.Vector3(fx, 11.5, fz + 13.5);
      camTarget.lerp(new THREE.Vector3(fx, 1.2, fz), 0.12);
    } else {
      // spectator overview
      want = new THREE.Vector3(0, 34, 30);
      camTarget.lerp(new THREE.Vector3(0, 0, 0), 0.05);
    }
    camPos.lerp(want, 0.08);
    cam.position.copy(camPos);
    cam.lookAt(camTarget);
  }

  // ------------------------------------------------------------------
  // input -> server + decode hint
  // ------------------------------------------------------------------
  function sendInputs() {
    if (phase !== 'running' || !curState || !myId) return;
    const me = curState.survivors.find(s => s.id === myId);
    if (!me || me.state !== 'alive') { Net.sendInput(0, 0, false); return; }

    const v = Input.moveVector();
    // screen space -> world: camera looks roughly -z, so up = -z, right = +x
    Net.sendInput(v.x, v.y, Input.isDecoding());

    // decode hint: near an unfinished cipher
    let near = false;
    for (const c of curState.ciphers) {
      if (c.done) continue;
      const spot = mapData.ciphers[c.idx];
      const dx = spot[0] - me.x, dz = spot[1] - me.z;
      if (dx * dx + dz * dz < 2.6 * 2.6) { near = true; break; }
    }
    Hud.setDecodeHint(near && me.decoding < 0);
  }

  // ------------------------------------------------------------------
  // render loop
  // ------------------------------------------------------------------
  let last = performance.now();
  function frame(nowMs) {
    requestAnimationFrame(frame);
    const time = nowMs / 1000;
    if (nowMs - last > 33) { sendInputs(); last = nowMs; }
    if (phase === 'running' || phase === 'result') {
      interpolate(time);
      updateCamera();
    }
    World3D.render(time);
  }
  requestAnimationFrame(frame);
})();
