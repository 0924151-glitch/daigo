/* main.js - game orchestration: net events -> state, render loop,
 * entity interpolation, camera follow, input -> server.
 * Integrates: World3D, Characters, Effects, Sound, SkillCheck, Hud. */
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

  // three.js entity registry: id -> { obj, label, moving }
  const survivorObjs = new Map();
  let hunterObj = null;

  const canvas = document.getElementById('gl');
  World3D.init(canvas);
  Effects.init(World3D.scene);
  Input.init();
  SkillCheck.init((seq, success, great) => {
    Net.send({ type: 'skill', seq, success, great });
  });

  // audio needs a user gesture; hook first interaction
  const startAudio = () => { Sound.start(); Sound.resume(); };
  window.addEventListener('pointerdown', startAudio, { once: true });
  window.addEventListener('keydown', startAudio, { once: true });

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
    Effects.clearAmbience();
    Effects.buildAmbience(mapData.half || 30);
    Hud.resetFeed();
    Hud.showGame();
    SkillCheck.dismiss();
  });

  Net.on('state', (d) => {
    if (phase !== 'running') return;
    prevState = curState;
    curState = d;
    stateAt = performance.now();
    syncEntities(d);
    Hud.updateHud(d, myId);
    handleEvents(d.events);
    Hud.pushEvents(d.events);
    updateAudioMood(d);
  });

  Net.on('skill_check', (d) => {
    // only trigger while actually decoding & alive
    const me = curState && curState.survivors.find(s => s.id === myId);
    if (me && me.state === 'alive' && me.decoding >= 0) {
      SkillCheck.trigger(d.seq, d.window);
    }
  });

  Net.on('match_end', (d) => {
    phase = 'result';
    SkillCheck.dismiss();
    Sound.setDanger(0);
    Sound.setDecoding(false);
    const meName = mySurvivorName();
    const won = d.result && d.result.outcome === 'survivors_win';
    Sound.fx[won ? 'win' : 'lose']?.();
    Hud.showResult(d.result, myId, meName);
  });

  Net.on('close', () => {
    if (phase === 'running') {
      phase = 'wait';
      SkillCheck.dismiss();
      Hud.showWait(null);
    }
  });

  function mySurvivorName() {
    if (!curState) return myName;
    const me = curState.survivors.find(s => s.id === myId);
    return me ? me.name : myName;
  }

  // ------------------------------------------------------------------
  // events -> sound / effects (only new ones)
  // ------------------------------------------------------------------
  const fxSeen = new Set();
  function handleEvents(events) {
    if (!events) return;
    for (const e of events) {
      const key = e.t + ':' + e.kind + ':' + (e.who || e.cipher || '');
      if (fxSeen.has(key)) continue;
      fxSeen.add(key);
      const isMe = e.who && e.who === mySurvivorName();
      switch (e.kind) {
        case 'cipher_done': {
          Sound.fx.cipherDone();
          const spot = mapData && mapData.ciphers[e.cipher];
          if (spot) Effects.burst(spot[0], 1.4, spot[1], 0xffd76a, 42, 5, 1.1, 0.2);
          break;
        }
        case 'gate_open':
          Sound.fx.gate();
          if (mapData) for (const g of mapData.gates) {
            Effects.burst(g[0], 1.5, g[1], 0x52e0d8, 36, 4.5, 1.2, 0.18);
          }
          break;
        case 'hit': {
          Sound.fx.hit();
          if (isMe) { Effects.shake(0.5); Effects.hitFlash(); }
          const s = findSurvivorByName(e.who);
          if (s) Effects.burst(s.x, 1.2, s.z, 0xc73535, 24, 3.5, 0.7, 0.15);
          break;
        }
        case 'down': {
          Sound.fx.down();
          if (isMe) { Effects.shake(0.8); Effects.hitFlash(); }
          const s = findSurvivorByName(e.who);
          if (s) Effects.burst(s.x, 0.8, s.z, 0x8a1020, 34, 4, 1.0, 0.18);
          break;
        }
        case 'rescue': {
          Sound.fx.rescue();
          const s = findSurvivorByName(e.who);
          if (s) Effects.burst(s.x, 1.2, s.z, 0x6fe3a0, 30, 3.5, 0.9, 0.16);
          break;
        }
        case 'escaped':
          Sound.fx.rescue();
          break;
        case 'eliminated':
          Sound.fx.down();
          break;
        case 'skill_miss':
          if (isMe) Effects.shake(0.3);
          break;
      }
    }
    if (fxSeen.size > 200) fxSeen.clear();
  }

  function findSurvivorByName(name) {
    return curState ? curState.survivors.find(s => s.name === name) : null;
  }

  // ------------------------------------------------------------------
  // dynamic audio mood: heartbeat scales with hunter distance
  // ------------------------------------------------------------------
  function updateAudioMood(state) {
    const me = state.survivors.find(s => s.id === myId);
    if (!me || (me.state !== 'alive' && me.state !== 'down') || !state.hunter) {
      Sound.setDanger(0);
      Sound.setDecoding(false);
      return;
    }
    const dx = state.hunter.x - me.x, dz = state.hunter.z - me.z;
    const d = Math.sqrt(dx * dx + dz * dz);
    const TERROR = 17.0;
    Sound.setDanger(Math.max(0, Math.min(1, 1 - d / TERROR)));
    Sound.setDecoding(me.decoding >= 0);
    // dismiss QTE if we stopped decoding (hit, moved away...)
    if (me.decoding < 0 && SkillCheck.isActive()) SkillCheck.dismiss();
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
        const label = makeLabel(s.name, i);
        obj.add(label);
        survivorObjs.set(s.id, { obj, label, moving: false, wasDecoding: false });
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
      const gone = s.state === 'escaped' || s.state === 'eliminated';
      e.obj.visible = !gone;
      const decoding = s.decoding >= 0;
      Characters.animateSurvivor(e.obj, e.moving, decoding, s.state === 'down', time);
      // decode sparks at the cipher the survivor works on
      if (decoding && mapData) {
        const spot = mapData.ciphers[s.decoding];
        if (spot) Effects.decodeSparks(spot[0], 1.35, spot[1], time);
      }
      e.wasDecoding = decoding;
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

  function updateCamera(time) {
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
    Effects.applyShake(cam, time);
  }

  // ------------------------------------------------------------------
  // input -> server + interact hints (decode / rescue)
  // ------------------------------------------------------------------
  function sendInputs() {
    if (phase !== 'running' || !curState || !myId) return;
    const me = curState.survivors.find(s => s.id === myId);
    if (!me || me.state !== 'alive') { Net.sendInput(0, 0, false); return; }

    const v = Input.moveVector();
    Net.sendInput(v.x, v.y, Input.isDecoding());

    // context hint: rescue takes priority over decode
    let hint = null;
    for (const s of curState.survivors) {
      if (s.id !== me.id && s.state === 'down') {
        const dx = s.x - me.x, dz = s.z - me.z;
        if (dx * dx + dz * dz < 2.2 * 2.2) {
          hint = '\u9577\u62bc\u3057 / SPACE \u3067 ' + s.name + ' \u3092\u6551\u52a9';
          break;
        }
      }
    }
    if (!hint && mapData) {
      for (const c of curState.ciphers) {
        if (c.done) continue;
        const spot = mapData.ciphers[c.idx];
        const dx = spot[0] - me.x, dz = spot[1] - me.z;
        if (dx * dx + dz * dz < 2.6 * 2.6) {
          hint = '\u9577\u62bc\u3057 / SPACE \u3067\u89e3\u8aad';
          break;
        }
      }
    }
    const busy = me.decoding >= 0 || me.rescuing;
    Hud.setDecodeHint(!!hint && !busy, hint || '');
  }

  // ------------------------------------------------------------------
  // render loop
  // ------------------------------------------------------------------
  let last = performance.now();
  let lastFrame = performance.now();
  function frame(nowMs) {
    requestAnimationFrame(frame);
    const time = nowMs / 1000;
    const dt = Math.min(0.05, (nowMs - lastFrame) / 1000);
    lastFrame = nowMs;
    if (nowMs - last > 33) { sendInputs(); last = nowMs; }
    if (phase === 'running' || phase === 'result') {
      interpolate(time);
      updateCamera(time);
      Effects.update(dt, time);
    }
    World3D.render(time, dt);
    SkillCheck.draw();
  }
  requestAnimationFrame(frame);
})();
