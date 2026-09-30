import type { Vec3 } from './math';
import type { CounterKind, HitSound, WeaponId } from './moves/types';

// Everything noteworthy that happens in the simulation is emitted as an event.
// The renderer, audio and HUD consume them; tests assert on them.
export type SimEvent =
  | { t: 'swing'; f: number; attack: string; heavy: boolean; weapon: WeaponId }
  | { t: 'telegraph'; f: number; kind: CounterKind | 'ult'; attack: string }
  | {
      t: 'hit';
      attacker: number;
      target: number;
      attack: string;
      damage: number;
      posture: number;
      pos: Vec3;
      heavy: boolean;
      sound: HitSound;
      backstab?: boolean;
    }
  | { t: 'block'; attacker: number; target: number; attack: string; posture: number; pos: Vec3; heavy: boolean }
  | {
      t: 'parry';
      parrier: number;
      attacker: number;
      pos: Vec3;
      kind: 'parry' | 'flash' | 'redirect';
      /** frames between the block press and impact (for training feedback) */
      timing: number;
      window: number;
    }
  | { t: 'counter'; kind: 'stomp' | 'leap' | 'evade'; by: number; on: number; pos: Vec3 }
  | { t: 'evade'; f: number; attacker: number }
  | { t: 'disarm'; victim: number; by: number; pos: Vec3; reason: 'parried' | 'blocked' | 'redirect' }
  | { t: 'stagger'; f: number }
  | { t: 'dodge'; f: number; back: boolean }
  | { t: 'jump'; f: number }
  | { t: 'land'; f: number }
  | { t: 'step'; f: number }
  | { t: 'ko'; loser: number; winner: number }
  | { t: 'ultReady'; f: number }
  | { t: 'ultStart'; f: number; ult: string }
  | { t: 'ultChoice'; f: number }
  | { t: 'ultWave'; f: number; kind: 'vertical' | 'horizontal'; pos: Vec3; yaw: number }
  | { t: 'ultDash'; f: number }
  | { t: 'ultImpale'; f: number; target: number }
  | { t: 'ultBurst'; f: number; pos: Vec3 }
  | { t: 'ultLightning'; f: number; from: Vec3; to: Vec3 }
  | { t: 'recall'; f: number }
  | { t: 'pickup'; f: number }
  | { t: 'weaponBounce'; owner: number; pos: Vec3; speed: number }
  | { t: 'counterReady'; f: number }
  | { t: 'backstabReady'; f: number }
  | { t: 'whiff'; f: number; attack: string }
  | { t: 'parryEarly'; f: number; frames: number }
  | { t: 'roundStart'; round: number }
  | { t: 'fight'; round: number }
  | { t: 'roundOver'; winner: number; wins: [number, number]; perfect: boolean }
  | { t: 'matchOver'; winner: number };
