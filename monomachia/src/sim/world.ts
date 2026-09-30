// The World owns both fighters, dropped weapons and projectiles, and resolves
// every clash between them once per frame.

import {
  ARENA_RADIUS,
  COUNTER_LUNGE_WINDOW,
  DISARMED_STAGGER,
  DISARMED_STAGGER_RESET,
  DT,
  EVADE_EXTRA_RECOVERY,
  EVADE_POSTURE,
  FIGHTER_RADIUS,
  FLASH_STUN,
  HIT_POSTURE_MULT,
  JUMP_CLEAR,
  LEAP_POSTURE,
  LEAP_STUN,
  PARRIER_RECOVERY,
  PARRY_POSTURE,
  PARRY_RECOIL,
  PARRY_RECOIL_GUARD_AFTER,
  REDIRECT_POSTURE,
  REDIRECT_STUN,
  STOMP_POSTURE,
  STOMP_STUN,
} from './constants';
import type { SimEvent } from './events';
import { Fighter, FighterConfig } from './fighter';
import { B, RawInput } from './input';
import { Vec3, dist2, fwd, norm2, v3 } from './math';
import { AttackDef, ULT_HITS, WeaponId } from './moves';
import { Rng } from './rng';
import type { OutcomeKind, WorldLike } from './worldTypes';

export class DroppedWeapon {
  grounded = false;
  spin: number;
  tumble = 0;
  yaw: number;
  restFrames = 0;
  constructor(
    public owner: number,
    public weaponId: WeaponId,
    public pos: Vec3,
    public vel: Vec3,
    rng: Rng,
  ) {
    this.spin = rng.range(10, 18) * (rng.chance(0.5) ? 1 : -1);
    this.yaw = rng.range(0, Math.PI * 2);
  }
}

export class SlashWave {
  s = 0;
  alive = true;
  resolved = false;
  constructor(
    public owner: Fighter,
    public kind: 'vertical' | 'horizontal',
    public ox: number,
    public oz: number,
    public dx: number,
    public dz: number,
  ) {}
}

interface HitCtx {
  chargeF: number;
  backstab: boolean;
}

export const WAVE_SPEED = 30;
export const WAVE_RANGE = 26;

export class World implements WorldLike {
  frame = 0;
  fighters: [Fighter, Fighter];
  weapons: DroppedWeapon[] = [];
  waves: SlashWave[] = [];
  events: SimEvent[] = [];
  hitstop = 0;
  slowmoFrames = 0;
  slowmoScale = 1;
  koResolved = false;
  rng: Rng;
  private scriptedQueue: { a: Fighter; b: Fighter; def: AttackDef; cb?: (res: OutcomeKind) => void }[] = [];

  constructor(p1: FighterConfig, p2: FighterConfig, seed = 1) {
    this.rng = new Rng(seed);
    const a = new Fighter(0, p1);
    const b = new Fighter(1, p2);
    a.opp = b;
    b.opp = a;
    a.world = this;
    b.world = this;
    this.fighters = [a, b];
    this.resetRound();
  }

  get timeScale() {
    return this.slowmoFrames > 0 ? this.slowmoScale : 1;
  }

  emit(e: SimEvent) {
    this.events.push(e);
  }

  drainEvents(): SimEvent[] {
    const e = this.events;
    this.events = [];
    return e;
  }

  resetRound() {
    this.fighters[0].resetForRound(0, -3.2, 0);
    this.fighters[1].resetForRound(0, 3.2, Math.PI);
    this.weapons = [];
    this.waves = [];
    this.scriptedQueue = [];
    this.hitstop = 0;
    this.slowmoFrames = 0;
    this.koResolved = false;
  }

  requestSlowmo(frames: number, scale: number) {
    this.slowmoFrames = frames;
    this.slowmoScale = scale;
  }

  // ------------------------------------------------------------------ step

  step(inputs: RawInput[]) {
    for (let i = 0; i < 2; i++) this.fighters[i].input.update(inputs[i], this.frame + 1);
    if (this.hitstop > 0) {
      this.hitstop--;
      return;
    }
    this.frame++;
    if (this.slowmoFrames > 0) this.slowmoFrames--;

    for (const f of this.fighters) f.update();
    this.flushScriptedHits();
    this.separate();
    this.resolveCombat();
    this.updateWaves();
    this.updateWeapons();
    this.clampArena();
    this.checkKO();
  }

