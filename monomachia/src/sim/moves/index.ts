import { KATANA } from './katana';
import { GREATSWORD } from './greatsword';
import { DAGGERS } from './daggers';
import { FISTS } from './fists';
import { AttackDef, WeaponDef, WeaponId, finalizeMoves } from './types';

export * from './types';
export { KATANA, GREATSWORD, DAGGERS, FISTS };

export const WEAPONS: Record<WeaponId, WeaponDef> = {
  katana: KATANA,
  greatsword: GREATSWORD,
  daggers: DAGGERS,
  fists: FISTS,
};

export const PLAYABLE_WEAPONS: WeaponId[] = ['katana', 'greatsword', 'daggers'];

/** Counter-lunge follow-up (after the back-dash counter) per weapon. */
export const COUNTER_LUNGE: Record<WeaponId, string> = {
  katana: 'k_lunge',
  greatsword: 'g_lunge',
  daggers: 'd_lunge',
  fists: 'f_lunge',
};

// Hits dealt by scripted ultimates. They run through the same hit pipeline as
// ordinary attacks, so parry/block/i-frame rules apply consistently.
export const ULT_HITS: Record<string, AttackDef> = finalizeMoves({
  u_moon_v: {
    id: 'u_moon_v', name: 'Moonsplitter', kind: 'ultimate', type: 'slash', anim: 'ult',
    startup: 0, active: 1, recovery: 0, damage: 30, posture: 40, knockback: 2.2,
    range: 30, arc: 360, unblockable: true, undodgeable: true, hitstun: 50, hitstop: 12,
  },
  u_moon_h: {
    id: 'u_moon_h', name: 'Moonsplitter', kind: 'ultimate', type: 'sweep', anim: 'ult',
    startup: 0, active: 1, recovery: 0, damage: 30, posture: 40, knockback: 2.2,
    range: 30, arc: 360, unblockable: true, undodgeable: true, jumpable: true, hitstun: 50, hitstop: 12,
  },
  u_impale: {
    id: 'u_impale', name: 'Impaler', kind: 'ultimate', type: 'thrust', anim: 'ult', sound: 'colossal',
    startup: 0, active: 1, recovery: 0, damage: 15, posture: 20, knockback: 0,
    range: 2, arc: 60, unblockable: true, undodgeable: false, hitstun: 60, hitstop: 12,
  },
  u_burst: {
    id: 'u_burst', name: 'Impaler Burst', kind: 'ultimate', type: 'thrust', anim: 'ult', sound: 'colossal',
    startup: 0, active: 1, recovery: 0, damage: 20, posture: 30, knockback: 4.5,
    range: 3, arc: 360, unblockable: true, undodgeable: true, hitstun: 55, hitstop: 14,
  },
  u_tempest: {
    id: 'u_tempest', name: 'Lightning Tempest', kind: 'ultimate', type: 'spin', anim: 'ult', sound: 'dagger',
    startup: 0, active: 1, recovery: 0, damage: 5, posture: 5, knockback: 0.05,
    range: 2.2, arc: 360, hitstun: 16, blockstun: 12, hitstop: 3,
  },
  u_tempest_final: {
    id: 'u_tempest_final', name: 'Thunder Finisher', kind: 'ultimate', type: 'slash', anim: 'ult', sound: 'dagger',
    startup: 0, active: 1, recovery: 0, damage: 8, posture: 10, knockback: 2.5,
    range: 2.4, arc: 360, hitstun: 36, blockstun: 18, hitstop: 10,
  },
});

export function getMove(weapon: WeaponDef, id: string): AttackDef {
  const m = weapon.moves[id] ?? ULT_HITS[id];
  if (!m) throw new Error(`Unknown move ${id} for ${weapon.id}`);
  return m;
}
