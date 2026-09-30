// A fighter: position, health, posture, and a frame-by-frame state machine.
// Pure simulation — no rendering code — so it can be unit tested.

import {
  CHARGE_MAX,
  CHARGE_MIN,
  CHORD_FRAMES,
  DISARMED_MULT,
  DISARMED_POSTURE_DELAY,
  DISARMED_POSTURE_RECOVER,
  DISARM_STAGGER,
  DT,
  FIGHTER_RADIUS,
  GRAVITY,
  GUARD_HALF_ANGLE,
  HP_MAX,
  MOVE,
  PARRY_MIN_WINDOW,
  PARRY_SPAM_PENALTY,
  PARRY_SPAM_WINDOW,
  PICKUP_ATTACH_FRAME,
  PICKUP_FRAMES,
  PICKUP_RANGE,
  POSTURE_MAX,
  POSTURE_RECOVER_DELAY,
  POSTURE_RECOVER_HP_FLOOR,
  POSTURE_RECOVER_MOVE,
  POSTURE_RECOVER_STAND,
  ULT_CHOICE_FRAMES,
  ULT_HP_THRESHOLD,
} from './constants';
import { B, InputTracker, dirVector } from './input';
import {
  DEG,
  Vec3,
  angleBetween,
  clamp,
  dist2,
  easeOutCubic,
  fwd,
  norm2,
  turnToward,
  v3,
  wrapAngle,
  yawTo,
} from './math';
import {
  AttackDef,
  COUNTER_LUNGE,
  FISTS,
  ULT_HITS,
  WeaponDef,
  getMove,
} from './moves';
import type { WorldLike } from './worldTypes';

export type FState =
  | 'intro'
  | 'free'
  | 'step'
  | 'dodge'
  | 'backstep'
  | 'jump'
  | 'land'
  | 'attack'
  | 'blockstun'
  | 'hitstun'
  | 'recoil'
  | 'parryAnim'
  | 'stunned'
  | 'disarmStagger'
  | 'stagger'
  | 'pickup'
  | 'stomp'
  | 'leap'
  | 'ult'
  | 'ultChoice'
  | 'recall'
  | 'impaled'
  | 'ko'
  | 'victory';

export interface AttackState {
  def: AttackDef;
  frame: number;
  hitDone: boolean;
  hitsDone: number;
  charging: boolean;
  chargeFrames: number;
  chargeFrac: number;
  queued: string | null;
  lungeTotal: number;
  extraRecovery: number;
  backstab: boolean;
  startedBy: B | null;
  evadedEmitted: boolean;
  whiffEmitted: boolean;
  // shadow step path
  pathFrom?: { ang: number; r: number };
  pathTo?: { ang: number; r: number };
}

export interface DodgeState {
  dirX: number;
  dirZ: number;
  dist: number;
  frames: number;
  iframes: number;
  recovery: number;
  back: boolean;
  forward: boolean;
}

export type UltKind = 'moonsplitter' | 'impaler' | 'tempest';

export interface UltState {
  kind: UltKind;
  phase: string;
  pf: number;
  variant: 'vertical' | 'horizontal';
  spins: number;
  impaled: boolean;
}

export interface FighterStats {
  hitsLanded: number;
  damageDealt: number;
  parries: number;
  counters: number;
  disarms: number;
  ultimates: number;
  blocks: number;
}

export interface FighterConfig {
  weapon: WeaponDef;
  abilities?: [string, string];
  name?: string;
}

const CHARGE_CHECK_FRAME = 9;
const GUARD_STATES: FState[] = ['free', 'step', 'blockstun', 'land', 'parryAnim'];

export class Fighter {
  readonly id: number;
  opp!: Fighter;
  world!: WorldLike;
  input = new InputTracker();

  weapon: WeaponDef;
  abilities: [string, string];
  name: string;
  armed = true;

  hp = HP_MAX;
  posture = 0;
  pos: Vec3 = v3();
  vel: Vec3 = v3();
  yaw = 0;

  state: FState = 'intro';
  sf = 0; // frames spent in the current state
  stateDur = 0; // duration for timed states
  actionableAfter = 0; // for scripted states that may be cancelled late

  atk: AttackState | null = null;
  dodge: DodgeState | null = null;
  ult: UltState | null = null;

  // guard / parry
  blocking = false;
  blockPressFrame = -99999;
  parryWindowAtPress = 0;
  lastBlockPress = -99999;
  spamCount = 0;
  recoilGuardAfter = 0;
  lastPostureDamage = -99999;

  // movement bookkeeping
  moving = false;
  sprintFrames = 0;
  dodgeEndFrame = -99999;
  dodgeWasBack = false;
  airAttackUsed = false;
  stepDir = { x: 0, z: 0 };

  // knockback slide
  knockX = 0;
  knockZ = 0;
  knockLeft = 0;
  knockTotal = 0;
  knockMeters = 0;

  // follow-up windows
  counterLungeUntil = -99999;
  backstabUntil = -99999;
  blindUntil = -99999;

  // ultimates
  ultUsed = false;
  ultAnnounced = false;
  impaledBy: Fighter | null = null;

  // scripted counter movement
  scriptFrom = v3();
  scriptTo = v3();

  stats: FighterStats = {
    hitsLanded: 0,
    damageDealt: 0,
    parries: 0,
    counters: 0,
    disarms: 0,
    ultimates: 0,
    blocks: 0,
  };

  constructor(id: number, cfg: FighterConfig) {
    this.id = id;
    this.weapon = cfg.weapon;
    this.abilities = cfg.abilities ?? cfg.weapon.defaultAbilities;
    this.name = cfg.name ?? cfg.weapon.name;
  }

  // ------------------------------------------------------------------ queries

  get moveset(): WeaponDef {
    return this.armed ? this.weapon : FISTS;
  }

  get airborne() {
    return this.pos.y > 0.001 || this.vel.y > 0;
  }

  get hpFrac() {
    return this.hp / HP_MAX;
  }

  get postureFull() {
    return this.posture >= POSTURE_MAX - 1e-6;
  }

  canUlt() {
    return this.hp > 0 && this.hp <= ULT_HP_THRESHOLD && !this.ultUsed;
  }

