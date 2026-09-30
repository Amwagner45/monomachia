// A fighter "puppet" built from simple shapes. Each frame the animator gives a
// pose (hand, weapon and foot targets); the rig solves elbows and knees with
// two-bone IK and places every part.

import * as THREE from 'three';
import type { Fighter } from '../sim/fighter';
import type { WeaponId } from '../sim/moves/types';
import { AnimState, Pose, PoseResult, V, clonePose, computePose, lerpPose, newAnimState } from './pose';
import { WeaponModel, buildWeapon } from './weaponMesh';

export interface FighterPalette {
  accent: number;
  armor: number;
  cloth: number;
  trim: number;
  eyes: number;
}

export const PALETTES: FighterPalette[] = [
  { accent: 0xa3201f, armor: 0x19171c, cloth: 0x2c2226, trim: 0xa4844a, eyes: 0xff5a2a },
  { accent: 0x2d6394, armor: 0x16191e, cloth: 0x222730, trim: 0x9aa6b4, eyes: 0x4fd6ff },
];

const UP_ARM = 0.29;
const FORE_ARM = 0.27;
const THIGH = 0.44;
const SHIN = 0.44;
const Y = new THREE.Vector3(0, 1, 0);

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _e = new THREE.Euler();

/** authored (right, up, forward) -> three.js local (x = left) */
function conv(v: V, out = new THREE.Vector3()) {
  return out.set(-v[0], v[1], v[2]);
}

function solveTwoBone(
  root: THREE.Vector3,
  target: THREE.Vector3,
  pole: THREE.Vector3,
  l1: number,
  l2: number,
  outMid: THREE.Vector3,
  outEnd: THREE.Vector3,
) {
  const dir = _a.subVectors(target, root);
  let d = dir.length();
  const minD = Math.abs(l1 - l2) + 1e-3;
  const maxD = l1 + l2 - 1e-3;
  d = Math.min(maxD, Math.max(minD, d));
  if (dir.lengthSq() < 1e-8) dir.set(0, -1, 0);
  dir.normalize();
  outEnd.copy(root).addScaledVector(dir, d);
  const cosA = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d);
  const a = Math.acos(Math.max(-1, Math.min(1, cosA)));
  const bend = _b.subVectors(pole, root);
  bend.addScaledVector(dir, -bend.dot(dir));
  if (bend.lengthSq() < 1e-8) bend.set(0, -1, 0).addScaledVector(dir, -dir.y);
  bend.normalize();
  outMid.copy(root).addScaledVector(dir, Math.cos(a) * l1).addScaledVector(bend, Math.sin(a) * l1);
}

function placeSegment(mesh: THREE.Object3D, a: THREE.Vector3, b: THREE.Vector3) {
  mesh.position.addVectors(a, b).multiplyScalar(0.5);
  _c.subVectors(b, a);
  const len = _c.length();
  if (len > 1e-6) mesh.quaternion.setFromUnitVectors(Y, _c.divideScalar(len));
}

/** Orient a weapon so its +Y follows `dir` with a stable roll. */
function orientWeapon(obj: THREE.Object3D, dir: THREE.Vector3, rollRef: THREE.Vector3) {
  const y = _a.copy(dir).normalize();
  const ref = Math.abs(y.dot(rollRef)) > 0.95 ? _b.set(0, 0, 1) : _b.copy(rollRef);
  const x = _c.crossVectors(ref, y).normalize();
  const z = new THREE.Vector3().crossVectors(x, y);
  _m.makeBasis(x, y, z);
  obj.quaternion.setFromRotationMatrix(_m);
}

export class FighterRig {
  root = new THREE.Group();
  body = new THREE.Group();
  private pelvisG = new THREE.Group();
  private torsoG = new THREE.Group();
  private headG = new THREE.Group();
  private upArmR: THREE.Mesh;
  private upArmL: THREE.Mesh;
  private foreArmR: THREE.Mesh;
  private foreArmL: THREE.Mesh;
  private handR: THREE.Mesh;
  private handL: THREE.Mesh;
  private thighR: THREE.Mesh;
  private thighL: THREE.Mesh;
  private shinR: THREE.Mesh;
  private shinL: THREE.Mesh;
  private footR: THREE.Mesh;
  private footL: THREE.Mesh;
  private sashTails: THREE.Mesh[] = [];