  // ------------------------------------------------------------------ geometry

  inVolume(a: Fighter, b: Fighter, def: AttackDef) {
    const d = dist2(a.pos, b.pos);
    if (d - FIGHTER_RADIUS > def.range) return false;
    if (def.minRange && d < def.minRange) return false;
    if (def.arc >= 360) return true;
    const half = def.arc / 2 + (d < 1.3 ? 30 : 0);
    return a.angleTo(b.pos) <= half;
  }

  private separate() {
    const [a, b] = this.fighters;
    const skip = (f: Fighter) =>
      f.state === 'leap' || f.state === 'impaled' || f.state === 'ko' || f.state === 'stomp';
    if (skip(a) || skip(b)) return;
    if (Math.abs(a.pos.y - b.pos.y) > 1.0) return;
    const dx = b.pos.x - a.pos.x;
    const dz = b.pos.z - a.pos.z;
    const d = Math.hypot(dx, dz);
    const min = FIGHTER_RADIUS * 2;
    if (d >= min) return;
    const n = d > 1e-6 ? { x: dx / d, z: dz / d } : { x: 1, z: 0 };
    const push = (min - d) / 2;
    a.pos.x -= n.x * push;
    a.pos.z -= n.z * push;
    b.pos.x += n.x * push;
    b.pos.z += n.z * push;
  }

  private clampArena() {
    const max = ARENA_RADIUS - FIGHTER_RADIUS;
    for (const f of this.fighters) {
      const r = Math.hypot(f.pos.x, f.pos.z);
      if (r > max) {
        f.pos.x *= max / r;
        f.pos.z *= max / r;
      }
    }
  }

  // ------------------------------------------------------------------ combat

  private resolveCombat() {
    const outs: [Fighter, Fighter, AttackDef, OutcomeKind, HitCtx][] = [];
    for (const a of this.fighters) {
      if (a.state !== 'attack' || !a.atk) continue;
      const at = a.atk;
      const def = at.def;
      if (def.damage <= 0 && def.posture <= 0) continue;
      if (at.charging) continue;
      const f = at.frame;
      if (f <= def.startup || f > def.startup + def.active) continue;
      if (def.multiHit) {
        const interval = def.multiInterval ?? 3;
        if ((f - def.startup - 1) % interval !== 0 || at.hitsDone >= def.multiHit) continue;
      } else if (at.hitDone) continue;
      outs.push([a, a.opp, def, this.evaluate(a, a.opp, def, false), { chargeF: at.chargeFrac, backstab: at.backstab }]);
    }
    // decided simultaneously, applied in order: each carries its own context so a
    // trade is fair even though the first application interrupts the second attacker
    for (const [a, b, def, kind, ctx] of outs) this.apply(a, b, def, kind, false, ctx);
  }

  /** Decide what an attack does to its target this frame, without changing anything. */
  evaluate(a: Fighter, b: Fighter, def: AttackDef, scripted: boolean): OutcomeKind {
    if (b.state === 'ko' || b.state === 'intro' || b.state === 'victory') return 'miss';
    if (b.state === 'impaled' && !scripted) return 'miss';
    const d = dist2(a.pos, b.pos);
    const ang = a.angleTo(b.pos);

    // The three unblockable counters, each with a slightly generous shape.
    if (def.counter === 'thrust' && b.isForwardDodging() && d <= def.range + 1.2 && ang <= def.arc / 2 + 35) {
      return 'stomp';
    }
    if (def.counter === 'slam' && b.isBackDodging() && d <= def.range + 2.6 && ang <= def.arc / 2 + 40) {
      return 'evadeCounter';
    }
    if (
      def.counter === 'sweep' &&
      b.pos.y > JUMP_CLEAR &&
      b.state !== 'leap' &&
      d <= def.range + 0.8 &&
      ang <= def.arc / 2 + 20
    ) {
      return 'leap';
    }

    if (!scripted && !this.inVolume(a, b, def)) return 'miss';
    if (def.jumpable && b.pos.y > JUMP_CLEAR) return 'jumped';
    if (b.isFlashActive() && b.facingPoint(a.pos)) return 'flash';
    if (b.state === 'leap' || b.state === 'stomp') return 'evade';
    if (b.isInvulnerable() && !def.undodgeable) return 'evade';
    if (b.parryActive() && b.facingPoint(a.pos)) return b.armed ? 'parry' : 'redirect';
    if (b.armed && b.blocking && b.isGuardCapable() && b.facingPoint(a.pos)) {
      const chargeFull = !scripted && (a.atk?.chargeFrac ?? 0) >= 1;
      const power = !!def.power || def.kind === 'ultimate' || chargeFull;
      if (def.unblockable) return b.postureFull ? 'disarm' : 'hit';
      if (power && b.postureFull) return 'disarm';
      return 'block';
    }
    return 'hit';
  }

