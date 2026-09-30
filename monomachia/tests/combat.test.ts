import { describe, expect, it } from 'vitest';
import { B } from '../src/sim/input';
import { DAGGERS, GREATSWORD, KATANA } from '../src/sim/moves';
import { HIT_POSTURE_MULT, PARRY_POSTURE, POSTURE_MAX, POSTURE_RECOVER_STAND } from '../src/sim/constants';
import { Rec, btn, idle, makeWorld, move, run, tapAt } from './helpers';

// A katana light (startup 11) started on step 0 becomes active on world frame 13.

describe('attacks', () => {
  it('a light attack hits an idle opponent for its HP and posture damage', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 30, tapAt(0, B.Light), idle, r);
    const [, b] = W.fighters;
    expect(r.has('hit')).toBe(true);
    expect(b.hp).toBeCloseTo(94);
    expect(b.posture).toBeCloseTo(7 * HIT_POSTURE_MULT);
  });

  it('misses when the opponent is out of range', () => {
    const W = makeWorld(KATANA, KATANA, 6);
    const r = new Rec();
    run(W, 40, tapAt(0, B.Light), idle, r);
    expect(r.has('hit')).toBe(false);
    expect(r.has('whiff')).toBe(true);
    expect(W.fighters[1].hp).toBe(100);
  });

  it('light attacks chain into a combo string', () => {
    const W = makeWorld();
    const r = new Rec();
    // press light repeatedly
    run(W, 90, (i) => (i % 8 === 0 ? btn(B.Light) : idle()), idle, r);
    const hits = r.events.filter((e) => e.t === 'hit').map((e) => (e as any).attack);
    expect(hits.slice(0, 3)).toEqual(['k_l1', 'k_l2', 'k_l3']);
  });

  it('a heavy held for 2.5 s releases by itself as a stronger power attack', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 220, () => btn(B.Heavy), idle, r);
    const hit = r.find('hit')!;
    expect(hit).toBeDefined();
    expect(hit.attack).toBe('k_h1');
    expect(hit.damage).toBeCloseTo(13 * 1.8);
  });
});

describe('blocking and parrying', () => {
  it('blocking stops HP damage but takes reduced posture damage', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 30, tapAt(0, B.Light), () => btn(B.Block), r);
    const b = W.fighters[1];
    expect(r.has('block')).toBe(true);
    expect(b.hp).toBe(100);
    expect(b.posture).toBeCloseTo(7 * KATANA.blockMitigation);
  });

  it('a well-timed block press parries: attacker recoils and takes parry posture', () => {
    const W = makeWorld();
    const r = new Rec();
    // impact on frame 13; press on step 8 -> frame 9 (4 frames early, inside the 9-frame window)
    run(W, 20, tapAt(0, B.Light), tapAt(8, B.Block), r);
    const [a, b] = W.fighters;
    const p = r.find('parry')!;
    expect(p).toBeDefined();
    expect(p.kind).toBe('parry');
    expect(p.timing).toBe(4);
    expect(b.hp).toBe(100);
    expect(a.posture).toBeCloseTo(PARRY_POSTURE);
    expect(a.state).toBe('recoil');
  });

  it('pressing block too early only blocks', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 30, tapAt(0, B.Light), (i) => (i >= 1 ? btn(B.Block) : idle()), r);
    expect(r.has('parry')).toBe(false);
    expect(r.has('block')).toBe(true);
  });

  it('mashing block shrinks the parry window', () => {
    const W = makeWorld();
    const b = W.fighters[1];
    // three presses 4 frames apart
    run(W, 12, idle, (i) => (i % 4 === 0 ? btn(B.Block) : idle()));
    expect(b.parryWindowAtPress).toBe(KATANA.parryWindow - 2 * 3);
  });

  it('the greatsword has a larger parry window than the daggers', () => {
    expect(GREATSWORD.parryWindow).toBeGreaterThan(KATANA.parryWindow);
    expect(KATANA.parryWindow).toBeGreaterThan(DAGGERS.parryWindow);
  });

  it('you cannot block an attack coming from behind', () => {
    const W = makeWorld();
    const r = new Rec();
    const b = W.fighters[1];
    run(W, 1);
    b.yaw = 0; // turn away from the attacker
    b.blindUntil = 1e9;
    run(W, 30, tapAt(0, B.Light), () => btn(B.Block), r);
    expect(r.has('hit')).toBe(true);
  });
});

