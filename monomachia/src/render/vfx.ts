// Visual effects: sparks, dust, blood, weapon trails, the danger mark over
// unblockables, parry rings, shockwaves, the katana wave, lightning and auras.

import * as THREE from 'three';
import { glowTexture, textTexture } from './textures';

const tmp = new THREE.Vector3();

// ------------------------------------------------------------------ particles

export class ParticleSystem {
  points: THREE.Points;
  private max: number;
  private pos: Float32Array;
  private vel: Float32Array;
  private col: Float32Array;
  private size: Float32Array;
  private alpha: Float32Array;
  private life: Float32Array;
  private maxLife: Float32Array;
  private grav: Float32Array;
  private drag: Float32Array;
  private baseSize: Float32Array;
  private next = 0;
  material: THREE.ShaderMaterial;

  constructor(max: number, additive: boolean) {
    this.max = max;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.col = new Float32Array(max * 3);
    this.size = new Float32Array(max);
    this.alpha = new Float32Array(max);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.grav = new Float32Array(max);
    this.drag = new Float32Array(max);
    this.baseSize = new Float32Array(max);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    geo.setAttribute('size', new THREE.BufferAttribute(this.size, 1));
    geo.setAttribute('alpha', new THREE.BufferAttribute(this.alpha, 1));
    this.material = new THREE.ShaderMaterial({
      uniforms: { map: { value: glowTexture() }, scale: { value: 600 } },
      vertexShader: `attribute float size; attribute float alpha; attribute vec3 color; varying vec3 vC; varying float vA; uniform float scale;
        void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0); gl_PointSize = size * scale / max(0.1, -mv.z); gl_Position = projectionMatrix * mv; vC = color; vA = alpha; }`,
      fragmentShader: `uniform sampler2D map; varying vec3 vC; varying float vA;
        void main(){ vec4 t = texture2D(map, gl_PointCoord); if (t.a * vA < 0.01) discard; gl_FragColor = vec4(vC * t.rgb, t.a * vA); }`,
      transparent: true,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(geo, this.material);
    this.points.frustumCulled = false;
  }

  spawn(p: THREE.Vector3, v: THREE.Vector3, color: THREE.Color, size: number, life: number, grav = 0, drag = 1) {
    const i = this.next;
    this.next = (this.next + 1) % this.max;
    this.pos.set([p.x, p.y, p.z], i * 3);
    this.vel.set([v.x, v.y, v.z], i * 3);
    this.col.set([color.r, color.g, color.b], i * 3);
    this.baseSize[i] = size;
    this.size[i] = size;
    this.alpha[i] = 1;
    this.life[i] = life;
    this.maxLife[i] = life;
    this.grav[i] = grav;
    this.drag[i] = drag;
  }

  burst(p: THREE.Vector3, n: number, speed: number, color: THREE.Color, size: number, life: number, grav = 0, spread?: THREE.Vector3) {
    for (let k = 0; k < n; k++) {
      tmp.set(Math.random() * 2 - 1, Math.random() * 2 - 1, Math.random() * 2 - 1).normalize();
      if (spread) tmp.add(spread).normalize();
      tmp.multiplyScalar(speed * (0.35 + Math.random() * 0.8));
      this.spawn(p, tmp, color, size * (0.6 + Math.random() * 0.7), life * (0.6 + Math.random() * 0.7), grav, 2.5);
    }
  }

  update(dt: number) {
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) {
        this.alpha[i] = 0;
        continue;
      }
      this.life[i] -= dt;
      const t = Math.max(0, this.life[i] / this.maxLife[i]);
      const dr = Math.exp(-this.drag[i] * dt);
      this.vel[i * 3] *= dr;
      this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * dr - this.grav[i] * dt;
      this.vel[i * 3 + 2] *= dr;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      if (this.pos[i * 3 + 1] < 0.02 && this.grav[i] > 0) {
        this.pos[i * 3 + 1] = 0.02;
        this.vel[i * 3 + 1] *= -0.2;
      }
      this.alpha[i] = t;
      this.size[i] = this.baseSize[i] * (0.4 + 0.6 * t);
    }
    const g = this.points.geometry;
    (g.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    (g.attributes.color as THREE.BufferAttribute).needsUpdate = true;
    (g.attributes.size as THREE.BufferAttribute).needsUpdate = true;
    (g.attributes.alpha as THREE.BufferAttribute).needsUpdate = true;
  }

  setScale(s: number) {
    this.material.uniforms.scale.value = s;
  }
}

// ------------------------------------------------------------------ weapon trails

const TRAIL_COLORS = {
  normal: new THREE.Color(0xdfe6ff),
  danger: new THREE.Color(0xff3020),
  ult: new THREE.Color(0xffc040),
};

export class Trail {
  mesh: THREE.Mesh;
  private samples: { b: THREE.Vector3; t: THREE.Vector3; age: number; k: number; c: THREE.Color }[] = [];
  private geo: THREE.BufferGeometry;
  private posArr: Float32Array;
  private colArr: Float32Array;
  private readonly N = 16;
  private readonly LIFE = 0.14;