  /** Apply an outcome decided by evaluate(). */
  apply(a: Fighter, b: Fighter, def: AttackDef, kind: OutcomeKind, scripted: boolean, ctx?: HitCtx) {
    const atk = scripted ? null : a.atk;
    const contact = v3((a.pos.x + b.pos.x) / 2, 1.25, (a.pos.z + b.pos.z) / 2);
    const markDone = () => {
      if (!atk) return;
      if (def.multiHit) atk.hitsDone++;
      else atk.hitDone = true;
    };
    const chargeF = ctx?.chargeF ?? atk?.chargeFrac ?? 0;

    switch (kind) {
      case 'miss':
        return;
      case 'jumped':
        markDone();
        return;
      case 'evade':
        if (atk && !atk.evadedEmitted) {
          atk.evadedEmitted = true;
          this.emit({ t: 'evade', f: b.id, attacker: a.id });
        }
        return;

      case 'parry':
      case 'flash':
      case 'redirect': {
        markDone();
        const wasFull = a.postureFull;
        const timing = this.frame - b.blockPressFrame;
        this.emit({ t: 'parry', parrier: b.id, attacker: a.id, pos: contact, kind, timing, window: b.parryWindowAtPress });
        b.stats.parries++;
        if (kind !== 'parry') b.stats.counters++;
        b.setState('parryAnim', PARRIER_RECOVERY);
        b.blocking = b.armed && b.input.isHeld(B.Block);
        b.blockPressFrame = -99999; // one press, one parry
        const melee = !scripted || def.id === 'u_impale';
        a.releaseIfImpaling();
        if (wasFull && a.armed) {
          a.disarm(b, kind === 'redirect' ? 'redirect' : 'parried');
          this.hitstop = 14;
          return;
        }
        if (wasFull && !a.armed) {
          // already bare-handed: a broken posture dazes instead
          a.enterStun(DISARMED_STAGGER, 'stagger');
          a.posture = DISARMED_STAGGER_RESET;
          this.emit({ t: 'stagger', f: a.id });
          this.hitstop = 10;
          return;
        }
        a.addPosture(kind === 'redirect' ? REDIRECT_POSTURE : PARRY_POSTURE);
        if (melee) {
          if (kind === 'parry') a.enterRecoil(PARRY_RECOIL, PARRY_RECOIL_GUARD_AFTER);
          else a.enterStun(kind === 'flash' ? FLASH_STUN : REDIRECT_STUN);
          a.knock(b.pos.x, b.pos.z, 0.35, 8);
        }
        this.hitstop = kind === 'parry' ? 8 : 10;
        return;
      }

      case 'stomp':
        a.releaseIfImpaling();
        a.enterStun(STOMP_STUN);
        a.addPosture(STOMP_POSTURE);
        b.beginStomp(a);
        b.stats.counters++;
        this.emit({ t: 'counter', kind: 'stomp', by: b.id, on: a.id, pos: v3(a.pos.x, 0.2, a.pos.z) });
        this.hitstop = 10;
        return;

      case 'leap':
        a.releaseIfImpaling();
        a.enterStun(LEAP_STUN);
        a.addPosture(LEAP_POSTURE);
        b.beginLeap(a);
        b.stats.counters++;
        this.emit({ t: 'counter', kind: 'leap', by: b.id, on: a.id, pos: v3(a.pos.x, 1.7, a.pos.z) });
        this.hitstop = 6;
        return;

      case 'evadeCounter':
        markDone();
        if (atk) atk.extraRecovery += EVADE_EXTRA_RECOVERY;
        a.addPosture(EVADE_POSTURE);
        b.counterLungeUntil = this.frame + COUNTER_LUNGE_WINDOW;
        b.stats.counters++;
        this.emit({ t: 'counter', kind: 'evade', by: b.id, on: a.id, pos: v3(a.pos.x, 0.1, a.pos.z) });
        this.emit({ t: 'counterReady', f: b.id });
        this.hitstop = 5;
        return;

      case 'block': {
        markDone();
        const chargeMult = 1 + 0.8 * chargeF;
        const mult = def.guardCrush ?? b.weapon.blockMitigation;
        b.addPosture(def.posture * mult * chargeMult);
        b.setState('blockstun', (def.blockstun ?? 12) + Math.round(8 * chargeF));
        b.blocking = true;
        b.knock(a.pos.x, a.pos.z, def.knockback * 0.45 * chargeMult, 10);
        b.stats.blocks++;
        this.hitstop = Math.max(3, (def.hitstop ?? 4) - 2);
        this.emit({
          t: 'block',
          attacker: a.id,
          target: b.id,
          attack: def.id,
          posture: def.posture * mult * chargeMult,
          pos: contact,
          heavy: def.kind !== 'light',
        });
        return;
      }

      case 'disarm':
        markDone();
        b.disarm(a, 'blocked');
        this.hitstop = 14;
        return;

      case 'hit': {
        markDone();
        let dmg = def.damage * (1 + 0.8 * chargeF);
        const backstab = !!(ctx?.backstab ?? atk?.backstab);
        if (backstab) dmg *= 1.6;
        const post = def.posture * HIT_POSTURE_MULT * (1 + 0.8 * chargeF);
        b.hp = Math.max(0, b.hp - dmg);
        b.addPosture(post);
        a.stats.hitsLanded++;
        a.stats.damageDealt += dmg;
        this.emit({
          t: 'hit',
          attacker: a.id,
          target: b.id,
          attack: def.id,
          damage: dmg,
          posture: post,
          pos: contact,
          heavy: def.kind !== 'light',
          sound: def.sound ?? 'blade',
          backstab,
        });
        b.releaseIfImpaling();
        if (b.hp <= 0) {
          b.toKO();
          b.knock(a.pos.x, a.pos.z, Math.max(1.5, def.knockback * 1.5), 20);
        } else if (!b.armed && b.postureFull && b.state !== 'stagger') {
          b.enterStun(DISARMED_STAGGER, 'stagger');
          b.posture = DISARMED_STAGGER_RESET;
          b.knock(a.pos.x, a.pos.z, def.knockback, 12);
          this.emit({ t: 'stagger', f: b.id });
        } else if (b.state !== 'impaled') {
          b.enterHitstun((def.hitstun ?? 20) + Math.round(12 * chargeF));
          b.knock(a.pos.x, a.pos.z, def.knockback * (1 + 1.2 * chargeF), 12);
        }
        this.hitstop = (def.hitstop ?? 4) + Math.round(4 * chargeF);
        return;
      }
    }
  }

