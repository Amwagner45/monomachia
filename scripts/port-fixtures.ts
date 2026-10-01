// Writes game/tests/fixtures/port.json: TypeScript reference values for
// game/tests/sim/test_port_regressions.gd, which checks the fixes made after
// the line-by-line review of the GDScript port.
//
// usage: npm run godot:fixtures   (or: npx tsx scripts/port-fixtures.ts)
//
// Every float is stored as its IEEE-754 bits in hex (big-endian, 16 digits),
// because Godot's JSON and float-literal parsers are not correctly rounded.
// The file is deterministic: random cases come from the sim's own Rng.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { World } from '../src/sim/world';
import { Match } from '../src/sim/match';
import { Fighter } from '../src/sim/fighter';
import { AIBrain, DIFFICULTY } from '../src/sim/ai/brain';
import { KATANA, DAGGERS, AttackDef } from '../src/sim/moves';
import { Rng } from '../src/sim/rng';
import { B, RawInput, dirIndex, emptyInput } from '../src/sim/input';
import { ARENA_RADIUS, DIR_DEADZONE, FIGHTER_RADIUS } from '../src/sim/constants';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'game', 'tests', 'fixtures', 'port.json');

const dv = new DataView(new ArrayBuffer(8));
const bits = (x: number) => {
  dv.setFloat64(0, x);
  return dv.getBigUint64(0).toString(16).padStart(16, '0');
};
const fromBits = (b: bigint) => {
  dv.setBigUint64(0, BigInt.asUintN(64, b));
  return dv.getFloat64(0);
};
/** The neighbouring double k ulps away (k may be negative), for x > 0. */
const ulps = (x: number, k: number) => {
  dv.setFloat64(0, x);
  return fromBits(dv.getBigUint64(0) + BigInt(k));
};
const naiveHypot = (x: number, z: number) => Math.sqrt(x * x + z * z);

const rng = new Rng(20260930);
const uni = (lo: number, hi: number) => rng.range(lo, hi);

// --- Math.hypot -----------------------------------------------------------------
// Pairs where V8's Math.hypot differs from sqrt(x*x + z*z), plus special values.
const hypot: string[][] = [];
const hypotSpecial: [number, number][] = [
  [0, 0], [-0, -0], [3, 4], [-3, -4], [0, -5], [1e-320, 1e-320], [1e300, 1e300], [1e-300, 1e300],
  [Infinity, NaN], [NaN, -Infinity], [NaN, 1], [-Infinity, 2], [5e-324, 0],
];
for (const [x, z] of hypotSpecial) hypot.push([bits(x), bits(z), bits(Math.hypot(x, z))]);
while (hypot.length < hypotSpecial.length + 120) {
  const s = [0.01, 0.4, 1, 11.08, 30][hypot.length % 5];
  const x = uni(-s, s);
  const z = uni(-s, s);
  if (Math.hypot(x, z) !== naiveHypot(x, z)) hypot.push([bits(x), bits(z), bits(Math.hypot(x, z))]);
}

// --- Math.sin, Math.cos, Math.atan2 ---------------------------------------------
// V8 computes these with its fdlibm port. Arguments cover the sim's ranges, the
// medium (|x| < 2^19 pi/2) and large argument reductions, and special values.
const trigArgs: number[] = [
  0, -0, 1e-9, -1e-9, 1e-300, Math.PI / 4, Math.PI / 2, -Math.PI / 2, Math.PI, -Math.PI, 3 * Math.PI / 4,
  1.5707963267948966, 1.5707963267948963, 2.356194490192345, 7.0685834705770345, 1e6, -1e6, 823549.6,
  1e9, 1e15, 1e22, 1e100, -1e200, 1.7976931348623157e308, NaN, Infinity, -Infinity,
];
for (let i = 0; i < 400; i++) trigArgs.push(uni(-Math.PI, Math.PI));
for (let i = 0; i < 200; i++) trigArgs.push(uni(-2 * Math.PI, 2 * Math.PI));
for (let i = 0; i < 100; i++) trigArgs.push(uni(-60, 60));
for (let i = 0; i < 100; i++) trigArgs.push(uni(-1e5, 1e5));
for (let i = 0; i < 100; i++) trigArgs.push((rng.chance(0.5) ? 1 : -1) * Math.pow(10, uni(6, 300)));
const sincos = trigArgs.map((a) => [bits(a), bits(Math.sin(a)), bits(Math.cos(a))]);

