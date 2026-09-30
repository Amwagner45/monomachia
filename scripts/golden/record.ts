// Golden replay recorder: runs the TypeScript rules (src/sim) on fixed scenarios
// and writes frame-by-frame logs to game/tests/golden/, so the GDScript port of
// the rules can replay the same inputs and be compared with the original.
//
// usage: npm run golden:record     (or: npx tsx scripts/golden/record.ts)
//
// The files record the web demo's rules exactly. Do NOT re-record them after
// the Godot rules deliberately change: they are the reference for the faithful
// port (plan task 4), not a snapshot of whatever the rules currently do.
//
// ---------------------------------------------------------------------------
// FILE FORMAT (one compact JSON file per scenario: game/tests/golden/<name>.json)
// ---------------------------------------------------------------------------
// {
//   "name": string,
//   "kind": "world" | "match",
//   "seed": int,               // World seed: new World(p1, p2, seed)
//   "p1": {"weapon": "katana"|"greatsword"|"daggers", "abilities": [id, id] | null},
//   "p2": {...},               // abilities null = the weapon's defaultAbilities
//   "gap": float | null,       // kind "world" only: place the fighters like
//                              // tests/helpers.ts makeWorld: fighter 0 at
//                              // (0, 0, -gap/2) yaw 0, fighter 1 at (0, 0, gap/2)
//                              // yaw PI (each pos is a new vector), then
//                              // setState('free') on fighter 0, then fighter 1.
//   "ai": null | [{"difficulty": "easy"|"normal"|"hard", "seed": int}, {...}],
//                              // kind "match" only: the AIBrains (fighter 0, fighter 1)
//                              // that produced the inputs. Provenance only: the
//                              // replay feeds "inputs" and needs no brain.
//   "setup": [{"step": i, "fighter": 0|1, "field": string, "value": ...}, ...],
//                              // direct field writes, applied in array order
//                              // immediately BEFORE step i's world.step / match.step
//                              // (for step 0: after the makeWorld placement).
//                              // Fields use the GDScript (snake_case) names:
//                              //   "hp", "posture", "yaw"         float
//                              //   "blind_until", "last_posture_damage"   int
//                              //   "armed"                        bool
//                              //   "pos"        {"x","y","z"}: a NEW vector
//                              //                (TS: f.pos = {x, y, z})
//                              //   "weapon"     weapon id: f.weapon = WEAPONS[id]
//                              //   "abilities"  [id, id]: f.abilities = [id, id]
//                              // Always [] for kind "match".
//   "steps": int,
//   "inputs": [[mx0, my0, buttons0, mx1, my1, buttons1], ...],
//                              // one entry per step. A step is one call to
//                              // world.step([in0, in1]) (kind "world") or
//                              // match.step([in0, in1]) (kind "match"), with
//                              // in = {mx, my, buttons}.
//   "sample_every": int,       // a sample is taken after every step i where
//                              // i % sample_every == sample_every - 1, and after
//                              // the last step
//   "samples": [{"step": i, "frame": world.frame, "hitstop": int, "timeScale": float,
//                "match": null | {"phase": string, "round": int, "wins": [int, int],
//                                 "phaseFrames": int},
//                "fighters": [F0, F1],
//                "weapons": [[owner, x, y, z, grounded], ...],   // world.weapons in order
//                "waves": [[owner_id, s, alive], ...]}, ...],    // world.waves in order
//   "events": [{"step": i, "e": {...}}, ...]
//                              // every event emitted during step i (including,
//                              // for step 0 of a match, the roundStart emitted
//                              // by new Match), in emission order, exactly as the
//                              // TS emitted it (every Vec3 as {"x","y","z"},
//                              // snapshotted at emit time)
// }
// F = {"state": string, "sf": int, "stateDur": int, "hp": float, "posture": float,
//      "x": float, "y": float, "z": float, "yaw": float, "vx": float, "vy": float,
//      "vz": float, "armed": bool, "blocking": bool, "ultUsed": bool,
//      "atk": null | {"id": string, "frame": int, "charging": bool,
//                     "chargeFrames": int, "hitDone": bool}}
//
// Kind "world": W = new World(p1, p2, seed), the makeWorld placement, then for
// each step i: apply the setup entries of step i, W.step(inputs[i]),
// W.drainEvents(), and sample.
// Kind "match": W = new World(p1, p2, seed), M = new Match(W) (which calls
// startRound and emits roundStart), then for each step i: M.step(inputs[i]),
// W.drainEvents(), and sample. The inputs are what two AIBrains returned from
// think() (fighter 0's brain first) right before each M.step, in the host order
// of scripts/soak.ts; each match runs until matchEnd plus 60 steps, or stops at
// the 15,000-step cap if it hasn't finished (match_greatsword_vs_daggers does).
//
// Numbers are written with JSON.stringify (shortest round-trip form of the
// double, so full precision). A JSON reader may give every number back as a
// float (Godot's does): compare ints by value.
// game/tests/golden/index.json lists the scenario names in order.
// tests/golden.test.ts is a reference replay: it rebuilds every file from its
// own contents on the TypeScript rules and expects an exact match.

import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { AIBrain, DIFFICULTY, Difficulty } from '../../src/sim/ai/brain';
import type { SimEvent } from '../../src/sim/events';
import type { Fighter } from '../../src/sim/fighter';
import { B, RawInput, bit, emptyInput } from '../../src/sim/input';
import { Match } from '../../src/sim/match';
import { WEAPONS, WeaponId } from '../../src/sim/moves';
import { Rng } from '../../src/sim/rng';
import { World } from '../../src/sim/world';

const OUT = resolve(dirname(fileURLToPath(import.meta.url)), '../../game/tests/golden');

// ---------------------------------------------------------------------------
// Format types
// ---------------------------------------------------------------------------

type PlayableId = 'katana' | 'greatsword' | 'daggers';
type Vec = { x: number; y: number; z: number };
type SetupField =
  | 'hp'
  | 'posture'
  | 'yaw'
  | 'blind_until'
  | 'last_posture_damage'
  | 'armed'
  | 'pos'
  | 'weapon'
  | 'abilities';
type SetupValue = number | boolean | string | Vec | [string, string];

interface SetupEntry {
  step: number;
  fighter: number;
  field: SetupField;
  value: SetupValue;
}

interface PlayerSpec {
  weapon: PlayableId;
  abilities: [string, string] | null;
}

interface Golden {
  name: string;
  kind: 'world' | 'match';
  seed: number;
  p1: PlayerSpec;
  p2: PlayerSpec;
  gap: number | null;
  ai: { difficulty: Difficulty; seed: number }[] | null;
  setup: SetupEntry[];
  steps: number;
  inputs: number[][];
  sample_every: number;
  samples: unknown[];
  events: { step: number; e: unknown }[];
}

// ---------------------------------------------------------------------------
// Recording helpers
// ---------------------------------------------------------------------------

function finite(n: number, what: string) {
  if (!Number.isFinite(n)) throw new Error(`non-finite ${what}: ${n}`);
  return n;
}