  isGuardCapable() {
    if (GUARD_STATES.includes(this.state)) return true;
    if (this.state === 'recoil' && this.sf >= this.recoilGuardAfter) return true;
    return false;
  }

  parryActive(): boolean {
    return (
      this.isGuardCapable() && this.world.frame - this.blockPressFrame <= this.parryWindowAtPress
    );
  }

  facingPoint(p: Vec3) {
    return angleBetween(this.yaw, yawTo(this.pos, p)) <= GUARD_HALF_ANGLE * DEG;
  }

  isInvulnerable() {
    const W = this.world;
    if ((this.state === 'dodge' || this.state === 'backstep') && this.dodge) {
      return this.sf <= this.dodge.iframes;
    }
    if (this.state === 'attack' && this.atk?.def.invuln) {
      const [a, b] = this.atk.def.invuln;
      return this.atk.frame >= a && this.atk.frame <= b;
    }
    if (this.state === 'recall') return this.sf <= 16;
    if (this.state === 'ult' && this.ult?.kind === 'tempest' && this.ult.phase === 'flash') return true;
    if (this.state === 'disarmStagger') return this.sf <= 8;
    if (this.state === 'leap' || this.state === 'stomp') return true;
    if (this.state === 'ko' || this.state === 'intro' || this.state === 'victory') return true;
    void W;
    return false;
  }

  /** dodging toward the attacker, early enough to count as "dodging into" a thrust */
  isForwardDodging() {
    return this.state === 'dodge' && !!this.dodge?.forward && this.sf <= MOVE.dodgeIFrames + 3;
  }

  /** back-dashing (backstep or backward dodge) within its invincible frames */
  isBackDodging() {
    return (
      (this.state === 'backstep' || (this.state === 'dodge' && !!this.dodge?.back)) &&
      !!this.dodge &&
      this.sf <= this.dodge.iframes + 2
    );
  }

  isFlashActive() {
    if (this.state !== 'attack' || !this.atk || this.atk.def.special !== 'flash') return false;
    const d = this.atk.def;
    return this.atk.frame > d.startup && this.atk.frame <= d.startup + d.active;
  }

  attackPhase(): 'startup' | 'active' | 'recovery' | null {
    if (this.state !== 'attack' || !this.atk) return null;
    const d = this.atk.def;
    const f = this.atk.frame;
    if (this.atk.charging || f <= d.startup) return 'startup';
    if (f <= d.startup + d.active) return 'active';
    return 'recovery';
  }

  speedMult() {
    return this.moveset.speedMult * (this.armed ? 1 : DISARMED_MULT.speed);
  }

  // ------------------------------------------------------------------ setup

  resetForRound(x: number, z: number, yaw: number) {
    this.hp = HP_MAX;
    this.posture = 0;
    this.armed = true;
    this.pos = v3(x, 0, z);
    this.vel = v3();
    this.yaw = yaw;
    this.atk = null;
    this.dodge = null;
    this.ult = null;
    this.blocking = false;
    this.ultUsed = false;
    this.ultAnnounced = false;
    this.impaledBy = null;
    this.counterLungeUntil = -99999;
    this.backstabUntil = -99999;
    this.blindUntil = -99999;
    this.knockLeft = 0;
    this.sprintFrames = 0;
    this.lastPostureDamage = -99999;
    this.blockPressFrame = -99999;
    this.setState('intro');
  }

  setState(s: FState, dur = 0) {
    this.state = s;
    this.sf = 0;
    this.stateDur = dur;
    if (s !== 'attack') this.atk = null;
    if (s !== 'dodge' && s !== 'backstep') this.dodge = null;
    if (s !== 'ult') this.ult = null;
    if (s !== 'free' && s !== 'step' && s !== 'blockstun' && s !== 'recoil') this.blocking = false;
  }

  toFree() {
    if (this.airborne) {
      this.setState('jump');
      this.airAttackUsed = true;
    } else {
      this.setState('free');
    }
  }

  // ------------------------------------------------------------------ main update

  update() {
    this.sf++;
    this.handleGuardPress();

    switch (this.state) {
      case 'intro':
      case 'victory':
        this.vel.x = this.vel.z = 0;
        break;
      case 'free':
        this.updateFree();
        break;
      case 'step':
        this.updateStep();
        break;
      case 'dodge':
      case 'backstep':
        this.updateDodge();
        break;
      case 'jump':
        this.updateJump();
        break;
      case 'land':
        if (this.sf >= MOVE.landRecovery) this.setState('free');
        else if (this.sf >= 2 && this.tryActions()) break;
        this.brake();
        break;
      case 'attack':
        this.updateAttack();
        break;
      case 'blockstun':
        this.blocking = this.armed && this.input.isHeld(B.Block);
        if (this.sf >= this.stateDur) this.setState('free');
        this.brake();
        break;
      case 'parryAnim':
        this.blocking = this.armed && this.input.isHeld(B.Block);
        if (this.sf >= this.stateDur) this.setState('free');
        else if (this.sf >= 3 && this.tryActions()) break;
        this.brake();
        break;
      case 'recoil':
        this.blocking = this.armed && this.sf >= this.recoilGuardAfter && this.input.isHeld(B.Block);
        if (this.sf >= this.stateDur) this.setState('free');
        this.brake();
        break;
      case 'hitstun':
      case 'stunned':
      case 'stagger':
      case 'disarmStagger':
        if (this.sf >= this.stateDur) this.toFree();
        this.brake();
        break;
      case 'pickup':
        this.updatePickup();
        break;
      case 'stomp':
        this.updateStomp();
        break;
      case 'leap':
        this.updateLeap();
        break;
      case 'ult':
        this.updateUlt();
        break;
      case 'ultChoice':
        this.updateUltChoice();
        break;
      case 'recall':
        this.updateRecall();
        break;
      case 'impaled':
        this.vel.x = this.vel.z = 0;
        break;
      case 'ko':
        this.brake();
        break;
    }

    this.integrate();
    this.updateFacing();
    this.updatePosture();
    if (this.canUlt() && !this.ultAnnounced) {
      this.ultAnnounced = true;
      this.world.emit({ t: 'ultReady', f: this.id });
    }
  }

