import { describe, expect, it } from 'vitest';
import { B } from '../src/sim/input';
import { DAGGERS, GREATSWORD, KATANA } from '../src/sim/moves';
import { Rec, btn, idle, makeWorld, move, run } from './helpers';
import { HIT_POSTURE_MULT } from '../src/sim/constants';

describe('ultimates', () => {
  it('are locked above 25% HP', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 5, (i) => (i === 0 ? btn(B.Light, B.Heavy) : idle()), idle, r);
    expect(r.has('ultStart')).toBe(false);
  });

  it('unlock at 25% HP, fire on light+heavy, and only once per round', () => {
    const W = makeWorld(KATANA, KATANA, 3);
    const r = new Rec();
    const a = W.fighters[0];
    a.hp = 25;
    run(W, 3, idle, idle, r);
    expect(r.has('ultReady')).toBe(true);
    run(W, 100, (i) => (i === 0 ? btn(B.Light, B.Heavy) : idle()), idle, r);
    expect(r.count('ultStart')).toBe(1);
    const r2 = new Rec();
    run(W, 100, (i) => (i === 0 ? btn(B.Light, B.Heavy) : idle()), idle, r2);
    expect(r2.has('ultStart')).toBe(false);
  });

  it('light pressed a frame before heavy still counts as the chord', () => {
    const W = makeWorld(KATANA, KATANA, 3);
    const r = new Rec();
    W.fighters[0].hp = 20;
    run(W, 10, (i) => (i === 0 ? btn(B.Light) : i === 2 ? btn(B.Heavy) : idle()), idle, r);
    expect(r.has('ultStart')).toBe(true);
  });

  it('Moonsplitter (vertical) crosses the stage and hits', () => {
    const W = makeWorld(KATANA, KATANA, 8);
    const r = new Rec();
    W.fighters[0].hp = 20;
    run(W, 70, (i) => (i === 0 ? btn(B.Ultimate) : idle()), idle, r);
    expect(r.find('ultWave')?.kind).toBe('vertical');
    expect(W.fighters[1].hp).toBeCloseTo(70);
  });

  it('Moonsplitter (horizontal) can be jumped over', () => {
    const W = makeWorld(KATANA, KATANA, 8);
    const r = new Rec();
    W.fighters[0].hp = 20;
    // tilt sideways while sheathed; defender jumps as the wave approaches
    run(
      W,
      70,
      (i) => (i === 0 ? btn(B.Ultimate) : i < 30 ? move(1, 0) : idle()),
      (i) => (i === 38 ? btn(B.Jump) : idle()),
      r,
    );
    expect(r.find('ultWave')?.kind).toBe('horizontal');
    expect(W.fighters[1].hp).toBe(100);
  });

  it('Impaler dashes, impales, and bursts on heavy', () => {
    const W = makeWorld(GREATSWORD, KATANA, 6);
    const r = new Rec();
    W.fighters[0].hp = 20;
    run(W, 140, (i) => (i === 0 ? btn(B.Ultimate) : i >= 50 && i % 3 === 0 ? btn(B.Heavy) : idle()), idle, r);
    expect(r.has('ultImpale')).toBe(true);
    expect(r.has('ultBurst')).toBe(true);
    expect(W.fighters[1].hp).toBeCloseTo(65);
  });

  it('Lightning Tempest lands six spins and a finisher', () => {
    const W = makeWorld(DAGGERS, KATANA, 7);
    const r = new Rec();
    W.fighters[0].hp = 20;
    run(W, 140, (i) => (i === 0 ? btn(B.Ultimate) : idle()), idle, r);
    const hits = r.events.filter((e) => e.t === 'hit');
    expect(hits.length).toBe(7);
    expect(W.fighters[1].hp).toBeCloseTo(100 - 6 * 5 - 8);
  });

  it('disarmed: the ultimate offers Recall, which re-arms', () => {
    const W = makeWorld(KATANA, KATANA, 4);
    const [a, b] = W.fighters;
    a.hp = 20;
    a.posture = 100;
    a.disarm(b, 'parried');
    run(W, 60);
    const r = new Rec();
    run(W, 80, (i) => (i === 0 ? btn(B.Ultimate) : i === 10 ? btn(B.Light) : idle()), idle, r);
    expect(r.has('ultChoice')).toBe(true);
    expect(r.has('recall')).toBe(true);
    expect(a.armed).toBe(true);
    expect(W.weaponOf(0)).toBeNull();
  });

  it('disarmed: choosing heavy throws the Breaker Palm posture blow', () => {
    const W = makeWorld(KATANA, KATANA, 1.8);
    const [a, b] = W.fighters;
    a.hp = 20;
    a.armed = false;
    const r = new Rec();
    run(W, 80, (i) => (i === 0 ? btn(B.Ultimate) : i === 10 ? btn(B.Heavy) : idle()), idle, r);
    const hit = r.find('hit');
    expect(hit?.attack).toBe('f_breaker');
    expect(b.posture).toBeCloseTo(Math.min(100, 50 * HIT_POSTURE_MULT));
  });
});