const atanArgs: [number, number][] = [
  [0, 0], [-0, 0], [0, -0], [-0, -0], [0, 3], [-0, 3], [0, -3], [-0, -3], [2, 0], [-2, 0], [2, -0], [-2, -0],
  [Infinity, Infinity], [-Infinity, Infinity], [Infinity, -Infinity], [-Infinity, -Infinity],
  [1, Infinity], [-1, Infinity], [1, -Infinity], [-1, -Infinity], [Infinity, 1], [-Infinity, -1],
  [NaN, 1], [1, NaN], [0.3, 1], [-7, 1], [1e300, 1e-300], [-1e300, 1e-300], [1e-300, -1e300], [-1e-300, -1e300],
  [1e-20, 1], [1e-10, 1e-10], [0.4375, 1], [0.6875, 1], [1.1875, 1], [2.4375, 1], [1e20, 1],
];
for (let i = 0; i < 800; i++) {
  const s = [1e-6, 0.05, 1, 3, 12, 25, 1e4][i % 7];
  atanArgs.push([uni(-s, s), uni(-s, s) * (i % 13 === 0 ? 1e-9 : 1)]);
}
const atan2 = atanArgs.map(([y, x]) => [bits(y), bits(x), bits(Math.atan2(y, x))]);

// --- Thresholds that Math.hypot decides -----------------------------------------
// Sticks and positions where Math.hypot and sqrt(x*x + z*z) fall on different
// sides of a threshold: dirIndex's deadzone and the arena clamp.
function straddle(r: number, n: number, below: (v: number) => boolean) {
  const out: [number, number][] = [];
  while (out.length < n) {
    const t = uni(0, Math.PI * 2);
    const x0 = Math.sin(t) * r;
    const z0 = Math.cos(t) * r;
    for (let i = -3; i <= 3 && out.length < n; i++) {
      for (let j = -3; j <= 3 && out.length < n; j++) {
        const x = x0 > 0 ? ulps(x0, i) : -ulps(-x0, i);
        const z = z0 > 0 ? ulps(z0, j) : -ulps(-z0, j);
        if (below(Math.hypot(x, z)) !== below(naiveHypot(x, z))) out.push([x, z]);
      }
    }
  }
  return out;
}
const deadzone = straddle(DIR_DEADZONE, 8, (m) => m < DIR_DEADZONE).map(([mx, my]) => [bits(mx), bits(my), dirIndex(mx, my)]);

function makeWorld(w1 = KATANA, w2 = KATANA, gap = 2.2) {
  const W = new World({ weapon: w1 }, { weapon: w2 }, 7);
  const [a, b] = W.fighters;
  a.pos = { x: 0, y: 0, z: -gap / 2 };
  b.pos = { x: 0, y: 0, z: gap / 2 };
  a.yaw = 0;
  b.yaw = Math.PI;
  a.setState('free');
  b.setState('free');
  return W;
}
const btn = (...bs: B[]): RawInput => ({ mx: 0, my: 0, buttons: bs.reduce((m, b) => m | (1 << b), 0) });
const move = (mx: number, my: number, ...bs: B[]): RawInput => ({ mx, my, buttons: bs.reduce((m, b) => m | (1 << b), 0) });
const idle = () => emptyInput();

// One idle step with fighter 0 placed at (x, z) and fighter 1 at the centre.
const clampMax = ARENA_RADIUS - FIGHTER_RADIUS;
const clampArena = straddle(clampMax, 8, (r) => !(r > clampMax)).map(([x, z]) => {
  const W = makeWorld();
  const a = W.fighters[0];
  a.pos = { x, y: 0, z };
  W.fighters[1].pos = { x: 0, y: 0, z: 0 };
  W.step([idle(), idle()]);
  return [bits(x), bits(z), bits(a.pos.x), bits(a.pos.z)];
});

// --- Bit-exact traces -------------------------------------------------------------
// FNV-1a over 32-bit words: floats as their two words (-0 counted as 0), ints
// as one word, strings one word per UTF-16 unit.
class Hash {
  h = 2166136261;
  word(w: number) {
    this.h = Math.imul((this.h ^ w) >>> 0, 16777619) >>> 0;
  }
  num(x: number) {
    dv.setFloat64(0, x === 0 ? 0 : x);
    this.word(dv.getUint32(0));
    this.word(dv.getUint32(4));
  }
  int(n: number) {
    this.word(n >>> 0);
  }
  str(s: string) {
    for (let i = 0; i < s.length; i++) this.word(s.charCodeAt(i));
  }
  fighter(f: Fighter) {
    for (const x of [f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.yaw, f.hp, f.posture, f.knockX, f.knockZ]) {
      this.num(x);
    }
    this.int(f.sf);
    this.str(f.state);
    this.int(f.armed ? 1 : 0);
  }
  step(W: World, inputs: RawInput[]) {
    for (const i of inputs) {
      this.num(i.mx);
      this.num(i.my);
      this.int(i.buttons);
    }
    this.int(W.frame);
    this.int(W.hitstop);
    for (const f of W.fighters) this.fighter(f);
    for (const e of W.drainEvents()) this.str(e.t);
  }
}

