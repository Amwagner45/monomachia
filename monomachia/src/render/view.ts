// The renderer: scene, camera, arena, fighter puppets and effects, driven by
// the simulation state and its events.

import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import type { World } from '../sim/world';
import type { SimEvent } from '../sim/events';
import { WAVE_RANGE, WAVE_SPEED } from '../sim/world';
import { getMove } from '../sim/moves';
import { Arena } from './arena';
import { CamMode, CameraRig } from './camera';
import { FighterRig, PALETTES } from './rig';
import { Effects, Trail } from './vfx';
import { WeaponModel, buildWeapon } from './weaponMesh';

export type Quality = 'high' | 'low';

const C = (hex: number) => new THREE.Color(hex);
const V = (p: { x: number; y: number; z: number }) => new THREE.Vector3(p.x, p.y, p.z);

/** The simplest stand-in for a material whose shader cannot be built on this device. */
function plainMaterial(o: THREE.Object3D, mat: THREE.Material): THREE.Material {
  const src = mat as THREE.Material & { color?: THREE.Color; map?: THREE.Texture | null };
  const additive = mat.blending === THREE.AdditiveBlending;
  const color = src.color ?? C(additive ? 0xffb070 : 0x2a1418);
  const common = { transparent: mat.transparent, opacity: mat.opacity, depthWrite: mat.depthWrite, blending: mat.blending, side: mat.side };
  const out = (o as THREE.Points).isPoints
    ? new THREE.PointsMaterial({ ...common, color, size: 0.08 })
    : (o as THREE.Line).isLine
      ? new THREE.LineBasicMaterial({ ...common, color })
      : new THREE.MeshBasicMaterial({ ...common, color, map: src.map ?? null });
  out.userData.plain = true;
  return out;
}

export class View {
  renderer: THREE.WebGLRenderer;
  scene = new THREE.Scene();
  cam: CameraRig;
  cam2: CameraRig;
  split = false;
  arena: Arena;
  rigs: FighterRig[] = [];
  trails: Trail[][] = [];
  fx: Effects;
  composer: EffectComposer | null = null;
  bloom: UnrealBloomPass | null = null;
  quality: Quality;
  shaderErrors: string[] = [];
  safeLevel = 0;
  onSafeMode: ((level: number) => void) | null = null;
  private recoverPending = false;
  private recoverTick = 0;
  private dropped = new Map<number, WeaponModel>();
  private beams = new Map<number, () => void>();
  private world: World | null = null;
  playerIndex = 0;
  camMode: CamMode = 'menu';
  private auraTimer = 0;
  private _reduced = false;

  get reduced() {
    return this._reduced;
  }
  set reduced(v: boolean) {
    this._reduced = v;
    this.fx.flashScale = v ? 0.45 : 1;
    this.cam.shakeScale = v ? 0.15 : 1;
    this.cam.fovScale = v ? 0 : 1;
  }

