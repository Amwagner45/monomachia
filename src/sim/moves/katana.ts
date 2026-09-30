import { AttackDef, WeaponDef, finalizeMoves } from './types';

// Katana — medium class. Balanced, versatile, decent speed.
const moves: Record<string, AttackDef> = {
  k_l1: {
    id: 'k_l1', name: 'Right Cut', kind: 'light', type: 'slash', anim: 'slashRL',
    startup: 11, active: 3, recovery: 16, damage: 6, posture: 7, knockback: 0.35,
    range: 2.2, arc: 110, lunge: 0.35, lungeEnd: 12, chainLight: 'k_l2', chainHeavy: 'k_h1f', dodgeCancelFrom: 20,
  },
  k_l2: {
    id: 'k_l2', name: 'Return Cut', kind: 'light', type: 'slash', anim: 'slashLR',
    startup: 10, active: 3, recovery: 16, damage: 6, posture: 7, knockback: 0.35,
    range: 2.2, arc: 110, lunge: 0.35, lungeEnd: 11, chainLight: 'k_l3', chainHeavy: 'k_h1f', dodgeCancelFrom: 19,
  },
  k_l3: {
    id: 'k_l3', name: 'Crown Cut', kind: 'light', type: 'overhead', anim: 'overhead',
    startup: 14, active: 4, recovery: 22, damage: 8, posture: 10, knockback: 0.6,
    range: 2.3, arc: 60, lunge: 0.5, lungeEnd: 16, chainHeavy: 'k_h2', dodgeCancelFrom: 26,
  },
  k_h1: {
    id: 'k_h1', name: 'Kesa Giri', kind: 'heavy', type: 'slash', anim: 'diagDown',
    startup: 22, active: 4, recovery: 26, damage: 13, posture: 16, knockback: 1.0,
    range: 2.4, arc: 90, lunge: 0.6, lungeStart: 8, lungeEnd: 24, chargeable: true,
    chainLight: 'k_l2', chainHeavy: 'k_h2',
  },
  k_h1f: {
    id: 'k_h1f', name: 'Rising Heaven', kind: 'heavy', type: 'slash', anim: 'diagUp',
    startup: 18, active: 4, recovery: 24, damage: 12, posture: 15, knockback: 0.9,
    range: 2.3, arc: 90, lunge: 0.5, lungeEnd: 20, chainHeavy: 'k_h2',
  },
  k_h2: {
    id: 'k_h2', name: 'Heaven Splitter', kind: 'heavy', type: 'overhead', anim: 'overhead',
    startup: 24, active: 4, recovery: 28, damage: 15, posture: 18, knockback: 1.2,
    range: 2.4, arc: 60, lunge: 0.7, lungeStart: 8, lungeEnd: 26,
  },
  k_sl: {
    id: 'k_sl', name: 'Running Draw', kind: 'light', type: 'slash', anim: 'drawCut',
    startup: 12, active: 4, recovery: 18, damage: 8, posture: 9, knockback: 0.5,
    range: 2.3, arc: 100, lunge: 1.6, lungeEnd: 15,
  },
  k_sh: {
    id: 'k_sh', name: 'Leaping Cleave', kind: 'heavy', type: 'overhead', anim: 'leapCleave',
    startup: 20, active: 5, recovery: 26, damage: 15, posture: 18, knockback: 1.2,
    range: 2.4, arc: 70, lunge: 2.6, lungeStart: 4, lungeEnd: 22, hop: 5,
  },
  k_dl: {
    id: 'k_dl', name: 'Wind Cut', kind: 'light', type: 'slash', anim: 'slashRL',
    startup: 9, active: 3, recovery: 16, damage: 6, posture: 7, knockback: 0.4,
    range: 2.2, arc: 120, lunge: 0.4, dodgeCancelFrom: 18,
  },
  k_dh: {
    id: 'k_dh', name: 'Whirl Cut', kind: 'heavy', type: 'spin', anim: 'spin',
    startup: 18, active: 6, recovery: 24, damage: 12, posture: 14, knockback: 1.0,
    range: 2.3, arc: 360, lunge: 0.3,
  },
  k_bl: {
    id: 'k_bl', name: 'Rising Cut', kind: 'light', type: 'slash', anim: 'diagUp',
    startup: 10, active: 3, recovery: 18, damage: 6, posture: 8, knockback: 0.4,
    range: 2.2, arc: 100, lunge: 0.8,
  },
  k_bh: {
    id: 'k_bh', name: 'Lunging Cut', kind: 'heavy', type: 'slash', anim: 'diagDown',
    startup: 18, active: 4, recovery: 24, damage: 12, posture: 14, knockback: 1.0,
    range: 2.4, arc: 80, lunge: 2.2, lungeStart: 4, lungeEnd: 20,
  },
  k_jl: {
    id: 'k_jl', name: 'Aerial Cut', kind: 'light', type: 'slash', anim: 'airSlash',
    startup: 7, active: 4, recovery: 12, damage: 6, posture: 7, knockback: 0.4,
    range: 2.1, arc: 120, airborne: true,
  },
  k_jh: {
    id: 'k_jh', name: 'Falling Crown', kind: 'heavy', type: 'overhead', anim: 'plunge',
    startup: 12, active: 5, recovery: 18, damage: 13, posture: 16, knockback: 1.0,
    range: 2.3, arc: 80, airborne: true,
  },
  // --- block abilities ---
  k_flash: {
    id: 'k_flash', name: 'Flash', kind: 'ability', type: 'slash', anim: 'flash', special: 'flash',
    startup: 2, active: 18, recovery: 18, damage: 0, posture: 0, knockback: 0,
    range: 0, arc: 0,
  },
  k_thrust: {
    id: 'k_thrust', name: 'Piercing Thrust', kind: 'ability', type: 'thrust', anim: 'thrust',
    startup: 26, active: 4, recovery: 24, damage: 12, posture: 16, knockback: 0.8,
    range: 3.1, arc: 36, lunge: 1.0, lungeStart: 18, lungeEnd: 30,
    unblockable: true, counter: 'thrust', trackStartup: 5, trackActive: 0.5,
  },
  k_sweep: {
    id: 'k_sweep', name: 'Swallow Sweep', kind: 'ability', type: 'sweep', anim: 'sweep',
    startup: 26, active: 5, recovery: 24, damage: 11, posture: 16, knockback: 0.8,
    range: 2.6, arc: 150, lunge: 0.4, unblockable: true, jumpable: true, counter: 'sweep',
  },
  // --- counter follow-up ---
  k_lunge: {
    id: 'k_lunge', name: 'Counter Lunge', kind: 'light', type: 'slash', anim: 'drawCut',
    special: 'counterLunge', startup: 6, active: 3, recovery: 18, damage: 10, posture: 22,
    knockback: 0.8, range: 2.2, arc: 100, lunge: 0, lungeEnd: 8, trail: 'ult',
  },
};

export const KATANA: WeaponDef = {
  id: 'katana',
  name: 'Katana',
  cls: 'medium',
  speedMult: 1.0,
  dodgeMult: 1.0,
  parryWindow: 9,
  blockMitigation: 0.7,
  moves: finalizeMoves(moves),
  lightStart: 'k_l1',
  heavyStart: 'k_h1',
  sprintLight: 'k_sl',
  sprintHeavy: 'k_sh',
  dodgeLight: 'k_dl',
  dodgeHeavy: 'k_dh',
  backLight: 'k_bl',
  backHeavy: 'k_bh',
  jumpLight: 'k_jl',
  jumpHeavy: 'k_jh',
  abilities: ['k_flash', 'k_thrust', 'k_sweep'],
  defaultAbilities: ['k_flash', 'k_thrust'],
  ultimate: 'moonsplitter',
  reach: 2.1,
  blurb: 'Balanced and versatile. Flash parries with a wide window and stuns.',
};