// A scripted duel: walking, strafing, chains, sprinting, a dodge, a charged
// heavy, a jump attack and blocks, with stick values that are not unit length.
function duelP0(i: number): RawInput {
  if (i < 40) return move(0.37, 0.91);
  if (i < 100) return i < 70 ? move(1, 0, B.Block) : move(1, 0);
  if (i === 100 || i === 108 || i === 116) return btn(B.Light);
  if (i >= 130 && i < 170) return move(-0.6, -0.8, B.Sprint);
  if (i === 175) return move(0.7, 0.2, B.Dodge);
  if (i >= 190 && i < 215) return btn(B.Heavy);
  if (i === 240) return move(0, 1, B.Jump);
  if (i === 250) return btn(B.Light);
  if (i === 300) return btn(B.Heavy);
  if (i >= 270 && i < 330) return move(-1, 0.25);
  return idle();
}
function duelP1(i: number): RawInput {
  if (i >= 20 && i < 60) return btn(B.Block);
  if (i === 70 || i === 78) return btn(B.Light);
  if (i >= 90 && i < 120) return move(-0.45, 0.2);
  if (i === 150) return btn(B.Heavy);
  if (i >= 200 && i < 230) return btn(B.Block);
  if (i === 260) return move(-1, 0, B.Dodge);
  if (i >= 280 && i < 300) return move(0.3, -0.95);
  if (i === 320) return btn(B.Light);
  return idle();
}
const DUEL_STEPS = 360;
const DUEL_EVERY = 30;
const duel: number[] = [];
{
  const W = makeWorld();
  const h = new Hash();
  for (let i = 0; i < DUEL_STEPS; i++) {
    const inputs = [duelP0(i), duelP1(i)];
    W.step(inputs);
    h.step(W, inputs);
    if ((i + 1) % DUEL_EVERY === 0) duel.push(h.h);
  }
}

// Computer against computer through a Match, built the way scripts/soak.ts does.
const AI_STEPS = 3600;
const AI_EVERY = 300;
const aiMatch: number[] = [];
{
  const W = new World({ weapon: KATANA }, { weapon: DAGGERS }, 1005);
  const M = new Match(W);
  const ai = [new AIBrain(W.fighters[0], DIFFICULTY.hard, 16), new AIBrain(W.fighters[1], DIFFICULTY.normal, 82)];
  const h = new Hash();
  for (let i = 0; i < AI_STEPS; i++) {
    const inputs = [ai[0].think(), ai[1].think()];
    M.step(inputs);
    h.step(W, inputs);
    h.str(M.phase);
    if ((i + 1) % AI_EVERY === 0) aiMatch.push(h.h);
  }
}

// --- Optional move fields given values the sentinels used to swallow -----------
// Each case patches Right Cut (k_l1), runs a katana-vs-katana world for `steps`
// steps and records per-step state; the patch is undone afterwards.
type Patch = Partial<AttackDef>;
function patched(patch: Patch, steps: number, p0: (i: number) => RawInput, p1: (i: number) => RawInput, setup?: (W: World) => void) {
  const def = KATANA.moves.k_l1;
  const saved: Record<string, unknown> = {};
  for (const k of Object.keys(patch)) saved[k] = (def as unknown as Record<string, unknown>)[k];
  Object.assign(def, patch);
  try {
    const W = makeWorld();
    setup?.(W);
    const [a, b] = W.fighters;
    const trace: unknown[] = [];
    const h = new Hash();
    for (let i = 0; i < steps; i++) {
      const inputs = [p0(i), p1(i)];
      W.step(inputs);
      const events = W.drainEvents();
      trace.push([W.hitstop, a.state, b.state, events.filter((e) => e.t === 'hit').length, bits(b.hp), bits(b.posture)]);
      h.int(W.hitstop);
      h.fighter(a);
      h.fighter(b);
      for (const e of events) h.str(e.t);
    }
    return { trace, hash: h.h, aPos: [bits(a.pos.x), bits(a.pos.z)] };
  } finally {
    for (const k of Object.keys(patch)) {
      if (saved[k] === undefined) delete (def as unknown as Record<string, unknown>)[k];
      else (def as unknown as Record<string, unknown>)[k] = saved[k];
    }
  }
}
const lightAt0 = (i: number) => (i === 0 ? btn(B.Light) : idle());
const holdBlock = () => btn(B.Block);
const sentinels = {
  // multiInterval 0: (f - S - 1) % 0 is NaN, so every active frame is skipped
  multiIntervalZero: patched({ multiHit: 3, multiInterval: 0, active: 6 }, 30, lightAt0, idle),
  // a negative interval is used as is: x % -2 has the sign of x
  multiIntervalNegative: patched({ multiHit: 3, multiInterval: -2, active: 6 }, 30, lightAt0, idle),
  // guardCrush ?? blockMitigation keeps a negative multiplier (addPosture then ignores it)
  guardCrushNegative: patched({ guardCrush: -0.5 }, 30, lightAt0, holdBlock, (W) => {
    W.fighters[1].posture = 40;
  }),
  // dodgeCancelFrom !== undefined accepts a negative frame: cancellable at once
  dodgeCancelNegative: patched({ dodgeCancelFrom: -1 }, 12, (i) => (i === 0 ? btn(B.Light) : i === 3 ? btn(B.Dodge) : idle()), idle),
  // lungeEnd ?? S + A keeps a negative end: no lunge at all
  lungeEndNegative: patched({ lungeEnd: -1 }, 30, lightAt0, idle, (W) => {
    W.fighters[1].pos.z = 4;
  }),
  // hitstop / hitstun / blockstun ?? default keep a negative value
  hitstopNegative: patched({ hitstop: -3, hitstun: -4 }, 30, lightAt0, idle),
  blockstunNegative: patched({ blockstun: -5, hitstop: -2 }, 30, lightAt0, holdBlock),
};