  // ------------------------------------------------------------------ guard press

  private handleGuardPress() {
    const inp = this.input;
    if (!inp.buffered(B.Block, 2)) return;
    if (!this.isGuardCapable()) return;
    inp.consume(B.Block);
    const W = this.world;
    if (W.frame - this.lastBlockPress < PARRY_SPAM_WINDOW) this.spamCount++;
    else this.spamCount = 0;
    this.lastBlockPress = W.frame;
    const base = this.moveset.parryWindow;
    this.parryWindowAtPress = Math.max(PARRY_MIN_WINDOW, base - this.spamCount * PARRY_SPAM_PENALTY);
    this.blockPressFrame = W.frame;
  }

  // ------------------------------------------------------------------ free / movement

  private updateFree() {
    if (this.tryActions()) return;
    const inp = this.input;
    this.blocking = this.armed && inp.isHeld(B.Block);
    if (inp.stepRequest && !this.blocking && !inp.sprinting) {
      this.startStep();
      return;
    }
    this.locomotion();
  }

  private startStep() {
    const inp = this.input;
    const d = this.worldDir(inp.mx, inp.my);
    this.stepDir = d;
    this.setState('step', MOVE.stepFrames);
    this.world.emit({ t: 'step', f: this.id });
    this.updateStep();
  }

  private updateStep() {
    if (this.tryActions()) return;
    const inp = this.input;
    if (inp.isHeld(B.Block) && this.armed) {
      this.setState('free');
      this.blocking = true;
      this.locomotion();
      return;
    }
    const speed = (MOVE.stepDist / (MOVE.stepFrames * DT)) * this.speedMult();
    this.vel.x = this.stepDir.x * speed;
    this.vel.z = this.stepDir.z * speed;
    this.moving = true;
    if (this.sf >= this.stateDur) {
      this.setState('free');
      if (!inp.moving) {
        this.vel.x *= 0.25;
        this.vel.z *= 0.25;
      }
    }
  }

  /** Convert stick axes (relative to the opponent) into a world-space unit vector. */
  worldDir(mx: number, my: number) {
    const to = norm2(this.opp.pos.x - this.pos.x, this.opp.pos.z - this.pos.z);
    const rx = -to.z;
    const rz = to.x;
    return norm2(to.x * my + rx * mx, to.z * my + rz * mx);
  }

  private locomotion() {
    const inp = this.input;
    let mx = inp.mx;
    let my = inp.my;
    const mag = Math.hypot(mx, my);
    if (mag > 1) {
      mx /= mag;
      my /= mag;
    }
    const active = inp.dir !== -1;
    this.moving = active;
    let tx = 0;
    let tz = 0;
    if (active) {
      const to = norm2(this.opp.pos.x - this.pos.x, this.opp.pos.z - this.pos.z);
      const rx = -to.z;
      const rz = to.x;
      const sprinting = inp.sprinting && !this.blocking;
      let sF = my >= 0 ? MOVE.runForward : MOVE.runBack;
      let sS = MOVE.runStrafe;
      if (sprinting) sF = sS = MOVE.sprint;
      let mult = this.speedMult();
      if (this.blocking) mult *= MOVE.blockSpeedMult;
      tx = (to.x * my * sF + rx * mx * sS) * mult;
      tz = (to.z * my * sF + rz * mx * sS) * mult;
      if (sprinting) {
        // sprint at full speed in the held direction
        const n = norm2(tx, tz);
        tx = n.x * MOVE.sprint * mult;
        tz = n.z * MOVE.sprint * mult;
      }
      this.sprintFrames = sprinting ? this.sprintFrames + 1 : 0;
    } else {
      this.sprintFrames = 0;
    }
    const dvx = tx - this.vel.x;
    const dvz = tz - this.vel.z;
    const dl = Math.hypot(dvx, dvz);
    const rate = (active ? MOVE.accel : MOVE.decel) * DT;
    if (dl <= rate) {
      this.vel.x = tx;
      this.vel.z = tz;
    } else {
      this.vel.x += (dvx / dl) * rate;
      this.vel.z += (dvz / dl) * rate;
    }
  }

  private brake() {
    const k = Math.max(0, 1 - 12 * DT);
    this.vel.x *= k;
    this.vel.z *= k;
    this.moving = false;
    this.sprintFrames = 0;
  }

  // ------------------------------------------------------------------ actions

  private chordPressed() {
    const inp = this.input;
    if (!inp.buffered(B.Light, CHORD_FRAMES) || !inp.buffered(B.Heavy, CHORD_FRAMES)) return false;
    return Math.abs(inp.pressFrame[B.Light] - inp.pressFrame[B.Heavy]) <= CHORD_FRAMES;
  }

  /** Start whatever action the buffered input asks for. Returns true if one began. */
  tryActions(): boolean {
    const inp = this.input;
    const W = this.world;
    if (this.canUlt() && (inp.buffered(B.Ultimate, 4) || this.chordPressed())) {
      inp.consume(B.Ultimate);
      inp.consume(B.Light);
      inp.consume(B.Heavy);
      this.startUlt();
      return true;
    }
    if (this.armed && inp.isHeld(B.Block)) {
      if (inp.buffered(B.Light) && this.abilities[0]) {
        inp.consume(B.Light);
        this.startAttack(this.abilities[0], B.Light);
        return true;
      }
      if (inp.buffered(B.Heavy) && this.abilities[1]) {
        inp.consume(B.Heavy);
        this.startAttack(this.abilities[1], B.Heavy);
        return true;
      }
    }
    if (!this.armed && inp.buffered(B.Interact)) {
      const w = W.weaponOf(this.id);
      if (w && w.grounded && dist2(w.pos, this.pos) <= PICKUP_RANGE) {
        inp.consume(B.Interact);
        this.setState('pickup', PICKUP_FRAMES);
        this.vel.x = this.vel.z = 0;
        return true;
      }
    }
    if (inp.buffered(B.Dodge)) {
      inp.consume(B.Dodge);
      this.startDodge();
      return true;
    }
    if (inp.buffered(B.Jump) && !this.airborne) {
      inp.consume(B.Jump);
      this.startJump();
      return true;
    }
    if (inp.buffered(B.Light)) {
      inp.consume(B.Light);
      this.startAttack(this.contextAttack('light'), B.Light);
      return true;
    }
    if (inp.buffered(B.Heavy)) {
      inp.consume(B.Heavy);
      this.startAttack(this.contextAttack('heavy'), B.Heavy);
      return true;
    }
    return false;
  }

