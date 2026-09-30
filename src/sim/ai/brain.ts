// Computer opponent. It plays through a virtual controller (RawInput), so it is
// bound by exactly the same rules, timings and cooldowns as a human player.

import { FIGHTER_RADIUS, PICKUP_RANGE } from '../constants';
import type { Fighter } from '../fighter';
import { B, RawInput } from '../input';
import { dist2, norm2 } from '../math';
import { AttackDef, WeaponDef } from '../moves';
import { Rng } from '../rng';
import type { World } from '../world';

export type Difficulty = 'easy' | 'normal' | 'hard';

export interface AIParams {
  /** frames before the AI notices a new attack */
  reaction: number;
  reactionJitter: number;
  parry: number;
  block: number;
  counter: number;
  dodge: number;
  aggression: number;
  /** +/- frames of timing error on parries and counters */
  timingError: number;
  useUlt: number;
  /** chance to raise a pre-emptive guard when inside the opponent's reach */
  guard: number;
}

export const DIFFICULTY: Record<Difficulty, AIParams> = {
  easy: { reaction: 27, reactionJitter: 8, parry: 0.08, block: 0.35, counter: 0.1, dodge: 0.15, aggression: 0.35, timingError: 5, useUlt: 0.5, guard: 0.3 },
  normal: { reaction: 18, reactionJitter: 6, parry: 0.3, block: 0.45, counter: 0.35, dodge: 0.2, aggression: 0.55, timingError: 3, useUlt: 0.8, guard: 0.55 },
  hard: { reaction: 11, reactionJitter: 4, parry: 0.55, block: 0.35, counter: 0.6, dodge: 0.25, aggression: 0.72, timingError: 2, useUlt: 1, guard: 0.7 },
};

interface Tap {
  btn: B;
  from: number;
  to: number;
  mx?: number;
  my?: number;
}

type Plan = 'none' | 'parry' | 'block' | 'dodge' | 'counter' | 'flash' | 'evade';

export class AIBrain {
  rng: Rng;
  private taps: Tap[] = [];
  private holdMask = 0;
  private moveX = 0;
  private moveY = 0;

  private seenAtk: object | null = null;
  private seenWave: object | null = null;
  private seenUlt = false;
  private reactAt = -1;
  private plan: Plan = 'none';
  private planUntil = -1;

  private nextThink = 0;
  private attackCooldownUntil = 0;
  private comboLeft = 0;
  private comboBtn: B = B.Light;
  private nextComboPress = 0;
  private chargeUntil = -1;
  private strafe = 1;
  private strafeUntil = 0;
  private recoverPosture = false;
  private lastOppBlockingFrames = 0;
  private spacingBias = 0;
  private guardUntil = 0;
  private guardRoll = 0;

  constructor(public me: Fighter, public params: AIParams, seed = 99) {
    this.rng = new Rng(seed);
  }

  private get W(): World {
    return this.me.world as unknown as World;
  }

  // ------------------------------------------------------------------ output helpers

  private tap(btn: B, at: number, len = 2, mx?: number, my?: number) {
    this.taps.push({ btn, from: at, to: at + len - 1, mx, my });
  }

  private output(frame: number): RawInput {
    let buttons = this.holdMask;
    let mx = this.moveX;
    let my = this.moveY;
    for (const t of this.taps) {
      if (frame >= t.from && frame <= t.to) {
        buttons |= 1 << t.btn;
        if (t.mx !== undefined) mx = t.mx;
        if (t.my !== undefined) my = t.my;
      }
    }
    this.taps = this.taps.filter((t) => t.to >= frame);
    return { mx, my, buttons };
  }

  /** Convert a desired world direction into opponent-relative stick axes. */
  private stickToward(x: number, z: number) {
    const me = this.me;
    const to = norm2(me.opp.pos.x - me.pos.x, me.opp.pos.z - me.pos.z);
    const d = norm2(x - me.pos.x, z - me.pos.z);
    const rx = -to.z;
    const rz = to.x;
    return { mx: d.x * rx + d.z * rz, my: d.x * to.x + d.z * to.z };
  }

  // ------------------------------------------------------------------ main