// --- JS number formatting and parsing for the tools -----------------------------
const toFixedCases: number[] = [
  0, -0, 0.001, 0.0015, 0.0038, 0.0005, 0.00049, 0.0025, 0.0035, 0.0036, 0.0037, 0.00375, 0.0076, 0.0155, 0.01555,
  1.005, 2.5, 0.5, 1.5, -0.0001, -0.0005, 1e-10, 123.456, 0.0625, 0.125, 44.5, 121.8, 281.125, 12.345, 9.995,
  -2.5, -1.005, 1e15, 4503599627370495.5, 4503599627370496, 9007199254740991,
];
for (let i = 0; i < 150; i++) toFixedCases.push(uni(0, 0.02));
for (let i = 0; i < 150; i++) toFixedCases.push(uni(-500, 500));
for (let i = 0; i < 60; i++) toFixedCases.push(Math.pow(2, -Math.floor(uni(1, 70))) * uni(1, 2));
const toFixed: unknown[] = [];
for (const x of toFixedCases) for (const d of [0, 1, 2, 3]) toFixed.push([bits(x), d, x.toFixed(d)]);

const numberArgs = [
  '40', '30', '40.5', '1.5', 'abc', '', ' ', ' 12 ', '\t7\n', '1e1', '1E+2', '2e-1', '.5', '5.', '-5', '+5', '-0',
  '0x10', '0X1f', '0b101', '0o17', '-0x10', '0x', '1_000', 'Infinity', '-Infinity', '+Infinity', 'infinity', 'NaN',
  '12abc', '1.2.3', '00012', '1e400', '-1e400', '1e-400', '0.1', '0.30000000000000004', '123456789012345678901234567890',
];
const numberCases = numberArgs.map((s) => [s, bits(Number(s)), String(Number(s))]);
const strCases: number[] = [0.1, 0.1 + 0.2, 1 / 3, 40.5, 1e21, 1e20, 1e-7, 1e-6, 123456789.123, 2 / 3, 100, 1e15, 1e16, -0, -1.5, 5e-324, 1.7976931348623157e308, 0.000001234, 12345678901234567890];
for (let i = 0; i < 100; i++) strCases.push(uni(-1, 1) * Math.pow(10, Math.floor(uni(-12, 25))));
const numToString = strCases.map((x) => [bits(x), String(x)]);

const data = {
  hypot,
  sincos,
  atan2,
  deadzone,
  clampArena,
  duel: { steps: DUEL_STEPS, every: DUEL_EVERY, hashes: duel },
  aiMatch: { steps: AI_STEPS, every: AI_EVERY, hashes: aiMatch },
  sentinels,
  toFixed,
  number: numberCases,
  numToString,
};

mkdirSync(dirname(OUT), { recursive: true });
const lines = Object.entries(data).map(([k, v]) => {
  if (Array.isArray(v)) return `  ${JSON.stringify(k)}: [\n${v.map((r) => '    ' + JSON.stringify(r)).join(',\n')}\n  ]`;
  return `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`;
});
writeFileSync(OUT, '{\n' + lines.join(',\n') + '\n}\n');
console.log(`wrote ${OUT}`);
