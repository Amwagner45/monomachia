// Pose library and animator. A pose places the hands, weapon direction, feet
// and torso in the fighter's local frame (r = right, u = up, f = forward);
// the rig solves elbows and knees with IK. Attack animations are three
// keyframes per move (wind-up, impact, follow-through) timed to the simulation.

import type { Fighter } from '../sim/fighter';
import type { WeaponId } from '../sim/moves/types';
import { MOVE } from '../sim/constants';

export type V = [number, number, number];

export interface Pose {
  dy: number; // pelvis height offset
  lean: number; // torso pitch forward (rad)
  twist: number; // torso yaw, + = turn right
  roll: number; // torso roll, + = lean right
  bodyYaw: number; // whole-body yaw offset, + = turn right
  bodyPitch: number; // whole-body pitch, + = fall backward
  rh: V; // right hand target
  rd: V; // right blade direction
  lh: V;
  ld: V;
  twoHanded: number; // 1 = left hand grips below the right hand on one weapon
  fl: V; // left ankle target
  fr: V; // right ankle target
  step: number; // front foot forward offset (m)
  head: number; // head pitch (+ = look down)
}

type KF = Partial<Pose>;

// ------------------------------------------------------------------ vector utils

const vlerp = (a: V, b: V, t: number): V => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

function vnorm(a: V): V {
  const l = Math.hypot(a[0], a[1], a[2]) || 1;
  return [a[0] / l, a[1] / l, a[2] / l];
}

