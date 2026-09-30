// Top-level orchestrator: game modes, the fixed-step loop, and the glue
// between simulation, rendering, audio, HUD and menus.

import { AudioEngine } from './audio/audio';
import { KB_ARROWS, ProfileStore, bindingLabel, loadProfiles, tokensOf } from './input/bindings';
import { DeviceId, InputDevices } from './input/devices';
import { View } from './render/view';
import { AIBrain, DIFFICULTY } from './sim/ai/brain';
import { TrainingBehaviour, TrainingBrain } from './sim/ai/training';
import { DT, HP_MAX } from './sim/constants';
import { RawInput, emptyInput } from './sim/input';
import { Match } from './sim/match';
import { WEAPONS } from './sim/moves';
import type { WeaponId } from './sim/moves/types';
import { World } from './sim/world';
import { TRAINING_BEHAVIOURS } from './ui/data';
import { h } from './ui/dom';
import { Hud } from './ui/hud';
import { MatchConfig, Menus, Settings } from './ui/menus';

type Mode = 'attract' | 'playing' | 'paused' | 'results';

function loadSettings(): Settings {
  const reduce = typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const s: Settings = { quality: 'high', reduceFlashes: reduce, showHints: true };
  try {
    const raw = localStorage.getItem('monomachia.settings');
    if (raw) Object.assign(s, JSON.parse(raw));
  } catch {
    /* ignore */
  }
  // test hook: #low forces the fast renderer
  if (typeof location !== 'undefined' && location.hash === '#low') s.quality = 'low';
  return s;
}

export class Game {
  view: View;
  audio = new AudioEngine();
  devices: InputDevices;
  hud: Hud;
  menus: Menus;
  profiles: ProfileStore = loadProfiles();
  settings = loadSettings();

  world!: World;
  match!: Match;
  brains: (AIBrain | TrainingBrain | null)[] = [null, null];
  config: MatchConfig | null = null;
  mode: Mode = 'attract';
  private acc = 0;
  private last = 0;
  private time = 0;
  private resultAt = -1;
  private trainingBrain: TrainingBrain | null = null;
  private refill = true;
  private lastHurt = [0, 0];
  private prevHp = [HP_MAX, HP_MAX];
  private seed = 1;

  constructor(private app: HTMLElement) {
    const stage = app.querySelector<HTMLElement>('#stage')!;
    const screens = app.querySelector<HTMLElement>('#screens')!;
    this.view = new View(stage, this.settings.quality);
    this.devices = new InputDevices(app);
    this.hud = new Hud(app);
    this.hud.labelFn = (a) => this.label(a);
    this.view.onSafeMode = (level) => {
      this.hud.toast('Safe graphics', 'dim', level === 1 ? 'Shadows and reflections turned off for this device' : 'Simplified lighting for this device');
    };
    this.menus = new Menus(screens, this.devices, this.audio, this.profiles, this.settings, {
      start: (cfg) => this.startMatch(cfg),
      resume: () => this.resume(),
      restart: () => this.config && this.startMatch(this.config),
      quitToMenu: () => this.quitToMenu(),
      settingsChanged: () => this.applySettings(),
      enteredMenus: () => this.audio.setMusic('menu'),
    });
    this.applySettings();

    window.addEventListener('blur', () => {
      if (this.mode === 'playing') this.pause();
    });
    window.addEventListener('keydown', (e) => this.trainingKeys(e));

    this.startAttract();
    this.menus.showTitle();
    requestAnimationFrame((t) => this.loop(t));
    (window as unknown as { __game: Game }).__game = this;
  }

  get profile() {
    return this.profiles.profiles[this.profiles.active];
  }

  private versus() {
    return this.config?.mode === 'versus' && this.mode !== 'attract';
  }

  profileFor(player: number) {
    if (this.versus()) {
      const idx = this.config?.profiles?.[player] ?? this.profiles.active;
      return this.profiles.profiles[idx] ?? this.profile;
    }
    return this.profile;
  }

  deviceFor(player: number): DeviceId {
    return this.versus() ? this.config?.devices?.[player] ?? (player === 0 ? 'kbm' : 'pad0') : 'all';
  }

  /** Keys one player must ignore because the other player's layout uses them. */
  private excludeFor(player: number): Set<string> | undefined {
    if (!this.versus()) return undefined;
    const other = this.deviceFor(1 - player);
    return other === 'kbArrows' && this.deviceFor(player) === 'kbm' ? tokensOf(KB_ARROWS) : undefined;
  }