  resolveScriptedHit(a: Fighter, b: Fighter, def: AttackDef): OutcomeKind {
    const kind = this.evaluate(a, b, def, true);
    this.apply(a, b, def, kind, true);
    return kind;
  }

  /**
   * Scripted (ultimate) hits are queued and resolved after BOTH fighters have
   * read this frame's input, so neither player gets a one-frame advantage.
   */
  queueScriptedHit(a: Fighter, b: Fighter, def: AttackDef, cb?: (res: OutcomeKind) => void) {
    this.scriptedQueue.push({ a, b, def, cb });
  }

  private flushScriptedHits() {
    const q = this.scriptedQueue;
    this.scriptedQueue = [];
    for (const h of q) {
      const res = this.koResolved ? 'miss' : this.resolveScriptedHit(h.a, h.b, h.def);
      h.cb?.(res);
    }
  }

  // ------------------------------------------------------------------ katana ultimate wave

  spawnWave(owner: Fighter, kind: 'vertical' | 'horizontal') {
    const d = fwd(owner.yaw);
    this.waves.push(new SlashWave(owner, kind, owner.pos.x + d.x * 0.6, owner.pos.z + d.z * 0.6, d.x, d.z));
    this.emit({ t: 'ultWave', f: owner.id, kind, pos: v3(owner.pos.x, 1, owner.pos.z), yaw: owner.yaw });
  }