  think(): RawInput {
    const me = this.me;
    const W = this.W;
    const frame = W.frame + 1; // the frame this input will be read on
    const opp = me.opp;

    if (me.state === 'intro' || me.state === 'victory' || me.state === 'ko') {
      this.reset();
      return this.output(frame);
    }

    this.perceive(frame);

    if (this.plan !== 'none' && frame > this.planUntil) {
      this.plan = 'none';
      this.holdMask &= ~(1 << B.Block);
    }

    // Plans (defence) take priority over everything else.
    if (this.plan !== 'none') {
      if (this.plan === 'block') {
        this.holdMask |= 1 << B.Block;
        this.moveX = this.moveY = 0;
      }
      return this.output(frame);
    }

    // Charging a heavy.
    if (this.chargeUntil > 0) {
      if (frame < this.chargeUntil && me.state === 'attack') {
        this.holdMask |= 1 << B.Heavy;
        return this.output(frame);
      }
      this.chargeUntil = -1;
      this.holdMask &= ~(1 << B.Heavy);
    }

    // Continue a combo string.
    if (this.comboLeft > 0 && me.state === 'attack') {
      if (frame >= this.nextComboPress) {
        this.tap(this.comboBtn, frame, 2);
        this.comboLeft--;
        this.nextComboPress = frame + 8;
      }
      return this.output(frame);
    }
    if (me.state !== 'attack') this.comboLeft = 0;

    if (frame < this.nextThink) return this.output(frame);
    this.nextThink = frame + 3;

    const d = dist2(me.pos, opp.pos);
    this.holdMask &= ~(1 << B.Heavy);

    // Ultimate.
    if (me.canUlt() && this.rng.chance(this.params.useUlt * 0.2) && this.ultMakesSense(d)) {
      this.holdMask = 0;
      if (me.weapon.ultimate === 'moonsplitter' && me.armed) {
        // choose vertical or horizontal by tilting during the sheathe
        const horiz = this.rng.chance(0.5);
        this.tap(B.Ultimate, frame, 2);
        this.moveX = horiz ? 1 : 0;
        this.moveY = horiz ? 0 : 1;
        this.nextThink = frame + 36;
        return this.output(frame);
      }
      this.tap(B.Ultimate, frame, 2);
      if (!me.armed) {
        // Recall when the weapon is far, otherwise the posture blow when close
        const w = W.weaponOf(me.id);
        const choice = w && d > 2.5 ? B.Light : B.Heavy;
        this.tap(choice, frame + 6, 2);
      } else if (me.weapon.ultimate === 'impaler') {
        for (let k = 50; k < 90; k += 4) this.tap(B.Heavy, frame + k, 2);
      }
      this.nextThink = frame + 30;
      return this.output(frame);
    }

    if (!me.armed) return this.thinkDisarmed(frame, d);
    if (!opp.armed && W.weaponOf(opp.id)) return this.thinkGuardWeapon(frame, d);
    return this.thinkNeutral(frame, d);
  }

  private reset() {
    this.taps = [];
    this.holdMask = 0;
    this.moveX = this.moveY = 0;
    this.plan = 'none';
    this.comboLeft = 0;
    this.chargeUntil = -1;
    this.seenAtk = null;
    this.seenUlt = false;
  }

  private ultMakesSense(d: number) {
    const me = this.me;
    const opp = me.opp;
    if (opp.state === 'ko' || opp.isInvulnerable()) return false;
    if (!me.armed) return true;
    switch (me.weapon.ultimate) {
      case 'moonsplitter':
        return d > 2.5 && d < 14;
      case 'impaler':
        return d > 2.5 && d < 12 && opp.state !== 'dodge';
      case 'tempest':
        return d < 10;
      default:
        return true;
    }
  }

  // ------------------------------------------------------------------ perception & defence

  private perceive(frame: number) {
    const me = this.me;
    const opp = me.opp;
    const P = this.params;

    // Incoming katana wave.
    for (const w of this.W.waves) {
      if (w.owner === opp && w !== this.seenWave) {
        this.seenWave = w;
        const along = (me.pos.x - w.ox) * w.dx + (me.pos.z - w.oz) * w.dz;
        const arrive = frame + Math.max(0, Math.round(((along - w.s) / 30) * 60));
        if (this.rng.chance(P.counter + 0.15)) {
          if (w.kind === 'horizontal') this.tap(B.Jump, Math.max(frame, arrive - 8), 2);
          else this.tap(B.Dodge, Math.max(frame, arrive - 6), 2, 1, 0);
          this.setPlan('evade', arrive + 6);
        }
      }
    }

    // Opponent ultimates that are dodged rather than parried.
    if (opp.state === 'ult' && opp.ult && !this.seenUlt) {
      if (opp.ult.kind === 'impaler' && opp.ult.phase === 'dash') {
        this.seenUlt = true;
        if (this.rng.chance(P.dodge + P.counter * 0.5)) {
          this.tap(B.Dodge, frame + Math.round(P.reaction / 3), 2, this.rng.chance(0.5) ? 1 : -1, 0);
          this.setPlan('evade', frame + 20);
        }
      }
    }
    if (opp.state !== 'ult') this.seenUlt = false;

    if (opp.state !== 'attack' || !opp.atk) return;
    const atk = opp.atk;
    if (atk !== this.seenAtk) {
      this.seenAtk = atk;
      this.reactAt = frame + Math.max(1, Math.round(P.reaction + this.rng.range(-P.reactionJitter, P.reactionJitter)));
    }
    if (this.reactAt < 0 || frame < this.reactAt || atk.charging) return;
    this.reactAt = -1;
    this.respondTo(atk.def, atk.frame, frame);
  }