  private contextAttack(kind: 'light' | 'heavy'): string {
    const w = this.moveset;
    const W = this.world;
    const L = kind === 'light';
    if (L && W.frame <= this.counterLungeUntil) {
      this.counterLungeUntil = -99999;
      return COUNTER_LUNGE[w.id];
    }
    if (this.airborne) return L ? w.jumpLight : w.jumpHeavy;
    if (this.sprintFrames >= MOVE.sprintAttackMinFrames) return L ? w.sprintLight : w.sprintHeavy;
    if (W.frame - this.dodgeEndFrame <= MOVE.followWindow) {
      if (this.dodgeWasBack) return L ? w.backLight : w.backHeavy;
      return L ? w.dodgeLight : w.dodgeHeavy;
    }
    return L ? w.lightStart : w.heavyStart;
  }

  startAttack(id: string, startedBy: B | null = null): boolean {
    const W = this.world;
    const def = this.moveset.moves[id] ?? (id.startsWith('f_') ? FISTS.moves[id] : undefined);
    if (!def) {
      // the move belongs to a weapon we no longer hold (e.g. disarmed mid-combo)
      if (this.state === 'attack') this.toFree();
      return false;
    }
    const wasDodging = this.state === 'dodge' || this.state === 'backstep';
    if (wasDodging) {
      this.dodgeEndFrame = W.frame;
      this.dodgeWasBack = !!this.dodge?.back;
    }
    this.setState('attack');
    this.blocking = false;
    const lungeTotal =
      def.special === 'counterLunge'
        ? clamp(dist2(this.pos, this.opp.pos) - FIGHTER_RADIUS * 2 - 0.6, 0, 7)
        : def.lunge ?? 0;
    this.atk = {
      def,
      frame: 0,
      hitDone: false,
      hitsDone: 0,
      charging: false,
      chargeFrames: 0,
      chargeFrac: 0,
      queued: null,
      lungeTotal,
      extraRecovery: 0,
      backstab: def.kind === 'light' && W.frame <= this.backstabUntil,
      startedBy,
      evadedEmitted: false,
      whiffEmitted: false,
    };
    if (this.atk.backstab) this.backstabUntil = -99999;
    if (def.airborne) this.airAttackUsed = true;
    this.sprintFrames = 0;
    if (def.counter) this.world.emit({ t: 'telegraph', f: this.id, kind: def.counter, attack: def.id });
    if (def.special === 'shadowStep') this.planShadowStep();
    if (!def.airborne && !def.hop) {
      // keep a little of the running momentum
      this.vel.x *= 0.3;
      this.vel.z *= 0.3;
    }
    return true;
  }

  private planShadowStep() {
    const o = this.opp.pos;
    const dx = this.pos.x - o.x;
    const dz = this.pos.z - o.z;
    const r0 = Math.max(1.0, Math.hypot(dx, dz));
    const a0 = Math.atan2(dx, dz);
    // circle toward the held side, default to the right
    const side = this.input.mx < -0.3 ? -1 : 1;
    this.atk!.pathFrom = { ang: a0, r: r0 };
    this.atk!.pathTo = { ang: a0 + side * Math.PI * 0.95, r: 1.35 };
  }

  private updateAttack() {
    const a = this.atk!;
    const def = a.def;
    const inp = this.input;
    const W = this.world;

    // Light + heavy within a few frames: cancel into the ultimate.
    if (a.frame <= CHORD_FRAMES && a.startedBy !== null && this.canUlt() && def.kind !== 'ability') {
      const other = a.startedBy === B.Light ? B.Heavy : B.Light;
      if (inp.buffered(other, CHORD_FRAMES)) {
        inp.consume(other);
        this.startUlt();
        return;
      }
    }

    // Charging a heavy.
    if (def.chargeable && !a.charging && a.chargeFrames === 0 && a.frame === CHARGE_CHECK_FRAME) {
      if (inp.isHeld(B.Heavy)) a.charging = true;
    }
    if (a.charging) {
      a.chargeFrames++;
      this.brake();
      if (!inp.isHeld(B.Heavy) || a.chargeFrames >= CHARGE_MAX) {
        a.charging = false;
        if (a.chargeFrames >= CHARGE_MAX) a.chargeFrac = 1;
        else if (a.chargeFrames >= CHARGE_MIN) a.chargeFrac = clamp(a.chargeFrames / CHARGE_MAX, 0, 0.95);
        else a.chargeFrac = 0;
        a.extraRecovery += Math.round(16 * a.chargeFrac);
      } else {
        return;
      }
    }

    a.frame++;
    const f = a.frame;
    const S = def.startup;
    const A = def.active;
    const R = def.recovery + a.extraRecovery;

    // Lunge forward along our facing.
    const ls = def.lungeStart ?? 0;
    const le = def.lungeEnd ?? S + A;
    if (a.lungeTotal > 0 && f > ls && f <= le) {
      const per = a.lungeTotal / Math.max(1, le - ls);
      const d = dist2(this.pos, this.opp.pos);
      const minGap = FIGHTER_RADIUS * 2 + 0.25;
      const step = Math.min(per, Math.max(0, d - minGap));
      const dir = fwd(this.yaw);
      this.pos.x += dir.x * step;
      this.pos.z += dir.z * step;
    }
    if (def.hop && f === ls + 1 && !this.airborne) this.vel.y = def.hop;
    if (def.airborne && def.type === 'overhead' && f === S + 1 && this.airborne) this.vel.y = Math.min(this.vel.y, -6);
    if (!def.airborne && !this.airborne) this.brake();

    if (f === S) {
      this.world.emit({
        t: 'swing',
        f: this.id,
        attack: def.id,
        heavy: def.kind !== 'light',
        weapon: this.moveset.id,
      });
    }

    if (def.special === 'shadowStep') this.updateShadowStep(f);

    // Whiff notice once the active frames pass without contact.
    if (f === S + A + 1 && !a.hitDone && def.damage > 0 && !a.whiffEmitted) {
      a.whiffEmitted = true;
      this.world.emit({ t: 'whiff', f: this.id, attack: def.id });
    }

    // Combo chains.
    if (f > S && !a.queued) {
      if (def.chainLight && inp.buffered(B.Light) && !(this.armed && inp.isHeld(B.Block))) {
        inp.consume(B.Light);
        a.queued = def.chainLight;
      } else if (def.chainHeavy && inp.buffered(B.Heavy) && !(this.armed && inp.isHeld(B.Block))) {
        inp.consume(B.Heavy);
        a.queued = def.chainHeavy;
      }
    }
    if (a.queued && f >= S + A + 2) {
      this.startAttack(a.queued, null);
      return;
    }

    // Dodge-cancel the recovery of quick attacks.
    if (def.dodgeCancelFrom !== undefined && f >= def.dodgeCancelFrom && inp.buffered(B.Dodge)) {
      inp.consume(B.Dodge);
      this.startDodge();
      return;
    }

    if (f >= S + A + R) {
      if (def.special === 'shadowStep') {
        this.backstabUntil = W.frame + 30;
      }
      this.atk = null;
      this.toFree();
    }
  }

