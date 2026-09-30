// Behind-the-back lock-on camera, plus a side-on cinematic view for watch mode.

import * as THREE from 'three';
import type { Fighter } from '../sim/fighter';

export type CamMode = 'follow' | 'cinematic' | 'menu';

const damp = (a: number, b: number, k: number, dt: number) => a + (b - a) * (1 - Math.exp(-k * dt));

export class CameraRig {
  camera: THREE.PerspectiveCamera;
  pos = new THREE.Vector3(0, 3, -9);
  look = new THREE.Vector3(0, 1.2, 0);
  private dir = new THREE.Vector3(0, 0, 1);
  private shake = 0;
  private fovKick = 0;
  private baseFov = 56;
  private time = 0;
  koOrbit = 0;
  shakeScale = 1;
  fovScale = 1;

  constructor(aspect: number) {
    this.camera = new THREE.PerspectiveCamera(this.baseFov, aspect, 0.1, 900);
    this.camera.position.copy(this.pos);
  }

  addShake(a: number) {
    this.shake = Math.min(1.2, this.shake + a * this.shakeScale);
  }

  kickFov(a: number) {
    this.fovKick = a * this.fovScale;
  }

  snap(player: Fighter, opp: Fighter, mode: CamMode) {
    this.update(1, player, opp, mode, true);
  }

  update(dt: number, player: Fighter, opp: Fighter, mode: CamMode, snap = false) {
    this.time += dt;
    const P = player.pos;
    const O = opp.pos;
    const dx = O.x - P.x;
    const dz = O.z - P.z;
    const d = Math.hypot(dx, dz);
    if (d > 0.3) {
      const nd = new THREE.Vector3(dx / d, 0, dz / d);
      // keep the direction smooth when fighters cross each other
      this.dir.lerp(nd, snap ? 1 : 1 - Math.exp(-6 * dt)).normalize();
    }
    const dir = this.dir;
    const right = new THREE.Vector3(-dir.z, 0, dir.x);
    const targetPos = new THREE.Vector3();
    const targetLook = new THREE.Vector3();

    if (mode === 'menu') {
      const a = this.time * 0.08;
      targetPos.set(Math.sin(a) * 10.5, 3.2, Math.cos(a) * 10.5 - 1);
      targetLook.set(0, 1.4, 0);
    } else if (mode === 'cinematic' || this.koOrbit > 0) {
      const mid = new THREE.Vector3((P.x + O.x) / 2, 0, (P.z + O.z) / 2);
      const swing = Math.sin(this.time * 0.15) * 0.5 + (this.koOrbit > 0 ? this.koOrbit * 0.25 : 0);
      const side = right.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), swing);
      const dist = 4.6 + d * 0.55;
      targetPos.copy(mid).addScaledVector(side, dist).addScaledVector(dir, -1.2);
      targetPos.y = 1.9 + d * 0.08;
      targetLook.copy(mid);
      targetLook.y = 1.1;
      if (this.koOrbit > 0) this.koOrbit += dt;
    } else {
      const extra = Math.max(0, Math.min(8, d - 3));
      const close = Math.max(0, 2.5 - d);
      const back = 3.9 + extra * 0.3 + close * 0.5;
      const height = 2.15 + extra * 0.14;
      targetPos.set(P.x, 0, P.z).addScaledVector(dir, -back).addScaledVector(right, 1.05);
      targetPos.y = height + P.y * 0.5;
      targetLook.set(P.x + dx * 0.6, 1.05 + (P.y + O.y) * 0.3, P.z + dz * 0.6);
    }

    // keep the camera inside a generous radius
    const r = Math.hypot(targetPos.x, targetPos.z);
    if (r > 15.5 && mode !== 'menu') {
      targetPos.x *= 15.5 / r;
      targetPos.z *= 15.5 / r;
    }

    if (snap) {
      this.pos.copy(targetPos);
      this.look.copy(targetLook);
    } else {
      const kp = mode === 'follow' ? 9 : 3;
      this.pos.set(damp(this.pos.x, targetPos.x, kp, dt), damp(this.pos.y, targetPos.y, kp, dt), damp(this.pos.z, targetPos.z, kp, dt));
      this.look.set(damp(this.look.x, targetLook.x, 12, dt), damp(this.look.y, targetLook.y, 12, dt), damp(this.look.z, targetLook.z, 12, dt));
    }

    const cam = this.camera;
    cam.position.copy(this.pos);
    if (this.shake > 0.001) {
      const s = this.shake * 0.12;
      cam.position.x += (Math.random() - 0.5) * s;
      cam.position.y += (Math.random() - 0.5) * s;
      cam.position.z += (Math.random() - 0.5) * s;
      this.shake *= Math.exp(-9 * dt);
    }
    cam.lookAt(this.look);
    this.fovKick *= Math.exp(-3 * dt);
    const fov = this.baseFov - this.fovKick;
    if (Math.abs(cam.fov - fov) > 0.01) {
      cam.fov = fov;
      cam.updateProjectionMatrix();
    }
  }
}
