// Data definitions for attacks and weapons. Every move in the game is a record
// of numbers, so new weapons are mostly "filling in a form".

export type AttackType =
  | 'slash'
  | 'overhead'
  | 'thrust'
  | 'sweep'
  | 'slam'
  | 'spin'
  | 'bash'
  | 'stab'
  | 'punch'
  | 'kick';

export type CounterKind = 'thrust' | 'sweep' | 'slam';
export type Hand = 'R' | 'L' | 'both';
export type AttackKind = 'light' | 'heavy' | 'ability' | 'special' | 'ultimate';
export type HitSound = 'blade' | 'colossal' | 'dagger' | 'fist';

export interface AttackDef {
  id: string;
  name: string;
  kind: AttackKind;
  type: AttackType;
  /** Animation archetype key used by the renderer */
  anim: string;
  hand?: Hand;
  startup: number;
  active: number;
  recovery: number;
  damage: number;
  posture: number;
  /** metres of pushback on a clean hit */
  knockback: number;
  /** reach from the attacker's centre to the target's surface (m) */
  range: number;
  minRange?: number;
  /** full cone angle in degrees */
  arc: number;
  /** metres travelled forward between lungeStart and lungeEnd */
  lunge?: number;
  lungeStart?: number;
  lungeEnd?: number;
  /** turn rate while winding up (rad/s) */
  trackStartup?: number;
  /** turn rate while active (rad/s) */
  trackActive?: number;
  hitstun?: number;
  blockstun?: number;
  hitstop?: number;
  unblockable?: boolean;
  counter?: CounterKind;
  jumpable?: boolean;
  undodgeable?: boolean;
  /** counts as a "power attack" for the disarm rules */
  power?: boolean;
  chainLight?: string;
  chainHeavy?: string;
  /** light-attack recovery may be cancelled into a dodge after this frame */
  dodgeCancelFrom?: number;
  multiHit?: number;
  multiInterval?: number;
  /** performed in the air (jump attacks) */
  airborne?: boolean;
  /** posture multiplier through a block (overrides the defender's mitigation) */
  guardCrush?: number;
  special?: 'flash' | 'shadowStep' | 'counterLunge' | 'breakerPalm';
  /** heavy starters can be held to charge */
  chargeable?: boolean;
  sound?: HitSound;
  /** visual trail colour class */
  trail?: 'normal' | 'danger' | 'ult';
  /** i-frames during the move (frames from start, inclusive range) */
  invuln?: [number, number];
  /** vertical hop applied at lungeStart (m/s), for leaping attacks */
  hop?: number;
}

export type WeaponId = 'katana' | 'greatsword' | 'daggers' | 'fists';
export type UltimateId = 'moonsplitter' | 'impaler' | 'tempest' | 'disarmed';
export type WeaponClass = 'small' | 'medium' | 'colossal' | 'fists';

export interface WeaponDef {
  id: WeaponId;
  name: string;
  cls: WeaponClass;
  /** movement speed multiplier */
  speedMult: number;
  /** dodge distance multiplier */
  dodgeMult: number;
  /** frames before impact in which a block press parries */
  parryWindow: number;
  /** fraction of an attack's posture damage taken when blocking */
  blockMitigation: number;
  moves: Record<string, AttackDef>;
  lightStart: string;
  heavyStart: string;
  sprintLight: string;
  sprintHeavy: string;
  dodgeLight: string;
  dodgeHeavy: string;
  backLight: string;
  backHeavy: string;
  jumpLight: string;
  jumpHeavy: string;
  /** block-ability options: pick 2 */
  abilities: string[];
  defaultAbilities: [string, string];
  ultimate: UltimateId;
  /** preferred fighting distance for the AI */
  reach: number;
  /** blurb for menus */
  blurb: string;
}

/** Fill in derived defaults so move files can stay terse. */
export function finalizeMoves(moves: Record<string, AttackDef>) {
  for (const m of Object.values(moves)) {
    if (m.trackStartup === undefined) m.trackStartup = m.unblockable ? 5 : 7;
    if (m.trackActive === undefined) m.trackActive = 1.2;
    if (m.hitstun === undefined) {
      m.hitstun =
        m.kind === 'light' ? 18 : m.kind === 'heavy' ? 26 : m.kind === 'ultimate' ? 40 : 24;
    }
    if (m.blockstun === undefined) {
      m.blockstun = m.kind === 'light' ? 10 : m.kind === 'heavy' ? 16 : 14;
    }
    if (m.hitstop === undefined) {
      m.hitstop = m.kind === 'light' ? 4 : m.kind === 'heavy' ? 7 : 6;
    }
    if (m.unblockable && m.undodgeable === undefined) m.undodgeable = true;
    if (m.unblockable && m.trail === undefined) m.trail = 'danger';
    if (m.kind === 'ultimate' && m.trail === undefined) m.trail = 'ult';
    if (m.trail === undefined) m.trail = 'normal';
    if (m.hand === undefined) m.hand = 'R';
  }
  return moves;
}

export const totalFrames = (m: AttackDef) => m.startup + m.active + m.recovery;