  private updateShadowStep(f: number) {
    const a = this.atk!;
    const def = a.def;
    const S = def.startup;
    const A = def.active;
    if (f > S && f <= S + A && a.pathFrom && a.pathTo) {
      const t = easeOutCubic((f - S) / A);
      const ang = a.pathFrom.ang + (a.pathTo.ang - a.pathFrom.ang) * t;
      const r = a.pathFrom.r + (a.pathTo.r - a.pathFrom.r) * t;
      this.pos.x = this.opp.pos.x + Math.sin(ang) * r;
      this.pos.z = this.opp.pos.z + Math.cos(ang) * r;
      this.yaw = yawTo(this.pos, this.opp.pos);
      if (f === S + A) {
        this.opp.blindUntil = this.world.frame + 6;
        this.world.emit({ t: 'backstabReady', f: this.id });
      }
    }
  }

  // ------------------------------------------------------------------ dodge / jump

  startDodge() {
    const inp = this.input;
    const W = this.world;
    const mult = this.moveset.dodgeMult * (this.armed ? 1 : DISARMED_MULT.dodge);
    const to = norm2(this.opp.pos.x - this.pos.x, this.opp.pos.z - this.pos.z);
    if (inp.dir === -1) {
      this.setState('backstep');
      this.dodge = {
        dirX: -to.x,
        dirZ: -to.z,
        dist: MOVE.backstepDist * mult,
        frames: MOVE.backstepFrames,
        iframes: MOVE.backstepIFrames,
        recovery: MOVE.backstepRecovery,
        back: true,
        forward: false,
      };
    } else {
      const dv = dirVector(inp.dir);
      const d = this.worldDir(dv.mx, dv.my);
      this.setState('dodge');
      this.dodge = {
        dirX: d.x,
        dirZ: d.z,
        dist: MOVE.dodgeDist * mult,
        frames: MOVE.dodgeFrames,
        iframes: MOVE.dodgeIFrames,
        recovery: MOVE.dodgeRecovery,
        back: inp.dir >= 3 && inp.dir <= 5,
        forward: inp.dir === 0 || inp.dir === 1 || inp.dir === 7,
      };
    }
    this.vel.x = this.vel.z = 0;
    this.sprintFrames = 0;
    W.emit({ t: 'dodge', f: this.id, back: this.dodge!.back });
  }

  private updateDodge() {
    const dg = this.dodge!;
    const f = this.sf;
    if (f <= dg.frames) {
      const t0 = easeOutCubic((f - 1) / dg.frames);
      const t1 = easeOutCubic(f / dg.frames);
      const step = (t1 - t0) * dg.dist;
      this.pos.x += dg.dirX * step;
      this.pos.z += dg.dirZ * step;
      this.vel.x = this.vel.z = 0;
    }
    // follow-up attacks are allowed once the invincible part is over
    if (f > dg.iframes) {
      const inp = this.input;
      if (inp.buffered(B.Light) || inp.buffered(B.Heavy) || (f > dg.frames && (inp.buffered(B.Dodge) || inp.buffered(B.Jump)))) {
        this.dodgeEndFrame = this.world.frame;
        this.dodgeWasBack = dg.back;
        if (this.tryActions()) return;
      }
    }
    if (f >= dg.frames + dg.recovery) {
      this.dodgeEndFrame = this.world.frame;
      this.dodgeWasBack = dg.back;
      this.setState('free');
    }
  }

  private startJump() {
    const h = MOVE.jumpHeight * (this.armed ? 1 : DISARMED_MULT.jump);
    this.vel.y = Math.sqrt(2 * GRAVITY * h);
    const inp = this.input;
    if (inp.moving) {
      const d = this.worldDir(inp.mx, inp.my);
      const s = (inp.sprinting ? MOVE.sprint : MOVE.runStrafe) * this.speedMult();
      this.vel.x = d.x * s;
      this.vel.z = d.z * s;
    }
    this.setState('jump');
    this.airAttackUsed = false;
    this.world.emit({ t: 'jump', f: this.id });
  }

  private updateJump() {
    const inp = this.input;
    if (!this.airAttackUsed) {
      if (inp.buffered(B.Light)) {
        inp.consume(B.Light);
        this.startAttack(this.moveset.jumpLight, B.Light);
        return;
      }
      if (inp.buffered(B.Heavy)) {
        inp.consume(B.Heavy);
        this.startAttack(this.moveset.jumpHeavy, B.Heavy);
        return;
      }
    }
    // gentle air steering
    if (inp.moving) {
      const d = this.worldDir(inp.mx, inp.my);
      this.vel.x += d.x * 6 * DT;
      this.vel.z += d.z * 6 * DT;
      const s = Math.hypot(this.vel.x, this.vel.z);
      const cap = MOVE.sprint * this.speedMult();
      if (s > cap) {
        this.vel.x *= cap / s;
        this.vel.z *= cap / s;
      }
    }
  }