  constructor() {
    this.geo = new THREE.BufferGeometry();
    this.posArr = new Float32Array(this.N * 2 * 3);
    this.colArr = new Float32Array(this.N * 2 * 4);
    this.geo.setAttribute('position', new THREE.BufferAttribute(this.posArr, 3));
    this.geo.setAttribute('color', new THREE.BufferAttribute(this.colArr, 4));
    const idx: number[] = [];
    for (let i = 0; i < this.N - 1; i++) {
      const a = i * 2;
      idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
    this.geo.setIndex(idx);
    this.mesh = new THREE.Mesh(
      this.geo,
      new THREE.MeshBasicMaterial({
        vertexColors: true,
        transparent: true,
        depthWrite: false,
        side: THREE.DoubleSide,
        blending: THREE.AdditiveBlending,
      }),
    );
    this.mesh.frustumCulled = false;
  }

  push(base: THREE.Vector3, tip: THREE.Vector3, k: number, kind: 'normal' | 'danger' | 'ult') {
    if (k <= 0.01) return;
    this.samples.unshift({ b: base.clone(), t: tip.clone(), age: 0, k, c: TRAIL_COLORS[kind] });
    if (this.samples.length > this.N) this.samples.length = this.N;
  }

  update(dt: number) {
    for (const s of this.samples) s.age += dt;
    this.samples = this.samples.filter((s) => s.age < this.LIFE);
    const n = this.samples.length;
    for (let i = 0; i < this.N; i++) {
      const s = this.samples[Math.min(i, n - 1)];
      if (!s || n < 2) {
        this.posArr.fill(0, i * 6, i * 6 + 6);
        this.colArr.fill(0, i * 8, i * 8 + 8);
        continue;
      }
      this.posArr.set([s.b.x, s.b.y, s.b.z, s.t.x, s.t.y, s.t.z], i * 6);
      const f = (1 - s.age / this.LIFE) * s.k * (i < n ? 1 : 0);
      const a = f * 0.55;
      this.colArr.set([s.c.r * a, s.c.g * a, s.c.b * a, a * 0.2, s.c.r * f, s.c.g * f, s.c.b * f, f], i * 8);
    }
    (this.geo.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    (this.geo.attributes.color as THREE.BufferAttribute).needsUpdate = true;
  }
}

// ------------------------------------------------------------------ one-shot effects

interface Timed {
  obj: THREE.Object3D;
  age: number;
  life: number;
  update: (t: number, obj: THREE.Object3D) => void;
}

export class Effects {
  group = new THREE.Group();
  sparks = new ParticleSystem(1600, true);
  dust = new ParticleSystem(700, false);
  private timed: Timed[] = [];
  private glowTex = glowTexture();
  flashScale = 1;
  private ringGeo = new THREE.RingGeometry(0.85, 1, 48);
  telegraphTex: Record<string, THREE.Texture> = {
    thrust: textTexture('危', 'THRUST', '#ff2a1a'),
    sweep: textTexture('危', 'SWEEP', '#ff2a1a'),
    slam: textTexture('危', 'SLAM', '#ff2a1a'),
    ult: textTexture('奥義', 'ULTIMATE', '#ffb020'),
  };

  constructor(parent: THREE.Scene) {
    parent.add(this.group);
    this.group.add(this.sparks.points, this.dust.points);
  }

  private add(obj: THREE.Object3D, life: number, update: Timed['update']) {
    this.group.add(obj);
    this.timed.push({ obj, age: 0, life, update });
  }

  flash(p: THREE.Vector3, color: number, size: number, life = 0.18) {
    size *= this.flashScale;
    const s = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: this.glowTex, color, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }),
    );
    s.position.copy(p);
    s.scale.setScalar(size);
    this.add(s, life, (t, o) => {
      const sp = o as THREE.Sprite;
      sp.material.opacity = 1 - t;
      sp.scale.setScalar(size * (1 + t * 0.6));
    });
  }

  ring(p: THREE.Vector3, color: number, from: number, to: number, life: number, flat: boolean, cam?: THREE.Camera) {
    const m = new THREE.Mesh(
      this.ringGeo,
      new THREE.MeshBasicMaterial({ color, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }),
    );
    m.position.copy(p);
    if (flat) m.rotation.x = -Math.PI / 2;
    else if (cam) m.quaternion.copy(cam.quaternion);
    this.add(m, life, (t, o) => {
      const mm = o as THREE.Mesh;
      const e = 1 - (1 - t) * (1 - t);
      mm.scale.setScalar(from + (to - from) * e);
      (mm.material as THREE.MeshBasicMaterial).opacity = 1 - t;
    });
  }