  private setPlan(p: Plan, until: number) {
    this.plan = p;
    this.planUntil = until;
    this.comboLeft = 0;
    this.chargeUntil = -1;
    this.holdMask &= ~(1 << B.Heavy);
  }

  private respondTo(def: AttackDef, atkFrame: number, frame: number) {
    const me = this.me;
    const opp = me.opp;
    const P = this.params;
    if (def.damage <= 0) return; // stances
    const impact = frame + (def.startup + 1 - atkFrame);
    if (impact < frame) return; // too late
    const d = dist2(me.pos, opp.pos);
    const reach = def.range + FIGHTER_RADIUS + (def.lunge ?? 0) + 0.6;
    if (d > reach && !def.counter) return;
    if (me.state === 'attack' || me.state === 'hitstun' || me.state === 'stunned') return;

    const err = () => this.rng.int(-P.timingError, P.timingError);
    const armed = me.armed;
    const window = me.moveset.parryWindow;
    const parryTap = () => {
      const k = Math.max(0, Math.min(window - 1, this.rng.int(1, window - 2) + err()));
      this.holdMask &= ~(1 << B.Block);
      this.tap(B.Block, Math.max(frame, impact - k), 3);
      this.setPlan('parry', impact + 4);
    };

    if (def.counter) {
      if (this.rng.chance(P.counter)) {
        if (def.counter === 'thrust') {
          this.tap(B.Dodge, Math.max(frame, impact - this.rng.int(3, 9) + err()), 2, 0, 1);
        } else if (def.counter === 'sweep') {
          this.tap(B.Jump, Math.max(frame, impact - this.rng.int(7, 13) + err()), 2);
        } else {
          this.tap(B.Dodge, Math.max(frame, impact - this.rng.int(2, 8) + err()), 2, 0, 0);
        }
        this.setPlan('counter', impact + 14);
        return;
      }
      if (this.rng.chance(P.parry * 0.6)) return parryTap();
      if (this.rng.chance(P.dodge + 0.25)) {
        this.tap(B.Dodge, Math.max(frame, impact - 16), 2, 0, -1);
        this.setPlan('dodge', impact + 10);
      }
      return;
    }

    // Katana Flash stance, if equipped, as an occasional answer to heavies.
    if (armed && me.abilities.includes('k_flash') && def.kind === 'heavy' && this.rng.chance(P.parry * 0.5)) {
      const slot = me.abilities[0] === 'k_flash' ? B.Light : B.Heavy;
      const at = Math.max(frame, impact - this.rng.int(4, 14));
      this.tap(B.Block, at, 3);
      this.tap(slot, at + 1, 2);
      this.setPlan('flash', impact + 6);
      return;
    }

    const parryChance = opp.postureFull && armed ? Math.min(0.9, P.parry + 0.25) : P.parry;
    if (this.rng.chance(parryChance)) return parryTap();
    if (armed && this.rng.chance(P.block / (1 - P.parry))) {
      this.holdMask |= 1 << B.Block;
      this.setPlan('block', impact + (def.active ?? 3) + 4);
      return;
    }
    if (this.rng.chance(P.dodge * (armed ? 1 : 2.5))) {
      const side = this.rng.chance(0.5) ? 1 : -1;
      const back = this.rng.chance(0.4);
      this.tap(B.Dodge, Math.max(frame, impact - this.rng.int(3, 8)), 2, back ? 0 : side, back ? -1 : 0);
      this.setPlan('dodge', impact + 8);
    }
  }

  // ------------------------------------------------------------------ neutral game