  constructor(public container: HTMLElement, quality: Quality) {
    this.quality = quality;
    const r = new THREE.WebGLRenderer({ antialias: quality === 'high', powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, quality === 'high' ? 2 : 1));
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFShadowMap;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.05;
    r.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(r.domElement);
    this.renderer = r;
    // Never fail silently: record shader errors and fall back to simpler graphics.
    r.debug.checkShaderErrors = true;
    r.debug.onShaderError = (gl, program, vs, fsh) => {
      const log = [gl.getProgramInfoLog(program), gl.getShaderInfoLog(vs), gl.getShaderInfoLog(fsh)].filter(Boolean).join(' | ');
      console.error('Monomachia shader error:', log.slice(0, 600));
      this.shaderErrors.push(log.slice(0, 600));
      (window as unknown as { __shaderErrors: string[] }).__shaderErrors = this.shaderErrors;
      this.recoverPending = true; // handled right after this frame is drawn
    };

    this.scene.fog = new THREE.FogExp2(0x1d0d10, 0.021);
    this.scene.background = new THREE.Color(0x0a0608);
    const pmrem = new THREE.PMREMGenerator(r);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environmentIntensity = 0.28;

    this.cam = new CameraRig(1);
    this.cam2 = new CameraRig(1);
    this.arena = new Arena(this.scene, quality);
    this.fx = new Effects(this.scene);

    this.setupComposer();
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  private setupComposer() {
    const r = this.renderer;
    if (this.quality !== 'high') {
      this.composer = null;
      return;
    }
    const composer = new EffectComposer(r);
    composer.addPass(new RenderPass(this.scene, this.cam.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.5, 0.4, 0.88);
    composer.addPass(this.bloom);
    composer.addPass(new OutputPass());
    this.composer = composer;
  }

  /**
   * After a shader failure: step down to simpler lighting (which rebuilds every
   * shader), and when there is nothing simpler left, give whatever still fails
   * the plainest material of its kind, so one broken effect can never blank the
   * whole picture.
   */
  private recover() {
    const props = this.renderer.properties;
    const isBroken = (mat: THREE.Material) => {
      const prog = (props.get(mat) as { currentProgram?: { diagnostics?: { runnable: boolean } } }).currentProgram;
      return !!prog?.diagnostics && !prog.diagnostics.runnable;
    };
    const broken: THREE.Object3D[] = [];
    let lit = false;
    this.scene.traverse((o) => {
      const mats = (o as THREE.Mesh).material;
      if (!mats) return;
      const bad = (Array.isArray(mats) ? mats : [mats]).filter(isBroken);
      if (!bad.length) return;
      broken.push(o);
      lit ||= bad.some((m) => m instanceof THREE.MeshStandardMaterial || m instanceof THREE.MeshPhongMaterial || m instanceof THREE.MeshLambertMaterial);
    });
    if (!broken.length) {
      this.recoverPending = false;
      return;
    }
    // lit surfaces failing means the lighting is too much for this device
    if (lit && this.safeLevel < 2) {
      this.fallBack(); // check again once the rebuilt shaders have been used
      return;
    }
    const fix = (o: THREE.Object3D, x: THREE.Material) => {
      if (!isBroken(x)) return x;
      if (x instanceof THREE.MeshStandardMaterial) return this.toPhong(x);
      if (x.userData.plain) {
        o.visible = false; // even the plainest material fails: hide it rather than keep retrying
        return x;
      }
      return plainMaterial(o, x);
    };
    for (const o of broken) {
      const m = o as THREE.Mesh;
      m.material = Array.isArray(m.material) ? m.material.map((x) => fix(o, x)) : fix(o, m.material);
    }
    this.recoverPending = false;
  }

  private phong = new WeakMap<THREE.Material, THREE.Material>();

  /** A simpler lit stand-in for a physically based material. */
  private toPhong(mat: THREE.Material): THREE.Material {
    if (!(mat instanceof THREE.MeshStandardMaterial)) return mat;
    let out = this.phong.get(mat);
    if (!out) {
      const shiny = 1 - mat.roughness;
      const spec = 0.1 + 0.5 * mat.metalness;
      const p = new THREE.MeshPhongMaterial({
        map: mat.map, specular: new THREE.Color(spec, spec, spec), shininess: 6 + 60 * shiny * shiny,
        transparent: mat.transparent, side: mat.side,
      });
      // The game animates the original material (hit flashes, blade glow), so the
      // stand-in shares its colours and reads its animated numbers live.
      p.color = mat.color;
      p.emissive = mat.emissive;
      for (const k of ['emissiveIntensity', 'opacity'] as const) {
        Object.defineProperty(p, k, { get: () => mat[k], set: (v: number) => (mat[k] = v), configurable: true });
      }
      out = p;
      this.phong.set(mat, out);
    }
    return out;
  }

  /** Step down to simpler lighting after a shader failure. */
  fallBack() {
    if (this.safeLevel >= 2) return;
    this.safeLevel++;
    const r = this.renderer;
    if (this.safeLevel === 1) {
      r.shadowMap.enabled = false;
      this.scene.environment = null;
      for (const l of this.arena.lanternLights) l.visible = false;
      // make up for the lost reflections and lantern glow so fighters stay readable
      this.arena.hemi.intensity = 1.9;
    } else {
      // last resort: swap every physically based material for a simpler Phong one
      // (if even that fails, recover() gives it an unlit material)
      this.scene.traverse((o) => {
        const m = o as THREE.Mesh;
        if (!m.isMesh) return;
        m.material = Array.isArray(m.material) ? m.material.map((x) => this.toPhong(x)) : this.toPhong(m.material);
      });
    }
    this.scene.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      for (const mat of Array.isArray(m.material) ? m.material : [m.material]) mat.needsUpdate = true;
    });
    this.onSafeMode?.(this.safeLevel);
  }

