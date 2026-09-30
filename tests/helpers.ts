import { World } from '../src/sim/world';
import { B, RawInput, emptyInput } from '../src/sim/input';
import { WeaponDef, KATANA } from '../src/sim/moves';
import type { SimEvent } from '../src/sim/events';

export function makeWorld(w1: WeaponDef = KATANA, w2: WeaponDef = KATANA, gap = 2.2, abilities?: {
  a?: [string, string];
  b?: [string, string];
}) {
  const W = new World({ weapon: w1, abilities: abilities?.a }, { weapon: w2, abilities: abilities?.b }, 7);
  const [a, b] = W.fighters;
  a.pos = { x: 0, y: 0, z: -gap / 2 };
  b.pos = { x: 0, y: 0, z: gap / 2 };
  a.yaw = 0;
  b.yaw = Math.PI;
  a.setState('free');
  b.setState('free');
  return W;
}

export const btn = (...bs: B[]): RawInput => ({ mx: 0, my: 0, buttons: bs.reduce((m, b) => m | (1 << b), 0) });
export const move = (mx: number, my: number, ...bs: B[]): RawInput => ({
  mx,
  my,
  buttons: bs.reduce((m, b) => m | (1 << b), 0),
});
export const idle = () => emptyInput();

/** Collected events across steps. */
export class Rec {
  events: SimEvent[] = [];
  collect(W: World) {
    this.events.push(...W.drainEvents());
  }
  has(t: SimEvent['t']) {
    return this.events.some((e) => e.t === t);
  }
  find<T extends SimEvent['t']>(t: T) {
    return this.events.find((e) => e.t === t) as Extract<SimEvent, { t: T }> | undefined;
  }
  count(t: SimEvent['t']) {
    return this.events.filter((e) => e.t === t).length;
  }
}

/** Step the world with per-player input functions of the step index. */
export function run(
  W: World,
  n: number,
  p0: (i: number) => RawInput = idle,
  p1: (i: number) => RawInput = idle,
  rec?: Rec,
) {
  for (let i = 0; i < n; i++) {
    W.step([p0(i), p1(i)]);
    if (rec) rec.collect(W);
  }
}

/** Run until the predicate is true (or the limit), returning the number of steps taken. */
export function runUntil(
  W: World,
  pred: () => boolean,
  limit: number,
  p0: (i: number) => RawInput = idle,
  p1: (i: number) => RawInput = idle,
  rec?: Rec,
) {
  for (let i = 0; i < limit; i++) {
    if (pred()) return i;
    W.step([p0(i), p1(i)]);
    if (rec) rec.collect(W);
  }
  return limit;
}

/** Press a button on frame `at` only (a tap). */
export const tapAt = (at: number, b: B) => (i: number) => (i === at ? btn(b) : idle());