  // ------------------------------------------------------------------ physics

  private integrate() {
    const W = this.world;
    if (this.state === 'impaled' || this.state === 'leap' || this.state === 'stomp') return;
    const wasAir = this.pos.y > 0.001;

    // strafing orbits the opponent: keep distance when moving sideways only
    let keep = -1;
    if ((this.state === 'free' || this.state === 'step') && this.moving && Math.abs(this.input.my) < 0.25) {
      keep = dist2(this.pos, this.opp.pos);
    }

    this.pos.x += this.vel.x * DT;
    this.pos.z += this.vel.z * DT;

    if (keep > 0 && keep < 9) {
      const dx = this.pos.x - this.opp.pos.x;
      const dz = this.pos.z - this.opp.pos.z;
      const d = Math.hypot(dx, dz);
      if (d > 1e-6) {
        this.pos.x = this.opp.pos.x + (dx / d) * keep;
        this.pos.z = this.opp.pos.z + (dz / d) * keep;
      }
    }

    // knockback slide
    if (this.knockLeft > 0) {
      const T = this.knockTotal;
      const k = T - this.knockLeft;
      const d = (this.knockMeters * 2 * (T - k)) / (T * (T + 1));
      this.pos.x += this.knockX * d;
      this.pos.z += this.knockZ * d;
      this.knockLeft--;
    }

    // vertical
    if (wasAir || this.vel.y > 0) {
      this.vel.y -= GRAVITY * DT;
      this.pos.y += this.vel.y * DT;
      if (this.pos.y <= 0) {
        this.pos.y = 0;
        const falling = this.vel.y < 0;
        this.vel.y = 0;
        if (falling) this.onLand();
      }
    }
    void W;
  }

  private onLand() {
    this.world.emit({ t: 'land', f: this.id });
    if (this.state === 'jump') {
      this.setState('land', MOVE.landRecovery);
      this.vel.x *= 0.4;
      this.vel.z *= 0.4;
    } else if (this.state === 'attack' && this.atk?.def.airborne) {
      // landing ends the air attack's active part quickly
      const a = this.atk;
      const d = a.def;
      if (a.frame < d.startup + d.active) a.frame = Math.max(a.frame, d.startup);
    }
  }

  private updateFacing() {
    const W = this.world;
    const target = yawTo(this.pos, this.opp.pos);
    let rate = MOVE.turnRate;
    switch (this.state) {
      case 'attack': {
        const ph = this.attackPhase();
        const d = this.atk!.def;
        if (d.special === 'shadowStep') return;
        rate = this.atk!.charging ? 3 : ph === 'startup' ? d.trackStartup! : ph === 'active' ? d.trackActive! : 0.5;
        break;
      }
      case 'hitstun':
      case 'stunned':
      case 'stagger':
      case 'disarmStagger':
      case 'recoil':
        rate = 2;
        break;
      case 'ko':
      case 'impaled':
      case 'leap':
        return;
      case 'ult':
        rate = this.ult?.phase === 'windup' || this.ult?.phase === 'aim' ? 8 : this.ult?.phase === 'dash' ? 0.6 : 3;
        break;
    }
    if (W.frame < this.blindUntil) rate = 0;
    this.yaw = turnToward(this.yaw, target, rate * DT);
  }

  private updatePosture() {
    const W = this.world;
    if (this.state === 'ko') return;
    if (this.armed) {
      if (
        this.blocking &&
        this.state === 'free' &&
        W.frame - this.lastPostureDamage >= POSTURE_RECOVER_DELAY &&
        this.posture > 0
      ) {
        const moving = Math.hypot(this.vel.x, this.vel.z) > 0.3;
        const base = moving ? POSTURE_RECOVER_MOVE : POSTURE_RECOVER_STAND;
        const hpF = POSTURE_RECOVER_HP_FLOOR + (1 - POSTURE_RECOVER_HP_FLOOR) * this.hpFrac;
        this.posture = Math.max(0, this.posture - base * hpF * DT);
      }
    } else if (
      W.frame - this.lastPostureDamage >= DISARMED_POSTURE_DELAY &&
      this.state !== 'stagger' &&
      this.posture > 0
    ) {
      this.posture = Math.max(0, this.posture - DISARMED_POSTURE_RECOVER * DT);
    }
  }

  // ------------------------------------------------------------------ damage & reactions

  addPosture(amount: number) {
    if (amount <= 0) return;
    this.posture = Math.min(POSTURE_MAX, this.posture + amount);
    this.lastPostureDamage = this.world.frame;
  }

  knock(fromX: number, fromZ: number, meters: number, frames = 14) {
    const d = norm2(this.pos.x - fromX, this.pos.z - fromZ);
    this.knockX = d.x;
    this.knockZ = d.z;
    this.knockMeters = meters;
    this.knockTotal = Math.max(2, frames);
    this.knockLeft = this.knockTotal;
  }

  enterHitstun(frames: number) {
    this.setState('hitstun', frames);
    this.vel.x = this.vel.z = 0;
  }

  enterStun(frames: number, kind: FState = 'stunned') {
    this.setState(kind, frames);
    this.vel.x = this.vel.z = 0;
  }

  enterRecoil(frames: number, guardAfter: number) {
    this.setState('recoil', frames);
    this.recoilGuardAfter = guardAfter;
    this.vel.x = this.vel.z = 0;
  }

  disarm(by: Fighter, reason: 'parried' | 'blocked' | 'redirect') {
    const W = this.world;
    this.armed = false;
    this.posture = 0;
    this.lastPostureDamage = W.frame;
    this.setState('disarmStagger', DISARM_STAGGER);
    this.knock(by.pos.x, by.pos.z, 1.3, 16);
    W.spawnDroppedWeapon(this, by);
    W.emit({ t: 'disarm', victim: this.id, by: by.id, pos: v3(this.pos.x, 1.2, this.pos.z), reason });
    by.stats.disarms++;
  }

