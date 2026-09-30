// Simple, readable weapon models built from primitives. Each weapon group has
// its grip at the origin and the blade pointing along +Y.

import * as THREE from 'three';
import type { WeaponId } from '../sim/moves/types';

export interface WeaponModel {
  group: THREE.Group;
  bladeMat: THREE.MeshStandardMaterial;
  /** distance from grip to the blade tip */
  length: number;
  /** distance from grip where the edge starts (for trails) */
  base: number;
}

const steel = () =>
  new THREE.MeshStandardMaterial({ color: 0xd0d4dc, metalness: 0.85, roughness: 0.28, envMapIntensity: 1.6 });
const darkSteel = () =>
  new THREE.MeshStandardMaterial({ color: 0x9a9ea6, metalness: 0.85, roughness: 0.38, envMapIntensity: 1.4 });
const wrap = new THREE.MeshStandardMaterial({ color: 0x1c1411, roughness: 0.92 });
const gold = new THREE.MeshStandardMaterial({ color: 0xa4844a, metalness: 0.85, roughness: 0.38 });
const iron = new THREE.MeshStandardMaterial({ color: 0x2a2a2e, metalness: 0.8, roughness: 0.5 });

function extrudeBlade(pts: [number, number][], depth: number) {
  const shape = new THREE.Shape();
  shape.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) shape.lineTo(pts[i][0], pts[i][1]);
  shape.closePath();
  const g = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: true,
    bevelThickness: depth * 0.35,
    bevelSize: 0.003,
    bevelSegments: 1,
    curveSegments: 1,
  });
  g.translate(0, 0, -depth / 2);
  g.computeVertexNormals();
  return g;
}

function katana(): WeaponModel {
  const group = new THREE.Group();
  const bladeMat = steel();
  const L = 0.95;
  const back: [number, number][] = [];
  const edge: [number, number][] = [];
  const N = 10;
  for (let i = 0; i <= N; i++) {
    const y = 0.04 + (i / N) * (L - 0.09);
    const c = 0.04 * Math.pow(y / L, 2); // curvature (sori)
    const w = 0.042 - 0.008 * (y / L);
    back.push([c, y]);
    edge.push([c - w, y]);
  }
  const tipC = 0.04 * 1.0;
  const pts: [number, number][] = [...back, [tipC - 0.006, L], ...edge.reverse()];
  const blade = new THREE.Mesh(extrudeBlade(pts, 0.006), bladeMat);
  blade.castShadow = true;
  group.add(blade);
  const tsuba = new THREE.Mesh(new THREE.CylinderGeometry(0.046, 0.046, 0.012, 14), gold);
  tsuba.position.y = 0.02;
  group.add(tsuba);
  const habaki = new THREE.Mesh(new THREE.BoxGeometry(0.036, 0.035, 0.016), gold);
  habaki.position.set(-0.012, 0.05, 0);
  group.add(habaki);
  const tsuka = new THREE.Mesh(new THREE.BoxGeometry(0.034, 0.28, 0.028), wrap);
  tsuka.position.y = -0.125;
  tsuka.castShadow = true;
  group.add(tsuka);
  const kashira = new THREE.Mesh(new THREE.BoxGeometry(0.038, 0.02, 0.032), gold);
  kashira.position.y = -0.27;
  group.add(kashira);
  return { group, bladeMat, length: L, base: 0.1 };
}

function greatsword(): WeaponModel {
  const group = new THREE.Group();
  const bladeMat = darkSteel();
  const L = 1.32;
  const pts: [number, number][] = [
    [0.065, 0.02],
    [0.058, L - 0.16],
    [0.0, L],
    [-0.058, L - 0.16],
    [-0.065, 0.02],
  ];
  const blade = new THREE.Mesh(extrudeBlade(pts, 0.014), bladeMat);
  blade.castShadow = true;
  group.add(blade);
  const fuller = new THREE.Mesh(new THREE.BoxGeometry(0.018, L * 0.72, 0.022), iron);
  fuller.position.y = 0.06 + (L * 0.72) / 2;
  group.add(fuller);
  const guard = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.045, 0.055), iron);
  guard.position.y = 0.0;
  guard.castShadow = true;
  group.add(guard);
  const grip = new THREE.Mesh(new THREE.CylinderGeometry(0.021, 0.024, 0.36, 8), wrap);
  grip.position.y = -0.18;
  group.add(grip);
  const pommel = new THREE.Mesh(new THREE.SphereGeometry(0.038, 10, 8), iron);
  pommel.position.y = -0.38;
  group.add(pommel);
  return { group, bladeMat, length: L, base: 0.12 };
}

function dagger(): WeaponModel {
  const group = new THREE.Group();
  const bladeMat = steel();
  const L = 0.33;
  const pts: [number, number][] = [
    [0.02, 0.02],
    [0.018, L - 0.07],
    [0.0, L],
    [-0.02, L - 0.03],
    [-0.02, 0.02],
  ];
  const blade = new THREE.Mesh(extrudeBlade(pts, 0.005), bladeMat);
  blade.castShadow = true;
  group.add(blade);
  const guard = new THREE.Mesh(new THREE.BoxGeometry(0.085, 0.016, 0.026), gold);
  group.add(guard);
  const grip = new THREE.Mesh(new THREE.BoxGeometry(0.026, 0.12, 0.024), wrap);
  grip.position.y = -0.065;
  group.add(grip);
  const cap = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.018, 0.028), gold);
  cap.position.y = -0.13;
  group.add(cap);
  return { group, bladeMat, length: L, base: 0.04 };
}

export function buildWeapon(id: WeaponId): WeaponModel | null {
  switch (id) {
    case 'katana':
      return katana();
    case 'greatsword':
      return greatsword();
    case 'daggers':
      return dagger();
    default:
      return null;
  }
}
