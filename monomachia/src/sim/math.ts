// Small math helpers for the simulation (no three.js dependency so it runs in tests).

export interface Vec2 {
  x: number;
  z: number;
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export const v2 = (x = 0, z = 0): Vec2 => ({ x, z });
export const v3 = (x = 0, y = 0, z = 0): Vec3 => ({ x, y, z });

export const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const sign = (v: number) => (v < 0 ? -1 : 1);

export function len2(x: number, z: number) {
  return Math.sqrt(x * x + z * z);
}

export function dist2(a: Vec2 | Vec3, b: Vec2 | Vec3) {
  return len2(b.x - a.x, b.z - a.z);
}

export function norm2(x: number, z: number): Vec2 {
  const l = Math.sqrt(x * x + z * z);
  return l > 1e-9 ? { x: x / l, z: z / l } : { x: 0, z: 1 };
}

/** Forward unit vector for a yaw angle. yaw=0 faces +Z; positive yaw turns toward +X. */
export function fwd(yaw: number): Vec2 {
  return { x: Math.sin(yaw), z: Math.cos(yaw) };
}

/** Right-hand unit vector for a yaw angle (fighter's own right side). */
export function right(yaw: number): Vec2 {
  // right = forward x up = (-fz, fx)
  return { x: -Math.cos(yaw), z: Math.sin(yaw) };
}

export function yawTo(from: Vec2 | Vec3, to: Vec2 | Vec3) {
  return Math.atan2(to.x - from.x, to.z - from.z);
}

export function wrapAngle(a: number) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

/** Rotate `current` toward `target` by at most `maxStep` radians. */
export function turnToward(current: number, target: number, maxStep: number) {
  const d = wrapAngle(target - current);
  if (Math.abs(d) <= maxStep) return target;
  return wrapAngle(current + Math.sign(d) * maxStep);
}

export function angleBetween(yaw: number, dirYaw: number) {
  return Math.abs(wrapAngle(dirYaw - yaw));
}

export const DEG = Math.PI / 180;

export function easeOutCubic(t: number) {
  const u = 1 - t;
  return 1 - u * u * u;
}

export function easeInOut(t: number) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}
