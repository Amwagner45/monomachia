import type { SimEvent } from './events';
import type { Vec3 } from './math';
import type { AttackDef } from './moves/types';
import type { Fighter } from './fighter';

export type OutcomeKind =
  | 'miss'
  | 'jumped'
  | 'evade'
  | 'parry'
  | 'flash'
  | 'redirect'
  | 'stomp'
  | 'leap'
  | 'evadeCounter'
  | 'block'
  | 'disarm'
  | 'hit';

export interface DroppedWeaponLike {
  owner: number;
  pos: Vec3;
  grounded: boolean;
}

/** The slice of the World a Fighter is allowed to talk to. */
export interface WorldLike {
  frame: number;
  emit(e: SimEvent): void;
  weaponOf(owner: number): DroppedWeaponLike | null;
  removeDroppedWeapon(owner: number): void;
  spawnDroppedWeapon(victim: Fighter, by: Fighter): void;
  spawnWave(owner: Fighter, kind: 'vertical' | 'horizontal'): void;
  resolveScriptedHit(a: Fighter, b: Fighter, def: AttackDef): OutcomeKind;
  queueScriptedHit(a: Fighter, b: Fighter, def: AttackDef, cb?: (res: OutcomeKind) => void): void;
  requestSlowmo(frames: number, scale: number): void;
}
