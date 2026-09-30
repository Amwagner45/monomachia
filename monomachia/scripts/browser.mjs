// Headless browser check: loads the built single-file game, drives it
// deterministically through test hooks, captures screenshots and console errors.
// Usage: npm run build && node scripts/browser.mjs <scenario> [args...]
// Scenarios: menus, fight, watch, versus, padseats, gamepad, controls, results,
// events, poses, phone, audio, fallback, fallback2, lightprobe, perf.
// Env: SHOTS (screenshot folder, default ./shots), Q=low (fast renderer), W/H (viewport).
// Needs Playwright: npm i -D playwright && npx playwright install chromium
// (or point NPM_GLOBAL at a global node_modules folder that has it).
import { createRequire } from 'module';
import http from 'http';
import fs from 'fs';
import path from 'path';

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  if (!process.env.NPM_GLOBAL) {
    console.error('Playwright not found. Run: npm i -D playwright && npx playwright install chromium');
    process.exit(1);
  }
  ({ chromium } = createRequire(path.join(process.env.NPM_GLOBAL, '/'))('playwright'));
}

const scenario = process.argv[2] ?? 'menus';
const args = process.argv.slice(3);
const outDir = process.env.SHOTS ?? 'shots';
const quality = process.env.Q ?? 'high';
const vw = Number(process.env.W ?? 1280);
const vh = Number(process.env.H ?? 720);
fs.mkdirSync(outDir, { recursive: true });
// Test exactly what ships: the artifact page wrapped like the publisher does.
const inner = fs.readFileSync(path.resolve('dist/monomachia.html'), 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><style>:root{color-scheme:light;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}body{margin:0;font:14px system-ui;background:#fafaf7}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${inner}</body></html>`;

const srv = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});
await new Promise((r) => srv.listen(8766, r));

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: vw, height: vh } });
await page.emulateMedia({ reducedMotion: 'reduce' });
const errors = [];
page.on('console', (m) => {
  if (m.type() === 'error' || m.type() === 'warning') errors.push(`${m.type()}: ${m.text()}`);
  if (m.type() === 'log') console.log('page:', m.text());
});
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
await page.goto('http://localhost:8766/' + (quality === 'low' ? '#low' : ''));
await page.waitForFunction(() => window.__game, null, { timeout: 30000 });
await page.evaluate(() => (window.__game.frozen = true));

const G = (fn, arg) => page.evaluate(fn, arg);
const render = (k = 2) => G((k) => { for (let i = 0; i < k; i++) window.__game.debugRender(); }, k);
const advance = (n) => G((n) => window.__game.debugAdvance(n), n);
const snap = async (name, k = 2) => {
  await render(k);
  await page.waitForTimeout(350);
  await page.screenshot({ path: `${outDir}/${name}.png` });
  console.log('shot', name);
};
const ABIL = { katana: ['k_flash', 'k_thrust'], greatsword: ['g_sweep', 'g_slam'], daggers: ['d_sweep', 'd_shadow'] };
async function startMatch(mode, w1, w2, ai1 = null, ai2 = 'normal') {
  await G(({ mode, w1, w2, ai1, ai2, ABIL }) => {
    const g = window.__game;
    g.startMatch({ mode, p1: { weapon: w1, abilities: ABIL[w1], ai: ai1 }, p2: { weapon: w2, abilities: ABIL[w2], ai: ai2 } });
  }, { mode, w1, w2, ai1, ai2, ABIL });
}
const state = () => G(() => window.__game.world.fighters.map((f) => ({ hp: +f.hp.toFixed(1), posture: +f.posture.toFixed(1), state: f.state, armed: f.armed, x: +f.pos.x.toFixed(2), z: +f.pos.z.toFixed(2) })));