describe('posture and disarm', () => {
  it('a parried attacker with a full posture meter is disarmed and loses no HP', () => {
    const W = makeWorld();
    const r = new Rec();
    const [a] = W.fighters;
    a.posture = POSTURE_MAX;
    run(W, 30, tapAt(0, B.Light), tapAt(8, B.Block), r);
    expect(r.has('disarm')).toBe(true);
    expect(a.armed).toBe(false);
    expect(a.hp).toBe(100);
    expect(a.posture).toBe(0);
    expect(W.weaponOf(0)).not.toBeNull();
  });

  it('blocking an unblockable takes the full hit', () => {
    const W = makeWorld();
    const r = new Rec();
    // katana heavy ability = Piercing Thrust
    run(W, 45, (i) => (i === 0 ? btn(B.Block, B.Heavy) : idle()), () => btn(B.Block), r);
    expect(r.has('telegraph')).toBe(true);
    expect(r.has('hit')).toBe(true);
    expect(W.fighters[1].hp).toBeCloseTo(88);
  });

  it('blocking an unblockable with a full meter disarms the blocker', () => {
    const W = makeWorld();
    const r = new Rec();
    const keepFull = () => {
      // recent pressure: the meter is full and has not had time to drain
      W.fighters[1].posture = POSTURE_MAX;
      W.fighters[1].lastPostureDamage = W.frame;
      return btn(B.Block);
    };
    run(W, 45, (i) => (i === 0 ? btn(B.Block, B.Heavy) : idle()), keepFull, r);
    expect(r.has('disarm')).toBe(true);
    expect(W.fighters[1].armed).toBe(false);
    expect(W.fighters[1].hp).toBe(100);
  });

  it('blocking a full-charge power attack with a full meter disarms', () => {
    const W = makeWorld();
    const r = new Rec();
    W.fighters[1].posture = POSTURE_MAX;
    // attacker holds heavy for the whole charge; defender holds block but must not drain posture:
    // keep hitting posture to full each frame to simulate pressure
    run(W, 220, () => btn(B.Heavy), () => {
      W.fighters[1].posture = POSTURE_MAX;
      W.fighters[1].lastPostureDamage = W.frame;
      return btn(B.Block);
    }, r);
    expect(r.has('disarm')).toBe(true);
  });

  it('holding block while standing drains posture faster than while moving, and slower at low HP', () => {
    const drain = (hp: number, moving: boolean) => {
      const W = makeWorld(KATANA, KATANA, 5);
      const b = W.fighters[1];
      b.posture = 60;
      b.hp = hp;
      run(W, 60, idle, () => (moving ? move(1, 0, B.Block) : btn(B.Block)));
      return 60 - b.posture;
    };
    const standFull = drain(100, false);
    const moveFull = drain(100, true);
    const standLow = drain(30, false);
    expect(standFull).toBeGreaterThan(moveFull);
    expect(standFull).toBeGreaterThan(standLow);
    expect(standFull).toBeCloseTo(POSTURE_RECOVER_STAND, 0);
  });

  it('posture does not drain while not blocking', () => {
    const W = makeWorld(KATANA, KATANA, 5);
    const b = W.fighters[1];
    b.posture = 60;
    run(W, 120);
    expect(b.posture).toBe(60);
  });
});