  // ------------------------------------------------------------------ pickup / counters

  private updatePickup() {
    this.brake();
    if (this.sf === PICKUP_ATTACH_FRAME) {
      const w = this.world.weaponOf(this.id);
      if (w && dist2(w.pos, this.pos) <= PICKUP_RANGE + 0.5) {
        this.world.removeDroppedWeapon(this.id);
        this.armed = true;
        this.world.emit({ t: 'pickup', f: this.id });
      }
    }
    if (this.sf >= this.stateDur) this.setState('free');
  }

  beginStomp(attacker: Fighter) {
    this.setState('stomp', 26);
    this.actionableAfter = 16;
    this.scriptFrom = v3(this.pos.x, 0, this.pos.z);
    const d = fwd(attacker.yaw);
    this.scriptTo = v3(attacker.pos.x + d.x * 0.95, 0, attacker.pos.z + d.z * 0.95);
    this.vel = v3();
    this.pos.y = 0;
  }

  private updateStomp() {
    const t = Math.min(1, this.sf / 8);
    const e = easeOutCubic(t);
    this.pos.x = this.scriptFrom.x + (this.scriptTo.x - this.scriptFrom.x) * e;
    this.pos.z = this.scriptFrom.z + (this.scriptTo.z - this.scriptFrom.z) * e;
    this.pos.y = this.sf < 8 ? Math.sin(t * Math.PI) * 0.35 : 0;
    this.yaw = yawTo(this.pos, this.opp.pos);
    if (this.sf >= this.actionableAfter && this.tryActions()) return;
    if (this.sf >= this.stateDur) this.setState('free');
  }

  beginLeap(attacker: Fighter) {
    this.setState('leap', 32);
    this.scriptFrom = v3(this.pos.x, this.pos.y, this.pos.z);
    const to = norm2(attacker.pos.x - this.pos.x, attacker.pos.z - this.pos.z);
    // land a little further out than we started, on the same side
    this.scriptTo = v3(attacker.pos.x - to.x * 2.4, 0, attacker.pos.z - to.z * 2.4);
    this.vel = v3();
  }

  private updateLeap() {
    const o = this.opp.pos;
    const f = this.sf;
    const to = norm2(o.x - this.scriptFrom.x, o.z - this.scriptFrom.z);
    if (f <= 10) {
      // spring onto the attacker's shoulders
      const t = f / 10;
      const target = v3(o.x - to.x * 0.55, 1.55, o.z - to.z * 0.55);
      const e = easeOutCubic(t);
      this.pos.x = this.scriptFrom.x + (target.x - this.scriptFrom.x) * e;
      this.pos.z = this.scriptFrom.z + (target.z - this.scriptFrom.z) * e;
      this.pos.y = this.scriptFrom.y + (target.y - this.scriptFrom.y) * e;
    } else {
      // kick off and arc back down
      const t = Math.min(1, (f - 10) / 22);
      const start = v3(o.x - to.x * 0.55, 1.55, o.z - to.z * 0.55);
      this.pos.x = start.x + (this.scriptTo.x - start.x) * t;
      this.pos.z = start.z + (this.scriptTo.z - start.z) * t;
      this.pos.y = Math.max(0, start.y + 1.2 * Math.sin(t * Math.PI) * (1 - t) - start.y * t * t);
    }
    this.yaw = yawTo(this.pos, o);
    if (f >= this.stateDur) {
      this.pos.y = 0;
      this.world.emit({ t: 'land', f: this.id });
      this.setState('free');
    }
  }

  // ------------------------------------------------------------------ ultimates

  startUlt() {
    const W = this.world;
    this.ultUsed = true;
    this.stats.ultimates++;
    this.vel.x = this.vel.z = 0;
    if (!this.armed) {
      this.setState('ultChoice', ULT_CHOICE_FRAMES);
      W.emit({ t: 'ultChoice', f: this.id });
      W.requestSlowmo(ULT_CHOICE_FRAMES, 0.35);
      return;
    }
    const kind = this.weapon.ultimate as UltKind;
    this.setState('ult');
    this.ult = {
      kind,
      phase: kind === 'moonsplitter' ? 'windup' : kind === 'impaler' ? 'aim' : 'flash',
      pf: 0,
      variant: 'vertical',
      spins: 0,
      impaled: false,
    };
    W.emit({ t: 'ultStart', f: this.id, ult: kind });
    W.emit({ t: 'telegraph', f: this.id, kind: 'ult', attack: kind });
  }

  private setUltPhase(p: string) {
    this.ult!.phase = p;
    this.ult!.pf = 0;
  }

  private updateUlt() {
    const u = this.ult!;
    u.pf++;
    this.brake();
    switch (u.kind) {
      case 'moonsplitter':
        return this.ultMoonsplitter(u);
      case 'impaler':
        return this.ultImpaler(u);
      case 'tempest':
        return this.ultTempest(u);
    }
  }

  private ultMoonsplitter(u: UltState) {
    const W = this.world;
    const inp = this.input;
    if (u.phase === 'windup') {
      if (inp.dir !== -1) {
        u.variant = Math.abs(inp.mx) > Math.abs(inp.my) ? 'horizontal' : 'vertical';
      }
      if (u.pf >= 36) {
        this.setUltPhase('release');
        W.spawnWave(this, u.variant);
      }
    } else if (u.phase === 'release') {
      if (u.pf >= 34) this.toFree();
    }
  }

