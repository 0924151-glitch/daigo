/* characters.js - low-poly stylized survivor & hunter models with
 * procedural walk/idle/decode animation. All original geometry. */
'use strict';

const Characters = (() => {
  const SURV_COLORS = [0x52e0d8, 0xe8a33d, 0x7c5cbf, 0x5aa860];

  // ------------------------------------------------------------------
  // model builders (return a THREE.Group with named parts on userData)
  // ------------------------------------------------------------------
  function buildSurvivor(colorIdx) {
    const accent = SURV_COLORS[colorIdx % SURV_COLORS.length];
    const cloth = new THREE.MeshStandardMaterial({ color: 0x2b2836, roughness: 0.85 });
    const skin = new THREE.MeshStandardMaterial({ color: 0xc9b8a6, roughness: 0.7 });
    const acc = new THREE.MeshStandardMaterial({
      color: accent, roughness: 0.5, emissive: accent, emissiveIntensity: 0.25,
    });

    const g = new THREE.Group();

    // torso (slightly tapered)
    const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.34, 0.75, 7), cloth);
    torso.position.y = 1.0;
    torso.castShadow = true;
    g.add(torso);

    // accent scarf
    const scarf = new THREE.Mesh(new THREE.TorusGeometry(0.26, 0.07, 6, 12), acc);
    scarf.position.y = 1.36;
    scarf.rotation.x = Math.PI / 2;
    g.add(scarf);

    // head + hood
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.22, 10, 8), skin);
    head.position.y = 1.62;
    head.castShadow = true;
    g.add(head);
    const hood = new THREE.Mesh(new THREE.ConeGeometry(0.26, 0.42, 8), cloth);
    hood.position.y = 1.78;
    g.add(hood);

    // arms
    const armGeo = new THREE.CylinderGeometry(0.07, 0.06, 0.6, 6);
    const armL = new THREE.Mesh(armGeo, cloth);
    armL.position.set(-0.36, 1.1, 0);
    const armR = new THREE.Mesh(armGeo, cloth);
    armR.position.set(0.36, 1.1, 0);
    armL.castShadow = armR.castShadow = true;
    g.add(armL, armR);

    // legs
    const legGeo = new THREE.CylinderGeometry(0.09, 0.08, 0.62, 6);
    const legL = new THREE.Mesh(legGeo, cloth);
    legL.position.set(-0.14, 0.31, 0);
    const legR = new THREE.Mesh(legGeo, cloth);
    legR.position.set(0.14, 0.31, 0);
    g.add(legL, legR);

    // soft accent glow at feet (team-color identify ring)
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(0.34, 0.44, 24),
      new THREE.MeshBasicMaterial({ color: accent, transparent: true, opacity: 0.35, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.02;
    g.add(ring);

    g.userData = { armL, armR, legL, legR, torso, head, ring, accent, phase: Math.random() * 6 };
    return g;
  }

  function buildHunter() {
    const dark = new THREE.MeshStandardMaterial({ color: 0x17121c, roughness: 0.9 });
    const bloodMat = new THREE.MeshStandardMaterial({
      color: 0x9c2233, roughness: 0.5, emissive: 0x9c2233, emissiveIntensity: 0.45,
    });

    const g = new THREE.Group();

    // massive cloaked torso
    const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.62, 1.35, 8), dark);
    torso.position.y = 1.15;
    torso.castShadow = true;
    g.add(torso);

    // shoulder pads
    for (const dx of [-0.5, 0.5]) {
      const pad = new THREE.Mesh(new THREE.SphereGeometry(0.22, 8, 6), dark);
      pad.position.set(dx, 1.68, 0);
      g.add(pad);
    }

    // head: hollow hood with glowing eyes
    const hood = new THREE.Mesh(new THREE.ConeGeometry(0.32, 0.62, 8), dark);
    hood.position.y = 2.1;
    g.add(hood);
    const eyeGeo = new THREE.SphereGeometry(0.045, 6, 6);
    const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff3040 });
    const eyeL = new THREE.Mesh(eyeGeo, eyeMat);
    eyeL.position.set(-0.09, 2.02, 0.22);
    const eyeR = new THREE.Mesh(eyeGeo, eyeMat);
    eyeR.position.set(0.09, 2.02, 0.22);
    g.add(eyeL, eyeR);

    // arms + huge blade
    const armGeo = new THREE.CylinderGeometry(0.11, 0.09, 0.85, 6);
    const armL = new THREE.Mesh(armGeo, dark);
    armL.position.set(-0.55, 1.25, 0);
    const armR = new THREE.Mesh(armGeo, dark);
    armR.position.set(0.55, 1.25, 0);
    g.add(armL, armR);

    const blade = new THREE.Group();
    const bladeMesh = new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.5, 0.3), bloodMat);
    bladeMesh.position.y = -0.8;
    blade.add(bladeMesh);
    const tip = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.4, 4), bloodMat);
    tip.position.y = -1.62;
    tip.rotation.x = Math.PI;
    blade.add(tip);
    blade.position.set(0.62, 1.5, 0.12);
    g.add(blade);

    // red menace light
    const menace = new THREE.PointLight(0x9c2233, 0.8, 8, 2);
    menace.position.y = 1.8;
    g.add(menace);

    g.userData = { armL, armR, torso, blade, menace, eyeL, eyeR, phase: 0 };
    g.scale.setScalar(1.12);
    return g;
  }

  // ------------------------------------------------------------------
  // per-frame animation
  // ------------------------------------------------------------------
  function animateSurvivor(g, moving, decoding, downed, time) {
    const u = g.userData;
    const t = time * 7 + u.phase;
    if (downed) {
      // lie on the ground
      g.rotation.x = -Math.PI / 2 * 0.92;
      g.position.y = 0.25;
      u.ring.material.opacity = 0.15 + 0.15 * Math.sin(time * 2);
      return;
    }
    g.rotation.x = 0;
    g.position.y = 0;

    if (decoding) {
      // hands forward, subtle fidget
      u.armL.rotation.x = -1.15 + Math.sin(t * 2.2) * 0.12;
      u.armR.rotation.x = -1.15 + Math.cos(t * 2.5) * 0.12;
      u.legL.rotation.x = u.legR.rotation.x = 0;
      u.torso.rotation.x = 0.12;
    } else if (moving) {
      const s = Math.sin(t);
      u.armL.rotation.x = s * 0.7;
      u.armR.rotation.x = -s * 0.7;
      u.legL.rotation.x = -s * 0.8;
      u.legR.rotation.x = s * 0.8;
      u.torso.rotation.x = 0.08;
      g.position.y = Math.abs(Math.sin(t)) * 0.045;
    } else {
      // idle breathing
      u.armL.rotation.x = u.armR.rotation.x = Math.sin(time * 1.8) * 0.05;
      u.legL.rotation.x = u.legR.rotation.x = 0;
      u.torso.rotation.x = 0;
      u.torso.scale.y = 1 + Math.sin(time * 1.8) * 0.015;
    }
    u.ring.material.opacity = 0.3 + 0.1 * Math.sin(time * 3);
  }

  function animateHunter(g, moving, lunging, time) {
    const u = g.userData;
    const t = time * 6;
    if (lunging) {
      u.blade.rotation.z = -1.9 + Math.sin(time * 26) * 0.25;
      u.menace.intensity = 1.8;
      u.torso.rotation.x = 0.28;
    } else if (moving) {
      const s = Math.sin(t);
      u.armL.rotation.x = s * 0.5;
      u.blade.rotation.z = -0.35 + Math.sin(t * 0.5) * 0.1;
      u.torso.rotation.x = 0.12;
      u.menace.intensity = 0.9 + 0.2 * Math.sin(time * 5);
      g.position.y = Math.abs(Math.sin(t * 0.9)) * 0.05;
    } else {
      u.armL.rotation.x = Math.sin(time * 1.4) * 0.05;
      u.blade.rotation.z = -0.25;
      u.torso.rotation.x = 0;
      u.menace.intensity = 0.7 + 0.15 * Math.sin(time * 2.2);
      g.position.y = 0;
    }
    // eyes pulse
    const e = 0.8 + 0.2 * Math.sin(time * 4);
    u.eyeL.scale.setScalar(e);
    u.eyeR.scale.setScalar(e);
  }

  return { buildSurvivor, buildHunter, animateSurvivor, animateHunter, SURV_COLORS };
})();