  private updateWaves() {
    if (this.koResolved) {
      this.waves = [];
      return;
    }
    for (const w of this.waves) {
      const prev = w.s;
      w.s += WAVE_SPEED * DT;
      const b = w.owner.opp;
      if (!w.resolved) {
        const rx = b.pos.x - w.ox;
        const rz = b.pos.z - w.oz;
        const along = rx * w.dx + rz * w.dz;
        const lateral = Math.abs(rx * w.dz - rz * w.dx);
        if (along > prev - 0.4 && along <= w.s + 0.3) {
          const inLane = w.kind === 'horizontal' || lateral <= 0.95;
          if (inLane) {
            const def = w.kind === 'vertical' ? ULT_HITS.u_moon_v : ULT_HITS.u_moon_h;
            const res = this.resolveScriptedHit(w.owner, b, def);
            if (res !== 'miss' && res !== 'evade') w.resolved = true;
            if (res === 'parry' || res === 'flash' || res === 'redirect') w.alive = false;
          }
        }
      }
      if (w.s > WAVE_RANGE) w.alive = false;
    }
    this.waves = this.waves.filter((w) => w.alive);
  }

  // ------------------------------------------------------------------ dropped weapons

  spawnDroppedWeapon(victim: Fighter, by: Fighter) {
    const away = norm2(victim.pos.x - by.pos.x, victim.pos.z - by.pos.z);
    const ang = Math.atan2(away.x, away.z) + this.rng.range(-0.7, 0.7);
    const sp = this.rng.range(5.0, 7.0);
    this.weapons = this.weapons.filter((w) => w.owner !== victim.id);
    this.weapons.push(
      new DroppedWeapon(
        victim.id,
        victim.weapon.id,
        v3(victim.pos.x, 1.3, victim.pos.z),
        v3(Math.sin(ang) * sp, 5.5, Math.cos(ang) * sp),
        this.rng,
      ),
    );
  }

  weaponOf(owner: number) {
    return this.weapons.find((w) => w.owner === owner) ?? null;
  }

  removeDroppedWeapon(owner: number) {
    this.weapons = this.weapons.filter((w) => w.owner !== owner);
  }

  private updateWeapons() {
    const maxR = ARENA_RADIUS - 0.8;
    for (const w of this.weapons) {
      if (w.grounded) continue;
      w.vel.y -= 20 * DT;
      w.pos.x += w.vel.x * DT;
      w.pos.y += w.vel.y * DT;
      w.pos.z += w.vel.z * DT;
      w.tumble += w.spin * DT;
      const r = Math.hypot(w.pos.x, w.pos.z);
      if (r > maxR) {
        const nx = w.pos.x / r;
        const nz = w.pos.z / r;
        const vn = w.vel.x * nx + w.vel.z * nz;
        if (vn > 0) {
          w.vel.x -= 1.6 * vn * nx;
          w.vel.z -= 1.6 * vn * nz;
        }
        w.pos.x = nx * maxR;
        w.pos.z = nz * maxR;
      }
      if (w.pos.y <= 0.06) {
        w.pos.y = 0.06;
        if (w.vel.y < -2.5) {
          this.emit({ t: 'weaponBounce', owner: w.owner, pos: v3(w.pos.x, 0.1, w.pos.z), speed: -w.vel.y });
          w.vel.y = -w.vel.y * 0.3;
          w.spin *= 0.5;
        } else {
          w.vel.y = 0;
        }
        w.vel.x *= 0.86;
        w.vel.z *= 0.86;
        w.spin *= 0.8;
        if (Math.hypot(w.vel.x, w.vel.z) < 0.25 && Math.abs(w.vel.y) < 0.01) {
          w.grounded = true;
          w.tumble = Math.round(w.tumble / Math.PI) * Math.PI; // lie flat
        }
      }
    }
  }

  // ------------------------------------------------------------------ round end

  private checkKO() {
    if (this.koResolved) return;
    const [f0, f1] = this.fighters;
    const d0 = f0.hp <= 0;
    const d1 = f1.hp <= 0;
    if (!d0 && !d1) return;
    this.koResolved = true;
    if (d0 && f0.state !== 'ko') f0.toKO();
    if (d1 && f1.state !== 'ko') f1.toKO();
    const winner = d0 && d1 ? -1 : d0 ? 1 : 0;
    this.emit({ t: 'ko', loser: d0 && d1 ? -1 : d0 ? 0 : 1, winner });
    this.requestSlowmo(50, 0.3);
  }
}