  /** Red danger kanji over an attacker's head during an unblockable wind-up. */
  telegraph(getPos: () => THREE.Vector3, kind: string, life: number) {
    const tex = this.telegraphTex[kind] ?? this.telegraphTex.thrust;
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true, depthWrite: false }));
    s.renderOrder = 10;
    s.scale.setScalar(0.6);
    this.add(s, life, (t, o) => {
      const sp = o as THREE.Sprite;
      sp.position.copy(getPos()).add(new THREE.Vector3(0, 0.72, 0));
      const pop = t < 0.12 ? 0.6 + (t / 0.12) * 0.6 : 1.2 - Math.min(0.2, (t - 0.12) * 0.5);
      sp.scale.setScalar(0.62 * pop);
      sp.material.opacity = t > 0.85 ? (1 - t) / 0.15 : 1;
    });
  }

  /** The katana ultimate's travelling crescent. */
  wave(origin: THREE.Vector3, yaw: number, kind: 'vertical' | 'horizontal', speed: number, range: number) {
    const g = new THREE.Group();
    const arc = new THREE.Mesh(
      new THREE.TorusGeometry(kind === 'horizontal' ? 9 : 1.6, 0.06, 6, 48, Math.PI * (kind === 'horizontal' ? 0.9 : 0.9)),
      new THREE.MeshBasicMaterial({ color: 0xbfe4ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }),
    );
    const glow = new THREE.Mesh(
      new THREE.TorusGeometry(kind === 'horizontal' ? 9 : 1.6, 0.22, 6, 48, Math.PI * 0.9),
      new THREE.MeshBasicMaterial({ color: 0x5aa0ff, transparent: true, opacity: 0.35, blending: THREE.AdditiveBlending, depthWrite: false }),
    );
    for (const m of [arc, glow]) {
      if (kind === 'horizontal') {
        // lie flat with the crescent's tip leading, just ahead of the wave's origin
        m.rotation.x = Math.PI / 2;
        m.rotation.z = Math.PI * 0.05;
        m.position.set(0, 0.85, -8.6);
      } else {
        m.rotation.y = Math.PI / 2;
        m.rotation.x = Math.PI * 0.05;
        m.position.set(0, 0.2, 0);
      }
      g.add(m);
    }
    g.position.copy(origin);
    g.rotation.y = yaw;
    const dir = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
    const life = range / speed;
    this.add(g, life, (t, o) => {
      o.position.copy(origin).addScaledVector(dir, range * t);
      o.traverse((c) => {
        const mat = (c as THREE.Mesh).material as THREE.MeshBasicMaterial | undefined;
        if (mat) mat.opacity = (c === glow ? 0.35 : 1) * (1 - t * 0.6);
      });
    });
  }

  lightning(from: THREE.Vector3, to: THREE.Vector3, color = 0xa0d8ff, life = 0.35) {
    const n = 14;
    const geo = new THREE.BufferGeometry();
    const arr = new Float32Array(n * 3);
    geo.setAttribute('position', new THREE.BufferAttribute(arr, 3));
    const line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color, transparent: true, blending: THREE.AdditiveBlending }));
    line.frustumCulled = false;
    const jitter = () => {
      for (let i = 0; i < n; i++) {
        const t = i / (n - 1);
        const p = from.clone().lerp(to, t);
        const j = i === 0 || i === n - 1 ? 0 : 0.35;
        arr.set([p.x + (Math.random() - 0.5) * j, p.y + (Math.random() - 0.5) * j, p.z + (Math.random() - 0.5) * j], i * 3);
      }
      geo.attributes.position.needsUpdate = true;
    };
    jitter();
    this.add(line, life, (t, o) => {
      jitter();
      ((o as THREE.Line).material as THREE.LineBasicMaterial).opacity = 1 - t;
    });
  }

  /** A slow glowing column marking a dropped weapon. */
  beam(getPos: () => THREE.Vector3 | null, color: number) {
    const m = new THREE.Mesh(
      new THREE.CylinderGeometry(0.05, 0.25, 3.5, 12, 1, true),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.35, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }),
    );
    const ring = new THREE.Mesh(
      this.ringGeo,
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }),
    );
    ring.rotation.x = -Math.PI / 2;
    const g = new THREE.Group();
    g.add(m, ring);
    m.position.y = 1.75;
    ring.position.y = 0.03;
    this.add(g, 1e9, (t, o) => {
      const p = getPos();
      if (!p) {
        o.visible = false;
        return;
      }
      o.visible = true;
      o.position.set(p.x, 0, p.z);
      const pulse = 0.8 + Math.sin(performance.now() * 0.006) * 0.2;
      ring.scale.setScalar(0.7 * pulse);
      (m.material as THREE.MeshBasicMaterial).opacity = 0.25 * pulse;
    });
    return () => {
      const i = this.timed.findIndex((x) => x.obj === g);
      if (i >= 0) {
        this.group.remove(g);
        this.timed.splice(i, 1);
      }
    };
  }

  clearAll() {
    for (const t of this.timed) this.group.remove(t.obj);
    this.timed = [];
  }

  update(dt: number) {
    this.sparks.update(dt);
    this.dust.update(dt);
    for (const e of this.timed) {
      e.age += dt;
      e.update(Math.min(1, e.age / e.life), e.obj);
    }
    const dead = this.timed.filter((e) => e.age >= e.life);
    for (const d of dead) {
      this.group.remove(d.obj);
      d.obj.traverse((o) => {
        const mat = (o as THREE.Mesh).material as THREE.Material | undefined;
        if (mat && mat !== undefined) mat.dispose();
      });
    }
    this.timed = this.timed.filter((e) => e.age < e.life);
  }
}
