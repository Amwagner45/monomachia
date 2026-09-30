// Procedural canvas textures (no image files needed).

import * as THREE from 'three';
import { Rng } from '../sim/rng';

function canvas(w: number, h: number) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

/** Circular flagstone floor with grooves, cracks and a faded crest. */
export function stoneFloorTextures(size = 1024) {
  const rng = new Rng(4242);
  const col = canvas(size, size);
  const bump = canvas(size, size);
  const g = col.getContext('2d')!;
  const b = bump.getContext('2d')!;
  const c = size / 2;
  g.fillStyle = '#3b3632';
  g.fillRect(0, 0, size, size);
  b.fillStyle = '#808080';
  b.fillRect(0, 0, size, size);

  // stones: rings of segments
  const rings = [0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 1.0];
  for (let i = 0; i < rings.length - 1; i++) {
    const r0 = rings[i] * c;
    const r1 = rings[i + 1] * c;
    const n = i === 0 ? 1 : 6 + i * 5;
    const off = rng.range(0, Math.PI * 2);
    for (let s = 0; s < n; s++) {
      const a0 = off + (s / n) * Math.PI * 2 + rng.range(-0.03, 0.03);
      const a1 = off + ((s + 1) / n) * Math.PI * 2 + rng.range(-0.03, 0.03);
      const shade = rng.range(-18, 14);
      const base = [59 + shade, 54 + shade, 50 + shade * 0.9];
      g.fillStyle = `rgb(${base[0] | 0},${base[1] | 0},${base[2] | 0})`;
      g.beginPath();
      if (i === 0) g.arc(c, c, r1, 0, Math.PI * 2);
      else {
        g.arc(c, c, r1, a0, a1);
        g.arc(c, c, r0, a1, a0, true);
      }
      g.closePath();
      g.fill();
      // speckle
      for (let k = 0; k < 40 + i * 25; k++) {
        const a = rng.range(a0, a1);
        const r = rng.range(r0, r1);
        const x = c + Math.cos(a) * r;
        const y = c + Math.sin(a) * r;
        const v = rng.range(-25, 25);
        g.fillStyle = `rgba(${base[0] + v | 0},${base[1] + v | 0},${base[2] + v | 0},0.5)`;
        g.fillRect(x, y, rng.range(1, 4), rng.range(1, 4));
      }
      // grooves
      for (const ctx of [g, b]) {
        ctx.strokeStyle = ctx === g ? 'rgba(15,12,12,0.85)' : '#202020';
        ctx.lineWidth = ctx === g ? 3 : 5;
        ctx.beginPath();
        if (i > 0) {
          ctx.moveTo(c + Math.cos(a0) * r0, c + Math.sin(a0) * r0);
          ctx.lineTo(c + Math.cos(a0) * r1, c + Math.sin(a0) * r1);
        }
        ctx.stroke();
      }
    }
    for (const ctx of [g, b]) {
      ctx.strokeStyle = ctx === g ? 'rgba(15,12,12,0.9)' : '#202020';
      ctx.lineWidth = ctx === g ? 3 : 5;
      ctx.beginPath();
      ctx.arc(c, c, r1, 0, Math.PI * 2);
      ctx.stroke();
    }
  }
  // cracks
  for (let k = 0; k < 40; k++) {
    let x = rng.range(0.1, 0.9) * size;
    let y = rng.range(0.1, 0.9) * size;
    let a = rng.range(0, Math.PI * 2);
    g.strokeStyle = 'rgba(10,8,8,0.7)';
    b.strokeStyle = '#303030';
    g.lineWidth = 1.2;
    b.lineWidth = 2;
    g.beginPath();
    b.beginPath();
    g.moveTo(x, y);
    b.moveTo(x, y);
    const n = rng.int(4, 12);
    for (let i = 0; i < n; i++) {
      a += rng.range(-0.7, 0.7);
      x += Math.cos(a) * rng.range(6, 18);
      y += Math.sin(a) * rng.range(6, 18);
      g.lineTo(x, y);
      b.lineTo(x, y);
    }
    g.stroke();
    b.stroke();
  }
  // dark stains
  for (let k = 0; k < 26; k++) {
    const x = rng.range(0, size);
    const y = rng.range(0, size);
    const r = rng.range(20, 90);
    const grd = g.createRadialGradient(x, y, 0, x, y, r);
    grd.addColorStop(0, 'rgba(20,10,10,0.35)');
    grd.addColorStop(1, 'rgba(20,10,10,0)');
    g.fillStyle = grd;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  // faded crest in the centre
  g.save();
  g.translate(c, c);
  g.strokeStyle = 'rgba(120,20,18,0.22)';
  g.lineWidth = 10;
  g.beginPath();
  g.arc(0, 0, c * 0.25, 0, Math.PI * 2);
  g.stroke();
  g.lineWidth = 4;
  g.beginPath();
  g.arc(0, 0, c * 0.21, 0, Math.PI * 2);
  g.stroke();
  g.fillStyle = 'rgba(130,24,20,0.2)';
  g.font = `bold ${Math.round(c * 0.26)}px serif`;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText('闘', 0, c * 0.01);
  g.restore();

  const map = new THREE.CanvasTexture(col);
  map.colorSpace = THREE.SRGBColorSpace;
  map.anisotropy = 8;
  const bumpMap = new THREE.CanvasTexture(bump);
  return { map, bumpMap };
}

/** Tileable noisy texture for earth, stone walls, bark. */
export function noiseTexture(base: [number, number, number], vary: number, size = 256, seed = 7, repeat = 1) {
  const rng = new Rng(seed);
  const cv = canvas(size, size);
  const g = cv.getContext('2d')!;
  g.fillStyle = `rgb(${base[0]},${base[1]},${base[2]})`;
  g.fillRect(0, 0, size, size);
  for (let i = 0; i < size * size * 0.35; i++) {
    const v = rng.range(-vary, vary);
    g.fillStyle = `rgba(${base[0] + v | 0},${base[1] + v | 0},${base[2] + v | 0},0.6)`;
    g.fillRect(rng.int(0, size), rng.int(0, size), rng.int(1, 3), rng.int(1, 3));
  }
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  return t;
}

/** Soft round glow sprite. */
export function glowTexture(inner = 'rgba(255,255,255,1)', outer = 'rgba(255,255,255,0)', size = 128) {
  const cv = canvas(size, size);
  const g = cv.getContext('2d')!;
  const grd = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grd.addColorStop(0, inner);
  grd.addColorStop(0.25, inner.replace(/[\d.]+\)$/, '0.6)'));
  grd.addColorStop(1, outer);
  g.fillStyle = grd;
  g.fillRect(0, 0, size, size);
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/** A glowing text/kanji sprite texture. */
export function textTexture(text: string, sub: string, color: string, size = 256) {
  const cv = canvas(size, size);
  const g = cv.getContext('2d')!;
  g.clearRect(0, 0, size, size);
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.shadowColor = color;
  g.shadowBlur = 24;
  g.fillStyle = color;
  g.font = `bold ${Math.round(size * 0.55)}px serif`;
  g.fillText(text, size / 2, size * 0.42);
  g.shadowBlur = 0;
  g.fillStyle = '#ffffff';
  g.fillText(text, size / 2, size * 0.42);
  if (sub) {
    g.shadowBlur = 10;
    g.shadowColor = color;
    g.font = `bold ${Math.round(size * 0.13)}px sans-serif`;
    g.fillStyle = color;
    g.fillText(sub, size / 2, size * 0.86);
  }
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
