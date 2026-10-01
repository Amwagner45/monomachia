#!/usr/bin/env node
// Builds the game's recorded sound effects from the Sonniss GDC 2026 bundle.
//
// For each output in scripts/audio/sonniss-picks.json it reads only the chosen
// recordings straight out of the bundle zips (nothing is extracted to disk),
// cuts, pitches, filters and layers them, and writes a 16-bit 44.1 kHz WAV to
// game/assets/audio/sfx/ (mono, except the stereo ambience loops, which carry
// their loop points in a 'smpl' chunk). Then it rewrites
// game/assets/audio/SOURCES.md.
//
// The raw recordings may be used in the game but never redistributed as they
// come, and never fed to AI tools: only these processed files are committed.
//
// usage: node scripts/audio/extract-sonniss.mjs [--only=<regex>]
// The zips are looked for in SONNISS_DIR, else ~/Downloads. A missing part is
// reported and every output that needs it is skipped (its old file is kept).

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as dsp from './lib/dsp.mjs';
import { openBundle, readRecording } from './lib/sonniss.mjs';
import { writeWav } from './lib/wav.mjs';
import { seedFrom } from './lib/rng.mjs';
import { writeSourcesMd } from './lib/sources.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
export const PICKS_PATH = join(HERE, 'sonniss-picks.json');
const SFX_DIR = join(ROOT, 'game', 'assets', 'audio', 'sfx');

export function loadPicks() {
  return JSON.parse(readFileSync(PICKS_PATH, 'utf8'));
}

async function main() {
  const onlyArg = process.argv.find((a) => a.startsWith('--only='));
  const only = onlyArg ? new RegExp(onlyArg.slice(7), 'i') : null;
  const picks = loadPicks();
  const rate = picks.sampleRate;
  const bundle = openBundle();
  for (const m of bundle.missing) {
    console.warn(`extract-sonniss: bundle part ${m.part} not found at ${m.path}; outputs that need it are skipped.`);
  }

  const recordings = new Map(); // source id -> Promise<audio>
  const takeCache = new Map();
  const source = (id) => {
    const s = picks.sources[id];
    if (!s) throw new Error(`unknown source "${id}"`);
    if (!recordings.has(id)) {
      recordings.set(id, readRecording(bundle.zips.get(s.part), s.entry, { until: s.until }));
    }
    return recordings.get(id);
  };
  const takes = async (id) => {
    if (!takeCache.has(id)) {
      const s = picks.sources[id];
      takeCache.set(id, dsp.regions(await source(id), s.takes ?? {}));
    }
    return takeCache.get(id);
  };

  /** Cuts, pitches and filters one layer; returns audio at the output rate. */
  async function renderLayer(layer, channels) {
    const src = await source(layer.source);
    let start = layer.start ?? 0;
    let end = layer.end;
    if (layer.take != null) {
      const list = await takes(layer.source);
      const t = list[layer.take - 1];
      if (!t) throw new Error(`${layer.source} has ${list.length} takes, not ${layer.take}`);
      const base = layer.anchor === 'peak' ? t.peakTime : t.start;
      start = base + (layer.from ?? 0);
      end = layer.length != null ? start + layer.length : t.end;
    } else if (layer.length != null) {
      end = start + layer.length;
    }
    let a = dsp.slice(src, start, end ?? Infinity);
    a = channels === 1 ? dsp.toMono(a) : dsp.toStereo(a);
    if (layer.width != null) a = dsp.stereoWidth(a, layer.width);
    a = dsp.resample(a, rate, { pitch: Math.pow(2, (layer.pitch ?? 0) / 12) });
    if (layer.reverse) a = dsp.reverse(a);
    if (layer.highpass) a = dsp.highpass(a, layer.highpass, layer.order ?? 2);
    if (layer.lowpass) a = dsp.lowpass(a, layer.lowpass, layer.order ?? 2);
    if (layer.normalize) a = dsp.normalize(a, layer.normalize);
    if (layer.gainDb) a = dsp.gain(a, layer.gainDb);
    a = dsp.fade(a, { fadeIn: layer.fadeIn ?? 0.002, fadeOut: layer.fadeOut ?? 0.01 });
    if (layer.loop) a = dsp.loopCrossfade(a, layer.loop.seconds, layer.loop.crossfade);
    return a;
  }

  async function renderOutput(out) {
    const p = out.process ?? {};
    const channels = p.channels ?? 1;
    const layers = [];
    for (const layer of out.layers) {
      layers.push({ audio: await renderLayer(layer, channels), offset: layer.offset ?? 0, pan: layer.pan ?? 0 });
    }
    let a = dsp.mix(layers, { channels });
    if (p.highpass) a = dsp.highpass(a, p.highpass, 2);
    if (p.lowpass) a = dsp.lowpass(a, p.lowpass, 2);
    if (p.lowShelf) a = dsp.shelf(a, 'low', p.lowShelf.hz, p.lowShelf.db);
    if (p.highShelf) a = dsp.shelf(a, 'high', p.highShelf.hz, p.highShelf.db);
    if (p.saturateDb) a = dsp.saturate(a, p.saturateDb);
    a = dsp.normalize(a, p.normalize ?? { peakDb: -1 });
    if (p.loop) {
      a = dsp.loopCrossfade(a, p.loop.seconds, p.loop.crossfade);
    } else {
      if (p.trim !== false) a = dsp.trimSilence(a, { thresholdDb: p.trimDb ?? -60, padStart: 0.001, padEnd: 0.02 });
      if (p.maxLength) a = dsp.slice(a, 0, p.maxLength);
      a = dsp.fade(a, { fadeIn: p.fadeIn ?? 0.001, fadeOut: p.fadeOut ?? 0.02 });
    }
    return a;
  }

  let written = 0;
  const skipped = [];
  for (const out of picks.outputs) {
    if (only && !only.test(out.file)) continue;
    const parts = [...new Set(out.layers.map((l) => picks.sources[l.source]?.part))];
    const missingParts = parts.filter((part) => !bundle.has(part));
    if (missingParts.length) {
      skipped.push(`${out.file} (needs part ${missingParts.join(', ')})`);
      continue;
    }
    const a = await renderOutput(out);
    if (dsp.frames(a) === 0) throw new Error(`${out.file}: the processed sound is empty (check its slice times)`);
    mkdirSync(SFX_DIR, { recursive: true });
    const loop = out.process?.loop ? { start: 0, end: dsp.frames(a) } : undefined;
    writeFileSync(join(SFX_DIR, out.file), writeWav(a, { loop, seed: seedFrom(out.file) }));
    const s = dsp.stats(a);
    console.log(`  sfx/${out.file.padEnd(28)} ${s.seconds.toFixed(2).padStart(6)} s  ${s.channels} ch  peak ${s.peakDb} dB`);
    written++;
  }
  bundle.close();
  await writeSourcesMd();
  console.log(`extract-sonniss: wrote ${written} file(s)${skipped.length ? `, skipped ${skipped.length}` : ''}.`);
  if (skipped.length) {
    console.warn(`extract-sonniss: skipped because bundle parts are missing:\n  ${skipped.join('\n  ')}`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