  /** Human-readable binding for an action on the device a player is using. */
  label(action: string, player = 0) {
    const a = action as keyof typeof this.profile.kb;
    const dev = this.deviceFor(player);
    const prof = this.profileFor(player);
    const pad = dev === 'pad0' || dev === 'pad1' || (dev === 'all' && this.devices.lastDevice === 'pad' && !!this.devices.pad);
    const list = dev === 'kbArrows' ? KB_ARROWS[a] : pad ? prof.pad[a] : prof.kb[a];
    const ex = this.excludeFor(player);
    const tok = list?.find((t) => !t.startsWith('a:') && !ex?.has(t)) ?? list?.[0];
    return tok ? bindingLabel(tok, pad ? this.devices.padStyleFor(dev) : 'generic') : '';
  }

  private applySettings() {
    try {
      localStorage.setItem('monomachia.settings', JSON.stringify(this.settings));
    } catch {
      /* ignore */
    }
    this.view.setQuality(this.settings.quality);
    this.view.reduced = this.settings.reduceFlashes;
    this.hud.showHints = this.settings.showHints;
  }

  // ------------------------------------------------------------------ worlds

  private buildWorld(cfg: MatchConfig) {
    this.seed = (this.seed * 1103515245 + 12345) % 2147483647;
    const n1 = cfg.mode === 'watch' ? `Red ${WEAPONS[cfg.p1.weapon].name}` : cfg.mode === 'versus' ? 'Player 1' : 'You';
    const n2 = cfg.mode === 'training' ? 'Dummy' : cfg.mode === 'watch' ? `Blue ${WEAPONS[cfg.p2.weapon].name}` : cfg.mode === 'versus' ? 'Player 2' : 'Rival';
    const W = new World(
      { weapon: WEAPONS[cfg.p1.weapon], abilities: cfg.p1.abilities, name: n1 },
      { weapon: WEAPONS[cfg.p2.weapon], abilities: cfg.p2.abilities, name: n2 },
      this.seed,
    );
    this.world = W;
    this.match = new Match(W);
    this.trainingBrain = null;
    this.brains = [0, 1].map((i) => {
      const side = i === 0 ? cfg.p1 : cfg.p2;
      if (cfg.mode === 'training' && i === 1) {
        this.trainingBrain = new TrainingBrain(W.fighters[1]);
        return this.trainingBrain;
      }
      if (cfg.mode === 'versus') return null;
      return side.ai ? new AIBrain(W.fighters[i], DIFFICULTY[side.ai], this.seed + i * 17) : null;
    });
    if (cfg.mode === 'training') this.match.endless = true;
    this.view.playerIndex = 0;
    this.view.bindWorld(W);
    this.acc = 0;
  }

  private startAttract() {
    this.view.setSplit(false);
    const cfg: MatchConfig = {
      mode: 'watch',
      p1: { weapon: 'katana', abilities: [...WEAPONS.katana.defaultAbilities] as [string, string], ai: 'normal' },
      p2: { weapon: 'greatsword', abilities: [...WEAPONS.greatsword.defaultAbilities] as [string, string], ai: 'normal' },
    };
    this.mode = 'attract';
    this.view.camMode = 'menu';
    this.buildWorld(cfg);
    this.hud.show(false);
    this.devices.gameActive = false;
  }

  startMatch(cfg: MatchConfig) {
    this.audio.init();
    this.config = cfg;
    if (cfg.mode === 'versus') this.devices.bindSeats();
    else this.devices.unbindSeats();
    this.view.camMode = cfg.mode === 'watch' ? 'cinematic' : 'follow';
    this.view.setSplit(cfg.mode === 'versus');
    this.buildWorld(cfg);
    this.mode = 'playing';
    this.resultAt = -1;
    this.menus.hide();
    const [a, b] = this.world.fighters;
    this.hud.playerIndex = 0;
    this.hud.training = cfg.mode === 'training';
    this.hud.watch = cfg.mode === 'watch';
    this.hud.versus = cfg.mode === 'versus';
    this.hud.setup([a.name, b.name], [a.weapon.name, b.weapon.name]);
    this.hud.show(true);
    this.devices.gameActive = cfg.mode !== 'watch';
    this.audio.setMusic('fight');
    this.setupTrainingPanel();
    this.lastHurt = [0, 0];
    this.prevHp = [HP_MAX, HP_MAX];
    // drain the intro events into the HUD
    this.hud.handleEvents(this.world.drainEvents(), this.world, this.match);
  }

