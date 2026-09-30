import { AttackDef, WeaponDef, finalizeMoves } from './types';

// Twin Daggers — small class. Fast, slippery, strong HP damage over many hits,
// weak posture damage, short parry window.
const D = 'dagger' as const;
const moves: Record<string, AttackDef> = {
  d_l1: {
    id: 'd_l1', name: 'Quick Slice', kind: 'light', type: 'slash', anim: 'slashRL', hand: 'R', sound: D,
    startup: 7, active: 2, recovery: 13, damage: 4, posture: 4, knockback: 0.2,
    range: 1.8, arc: 110, lunge: 0.3, chainLight: 'd_l2', chainHeavy: 'd_h1', dodgeCancelFrom: 13,
  },
  d_l2: {
    id: 'd_l2', name: 'Off-hand Slice', kind: 'light', type: 'slash', anim: 'slashRL', hand: 'L', sound: D,
    startup: 7, active: 2, recovery: 13, damage: 4, posture: 4, knockback: 0.2,
    range: 1.8, arc: 110, lunge: 0.3, chainLight: 'd_l3', chainHeavy: 'd_h1', dodgeCancelFrom: 13,
  },
  d_l3: {
    id: 'd_l3', name: 'Twin Rip', kind: 'light', type: 'slash', anim: 'cross', hand: 'both', sound: D,
    startup: 9, active: 3, recovery: 14, damage: 6, posture: 5, knockback: 0.3,
    range: 1.8, arc: 100, lunge: 0.4, chainLight: 'd_l4', chainHeavy: 'd_h1', dodgeCancelFrom: 16,
  },
  d_l4: {
    id: 'd_l4', name: 'Flurry Finisher', kind: 'light', type: 'stab', anim: 'doubleStab', hand: 'both', sound: D,
    startup: 11, active: 3, recovery: 18, damage: 7, posture: 6, knockback: 0.6,
    range: 1.9, arc: 70, lunge: 0.6, chainHeavy: 'd_h2',
  },
  d_h1: {
    id: 'd_h1', name: 'Twin Fang', kind: 'heavy', type: 'stab', anim: 'doubleStab', hand: 'both', sound: D,
    startup: 16, active: 3, recovery: 20, damage: 10, posture: 9, knockback: 0.6,
    range: 1.9, arc: 70, lunge: 0.8, chargeable: true, chainHeavy: 'd_h2', chainLight: 'd_l1',
  },
  d_h2: {
    id: 'd_h2', name: 'Gutting Spiral', kind: 'heavy', type: 'spin', anim: 'spin', hand: 'both', sound: D,
    startup: 18, active: 5, recovery: 22, damage: 12, posture: 10, knockback: 0.9,
    range: 1.9, arc: 360, lunge: 0.4,
  },
  d_sl: {
    id: 'd_sl', name: 'Slide Slash', kind: 'light', type: 'slash', anim: 'slideSlash', hand: 'R', sound: D,
    startup: 8, active: 3, recovery: 14, damage: 6, posture: 5, knockback: 0.4,
    range: 1.9, arc: 110, lunge: 2.0, lungeEnd: 11,
  },
  d_sh: {
    id: 'd_sh', name: 'Pounce', kind: 'heavy', type: 'stab', anim: 'pounce', hand: 'both', sound: D,
    startup: 14, active: 4, recovery: 20, damage: 11, posture: 9, knockback: 0.8,
    range: 1.9, arc: 80, lunge: 3.0, lungeStart: 2, lungeEnd: 16, hop: 4,
  },
  d_dl: {
    id: 'd_dl', name: 'Ghost Cut', kind: 'light', type: 'slash', anim: 'slashRL', hand: 'R', sound: D,
    startup: 6, active: 2, recovery: 12, damage: 5, posture: 4, knockback: 0.2,
    range: 1.8, arc: 120, lunge: 0.4, dodgeCancelFrom: 12,
  },
  d_dh: {
    id: 'd_dh', name: 'Reverse Spin', kind: 'heavy', type: 'spin', anim: 'spin', hand: 'both', sound: D,
    startup: 12, active: 4, recovery: 16, damage: 9, posture: 7, knockback: 0.6,
    range: 1.9, arc: 360,
  },
  d_bl: {
    id: 'd_bl', name: 'Flick', kind: 'light', type: 'slash', anim: 'slashLR', hand: 'L', sound: D,
    startup: 7, active: 2, recovery: 12, damage: 4, posture: 4, knockback: 0.2,
    range: 1.8, arc: 110, lunge: 0.5,
  },
  d_bh: {
    id: 'd_bh', name: 'Rebound Lunge', kind: 'heavy', type: 'stab', anim: 'doubleStab', hand: 'both', sound: D,
    startup: 12, active: 4, recovery: 18, damage: 10, posture: 8, knockback: 0.6,
    range: 1.9, arc: 70, lunge: 2.5, lungeStart: 2, lungeEnd: 14,
  },
  d_jl: {
    id: 'd_jl', name: 'Air Slash', kind: 'light', type: 'slash', anim: 'airSlash', hand: 'R', sound: D,
    startup: 7, active: 3, recovery: 12, damage: 5, posture: 4, knockback: 0.3,
    range: 1.8, arc: 120, airborne: true,
  },
  d_jh: {
    id: 'd_jh', name: 'Dive Stab', kind: 'heavy', type: 'stab', anim: 'plunge', hand: 'both', sound: D,
    startup: 12, active: 4, recovery: 18, damage: 10, posture: 9, knockback: 0.6,
    range: 1.9, arc: 90, airborne: true,
  },
  // --- block abilities ---
  d_sweep: {
    id: 'd_sweep', name: 'Serpent Sweep', kind: 'ability', type: 'sweep', anim: 'sweep', hand: 'R', sound: D,
    startup: 20, active: 5, recovery: 22, damage: 10, posture: 12, knockback: 0.6,
    range: 2.0, arc: 150, lunge: 2.5, lungeStart: 10, lungeEnd: 25,
    unblockable: true, jumpable: true, counter: 'sweep',
  },
  d_shadow: {
    id: 'd_shadow', name: 'Shadow Step', kind: 'ability', type: 'slash', anim: 'shadowStep', special: 'shadowStep',
    startup: 5, active: 14, recovery: 8, damage: 0, posture: 0, knockback: 0,
    range: 0, arc: 0, invuln: [0, 20],
  },
  d_needle: {
    id: 'd_needle', name: 'Needle Thrust', kind: 'ability', type: 'thrust', anim: 'thrust', hand: 'R', sound: D,
    startup: 20, active: 3, recovery: 20, damage: 10, posture: 12, knockback: 0.5,
    range: 2.4, arc: 34, lunge: 0.8, lungeStart: 12, lungeEnd: 23,
    unblockable: true, counter: 'thrust', trackActive: 0.5,
  },
  d_lunge: {
    id: 'd_lunge', name: 'Counter Lunge', kind: 'light', type: 'stab', anim: 'pounce', hand: 'both', sound: D,
    special: 'counterLunge', startup: 5, active: 3, recovery: 16, damage: 10, posture: 18,
    knockback: 0.6, range: 1.9, arc: 100, lunge: 0, lungeEnd: 7, trail: 'ult',
  },
};

export const DAGGERS: WeaponDef = {
  id: 'daggers',
  name: 'Twin Daggers',
  cls: 'small',
  speedMult: 1.12,
  dodgeMult: 1.2,
  parryWindow: 6,
  blockMitigation: 0.8,
  moves: finalizeMoves(moves),
  lightStart: 'd_l1',
  heavyStart: 'd_h1',
  sprintLight: 'd_sl',
  sprintHeavy: 'd_sh',
  dodgeLight: 'd_dl',
  dodgeHeavy: 'd_dh',
  backLight: 'd_bl',
  backHeavy: 'd_bh',
  jumpLight: 'd_jl',
  jumpHeavy: 'd_jh',
  abilities: ['d_sweep', 'd_shadow', 'd_needle'],
  defaultAbilities: ['d_sweep', 'd_shadow'],
  ultimate: 'tempest',
  reach: 1.6,
  blurb: 'Fast and slippery. Many quick hits, long dodges, a short parry window.',
};