  private ultImpaler(u: UltState) {
    const W = this.world;
    const o = this.opp;
    if (u.phase === 'aim') {
      if (u.pf >= 30) {
        this.setUltPhase('dash');
        W.emit({ t: 'ultDash', f: this.id });
      }
    } else if (u.phase === 'dash') {
      const d = fwd(this.yaw);
      const speed = 24 * DT;
      const gap = dist2(this.pos, o.pos);
      this.pos.x += d.x * speed;
      this.pos.z += d.z * speed;
      // contact check: target just ahead of the blade tip
      const dx = o.pos.x - this.pos.x;
      const dz = o.pos.z - this.pos.z;
      const along = dx * d.x + dz * d.z;
      const lateral = Math.abs(dx * d.z - dz * d.x);
      if (along > -0.2 && along < 1.9 && lateral < 0.85 && o.pos.y < 1.5) {
        W.queueScriptedHit(this, o, ULT_HITS.u_impale, (res) => {
          if (this.state !== 'ult' || this.ult !== u || u.phase !== 'dash') return; // parried or disarmed
          if (res === 'hit' && o.state === 'ko') {
            this.setUltPhase('recover');
          } else if (res === 'hit') {
            u.impaled = true;
            o.impaledBy = this;
            o.setState('impaled');
            o.knockLeft = 0;
            this.setUltPhase('impale');
            W.emit({ t: 'ultImpale', f: this.id, target: o.id });
          } else if (res === 'parry' || res === 'flash' || res === 'redirect' || res === 'block' || res === 'disarm') {
            this.setUltPhase('recover');
          }
        });
      }
      const r = Math.hypot(this.pos.x, this.pos.z);
      if (u.pf >= 40 || r > 10.8 || (gap < 0.6 && along < -0.5)) this.setUltPhase('recover');
    } else if (u.phase === 'impale') {
      // hold the victim on the blade
      const d = fwd(this.yaw);
      o.pos.x = this.pos.x + d.x * 1.3;
      o.pos.z = this.pos.z + d.z * 1.3;
      o.pos.y = Math.min(1.0, o.pos.y + 0.12);
      o.vel = v3();
      if (u.pf >= 8 && this.input.buffered(B.Heavy, 10)) {
        this.input.consume(B.Heavy);
        this.setUltPhase('burst');
        W.emit({ t: 'ultBurst', f: this.id, pos: v3(o.pos.x, 1.2, o.pos.z) });
        this.releaseImpaled();
        W.queueScriptedHit(this, o, ULT_HITS.u_burst);
        return;
      }
      if (o.state !== 'impaled') {
        // something freed the victim (e.g. a KO elsewhere)
        this.setUltPhase('recover');
        return;
      }
      if (u.pf >= 50) {
        this.releaseImpaled();
        o.enterHitstun(30);
        o.knock(this.pos.x, this.pos.z, 1.2, 12);
        this.setUltPhase('recover');
      }
    } else if (u.phase === 'burst') {
      if (u.pf >= 24) this.setUltPhase('recover');
    } else if (u.phase === 'recover') {
      if (u.pf >= 30) this.toFree();
    }
  }

  releaseImpaled() {
    const o = this.opp;
    if (o.state === 'impaled') {
      o.impaledBy = null;
      o.pos.y = Math.max(o.pos.y, 0.6);
      o.vel.y = 0;
      o.setState('hitstun', 30);
    }
  }

  private ultTempest(u: UltState) {
    const W = this.world;
    const o = this.opp;
    if (u.phase === 'flash') {
      if (u.pf === 1) {
        const to = norm2(o.pos.x - this.pos.x, o.pos.z - this.pos.z);
        const from = v3(this.pos.x, 1, this.pos.z);
        this.scriptFrom = v3(this.pos.x, 0, this.pos.z);
        const gap = Math.max(0, dist2(this.pos, o.pos) - 1.15);
        this.scriptTo = v3(this.pos.x + to.x * gap, 0, this.pos.z + to.z * gap);
        W.emit({ t: 'ultLightning', f: this.id, from, to: v3(this.scriptTo.x, 1, this.scriptTo.z) });
      }
      const t = Math.min(1, u.pf / 6);
      this.pos.x = this.scriptFrom.x + (this.scriptTo.x - this.scriptFrom.x) * t;
      this.pos.z = this.scriptFrom.z + (this.scriptTo.z - this.scriptFrom.z) * t;
      if (u.pf >= 8) this.setUltPhase('spin');
    } else if (u.phase === 'spin') {
      // keep close to the target while spinning
      const d = dist2(this.pos, o.pos);
      if (d > 1.3) {
        const to = norm2(o.pos.x - this.pos.x, o.pos.z - this.pos.z);
        const s = Math.min(d - 1.2, 0.12);
        this.pos.x += to.x * s;
        this.pos.z += to.z * s;
      }
      if (u.pf === 5) {
        W.queueScriptedHit(this, o, ULT_HITS.u_tempest, (res) => {
          if (this.state !== 'ult' || this.ult !== u) return; // parried while our posture was full
          if (res === 'disarm' || o.state === 'ko') this.setUltPhase('recover');
        });
      }
      if (u.pf >= 10) {
        u.spins++;
        if (u.spins >= 6) this.setUltPhase('final');
        else this.setUltPhase('spin');
      }
    } else if (u.phase === 'final') {
      if (u.pf === 8) W.queueScriptedHit(this, o, ULT_HITS.u_tempest_final);
      if (u.pf >= 14) this.setUltPhase('recover');
    } else if (u.phase === 'recover') {
      if (u.pf >= 24) this.toFree();
    }
  }

  private updateUltChoice() {
    const inp = this.input;
    this.brake();
    if (inp.buffered(B.Heavy, 6)) {
      inp.consume(B.Heavy);
      inp.consume(B.Light);
      this.startAttack('f_breaker', null);
      return;
    }
    if (inp.buffered(B.Light, 6) || this.sf >= this.stateDur) {
      inp.consume(B.Light);
      this.setState('recall', 26);
      this.world.emit({ t: 'recall', f: this.id });
    }
  }

  private updateRecall() {
    this.brake();
    if (this.sf === 16) {
      this.world.removeDroppedWeapon(this.id);
      this.armed = true;
      this.world.emit({ t: 'pickup', f: this.id });
    }
    if (this.sf >= this.stateDur) this.setState('free');
  }

  toKO() {
    this.hp = 0;
    this.releaseIfImpaling();
    this.setState('ko');
    this.vel.x = this.vel.z = 0;
  }

  releaseIfImpaling() {
    if (this.state === 'ult' && this.ult?.impaled) this.releaseImpaled();
  }

  /** Angle (deg) between our facing and the direction to a point. */
  angleTo(p: Vec3) {
    return Math.abs(wrapAngle(yawTo(this.pos, p) - this.yaw)) / DEG;
  }
}