  pause() {
    if (this.mode !== 'playing') return;
    this.mode = 'paused';
    this.devices.gameActive = false;
    this.menus.showPause();
  }

  resume() {
    if (this.mode !== 'paused') return;
    this.menus.hide();
    this.mode = 'playing';
    this.devices.gameActive = this.config?.mode !== 'watch';
    this.last = performance.now();
    // the button that closed the menu may still be held: note it as "already
    // pressed" so it doesn't instantly pause the game again
    const n = this.versus() ? 2 : 1;
    for (let i = 0; i < n; i++) this.devices.pausePressed(this.profileFor(i), this.deviceFor(i), this.excludeFor(i));
  }

  quitToMenu() {
    this.menus.hide();
    this.devices.unbindSeats();
    this.startAttract();
    this.audio.setMusic('menu');
    this.menus.showMain();
  }

  // ------------------------------------------------------------------ training

  private setupTrainingPanel() {
    const p = this.hud.trainPanel;
    p.innerHTML = '';
    if (this.config?.mode !== 'training') {
      p.hidden = true;
      return;
    }
    p.hidden = false;
    const render = () => {
      p.innerHTML = '';
      const tb = this.trainingBrain!;
      const row = h('div', { class: 'row' });
      TRAINING_BEHAVIOURS.forEach((b, i) => {
        row.append(
          h('button', { class: `chip${tb.behaviour === b.id ? ' on' : ''}`, onclick: () => { this.setTrainingBehaviour(b.id as TrainingBehaviour); render(); } }, `${i + 1} ${b.label}`),
        );
      });
      const dummy = this.world.fighters[1];
      p.append(
        h('b', null, `Dummy · ${dummy.weapon.name}`),
        h('span', { class: 'muted' }, 'What should the dummy do? Keys 1–9 also work.'),
        row,
        h('div', { class: 'row' },
          h('button', { class: `chip${this.refill ? ' on' : ''}`, onclick: () => { this.refill = !this.refill; render(); } }, `0 Refill health: ${this.refill ? 'on' : 'off'}`),
        ),
      );
    };
    this.renderTraining = render;
    render();
  }

  private renderTraining: () => void = () => {};

  setTrainingBehaviour(id: TrainingBehaviour) {
    const tb = this.trainingBrain;
    if (!tb) return;
    const need = TRAINING_BEHAVIOURS.find((b) => b.id === id)?.needs;
    const dummy = this.world.fighters[1];
    if (need && !need.includes(dummy.weapon.id)) this.swapDummyWeapon(need[0]);
    tb.setBehaviour(id);
    this.hud.toast(TRAINING_BEHAVIOURS.find((b) => b.id === id)?.label ?? id, 'dim', 'Dummy behaviour');
  }

  private swapDummyWeapon(w: WeaponId) {
    const dummy = this.world.fighters[1];
    // stop anything that belongs to the old weapon before it disappears
    dummy.releaseIfImpaling();
    if (['attack', 'ult', 'ultChoice', 'recall', 'pickup', 'disarmStagger'].includes(dummy.state)) dummy.toFree();
    dummy.weapon = WEAPONS[w];
    dummy.armed = true;
    dummy.abilities = [...WEAPONS[w].defaultAbilities] as [string, string];
    this.world.removeDroppedWeapon(1);
    this.view.rigs[1].setWeapon(w);
    this.hud.setup([this.world.fighters[0].name, dummy.name], [this.world.fighters[0].weapon.name, dummy.weapon.name]);
  }

  private trainingKeys(e: KeyboardEvent) {
    if (this.mode !== 'playing' || this.config?.mode !== 'training') return;
    const m = /^Digit(\d)$/.exec(e.code);
    if (!m) return;
    const n = Number(m[1]);
    if (n === 0) this.refill = !this.refill;
    else {
      const b = TRAINING_BEHAVIOURS[n - 1];
      if (b) this.setTrainingBehaviour(b.id as TrainingBehaviour);
    }
    this.renderTraining();
  }

