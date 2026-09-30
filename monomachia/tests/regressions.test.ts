// Regression tests for bugs found in the independent code review.
import { describe, expect, it } from 'vitest';
import { B } from '../src/sim/input';
import { DAGGERS, GREATSWORD, KATANA } from '../src/sim/moves';
import { DISARMED_STAGGER_RESET, POSTURE_MAX } from '../src/sim/constants';
import { Rec, btn, idle, makeWorld, run } from './helpers';

describe('review regressions', () => {
  it("changing a fighter's weapon mid-combo never crashes", () => {
    const W = makeWorld();
    const [a] = W.fighters;
    const p0 = (i: number) => {
      if (i === 6) {
        a.weapon = GREATSWORD;
        a.abilities = [...GREATSWORD.defaultAbilities] as [string, string];
      }
      return i % 5 === 0 ? btn(B.Light) : idle();
    };
    expect(() => run(W, 120, p0, idle)).not.toThrow();
  });

  it('a move from a weapon you no longer hold is refused instead of crashing', () => {
    const W = makeWorld();
    const [a] = W.fighters;
    a.armed = false;
    expect(a.startAttack('k_l2')).toBe(false);
    a.armed = true;
    expect(a.startAttack('f_breaker')).toBe(true); // bare-hand moves always resolve
  });

  it('parrying a bare-handed attacker at full posture dazes them instead of disarming again', () => {
    const W = makeWorld(KATANA, KATANA, 1.5);
    const r = new Rec();
    const [a] = W.fighters;
    a.armed = false;
    const p0 = (i: number) => {
      if (i <= 6) {
        a.posture = POSTURE_MAX;
        a.lastPostureDamage = W.frame;
      }
      return i === 0 ? btn(B.Light) : idle();
    };
    // jab (startup 5) connects on frame 7; block pressed on frame 3
    run(W, 14, p0, (i) => (i === 2 ? btn(B.Block) : idle()), r);
    expect(r.has('parry')).toBe(true);
    expect(r.has('disarm')).toBe(false);
    expect(r.has('stagger')).toBe(true);
    expect(a.state).toBe('stagger');
    expect(a.posture).toBeLessThanOrEqual(DISARMED_STAGGER_RESET + 1e-6);
    expect(W.weaponOf(0)).toBeNull();
  });

  it('a trade between two charged heavies is fair: both take the same damage', () => {
    const W = makeWorld(KATANA, KATANA, 2.2);
    const r = new Rec();
    const hold = (i: number) => (i < 60 ? btn(B.Heavy) : idle());
    run(W, 140, hold, hold, r);
    const hits = r.events.filter((e) => e.t === 'hit') as Extract<(typeof r.events)[number], { t: 'hit' }>[];
    expect(hits.length).toBe(2);
    expect(hits[0].damage).toBeGreaterThan(13); // the charge counted for both
    expect(hits[0].damage).toBeCloseTo(hits[1].damage);
    const [a, b] = W.fighters;
    expect(a.hp).toBeCloseTo(b.hp);
  });

  it('one block press parries one hit, not a whole flurry', () => {
    // find when the first Lightning Tempest spin lands on an idle greatsword
    const probe = makeWorld(DAGGERS, GREATSWORD, 7);
    probe.fighters[0].hp = 20;
    let firstHit = -1;
    for (let i = 0; i < 140 && firstHit < 0; i++) {
      probe.step([i === 0 ? btn(B.Ultimate) : idle(), idle()]);
      if (probe.drainEvents().some((e) => e.t === 'hit')) firstHit = probe.frame;
    }
    expect(firstHit).toBeGreaterThan(0);

    // one press a frame early: the next spin (10 frames later) would still be
    // inside the greatsword's 12-frame window if the press weren't used up
    const W = makeWorld(DAGGERS, GREATSWORD, 7);
    W.fighters[0].hp = 20;
    const r = new Rec();
    run(W, 140, (i) => (i === 0 ? btn(B.Ultimate) : idle()), (i) => (i === firstHit - 2 ? btn(B.Block) : idle()), r);
    expect(r.count('parry')).toBe(1);
  });

  it('a Moonsplitter wave still in flight when the round ends does no damage', () => {
    const W = makeWorld(KATANA, KATANA, 8);
    const r = new Rec();
    const [a, b] = W.fighters;
    a.hp = 20;
    let waved = false;
    run(
      W,
      90,
      (i) => {
        if (waved && a.hp > 0) a.hp = 0; // the caster is knocked out while the wave travels
        return i === 0 ? btn(B.Ultimate) : idle();
      },
      idle,
      {
        events: r.events,
        collect(w) {
          const ev = w.drainEvents();
          if (ev.some((e) => e.t === 'ultWave')) waved = true;
          r.events.push(...ev);
        },
      } as Rec,
    );
    expect(waved).toBe(true);
    expect(r.count('ko')).toBe(1);
    expect(b.hp).toBe(100);
  });
});
