import { AttackDef, WeaponDef, finalizeMoves } from './types';

// Greatsword — colossal class. Slow and crushing, big knockback, sweeps and slams.
const C = 'colossal' as const;
const moves: Record<string, AttackDef> = {
  g_l1: {
    id: 'g_l1', name: 'Heavy Swing', kind: 'light', type: 'slash', anim: 'slashRL', sound: C,
    startup: 14, active: 4, recovery: 22, damage: 9, posture: 11, knockback: 0.8,
    range: 3.0, arc: 120, lunge: 0.4, lungeEnd: 15, chainLight: 'g_l2', chainHeavy: 'g_h2', dodgeCancelFrom: 26,
  },
  g_l2: {
    id: 'g_l2', name: 'Backswing', kind: 'light', type: 'slash', anim: 'slashLR', sound: C,
    startup: 13, active: 4, recovery: 22, damage: 9, posture: 11, knockback: 0.8,
    range: 3.0, arc: 120, lunge: 0.4, lungeEnd: 14, chainHeavy: 'g_h2', dodgeCancelFrom: 25,
  },
  g_h1: {
    id: 'g_h1', name: 'Crushing Blow', kind: 'heavy', type: 'slash', anim: 'diagDown', sound: C,
    startup: 26, active: 5, recovery: 32, damage: 18, posture: 22, knockback: 1.6,
    range: 3.1, arc: 90, lunge: 0.7, lungeStart: 10, lungeEnd: 30, chargeable: true,
    chainHeavy: 'g_h2', chainLight: 'g_l2', hitstop: 9,
  },
  g_h2: {
    id: 'g_h2', name: 'Earthbreaker', kind: 'heavy', type: 'overhead', anim: 'overhead', sound: C,
    startup: 30, active: 5, recovery: 34, damage: 20, posture: 24, knockback: 2.0,
    range: 3.0, arc: 60, lunge: 0.8, lungeStart: 10, lungeEnd: 32, hitstop: 10,
  },
  g_sl: {
    id: 'g_sl', name: 'Shoulder Charge', kind: 'light', type: 'bash', anim: 'bash', sound: 'fist',
    startup: 10, active: 6, recovery: 20, damage: 5, posture: 14, knockback: 1.3,
    range: 1.5, arc: 100, lunge: 2.2, lungeEnd: 16,
  },
  g_sh: {
    id: 'g_sh', name: 'Leaping Smash', kind: 'heavy', type: 'overhead', anim: 'leapCleave', sound: C,
    startup: 26, active: 5, recovery: 32, damage: 18, posture: 22, knockback: 1.8,
    range: 3.0, arc: 70, lunge: 3.0, lungeStart: 6, lungeEnd: 28, hop: 5.5, hitstop: 10,
  },
  g_dl: {
    id: 'g_dl', name: 'Pommel Strike', kind: 'light', type: 'bash', anim: 'pommel', sound: 'fist',
    startup: 12, active: 3, recovery: 18, damage: 6, posture: 12, knockback: 0.8,
    range: 1.7, arc: 90, lunge: 0.6,
  },
  g_dh: {
    id: 'g_dh', name: 'Cyclone', kind: 'heavy', type: 'spin', anim: 'spin', sound: C,
    startup: 24, active: 8, recovery: 30, damage: 14, posture: 18, knockback: 1.4,
    range: 2.9, arc: 360,
  },
  g_bl: {
    id: 'g_bl', name: 'Rising Edge', kind: 'light', type: 'slash', anim: 'diagUp', sound: C,
    startup: 14, active: 4, recovery: 20, damage: 8, posture: 10, knockback: 0.7,
    range: 2.8, arc: 110, lunge: 0.9,
  },
  g_bh: {
    id: 'g_bh', name: 'Lunge Cleave', kind: 'heavy', type: 'slash', anim: 'diagDown', sound: C,
    startup: 24, active: 5, recovery: 28, damage: 14, posture: 18, knockback: 1.5,
    range: 3.0, arc: 80, lunge: 2.2, lungeStart: 6, lungeEnd: 26,
  },
  g_jl: {
    id: 'g_jl', name: 'Aerial Chop', kind: 'light', type: 'slash', anim: 'airSlash', sound: C,
    startup: 12, active: 4, recovery: 18, damage: 9, posture: 10, knockback: 0.7,
    range: 2.7, arc: 120, airborne: true,
  },
  g_jh: {
    id: 'g_jh', name: 'Meteor Drop', kind: 'heavy', type: 'overhead', anim: 'plunge', sound: C,
    startup: 20, active: 6, recovery: 30, damage: 18, posture: 24, knockback: 1.8,
    range: 2.8, arc: 110, airborne: true, hitstop: 10,
  },
  // --- block abilities ---
  g_sweep: {
    id: 'g_sweep', name: 'Reaping Sweep', kind: 'ability', type: 'sweep', anim: 'sweep', sound: C,
    startup: 28, active: 6, recovery: 28, damage: 14, posture: 18, knockback: 1.0,
    range: 3.0, arc: 160, lunge: 0.3, unblockable: true, jumpable: true, counter: 'sweep',
  },
  g_slam: {
    id: 'g_slam', name: 'Mountain Slam', kind: 'ability', type: 'slam', anim: 'slam', sound: C,
    startup: 32, active: 5, recovery: 36, damage: 20, posture: 26, knockback: 1.6,
    range: 3.2, arc: 44, lunge: 0.6, lungeStart: 12, lungeEnd: 34,
    unblockable: true, counter: 'slam', hitstop: 12,
  },
  g_crush: {
    id: 'g_crush', name: 'Guard Crusher', kind: 'ability', type: 'bash', anim: 'bash', sound: 'fist',
    startup: 14, active: 5, recovery: 22, damage: 4, posture: 20, knockback: 1.2,
    range: 1.6, arc: 100, lunge: 1.6, lungeEnd: 18, guardCrush: 1.6,
  },
  g_lunge: {
    id: 'g_lunge', name: 'Counter Lunge', kind: 'light', type: 'slash', anim: 'drawCut', sound: C,
    special: 'counterLunge', startup: 8, active: 3, recovery: 22, damage: 12, posture: 24,
    knockback: 1.2, range: 2.7, arc: 100, lunge: 0, lungeEnd: 10, trail: 'ult',
  },
};

export const GREATSWORD: WeaponDef = {
  id: 'greatsword',
  name: 'Greatsword',
  cls: 'colossal',
  speedMult: 0.9,
  dodgeMult: 0.95,
  parryWindow: 12,
  blockMitigation: 0.6,
  moves: finalizeMoves(moves),
  lightStart: 'g_l1',
  heavyStart: 'g_h1',
  sprintLight: 'g_sl',
  sprintHeavy: 'g_sh',
  dodgeLight: 'g_dl',
  dodgeHeavy: 'g_dh',
  backLight: 'g_bl',
  backHeavy: 'g_bh',
  jumpLight: 'g_jl',
  jumpHeavy: 'g_jh',
  abilities: ['g_sweep', 'g_slam', 'g_crush'],
  defaultAbilities: ['g_sweep', 'g_slam'],
  ultimate: 'impaler',
  reach: 2.75,
  blurb: 'Slow and crushing. Huge knockback, sweeps and overhead slams.',
};
