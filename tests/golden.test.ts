// Replays every golden file in game/tests/golden/ on the TypeScript rules, using
// only what the file holds (the format is documented at the top of
// scripts/golden/record.ts), and expects the samples and events to match
// exactly. This proves the files are complete enough for the GDScript replay,
// and fails if the web rules drift from the recording.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Fighter } from '../src/sim/fighter';
import { Match } from '../src/sim/match';
import { WEAPONS, WeaponId } from '../src/sim/moves';
import { World } from '../src/sim/world';

const DIR = join(__dirname, '..', 'game', 'tests', 'golden');

interface Player {
  weapon: WeaponId;
  abilities: [string, string] | null;
}
interface Setup {
  step: number;
  fighter: number;
  field: string;
  value: any;
}
interface Golden {
  name: string;
  kind: 'world' | 'match';
  seed: number;
  p1: Player;
  p2: Player;
  gap: number | null;
  setup: Setup[];
  steps: number;
  inputs: number[][];
  sample_every: number;
  samples: any[];
  events: { step: number; e: any }[];
}

function fighter(f: Fighter) {
  const a = f.atk;
  return {
    state: f.state,
    sf: f.sf,
    stateDur: f.stateDur,
    hp: f.hp,
    posture: f.posture,
    x: f.pos.x,
    y: f.pos.y,
    z: f.pos.z,
    yaw: f.yaw,
    vx: f.vel.x,
    vy: f.vel.y,
    vz: f.vel.z,
    armed: f.armed,
    blocking: f.blocking,
    ultUsed: f.ultUsed,
    atk: a ? { id: a.def.id, frame: a.frame, charging: a.charging, chargeFrames: a.chargeFrames, hitDone: a.hitDone } : null,
  };
}

function applySetup(W: World, s: Setup) {
  const f = W.fighters[s.fighter];
  const v = s.value;
  switch (s.field) {
    case 'hp':
      f.hp = v;
      break;
    case 'posture':
      f.posture = v;
      break;
    case 'yaw':
      f.yaw = v;
      break;
    case 'blind_until':
      f.blindUntil = v;
      break;
    case 'last_posture_damage':
      f.lastPostureDamage = v;
      break;
    case 'armed':
      f.armed = v;
      break;
    case 'pos':
      f.pos = { x: v.x, y: v.y, z: v.z };
      break;
    case 'weapon':
      f.weapon = WEAPONS[v as WeaponId];
      break;
    case 'abilities':
      f.abilities = [v[0], v[1]];
      break;
    default:
      throw new Error(`unknown setup field ${s.field}`);
  }
}

/** Replay a golden file and return what the rules produce, in the file's own shape. */
function replay(g: Golden) {
  const cfg = (p: Player) => ({ weapon: WEAPONS[p.weapon], abilities: p.abilities ?? undefined });
  const W = new World(cfg(g.p1), cfg(g.p2), g.seed);
  let M: Match | null = null;
  if (g.kind === 'world') {
    const [a, b] = W.fighters;
    a.pos = { x: 0, y: 0, z: -g.gap! / 2 };
    b.pos = { x: 0, y: 0, z: g.gap! / 2 };
    a.yaw = 0;
    b.yaw = Math.PI;
    a.setState('free');
    b.setState('free');
  } else {
    M = new Match(W);
  }
  const samples: unknown[] = [];
  const events: { step: number; e: unknown }[] = [];
  let next = 0;
  for (let i = 0; i < g.steps; i++) {
    while (next < g.setup.length && g.setup[next].step === i) applySetup(W, g.setup[next++]);
    const r = g.inputs[i];
    const inputs = [
      { mx: r[0], my: r[1], buttons: r[2] },
      { mx: r[3], my: r[4], buttons: r[5] },
    ];
    if (M) M.step(inputs);
    else W.step(inputs);
    for (const e of W.drainEvents()) events.push({ step: i, e: JSON.parse(JSON.stringify(e)) });
    if (i % g.sample_every === g.sample_every - 1 || i === g.steps - 1) {
      samples.push({
        step: i,
        frame: W.frame,
        hitstop: W.hitstop,
        timeScale: W.timeScale,
        match: M ? { phase: M.phase, round: M.round, wins: [M.wins[0], M.wins[1]], phaseFrames: M.phaseFrames } : null,
        fighters: [fighter(W.fighters[0]), fighter(W.fighters[1])],
        weapons: W.weapons.map((w) => [w.owner, w.pos.x, w.pos.y, w.pos.z, w.grounded]),
        waves: W.waves.map((w) => [w.owner.id, w.s, w.alive]),
      });
    }
  }
  expect(next).toBe(g.setup.length); // every setup entry was applied
  return { samples, events };
}

const names: string[] = JSON.parse(readFileSync(join(DIR, 'index.json'), 'utf8'));

describe('golden replays match the TypeScript rules', () => {
  it('lists the golden files', () => {
    expect(names.length).toBeGreaterThan(0);
  });

  for (const name of names) {
    it(name, () => {
      const g: Golden = JSON.parse(readFileSync(join(DIR, `${name}.json`), 'utf8'));
      expect(g.name).toBe(name);
      expect(g.inputs.length).toBe(g.steps);
      const out = replay(g);
      // compare as JSON text, the way the file stores numbers
      expect(JSON.stringify(out.events)).toBe(JSON.stringify(g.events));
      expect(JSON.stringify(out.samples)).toBe(JSON.stringify(g.samples));
    });
  }
});
