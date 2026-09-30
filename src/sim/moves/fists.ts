import { AttackDef, WeaponDef, finalizeMoves } from './types';

// Bare hands — used by any fighter after being disarmed.
// Low HP damage, high posture damage, extra knockback.
const F = 'fist' as const;
const moves: Record<string, AttackDef> = {
  f_l1: {
    id: 'f_l1', name: 'Jab', kind: 'light', type: 'punch', anim: 'f_jab', hand: 'L', sound: F,
    startup: 5, active: 2, recovery: 10, damage: 3, posture: 8, knockback: 0.5,
    range: 1.3, arc: 90, lunge: 0.3, chainLight: 'f_l2', chainHeavy: 'f_h1', dodgeCancelFrom: 9, hitstun: 16,
  },
  f_l2: {
    id: 'f_l2', name: 'Cross', kind: 'light', type: 'punch', anim: 'f_cross', hand: 'R', sound: F,
    startup: 6, active: 2, recovery: 10, damage: 3, posture: 8, knockback: 0.5,
    range: 1.3, arc: 90, lunge: 0.3, chainLight: 'f_l3', chainHeavy: 'f_h1', dodgeCancelFrom: 10, hitstun: 16,
  },
  f_l3: {
    id: 'f_l3', name: 'Hook', kind: 'light', type: 'punch', anim: 'f_hook', hand: 'L', sound: F,
    startup: 8, active: 3, recovery: 14, damage: 4, posture: 10, knockback: 0.9,
    range: 1.3, arc: 110, lunge: 0.3, chainHeavy: 'f_h1',
  },
  f_h1: {
    id: 'f_h1', name: 'Roundhouse', kind: 'heavy', type: 'kick', anim: 'f_roundhouse', sound: F,
    startup: 14, active: 4, recovery: 20, damage: 6, posture: 16, knockback: 1.6,
    range: 1.5, arc: 110, lunge: 0.4, chargeable: true, chainHeavy: 'f_h2',
  },
  f_h2: {
    id: 'f_h2', name: 'Spinning Heel', kind: 'heavy', type: 'kick', anim: 'f_spinHeel', sound: F,
    startup: 16, active: 4, recovery: 22, damage: 7, posture: 18, knockback: 2.0,
    range: 1.5, arc: 130, lunge: 0.4,
  },
  f_sl: {
    id: 'f_sl', name: 'Flying Knee', kind: 'light', type: 'kick', anim: 'f_flyingKnee', sound: F,
    startup: 8, active: 4, recovery: 16, damage: 5, posture: 12, knockback: 1.5,
    range: 1.3, arc: 100, lunge: 2.2, lungeEnd: 12, hop: 3.5,
  },
  f_sh: {
    id: 'f_sh', name: 'Dragon Kick', kind: 'heavy', type: 'kick', anim: 'f_dragonKick', sound: F,
    startup: 14, active: 5, recovery: 20, damage: 7, posture: 18, knockback: 2.2,
    range: 1.5, arc: 100, lunge: 2.4, lungeEnd: 18,
  },
  f_dl: {
    id: 'f_dl', name: 'Slip Jab', kind: 'light', type: 'punch', anim: 'f_jab', hand: 'L', sound: F,
    startup: 5, active: 2, recovery: 10, damage: 3, posture: 9, knockback: 0.5,
    range: 1.3, arc: 110, lunge: 0.4, dodgeCancelFrom: 9,
  },
  f_dh: {
    id: 'f_dh', name: 'Spinning Backfist', kind: 'heavy', type: 'punch', anim: 'f_backfist', hand: 'R', sound: F,
    startup: 10, active: 3, recovery: 16, damage: 5, posture: 14, knockback: 1.4,
    range: 1.4, arc: 150,
  },
  f_bl: {
    id: 'f_bl', name: 'Snap Kick', kind: 'light', type: 'kick', anim: 'f_snapKick', sound: F,
    startup: 7, active: 3, recovery: 12, damage: 3, posture: 10, knockback: 1.0,
    range: 1.5, arc: 90, lunge: 0.5,
  },
  f_bh: {
    id: 'f_bh', name: 'Lunging Palm', kind: 'heavy', type: 'punch', anim: 'f_palm', hand: 'R', sound: F,
    startup: 12, active: 4, recovery: 16, damage: 5, posture: 16, knockback: 1.6,
    range: 1.4, arc: 90, lunge: 1.8, lungeEnd: 14,
  },
  f_jl: {
    id: 'f_jl', name: 'Air Kick', kind: 'light', type: 'kick', anim: 'f_airKick', sound: F,
    startup: 7, active: 3, recovery: 12, damage: 4, posture: 10, knockback: 1.0,
    range: 1.4, arc: 110, airborne: true,
  },
  f_jh: {
    id: 'f_jh', name: 'Axe Kick', kind: 'heavy', type: 'kick', anim: 'f_axeKick', sound: F,
    startup: 12, active: 4, recovery: 18, damage: 6, posture: 16, knockback: 1.4,
    range: 1.5, arc: 100, airborne: true,
  },
  f_lunge: {
    id: 'f_lunge', name: 'Counter Lunge', kind: 'light', type: 'punch', anim: 'f_palm', hand: 'R', sound: F,
    special: 'counterLunge', startup: 5, active: 3, recovery: 14, damage: 6, posture: 24,
    knockback: 1.4, range: 1.4, arc: 100, lunge: 0, lungeEnd: 7, trail: 'ult',
  },
  f_breaker: {
    id: 'f_breaker', name: 'Breaker Palm', kind: 'ultimate', type: 'punch', anim: 'f_breakerPalm', hand: 'R',
    sound: F, special: 'breakerPalm', startup: 14, active: 3, recovery: 26, damage: 6, posture: 50,
    knockback: 1.8, range: 1.5, arc: 90, lunge: 2.5, lungeEnd: 15, power: true, hitstop: 12, hitstun: 36,
  },
};

export const FISTS: WeaponDef = {
  id: 'fists',
  name: 'Bare Hands',
  cls: 'fists',
  speedMult: 1.0,
  dodgeMult: 1.0,
  parryWindow: 8, // the Redirect counter's timing window
  blockMitigation: 1,
  moves: finalizeMoves(moves),
  lightStart: 'f_l1',
  heavyStart: 'f_h1',
  sprintLight: 'f_sl',
  sprintHeavy: 'f_sh',
  dodgeLight: 'f_dl',
  dodgeHeavy: 'f_dh',
  backLight: 'f_bl',
  backHeavy: 'f_bh',
  jumpLight: 'f_jl',
  jumpHeavy: 'f_jh',
  abilities: [],
  defaultAbilities: ['', ''],
  ultimate: 'disarmed',
  reach: 1.2,
  blurb: 'Punches and kicks: little damage, heavy posture damage, big knockback.',
};
