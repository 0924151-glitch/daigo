/* textures.js - procedural canvas textures so the world doesn't look like
 * flat-colored boxes. All generated at runtime: cobblestone, stone brick,
 * wood, rusted metal, noise/fog & glow sprites. */
'use strict';

const Textures = (() => {
  const cache = {};

  function cvs(size) {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    return [c, c.getContext('2d')];
  }

  function rand(seed) {
    // deterministic PRNG so textures look identical for everyone
    let s = seed >>> 0;
    return () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    };
  }

  function toTex(c, repeat = 1) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeat, repeat);
    t.anisotropy = 4;
    return t;
  }

  // ---------------------------------------------------------------- noise
  function addNoise(g, size, alpha, r) {
    const img = g.getImageData(0, 0, size, size);
    const d = img.data;
    for (let i = 0; i < d.length; i += 4) {
      const n = (r() - 0.5) * 255 * alpha;
      d[i] += n; d[i + 1] += n; d[i + 2] += n;
    }
    g.putImageData(img, 0, 0);
  }

  // ------------------------------------------------------------ cobblestone
  function cobblestone() {
    if (cache.cobble) return cache.cobble;
    const S = 512;
    const [c, g] = cvs(S);
    const r = rand(1337);
    g.fillStyle = '#101018';
    g.fillRect(0, 0, S, S);

    const cols = 8, rows = 8, cw = S / cols, ch = S / rows;
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const off = (y % 2) * cw / 2;
        const px = x * cw + off + (r() - 0.5) * 6;
        const py = y * ch + (r() - 0.5) * 6;
        const w = cw - 7 - r() * 6, h = ch - 7 - r() * 6;
        const shade = 22 + r() * 26;
        const blue = shade + 6 + r() * 10;
        g.fillStyle = `rgb(${shade},${shade},${blue})`;
        roundRect(g, px, py, w, h, 8 + r() * 8);
        g.fill();
        // top-light bevel
        g.strokeStyle = 'rgba(255,255,255,0.05)';
        g.lineWidth = 2;
        roundRect(g, px + 1, py + 1, w - 2, h - 2, 8);
        g.stroke();
        // moss blotches
        if (r() < 0.4) {
          g.fillStyle = `rgba(38,52,34,${0.25 + r() * 0.3})`;
          g.beginPath();
          g.ellipse(px + r() * w, py + r() * h, 6 + r() * 14, 4 + r() * 9,
            r() * 3, 0, 7);
          g.fill();
        }
      }
    }
    addNoise(g, S, 0.10, r);
    cache.cobble = toTex(c, 10);
    return cache.cobble;
  }

  // ------------------------------------------------------------ stone brick
  function stoneBrick() {
    if (cache.brick) return cache.brick;
    const S = 512;
    const [c, g] = cvs(S);
    const r = rand(4242);
    g.fillStyle = '#0c0c12';
    g.fillRect(0, 0, S, S);
    const rows = 7, bh = S / rows;
    for (let y = 0; y < rows; y++) {
      let x = (y % 2) * -40;
      while (x < S) {
        const bw = 80 + r() * 70;
        const shade = 26 + r() * 22;
        g.fillStyle = `rgb(${shade},${shade - 2},${shade + 8})`;
        g.fillRect(x + 3, y * bh + 3, bw - 6, bh - 6);
        g.fillStyle = 'rgba(255,255,255,0.045)';
        g.fillRect(x + 3, y * bh + 3, bw - 6, 3);
        // cracks
        if (r() < 0.35) {
          g.strokeStyle = 'rgba(0,0,0,0.5)';
          g.lineWidth = 1.4;
          g.beginPath();
          let cx = x + 10 + r() * (bw - 20), cy = y * bh + 5;
          g.moveTo(cx, cy);
          for (let k = 0; k < 4; k++) {
            cx += (r() - 0.5) * 22; cy += bh / 5;
            g.lineTo(cx, cy);
          }
          g.stroke();
        }
        // moss along bottom edges
        if (r() < 0.5) {
          g.fillStyle = `rgba(40,56,36,${0.2 + r() * 0.25})`;
          g.fillRect(x + 3, (y + 1) * bh - 10, bw - 6, 8);
        }
        x += bw;
      }
    }
    addNoise(g, S, 0.09, r);
    cache.brick = toTex(c, 1);
    return cache.brick;
  }

  // ------------------------------------------------------------------ wood
  function wood() {
    if (cache.wood) return cache.wood;
    const S = 256;
    const [c, g] = cvs(S);
    const r = rand(777);
    g.fillStyle = '#211510';
    g.fillRect(0, 0, S, S);
    const planks = 5, pw = S / planks;
    for (let i = 0; i < planks; i++) {
      const shade = 30 + r() * 18;
      g.fillStyle = `rgb(${shade + 12},${shade - 2},${shade - 12})`;
      g.fillRect(i * pw + 2, 0, pw - 4, S);
      // grain lines
      g.strokeStyle = 'rgba(0,0,0,0.35)';
      g.lineWidth = 1;
      for (let k = 0; k < 6; k++) {
        g.beginPath();
        let gx = i * pw + 4 + r() * (pw - 8);
        g.moveTo(gx, 0);
        for (let y = 0; y < S; y += 24) {
          g.lineTo(gx + Math.sin(y * 0.05 + r() * 6) * 3, y);
        }
        g.stroke();
      }
      // nails
      g.fillStyle = '#0a0a0c';
      g.beginPath(); g.arc(i * pw + pw / 2, 14, 2.4, 0, 7); g.fill();
      g.beginPath(); g.arc(i * pw + pw / 2, S - 14, 2.4, 0, 7); g.fill();
    }
    addNoise(g, S, 0.08, r);
    cache.wood = toTex(c, 1);
    return cache.wood;
  }

  // ------------------------------------------------------------ rusty metal
  function metal() {
    if (cache.metal) return cache.metal;
    const S = 256;
    const [c, g] = cvs(S);
    const r = rand(9001);
    const grad = g.createLinearGradient(0, 0, 0, S);
    grad.addColorStop(0, '#23232c');
    grad.addColorStop(0.5, '#191921');
    grad.addColorStop(1, '#121218');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    // rust patches
    for (let i = 0; i < 26; i++) {
      g.fillStyle = `rgba(${70 + r() * 40},${34 + r() * 18},${16},${0.12 + r() * 0.2})`;
      g.beginPath();
      g.ellipse(r() * S, r() * S, 6 + r() * 26, 4 + r() * 16, r() * 3, 0, 7);
      g.fill();
    }
    // scratches
    g.strokeStyle = 'rgba(200,205,220,0.07)';
    for (let i = 0; i < 18; i++) {
      g.lineWidth = 0.8 + r();
      g.beginPath();
      const x = r() * S, y = r() * S;
      g.moveTo(x, y);
      g.lineTo(x + (r() - 0.5) * 90, y + (r() - 0.5) * 30);
      g.stroke();
    }
    addNoise(g, S, 0.07, r);
    cache.metal = toTex(c, 1);
    return cache.metal;
  }

  // --------------------------------------------------------------- fabric
  function fabric(hex) {
    const key = 'fab' + hex;
    if (cache[key]) return cache[key];
    const S = 128;
    const [c, g] = cvs(S);
    const r = rand(hex);
    const col = '#' + hex.toString(16).padStart(6, '0');
    g.fillStyle = col;
    g.fillRect(0, 0, S, S);
    g.globalAlpha = 0.16;
    g.strokeStyle = '#000';
    for (let i = 0; i < S; i += 3) {
      g.beginPath(); g.moveTo(i, 0); g.lineTo(i, S); g.stroke();
      g.beginPath(); g.moveTo(0, i); g.lineTo(S, i); g.stroke();
    }
    g.globalAlpha = 1;
    addNoise(g, S, 0.10, r);
    cache[key] = toTex(c, 2);
    return cache[key];
  }

  // -------------------------------------------------------- sprite helpers
  /* soft radial glow sprite texture */
  function glowSprite(inner = 'rgba(255,255,255,1)', outer = 'rgba(255,255,255,0)') {
    const key = 'glow' + inner + outer;
    if (cache[key]) return cache[key];
    const S = 128;
    const [c, g] = cvs(S);
    const grad = g.createRadialGradient(S / 2, S / 2, 4, S / 2, S / 2, S / 2);
    grad.addColorStop(0, inner);
    grad.addColorStop(0.4, inner.replace(/[\d.]+\)$/, '0.35)'));
    grad.addColorStop(1, outer);
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
    cache[key] = new THREE.CanvasTexture(c);
    return cache[key];
  }

  /* blobby smoke/fog puff */
  function fogSprite() {
    if (cache.fog) return cache.fog;
    const S = 256;
    const [c, g] = cvs(S);
    const r = rand(555);
    for (let i = 0; i < 34; i++) {
      const x = S / 2 + (r() - 0.5) * S * 0.6;
      const y = S / 2 + (r() - 0.5) * S * 0.5;
      const rad = 20 + r() * 46;
      const grad = g.createRadialGradient(x, y, 2, x, y, rad);
      grad.addColorStop(0, 'rgba(160,170,205,0.05)');
      grad.addColorStop(1, 'rgba(160,170,205,0)');
      g.fillStyle = grad;
      g.fillRect(0, 0, S, S);
    }
    cache.fog = new THREE.CanvasTexture(c);
    return cache.fog;
  }

  // --------------------------------------------------------------- helpers
  function roundRect(g, x, y, w, h, r0) {
    const rr = Math.min(r0, w / 2, h / 2);
    g.beginPath();
    g.moveTo(x + rr, y);
    g.arcTo(x + w, y, x + w, y + h, rr);
    g.arcTo(x + w, y + h, x, y + h, rr);
    g.arcTo(x, y + h, x, y, rr);
    g.arcTo(x, y, x + w, y, rr);
    g.closePath();
  }

  return { cobblestone, stoneBrick, wood, metal, fabric, glowSprite, fogSprite };
})();
