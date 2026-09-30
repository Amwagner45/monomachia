// "Moonlit Shrine" arena: a round stone courtyard, torii gate, stone lanterns,
// broken pillars, distant mountains, a blood-red moon, embers and ash.

import * as THREE from 'three';
import { ARENA_RADIUS } from '../sim/constants';
import { Rng } from '../sim/rng';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { glowTexture, noiseTexture, stoneFloorTextures } from './textures';

export class Arena {
  group = new THREE.Group();
  lanternLights: THREE.PointLight[] = [];
  moonLight: THREE.DirectionalLight;
  hemi!: THREE.HemisphereLight;
  private embers: THREE.Points;
  private emberVel: Float32Array;
  private ash: THREE.Points;
  private flameSprites: THREE.Sprite[] = [];
  private rng = new Rng(99);
  moonDir = new THREE.Vector3(0.25, 0.42, 1).normalize();

  constructor(scene: THREE.Scene, quality: 'high' | 'low') {
    const G = this.group;
    scene.add(G);
    const rng = this.rng;

    // --- sky dome with a vertical gradient
    const skyMat = new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      uniforms: {
        top: { value: new THREE.Color(0x050409) },
        mid: { value: new THREE.Color(0x1a0a10) },
        horizon: { value: new THREE.Color(0x4a1512) },
        moonDir: { value: this.moonDir },
      },
      vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `uniform vec3 top; uniform vec3 mid; uniform vec3 horizon; uniform vec3 moonDir; varying vec3 vDir;
        void main(){ float h = clamp(vDir.y, -0.2, 1.0);
          vec3 c = mix(horizon, mid, smoothstep(-0.02, 0.18, h));
          c = mix(c, top, smoothstep(0.18, 0.75, h));
          float m = max(dot(normalize(vDir), normalize(moonDir)), 0.0);
          c += vec3(0.55,0.12,0.06) * pow(m, 18.0) * 0.8 + vec3(0.3,0.05,0.03) * pow(m, 4.0) * 0.25;
          gl_FragColor = vec4(c, 1.0); }`,
    });
    const sky = new THREE.Mesh(new THREE.SphereGeometry(420, 32, 16), skyMat);
    G.add(sky);

    // moon
    const moon = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: glowTexture('rgba(255,190,150,1)', 'rgba(255,60,30,0)'), color: 0xffc0a0, fog: false, depthWrite: false, transparent: true }),
    );
    moon.position.copy(this.moonDir).multiplyScalar(380);
    moon.scale.setScalar(120);
    G.add(moon);
    const moonDisc = new THREE.Mesh(
      new THREE.CircleGeometry(14, 40),
      new THREE.MeshBasicMaterial({ color: 0xff9a7a, fog: false }),
    );
    moonDisc.position.copy(this.moonDir).multiplyScalar(370);
    moonDisc.lookAt(0, 0, 0);
    G.add(moonDisc);

    // stars
    {
      const n = 600;
      const pos = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        const u = rng.range(0.12, 1);
        const a = rng.range(0, Math.PI * 2);
        const r = Math.sqrt(1 - u * u);
        pos.set([Math.cos(a) * r * 400, u * 400, Math.sin(a) * r * 400], i * 3);
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      G.add(new THREE.Points(geo, new THREE.PointsMaterial({ color: 0x8a8090, size: 1.2, sizeAttenuation: false, fog: false })));
    }

    // --- floor
    const { map, bumpMap } = stoneFloorTextures(quality === 'high' ? 2048 : 1024);
    const floorR = ARENA_RADIUS + 0.9;
    const floor = new THREE.Mesh(
      new THREE.CircleGeometry(floorR, 96),
      new THREE.MeshStandardMaterial({ map, bumpMap, bumpScale: 1.5, roughness: 0.88, metalness: 0.05 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    G.add(floor);
    const stoneMat = new THREE.MeshStandardMaterial({ map: noiseTexture([58, 53, 50], 18, 256, 3, 4), roughness: 0.92 });
    const rim = new THREE.Mesh(new THREE.CylinderGeometry(floorR, floorR + 0.4, 0.45, 96, 1, true), stoneMat);
    rim.position.y = -0.225;
    G.add(rim);
    const ground = new THREE.Mesh(
      new THREE.CircleGeometry(200, 48),
      new THREE.MeshStandardMaterial({ map: noiseTexture([28, 22, 22], 10, 256, 5, 60), roughness: 1 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.45;
    ground.receiveShadow = true;
    G.add(ground);

    // --- low balustrade around the ring
    const wallR = ARENA_RADIUS + 0.45;
    const postGeo = new THREE.BoxGeometry(0.34, 0.95, 0.34);
    const capGeo = new THREE.BoxGeometry(0.44, 0.12, 0.44);
    const posts = 36;
    for (let i = 0; i < posts; i++) {
      const a = (i / posts) * Math.PI * 2;
      const x = Math.sin(a) * wallR;
      const z = Math.cos(a) * wallR;
      const p = new THREE.Mesh(postGeo, stoneMat);
      p.position.set(x, 0.47, z);
      p.rotation.y = a;
      p.castShadow = true;
      p.receiveShadow = true;
      G.add(p);
      const cap = new THREE.Mesh(capGeo, stoneMat);
      cap.position.set(x, 1.0, z);
      cap.rotation.y = a;
      G.add(cap);
      // rail to the next post
      const a2 = ((i + 1) / posts) * Math.PI * 2;
      const mx = (Math.sin(a) + Math.sin(a2)) * 0.5 * wallR;
      const mz = (Math.cos(a) + Math.cos(a2)) * 0.5 * wallR;
      const len = 2 * wallR * Math.sin(Math.PI / posts);
      const rail = new THREE.Mesh(new THREE.BoxGeometry(len, 0.14, 0.18), stoneMat);
      rail.position.set(mx, 0.72, mz);
      rail.rotation.y = (a + a2) / 2 + Math.PI / 2;
      rail.castShadow = true;
      G.add(rail);
      const rail2 = rail.clone();
      rail2.position.y = 0.3;
      G.add(rail2);
    }

    // --- torii gate beyond the far side
    const lacquer = new THREE.MeshStandardMaterial({ color: 0x6e1510, roughness: 0.65, metalness: 0.05 });
    const black = new THREE.MeshStandardMaterial({ color: 0x0e0c0d, roughness: 0.7 });
    const torii = new THREE.Group();
    for (const s of [-1, 1]) {
      const pillar = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.4, 8.4, 16), lacquer);
      pillar.position.set(3.4 * s, 4.2, 0);
      pillar.castShadow = true;
      torii.add(pillar);
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.55, 0.6, 16), black);
      base.position.set(3.4 * s, 0.3, 0);
      torii.add(base);
    }
    const kasagi = new THREE.Mesh(new THREE.BoxGeometry(10.4, 0.5, 0.75), black);
    kasagi.position.y = 8.45;
    kasagi.castShadow = true;
    const shimaki = new THREE.Mesh(new THREE.BoxGeometry(9.6, 0.4, 0.6), lacquer);
    shimaki.position.y = 8.0;
    const nuki = new THREE.Mesh(new THREE.BoxGeometry(8.6, 0.35, 0.4), lacquer);
    nuki.position.y = 6.7;
    const strut = new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.1, 0.35), lacquer);
    strut.position.y = 7.3;
    const plaque = new THREE.Mesh(new THREE.BoxGeometry(0.9, 1.2, 0.1), black);
    plaque.position.set(0, 7.35, 0.25);
    for (const s of [-1, 1]) {
      const tip = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.45, 0.72), black);
      tip.position.set(5.5 * s, 8.6, 0);
      tip.rotation.z = -0.18 * s;
      torii.add(tip);
    }
    torii.add(kasagi, shimaki, nuki, strut, plaque);
    torii.position.set(0, -0.45, 21);
    G.add(torii);

    // --- stone lanterns with flickering fire
    const flameTex = glowTexture('rgba(255,200,120,1)', 'rgba(255,90,20,0)');
    const lanternAngles = [Math.PI * 0.25, Math.PI * 0.75, Math.PI * 1.25, Math.PI * 1.75];
    for (const a of lanternAngles) {
      const lg = new THREE.Group();
      const r = ARENA_RADIUS + 2.2;
      lg.position.set(Math.sin(a) * r, -0.45, Math.cos(a) * r);
      const parts: [THREE.BufferGeometry, number][] = [
        [new THREE.BoxGeometry(1.1, 0.35, 1.1), 0.18],
        [new THREE.CylinderGeometry(0.18, 0.24, 1.3, 8), 1.0],
        [new THREE.BoxGeometry(0.9, 0.18, 0.9), 1.72],
        [new THREE.BoxGeometry(0.65, 0.6, 0.65), 2.1],
      ];
      for (const [geo, y] of parts) {
        const m = new THREE.Mesh(geo, stoneMat);
        m.position.y = y;
        m.castShadow = true;
        lg.add(m);
      }
      const roof = new THREE.Mesh(new THREE.ConeGeometry(0.85, 0.55, 4), stoneMat);
      roof.position.y = 2.68;
      roof.rotation.y = Math.PI / 4;
      lg.add(roof);
      const glowBox = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.4, 0.66), new THREE.MeshBasicMaterial({ color: 0xffa050 }));
      glowBox.position.y = 2.1;
      lg.add(glowBox);
      const flame = new THREE.Sprite(new THREE.SpriteMaterial({ map: flameTex, color: 0xff8a3a, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      flame.position.y = 2.1;
      flame.scale.setScalar(1.6);
      lg.add(flame);
      this.flameSprites.push(flame);
      const light = new THREE.PointLight(0xff7a30, 14, 16, 1.6);
      light.position.set(0, 2.2, 0);
      lg.add(light);
      this.lanternLights.push(light);
      G.add(lg);
    }

    // --- pillars, some broken, with sacred rope
    const pillarMat = new THREE.MeshStandardMaterial({ map: noiseTexture([66, 60, 56], 16, 128, 9, 2), roughness: 0.95 });
    const ropeMat = new THREE.MeshStandardMaterial({ color: 0xb8a57a, roughness: 1 });
    const pillarAngles = [0.12, 0.5, 0.9, 1.1, 1.5, 1.88, 2.3, 2.7, 3.3, 3.7, 4.1, 4.5, 4.9, 5.3, 5.7, 6.0];
    for (let i = 0; i < pillarAngles.length; i++) {
      const a = pillarAngles[i] + rng.range(-0.05, 0.05);
      if (Math.abs(Math.sin(a)) < 0.3 && Math.cos(a) > 0.8) continue; // keep the torii view clear
      const r = ARENA_RADIUS + rng.range(3.6, 5.5);
      const h = rng.range(2.5, 6.5);
      const broken = rng.chance(0.4);
      const col = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.55, h, 10), pillarMat);
      col.position.set(Math.sin(a) * r, h / 2 - 0.45, Math.cos(a) * r);
      col.castShadow = true;
      col.receiveShadow = true;
      G.add(col);
      if (broken) {
        const chunk = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, rng.range(0.8, 1.6), 10), pillarMat);
        chunk.position.set(col.position.x + rng.range(-1.2, 1.2), 0, col.position.z + rng.range(-1.2, 1.2));
        chunk.rotation.set(Math.PI / 2, rng.range(0, 3), 0);
        chunk.castShadow = true;
        G.add(chunk);
      } else {
        const capital = new THREE.Mesh(new THREE.BoxGeometry(1.3, 0.3, 1.3), pillarMat);
        capital.position.set(col.position.x, h - 0.3, col.position.z);
        G.add(capital);
        const rope = new THREE.Mesh(new THREE.TorusGeometry(0.58, 0.07, 6, 18), ropeMat);
        rope.rotation.x = Math.PI / 2;
        rope.position.set(col.position.x, h * 0.62, col.position.z);
        G.add(rope);
      }
    }

    // --- dead trees
    const bark = new THREE.MeshStandardMaterial({ color: 0x1c1614, roughness: 1 });
    const tree = (x: number, z: number, s: number) => {
      const t = new THREE.Group();
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.12 * s, 0.3 * s, 4 * s, 6), bark);
      trunk.position.y = 2 * s;
      t.add(trunk);
      for (let i = 0; i < 5; i++) {
        const br = new THREE.Mesh(new THREE.CylinderGeometry(0.03 * s, 0.09 * s, rng.range(1.2, 2.2) * s, 5), bark);
        br.position.y = rng.range(2.2, 3.8) * s;
        br.rotation.z = rng.range(0.6, 1.2) * (rng.chance(0.5) ? 1 : -1);
        br.rotation.y = rng.range(0, Math.PI * 2);
        br.geometry.translate(0, rng.range(0.5, 0.9) * s, 0);
        t.add(br);
      }
      t.position.set(x, -0.45, z);
      t.traverse((o) => ((o as THREE.Mesh).castShadow = true));
      G.add(t);
    };
    tree(-18, 12, 1.3);
    tree(19, 6, 1.1);
    tree(-14, -17, 1.2);
    tree(15, -19, 1.4);

    // --- far mountains and a pagoda silhouette
    const mountMat = new THREE.MeshStandardMaterial({ color: 0x0c0a10, roughness: 1, flatShading: true });
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2 + rng.range(-0.15, 0.15);
      const r = rng.range(110, 170);
      const h = rng.range(30, 75);
      const m = new THREE.Mesh(new THREE.ConeGeometry(rng.range(35, 60), h, rng.int(5, 7)), mountMat);
      m.position.set(Math.sin(a) * r, h / 2 - 2, Math.cos(a) * r);
      m.rotation.y = rng.range(0, 3);
      G.add(m);
    }
    const pagoda = new THREE.Group();
    const pagMat = new THREE.MeshStandardMaterial({ color: 0x0f0c0e, roughness: 1 });
    for (let i = 0; i < 5; i++) {
      const w = 7 - i * 1.1;
      const body = new THREE.Mesh(new THREE.BoxGeometry(w * 0.6, 2.2, w * 0.6), pagMat);
      body.position.y = 1.1 + i * 3;
      const roof = new THREE.Mesh(new THREE.ConeGeometry(w * 0.95, 1.4, 4), pagMat);
      roof.position.y = 2.6 + i * 3;
      roof.rotation.y = Math.PI / 4;
      pagoda.add(body, roof);
    }
    const spire = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.2, 5, 6), pagMat);
    spire.position.y = 17.5;
    pagoda.add(spire);
    pagoda.position.set(-48, -1, 62);
    G.add(pagoda);

    floor.userData.keep = true;
    ground.userData.keep = true;
    this.mergeStatic();

    // --- lights
    const hemi = new THREE.HemisphereLight(0x8a5260, 0x1a0f0f, 1.15);
    this.hemi = hemi;
    scene.add(hemi);
    this.moonLight = new THREE.DirectionalLight(0xffd6c8, 2.1);
    this.moonLight.position.copy(this.moonDir).multiplyScalar(40);
    this.moonLight.castShadow = true;
    const sc = this.moonLight.shadow.camera;
    sc.left = -16;
    sc.right = 16;
    sc.top = 16;
    sc.bottom = -16;
    sc.near = 5;
    sc.far = 90;
    this.moonLight.shadow.mapSize.set(quality === 'high' ? 2048 : 1024, quality === 'high' ? 2048 : 1024);
    this.moonLight.shadow.bias = -0.0006;
    this.moonLight.shadow.normalBias = 0.03;
    scene.add(this.moonLight);
    const rimLight = new THREE.DirectionalLight(0x6a86c8, 0.7);
    rimLight.position.set(-20, 12, -25);
    scene.add(rimLight);

    // --- embers (rising) and ash (falling)
    {
      const n = quality === 'high' ? 260 : 120;
      const pos = new Float32Array(n * 3);
      this.emberVel = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) this.respawnEmber(pos, i, true);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      this.embers = new THREE.Points(
        geo,
        new THREE.PointsMaterial({
          color: 0xff7a2a,
          size: 0.09,
          map: glowTexture(),
          transparent: true,
          depthWrite: false,
          blending: THREE.AdditiveBlending,
        }),
      );
      G.add(this.embers);
    }
    {
      const n = quality === 'high' ? 400 : 160;
      const pos = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) pos.set([rng.range(-22, 22), rng.range(0, 14), rng.range(-22, 22)], i * 3);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      this.ash = new THREE.Points(
        geo,
        new THREE.PointsMaterial({ color: 0x8a8080, size: 0.05, transparent: true, opacity: 0.6, depthWrite: false }),
      );
      G.add(this.ash);
    }
  }

  /** Merge static stone/wood meshes that share a material into single draw calls. */
  private mergeStatic() {
    const G = this.group;
    G.updateMatrixWorld(true);
    const buckets = new Map<string, { mat: THREE.Material; cast: boolean; recv: boolean; geos: THREE.BufferGeometry[] }>();
    const remove: THREE.Mesh[] = [];
    G.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh || !(m.material instanceof THREE.MeshStandardMaterial) || m.userData.keep) return;
      const g0 = m.geometry;
      if (!g0.index || !g0.attributes.uv || !g0.attributes.normal) return;
      const key = m.material.uuid + (m.castShadow ? 'c' : '') + (m.receiveShadow ? 'r' : '');
      let b = buckets.get(key);
      if (!b) {
        b = { mat: m.material, cast: m.castShadow, recv: m.receiveShadow, geos: [] };
        buckets.set(key, b);
      }
      const g = g0.clone();
      g.applyMatrix4(m.matrixWorld);
      for (const name of Object.keys(g.attributes)) if (name !== 'position' && name !== 'normal' && name !== 'uv') g.deleteAttribute(name);
      g.clearGroups();
      b.geos.push(g);
      remove.push(m);
    });
    for (const b of buckets.values()) {
      if (b.geos.length < 2) continue;
      const merged = mergeGeometries(b.geos, false);
      if (!merged) continue;
      const mesh = new THREE.Mesh(merged, b.mat);
      mesh.castShadow = b.cast;
      mesh.receiveShadow = b.recv;
      G.add(mesh);
      for (const m of remove) if (m.material === b.mat && m.castShadow === b.cast && m.receiveShadow === b.recv) m.parent?.remove(m);
    }
  }

  private respawnEmber(pos: Float32Array, i: number, anyHeight: boolean) {
    const rng = this.rng;
    const a = rng.range(0, Math.PI * 2);
    const r = rng.range(3, 24);
    pos[i * 3] = Math.sin(a) * r;
    pos[i * 3 + 1] = anyHeight ? rng.range(0, 10) : rng.range(-0.3, 0.5);
    pos[i * 3 + 2] = Math.cos(a) * r;
    this.emberVel[i * 3] = rng.range(-0.3, 0.3);
    this.emberVel[i * 3 + 1] = rng.range(0.4, 1.3);
    this.emberVel[i * 3 + 2] = rng.range(-0.3, 0.3);
  }

  update(time: number, dt: number) {
    // lantern flicker
    for (let i = 0; i < this.lanternLights.length; i++) {
      const f = 0.82 + Math.sin(time * 9 + i * 1.7) * 0.08 + Math.sin(time * 23 + i) * 0.06 + Math.random() * 0.06;
      this.lanternLights[i].intensity = 14 * f;
      this.flameSprites[i].scale.setScalar(1.5 * f + 0.2);
    }
    // embers
    const ep = this.embers.geometry.attributes.position as THREE.BufferAttribute;
    const arr = ep.array as Float32Array;
    for (let i = 0; i < arr.length / 3; i++) {
      arr[i * 3] += (this.emberVel[i * 3] + Math.sin(time * 0.7 + i) * 0.25) * dt;
      arr[i * 3 + 1] += this.emberVel[i * 3 + 1] * dt;
      arr[i * 3 + 2] += (this.emberVel[i * 3 + 2] + Math.cos(time * 0.6 + i) * 0.25) * dt;
      if (arr[i * 3 + 1] > 12) this.respawnEmber(arr, i, false);
    }
    ep.needsUpdate = true;
    // ash
    const ap = this.ash.geometry.attributes.position as THREE.BufferAttribute;
    const aa = ap.array as Float32Array;
    for (let i = 0; i < aa.length / 3; i++) {
      aa[i * 3] += Math.sin(time * 0.5 + i * 0.3) * 0.3 * dt + 0.15 * dt;
      aa[i * 3 + 1] -= (0.35 + (i % 5) * 0.06) * dt;
      aa[i * 3 + 2] += Math.cos(time * 0.4 + i * 0.2) * 0.3 * dt;
      if (aa[i * 3 + 1] < -0.3) aa[i * 3 + 1] = 14;
    }
    ap.needsUpdate = true;
  }
}