  private thinkNeutral(frame: number, d: number) {
    const me = this.me;
    const opp = me.opp;
    const P = this.params;
    const w = me.moveset;
    const reach = w.reach + FIGHTER_RADIUS;

    // Posture management: back off and hold block to drain when the meter runs high.
    if (me.posture > 62 && !this.recoverPosture && this.rng.chance(0.3)) this.recoverPosture = true;
    if (this.recoverPosture) {
      if (me.posture < 25 || (opp.state === 'attack' && d < reach + 1)) this.recoverPosture = false;
      else {
        this.holdMask |= 1 << B.Block;
        this.moveX = 0;
        this.moveY = d < 3.5 ? -0.8 : 0;
        return this.output(frame);
      }
    }
    this.holdMask &= ~(1 << B.Block);

    // Track how much the opponent turtles.
    this.lastOppBlockingFrames = opp.blocking ? this.lastOppBlockingFrames + 3 : Math.max(0, this.lastOppBlockingFrames - 2);

    const punish = ['recoil', 'stunned', 'stagger', 'disarmStagger', 'pickup'].includes(opp.state) ||
      (opp.state === 'attack' && opp.attackPhase() === 'recovery' && opp.atk!.frame > 0);
    const canAct = me.state === 'free' || me.state === 'step' || me.state === 'parryAnim' || me.state === 'land';

    // With a full meter, a parried attack would disarm us: only attack into openings.
    const risky = me.postureFull || (me.posture > 80 && !punish);
    const oppSwinging = opp.state === 'attack' && opp.attackPhase() !== 'recovery';
    if (canAct && frame >= this.attackCooldownUntil && !(risky && !punish && this.rng.chance(0.75)) && !(oppSwinging && !punish && this.rng.chance(0.7))) {
      // Counter-lunge window after an evade counter
      if (frame <= me.counterLungeUntil + 1) {
        this.tap(B.Light, frame, 2);
        this.attackCooldownUntil = frame + 20;
        return this.output(frame);
      }
      if (punish && d < reach + 0.9) {
        this.startCombo(frame, this.rng.int(2, 3), this.rng.chance(0.35));
        this.attackCooldownUntil = frame + 12;
        return this.output(frame);
      }
      if (d < reach + 0.25 && this.rng.chance(0.08 + P.aggression * 0.25)) {
        this.pickAttack(frame, d);
        return this.output(frame);
      }
      // sprint attack from mid range
      if (d > 4.5 && d < 7.5 && this.rng.chance(0.03 * P.aggression)) {
        this.holdMask |= 1 << B.Sprint;
        this.moveX = 0;
        this.moveY = 1;
        this.tap(this.rng.chance(0.6) ? B.Light : B.Heavy, frame + 16, 2);
        this.attackCooldownUntil = frame + 50;
        this.nextThink = frame + 18;
        return this.output(frame);
      }
    }
    this.holdMask &= ~(1 << B.Sprint);

    // Pre-emptive guard inside the opponent's reach (light attacks are too fast to react to).
    const threat = opp.moveset.reach + FIGHTER_RADIUS + 0.9;
    if (me.armed && d < threat && opp.state !== 'ko') {
      if (frame > this.guardUntil && frame > this.guardRoll) {
        const want = P.guard + (risky ? 0.25 : 0);
        if (this.rng.chance(want)) this.guardUntil = frame + this.rng.int(24, 72);
        this.guardRoll = frame + this.rng.int(18, 40);
      }
    } else this.guardUntil = 0;
    if (frame < this.guardUntil) this.holdMask |= 1 << B.Block;

    // Footsies: keep preferred distance and circle.
    if (frame > this.strafeUntil) {
      this.strafe = this.rng.chance(0.5) ? 1 : -1;
      if (this.rng.chance(0.25)) this.strafe = 0;
      this.strafeUntil = frame + this.rng.int(40, 110);
      this.spacingBias = this.rng.range(-0.4, 0.6);
    }
    const want = reach - 0.1 + this.spacingBias - P.aggression * 0.5;
    let my = 0;
    if (d > want + 0.4) my = 1;
    else if (d < want - 0.5) my = -0.8;
    if (d > 8) this.holdMask |= 1 << B.Sprint;
    this.moveX = this.strafe * 0.8;
    this.moveY = my;
    return this.output(frame);
  }

  private startCombo(frame: number, length: number, finishHeavy: boolean) {
    this.tap(B.Light, frame, 2);
    this.comboLeft = length - 1;
    this.comboBtn = B.Light;
    this.nextComboPress = frame + 8;
    if (finishHeavy && length > 1) {
      // replace the last press with a heavy
      this.comboLeft = length - 2;
      this.tap(B.Heavy, frame + 8 * (length - 1), 2);
    }
    this.moveX = this.moveY = 0;
  }