function fighterSample(f: Fighter) {
  const a = f.atk;
  return {
    state: f.state,
    sf: f.sf,
    stateDur: f.stateDur,
    hp: finite(f.hp, 'hp'),
    posture: finite(f.posture, 'posture'),
    x: finite(f.pos.x, 'x'),
    y: finite(f.pos.y, 'y'),
    z: finite(f.pos.z, 'z'),
    yaw: finite(f.yaw, 'yaw'),
    vx: finite(f.vel.x, 'vx'),
    vy: finite(f.vel.y, 'vy'),
    vz: finite(f.vel.z, 'vz'),
    armed: f.armed,
    blocking: f.blocking,
    ultUsed: f.ultUsed,
    atk: a
      ? { id: a.def.id, frame: a.frame, charging: a.charging, chargeFrames: a.chargeFrames, hitDone: a.hitDone }
      : null,
  };
}

function takeSample(step: number, W: World, M: Match | null) {
  return {
    step,
    frame: W.frame,
    hitstop: W.hitstop,
    timeScale: W.timeScale,
    match: M ? { phase: M.phase, round: M.round, wins: [M.wins[0], M.wins[1]], phaseFrames: M.phaseFrames } : null,
    fighters: [fighterSample(W.fighters[0]), fighterSample(W.fighters[1])],
    weapons: W.weapons.map((w) => [w.owner, finite(w.pos.x, 'wx'), finite(w.pos.y, 'wy'), finite(w.pos.z, 'wz'), w.grounded]),
    waves: W.waves.map((w) => [w.owner.id, finite(w.s, 'wave s'), w.alive]),
  };
}

/**
 * Snapshot every event as JSON at the moment it is emitted, so a vector that
 * changed later in the step could never leak into the log. After each step the
 * drained events are checked against the snapshots.
 */
function captureEmits(W: World) {
  const snaps: unknown[] = [];
  const emit = W.emit.bind(W);
  W.emit = (e: SimEvent) => {
    snaps.push(JSON.parse(JSON.stringify(e)));
    emit(e);
  };
  return {
    drain(step: number, out: { step: number; e: unknown }[]) {
      const drained = W.drainEvents();
      if (drained.length !== snaps.length) throw new Error(`step ${step}: ${drained.length} events, ${snaps.length} snapshots`);
      drained.forEach((e, k) => {
        if (JSON.stringify(e) !== JSON.stringify(snaps[k])) throw new Error(`step ${step}: event ${e.t} changed after emit`);
        out.push({ step, e: snaps[k] });
      });
      snaps.length = 0;
      return drained;
    },
  };
}

const inputRow = (a: RawInput, b: RawInput) => [a.mx, a.my, a.buttons, b.mx, b.my, b.buttons];

