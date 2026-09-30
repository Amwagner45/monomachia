// Menu-facing descriptions of weapons and abilities.
import type { WeaponId } from '../sim/moves/types';

export const WEAPON_INFO: Record<Exclude<WeaponId, 'fists'>, {
  kanji: string;
  cls: string;
  stats: { speed: number; power: number; posture: number; reach: number; parry: number };
  ultimate: string;
  ultDesc: string;
}> = {
  katana: {
    kanji: '刀',
    cls: 'Medium',
    stats: { speed: 0.65, power: 0.55, posture: 0.55, reach: 0.6, parry: 0.6 },
    ultimate: 'Moonsplitter',
    ultDesc: 'Sheathe, then release a stage-length slash. Tilt up/down for vertical, left/right for horizontal (it can be jumped).',
  },
  greatsword: {
    kanji: '大剣',
    cls: 'Colossal',
    stats: { speed: 0.3, power: 0.95, posture: 0.9, reach: 0.85, parry: 0.85 },
    ultimate: 'Impaler',
    ultDesc: 'Take aim and dash across the stage. On impact, press heavy to detonate a burst of energy.',
  },
  daggers: {
    kanji: '双短刀',
    cls: 'Small',
    stats: { speed: 0.95, power: 0.45, posture: 0.3, reach: 0.35, parry: 0.35 },
    ultimate: 'Lightning Tempest',
    ultDesc: 'Flash to the opponent and spin through six strikes. Each spin can be parried.',
  },
};

export const ABILITY_INFO: Record<string, { name: string; desc: string }> = {
  k_flash: { name: 'Flash', desc: 'Parry stance with a wide window. Stuns the attacker.' },
  k_thrust: { name: 'Piercing Thrust', desc: 'Unblockable thrust. Counter: dodge into it.' },
  k_sweep: { name: 'Swallow Sweep', desc: 'Unblockable low cut. Counter: jump.' },
  g_sweep: { name: 'Reaping Sweep', desc: 'Unblockable wide sweep. Counter: jump.' },
  g_slam: { name: 'Mountain Slam', desc: 'Unblockable overhead slam. Counter: back-dash.' },
  g_crush: { name: 'Guard Crusher', desc: 'Shoulder bash that crushes posture through a block.' },
  d_sweep: { name: 'Serpent Sweep', desc: 'Dashing low sweep, unblockable. Counter: jump.' },
  d_shadow: { name: 'Shadow Step', desc: 'Blink behind them. Your next light attack backstabs.' },
  d_needle: { name: 'Needle Thrust', desc: 'Quick unblockable thrust. Counter: dodge into it.' },
};

export const TRAINING_BEHAVIOURS: { id: string; label: string; needs?: WeaponId[] }[] = [
  { id: 'idle', label: 'Stand still' },
  { id: 'block', label: 'Block' },
  { id: 'lights', label: 'Light chains' },
  { id: 'heavies', label: 'Heavies' },
  { id: 'thrust', label: 'Thrust', needs: ['katana', 'daggers'] },
  { id: 'sweep', label: 'Sweep' },
  { id: 'slam', label: 'Slam', needs: ['greatsword'] },
  { id: 'random', label: 'Mixed attacks' },
  { id: 'fight', label: 'Spar' },
];
