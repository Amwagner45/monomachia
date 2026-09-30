import { describe, expect, it } from 'vitest';
import { B, InputTracker, emptyInput } from '../src/sim/input';
import { Match, INTRO_FRAMES, ROUND_END_FRAMES } from '../src/sim/match';
import { World } from '../src/sim/world';
import { KATANA } from '../src/sim/moves';
import type { SimEvent } from '../src/sim/events';
import { btn, idle, move } from './helpers';

describe('match flow', () => {
  it('first to 3 rounds wins the match', () => {
    const W = new World({ weapon: KATANA }, { weapon: KATANA }, 3);
    const M = new Match(W);
    const events: SimEvent[] = [];
    const stepM = (n: number, p0 = idle) => {
      for (let i = 0; i < n; i++) {
        M.step([p0(), emptyInput()]);
        events.push(...W.drainEvents());
      }
    };
    for (let round = 0; round < 3; round++) {
      stepM(INTRO_FRAMES + 2);
      expect(M.phase).toBe('fight');
      // put the fighters close and make the next hit lethal
      const [a, b] = W.fighters;
      a.pos = { x: 0, y: 0, z: -1 };
      b.pos = { x: 0, y: 0, z: 1 };
      a.yaw = 0;
      b.hp = 1;
      let i = 0;
      stepM(40, () => (i++ === 0 ? btn(B.Light) : idle()));
      expect(M.phase).toBe('roundEnd');
      stepM(ROUND_END_FRAMES + 2);
    }
    expect(M.wins).toEqual([3, 0]);
    expect(M.phase).toBe('matchEnd');
    expect(events.some((e) => e.t === 'matchOver' && e.winner === 0)).toBe(true);
  });

  it('fighters cannot act during the round intro', () => {
    const W = new World({ weapon: KATANA }, { weapon: KATANA }, 3);
    const M = new Match(W);
    for (let i = 0; i < 30; i++) M.step([btn(B.Light), emptyInput()]);
    expect(W.fighters[0].state).toBe('intro');
  });
});

describe('input tracker', () => {
  it('a fresh push from neutral requests a step', () => {
    const t = new InputTracker();
    t.update(emptyInput(), 1);
    t.update(move(0, 1), 2);
    expect(t.stepRequest).toBe(true);
    t.update(move(0, 1), 3);
    expect(t.stepRequest).toBe(false);
  });

  it('double-tap and hold latches a sprint; releasing clears it', () => {
    const t = new InputTracker();
    let f = 1;
    t.update(move(0, 1), f++);
    t.update(move(0, 1), f++);
    t.update(emptyInput(), f++);
    t.update(emptyInput(), f++);
    t.update(move(0, 1), f++);
    expect(t.sprinting).toBe(true);
    t.update(emptyInput(), f++);
    expect(t.sprinting).toBe(false);
  });

  it('a slow second push does not sprint', () => {
    const t = new InputTracker();
    let f = 1;
    t.update(move(0, 1), f++);
    t.update(emptyInput(), f++);
    for (let i = 0; i < 30; i++) t.update(emptyInput(), f++);
    t.update(move(0, 1), f++);
    expect(t.sprinting).toBe(false);
  });

  it('buffers presses for a few frames', () => {
    const t = new InputTracker();
    t.update(btn(B.Light), 10);
    t.update(emptyInput(), 14);
    expect(t.buffered(B.Light)).toBe(true);
    t.update(emptyInput(), 30);
    expect(t.buffered(B.Light)).toBe(false);
  });
});