function applySetup(W: World, s: SetupEntry) {
  const f = W.fighters[s.fighter];
  const v = s.value;
  switch (s.field) {
    case 'hp':
      f.hp = v as number;
      break;
    case 'posture':
      f.posture = v as number;
      break;
    case 'yaw':
      f.yaw = v as number;
      break;
    case 'blind_until':
      f.blindUntil = v as number;
      break;
    case 'last_posture_damage':
      f.lastPostureDamage = v as number;
      break;
    case 'armed':
      f.armed = v as boolean;
      break;
    case 'pos': {
      const p = v as Vec;
      f.pos = { x: p.x, y: p.y, z: p.z };
      break;
    }
    case 'weapon':
      f.weapon = WEAPONS[v as WeaponId];
      break;
    case 'abilities': {
      const ab = v as [string, string];
      f.abilities = [ab[0], ab[1]];
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// Scripted "world" scenarios
// ---------------------------------------------------------------------------

/** What a scenario script sees each step, before that step runs. */
interface Ctx {
  W: World;
  /** the step about to run */
  i: number;
  /** every event emitted by the steps before this one */
  events: SimEvent[];
  /** the events emitted from step `from` on, with their steps */
  since(from: number): { step: number; e: SimEvent }[];
  /** record a field write, applied right away (before this step) */
  set(fighter: number, field: SetupField, value: SetupValue): void;
  /** move both fighters back to the makeWorld placement for a gap */
  place(gap: number): void;
}

interface CheckCtx {
  W: World;
  events: SimEvent[];
  samples: ReturnType<typeof takeSample>[];
}

interface WorldScenario {
  name: string;
  p1: PlayableId;
  p2: PlayableId;
  a1?: [string, string];
  a2?: [string, string];
  gap: number;
  steps: number;
  /** inputs for fighter 0 and fighter 1 on step c.i (may call c.set first) */
  script: (c: Ctx) => [RawInput, RawInput];
  /** asserts the scenario really exercised its mechanic */
  check: (c: CheckCtx) => void;
}

const WORLD_SEED = 7; // tests/helpers.ts makeWorld

const btn = (...bs: B[]): RawInput => ({ mx: 0, my: 0, buttons: bs.reduce((m, b) => m | (1 << b), 0) });
const move = (mx: number, my: number, ...bs: B[]): RawInput => ({ mx, my, buttons: bs.reduce((m, b) => m | (1 << b), 0) });
const idle = () => emptyInput();

function need(cond: unknown, msg: string) {
  if (!cond) throw new Error(`check failed: ${msg}`);
}
const ofType = <T extends SimEvent['t']>(evs: SimEvent[], t: T) =>
  evs.filter((e) => e.t === t) as Extract<SimEvent, { t: T }>[];
const swings = (evs: SimEvent[], f: number) => ofType(evs, 'swing').filter((e) => e.f === f).map((e) => e.attack);
const hitIds = (evs: SimEvent[]) => ofType(evs, 'hit').map((e) => e.attack);
const near = (a: number, b: number, eps = 1e-6) => Math.abs(a - b) <= eps;

/**
 * A string of presses that follows the attacks instead of fixed frames (hit-stop
 * shifts those): buttons[0] on step `from`, then buttons[k] on the step right
 * after fighter f's k-th swing since `from`, so each press lands in the move's
 * active frames and queues the chained move. Returns null on the other steps.
 */
function chain(c: Ctx, f: number, from: number, buttons: B[]): RawInput | null {
  if (c.i < from) return null;
  if (c.i === from) return btn(buttons[0]);
  const sw = c.since(from).filter((x) => x.e.t === 'swing' && x.e.f === f);
  const n = sw.length;
  if (n >= 1 && n < buttons.length && sw[n - 1].step === c.i - 1) return btn(buttons[n]);
  return null;
}

/** Keep a fighter's posture meter full, as the tests' keepFull helper does. */
function keepFull(c: Ctx, f: number) {
  c.set(f, 'posture', 100);
  c.set(f, 'last_posture_damage', c.W.frame);
}

/**
 * A deterministic button masher for the mirror matchups: holds the stick in a
 * direction for a while, sometimes guards, and taps or holds random actions.
 */
function fuzzer(seed: number) {
  const rng = new Rng(seed);
  let mx = 0;
  let my = 0;
  let stickUntil = 0;
  let guard = false;
  let guardUntil = 0;
  let nextAct = rng.int(0, 12);
  let holds: { mask: number; from: number; to: number }[] = [];
  return (i: number): RawInput => {
    if (i >= stickUntil) {
      const r = rng.next();
      if (r < 0.3) [mx, my] = [0, 0];
      else if (r < 0.48) [mx, my] = [0, 1];
      else if (r < 0.58) [mx, my] = [0, -1];
      else if (r < 0.72) [mx, my] = [1, 0];
      else if (r < 0.86) [mx, my] = [-1, 0];
      else [mx, my] = [rng.range(-1, 1), rng.range(-1, 1)];
      stickUntil = i + rng.int(3, 36);
    }
    if (i >= guardUntil) {
      guard = rng.chance(0.25);
      guardUntil = i + rng.int(8, 45);
    }
    if (i >= nextAct) {
      const r = rng.next();
      let mask = 0;
      let len = 1;
      if (r < 0.3) mask = bit(B.Light);
      else if (r < 0.44) {
        mask = bit(B.Heavy);
        if (rng.chance(0.3)) len = rng.int(12, 100);
      } else if (r < 0.54) mask = bit(B.Block);
      else if (r < 0.65) mask = bit(B.Dodge);
      else if (r < 0.72) mask = bit(B.Jump);
      else if (r < 0.78) mask = bit(B.Block) | bit(B.Light);
      else if (r < 0.84) mask = bit(B.Block) | bit(B.Heavy);
      else if (r < 0.9) {
        mask = bit(B.Sprint);
        len = rng.int(10, 60);
      } else if (r < 0.95) mask = bit(B.Light) | bit(B.Heavy);
      else mask = bit(B.Interact);
      holds.push({ mask, from: i, to: i + len - 1 });
      nextAct = i + rng.int(3, 28);
    }
    holds = holds.filter((h) => h.to >= i);
    let buttons = guard ? bit(B.Block) : 0;
    for (const h of holds) if (i >= h.from) buttons |= h.mask;
    return { mx, my, buttons };
  };
}

/** First frame a Lightning Tempest spin lands on an idle greatsword (regressions.test.ts). */
function tempestFirstHitFrame() {
  const W = new World({ weapon: WEAPONS.daggers }, { weapon: WEAPONS.greatsword }, WORLD_SEED);
  const [a, b] = W.fighters;
  a.pos = { x: 0, y: 0, z: -3.5 };
  b.pos = { x: 0, y: 0, z: 3.5 };
  a.yaw = 0;
  b.yaw = Math.PI;
  a.setState('free');
  b.setState('free');
  a.hp = 20;
  for (let i = 0; i < 140; i++) {
    W.step([i === 0 ? btn(B.Ultimate) : idle(), idle()]);
    if (W.drainEvents().some((e) => e.t === 'hit')) return W.frame;
  }
  throw new Error('tempest probe never hit');
}

const WORLD_SCENARIOS: WorldScenario[] = [
  {
    // combat.test.ts "light attacks chain into a combo string", then the heavy
    // strings H-L(k_l2)-H(k_h1f)-H(k_h2) and L-H(k_h1f)-H(k_h2), the second one
    // into a guard held from before the swing ("pressing block too early only blocks")
    name: 'katana_strings',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 380,
    script: (c) => {
      const i = c.i;
      let p0 = idle();
      if (i < 50 && i % 8 === 0) p0 = btn(B.Light);
      if (i === 120) c.place(2.2);
      if (i === 120) p0 = btn(B.Heavy);
      if (i === 146) p0 = btn(B.Light);
      if (i === 162) p0 = btn(B.Heavy);
      if (i === 185) p0 = btn(B.Heavy);
      if (i === 270) c.place(2.2);
      if (i === 270) p0 = btn(B.Light);
      if (i === 283) p0 = btn(B.Heavy);
      if (i === 306) p0 = btn(B.Heavy);
      const p1 = i >= 271 ? btn(B.Block) : idle();
      return [p0, p1];
    },
    check: ({ events, W }) => {
      const s = swings(events, 0);
      need(hitIds(events).slice(0, 3).join() === 'k_l1,k_l2,k_l3', 'light chain k_l1,k_l2,k_l3');
      need(s.join().includes('k_h1,k_l2,k_h1f,k_h2'), 'heavy chain H-L-H-H');
      need(s.join().includes('k_l1,k_h1f,k_h2'), 'chain L-H-H');
      need(ofType(events, 'block').length >= 2, 'blocks');
      need(ofType(events, 'parry').length === 0, 'early press only blocks');
      void W;
    },
  },
  {
    // combat.test.ts "a heavy held for 2.5 s releases by itself as a stronger power attack"
    name: 'katana_charged_heavy_autorelease',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 225,
    script: (c) => [c.i < 200 ? btn(B.Heavy) : idle(), idle()],
    check: ({ events }) => {
      const h = ofType(events, 'hit')[0];
      need(h && h.attack === 'k_h1' && near(h.damage, 13 * 1.8), 'full-charge k_h1 for 23.4');
    },
  },
  {
    // "a well-timed block press parries", then a riposte into the recoil; then
    // "mashing block shrinks the parry window" (3 presses 4 frames apart), and a
    // fresh press after the spam window parries with the full window again
    name: 'katana_parry_timing',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 230,
    script: (c) => {
      const i = c.i;
      if (i === 100 || i === 180) c.place(2.2);
      const p0 = i === 0 || i === 100 || i === 180 ? btn(B.Light) : idle();
      let p1 = idle();
      if (i === 8 || i === 188) p1 = btn(B.Block);
      if (i === 16) p1 = btn(B.Light);
      if (i === 100 || i === 104 || i === 108) p1 = btn(B.Block);
      return [p0, p1];
    },
    check: ({ events }) => {
      const p = ofType(events, 'parry');
      need(p.length === 2 && p[0].kind === 'parry' && p[0].timing === 4 && p[0].window === 9, 'timed parry');
      need(p[1].window === 9, 'window restored after the spam window');
      need(ofType(events, 'hit').length >= 2, 'riposte and the hit through the shrunk window');
    },
  },
  {
    // "you cannot block an attack coming from behind"
    name: 'katana_block_from_behind',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 121,
    script: (c) => {
      if (c.i === 1) {
        c.set(1, 'yaw', 0);
        c.set(1, 'blind_until', 1e9);
      }
      return [c.i === 1 ? btn(B.Light) : idle(), c.i >= 1 ? btn(B.Block) : idle()];
    },
    check: ({ events }) => need(ofType(events, 'hit').length === 1 && !ofType(events, 'block').length, 'hit from behind'),
  },
  {
    // "blocking an unblockable takes the full hit", "blocking an unblockable with
    // a full meter disarms the blocker", a weapon pickup ("a disarmed fighter can
    // pick their weapon back up", including a press too far away), then
    // "blocking a full-charge power attack with a full meter disarms"
    name: 'katana_unblockable_and_power_disarms',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 560,
    script: (c) => {
      const i = c.i;
      const b = c.W.fighters[1];
      let p0 = idle();
      let p1 = idle();
      if (i === 0 || i === 100) p0 = btn(B.Block, B.Heavy);
      if (i < 60) p1 = btn(B.Block);
      if (i === 100) c.place(2.2);
      if (i >= 100 && i < 145) {
        if (b.armed) keepFull(c, 1);
        p1 = btn(B.Block);
      }
      if (i === 240) p1 = btn(B.Interact); // too far from the weapon: nothing
      if (i === 260) {
        const w = c.W.weaponOf(1)!;
        c.set(1, 'pos', { x: w.pos.x, y: 0, z: w.pos.z });
        p1 = btn(B.Interact);
      }
      if (i === 320) c.place(2.2);
      if (i >= 320 && i < 540) {
        p0 = btn(B.Heavy);
        if (b.armed) keepFull(c, 1);
        p1 = btn(B.Block);
      }
      return [p0, p1];
    },
    check: ({ events, W }) => {
      const hits = ofType(events, 'hit');
      need(hits[0]?.attack === 'k_thrust' && near(hits[0].damage, 12), 'unblockable hit through the guard');
      need(ofType(events, 'telegraph').length === 2, 'telegraphs');
      const d = ofType(events, 'disarm');
      need(d.length === 2 && d.every((e) => e.victim === 1 && e.reason === 'blocked'), 'two block disarms');
      need(ofType(events, 'pickup').length === 1, 'pickup');
      need(!W.fighters[1].armed, 'disarmed by the full charge');
    },
  },
  {
    // "a parried attacker with a full posture meter is disarmed and loses no HP",
    // then "disarmed: the ultimate offers Recall, which re-arms", then a fight on
    name: 'katana_parry_disarm_recall',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 220,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(0, 'posture', 100);
      if (i === 100) c.set(0, 'hp', 20);
      let p0 = idle();
      if (i === 0) p0 = btn(B.Light);
      if (i === 100) p0 = btn(B.Ultimate);
      if (i === 110) p0 = btn(B.Light);
      if (i === 180) p0 = btn(B.Light);
      return [p0, i === 8 ? btn(B.Block) : i === 160 ? btn(B.Heavy) : idle()];
    },
    check: ({ events, W }) => {
      need(ofType(events, 'disarm')[0]?.reason === 'parried', 'parry disarm');
      need(ofType(events, 'ultChoice').length === 1 && ofType(events, 'recall').length === 1, 'recall');
      need(W.fighters[0].armed && !W.weaponOf(0), 're-armed');
    },
  },
  {
    // "holding block while standing drains posture faster than while moving, and
    // slower at low HP", and "posture does not drain while not blocking"
    name: 'katana_posture_drain',
    p1: 'katana',
    p2: 'katana',
    gap: 5,
    steps: 240,
    script: (c) => {
      const i = c.i;
      if (i === 0 || i === 120) {
        c.set(0, 'posture', 60);
        c.set(1, 'posture', 60);
      }
      if (i === 120) c.set(0, 'hp', 30);
      if (i < 120) return [btn(B.Block), move(1, 0, B.Block)];
      return [btn(B.Block), idle()];
    },
    check: ({ samples, W }) => {
      const s = samples[119].fighters;
      const stand = 60 - s[0].posture;
      const moving = 60 - s[1].posture;
      const low = 60 - W.fighters[0].posture;
      need(stand > moving && stand > low && Math.abs(stand * 60 / 119 - 14) < 1, 'drain rates');
      need(W.fighters[1].posture === 60, 'no drain when not blocking');
    },
  },
  {
    // "dodge invincibility lets a normal attack pass through" with a dodge-light
    // follow-up, then "dodging into a thrust triggers the stomp counter"
    name: 'katana_dodge_and_stomp',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 200,
    script: (c) => {
      const i = c.i;
      if (i === 100) c.place(2.2);
      let p1 = idle();
      if (i === 7 || i === 120) p1 = move(0, 1, B.Dodge);
      if (i === 21 || i === 150) p1 = btn(B.Light);
      return [i === 0 ? btn(B.Light) : i === 100 ? btn(B.Block, B.Heavy) : idle(), p1];
    },
    check: ({ events }) => {
      need(ofType(events, 'evade').length >= 1, 'evade');
      need(swings(events, 1)[0] === 'k_dl', 'dodge light follow-up');
      need(ofType(events, 'counter')[0]?.kind === 'stomp', 'stomp');
    },
  },
  {
    // greatsword unblockables: "dodge invincibility does not work against
    // unblockables", "jumping over a sweep triggers the leap counter", and
    // "back-dashing an overhead slam triggers the evade counter and a counter lunge"
    name: 'greatsword_counters',
    p1: 'greatsword',
    p2: 'katana',
    gap: 1.6,
    steps: 350,
    script: (c) => {
      const i = c.i;
      if (i === 120) c.place(2.2);
      if (i === 260) c.place(2.4);
      let p0 = idle();
      if (i === 0 || i === 120) p0 = btn(B.Block, B.Light);
      if (i === 260) p0 = btn(B.Block, B.Heavy);
      let p1 = idle();
      if (i === 24) p1 = move(1, 0, B.Dodge);
      if (i === 140) p1 = btn(B.Jump);
      if (i === 288) p1 = btn(B.Dodge);
      if (i === 302) p1 = btn(B.Light);
      return [p0, p1];
    },
    check: ({ events }) => {
      need(hitIds(events)[0] === 'g_sweep', 'sweep hits through a dodge');
      const k = ofType(events, 'counter').map((e) => e.kind);
      need(k.join() === 'leap,evade', 'leap then evade counters');
      need(hitIds(events).includes('k_lunge'), 'counter lunge');
    },
  },
  {
    // "a disarmed fighter cannot block", "a timed block press while disarmed is a
    // redirect counter", "a redirect against a full-posture attacker disarms
    // them", "parrying a bare-handed attacker at full posture dazes them", then
    // the bare-hand string L-L-L-H-H
    name: 'disarmed_brawl',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 500,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(1, 'armed', false);
      if (i === 100 || i === 200) c.place(2.2);
      if (i === 200) c.set(0, 'posture', 100);
      if (i === 300) c.place(1.5);
      if (i >= 300 && i <= 306) keepFull(c, 0);
      let p0 = idle();
      if (i === 0 || i === 100 || i === 200 || i === 300) p0 = btn(B.Light);
      let p1 = idle();
      if (i < 40) p1 = btn(B.Block);
      if (i === 108 || i === 208 || i === 302) p1 = btn(B.Block);
      if (i === 380 || i === 388 || i === 396) p1 = btn(B.Light);
      if (i === 410 || i === 440) p1 = btn(B.Heavy);
      return [p0, p1];
    },
    check: ({ events }) => {
      need(hitIds(events)[0] === 'k_l1', 'disarmed cannot block');
      const p = ofType(events, 'parry').map((e) => e.kind);
      need(p.join() === 'redirect,redirect,redirect', 'three redirects');
      need(ofType(events, 'disarm')[0]?.reason === 'redirect', 'redirect disarm');
      need(ofType(events, 'stagger')[0]?.f === 0, 'bare-handed stagger');
      need(swings(events, 1).join().includes('f_l1,f_l2,f_l3,f_h1,f_h2'), 'fists string');
    },
  },
  {
    // "disarmed fighters move faster and dodge farther" (and jump higher)
    name: 'disarmed_movement',
    p1: 'katana',
    p2: 'katana',
    gap: 6,
    steps: 200,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(0, 'armed', false);
      let p = idle();
      if (i === 0) p = move(1, 0, B.Dodge);
      else if (i >= 40 && i < 70) p = move(0, -1);
      else if (i >= 80 && i < 110) p = move(0, 1);
      else if (i === 130) p = btn(B.Jump);
      else if (i === 170) p = btn(B.Dodge);
      return [p, p];
    },
    check: ({ samples }) => {
      const s0 = samples[29].fighters;
      need(Math.abs(s0[0].x) > 1.3 * Math.abs(s0[1].x), 'disarmed dodge farther');
      const peak = (f: number) => Math.max(...samples.slice(130, 170).map((s) => s.fighters[f].y));
      need(peak(0) > peak(1), 'disarmed jump higher');
    },
  },
  {
    // jump attacks (both weapons, light and plunging heavy) and sprint attacks
    // (double-tap sprint and the sprint button)
    name: 'aerial_and_sprint_attacks',
    p1: 'katana',
    p2: 'greatsword',
    gap: 2.2,
    steps: 570,
    script: (c) => {
      const i = c.i;
      let p0 = idle();
      let p1 = idle();
      if (i === 0) p0 = btn(B.Jump);
      if (i === 8) p0 = btn(B.Light);
      if (i === 70) p0 = btn(B.Jump); // a plain jump and landing
      if (i === 110) c.place(2.6);
      if (i === 110) p0 = move(0, 1, B.Jump);
      if (i === 118) p0 = btn(B.Heavy);
      if (i === 170) c.place(2.8);
      if (i === 170) p1 = btn(B.Jump);
      if (i === 178) p1 = btn(B.Heavy);
      if (i === 240) p1 = btn(B.Jump);
      if (i === 246) p1 = btn(B.Light);
      if (i === 300) c.place(9);
      // double-tap forward, hold: sprint, then a sprint light
      if (i >= 300 && i < 303) p0 = move(0, 1);
      if (i >= 306 && i < 330) p0 = move(0, 1, ...(i === 322 ? [B.Light] : []));
      if (i === 370) c.place(9);
      if (i >= 370 && i < 400) p0 = move(0, 1, B.Sprint, ...(i === 386 ? [B.Heavy] : []));
      if (i === 440) c.place(9);
      if (i >= 440 && i < 530) p1 = move(0, 1, B.Sprint, ...(i === 456 ? [B.Light] : i === 508 ? [B.Heavy] : []));
      return [p0, p1];
    },
    check: ({ events }) => {
      const s0 = swings(events, 0);
      const s1 = swings(events, 1);
      for (const id of ['k_jl', 'k_jh', 'k_sl', 'k_sh']) need(s0.includes(id), `swing ${id}`);
      for (const id of ['g_jh', 'g_jl', 'g_sl', 'g_sh']) need(s1.includes(id), `swing ${id}`);
    },
  },
  {
    // attacks out of a backstep, back dodge and side dodge (katana and
    // greatsword), and a light's recovery dodge-cancelled
    name: 'dodge_followups',
    p1: 'katana',
    p2: 'greatsword',
    gap: 2.6,
    steps: 480,
    script: (c) => {
      const i = c.i;
      for (const at of [60, 130, 190, 250, 340]) if (i === at) c.place(2.6);
      if (i === 400) c.place(2.2);
      let p0 = idle();
      let p1 = idle();
      if (i === 0) p0 = btn(B.Dodge);
      if (i === 14) p0 = btn(B.Light);
      if (i === 60) p0 = move(0, -1, B.Dodge);
      if (i === 74) p0 = btn(B.Heavy);
      if (i === 130) p0 = move(1, 0, B.Dodge);
      if (i === 144) p0 = btn(B.Light);
      if (i === 190) p0 = move(-1, 0, B.Dodge);
      if (i === 204) p0 = btn(B.Heavy);
      if (i === 250) p1 = btn(B.Dodge);
      if (i === 262) p1 = btn(B.Heavy);
      if (i === 340) p1 = move(1, 0, B.Dodge);
      if (i === 354) p1 = btn(B.Light);
      if (i === 400) p0 = btn(B.Light);
      if (i >= 422 && i < 432) p0 = move(1, 0, ...(i === 422 ? [B.Dodge] : []));
      return [p0, p1];
    },
    check: ({ events }) => {
      const s0 = swings(events, 0);
      need(s0.slice(0, 5).join() === 'k_bl,k_bh,k_dl,k_dh,k_l1', 'katana follow-ups');
      need(swings(events, 1).join() === 'g_bh,g_dl', 'greatsword follow-ups');
      need(ofType(events, 'dodge').filter((e) => e.f === 0).length === 5, 'dodge cancel');
    },
  },
  {
    // footsies: strafing orbits, steps from neutral, walking back, block-walking,
    // stepping into a guard, and sprinting sideways
    name: 'strafe_orbit_steps',
    p1: 'katana',
    p2: 'daggers',
    gap: 3,
    steps: 240,
    script: (c) => {
      const i = c.i;
      let p0 = idle();
      if (i < 100) p0 = move(1, 0);
      else if (i >= 110 && i < 140) p0 = move(-0.7, 0.7);
      else if (i >= 150 && i < 153) p0 = move(-1, 0);
      else if (i >= 156 && i < 200) p0 = move(-1, 0);
      else if (i >= 210 && i < 230) p0 = move(0.3, -0.9, B.Sprint);
      let p1 = idle();
      if (i === 10 || i === 30) p1 = move(0, 1);
      else if (i >= 50 && i < 53) p1 = move(1, 0);
      else if (i === 70) p1 = move(-1, 0);
      else if (i >= 90 && i < 130) p1 = move(0, -1);
      else if (i >= 150 && i < 200) p1 = move(-1, 0, B.Block);
      else if (i === 210) p1 = move(0, 1);
      else if (i >= 212 && i < 220) p1 = move(0, 1, B.Block);
      return [p0, p1];
    },
    check: ({ events }) => {
      need(ofType(events, 'step').length >= 6, 'steps');
    },
  },
  {
    // knockback into the arena wall: a charged heavy, a string, and a KO slide
    // (with the KO slow motion and ultReady on the way)
    name: 'wall_knockback_ko',
    p1: 'greatsword',
    p2: 'katana',
    gap: 2.2,
    steps: 280,
    script: (c) => {
      const i = c.i;
      if (i === 0) {
        c.set(0, 'pos', { x: 0, y: 0, z: 8.2 });
        c.set(1, 'pos', { x: 0, y: 0, z: 10.4 });
        c.set(1, 'hp', 40);
      }
      let p0 = idle();
      if (i < 60) p0 = btn(B.Heavy);
      if (i === 150 || i === 162 || i === 230) p0 = btn(B.Light);
      return [p0, idle()];
    },
    check: ({ events, samples }) => {
      need(ofType(events, 'ko').length === 1, 'KO');
      need(ofType(events, 'ultReady').length === 1, 'ultReady');
      need(samples.some((s) => Math.hypot(s.fighters[1].x, s.fighters[1].z) >= 11.08 - 1e-9), 'pinned at the wall');
      need(samples.some((s) => s.timeScale === 0.3), 'KO slow motion');
    },
  },
  {
    // regressions.test.ts "a trade between two charged heavies is fair"
    name: 'charged_heavy_trade',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 140,
    script: (c) => {
      const hold = c.i < 60 ? btn(B.Heavy) : idle();
      return [hold, hold];
    },
    check: ({ events, W }) => {
      const h = ofType(events, 'hit');
      need(h.length === 2 && h[0].damage > 13 && near(h[0].damage, h[1].damage), 'fair trade');
      need(near(W.fighters[0].hp, W.fighters[1].hp), 'equal HP');
    },
  },
  {
    // "are locked above 25% HP", "Moonsplitter (vertical) crosses the stage and
    // hits", "only once per round", then "Moonsplitter (horizontal) can be jumped over"
    name: 'ult_moonsplitter',
    p1: 'katana',
    p2: 'katana',
    gap: 8,
    steps: 260,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(0, 'hp', 20);
      if (i === 150) {
        c.place(8);
        c.set(1, 'hp', 20);
      }
      let p0 = idle();
      if (i === 0 || i === 100) p0 = btn(B.Ultimate);
      if (i === 188) p0 = btn(B.Jump);
      let p1 = idle();
      if (i === 0) p1 = btn(B.Light, B.Heavy);
      if (i === 150) p1 = btn(B.Ultimate);
      else if (i > 150 && i < 180) p1 = move(1, 0);
      return [p0, p1];
    },
    check: ({ events, W }) => {
      const s = ofType(events, 'ultStart');
      need(s.length === 2 && s[0].f === 0 && s[1].f === 1, 'one ult each');
      need(ofType(events, 'ultWave').map((e) => e.kind).join() === 'vertical,horizontal', 'both variants');
      need(hitIds(events).join() === 'u_moon_v' && near(W.fighters[0].hp, 20), 'vertical hits, horizontal jumped');
    },
  },
  {
    // "light pressed a frame before heavy still counts as the chord" (the
    // in-attack chord cancel), a second chord doing nothing, then "a Moonsplitter
    // wave still in flight when the round ends does no damage"
    name: 'ult_chord_and_wave_ko',
    p1: 'katana',
    p2: 'katana',
    gap: 3,
    steps: 240,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(0, 'hp', 20);
      if (i === 160) {
        c.place(8);
        c.set(1, 'hp', 20);
      }
      const waved = c.events.some((e) => e.t === 'ultWave' && e.f === 1);
      if (waved && c.W.fighters[1].hp > 0) c.set(1, 'hp', 0);
      let p0 = idle();
      if (i === 0) p0 = btn(B.Light);
      if (i === 2) p0 = btn(B.Heavy);
      if (i === 120) p0 = btn(B.Light, B.Heavy);
      return [p0, i === 160 ? btn(B.Ultimate) : idle()];
    },
    check: ({ events, W }) => {
      need(ofType(events, 'ultStart').length === 2, 'chord ult and the second ult');
      need(ofType(events, 'ko').length === 1 && W.fighters[1].state === 'ko', 'caster KO');
      need(near(W.fighters[0].hp, 20), 'the late wave does no damage');
    },
  },
  {
    // "Impaler dashes, impales, and bursts on heavy", then an impale left to time out
    name: 'ult_impaler',
    p1: 'greatsword',
    p2: 'greatsword',
    gap: 6,
    steps: 330,
    script: (c) => {
      const i = c.i;
      if (i === 0) c.set(0, 'hp', 20);
      if (i === 180) {
        c.place(6);
        c.set(1, 'hp', 20);
      }
      const p0 = i === 0 ? btn(B.Ultimate) : i >= 50 && i < 180 && i % 3 === 0 ? btn(B.Heavy) : idle();
      return [p0, i === 180 ? btn(B.Ultimate) : idle()];
    },
    check: ({ events }) => {
      need(ofType(events, 'ultImpale').length === 2, 'two impales');
      need(ofType(events, 'ultBurst').length === 1, 'one burst');
      need(hitIds(events).join() === 'u_impale,u_burst,u_impale', 'impale hits');
    },
  },
  {
    // "Lightning Tempest lands six spins and a finisher"
    name: 'ult_tempest',
    p1: 'daggers',
    p2: 'katana',
    gap: 7,
    steps: 130,
    script: (c) => {
      if (c.i === 0) c.set(0, 'hp', 20);
      return [c.i === 0 ? btn(B.Ultimate) : idle(), idle()];
    },
    check: ({ events, W }) => {
      need(ofType(events, 'hit').length === 7, 'seven hits');
      need(near(W.fighters[1].hp, 100 - 6 * 5 - 8), 'tempest damage');
    },
  },
  {
    // regressions.test.ts "one block press parries one hit, not a whole flurry"
    name: 'ult_tempest_one_parry',
    p1: 'daggers',
    p2: 'greatsword',
    gap: 7,
    steps: 130,
    script: (() => {
      const firstHit = tempestFirstHitFrame();
      return (c: Ctx): [RawInput, RawInput] => {
        if (c.i === 0) c.set(0, 'hp', 20);
        return [c.i === 0 ? btn(B.Ultimate) : idle(), c.i === firstHit - 2 ? btn(B.Block) : idle()];
      };
    })(),
    check: ({ events }) => need(ofType(events, 'parry').length === 1, 'one parry'),
  },
  {
    // "disarmed: choosing heavy throws the Breaker Palm posture blow"
    name: 'disarmed_ult_breaker_palm',
    p1: 'katana',
    p2: 'katana',
    gap: 1.8,
    steps: 120,
    script: (c) => {
      if (c.i === 0) {
        c.set(0, 'hp', 20);
        c.set(0, 'armed', false);
      }
      return [c.i === 0 ? btn(B.Ultimate) : c.i === 10 ? btn(B.Heavy) : idle(), idle()];
    },
    check: ({ events, W }) => {
      need(hitIds(events)[0] === 'f_breaker', 'breaker palm');
      need(ofType(events, 'ultChoice').length === 1, 'ult choice');
      need(near(W.fighters[1].posture, 75), 'posture 75');
    },
  },
  {
    // Shadow Step to either side and the backstab it opens, then the daggers'
    // strings: the d_l1 -> d_h1 -> d_l1 loop and L-L-L-L-H(d_h2)
    name: 'daggers_shadow_step_and_chains',
    p1: 'daggers',
    p2: 'katana',
    gap: 2.5,
    steps: 500,
    script: (c) => {
      const i = c.i;
      if (i === 120 || i === 240 || i === 380) c.place(i === 120 ? 2.5 : 1.8);
      let p0 = idle();
      if (i === 0) p0 = btn(B.Block, B.Heavy);
      if (i === 30) p0 = btn(B.Light);
      if (i === 120) p0 = move(-1, 0, B.Block, B.Heavy);
      if (i === 150) p0 = btn(B.Light);
      if (i >= 240 && i < 380) p0 = chain(c, 0, 240, [B.Light, B.Heavy, B.Light, B.Heavy, B.Light]) ?? idle();
      if (i >= 380) p0 = chain(c, 0, 380, [B.Light, B.Light, B.Light, B.Light, B.Heavy]) ?? idle();
      return [p0, idle()];
    },
    check: ({ events }) => {
      need(ofType(events, 'backstabReady').length === 2, 'two shadow steps');
      need(ofType(events, 'hit').filter((e) => e.backstab).length === 2, 'two backstabs');
      const s = swings(events, 0).join();
      need(s.includes('d_l1,d_h1,d_l1,d_h1,d_l1'), 'd_l1/d_h1 loop');
      need(s.includes('d_l1,d_l2,d_l3,d_l4,d_h2'), 'full light string into d_h2');
    },
  },
  {
    // Flash: the katana's counter stance against a light, and against an unblockable
    name: 'katana_flash',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 170,
    script: (c) => {
      const i = c.i;
      if (i === 100) c.place(2.2);
      let p0 = idle();
      if (i === 4 || i === 118) p0 = btn(B.Block, B.Light);
      if (i === 30) p0 = btn(B.Light);
      return [p0, i === 0 ? btn(B.Light) : i === 100 ? btn(B.Block, B.Heavy) : idle()];
    },
    check: ({ events }) => {
      const p = ofType(events, 'parry');
      need(p.length === 2 && p.every((e) => e.kind === 'flash'), 'two flashes');
    },
  },
  {
    // Guard Crusher (a non-default ability) three times into a held guard, then
    // the katana's non-default Swallow Sweep on an idle target
    name: 'guard_crusher_and_alt_abilities',
    p1: 'greatsword',
    p2: 'katana',
    a1: ['g_sweep', 'g_crush'],
    a2: ['k_sweep', 'k_thrust'],
    gap: 2.2,
    steps: 280,
    script: (c) => {
      const i = c.i;
      for (const at of [50, 100, 220]) if (i === at) c.place(2.2);
      const p0 = i === 0 || i === 50 || i === 100 ? btn(B.Block, B.Heavy) : idle();
      let p1 = i < 150 ? btn(B.Block) : idle();
      if (i === 220) p1 = btn(B.Block, B.Light);
      return [p0, p1];
    },
    check: ({ events }) => {
      const bl = ofType(events, 'block');
      need(bl.length === 3 && bl.every((e) => e.attack === 'g_crush' && near(e.posture, 32)), 'guard crushes');
      need(swings(events, 1).includes('k_sweep'), 'katana sweep');
    },
  },
  {
    // regressions.test.ts "changing a fighter's weapon mid-combo never crashes"
    name: 'regress_weapon_swap',
    p1: 'katana',
    p2: 'katana',
    gap: 2.2,
    steps: 120,
    script: (c) => {
      if (c.i === 6) {
        c.set(0, 'weapon', 'greatsword');
        c.set(0, 'abilities', ['g_sweep', 'g_slam']);
      }
      return [c.i % 5 === 0 ? btn(B.Light) : idle(), idle()];
    },
    check: ({ events }) => need(swings(events, 0).includes('g_l1'), 'greatsword moves after the swap'),
  },
  {
    name: 'mirror_katana',
    p1: 'katana',
    p2: 'katana',
    a2: ['k_sweep', 'k_flash'],
    gap: 3,
    steps: 400,
    script: (() => {
      const f0 = fuzzer(101);
      const f1 = fuzzer(202);
      return (c: Ctx): [RawInput, RawInput] => [f0(c.i), f1(c.i)];
    })(),
    check: ({ events }) => need(ofType(events, 'hit').length >= 3, 'some hits'),
  },
  {
    name: 'mirror_greatsword',
    p1: 'greatsword',
    p2: 'greatsword',
    a1: ['g_crush', 'g_slam'],
    gap: 3,
    steps: 400,
    script: (() => {
      const f0 = fuzzer(303);
      const f1 = fuzzer(404);
      return (c: Ctx): [RawInput, RawInput] => [f0(c.i), f1(c.i)];
    })(),
    check: ({ events }) => need(ofType(events, 'hit').length >= 3, 'some hits'),
  },
  {
    name: 'mirror_daggers',
    p1: 'daggers',
    p2: 'daggers',
    a1: ['d_needle', 'd_shadow'],
    gap: 3,
    steps: 400,
    script: (() => {
      const f0 = fuzzer(505);
      const f1 = fuzzer(606);
      return (c: Ctx): [RawInput, RawInput] => [f0(c.i), f1(c.i)];
    })(),
    check: ({ events }) => need(ofType(events, 'hit').length >= 3, 'some hits'),
  },
];