describe('dodging and the unblockable counters', () => {
  it('dodge invincibility lets a normal attack pass through', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 30, tapAt(0, B.Light), (i) => (i === 7 ? move(0, 1, B.Dodge) : idle()), r);
    expect(r.has('evade')).toBe(true);
    expect(W.fighters[1].hp).toBe(100);
  });

  it('dodge invincibility does not work against unblockables', () => {
    const W = makeWorld(GREATSWORD, KATANA, 1.6);
    const r = new Rec();
    run(W, 45, (i) => (i === 0 ? btn(B.Block, B.Light) : idle()), (i) => (i === 24 ? move(1, 0, B.Dodge) : idle()), r);
    expect(r.has('hit')).toBe(true);
  });

  it('dodging into a thrust triggers the stomp counter', () => {
    const W = makeWorld();
    const r = new Rec();
    run(W, 45, (i) => (i === 0 ? btn(B.Block, B.Heavy) : idle()), (i) => (i === 20 ? move(0, 1, B.Dodge) : idle()), r);
    const c = r.find('counter')!;
    expect(c).toBeDefined();
    expect(c.kind).toBe('stomp');
    const [a, b] = W.fighters;
    expect(b.hp).toBe(100);
    expect(a.posture).toBeGreaterThanOrEqual(30);
  });

  it('jumping over a sweep triggers the leap counter', () => {
    const W = makeWorld(GREATSWORD, KATANA, 2.2);
    const r = new Rec();
    run(W, 50, (i) => (i === 0 ? btn(B.Block, B.Light) : idle()), (i) => (i === 20 ? btn(B.Jump) : idle()), r);
    const c = r.find('counter')!;
    expect(c).toBeDefined();
    expect(c.kind).toBe('leap');
    expect(W.fighters[1].hp).toBe(100);
    expect(W.fighters[0].posture).toBeGreaterThanOrEqual(30);
  });

  it('back-dashing an overhead slam triggers the evade counter and a counter lunge', () => {
    const W = makeWorld(GREATSWORD, KATANA, 2.4);
    const r = new Rec();
    run(W, 40, (i) => (i === 0 ? btn(B.Block, B.Heavy) : idle()), (i) => (i === 28 ? btn(B.Dodge) : idle()), r);
    const c = r.find('counter')!;
    expect(c).toBeDefined();
    expect(c.kind).toBe('evade');
    expect(W.fighters[1].hp).toBe(100);
    // follow up with light: the special lunge
    const r2 = new Rec();
    run(W, 40, idle, (i) => (i === 2 ? btn(B.Light) : idle()), r2);
    const hit = r2.find('hit');
    expect(hit?.attack).toBe('k_lunge');
  });
});

describe('disarmed mode', () => {
  it('a disarmed fighter cannot block', () => {
    const W = makeWorld();
    const r = new Rec();
    W.fighters[1].armed = false;
    run(W, 30, tapAt(0, B.Light), () => btn(B.Block), r);
    expect(r.has('hit')).toBe(true);
    expect(W.fighters[1].hp).toBeCloseTo(94);
  });

  it('a timed block press while disarmed is a redirect counter', () => {
    const W = makeWorld();
    const r = new Rec();
    const [a, b] = W.fighters;
    b.armed = false;
    run(W, 20, tapAt(0, B.Light), tapAt(8, B.Block), r);
    const p = r.find('parry')!;
    expect(p.kind).toBe('redirect');
    expect(a.state).toBe('stunned');
    expect(a.posture).toBeCloseTo(35);
  });

  it('a redirect against a full-posture attacker disarms them', () => {
    const W = makeWorld();
    const r = new Rec();
    const [a, b] = W.fighters;
    b.armed = false;
    a.posture = POSTURE_MAX;
    run(W, 20, tapAt(0, B.Light), tapAt(8, B.Block), r);
    expect(a.armed).toBe(false);
  });

  it('a disarmed fighter can pick their weapon back up', () => {
    const W = makeWorld(KATANA, KATANA, 4);
    const [a, b] = W.fighters;
    a.posture = 100;
    a.disarm(b, 'parried');
    run(W, 120); // weapon lands, stagger ends
    const w = W.weaponOf(0)!;
    expect(w.grounded).toBe(true);
    a.pos = { x: w.pos.x, y: 0, z: w.pos.z };
    run(W, 30, tapAt(0, B.Interact));
    expect(a.armed).toBe(true);
    expect(W.weaponOf(0)).toBeNull();
  });

  it('disarmed fighters move faster and dodge farther', () => {
    const W = makeWorld(KATANA, KATANA, 6);
    const a = W.fighters[0];
    const start = a.pos.x;
    run(W, 30, (i) => (i === 0 ? move(1, 0, B.Dodge) : idle()));
    const armedDist = Math.abs(a.pos.x - start);
    const W2 = makeWorld(KATANA, KATANA, 6);
    const a2 = W2.fighters[0];
    a2.armed = false;
    const s2 = a2.pos.x;
    run(W2, 30, (i) => (i === 0 ? move(1, 0, B.Dodge) : idle()));
    const disDist = Math.abs(a2.pos.x - s2);
    expect(disDist).toBeGreaterThan(armedDist * 1.3);
  });
});