/** Spherical interpolation between two directions (keeps swings on an arc). */
export function vslerp(a0: V, b0: V, t: number): V {
  const a = vnorm(a0);
  const b = vnorm(b0);
  let dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  dot = Math.max(-1, Math.min(1, dot));
  if (dot > 0.9995) return vnorm(vlerp(a, b, t));
  if (dot < -0.9995) {
    // pick a perpendicular through "up"
    const mid: V = vnorm([-a[2], 0.6, a[0]]);
    return t < 0.5 ? vslerp(a, mid, t * 2) : vslerp(mid, b, (t - 0.5) * 2);
  }
  const om = Math.acos(dot);
  const s = Math.sin(om);
  const k0 = Math.sin((1 - t) * om) / s;
  const k1 = Math.sin(t * om) / s;
  return [a[0] * k0 + b[0] * k1, a[1] * k0 + b[1] * k1, a[2] * k0 + b[2] * k1];
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const clamp01 = (t: number) => (t < 0 ? 0 : t > 1 ? 1 : t);
const smooth = (t: number) => t * t * (3 - 2 * t);
const easeOut = (t: number) => 1 - (1 - t) * (1 - t);
const easeIn = (t: number) => t * t;

export function clonePose(p: Pose): Pose {
  return {
    ...p,
    rh: [...p.rh] as V,
    rd: [...p.rd] as V,
    lh: [...p.lh] as V,
    ld: [...p.ld] as V,
    fl: [...p.fl] as V,
    fr: [...p.fr] as V,
  };
}

/** Blend a full pose toward a partial keyframe. */
export function mixPose(a: Pose, b: KF, t: number): Pose {
  const o = clonePose(a);
  if (t <= 0) return o;
  const n = (k: 'dy' | 'lean' | 'twist' | 'roll' | 'bodyYaw' | 'bodyPitch' | 'twoHanded' | 'step' | 'head') => {
    const v = b[k];
    if (v !== undefined) o[k] = lerp(a[k], v, t);
  };
  n('dy');
  n('lean');
  n('twist');
  n('roll');
  n('bodyYaw');
  n('bodyPitch');
  n('twoHanded');
  n('step');
  n('head');
  if (b.rh) o.rh = vlerp(a.rh, b.rh, t);
  if (b.lh) o.lh = vlerp(a.lh, b.lh, t);
  if (b.rd) o.rd = vslerp(a.rd, b.rd, t);
  if (b.ld) o.ld = vslerp(a.ld, b.ld, t);
  if (b.fl) o.fl = vlerp(a.fl, b.fl, t);
  if (b.fr) o.fr = vlerp(a.fr, b.fr, t);
  return o;
}

export function lerpPose(a: Pose, b: Pose, t: number): Pose {
  return mixPose(a, b, t);
}

// ------------------------------------------------------------------ base stances

const ANKLE = 0.07;
export const STANCE_FL: V = [-0.13, ANKLE, 0.17];
export const STANCE_FR: V = [0.15, ANKLE, -0.15];

function P(k: KF): Pose {
  return {
    dy: -0.05,
    lean: 0.04,
    twist: 0,
    roll: 0,
    bodyYaw: 0,
    bodyPitch: 0,
    rh: [0.1, 1.1, 0.3],
    rd: [0, 0.6, 0.8],
    lh: [-0.1, 1.1, 0.3],
    ld: [0, 0.6, 0.8],
    twoHanded: 0,
    fl: [...STANCE_FL] as V,
    fr: [...STANCE_FR] as V,
    step: 0,
    head: 0,
    ...k,
  };
}

export const GRIP_GAP: Record<WeaponId, number> = { katana: 0.17, greatsword: 0.2, daggers: 0, fists: 0 };

const GUARD: Record<WeaponId, Pose> = {
  katana: P({ dy: -0.06, rh: [0.03, 1.08, 0.36], rd: [-0.05, 0.62, 0.78], twoHanded: 1 }),
  greatsword: P({ dy: -0.07, rh: [0.21, 1.2, 0.16], rd: [0.3, 0.56, -0.77], twoHanded: 1, twist: 0.12 }),
  daggers: P({
    dy: -0.09,
    lean: 0.1,
    rh: [0.22, 1.16, 0.32],
    rd: [0.05, 0.32, 0.95],
    lh: [-0.2, 1.28, 0.26],
    ld: [-0.05, 0.55, 0.83],
  }),
  fists: P({ dy: -0.08, lean: 0.06, rh: [0.13, 1.4, 0.24], rd: [0, 1, 0], lh: [-0.1, 1.45, 0.33], ld: [0, 1, 0] }),
};

const BLOCK: Record<WeaponId, KF> = {
  katana: { rh: [0.22, 1.44, 0.36], rd: [-0.95, 0.24, 0.15], twoHanded: 1, lean: -0.04, dy: -0.1 },
  greatsword: { rh: [0.1, 1.06, 0.36], rd: [-0.16, 0.98, 0.12], twoHanded: 1, twist: 0, dy: -0.12 },
  daggers: { rh: [0.08, 1.42, 0.34], rd: [-0.62, 0.72, 0.28], lh: [-0.08, 1.44, 0.34], ld: [0.62, 0.72, 0.28], dy: -0.12 },
  fists: { rh: [0.1, 1.5, 0.3], lh: [-0.1, 1.52, 0.3] },
};

const SPRINT: Record<WeaponId, KF> = {
  katana: { lean: 0.32, rh: [0.3, 1.02, -0.05], rd: [0.3, 0.12, -0.95], twoHanded: 0, lh: [-0.25, 1.1, 0.2] },
  greatsword: { lean: 0.28, rh: [0.28, 1.1, 0.0], rd: [0.35, 0.2, -0.92], twoHanded: 0, lh: [-0.25, 1.1, 0.2] },
  daggers: { lean: 0.38, rh: [0.3, 1.0, -0.2], rd: [0.2, -0.1, -0.97], lh: [-0.3, 1.0, -0.2], ld: [-0.2, -0.1, -0.97] },
  fists: { lean: 0.3 },
};

// ------------------------------------------------------------------ attack archetypes: [wind-up, impact, follow-through]

const TAU = Math.PI * 2;
const TUCK: KF = { fl: [-0.13, 0.42, 0.16], fr: [0.15, 0.36, -0.08] };

const ARCH: Record<string, [KF, KF, KF]> = {
  slashRL: [
    { rh: [0.42, 1.38, 0.02], rd: [0.55, 0.4, -0.73], twist: 0.7, lean: 0.02, dy: -0.08 },
    { rh: [0.05, 1.22, 0.56], rd: [-0.72, 0.05, 0.69], twist: -0.1, lean: 0.14, dy: -0.12, step: 0.12 },
    { rh: [-0.34, 1.12, 0.36], rd: [-0.82, -0.08, -0.56], twist: -0.75, lean: 0.12, dy: -0.11, step: 0.12 },
  ],
  slashLR: [
    { rh: [-0.3, 1.4, 0.18], rd: [-0.62, 0.42, -0.66], twist: -0.7, lean: 0.02, dy: -0.08 },
    { rh: [0.1, 1.22, 0.56], rd: [0.75, 0.05, 0.66], twist: 0.1, lean: 0.14, dy: -0.12, step: 0.12 },
    { rh: [0.46, 1.12, 0.24], rd: [0.85, -0.08, -0.52], twist: 0.75, lean: 0.12, dy: -0.11, step: 0.12 },
  ],
  diagDown: [
    { rh: [0.3, 1.82, -0.05], rd: [0.32, 0.52, -0.79], twist: 0.55, lean: -0.1, dy: -0.05 },
    { rh: [0.06, 1.28, 0.56], rd: [-0.5, -0.25, 0.83], twist: -0.05, lean: 0.2, dy: -0.14, step: 0.2 },
    { rh: [-0.28, 0.88, 0.38], rd: [-0.55, -0.72, 0.42], twist: -0.55, lean: 0.32, dy: -0.2, step: 0.2 },
  ],
  diagUp: [
    { rh: [-0.28, 0.82, 0.32], rd: [-0.55, -0.68, 0.48], twist: -0.5, lean: 0.25, dy: -0.17 },
    { rh: [0.1, 1.32, 0.56], rd: [0.42, 0.52, 0.74], twist: 0.1, lean: 0.1, dy: -0.1, step: 0.15 },
    { rh: [0.34, 1.78, 0.16], rd: [0.35, 0.82, -0.45], twist: 0.45, lean: -0.1, dy: -0.04, step: 0.1 },
  ],
  overhead: [
    { rh: [0.06, 1.98, -0.08], rd: [0.02, 0.35, -0.94], lean: -0.15, dy: -0.04 },
    { rh: [0.03, 1.38, 0.58], rd: [0.0, 0.12, 0.99], lean: 0.16, dy: -0.13, step: 0.2 },
    { rh: [0.02, 0.98, 0.52], rd: [0.0, -0.66, 0.75], lean: 0.34, dy: -0.2, step: 0.2 },
  ],
  thrust: [
    { rh: [0.22, 1.16, -0.18], rd: [0.02, 0.06, 1.0], twist: 0.4, lean: -0.05, dy: -0.15 },
    { rh: [0.03, 1.26, 0.8], rd: [0.0, 0.03, 1.0], twist: -0.12, lean: 0.26, dy: -0.21, step: 0.38 },
    { rh: [0.03, 1.24, 0.74], rd: [0.0, 0.0, 1.0], twist: -0.1, lean: 0.22, dy: -0.21, step: 0.34 },
  ],
  sweep: [
    { rh: [0.5, 0.86, -0.15], rd: [0.62, -0.32, -0.72], twist: 0.8, lean: 0.3, dy: -0.36 },
    { rh: [0.06, 0.62, 0.58], rd: [-0.76, -0.28, 0.58], twist: 0.0, lean: 0.45, dy: -0.42, step: 0.22 },
    { rh: [-0.46, 0.66, 0.2], rd: [-0.8, -0.24, -0.55], twist: -0.8, lean: 0.36, dy: -0.38, step: 0.22 },
  ],
  slam: [
    { rh: [0.02, 2.06, -0.26], rd: [0.0, 0.12, -0.99], lean: -0.25, dy: 0.0 },
    { rh: [0.02, 0.9, 0.66], rd: [0.0, -0.55, 0.83], lean: 0.5, dy: -0.3, step: 0.32 },
    { rh: [0.02, 0.84, 0.64], rd: [0.0, -0.62, 0.78], lean: 0.52, dy: -0.32, step: 0.32 },
  ],
  spin: [
    { rh: [0.45, 1.25, -0.1], rd: [0.7, 0.1, -0.7], twist: 0.6, dy: -0.12, bodyYaw: 0 },
    { rh: [0.05, 1.2, 0.62], rd: [-0.6, 0.0, 0.8], twist: 0, dy: -0.16, bodyYaw: -Math.PI },
    { rh: [-0.3, 1.15, 0.4], rd: [-0.8, 0, -0.5], twist: -0.5, dy: -0.13, bodyYaw: -TAU },
  ],
  bash: [
    { rh: [0.2, 1.15, 0.05], rd: [0.1, 0.6, -0.78], twoHanded: 1, twist: -0.4, lean: 0.1, dy: -0.12 },
    { rh: [0.18, 1.12, 0.12], rd: [0.1, 0.6, -0.78], twist: 0.85, lean: 0.35, dy: -0.18, step: 0.35 },
    { rh: [0.18, 1.12, 0.12], rd: [0.1, 0.6, -0.78], twist: 0.8, lean: 0.3, dy: -0.18, step: 0.35 },
  ],
  pommel: [
    { rh: [0.12, 1.22, 0.12], rd: [0.05, 0.55, -0.83], twist: 0.3 },
    { rh: [0.02, 1.42, 0.58], rd: [0.08, 0.45, -0.89], twist: -0.2, lean: 0.2, step: 0.22 },
    { rh: [0.04, 1.36, 0.5], rd: [0.08, 0.5, -0.86], twist: -0.15, lean: 0.15, step: 0.2 },
  ],
  drawCut: [
    { rh: [-0.28, 1.02, 0.18], rd: [-0.3, -0.25, 0.92], twist: -0.6, lean: 0.25, dy: -0.18 },
    { rh: [0.12, 1.18, 0.6], rd: [0.8, 0.12, 0.58], twist: 0.15, lean: 0.3, dy: -0.2, step: 0.36 },
    { rh: [0.5, 1.25, 0.2], rd: [0.85, 0.2, -0.48], twist: 0.7, lean: 0.25, dy: -0.18, step: 0.3 },
  ],
  leapCleave: [
    { rh: [0.06, 2.0, -0.1], rd: [0.02, 0.3, -0.95], lean: -0.2, dy: -0.1, ...TUCK },
    { rh: [0.03, 1.3, 0.6], rd: [0.0, -0.05, 1.0], lean: 0.3, dy: -0.18, step: 0.3 },
    { rh: [0.02, 0.92, 0.55], rd: [0.0, -0.7, 0.71], lean: 0.42, dy: -0.26, step: 0.3 },
  ],
  airSlash: [
    { rh: [0.42, 1.4, 0.02], rd: [0.55, 0.4, -0.73], twist: 0.7, ...TUCK },
    { rh: [0.05, 1.22, 0.56], rd: [-0.72, 0.0, 0.69], twist: -0.1, lean: 0.14, ...TUCK },
    { rh: [-0.34, 1.1, 0.36], rd: [-0.82, -0.1, -0.56], twist: -0.75, lean: 0.12, ...TUCK },
  ],
  plunge: [
    { rh: [0.03, 1.95, 0.05], rd: [0.0, 0.95, -0.3], lean: -0.1, ...TUCK },
    { rh: [0.03, 1.05, 0.52], rd: [0.0, -0.8, 0.6], lean: 0.35, dy: -0.12 },
    { rh: [0.03, 0.9, 0.5], rd: [0.0, -0.85, 0.52], lean: 0.4, dy: -0.26, step: 0.2 },
  ],
  flash: [
    { rh: [0.08, 1.02, 0.28], rd: [-0.35, 0.28, 0.9], twist: -0.3, lean: 0.12, dy: -0.26, step: 0.25, twoHanded: 1 },
    { rh: [0.08, 1.02, 0.28], rd: [-0.35, 0.28, 0.9], twist: -0.3, lean: 0.12, dy: -0.26, step: 0.25, twoHanded: 1 },
    { rh: [0.08, 1.02, 0.28], rd: [-0.35, 0.28, 0.9], twist: -0.3, lean: 0.12, dy: -0.26, step: 0.25, twoHanded: 1 },
  ],
  shadowStep: [
    { dy: -0.32, lean: 0.45, rh: [0.35, 1.0, -0.25], rd: [0.25, -0.2, -0.95], lh: [-0.35, 1.0, -0.25], ld: [-0.25, -0.2, -0.95] },
    { dy: -0.36, lean: 0.55, rh: [0.35, 0.95, -0.3], rd: [0.25, -0.2, -0.95], lh: [-0.35, 0.95, -0.3], ld: [-0.25, -0.2, -0.95] },
    { dy: -0.2, lean: 0.25, rh: [0.3, 1.1, 0.1], rd: [0.1, 0.2, 0.97], lh: [-0.3, 1.15, 0.1], ld: [-0.1, 0.3, 0.95] },
  ],
  slideSlash: [
    { rh: [0.42, 1.1, 0.0], rd: [0.55, 0.2, -0.8], twist: 0.6, lean: 0.35, dy: -0.34 },
    { rh: [0.05, 0.95, 0.6], rd: [-0.72, -0.05, 0.69], twist: -0.1, lean: 0.4, dy: -0.38, step: 0.35 },
    { rh: [-0.34, 0.95, 0.38], rd: [-0.82, -0.1, -0.56], twist: -0.7, lean: 0.35, dy: -0.36, step: 0.35 },
  ],
  // --- dual-wield (both hands) ---
  cross: [
    { rh: [0.42, 1.55, 0.1], rd: [0.3, 0.9, 0.3], lh: [-0.42, 1.55, 0.1], ld: [-0.3, 0.9, 0.3], lean: -0.05 },
    { rh: [-0.05, 1.15, 0.56], rd: [-0.7, -0.3, 0.65], lh: [0.05, 1.12, 0.56], ld: [0.7, -0.3, 0.65], lean: 0.2, dy: -0.13, step: 0.15 },
    { rh: [-0.3, 0.95, 0.35], rd: [-0.8, -0.5, 0.3], lh: [0.3, 0.95, 0.35], ld: [0.8, -0.5, 0.3], lean: 0.25, dy: -0.15, step: 0.15 },
  ],
  doubleStab: [
    { rh: [0.22, 1.15, -0.15], rd: [0.0, 0.1, 1], lh: [-0.2, 1.2, -0.15], ld: [0, 0.1, 1], lean: -0.05, dy: -0.11 },
    { rh: [0.1, 1.2, 0.7], rd: [0, 0, 1], lh: [-0.1, 1.24, 0.68], ld: [0, 0, 1], lean: 0.26, dy: -0.17, step: 0.3 },
    { rh: [0.1, 1.2, 0.66], rd: [0, 0, 1], lh: [-0.1, 1.24, 0.64], ld: [0, 0, 1], lean: 0.24, dy: -0.17, step: 0.3 },
  ],
  pounce: [
    { dy: -0.32, lean: 0.3, rh: [0.3, 1.3, -0.2], rd: [0.2, 0.6, -0.8], lh: [-0.3, 1.3, -0.2], ld: [-0.2, 0.6, -0.8] },
    { dy: -0.1, lean: 0.42, rh: [0.12, 1.1, 0.62], rd: [0, -0.5, 0.86], lh: [-0.12, 1.1, 0.62], ld: [0, -0.5, 0.86], ...TUCK },
    { dy: -0.22, lean: 0.36, rh: [0.12, 1.05, 0.6], rd: [0, -0.55, 0.83], lh: [-0.12, 1.05, 0.6], ld: [0, -0.55, 0.83], step: 0.3 },
  ],
  spinBoth: [
    { rh: [0.5, 1.3, 0.0], rd: [0.9, 0.1, 0.3], lh: [-0.5, 1.3, 0.0], ld: [-0.9, 0.1, -0.3], twist: 0.5, dy: -0.13, bodyYaw: 0 },
    { rh: [0.58, 1.25, 0.1], rd: [0.95, 0.0, 0.3], lh: [-0.58, 1.25, -0.1], ld: [-0.95, 0.0, -0.3], dy: -0.16, bodyYaw: -Math.PI },
    { rh: [0.5, 1.25, 0.1], rd: [0.95, 0.0, 0.3], lh: [-0.5, 1.25, -0.1], ld: [-0.95, 0.0, -0.3], dy: -0.14, bodyYaw: -TAU },
  ],
  // --- bare hands ---
  f_jab: [
    { lh: [-0.1, 1.44, 0.3], twist: 0.05 },
    { lh: [-0.04, 1.47, 0.72], twist: 0.25, lean: 0.08, step: 0.15 },
    { lh: [-0.06, 1.46, 0.6], twist: 0.2, step: 0.1 },
  ],
  f_cross: [
    { rh: [0.16, 1.4, 0.18], twist: 0.2 },
    { rh: [0.02, 1.47, 0.76], twist: -0.55, lean: 0.12, step: 0.2 },
    { rh: [0.03, 1.45, 0.62], twist: -0.45, step: 0.15 },
  ],
  f_hook: [
    { lh: [-0.4, 1.42, 0.25], twist: -0.35 },
    { lh: [0.05, 1.45, 0.55], twist: 0.55, lean: 0.1 },
    { lh: [0.15, 1.42, 0.35], twist: 0.6 },
  ],
  f_roundhouse: [
    { fr: [0.3, 0.6, 0.05], lean: -0.15, twist: 0.2 },
    { fr: [0.05, 1.25, 0.8], lean: -0.35, twist: -0.6, roll: -0.15 },
    { fr: [-0.2, 1.0, 0.55], lean: -0.3, twist: -0.8 },
  ],
  f_spinHeel: [
    { fr: [0.3, 0.5, -0.1], twist: 0.3, bodyYaw: 0 },
    { fr: [0.05, 1.28, 0.82], lean: -0.3, bodyYaw: -Math.PI },
    { fr: [0.05, 1.1, 0.7], lean: -0.25, bodyYaw: -TAU },
  ],
  f_flyingKnee: [
    { dy: -0.2, lean: 0.1 },
    { fr: [0.08, 0.95, 0.38], fl: [-0.12, 0.3, -0.2], lean: 0.25, rh: [0.2, 1.5, 0.1], lh: [-0.2, 1.5, 0.1] },
    { fr: [0.08, 0.85, 0.35], fl: [-0.12, 0.3, -0.2], lean: 0.2 },
  ],
  f_dragonKick: [
    { fr: [0.1, 0.75, 0.2], lean: -0.1 },
    { fr: [0.05, 1.1, 0.88], lean: -0.3 },
    { fr: [0.05, 1.0, 0.7], lean: -0.25 },
  ],
  f_backfist: [
    { twist: 0.6, rh: [-0.2, 1.4, 0.2], bodyYaw: 0 },
    { rh: [0.62, 1.45, 0.25], bodyYaw: Math.PI },
    { rh: [0.5, 1.42, 0.3], bodyYaw: TAU },
  ],
  f_snapKick: [
    { fr: [0.12, 0.45, 0.2] },
    { fr: [0.06, 0.8, 0.82], lean: -0.15 },
    { fr: [0.08, 0.6, 0.6] },
  ],
  f_palm: [
    { rh: [0.2, 1.25, 0.05], twist: 0.35, dy: -0.12 },
    { rh: [0.02, 1.32, 0.82], twist: -0.35, lean: 0.25, dy: -0.18, step: 0.35 },
    { rh: [0.03, 1.3, 0.75], twist: -0.3, lean: 0.22, dy: -0.18, step: 0.35 },
  ],
  f_airKick: [
    { fr: [0.1, 0.5, 0.1], ...TUCK },
    { fr: [0.05, 0.9, 0.72], fl: [-0.1, 0.45, 0.0], lean: -0.2 },
    { fr: [0.05, 0.8, 0.6], fl: [-0.1, 0.45, 0.0], lean: -0.15 },
  ],
  f_axeKick: [
    { fr: [0.05, 1.9, 0.45], lean: -0.3 },
    { fr: [0.05, 0.9, 0.75], lean: 0.1 },
    { fr: [0.05, 0.6, 0.65], lean: 0.1 },
  ],
  f_breakerPalm: [
    { rh: [0.25, 1.2, -0.1], lh: [-0.2, 1.3, 0.3], twist: 0.5, dy: -0.2 },
    { rh: [0.0, 1.25, 0.88], lh: [-0.2, 1.25, 0.1], twist: -0.5, lean: 0.3, dy: -0.28, step: 0.45 },
    { rh: [0.0, 1.25, 0.85], lh: [-0.2, 1.25, 0.1], twist: -0.45, lean: 0.28, dy: -0.28, step: 0.45 },
  ],
};

/** Map a move's archetype + hand to keyframes (mirroring left-hand moves). */
function archetype(anim: string, hand: string | undefined, weapon: WeaponId): [KF, KF, KF] {
  let key = anim;
  if (weapon === 'daggers' && anim === 'spin') key = 'spinBoth';
  const k = ARCH[key] ?? ARCH.slashRL;
  if (hand === 'L' && !key.startsWith('f_')) return [mirror(k[0]), mirror(k[1]), mirror(k[2])];
  return k;
}

const mv = (v: V | undefined): V | undefined => (v ? [-v[0], v[1], v[2]] : undefined);

function mirror(k: KF): KF {
  const o: KF = { ...k };
  delete o.rh;
  delete o.rd;
  delete o.lh;
  delete o.ld;
  delete o.fl;
  delete o.fr;
  if (k.rh) o.lh = mv(k.rh);
  if (k.rd) o.ld = mv(k.rd);
  if (k.lh) o.rh = mv(k.lh);
  if (k.ld) o.rd = mv(k.ld);
  if (k.fl) o.fr = mv(k.fl);
  if (k.fr) o.fl = mv(k.fr);
  if (k.twist !== undefined) o.twist = -k.twist;
  if (k.roll !== undefined) o.roll = -k.roll;
  if (k.bodyYaw !== undefined) o.bodyYaw = -k.bodyYaw;
  return o;
}

// ------------------------------------------------------------------ animator

export interface AnimState {
  phase: number; // gait phase (rad)
  speed: number; // smoothed ground speed
  vf: number; // smoothed local forward velocity
  vr: number; // smoothed local right velocity
  hitFlip: number;
}

export function newAnimState(): AnimState {
  return { phase: 0, speed: 0, vf: 0, vr: 0, hitFlip: 1 };
}

export interface PoseResult {
  pose: Pose;
  /** identifies the current clip; a change triggers a short cross-fade */
  key: string;
  blend: number;
  /** trail intensity 0..1 and colour class for weapon trails */
  trail: number;
  trailKind: 'normal' | 'danger' | 'ult';
  /** 0..1 glow on the weapon (charge, unblockable wind-up) */
  glow: number;
  glowKind: 'danger' | 'charge' | 'ult';
}

function guardFor(f: Fighter): Pose {
  return clonePose(GUARD[f.armed ? f.weapon.id : 'fists']);
}

function wid(f: Fighter): WeaponId {
  return f.armed ? f.weapon.id : 'fists';
}

/** Two-handed weapons: derive the left hand from the right. */
export function resolveGrip(p: Pose, weapon: WeaponId) {
  const gap = GRIP_GAP[weapon];
  if (p.twoHanded > 0.01 && gap > 0) {
    const lh: V = [p.rh[0] - p.rd[0] * gap, p.rh[1] - p.rd[1] * gap, p.rh[2] - p.rd[2] * gap];
    p.lh = vlerp(p.lh, lh, Math.min(1, p.twoHanded));
    p.ld = p.rd;
  }
}

let atkSerial = new WeakMap<object, number>();
let serialCounter = 0;
function serialOf(o: object) {
  let s = atkSerial.get(o);
  if (s === undefined) {
    s = ++serialCounter;
    atkSerial.set(o, s);
  }
  return s;
}

/**
 * Compute the target pose for a fighter this render frame.
 * `alpha` is the fraction of a simulation frame elapsed since the last step (for smooth timing).
 */
export function computePose(f: Fighter, time: number, dt: number, A: AnimState, alpha = 0): PoseResult {
  const w = wid(f);
  let pose = guardFor(f);
  let key: string = f.state;
  let blend = 0.12;
  let trail = 0;
  let trailKind: PoseResult['trailKind'] = 'normal';
  let glow = 0;
  let glowKind: PoseResult['glowKind'] = 'danger';

  // --- locomotion bookkeeping (local velocity) ---
  const cy = Math.cos(f.yaw);
  const sy = Math.sin(f.yaw);
  const vx = f.vel.x;
  const vz = f.vel.z;
  const vfTarget = vx * sy + vz * cy;
  const vrTarget = -(vx * cy - vz * sy);
  const k = Math.min(1, dt * 14);
  A.vf += (vfTarget - A.vf) * k;
  A.vr += (vrTarget - A.vr) * k;
  A.speed = Math.hypot(A.vf, A.vr);

  const breathe = Math.sin(time * 2.2) * 0.012;

  const applyLocomotion = (p: Pose, amount = 1) => {
    const s = A.speed;
    if (s > 0.15) {
      const stride = Math.min(0.46, 0.13 * s) * amount;
      A.phase += (s / 1.15) * Math.PI * dt;
      const dirF = A.vf / s;
      const dirR = A.vr / s;
      const sL = Math.sin(A.phase);
      const sR = Math.sin(A.phase + Math.PI);
      const lift = Math.min(0.2, 0.05 * s) * amount;
      p.fl = [p.fl[0] + dirR * stride * sL, ANKLE + Math.max(0, Math.cos(A.phase)) * lift, p.fl[2] + dirF * stride * sL];
      p.fr = [p.fr[0] + dirR * stride * sR, ANKLE + Math.max(0, Math.cos(A.phase + Math.PI)) * lift, p.fr[2] + dirF * stride * sR];
      p.dy -= Math.abs(Math.sin(A.phase)) * 0.035 * Math.min(1, s / 4) * amount;
      p.lean += (A.vf / 8) * 0.25 * amount;
      p.roll += (-A.vr / 8) * 0.12 * amount;
      const bob = Math.sin(A.phase * 2) * 0.012 * amount;
      p.rh = [p.rh[0], p.rh[1] + bob, p.rh[2]];
      p.lh = [p.lh[0], p.lh[1] + bob, p.lh[2]];
    } else {
      p.dy += breathe;
      p.rh = [p.rh[0], p.rh[1] + breathe * 0.6, p.rh[2]];
      p.lh = [p.lh[0], p.lh[1] + breathe * 0.6, p.lh[2]];
    }
  };

  const withBlock = (p: Pose, amount: number) => mixPose(p, BLOCK[w], amount);

  switch (f.state) {
    case 'intro':
    case 'free':
    case 'step':
    case 'land': {
      if (f.blocking) {
        pose = withBlock(pose, 1);
        key = 'block';
        blend = 0.07;
      } else if (f.sprintFrames > 4 || A.speed > 5.5) {
        pose = mixPose(pose, SPRINT[w], Math.min(1, (A.speed - 3.5) / 3));
        key = 'sprint';
      } else key = 'free';
      if (f.state === 'land') pose.dy -= 0.12 * (1 - f.sf / MOVE.landRecovery);
      applyLocomotion(pose);
      break;
    }
    case 'blockstun':
      pose = withBlock(pose, 1);
      pose.lean -= 0.14 * (1 - f.sf / Math.max(1, f.stateDur));
      pose.dy -= 0.06;
      key = 'block';
      blend = 0.05;
      break;
    case 'parryAnim': {
      // flick the weapon up and out
      const t = clamp01(f.sf / Math.max(1, f.stateDur));
      const deflect: KF =
        w === 'daggers'
          ? { rh: [0.3, 1.6, 0.3], rd: [0.2, 0.95, -0.2], lh: [-0.3, 1.55, 0.3], ld: [-0.2, 0.95, -0.2] }
          : w === 'fists'
            ? { rh: [0.35, 1.5, 0.35], lh: [-0.3, 1.5, 0.45], twist: -0.3 }
            : { rh: [-0.12, 1.52, 0.46], rd: [0.35, 0.9, 0.25], twoHanded: 1, twist: -0.25 };
      pose = mixPose(pose, deflect, 1 - t * 0.6);
      key = 'parry';
      blend = 0.03;
      break;
    }
    case 'dodge':
    case 'backstep': {
      const dg = f.dodge;
      if (dg) {
        const lf = dg.dirX * sy + dg.dirZ * cy;
        const lr = -(dg.dirX * cy - dg.dirZ * sy);
        const t = clamp01(f.sf / dg.frames);
        const env = Math.sin(Math.min(1, t * 1.3) * Math.PI);
        pose.lean += lf * 0.35 * env;
        pose.roll += -lr * 0.35 * env;
        pose.dy -= 0.2 * env;
        const spread = 0.25 * env;
        pose.fl = [pose.fl[0] - lr * spread - 0.05, ANKLE + 0.12 * env, pose.fl[2] - lf * spread];
        pose.fr = [pose.fr[0] - lr * spread + 0.05, ANKLE + 0.05 * env, pose.fr[2] - lf * spread];
      }
      key = f.state;
      blend = 0.05;
      break;
    }
    case 'jump': {
      const up = f.vel.y;
      pose = mixPose(pose, TUCK, clamp01(0.4 + up * 0.05));
      pose.lean += 0.05;
      key = 'jump';
      blend = 0.08;
      break;
    }
    case 'attack': {
      const a = f.atk!;
      const def = a.def;
      const kf = archetype(def.anim, def.hand, w);
      const S = def.startup;
      const Act = def.active;
      const R = def.recovery + a.extraRecovery;
      const fr = a.frame + (a.charging ? 0 : alpha);
      key = 'atk' + serialOf(a);
      blend = 0.05;
      trailKind = (def.trail ?? 'normal') as PoseResult['trailKind'];
      if (a.charging) {
        // hold the wind-up and tremble
        pose = mixPose(pose, kf[0], 1);
        const tr = Math.min(1, a.chargeFrames / 150);
        const shake = Math.sin(time * 70) * 0.012 * tr;
        pose.rh = [pose.rh[0] + shake, pose.rh[1] + shake, pose.rh[2]];
        pose.dy -= 0.05 * tr;
        glow = 0.3 + tr * 0.7;
        glowKind = 'charge';
      } else if (fr <= S) {
        const t = clamp01(fr / Math.max(1, S));
        pose = mixPose(pose, kf[0], smooth(Math.min(1, t * 1.25)));
        if (def.unblockable) {
          glow = 0.35 + 0.65 * t;
          glowKind = 'danger';
        }
      } else if (fr <= S + Act) {
        const t = clamp01((fr - S) / Math.max(1, Act));
        const mid = mixPose(mixPose(pose, kf[0], 1), kf[1], easeOut(Math.min(1, t * 2)));
        pose = t < 0.5 ? mid : mixPose(mid, kf[2], easeIn((t - 0.5) * 2));
        trail = 1;
        if (def.unblockable) glow = 1;
      } else {
        const t = clamp01((fr - S - Act) / Math.max(1, R));
        const end = mixPose(pose, kf[2], 1);
        // un-spin: treat full turns as zero before blending home
        end.bodyYaw = Math.atan2(Math.sin(end.bodyYaw), Math.cos(end.bodyYaw));
        pose = mixPose(end, guardFor(f), smooth(clamp01((t - 0.25) / 0.75)));
        trail = Math.max(0, 1 - t * 4);
        if (def.unblockable) glow = Math.max(0, 1 - t * 3);
      }
      if (def.special === 'flash') {
        glow = 0.6;
        glowKind = 'charge';
        trail = 0;
      }
      if (def.airborne || f.airborne) pose = mixPose(pose, TUCK, f.airborne ? 0.8 : 0);
      if (!def.anim.startsWith('f_') && def.hand !== 'both' && w === 'daggers') pose.twoHanded = 0;
      break;
    }
    case 'hitstun': {
      const t = clamp01(f.sf / Math.max(1, f.stateDur));
      if (f.sf === 1) A.hitFlip = -A.hitFlip;
      const env = 1 - smooth(t);
      pose.lean -= 0.35 * env;
      pose.twist += 0.3 * A.hitFlip * env;
      pose.roll += 0.1 * A.hitFlip * env;
      pose.dy -= 0.08 * env;
      pose.head = -0.3 * env;
      pose.rh = vlerp(pose.rh, [pose.rh[0] + 0.15, pose.rh[1] + 0.1, pose.rh[2] - 0.25], env);
      pose.lh = vlerp(pose.lh, [pose.lh[0] - 0.2, pose.lh[1] + 0.05, pose.lh[2] - 0.2], env);
      key = 'hit' + (A.hitFlip > 0 ? 'a' : 'b');
      blend = 0.03;
      break;
    }
    case 'recoil': {
      const t = clamp01(f.sf / Math.max(1, f.stateDur));
      const env = 1 - smooth(clamp01((t - 0.3) / 0.7));
      const recoil: KF =
        w === 'daggers'
          ? { rh: [0.45, 1.7, 0.0], rd: [0.5, 0.8, -0.3], lh: [-0.45, 1.6, 0.0], ld: [-0.5, 0.8, -0.3] }
          : { rh: [0.36, 1.72, -0.1], rd: [0.4, 0.8, -0.44], twoHanded: 0.3, lh: [-0.3, 1.3, 0.1] };
      pose = mixPose(pose, { ...recoil, lean: -0.35, twist: 0.4, dy: -0.1, head: -0.25 }, env);
      key = 'recoil';
      blend = 0.03;
      break;
    }
    case 'stunned': {
      const sway = Math.sin(time * 5) * 0.08;
      const stun: KF =
        w === 'fists'
          ? { rh: [0.25, 0.95, 0.2], lh: [-0.25, 0.95, 0.2] }
          : { rh: [0.25, 0.82, 0.3], rd: [0.1, -0.7, 0.7], twoHanded: 0, lh: [-0.25, 0.95, 0.25], ld: [-0.1, -0.7, 0.7] };
      pose = mixPose(pose, { ...stun, lean: 0.42, dy: -0.22, head: 0.4, roll: sway }, 1);
      key = 'stunned';
      blend = 0.08;
      break;
    }
    case 'stagger': {
      const sway = Math.sin(time * 4) * 0.15;
      pose = mixPose(pose, { rh: [0.25, 1.0, 0.2], lh: [-0.25, 1.0, 0.2], lean: 0.3, dy: -0.18, head: 0.35, roll: sway, twist: sway }, 1);
      key = 'stagger';
      blend = 0.1;
      break;
    }
    case 'disarmStagger': {
      const t = clamp01(f.sf / Math.max(1, f.stateDur));
      const env = 1 - smooth(t);
      pose = mixPose(guardFor(f), { rh: [0.45, 1.6, -0.2], lh: [-0.4, 1.5, -0.1], lean: -0.45, dy: -0.12, head: -0.4, twist: 0.3 }, env);
      key = 'disarm';
      blend = 0.03;
      break;
    }
    case 'pickup': {
      const t = clamp01(f.sf / Math.max(1, f.stateDur));
      const env = Math.sin(t * Math.PI);
      pose = mixPose(pose, { rh: [0.15, 0.3, 0.45], lh: [-0.1, 0.6, 0.3], lean: 0.75, dy: -0.42, head: 0.3, step: 0.3 }, env);
      key = 'pickup';
      break;
    }
    case 'stomp': {
      const t = f.sf;
      const up: KF = { fr: [0.08, 0.62, 0.45], lean: -0.1, dy: 0.02 };
      const down: KF = { fr: [0.06, ANKLE, 0.55], lean: 0.2, dy: -0.18 };
      pose = t < 7 ? mixPose(pose, up, t / 7) : mixPose(mixPose(pose, up, 1), down, clamp01((t - 7) / 3));
      if (t > 16) pose = mixPose(pose, guardFor(f), clamp01((t - 16) / 10));
      key = 'stomp';
      blend = 0.04;
      break;
    }
    case 'leap': {
      const t = f.sf;
      pose = mixPose(pose, { ...TUCK, lean: -0.2 }, 1);
      if (t > 8 && t < 16) pose = mixPose(pose, { fr: [0.05, 0.9, 0.7], fl: [-0.1, 0.8, 0.6], lean: -0.45 }, 1);
      key = 'leap';
      blend = 0.04;
      break;
    }
    case 'ult': {
      const u = f.ult!;
      key = 'ult-' + u.phase;
      blend = 0.06;
      trailKind = 'ult';
      glowKind = 'ult';
      glow = 0.8;
      if (u.kind === 'moonsplitter') {
        if (u.phase === 'windup') {
          pose = mixPose(pose, { rh: [-0.2, 1.0, 0.12], rd: [-0.25, -0.3, -0.92], twoHanded: 0, lh: [-0.25, 1.02, 0.22], ld: [-0.25, -0.3, -0.92], dy: -0.32, lean: 0.25, twist: 0.35, step: 0.3 }, 1);
        } else {
          const t = clamp01(u.pf / 10);
          const strike: KF = u.variant === 'vertical'
            ? { rh: [0.03, 1.4, 0.62], rd: [0, 0.2, 0.98], twoHanded: 1, lean: 0.25, dy: -0.25, step: 0.4 }
            : { rh: [0.45, 1.2, 0.3], rd: [0.9, 0.05, -0.4], twoHanded: 0, lean: 0.25, dy: -0.3, twist: 0.8, step: 0.4 };
          pose = mixPose(pose, strike, easeOut(t));
          trail = u.pf < 6 ? 1 : 0;
          if (u.pf > 20) pose = mixPose(pose, guardFor(f), clamp01((u.pf - 20) / 14));
        }
      } else if (u.kind === 'impaler') {
        const aim: KF = { rh: [0.25, 1.2, -0.3], rd: [0.02, 0.05, 1.0], twoHanded: 1, twist: 0.45, dy: -0.22, lean: 0.15, step: 0.3 };
        const lunge: KF = { rh: [0.03, 1.25, 0.8], rd: [0, 0.03, 1], twoHanded: 1, twist: -0.1, lean: 0.42, dy: -0.25, step: 0.5 };
        const lift: KF = { rh: [0.05, 1.55, 0.62], rd: [0, 0.5, 0.87], twoHanded: 1, lean: 0.05, dy: -0.12, step: 0.4 };
        if (u.phase === 'aim') pose = mixPose(pose, aim, smooth(clamp01(u.pf / 12)));
        else if (u.phase === 'dash') {
          pose = mixPose(pose, lunge, 1);
          trail = 1;
        } else if (u.phase === 'impale' || u.phase === 'burst') pose = mixPose(pose, lift, smooth(clamp01(u.pf / 8)));
        else pose = mixPose(mixPose(pose, lunge, 1), guardFor(f), smooth(clamp01(u.pf / 24)));
      } else if (u.kind === 'tempest') {
        if (u.phase === 'flash') pose = mixPose(pose, ARCH.shadowStep[1], 1);
        else if (u.phase === 'spin') {
          pose = mixPose(pose, { rh: [0.6, 1.25, 0.1], rd: [0.95, 0.0, 0.3], lh: [-0.6, 1.25, -0.1], ld: [-0.95, 0.0, -0.3], dy: -0.15, lean: 0.1 }, 1);
          pose.bodyYaw = -((u.spins + u.pf / 10) * TAU);
          key = 'ult-spin';
          blend = 0.001;
          trail = 1;
        } else if (u.phase === 'final') {
          const kf = ARCH.cross;
          const t = clamp01(u.pf / 10);
          pose = t < 0.6 ? mixPose(pose, kf[0], t / 0.6) : mixPose(mixPose(pose, kf[0], 1), kf[1], (t - 0.6) / 0.4);
          trail = t > 0.5 ? 1 : 0;
        } else pose = mixPose(mixPose(pose, ARCH.cross[2], 1), guardFor(f), smooth(clamp01(u.pf / 20)));
      }
      break;
    }
    case 'ultChoice':
      pose = mixPose(pose, { rh: [0.02, 1.32, 0.3], lh: [-0.02, 1.32, 0.3], dy: -0.2, lean: 0.05, head: 0.25 }, 1);
      glow = 1;
      glowKind = 'ult';
      key = 'ultChoice';
      break;
    case 'recall': {
      const t = clamp01(f.sf / 16);
      pose = mixPose(pose, { rh: [0.25, 1.95, 0.25], lh: [-0.2, 1.3, 0.3], lean: -0.1, head: -0.3 }, Math.sin(Math.min(1, t) * Math.PI * 0.5));
      if (f.sf > 16) pose = mixPose(pose, guardFor(f), clamp01((f.sf - 16) / 10));
      key = 'recall';
      break;
    }
    case 'impaled':
      pose = mixPose(pose, { rh: [0.25, 0.9, 0.15], lh: [-0.25, 0.9, 0.15], lean: 0.5, head: 0.5, fl: [-0.12, -0.25, 0.05], fr: [0.12, -0.3, 0.0], dy: 0.0 }, 1);
      key = 'impaled';
      break;
    case 'ko': {
      const t = clamp01(f.sf / 40);
      pose = mixPose(pose, { rh: [0.4, 1.3, -0.2], lh: [-0.4, 1.3, -0.2], lean: -0.2, head: -0.3 }, 1);
      pose.bodyPitch = (Math.PI / 2) * 0.92 * easeIn(t);
      pose.dy = lerp(pose.dy, -0.1, t);
      key = 'ko';
      blend = 0.05;
      break;
    }
    case 'victory': {
      const t = clamp01(f.sf / 30);
      const pose2: KF =
        w === 'fists'
          ? { rh: [0.2, 2.0, 0.1], lh: [-0.15, 1.2, 0.2], head: -0.2 }
          : w === 'daggers'
            ? { rh: [0.35, 1.2, 0.1], rd: [0, -1, 0], lh: [-0.35, 1.2, 0.1], ld: [0, -1, 0], lean: -0.05 }
            : { rh: [0.2, 1.95, 0.15], rd: [0.05, 0.99, 0.1], twoHanded: 0, lh: [-0.2, 1.1, 0.15], head: -0.15 };
      pose = mixPose(pose, pose2, smooth(t));
      key = 'victory';
      blend = 0.2;
      break;
    }
  }

  // front foot forward for lunging poses
  if (pose.step) {
    pose.fl = [pose.fl[0], pose.fl[1], pose.fl[2] + pose.step];
    pose.fr = [pose.fr[0], pose.fr[1], pose.fr[2] - pose.step * 0.35];
  }
  resolveGrip(pose, w);
  return { pose, key, blend, trail, trailKind, glow, glowKind };
}
