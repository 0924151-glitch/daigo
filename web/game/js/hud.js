/* hud.js - DOM UI control: lobby, wait screen, countdown, in-game HUD,
 * event feed, down/rescue banners, result screen. No game logic. */
'use strict';

const Hud = (() => {
  const $ = (id) => document.getElementById(id);

  // ------------------------------------------------------------------
  // overlays
  // ------------------------------------------------------------------
  function show(id) {
    for (const ov of document.querySelectorAll('.overlay')) {
      ov.classList.toggle('hidden', ov.id !== id);
    }
    $('hud').classList.toggle('active', id === null);
  }

  function showGame() { show(null); }

  // ---- name entry ----
  function showNameEntry(onSubmit) {
    show('ov-name');
    const input = $('name-input');
    const btn = $('btn-join');
    const go = () => {
      const n = input.value.trim().slice(0, 12);
      if (!n) { input.focus(); return; }
      localStorage.setItem('cq_player_name', n);
      onSubmit(n);
    };
    btn.onclick = go;
    input.onkeydown = (e) => { if (e.key === 'Enter') go(); };
    input.value = localStorage.getItem('cq_player_name') || '';
    input.focus();
  }

  // ---- lobby ----
  function showLobby(data) {
    show('ov-lobby');
    const roster = $('roster');
    roster.innerHTML = '';
    const players = data.players || [];
    for (let i = 0; i < (data.max || 4); i++) {
      const div = document.createElement('div');
      if (players[i]) {
        div.textContent = '\u25c6 ' + players[i];
      } else {
        div.textContent = '\u25c7 \u2015 CPU\u304c\u88dc\u5145\u3055\u308c\u307e\u3059 \u2015';
        div.className = 'empty';
      }
      roster.appendChild(div);
    }
    const cd = $('lobby-countdown');
    if (data.phase === 'countdown' && data.countdown != null) {
      cd.textContent = Math.ceil(data.countdown);
      cd.style.display = 'block';
      $('lobby-msg').textContent = '\u307e\u3082\u306a\u304f\u8a66\u5408\u304c\u59cb\u307e\u308a\u307e\u3059\u2026';
    } else {
      cd.style.display = 'none';
      $('lobby-msg').textContent = '\u4ed6\u306e\u30d7\u30ec\u30a4\u30e4\u30fc\u3092\u5f85\u6a5f\u4e2d\u2026 (\u4e0d\u8db3\u5206\u306fCPU\u304c\u53c2\u6226)';
    }
  }

  // ---- wait (match in progress, no mid-join) ----
  function showWait(status) {
    show('ov-wait');
    let msg = '\u73fe\u5728\u8a66\u5408\u304c\u9032\u884c\u4e2d\u3067\u3059\u3002\u7d42\u4e86\u307e\u3067\u304a\u5f85\u3061\u304f\u3060\u3055\u3044\u3002';
    if (status && status.phase === 'running') {
      const parts = [];
      if (status.time_left != null) {
        const m = Math.floor(status.time_left / 60);
        const s = String(status.time_left % 60).padStart(2, '0');
        parts.push(`\u6b8b\u308a ${m}:${s}`);
      }
      if (status.ciphers_done != null) parts.push(`\u89e3\u8aad ${status.ciphers_done}/5`);
      if (status.alive != null) parts.push(`\u751f\u5b58 ${status.alive}`);
      if (parts.length) msg += '\n' + parts.join(' \u2502 ');
    }
    $('wait-msg').innerText = msg;
  }

  // ------------------------------------------------------------------
  // in-game HUD
  // ------------------------------------------------------------------
  function updateHud(state, myId) {
    // timer
    const t = Math.max(0, state.t | 0);
    $('hud-timer').textContent =
      `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;

    // cipher dots
    const dots = $('hud-ciphers').children;
    state.ciphers.forEach((c, i) => {
      if (dots[i]) {
        dots[i].classList.toggle('done', c.done);
        dots[i].style.setProperty('--p', (c.progress / 100));
        dots[i].title = `${c.progress.toFixed(0)}%`;
      }
    });

    // teammate status strip (Identity V style portraits)
    updateTeamStrip(state, myId);

    // my hp + decode bar + danger vignette
    const me = state.survivors.find(s => s.id === myId);
    if (me) {
      const pips = $('hud-hp').children;
      for (let i = 0; i < pips.length; i++) {
        pips[i].classList.toggle('lost', i >= me.hp);
      }
      const decoding = me.decoding >= 0 && me.state === 'alive';
      $('decode-bar-wrap').style.display = decoding ? 'block' : 'none';
      if (decoding) {
        const c = state.ciphers[me.decoding];
        if (c) $('decode-bar').style.width = c.progress + '%';
      }

      // hunter proximity vignette
      let danger = false;
      if (state.hunter && me.state === 'alive') {
        const dx = state.hunter.x - me.x, dz = state.hunter.z - me.z;
        danger = dx * dx + dz * dz < 14 * 14;
      }
      $('danger-vignette').classList.toggle('on', danger);

      updateStateBanner(me);
    }

    // gate hint
    $('gate-hint').style.display = state.gate_open ? 'block' : 'none';
  }

  // ---- downed / escaped / eliminated banner + bleedout ring ----
  function updateStateBanner(me) {
    const banner = $('state-banner');
    const bleed = $('bleedout-wrap');
    if (me.state === 'down') {
      banner.style.display = 'block';
      banner.style.color = 'var(--blood)';
      if (me.rescue_p > 0) {
        banner.textContent = `\u4ef2\u9593\u304c\u6551\u52a9\u4e2d\u2026 ${(me.rescue_p * 100 | 0)}%`;
        banner.style.color = 'var(--cyan)';
      } else {
        banner.textContent = '\u30c0\u30a6\u30f3\u4e2d\u2026 \u4ef2\u9593\u306e\u6551\u52a9\u3092\u5f85\u3066';
      }
      bleed.style.display = 'block';
      const p = Math.max(0, Math.min(1, me.bleed ?? 0));
      $('bleedout-bar').style.width = (p * 100) + '%';
      bleed.classList.toggle('critical', p < 0.3);
    } else {
      bleed.style.display = 'none';
      if (me.state === 'escaped') {
        banner.textContent = '\u8131\u51fa\u6210\u529f\uff01 \u8a66\u5408\u7d42\u4e86\u3092\u898b\u5b88\u3063\u3066\u3044\u307e\u3059';
        banner.style.display = 'block';
        banner.style.color = 'var(--cyan)';
      } else if (me.state === 'eliminated') {
        banner.textContent = '\u8131\u843d\u2026 \u8a66\u5408\u7d42\u4e86\u3092\u898b\u5b88\u3063\u3066\u3044\u307e\u3059';
        banner.style.display = 'block';
        banner.style.color = 'var(--blood)';
      } else {
        banner.style.display = 'none';
      }
    }
  }

  // ---- teammate status strip ----
  const STATE_ICON = {
    alive: '\u25cf', down: '\u2716', eliminated: '\u2620',
    escaped: '\u279a',
  };
  function updateTeamStrip(state, myId) {
    const strip = $('team-strip');
    if (!strip) return;
    // build once
    if (strip.children.length !== state.survivors.length) {
      strip.innerHTML = '';
      for (const s of state.survivors) {
        const d = document.createElement('div');
        d.className = 'tm';
        d.dataset.id = s.id;
        d.innerHTML = `<span class="tm-ic"></span><span class="tm-nm"></span>`;
        strip.appendChild(d);
      }
    }
    for (const el of strip.children) {
      const s = state.survivors.find(v => v.id === el.dataset.id);
      if (!s) continue;
      el.querySelector('.tm-ic').textContent = STATE_ICON[s.state] || '\u25cf';
      el.querySelector('.tm-nm').textContent =
        (s.id === myId ? '\u25b6' : '') + s.name;
      el.className = 'tm st-' + s.state +
        (s.decoding >= 0 ? ' decoding' : '') +
        (s.state === 'down' && s.rescue_p > 0 ? ' rescuing' : '');
    }
  }

  function setDecodeHint(visible, text) {
    const el = $('decode-hint');
    el.style.display = visible ? 'block' : 'none';
    if (text) el.querySelector('.hint-text').textContent = text;
  }

  // ---- event feed ----
  const seenEvents = new Set();
  const EVENT_TEXT = {
    cipher_done: (e) => `\u6697\u53f7\u6a5f\u89e3\u8aad\u5b8c\u4e86 (${(e.cipher != null ? e.cipher + 1 : '?')}\u53f7\u6a5f)`,
    gate_open: () => '\u30b2\u30fc\u30c8\u304c\u958b\u3044\u305f\uff01 \u8131\u51fa\u305b\u3088\uff01',
    hit: (e) => `${e.who} \u304c\u653b\u6483\u3092\u53d7\u3051\u305f`,
    down: (e) => `${e.who} \u304c\u30c0\u30a6\u30f3\u3057\u305f`,
    rescue: (e) => `${e.by} \u304c ${e.who} \u3092\u6551\u52a9\u3057\u305f\uff01`,
    escaped: (e) => `${e.who} \u304c\u8131\u51fa\u3057\u305f\uff01`,
    eliminated: (e) => `${e.who} \u304c\u8131\u843d\u3057\u305f`,
    skill_miss: (e) => `${e.who} \u304c\u89e3\u8aad\u3092\u30df\u30b9\u3057\u305f\uff01`,
  };
  const DANGER_KINDS = new Set(['hit', 'down', 'eliminated', 'skill_miss']);
  const GOOD_KINDS = new Set(['rescue', 'escaped', 'cipher_done', 'gate_open']);

  function pushEvents(events) {
    if (!events) return;
    const feed = $('event-feed');
    for (const e of events) {
      const key = e.t + ':' + e.kind + ':' + (e.who || e.cipher || '');
      if (seenEvents.has(key)) continue;
      seenEvents.add(key);
      const fn = EVENT_TEXT[e.kind];
      if (!fn) continue;
      const div = document.createElement('div');
      div.className = 'event-item'
        + (DANGER_KINDS.has(e.kind) ? ' danger' : '')
        + (GOOD_KINDS.has(e.kind) ? ' good' : '');
      div.textContent = fn(e);
      feed.prepend(div);
      setTimeout(() => div.remove(), 6000);
      while (feed.children.length > 5) feed.lastChild.remove();
    }
  }

  function resetFeed() {
    seenEvents.clear();
    $('event-feed').innerHTML = '';
  }

  // ------------------------------------------------------------------
  // result screen
  // ------------------------------------------------------------------
  const OUTCOME = {
    survivors_win: ['\u30b5\u30d0\u30a4\u30d0\u30fc\u52dd\u5229', 'win'],
    hunter_wins: ['\u30cf\u30f3\u30bf\u30fc\u52dd\u5229', 'lose'],
    time_up: ['\u6642\u9593\u5207\u308c', 'lose'],
  };
  const STATE_TEXT = {
    escaped: '\u8131\u51fa', eliminated: '\u8131\u843d',
    alive: '\u751f\u5b58', down: '\u30c0\u30a6\u30f3',
  };

  function showResult(result, myId, mySurvivorName) {
    show('ov-result');
    const [label, cls] = OUTCOME[result.outcome] || [result.outcome, ''];
    const el = $('result-outcome');
    el.textContent = label;
    el.className = 'result-outcome ' + cls;

    const tbody = $('result-body');
    tbody.innerHTML = '';
    for (const s of result.survivors) {
      const tr = document.createElement('tr');
      const me = s.name === mySurvivorName;
      tr.innerHTML =
        `<td>${me ? '\u25b6 ' : ''}${escapeHtml(s.name)}${s.bot ? ' <span class="bot-tag">CPU</span>' : ''}</td>` +
        `<td class="st-${s.state}">${STATE_TEXT[s.state] || s.state}</td>` +
        `<td>\u89e3\u8aad ${s.decoded}</td>` +
        `<td>\u6551\u52a9 ${s.rescues ?? 0}</td>`;
      tbody.appendChild(tr);
    }
    $('result-ciphers').textContent =
      `\u89e3\u8aad\u5b8c\u4e86: ${result.ciphers_done} / 5`;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  return {
    show, showGame, showNameEntry, showLobby, showWait,
    updateHud, setDecodeHint, pushEvents, resetFeed, showResult,
  };
})();