function recordWorld(sc: WorldScenario): Golden {
  const W = new World({ weapon: WEAPONS[sc.p1], abilities: sc.a1 }, { weapon: WEAPONS[sc.p2], abilities: sc.a2 }, WORLD_SEED);
  const cap = captureEmits(W);
  // tests/helpers.ts makeWorld
  const [a, b] = W.fighters;
  a.pos = { x: 0, y: 0, z: -sc.gap / 2 };
  b.pos = { x: 0, y: 0, z: sc.gap / 2 };
  a.yaw = 0;
  b.yaw = Math.PI;
  a.setState('free');
  b.setState('free');

  const setup: SetupEntry[] = [];
  const inputs: number[][] = [];
  const samples: ReturnType<typeof takeSample>[] = [];
  const events: { step: number; e: unknown }[] = [];
  const all: SimEvent[] = [];
  const allSteps: number[] = [];
  for (let i = 0; i < sc.steps; i++) {
    const ctx: Ctx = {
      W,
      i,
      events: all,
      since(from) {
        const out: { step: number; e: SimEvent }[] = [];
        for (let k = 0; k < all.length; k++) if (allSteps[k] >= from) out.push({ step: allSteps[k], e: all[k] });
        return out;
      },
      set(fighter, field, value) {
        const entry: SetupEntry = { step: i, fighter, field, value: JSON.parse(JSON.stringify(value)) };
        setup.push(entry);
        applySetup(W, entry);
      },
      place(gap) {
        this.set(0, 'pos', { x: 0, y: 0, z: -gap / 2 });
        this.set(1, 'pos', { x: 0, y: 0, z: gap / 2 });
        this.set(0, 'yaw', 0);
        this.set(1, 'yaw', Math.PI);
      },
    };
    const [in0, in1] = sc.script(ctx);
    inputs.push(inputRow(in0, in1));
    W.step([in0, in1]);
    for (const e of cap.drain(i, events)) {
      all.push(e);
      allSteps.push(i);
    }
    samples.push(takeSample(i, W, null)); // sample_every 1
  }
  try {
    sc.check({ W, events: all, samples });
  } catch (err) {
    throw new Error(`${sc.name}: ${(err as Error).message}`);
  }
  return {
    name: sc.name,
    kind: 'world',
    seed: WORLD_SEED,
    p1: { weapon: sc.p1, abilities: sc.a1 ?? null },
    p2: { weapon: sc.p2, abilities: sc.a2 ?? null },
    gap: sc.gap,
    ai: null,
    setup,
    steps: sc.steps,
    inputs,
    sample_every: 1,
    samples,
    events,
  };
}