  weaponR: WeaponModel | null = null;
  weaponL: WeaponModel | null = null;
  weaponId: WeaponId;
  mats: THREE.MeshStandardMaterial[] = [];
  eyeMat: THREE.MeshStandardMaterial;

  anim: AnimState = newAnimState();
  private current: Pose | null = null;
  private from: Pose | null = null;
  private blendT = 1;
  private blendDur = 0.1;
  private lastKey = '';
  lastResult: PoseResult | null = null;

  // world-space points for effects
  bladeBaseR = new THREE.Vector3();
  bladeTipR = new THREE.Vector3();
  bladeBaseL = new THREE.Vector3();
  bladeTipL = new THREE.Vector3();
  headWorld = new THREE.Vector3();
  chestWorld = new THREE.Vector3();
  handWorldR = new THREE.Vector3();

  private flash = 0;
  private flashColor = new THREE.Color();
  private shakeT = 0;

  constructor(public palette: FighterPalette, weaponId: WeaponId) {
    this.weaponId = weaponId;
    const P = palette;
    const mat = (color: number, rough = 0.7, metal = 0.1) => {
      const m = new THREE.MeshStandardMaterial({ color, roughness: rough, metalness: metal });
      this.mats.push(m);
      return m;
    };
    const armor = mat(P.armor, 0.42, 0.55);
    const accent = mat(P.accent, 0.55, 0.2);
    const cloth = mat(P.cloth, 0.9, 0.0);
    const trim = mat(P.trim, 0.35, 0.85);
    const glove = mat(0x1d1a18, 0.8, 0.1);
    this.eyeMat = new THREE.MeshStandardMaterial({ color: 0x000000, emissive: P.eyes, emissiveIntensity: 3 });

    const box = (w: number, h: number, d: number, m: THREE.Material) => {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
      mesh.castShadow = true;
      return mesh;
    };
    const cap = (r: number, len: number, m: THREE.Material) => {
      const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 4, 8), m);
      mesh.castShadow = true;
      return mesh;
    };

    this.root.add(this.body);
    this.body.add(this.pelvisG, this.torsoG, this.headG);

    // --- pelvis: hips, sash and tassets
    const hips = box(0.3, 0.2, 0.21, cloth);
    hips.position.y = -0.02;
    const obi = box(0.33, 0.075, 0.24, accent);
    obi.position.y = 0.08;
    this.pelvisG.add(hips, obi);
    const tasset = (x: number, z: number, ry: number) => {
      const t = box(0.17, 0.26, 0.025, armor);
      t.position.set(x, -0.12, z);
      t.rotation.y = ry;
      t.rotation.x = z > 0 ? 0.12 : z < 0 ? -0.12 : 0;
      t.rotation.z = x > 0 ? -0.12 : x < 0 ? 0.12 : 0;
      const band = box(0.17, 0.025, 0.03, accent);
      band.position.y = 0.05;
      t.add(band);
      this.pelvisG.add(t);
    };
    tasset(0, 0.12, 0);
    tasset(0, -0.12, 0);
    tasset(0.16, 0, Math.PI / 2);
    tasset(-0.16, 0, Math.PI / 2);
    for (const side of [-1, 1]) {
      const tail = box(0.05, 0.34, 0.012, accent);
      tail.geometry.translate(0, -0.17, 0);
      tail.position.set(0.1 * side, 0.06, -0.12);
      this.pelvisG.add(tail);
      this.sashTails.push(tail);
    }

    // --- torso: chest plate, shoulder guards
    const chest = box(0.38, 0.34, 0.24, armor);
    chest.position.y = 0.33;
    const belly = box(0.31, 0.16, 0.2, cloth);
    belly.position.y = 0.14;
    const stripe = box(0.385, 0.05, 0.245, accent);
    stripe.position.y = 0.28;
    const collar = box(0.26, 0.06, 0.22, trim);
    collar.position.y = 0.5;
    this.torsoG.add(chest, belly, stripe, collar);
    for (const side of [-1, 1]) {
      const sode = box(0.19, 0.2, 0.05, armor);
      sode.position.set(0.25 * side, 0.4, 0);
      sode.rotation.z = 0.38 * side;
      sode.rotation.y = Math.PI / 2;
      const lace = box(0.19, 0.03, 0.055, accent);
      lace.position.y = 0.06;
      sode.add(lace);
      const lace2 = box(0.19, 0.03, 0.055, accent);
      lace2.position.y = -0.03;
      sode.add(lace2);
      this.torsoG.add(sode);
    }

    // --- head: helmet bowl, neck guard, mask, crest
    const bowl = new THREE.Mesh(new THREE.SphereGeometry(0.135, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), armor);
    bowl.position.y = 0.05;
    bowl.castShadow = true;
    const neckGuard = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.2, 0.1, 12, 1, true), armor);
    neckGuard.position.set(0, 0.0, -0.02);
    neckGuard.castShadow = true;
    (neckGuard.material as THREE.Material).side = THREE.DoubleSide;
    const face = box(0.16, 0.15, 0.06, mat(0x120e0f, 0.6, 0.2));
    face.position.set(0, -0.02, 0.1);
    const eyeL = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.012, 0.01), this.eyeMat);
    eyeL.position.set(0.035, 0.02, 0.133);
    const eyeR = eyeL.clone();
    eyeR.position.x = -0.035;
    const brow = box(0.2, 0.025, 0.05, trim);
    brow.position.set(0, 0.06, 0.11);
    const hornL = box(0.02, 0.2, 0.012, trim);
    hornL.position.set(0.07, 0.17, 0.12);
    hornL.rotation.z = -0.45;
    const hornR = hornL.clone();
    hornR.position.x = -0.07;
    hornR.rotation.z = 0.45;
    const crest = box(0.05, 0.05, 0.02, accent);
    crest.position.set(0, 0.1, 0.14);
    this.headG.add(bowl, neckGuard, face, eyeL, eyeR, brow, hornL, hornR, crest);

    // --- limbs
    this.upArmR = cap(0.058, UP_ARM - 0.1, armor);
    this.upArmL = cap(0.058, UP_ARM - 0.1, armor);
    this.foreArmR = cap(0.05, FORE_ARM - 0.08, cloth);
    this.foreArmL = cap(0.05, FORE_ARM - 0.08, cloth);
    for (const fa of [this.foreArmR, this.foreArmL]) {
      const kote = box(0.1, 0.13, 0.1, armor);
      kote.position.y = -0.02;
      fa.add(kote);
    }
    this.handR = box(0.07, 0.085, 0.07, glove);
    this.handL = box(0.07, 0.085, 0.07, glove);
    this.thighR = cap(0.085, THIGH - 0.12, cloth);
    this.thighL = cap(0.085, THIGH - 0.12, cloth);
    this.shinR = cap(0.062, SHIN - 0.1, cloth);
    this.shinL = cap(0.062, SHIN - 0.1, cloth);
    for (const sh of [this.shinR, this.shinL]) {
      const guard = box(0.1, 0.26, 0.05, armor);
      guard.position.set(0, 0.02, 0.05);
      sh.add(guard);
    }
    this.footR = box(0.1, 0.07, 0.24, glove);
    this.footL = box(0.1, 0.07, 0.24, glove);
    this.body.add(
      this.upArmR, this.upArmL, this.foreArmR, this.foreArmL, this.handR, this.handL,
      this.thighR, this.thighL, this.shinR, this.shinL, this.footR, this.footL,
    );

    this.setWeapon(weaponId);
  }

  setWeapon(id: WeaponId) {
    for (const w of [this.weaponR, this.weaponL]) if (w) this.body.remove(w.group);
    this.weaponId = id;
    this.weaponR = buildWeapon(id);
    this.weaponL = id === 'daggers' ? buildWeapon(id) : null;
    if (this.weaponR) this.body.add(this.weaponR.group);
    if (this.weaponL) this.body.add(this.weaponL.group);
  }

  hitFlash(color: number, strength = 1) {
    this.flash = strength;
    this.flashColor.set(color);
  }

  shake(amount: number) {
    this.shakeT = amount;
  }

  update(f: Fighter, time: number, dt: number, alpha = 0) {
    // root transform
    this.root.position.set(f.pos.x, f.pos.y, f.pos.z);
    if (this.shakeT > 0) {
      this.root.position.x += (Math.random() - 0.5) * this.shakeT * 0.08;
      this.root.position.z += (Math.random() - 0.5) * this.shakeT * 0.08;
      this.shakeT = Math.max(0, this.shakeT - dt * 6);
    }
    this.root.rotation.set(0, f.yaw, 0);

    const res = computePose(f, time, dt, this.anim, alpha);
    this.lastResult = res;
    if (res.key !== this.lastKey) {
      this.from = this.current ? clonePose(this.current) : null;
      this.blendT = 0;
      this.blendDur = res.blend;
      this.lastKey = res.key;
    }
    let pose = res.pose;
    if (this.from && this.blendT < 1) {
      this.blendT = Math.min(1, this.blendT + dt / Math.max(0.001, this.blendDur));
      const t = this.blendT * this.blendT * (3 - 2 * this.blendT);
      pose = lerpPose(this.from, pose, t);
    }
    this.current = pose;
    this.applyPose(pose, f, time);

    // weapons visibility
    const armed = f.armed;
    if (this.weaponR) this.weaponR.group.visible = armed;
    if (this.weaponL) this.weaponL.group.visible = armed;

    // glow on blades
    const glow = res.glow;
    for (const w of [this.weaponR, this.weaponL]) {
      if (!w) continue;
      const c = res.glowKind === 'danger' ? 0xff2a1a : res.glowKind === 'charge' ? 0xffe0a0 : 0xffc240;
      if (glow > 0.01) {
        w.bladeMat.emissive.setHex(c);
        w.bladeMat.emissiveIntensity = glow * (res.glowKind === 'danger' ? 2.2 : 1.6);
      } else {
        w.bladeMat.emissive.setHex(0x9aa4b8);
        w.bladeMat.emissiveIntensity = 0.12;
      }
    }

    // hit flash
    if (this.flash > 0) {
      for (const m of this.mats) {
        m.emissive.copy(this.flashColor);
        m.emissiveIntensity = this.flash * 0.9;
      }
      this.flash = Math.max(0, this.flash - dt * 6);
      if (this.flash === 0) for (const m of this.mats) m.emissiveIntensity = 0;
    }

    this.root.updateMatrixWorld(true);
    this.collectWorldPoints();
  }

  private applyPose(p: Pose, f: Fighter, time: number) {
    // whole-body transforms (spins and falls)
    this.body.rotation.order = 'YXZ';
    this.body.rotation.set(-p.bodyPitch, -p.bodyYaw, 0);

    const pelvis = new THREE.Vector3(0, 0.95 + p.dy, 0);
    const qTorso = new THREE.Quaternion().setFromEuler(_e.set(p.lean, -p.twist, p.roll, 'YXZ'));
    const qPelvis = new THREE.Quaternion().setFromEuler(_e.set(0, -p.twist * 0.35, p.roll * 0.3, 'YXZ'));

    this.pelvisG.position.copy(pelvis);
    this.pelvisG.quaternion.copy(qPelvis);
    this.torsoG.position.copy(pelvis);
    this.torsoG.quaternion.copy(qTorso);

    const chestTop = new THREE.Vector3(0, 0.5, 0).applyQuaternion(qTorso).add(pelvis);
    const shR = new THREE.Vector3(-0.19, -0.05, 0).applyQuaternion(qTorso).add(chestTop);
    const shL = new THREE.Vector3(0.19, -0.05, 0).applyQuaternion(qTorso).add(chestTop);

    // head: stays fairly upright
    const qHead = new THREE.Quaternion().setFromEuler(_e.set(p.lean * 0.4 + p.head, -p.twist * 0.6, p.roll * 0.5, 'YXZ'));
    this.headG.position.copy(new THREE.Vector3(0, 0.14, 0.01).applyQuaternion(qTorso).add(chestTop));
    this.headG.quaternion.copy(qHead);

    // arms
    const handRT = conv(p.rh);
    const handLT = conv(p.lh);
    const poleR = new THREE.Vector3(-0.4, -0.6, -0.35).applyQuaternion(qTorso).add(shR);
    const poleL = new THREE.Vector3(0.4, -0.6, -0.35).applyQuaternion(qTorso).add(shL);
    const elR = new THREE.Vector3();
    const haR = new THREE.Vector3();
    const elL = new THREE.Vector3();
    const haL = new THREE.Vector3();
    solveTwoBone(shR, handRT, poleR, UP_ARM, FORE_ARM, elR, haR);
    solveTwoBone(shL, handLT, poleL, UP_ARM, FORE_ARM, elL, haL);
    placeSegment(this.upArmR, shR, elR);
    placeSegment(this.foreArmR, elR, haR);
    placeSegment(this.upArmL, shL, elL);
    placeSegment(this.foreArmL, elL, haL);
    this.handR.position.copy(haR);
    this.handR.quaternion.copy(this.foreArmR.quaternion);
    this.handL.position.copy(haL);
    this.handL.quaternion.copy(this.foreArmL.quaternion);

    // legs
    const hipR = new THREE.Vector3(-0.11, -0.04, 0).applyQuaternion(qPelvis).add(pelvis);
    const hipL = new THREE.Vector3(0.11, -0.04, 0).applyQuaternion(qPelvis).add(pelvis);
    const fR = conv(p.fr);
    const fL = conv(p.fl);
    const kneePoleR = new THREE.Vector3(-0.08, -0.25, 0.9).applyQuaternion(qPelvis).add(hipR);
    const kneePoleL = new THREE.Vector3(0.08, -0.25, 0.9).applyQuaternion(qPelvis).add(hipL);
    const knR = new THREE.Vector3();
    const anR = new THREE.Vector3();
    const knL = new THREE.Vector3();
    const anL = new THREE.Vector3();
    solveTwoBone(hipR, fR, kneePoleR, THIGH, SHIN, knR, anR);
    solveTwoBone(hipL, fL, kneePoleL, THIGH, SHIN, knL, anL);
    placeSegment(this.thighR, hipR, knR);
    placeSegment(this.shinR, knR, anR);
    placeSegment(this.thighL, hipL, knL);
    placeSegment(this.shinL, knL, anL);
    const footYaw = -p.twist * 0.25;
    this.footR.position.set(anR.x, anR.y - 0.035, anR.z + 0.05);
    this.footR.rotation.set(0, footYaw, 0);
    this.footL.position.set(anL.x, anL.y - 0.035, anL.z + 0.05);
    this.footL.rotation.set(0, footYaw, 0);

    // sash tails sway with movement
    const sway = Math.sin(time * 3) * 0.08 + Math.min(0.6, this.anim.speed * 0.08);
    for (let i = 0; i < this.sashTails.length; i++) this.sashTails[i].rotation.x = sway + i * 0.05;

    // weapons in hand
    const up = new THREE.Vector3(0, 1, 0);
    if (this.weaponR) {
      this.weaponR.group.position.copy(haR);
      orientWeapon(this.weaponR.group, conv(p.rd), up);
    }
    if (this.weaponL) {
      this.weaponL.group.position.copy(haL);
      orientWeapon(this.weaponL.group, conv(p.ld), up);
    }
    void f;
  }

  private collectWorldPoints() {
    const pt = (w: WeaponModel | null, d: number, out: THREE.Vector3) => {
      if (!w) return out.set(0, 0, 0);
      return out.set(0, d, 0).applyMatrix4(w.group.matrixWorld);
    };
    pt(this.weaponR, this.weaponR?.base ?? 0, this.bladeBaseR);
    pt(this.weaponR, this.weaponR?.length ?? 0, this.bladeTipR);
    pt(this.weaponL, this.weaponL?.base ?? 0, this.bladeBaseL);
    pt(this.weaponL, this.weaponL?.length ?? 0, this.bladeTipL);
    this.headWorld.setFromMatrixPosition(this.headG.matrixWorld);
    this.chestWorld.set(0, 0.3, 0).applyMatrix4(this.torsoG.matrixWorld);
    this.handWorldR.setFromMatrixPosition(this.handR.matrixWorld);
  }

  dispose() {
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.geometry) m.geometry.dispose();
    });
  }
}

export function vecOf(v: V) {
  return conv(v);
}