  private trainingUpkeep() {
    const W = this.world;
    W.fighters.forEach((f, i) => {
      if (f.hp < this.prevHp[i] || f.state === 'hitstun') this.lastHurt[i] = W.frame;
      this.prevHp[i] = f.hp;
      if (f.state === 'ko') {
        f.hp = HP_MAX;
        f.posture = 0;
        f.ultUsed = false;
        f.ultAnnounced = false;
        f.setState('free');
        W.koResolved = false;
        W.slowmoFrames = 0;
      }
      if (this.refill && W.frame - this.lastHurt[i] > 90 && (f.hp < HP_MAX || (i === 1 && f.posture > 0))) {
        f.hp = Math.min(HP_MAX, f.hp + 2);
        if (i === 1) f.posture = Math.max(0, f.posture - 2);
        if (f.hp >= HP_MAX) f.ultUsed = false;
      }
      if (!f.armed && i === 1 && f.state === 'free' && W.frame - this.lastHurt[i] > 240) {
        // the dummy quietly re-arms after a while
        W.removeDroppedWeapon(1);
        f.armed = true;
      }
    });
  }

  // ------------------------------------------------------------------ loop

  private step() {
    const W = this.world;
    const inputs: RawInput[] = [0, 1].map((i) => {
      const b = this.brains[i];
      if (b) return b.think();
      if (this.mode !== 'playing') return emptyInput();
      return this.devices.sample(this.profileFor(i), this.deviceFor(i), this.excludeFor(i));
    });
    this.match.step(inputs);
    const events = W.drainEvents();
    if (this.mode === 'playing' || this.mode === 'results') {
      this.audio.handle(events, 0);
      this.hud.handleEvents(events, W, this.match);
    }
    this.view.handleEvents(events);
    if (this.config?.mode === 'training' && this.mode === 'playing') this.trainingUpkeep();
    if (this.mode === 'playing' && this.match.phase === 'matchEnd' && this.match.phaseFrames >= 140) this.showResults();
  }

  /** Test hook: when frozen, the animation loop neither steps nor renders. */
  frozen = false;

  /** Test hook: advance the simulation deterministically. */
  debugAdvance(frames: number) {
    for (let i = 0; i < frames; i++) {
      this.step();
      this.time += DT;
      this.view.update(DT, this.time, 0);
    }
  }

  /** Test hook: render one frame now. */
  debugRender(dt = 1 / 60) {
    this.time += dt;
    this.view.render(dt, this.time, 0);
    if (this.mode !== 'attract') this.hud.update(this.world, this.match, this.view, (a: string, p: number) => this.label(a, p), dt);
  }

  private loop(now: number) {
    requestAnimationFrame((t) => this.loop(t));
    if (this.frozen) {
      this.last = now;
      for (const ev of this.devices.drainMenu()) if (this.menus.open) this.menus.nav(ev);
      return;
    }
    const dt = Math.min(0.1, Math.max(0, (now - (this.last || now)) / 1000));
    this.last = now;
    this.time += dt;
    this.devices.poll(now);

    for (const ev of this.devices.drainMenu()) {
      if (this.menus.open) this.menus.nav(ev);
      else if (this.mode === 'playing' && (ev === 'back' || ev === 'pause')) this.pause();
    }
    if (this.mode === 'playing' && this.devices.gameActive) {
      const n = this.versus() ? 2 : 1;
      for (let i = 0; i < n; i++) if (this.devices.pausePressed(this.profileFor(i), this.deviceFor(i), this.excludeFor(i))) this.pause();
    }

    const running = this.mode === 'attract' || this.mode === 'playing' || this.mode === 'results';
    let alpha = 0;
    if (running) {
      this.acc += dt * this.world.timeScale;
      let n = 0;
      while (this.acc >= DT && n < 6) {
        this.step();
        this.acc -= DT;
        n++;
      }
      if (n >= 6) this.acc = 0;
      alpha = this.acc / DT;
    }

    // attract mode loops forever; real matches end on the results screen
    if (this.mode === 'attract' && this.match.phase === 'matchEnd' && this.match.phaseFrames > 240) this.startAttract();

    this.view.render(dt, this.time, alpha);
    if (this.mode !== 'attract') this.hud.update(this.world, this.match, this.view, (a: string, p: number) => this.label(a, p), dt);
  }

  private showResults() {
    this.mode = 'results';
    this.devices.gameActive = false;
    const W = this.world;
    const [a, b] = W.fighters;
    this.hud.clearAnnounce();
    this.menus.showResults({
      winner: this.match.matchWinner,
      mode: this.config!.mode,
      names: [a.name, b.name],
      wins: [this.match.wins[0], this.match.wins[1]],
      stats: [a.stats, b.stats],
    });
  }
}