  private pickAttack(frame: number, d: number) {
    const me = this.me;
    const opp = me.opp;
    const P = this.params;
    const w: WeaponDef = me.moveset;
    const turtling = this.lastOppBlockingFrames > 30 || opp.blocking;
    const abilities = me.armed ? me.abilities : ['', ''];
    const unblockSlot = abilities.findIndex((id) => id && w.moves[id]?.unblockable);
    const r = this.rng.next();
    this.moveX = this.moveY = 0;
    this.holdMask &= ~(1 << B.Block);
    this.guardUntil = 0;
    const breakChance = opp.postureFull ? 0.7 : turtling ? 0.45 : 0.12;

    if (unblockSlot >= 0 && r < breakChance) {
      this.tap(B.Block, frame, 3);
      this.tap(unblockSlot === 0 ? B.Light : B.Heavy, frame + 1, 2);
      this.attackCooldownUntil = frame + 40;
      return;
    }
    const crushSlot = abilities.indexOf('g_crush');
    if (crushSlot >= 0 && turtling && r < 0.6) {
      this.tap(B.Block, frame, 3);
      this.tap(crushSlot === 0 ? B.Light : B.Heavy, frame + 1, 2);
      this.attackCooldownUntil = frame + 30;
      return;
    }
    if (r < 0.55) {
      this.startCombo(frame, this.rng.int(1, 3), this.rng.chance(0.25));
      this.attackCooldownUntil = frame + 24 + Math.round((1 - P.aggression) * 40);
    } else if (r < 0.8) {
      this.tap(B.Heavy, frame, 2);
      if (this.rng.chance(0.3)) this.tap(B.Heavy, frame + 30, 2);
      this.attackCooldownUntil = frame + 40 + Math.round((1 - P.aggression) * 40);
    } else if (r < 0.88 && me.armed) {
      // charged heavy
      this.holdMask |= 1 << B.Heavy;
      this.chargeUntil = frame + this.rng.int(30, 160);
      this.attackCooldownUntil = frame + 90;
    } else {
      // dodge then attack
      const side = this.rng.chance(0.5) ? 1 : -1;
      this.tap(B.Dodge, frame, 2, side, 0.3);
      this.tap(this.rng.chance(0.6) ? B.Light : B.Heavy, frame + 14, 2);
      this.attackCooldownUntil = frame + 45;
    }
    void d;
  }

  // ------------------------------------------------------------------ disarm situations

  private thinkDisarmed(frame: number, d: number) {
    const me = this.me;
    const opp = me.opp;
    const W = this.W;
    const wpn = W.weaponOf(me.id);
    if (wpn && wpn.grounded) {
      const myD = dist2(me.pos, wpn.pos);
      const oppD = dist2(opp.pos, wpn.pos);
      if (myD <= PICKUP_RANGE - 0.15) {
        if (me.state === 'free' || me.state === 'step') {
          this.moveX = this.moveY = 0;
          this.tap(B.Interact, frame, 2);
          this.nextThink = frame + 10;
        }
        return this.output(frame);
      }
      // go for it if we are not badly blocked
      if (myD < oppD + 2.5 || opp.state === 'stunned' || opp.state === 'recoil' || this.rng.chance(0.3)) {
        const s = this.stickToward(wpn.pos.x, wpn.pos.z);
        this.moveX = s.mx;
        this.moveY = s.my;
        if (myD > 4) this.holdMask |= 1 << B.Sprint;
        else this.holdMask &= ~(1 << B.Sprint);
        // hop around the guard occasionally
        if (oppD < myD && d < 2.2 && this.rng.chance(0.08)) {
          this.tap(B.Dodge, frame, 2, s.mx > 0 ? 1 : -1, 0.2);
        }
        return this.output(frame);
      }
    }
    this.holdMask &= ~(1 << B.Sprint);
    // Brawl.
    return this.thinkNeutral(frame, d);
  }

  private thinkGuardWeapon(frame: number, d: number) {
    const me = this.me;
    const opp = me.opp;
    const wpn = this.W.weaponOf(opp.id)!;
    // stand between the opponent and their weapon, and punish attempts
    const gx = wpn.pos.x + (opp.pos.x - wpn.pos.x) * 0.35;
    const gz = wpn.pos.z + (opp.pos.z - wpn.pos.z) * 0.35;
    const toGuard = Math.hypot(gx - me.pos.x, gz - me.pos.z);
    if (opp.state === 'pickup' && d < me.moveset.reach + 1.5) {
      this.startCombo(frame, 3, true);
      return this.output(frame);
    }
    if (toGuard > 1.0 && d > 2.2) {
      const s = this.stickToward(gx, gz);
      this.moveX = s.mx;
      this.moveY = s.my;
      this.holdMask &= ~(1 << B.Block);
      return this.output(frame);
    }
    return this.thinkNeutral(frame, d);
  }
}