// ---------------------------------------------------------------------------
// Computer-vs-computer "match" scenarios (host order of scripts/soak.ts)
// ---------------------------------------------------------------------------

interface MatchScenario {
  name: string;
  /** match index m in scripts/soak.ts: world seed 1000 + m, brain seeds 11 + m and 77 + m */
  m: number;
  p1: PlayableId;
  p2: PlayableId;
  d1: Difficulty;
  d2: Difficulty;
}

const MATCH_SCENARIOS: MatchScenario[] = [
  { name: 'match_katana_vs_greatsword', m: 0, p1: 'katana', p2: 'greatsword', d1: 'normal', d2: 'normal' },
  { name: 'match_greatsword_vs_daggers', m: 1, p1: 'greatsword', p2: 'daggers', d1: 'hard', d2: 'hard' },
  { name: 'match_daggers_vs_katana', m: 2, p1: 'daggers', p2: 'katana', d1: 'easy', d2: 'hard' },
  { name: 'match_katana_vs_katana', m: 3, p1: 'katana', p2: 'katana', d1: 'hard', d2: 'normal' },
  { name: 'match_greatsword_vs_greatsword', m: 4, p1: 'greatsword', p2: 'greatsword', d1: 'normal', d2: 'hard' },
  { name: 'match_daggers_vs_daggers', m: 5, p1: 'daggers', p2: 'daggers', d1: 'hard', d2: 'easy' },
];