  setQuality(q: Quality) {
    if (q === this.quality) return;
    this.quality = q;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, q === 'high' ? 2 : 1));
    this.setupComposer();
    this.resize();
  }

  setSplit(on: boolean) {
    this.split = on;
    this.resize();
  }

  resize() {
    const w = this.container.clientWidth || window.innerWidth;
    const h = this.container.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h);
    const aspect = this.split ? w / 2 / h : w / h;
    for (const c of [this.cam, this.cam2]) {
      c.camera.aspect = aspect;
      c.camera.updateProjectionMatrix();
    }
    if (this.composer) this.composer.setSize(w, h);
    const px = this.renderer.getPixelRatio() * h;
    const scale = px / (2 * Math.tan((this.cam.camera.fov * Math.PI) / 360));
    this.fx.sparks.setScale(scale);
    this.fx.dust.setScale(scale);
  }

  /** Build puppets for a world's fighters. */
  bindWorld(world: World) {
    this.world = world;
    for (const rig of this.rigs) {
      this.scene.remove(rig.root);
      rig.dispose();
    }
    for (const tr of this.trails) for (const t of tr) this.scene.remove(t.mesh);
    this.rigs = [];
    this.trails = [];
    world.fighters.forEach((f, i) => {
      const rig = new FighterRig(PALETTES[i], f.weapon.id);
      this.scene.add(rig.root);
      this.rigs.push(rig);
      const tr = [new Trail(), new Trail()];
      for (const t of tr) this.scene.add(t.mesh);
      this.trails.push(tr);
    });
    this.clearTransient();
    this.cam.koOrbit = 0;
    this.cam2.koOrbit = 0;
    this.cam.snap(world.fighters[this.playerIndex], world.fighters[1 - this.playerIndex], this.camMode);
    this.cam2.snap(world.fighters[1], world.fighters[0], this.camMode);
  }

  clearTransient() {
    for (const m of this.dropped.values()) this.scene.remove(m.group);
    this.dropped.clear();
    for (const rm of this.beams.values()) rm();
    this.beams.clear();
    this.fx.clearAll();
  }

  // ------------------------------------------------------------------ events -> effects

  handleEvents(events: SimEvent[]) {
    const W = this.world;
    if (!W) return;
    const fx = this.fx;
    const both = [this.cam, this.cam2];
    const cam = {
      camera: this.cam.camera,
      addShake: (a: number) => both.forEach((c) => c.addShake(a)),
      kickFov: (a: number) => both.forEach((c) => c.kickFov(a)),
    };
    for (const e of events) {
      switch (e.t) {
        case 'hit': {
          const p = V(e.pos);
          const heavy = e.heavy;
          const target = this.rigs[e.target];
          target?.hitFlash(e.sound === 'fist' ? 0xfff0e0 : 0xff6040, heavy ? 0.55 : 0.4);
          target?.shake(heavy ? 1 : 0.6);
          fx.sparks.burst(p, heavy ? 36 : 18, heavy ? 7 : 5, C(0xffb060), 0.09, 0.35, 6);
          if (e.sound !== 'fist') fx.dust.burst(p, heavy ? 22 : 12, 3.2, C(0x5a0808), 0.07, 0.7, 9);
          else fx.dust.burst(p, 10, 2.5, C(0x9a8a80), 0.1, 0.4, 2);
          if (e.sound === 'colossal') {
            fx.dust.burst(new THREE.Vector3(p.x, 0.1, p.z), 26, 3.5, C(0x6a5a50), 0.18, 0.9, 3, new THREE.Vector3(0, 0.6, 0));
            fx.ring(new THREE.Vector3(p.x, 0.04, p.z), 0xffa060, 0.3, 2.6, 0.45, true);
          }
          fx.flash(p, 0xffc8a0, heavy ? 0.7 : 0.45, 0.1);
          cam.addShake(heavy ? 0.45 : 0.2);
          if (e.backstab) fx.flash(p, 0xa060ff, 0.9, 0.2);
          break;
        }
        case 'block': {
          const p = V(e.pos);
          fx.sparks.burst(p, e.heavy ? 40 : 22, 6, C(0xffd890), 0.07, 0.3, 8);
          fx.flash(p, 0xfff0c0, e.heavy ? 0.6 : 0.4, 0.08);
          this.rigs[e.target]?.shake(0.4);
          cam.addShake(e.heavy ? 0.3 : 0.12);
          break;
        }
        case 'parry': {
          const p = V(e.pos);
          const color = e.kind === 'flash' ? 0x9ad8ff : e.kind === 'redirect' ? 0x7affd6 : 0xfff2c0;
          fx.flash(p, color, 1.0, 0.16);
          fx.ring(p, color, 0.1, 0.8, 0.22, false, cam.camera);
          fx.sparks.burst(p, 60, 8, C(0xffe6a0), 0.07, 0.4, 7);
          cam.addShake(0.35);
          cam.kickFov(e.kind === 'parry' ? 3 : 5);
          break;
        }
        case 'counter': {
          const p = V(e.pos);
          fx.flash(p, 0x9ad8ff, 1.0, 0.2);
          fx.ring(new THREE.Vector3(p.x, 0.05, p.z), 0x9ad8ff, 0.3, 2.4, 0.45, true);
          fx.sparks.burst(p, 50, 7, C(0xbfe6ff), 0.08, 0.5, 6);
          if (e.kind !== 'leap') fx.dust.burst(new THREE.Vector3(p.x, 0.1, p.z), 24, 3, C(0x7a6a60), 0.16, 0.8, 3, new THREE.Vector3(0, 0.5, 0));
          cam.addShake(0.5);
          cam.kickFov(6);
          break;
        }
        case 'evade': {
          const f = W.fighters[e.f];
          fx.flash(new THREE.Vector3(f.pos.x, 1.2, f.pos.z), 0x88aaff, 0.6, 0.12);
          break;
        }
        case 'disarm': {
          const p = V(e.pos);
          fx.flash(p, 0xffffff, 1.4, 0.25);
          fx.ring(p, 0xffe0a0, 0.2, 1.4, 0.35, false, cam.camera);
          fx.sparks.burst(p, 110, 11, C(0xffd080), 0.09, 0.6, 8);
          cam.addShake(0.8);
          cam.kickFov(7);
          break;
        }
        case 'stagger': {
          const f = W.fighters[e.f];
          fx.flash(new THREE.Vector3(f.pos.x, 1.9, f.pos.z), 0xffe070, 0.7, 0.3);
          break;
        }
        case 'telegraph': {
          const f = W.fighters[e.f];
          const rig = this.rigs[e.f];
          let life = 0.8;
          if (e.kind !== 'ult') {
            try {
              life = getMove(f.moveset, e.attack).startup / 60 + 0.12;
            } catch {
              life = 0.6;
            }
          }
          fx.telegraph(() => rig.headWorld, e.kind, life);
          fx.flash(rig.headWorld.clone().add(new THREE.Vector3(0, 0.75, 0)), e.kind === 'ult' ? 0xffb020 : 0xff2010, 0.7, 0.2);
          break;
        }
        case 'dodge':
        case 'land':
        case 'jump': {
          const f = W.fighters[e.f];
          fx.dust.burst(new THREE.Vector3(f.pos.x, 0.08, f.pos.z), e.t === 'land' ? 10 : 8, 1.6, C(0x6a5e56), 0.14, 0.55, 1, new THREE.Vector3(0, 0.3, 0));
          break;
        }
        case 'ultStart': {
          const f = W.fighters[e.f];
          fx.ring(new THREE.Vector3(f.pos.x, 0.05, f.pos.z), 0xffb020, 0.3, 3.2, 0.6, true);
          fx.flash(new THREE.Vector3(f.pos.x, 1.2, f.pos.z), 0xffb020, 1.2, 0.3);
          cam.kickFov(8);
          break;
        }
        case 'ultChoice': {
          const f = W.fighters[e.f];
          fx.ring(new THREE.Vector3(f.pos.x, 0.05, f.pos.z), 0x7affd6, 0.3, 2.5, 0.8, true);
          break;
        }
        case 'ultWave':
          // the simulated wave starts 0.6 m in front of the caster
          fx.wave(new THREE.Vector3(e.pos.x + Math.sin(e.yaw) * 0.6, 0, e.pos.z + Math.cos(e.yaw) * 0.6), e.yaw, e.kind, WAVE_SPEED, WAVE_RANGE);
          fx.flash(new THREE.Vector3(e.pos.x, 1.2, e.pos.z), 0xbfe4ff, 1.4, 0.25);
          cam.addShake(0.5);
          break;
        case 'ultDash': {
          const f = W.fighters[e.f];
          fx.dust.burst(new THREE.Vector3(f.pos.x, 0.1, f.pos.z), 30, 4, C(0x7a6a60), 0.18, 0.8, 2);
          break;
        }
        case 'ultImpale': {
          const t = W.fighters[e.target];
          const p = new THREE.Vector3(t.pos.x, 1.3, t.pos.z);
          fx.flash(p, 0xff3020, 1.0, 0.25);
          fx.dust.burst(p, 40, 4, C(0x5a0808), 0.08, 0.9, 9);
          cam.addShake(0.6);
          break;
        }
        case 'ultBurst': {
          const p = V(e.pos);
          fx.flash(p, 0xffa040, 2.4, 0.4);
          fx.ring(p, 0xffc060, 0.3, 3.2, 0.5, false, cam.camera);
          fx.ring(new THREE.Vector3(p.x, 0.05, p.z), 0xff8030, 0.5, 6, 0.7, true);
          fx.sparks.burst(p, 220, 14, C(0xffb050), 0.12, 0.8, 5);
          cam.addShake(1.2);
          cam.kickFov(10);
          break;
        }
        case 'ultLightning':
          fx.lightning(V(e.from), V(e.to));
          fx.flash(V(e.to), 0xa0d8ff, 1.1, 0.2);
          fx.flash(V(e.from), 0xa0d8ff, 0.8, 0.18);
          cam.addShake(0.3);
          break;
        case 'recall':
        case 'pickup': {
          const rig = this.rigs[e.f];
          fx.flash(rig.handWorldR.clone(), 0xffe0a0, 0.8, 0.25);
          break;
        }
        case 'weaponBounce':
          fx.sparks.burst(V(e.pos), 10, 3, C(0xffd080), 0.05, 0.25, 8);
          break;
        case 'counterReady':
        case 'backstabReady': {
          const f = W.fighters[e.f];
          fx.flash(new THREE.Vector3(f.pos.x, 1.1, f.pos.z), e.t === 'counterReady' ? 0x9ad8ff : 0xa060ff, 0.8, 0.25);
          break;
        }
        case 'ko': {
          const loser = e.loser >= 0 ? W.fighters[e.loser] : null;
          if (loser) fx.flash(new THREE.Vector3(loser.pos.x, 1.2, loser.pos.z), 0xffffff, 1.4, 0.35);
          cam.addShake(0.7);
          if (!this.split) this.cam.koOrbit = 0.001;
          break;
        }
        case 'roundStart':
          this.clearTransient();
          this.cam.koOrbit = 0;
          this.cam2.koOrbit = 0;
          break;
      }
    }
  }

  // ------------------------------------------------------------------ per-frame

  render(dt: number, time: number, alpha: number) {
    this.update(dt, time, alpha);
    this.draw(dt);
  }

  draw(dt: number) {
    if (this.split) {
      const r = this.renderer;
      const w = this.container.clientWidth || window.innerWidth;
      const h = this.container.clientHeight || window.innerHeight;
      const half = Math.floor(w / 2);
      r.setScissorTest(true);
      r.setViewport(0, 0, half, h);
      r.setScissor(0, 0, half, h);
      r.render(this.scene, this.cam.camera);
      r.setViewport(half, 0, w - half, h);
      r.setScissor(half, 0, w - half, h);
      r.render(this.scene, this.cam2.camera);
      r.setScissorTest(false);
      r.setViewport(0, 0, w, h);
    } else if (this.composer) this.composer.render(dt);
    else this.renderer.render(this.scene, this.cam.camera);
    // after any failure, also look twice a second for new objects (a new match's
    // fighters, a dropped weapon) that picked up an already-broken shader
    if (this.recoverPending || (this.shaderErrors.length > 0 && ++this.recoverTick % 30 === 0)) this.recover();
  }

  /** Advance animation and effects without drawing (cheap). */
  update(dt: number, time: number, alpha: number) {
    const W = this.world;
    if (W) {
      W.fighters.forEach((f, i) => {
        const rig = this.rigs[i];
        rig.update(f, time, dt, alpha);
        const res = rig.lastResult;
        const [tr, tl] = this.trails[i];
        if (res && res.trail > 0 && f.armed) {
          tr.push(rig.bladeBaseR, rig.bladeTipR, res.trail, res.trailKind);
          if (rig.weaponL) tl.push(rig.bladeBaseL, rig.bladeTipL, res.trail, res.trailKind);
        }
        tr.update(dt);
        tl.update(dt);
      });
      this.updateDropped();
      this.updateAuras(dt);
      const me = W.fighters[this.playerIndex];
      const opp = W.fighters[1 - this.playerIndex];
      this.cam.update(dt, me, opp, this.camMode);
      if (this.split) this.cam2.update(dt, W.fighters[1], W.fighters[0], this.camMode);
    }
    this.arena.update(time, dt);
    this.fx.update(dt);
  }

  private updateAuras(dt: number) {
    const W = this.world!;
    this.auraTimer += dt;
    if (this.auraTimer < 1 / 45) return;
    this.auraTimer = 0;
    W.fighters.forEach((f, i) => {
      if (!f.canUlt() || f.state === 'ko') return;
      const color = C(i === 0 ? 0xff5a20 : 0x40c8ff);
      for (let k = 0; k < 3; k++) {
        const a = Math.random() * Math.PI * 2;
        const r = 0.35 + Math.random() * 0.15;
        const p = new THREE.Vector3(f.pos.x + Math.sin(a) * r, f.pos.y + Math.random() * 1.7, f.pos.z + Math.cos(a) * r);
        this.fx.sparks.spawn(p, new THREE.Vector3(0, 1.2 + Math.random(), 0), color, 0.16, 0.5, -0.5, 1.5);
      }
    });
  }

  private updateDropped() {
    const W = this.world!;
    const present = new Set<number>();
    for (const w of W.weapons) {
      present.add(w.owner);
      let m = this.dropped.get(w.owner);
      if (!m) {
        m = buildWeapon(w.weaponId) ?? undefined;
        if (!m) continue;
        m.group.traverse((o) => ((o as THREE.Mesh).castShadow = true));
        this.scene.add(m.group);
        this.dropped.set(w.owner, m);
        if (w.weaponId === 'daggers') {
          const second = buildWeapon('daggers')!;
          second.group.position.set(0.1, 0, 0.12);
          second.group.rotation.set(0, 0, 0.4);
          m.group.add(second.group);
        }
      }
      m.group.position.set(w.pos.x, w.pos.y + (w.grounded ? 0.02 : 0), w.pos.z);
      m.group.rotation.order = 'YXZ';
      m.group.rotation.set(w.grounded ? Math.PI / 2 : w.tumble, w.yaw, 0);
      if (w.grounded && !this.beams.has(w.owner)) {
        const owner = w.owner;
        const color = owner === 0 ? 0xff6a3a : 0x5ad0ff;
        this.beams.set(
          owner,
          this.fx.beam(() => {
            const ww = this.world?.weaponOf(owner);
            return ww ? new THREE.Vector3(ww.pos.x, 0, ww.pos.z) : null;
          }, color),
        );
      }
    }
    for (const [owner, m] of [...this.dropped]) {
      if (!present.has(owner)) {
        this.scene.remove(m.group);
        this.dropped.delete(owner);
        const rm = this.beams.get(owner);
        if (rm) rm();
        this.beams.delete(owner);
      }
    }
  }

  /** Project a world point to screen pixels (for HUD markers), for a player's view. */
  project(p: THREE.Vector3, player = 0) {
    const cam = this.split && player === 1 ? this.cam2 : this.cam;
    const v = p.clone().project(cam.camera);
    const W = this.renderer.domElement.clientWidth;
    const h = this.renderer.domElement.clientHeight;
    const w = this.split ? W / 2 : W;
    const x0 = this.split && player === 1 ? W / 2 : 0;
    return { x: x0 + (v.x * 0.5 + 0.5) * w, y: (-v.y * 0.5 + 0.5) * h, behind: v.z > 1, x0, w };
  }
}