try {
  if (scenario === 'menus') {
    await snap('m01-title', 1);
    await G(() => { const g = window.__game; g.audio.init(); g.menus.showMain(); });
    await snap('m02-main', 1);
    for (const s of ['select-duel', 'select-training', 'controls', 'howto', 'settings', 'pause']) {
      await G((s) => {
        const m = window.__game.menus;
        if (s === 'select-duel') m.showSelect('duel');
        if (s === 'select-training') m.showSelect('training');
        if (s === 'controls') m.showControls(() => m.showMain());
        if (s === 'howto') m.showHowTo(() => m.showMain());
        if (s === 'settings') m.showSettings(() => m.showMain());
        if (s === 'pause') m.showPause();
      }, s);
      await snap(`m-${s}`, 1);
    }
  } else if (scenario === 'fight') {
    // human P1 idle vs AI; or AI vs AI when args[0] === 'ai'
    const w1 = args[1] ?? 'katana';
    const w2 = args[2] ?? 'greatsword';
    await startMatch('duel', w1, w2, args[0] === 'ai' ? 'hard' : null, 'hard');
    await snap('f00-start', 1);
    await advance(70);
    await snap('f01-round');
    await advance(40);
    await snap('f02-fight');
    for (let i = 0; i < 10; i++) {
      await advance(55);
      await snap(`f${String(i + 3).padStart(2, '0')}`);
      console.log(JSON.stringify(await state()));
    }
  } else if (scenario === 'watch') {
    await startMatch('watch', args[0] ?? 'katana', args[1] ?? 'daggers', 'hard', 'hard');
    await advance(110);
    for (let i = 0; i < 12; i++) {
      await advance(Number(args[2] ?? 70));
      await snap(`w${String(i).padStart(2, '0')}`);
      console.log(JSON.stringify(await state()));
    }
  } else if (scenario === 'poses') {
    // pose a fighter mid-move for inspection (side camera)
    const w1 = args[0] ?? 'katana';
    const moves = JSON.parse(args[1] ?? '["k_l1"]');
    const fracs = JSON.parse(args[2] ?? '[0.6, 1.0, 1.1, 1.2, 1.5]');
    await startMatch('duel', w1, 'katana', null, null);
    await advance(100);
    for (const id of moves) {
      for (const frac of fracs) {
        await G(({ id, frac }) => {
          const g = window.__game;
          const W = g.world;
          const f = W.fighters[0];
          const o = W.fighters[1];
          f.pos = { x: 0, y: 0, z: -1.3 };
          o.pos = { x: 0, y: 0, z: 1.3 };
          f.yaw = 0;
          o.yaw = Math.PI;
          f.setState('free');
          o.setState('free');
          f.startAttack(id);
          const d = f.atk.def;
          const S = d.startup;
          const A = d.active;
          let fr;
          if (frac <= 1) fr = S * frac;
          else if (frac <= 1.2) fr = S + (A * (frac - 1)) / 0.2;
          else fr = S + A + d.recovery * (frac - 1.2) / 0.8;
          f.atk.frame = Math.max(0, Math.round(fr));
          g.view.camMode = 'cinematic';
          for (let k = 0; k < 24; k++) g.view.update(1 / 60, 10 + k / 60, 0);
          const cam = g.view.cam.camera;
          cam.position.set(3.2, 1.6, -0.6);
          cam.lookAt(0, 1.1, -0.4);
          g.view.draw(1 / 60);
        }, { id, frac });
        await page.screenshot({ path: `${outDir}/pose-${id}-${frac}.png` });
        console.log('shot pose', id, frac);
      }
    }
  } else if (scenario === 'phone') {
    await page.setViewportSize({ width: 400, height: 820 });
    await snap('p-title', 1);
    await G(() => window.__game.menus.showSelect('duel'));
    await snap('p-select', 1);
    const sw1 = await G(() => document.documentElement.scrollWidth);
    await startMatch('duel', 'katana', 'greatsword', null, 'normal');
    await advance(160);
    await snap('p-fight');
    const sw2 = await G(() => document.documentElement.scrollWidth);
    console.log('scrollWidth', sw1, sw2);
  } else if (scenario === 'controls') {
    await startMatch('training', 'katana', 'katana', null, null);
    await advance(105);
    const log = async (label) => console.log(label, JSON.stringify((await state())[0]), await G(() => { const f = window.__game.world.fighters[0]; return f.atk ? f.atk.def.id : f.state; }));
    await log('start');
    await page.keyboard.down('KeyW');
    await advance(30);
    await log('after W 0.5s');
    await page.keyboard.up('KeyW');
    await advance(10);
    // tap step to the right
    await page.keyboard.down('KeyD');
    await advance(3);
    await page.keyboard.up('KeyD');
    await advance(12);
    await log('after tap D');
    // double-tap and hold W = sprint
    await page.keyboard.down('KeyW'); await advance(3); await page.keyboard.up('KeyW'); await advance(3);
    await page.keyboard.down('KeyW'); await advance(20);
    console.log('sprinting?', await G(() => window.__game.world.fighters[0].sprintFrames));
    await page.keyboard.up('KeyW');
    await advance(20);
    // dodge left
    await page.keyboard.down('KeyA'); await page.keyboard.down('Space'); await advance(2);
    await log('dodge');
    await page.keyboard.up('Space'); await page.keyboard.up('KeyA'); await advance(30);
    // light attack with mouse
    await page.mouse.move(vw / 2, vh / 2);
    await page.mouse.down({ button: 'left' }); await advance(2); await page.mouse.up({ button: 'left' });
    await advance(3);
    await log('light click');
    await advance(40);
    // heavy with right click
    await page.mouse.down({ button: 'right' }); await advance(2); await page.mouse.up({ button: 'right' });
    await advance(3);
    await log('heavy click');
    await advance(60);
    // block ability: hold shift + right click => thrust
    await page.keyboard.down('ShiftLeft'); await advance(2);
    await page.mouse.down({ button: 'right' }); await advance(2); await page.mouse.up({ button: 'right' });
    await advance(3);
    await log('shift+right');
    await page.keyboard.up('ShiftLeft');
    await advance(60);
    // jump
    await page.keyboard.down('KeyF'); await advance(2); await page.keyboard.up('KeyF'); await advance(8);
    await log('jump');
    await advance(40);
    // hold block
    await page.keyboard.down('ShiftLeft'); await advance(5);
    console.log('blocking?', await G(() => window.__game.world.fighters[0].blocking));
    await page.keyboard.up('ShiftLeft'); await advance(5);
    // escape pauses
    await G(() => (window.__game.frozen = false));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(4500);
    console.log('mode after Esc', await G(() => window.__game.mode), await G(() => window.__game.menus.screen));
  } else if (scenario === 'events') {
    await startMatch('watch', args[0] ?? 'katana', args[1] ?? 'greatsword', 'hard', 'hard');
    await G(() => {
      const g = window.__game;
      window.__ev = [];
      const orig = g.view.handleEvents.bind(g.view);
      g.view.handleEvents = (evs) => { for (const e of evs) window.__ev.push(e.t === 'counter' ? 'counter-' + e.kind : e.t === 'ultStart' ? 'ult-' + e.ult : e.t); orig(evs); };
    });
    const want = { disarm: 2, 'ult-moonsplitter': 1, 'ult-impaler': 1, 'ult-tempest': 1, ultChoice: 1, ultWave: 1, ultImpale: 1, ultBurst: 1, 'counter-stomp': 1, 'counter-leap': 1, 'counter-evade': 1, ko: 2, pickup: 1, recall: 1, stagger: 1, telegraph: 1 };
    const got = {};
    let n = 0;
    for (let it = 0; it < 4000; it++) {
      await advance(4);
      const evs = await G(() => { const e = window.__ev; window.__ev = []; return e; });
      const hit = evs.find((e) => want[e] && (got[e] ?? 0) < want[e]);
      if (hit) {
        got[hit] = (got[hit] ?? 0) + 1;
        await advance(hit === 'ko' ? 20 : hit.startsWith('ult') ? 10 : 3);
        await snap(`e${String(n++).padStart(2, '0')}-${hit}`);
      }
      const phase = await G(() => window.__game.match.phase);
      if (phase === 'matchEnd') {
        await advance(200);
        await G(() => { window.__game.frozen = false; });
        await page.waitForTimeout(9000);
        await G(() => { window.__game.frozen = true; });
        await snap('e99-results');
        break;
      }
    }
    console.log('captured', JSON.stringify(got), JSON.stringify(await G(() => window.__game.match.wins)));
  } else if (scenario === 'gamepad') {
    await G(() => {
      window.__pad = {
        id: 'DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)', index: 0, connected: true, mapping: 'standard', timestamp: 0,
        axes: [0, 0, 0, 0], buttons: Array.from({ length: 18 }, () => ({ pressed: false, value: 0, touched: false })),
      };
      navigator.getGamepads = () => [window.__pad, null, null, null];
      window.__press = (i, v) => { window.__pad.buttons[i].pressed = v; window.__pad.buttons[i].value = v ? 1 : 0; };
    });
    // menu navigation: ✕ confirms on the title, D-pad down + ✕ opens Training select
    const poll = () => G(() => { const g = window.__game; g.devices.poll(performance.now()); for (const ev of g.devices.drainMenu()) if (g.menus.open) g.menus.nav(ev); });
    await G(() => window.__press(0, true)); await poll(); await G(() => window.__press(0, false)); await poll();
    console.log('after X on title:', await G(() => window.__game.menus.screen), 'style', await G(() => window.__game.devices.padStyle));
    await G(() => window.__press(13, true)); await poll(); await G(() => window.__press(13, false)); await poll();
    await G(() => window.__press(0, true)); await poll(); await G(() => window.__press(0, false)); await poll();
    console.log('after down + X:', await G(() => window.__game.menus.screen));
    await startMatch('training', 'katana', 'katana', null, null);
    await advance(105);
    // stick forward
    await G(() => { window.__pad.axes[1] = -1; window.__game.devices.poll(); });
    await advance(20);
    await G(() => { window.__pad.axes[1] = 0; window.__game.devices.poll(); });
    console.log('moved to z =', (await state())[0].z);
    await G(() => { window.__press(5, true); window.__game.devices.poll(); });
    await advance(2);
    await G(() => { window.__press(5, false); window.__game.devices.poll(); });
    console.log('R1 ->', await G(() => { const f = window.__game.world.fighters[0]; return f.atk ? f.atk.def.id : f.state; }));
    console.log('label light =', await G(() => window.__game.label('light')), 'heavy =', await G(() => window.__game.label('heavy')));
    await advance(40);
    // fight stick preset: □ = light
    await G(() => { const g = window.__game; g.profile.pad = JSON.parse(JSON.stringify({ ...g.profile.pad, light: ['b:2'], heavy: ['b:3'], block: ['b:5'] })); });
    await G(() => { window.__press(2, true); window.__game.devices.poll(); });
    await advance(2);
    await G(() => { window.__press(2, false); window.__game.devices.poll(); });
    console.log('□ (fight stick) ->', await G(() => { const f = window.__game.world.fighters[0]; return f.atk ? f.atk.def.id : f.state; }));
  } else if (scenario === 'audio') {
    const r = await G(async () => {
      const g = window.__game;
      g.audio.init();
      await g.audio.ctx.resume();
      const a = g.audio;
      a.clang(true); a.parryClang('parry'); a.parryClang('flash'); a.parryClang('redirect'); a.slice(true, false); a.crush(); a.punch(true);
      a.whoosh(true, 'greatsword'); a.dodge(); a.land(); a.taiko(); a.telegraph(); a.gong(); a.disarm(); a.bounce(5); a.ultStart(); a.boom(); a.lightning(); a.wave(); a.uiMove(); a.uiSelect();
      a.setMusic('fight');
      await new Promise((res) => setTimeout(res, 2500));
      a.setMusic('menu');
      await new Promise((res) => setTimeout(res, 1500));
      return { state: a.ctx.state, t: a.ctx.currentTime };
    });
    console.log('audio', JSON.stringify(r));
  } else if (scenario === 'results') {
    await startMatch('duel', 'katana', 'greatsword', null, null);
    await advance(110);
    // force three quick round wins for the player
    for (let r = 0; r < 3; r++) {
      for (let k = 0; k < 100 && (await G(() => window.__game.match.phase)) !== 'fight'; k++) await advance(10);
      await G(() => { const W = window.__game.world; W.fighters[1].hp = 0.5; });
      await G(() => { const W = window.__game.world; const [a, b] = W.fighters; a.pos = { x: 0, y: 0, z: -1 }; b.pos = { x: 0, y: 0, z: 1 }; a.yaw = 0; b.setState('free'); a.setState('free'); a.startAttack('k_l1'); });
      await advance(60);
    }
    for (let k = 0; k < 100 && (await G(() => window.__game.match.phase)) !== 'matchEnd'; k++) await advance(10);
    console.log('phase', await G(() => window.__game.match.phase), JSON.stringify(await G(() => window.__game.match.wins)));
    await advance(160);
    await snap('results', 1);
    console.log('screen', await G(() => window.__game.menus.screen));
  } else if (scenario === 'versus') {
    await G(() => {
      const g = window.__game;
      g.startMatch({ mode: 'versus', p1: { weapon: 'katana', abilities: ['k_flash', 'k_thrust'], ai: null }, p2: { weapon: 'daggers', abilities: ['d_sweep', 'd_shadow'], ai: null }, devices: ['kbm', 'kbArrows'], profiles: [0, 0] });
    });
    await advance(105);
    await snap('v00-start');
    // P1 walks forward with W, P2 walks forward with ArrowUp
    await page.keyboard.down('KeyW'); await page.keyboard.down('ArrowUp');
    await advance(25);
    await page.keyboard.up('KeyW'); await page.keyboard.up('ArrowUp');
    await advance(5);
    console.log(JSON.stringify(await state()));
    // P2 attacks with J (must not trigger P1's J alternate)
    await page.keyboard.down('KeyJ'); await advance(2); await page.keyboard.up('KeyJ'); await advance(3);
    console.log('after J:', JSON.stringify(await G(() => window.__game.world.fighters.map((f) => (f.atk ? f.atk.def.id : f.state)))));
    await advance(30);
    // P1 clicks
    await page.mouse.move(vw / 4, vh / 2);
    await page.mouse.down({ button: 'left' }); await advance(2); await page.mouse.up({ button: 'left' }); await advance(3);
    console.log('after click:', JSON.stringify(await G(() => window.__game.world.fighters.map((f) => (f.atk ? f.atk.def.id : f.state)))));
    await advance(8);
    await snap('v01-clash');
    console.log('labels', await G(() => [window.__game.label('light', 0), window.__game.label('light', 1), window.__game.label('dodge', 1)]));
  } else if (scenario === 'padseats') {
    // two controllers; unplugging controller 1 must not hand player 2's pad to player 1,
    // and closing the pause menu with the pause button must not pause again
    await G(() => {
      const mk = (index, id) => ({ id, index, connected: true, mapping: 'standard', timestamp: 0, axes: [0, 0, 0, 0], buttons: Array.from({ length: 18 }, () => ({ pressed: false, value: 0, touched: false })) });
      window.__pads = [mk(0, 'DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)'), mk(1, 'Xbox Wireless Controller (STANDARD GAMEPAD Vendor: 045e Product: 0b13)')];
      window.__plugged = [true, true];
      navigator.getGamepads = () => [window.__plugged[0] ? window.__pads[0] : null, window.__plugged[1] ? window.__pads[1] : null, null, null];
      window.__press = (p, i, v) => { const b = window.__pads[p].buttons[i]; b.pressed = v; b.value = v ? 1 : 0; };
      // the input half of the real loop, without rendering
      window.__tick = () => {
        const g = window.__game;
        g.devices.poll(performance.now());
        for (const ev of g.devices.drainMenu()) {
          if (g.menus.open) g.menus.nav(ev);
          else if (g.mode === 'playing' && (ev === 'back' || ev === 'pause')) g.pause();
        }
        if (g.mode === 'playing' && g.devices.gameActive) {
          const n = g.config && g.config.mode === 'versus' ? 2 : 1;
          for (let i = 0; i < n; i++) if (g.devices.pausePressed(g.profileFor(i), g.deviceFor(i), g.excludeFor(i))) g.pause();
        }
        return g.mode;
      };
      window.__game.devices.poll();
    });
    const tick = () => G(() => window.__tick());
    const acting = () => G(() => window.__game.world.fighters.map((f) => (f.atk ? f.atk.def.id : f.state)));
    await G(() => window.__game.startMatch({ mode: 'versus', p1: { weapon: 'katana', abilities: ['k_flash', 'k_thrust'], ai: null }, p2: { weapon: 'daggers', abilities: ['d_sweep', 'd_shadow'], ai: null }, devices: ['pad0', 'pad1'], profiles: [0, 0] }));
    await advance(105);
    await G(() => window.__press(1, 5, true)); await tick(); await advance(2); await G(() => window.__press(1, 5, false)); await tick();
    console.log('pad#1 R1 ->', JSON.stringify(await acting()));
    await advance(50);
    await G(() => { window.__plugged[0] = false; }); await tick();
    await G(() => window.__press(1, 5, true)); await tick(); await advance(2); await G(() => window.__press(1, 5, false)); await tick();
    console.log('pad#0 unplugged, pad#1 R1 ->', JSON.stringify(await acting()), 'labels', JSON.stringify(await G(() => [window.__game.label('light', 0), window.__game.label('light', 1)])));
    await advance(50);
    await G(() => { window.__plugged[0] = true; }); await tick();
    await G(() => window.__press(0, 5, true)); await tick(); await advance(2); await G(() => window.__press(0, 5, false)); await tick();
    console.log('pad#0 back, pad#0 R1 ->', JSON.stringify(await acting()));
    await advance(50);
    // pause with Options on pad 1, then close the menu with Options again
    const seq = [];
    await G(() => window.__press(1, 9, true)); seq.push(await tick()); seq.push(await tick());
    await G(() => window.__press(1, 9, false)); seq.push(await tick());
    await G(() => window.__press(1, 9, true)); seq.push(await tick()); seq.push(await tick()); seq.push(await tick());
    await G(() => window.__press(1, 9, false)); seq.push(await tick());
    console.log('pause/resume with Options:', seq.join(' '));
    // same with Escape on the keyboard in a duel
    await startMatch('duel', 'katana', 'greatsword', null, 'normal');
    await advance(105);
    const seq2 = [];
    await page.keyboard.down('Escape'); seq2.push(await tick()); seq2.push(await tick());
    await page.keyboard.up('Escape'); seq2.push(await tick());
    await page.keyboard.down('Escape'); seq2.push(await tick()); seq2.push(await tick());
    await page.keyboard.up('Escape'); seq2.push(await tick());
    console.log('pause/resume with Esc:', seq2.join(' '));
  } else if (scenario === 'fallback') {
    await startMatch('duel', 'katana', 'greatsword', null, 'normal');
    await advance(100);
    const r = await G(() => {
      const g = window.__game;
      const THREE_ = g.view.scene.constructor; // scene exists; build a broken material via an existing mesh's material class
      const mesh = g.view.rigs[0].root.children[0];
      // inject a material with invalid GLSL to trigger a compile failure
      const bad = new (g.view.fx.sparks.material.constructor)({ vertexShader: 'void main(){ gl_Position = vec4(0.0); }', fragmentShader: 'void main(){ this is not glsl; }' });
      const probe = g.view.fx.sparks.points.clone();
      probe.material = bad;
      g.view.scene.add(probe);
      g.debugRender();
      return new Promise((res) => setTimeout(() => { g.debugRender(); res({ level: g.view.safeLevel, errors: (window.__shaderErrors || []).length, shadows: g.view.renderer.shadowMap.enabled }); }, 50));
    });
    console.log('fallback', JSON.stringify(r));
    await snap('fallback'); // one broken effect: it is swapped for a plain material, the rest untouched
    console.log('after one broken effect: level', await G(() => window.__game.view.safeLevel), 'probe material', await G(() => window.__game.view.scene.children.at(-1).material.type));
    await G(() => window.__game.view.fallBack());
    await snap('fallback-level1');
    await G(() => window.__game.view.fallBack());
    await snap('fallback-level2');
    console.log('level now', await G(() => window.__game.view.safeLevel));
  } else if (scenario === 'readme') {
    // action shots for the README: wait for a moment in a computer-vs-computer fight, then capture it
    const until = async (type, limit) => {
      for (let i = 0; i < limit; i += 1) {
        const hit = await G((t) => {
          const g = window.__game;
          if (!g.__hooked) {
            g.__hooked = true;
            const orig = g.view.handleEvents.bind(g.view);
            g.view.handleEvents = (evs) => { for (const e of evs) window.__evs.push(e.t); orig(evs); };
          }
          window.__evs = [];
          g.debugAdvance(1);
          return window.__evs.includes(t);
        }, type);
        if (hit) return true;
      }
      return false;
    };
    await startMatch('watch', 'katana', 'greatsword', 'hard', 'hard');
    await advance(100);
    if (await until('parry', 4000)) { await advance(3); await snap('readme-parry', 1); }
    await G(() => { const f = window.__game.world.fighters[0]; f.hp = Math.min(f.hp, 20); });
    if (await until('ultWave', 4000)) { await advance(10); await snap('readme-ultimate', 1); }
    // split screen: a Versus match driven by two computer players
    await G(() => {
      const g = window.__game;
      const Brain = g.brains[0].constructor;
      const params = g.brains[0].params;
      g.startMatch({ mode: 'versus', p1: { weapon: 'daggers', abilities: ['d_sweep', 'd_shadow'], ai: null }, p2: { weapon: 'greatsword', abilities: ['g_sweep', 'g_slam'], ai: null }, devices: ['kbm', 'pad0'], profiles: [0, 0] });
      g.brains = g.world.fighters.map((f, i) => new Brain(f, params, 7 + i));
    });
    await advance(100);
    if (await until('block', 3000)) { await advance(2); await snap('readme-versus', 1); }
  } else if (scenario === 'wave') {
    // both Moonsplitter shapes, seen from the side: the crescent must lead, in front of the caster
    for (const variant of ['horizontal', 'vertical']) {
      await startMatch('watch', 'katana', 'greatsword', 'normal', 'normal');
      await advance(100);
      await G((variant) => {
        const g = window.__game;
        g.brains = [null, null]; // hold both fighters still
        const [a, b] = g.world.fighters;
        a.pos = { x: -4, y: 0, z: 0 }; b.pos = { x: 4, y: 0, z: 0 };
        a.yaw = Math.PI / 2; b.yaw = -Math.PI / 2;
        a.hp = 20;
        a.startUlt();
        a.ult.variant = variant;
      }, variant);
      await advance(44);
      await snap(`wave-${variant}`, 1);
      console.log(variant, 'blue hp after:', await G(() => { window.__game.debugAdvance(40); return window.__game.world.fighters[1].hp; }));
    }
  } else if (scenario === 'fallback2') {
    // recreate the original bug: every lit (standard) material loses a shader chunk
    await startMatch('duel', 'katana', 'greatsword', null, 'normal');
    await advance(100);
    await G(() => {
      let proto = null;
      window.__game.view.scene.traverse((o) => {
        const ms = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : [];
        for (const m of ms) if (m.isMeshStandardMaterial) { proto ??= Object.getPrototypeOf(m); m.needsUpdate = true; }
      });
      // break every standard material, including ones created later
      proto.onBeforeCompile = function (s) { s.fragmentShader = s.fragmentShader.replace('#include <metalnessmap_fragment>', ''); };
    });
    for (let i = 0; i < 4; i++) { await render(1); console.log('frame', i, 'level', await G(() => window.__game.view.safeLevel)); }
    await snap('fallback2');
    // a new match builds new fighters whose shaders are already known to be broken
    await startMatch('duel', 'daggers', 'katana', null, 'normal');
    await advance(100);
    await snap('fallback2-newmatch-f1', 1);
    await render(40);
    await snap('fallback2-newmatch', 1);
    console.log('new match materials', JSON.stringify(await G(() => { const t = {}; window.__game.view.rigs[0].root.traverse((o) => { if (o.material) t[o.material.type] = (t[o.material.type] || 0) + 1; }); return t; })));
    // hit flashes animate the original materials; the safe stand-ins must follow them
    console.log('hit flash reaches safe materials:', await G(() => {
      const g = window.__game;
      const rig = g.view.rigs[1];
      rig.hitFlash(0xff0000, 1);
      g.view.update(1 / 60, 100, 0);
      const body = new Set(rig.mats.map((m) => m.emissive));
      let seen = 0, lit = 0;
      rig.root.traverse((o) => { const m = o.material; if (m && m.type === 'MeshPhongMaterial' && body.has(m.emissive)) { seen++; if (m.emissiveIntensity > 0.5 && m.emissive.r > 0.9) lit++; } });
      return `${lit}/${seen} body parts flashing`;
    }));
    await snap('fallback2-flash', 1);
  } else if (scenario === 'lightprobe') {
    // measure how bright the floor and the near fighter are at each safe level
    await startMatch('duel', 'katana', 'greatsword', null, 'normal');
    await advance(100);
    const sample = () => G(() => {
      const g = window.__game;
      g.debugRender();
      const c = g.view.renderer.domElement;
      const gl = g.view.renderer.getContext();
      const px = new Uint8Array(4);
      const at = (fx, fy) => { gl.readPixels(Math.floor(c.width * fx), Math.floor(c.height * (1 - fy)), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px); return [...px.slice(0, 3)]; };
      return { floorNear: at(0.3, 0.85), floorMid: at(0.7, 0.6), fighter: at(0.47, 0.62), hemi: g.view.arena.hemi.intensity, level: g.view.safeLevel };
    });
    await G(() => { window.__game.view.renderer.getContext().getContextAttributes(); });
    console.log('L0', JSON.stringify(await sample()));
    await G(() => window.__game.view.fallBack()); await render(1);
    console.log('L1', JSON.stringify(await sample()));
    await G(() => window.__game.view.fallBack()); await render(1);
    console.log('L2', JSON.stringify(await sample()));
    for (const k of [1.0, 4.0, 8.0]) {
      await G((k) => { window.__game.view.arena.hemi.intensity = k; }, k);
      console.log('L2 hemi', k, JSON.stringify(await sample()));
    }
  } else if (scenario === 'perf') {
    await startMatch('watch', 'katana', 'greatsword', 'normal', 'normal');
    await advance(200);
    const t = await G(() => {
      const g = window.__game;
      const t0 = performance.now();
      for (let i = 0; i < 5; i++) g.debugRender();
      const t1 = performance.now();
      for (let i = 0; i < 600; i++) g.debugAdvance(1);
      const t2 = performance.now();
      return { renderMs: (t1 - t0) / 5, simMsPerFrame: (t2 - t1) / 600, calls: g.view.renderer.info.render.calls, tris: g.view.renderer.info.render.triangles };
    });
    console.log(JSON.stringify(t));
  }
} catch (e) {
  console.log('SCENARIO ERROR', e);
}

const shaderErrors = await page.evaluate(() => window.__shaderErrors ?? []).catch(() => []);
console.log('SHADER ERRORS:', shaderErrors.length);
console.log('--- console errors/warnings ---');
for (const e of errors.slice(0, 40)) console.log(e);
await browser.close();
srv.close();