const MATCH_SAMPLE_EVERY = 40;
const MATCH_CAP = 15000;
const MATCH_TAIL = 60;

function recordMatch(sc: MatchScenario): Golden {
  const seed = 1000 + sc.m;
  const W = new World({ weapon: WEAPONS[sc.p1] }, { weapon: WEAPONS[sc.p2] }, seed);
  const cap = captureEmits(W);
  const M = new Match(W);
  const seeds = [11 + sc.m, 77 + sc.m];
  const ai = [new AIBrain(W.fighters[0], DIFFICULTY[sc.d1], seeds[0]), new AIBrain(W.fighters[1], DIFFICULTY[sc.d2], seeds[1])];

  const inputs: number[][] = [];
  const events: { step: number; e: unknown }[] = [];
  const samples: ReturnType<typeof takeSample>[] = [];
  let endAt = -1;
  let steps = 0;
  for (let i = 0; i < MATCH_CAP && (endAt < 0 || i <= endAt); i++) {
    // scripts/soak.ts: M.step([ai[0].think(), ai[1].think()])
    const in0 = ai[0].think();
    const in1 = ai[1].think();
    inputs.push(inputRow(in0, in1));
    M.step([in0, in1]);
    cap.drain(i, events);
    steps = i + 1;
    if (endAt < 0 && M.phase === 'matchEnd') endAt = i + MATCH_TAIL;
    const last = i === endAt || i === MATCH_CAP - 1;
    if (i % MATCH_SAMPLE_EVERY === MATCH_SAMPLE_EVERY - 1 || last) samples.push(takeSample(i, W, M));
  }
  return {
    name: sc.name,
    kind: 'match',
    seed,
    p1: { weapon: sc.p1, abilities: null },
    p2: { weapon: sc.p2, abilities: null },
    gap: null,
    ai: [
      { difficulty: sc.d1, seed: seeds[0] },
      { difficulty: sc.d2, seed: seeds[1] },
    ],
    setup: [],
    steps,
    inputs,
    sample_every: MATCH_SAMPLE_EVERY,
    samples,
    events,
  };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

/**
 * `--trace <name>`: print one world scenario's events, setup and check result
 * (a failing check is reported, not thrown); writes nothing. For tuning scripts.
 */
function trace(name: string) {
  const sc = WORLD_SCENARIOS.find((s) => s.name === name);
  if (!sc) throw new Error(`no world scenario ${name}`);
  let verdict = 'check: ok';
  const check = (c: CheckCtx) => {
    try {
      sc.check(c);
    } catch (err) {
      verdict = (err as Error).message;
    }
  };
  const g = recordWorld({ ...sc, check });
  for (const { step, e } of g.events) {
    const { t, ...rest } = e as { t: string };
    console.log(String(step).padStart(4), t.padEnd(14), JSON.stringify(rest));
  }
  for (const s of g.setup) console.log('setup', JSON.stringify(s));
  console.log(verdict);
}

function main() {
  const t = process.argv.indexOf('--trace');
  if (t >= 0) return trace(process.argv[t + 1]);
  mkdirSync(OUT, { recursive: true });
  const goldens = [...WORLD_SCENARIOS.map(recordWorld), ...MATCH_SCENARIOS.map(recordMatch)];
  const names = goldens.map((g) => g.name);
  if (new Set(names).size !== names.length) throw new Error('duplicate scenario names');

  // remove files from scenarios that no longer exist
  for (const f of readdirSync(OUT)) {
    if (f.endsWith('.json') && f !== 'index.json' && !names.includes(f.slice(0, -5))) rmSync(join(OUT, f));
  }
  let total = 0;
  for (const g of goldens) {
    const text = JSON.stringify(g) + '\n';
    writeFileSync(join(OUT, `${g.name}.json`), text);
    total += text.length;
    let note = '';
    if (g.kind === 'match') {
      const m = (g.samples[g.samples.length - 1] as ReturnType<typeof takeSample>).match!;
      note = `${m.phase === 'matchEnd' ? 'finished' : 'UNFINISHED (cap)'} ${m.wins[0]}-${m.wins[1]}`;
    }
    console.log(
      `${g.name.padEnd(36)} ${g.kind.padEnd(5)} steps ${String(g.steps).padStart(5)}  samples ${String(g.samples.length).padStart(5)}  events ${String(g.events.length).padStart(5)}  ${(text.length / 1024).toFixed(0).padStart(5)} KB  ${note}`,
    );
  }
  const index = JSON.stringify(names, null, 2) + '\n';
  writeFileSync(join(OUT, 'index.json'), index);
  total += index.length;
  console.log(`\n${goldens.length} scenarios, ${(total / 1024 / 1024).toFixed(2)} MB in ${OUT}`);
}

main();
