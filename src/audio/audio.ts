// All sound is synthesised with the Web Audio API: metal clangs, a special
// ringing parry clang, slices, colossal crunches, whooshes, taiko drums and a
// drum / plucked-string / distorted-guitar music loop. No audio files.

import type { SimEvent } from '../sim/events';

type Ctx = AudioContext;

const IN_SCALE = [0, 1, 5, 7, 8]; // Japanese "In" scale (semitones)

export class AudioEngine {
  ctx: Ctx | null = null;
  private master!: GainNode;
  private sfx!: GainNode;
  private music!: GainNode;
  private comp!: DynamicsCompressorNode;
  private noise!: AudioBuffer;
  private plucks: AudioBuffer[] = [];
  private distCurve!: Float32Array<ArrayBuffer>;
  volumes = { master: 0.8, sfx: 0.9, music: 0.45 };
  muted = false;

  // music scheduler
  private musicMode: 'off' | 'menu' | 'fight' = 'off';
  private nextNote = 0;
  private step = 0;
  private timer: number | null = null;
  private tempo = 138;
  private melodyIdx = 3;

  constructor() {
    try {
      const raw = localStorage.getItem('monomachia.audio');
      if (raw) Object.assign(this.volumes, JSON.parse(raw));
    } catch {
      /* storage unavailable */
    }
  }

  /** Must be called from a user gesture. */
  init() {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') void this.ctx.resume();
      return;
    }
    const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    this.ctx = ctx;
    this.comp = ctx.createDynamicsCompressor();
    this.comp.threshold.value = -14;
    this.comp.ratio.value = 4;
    this.master = ctx.createGain();
    this.sfx = ctx.createGain();
    this.music = ctx.createGain();
    this.sfx.connect(this.comp);
    this.music.connect(this.comp);
    this.comp.connect(this.master);
    this.master.connect(ctx.destination);
    this.applyVolumes();

    const len = ctx.sampleRate * 2;
    this.noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;

    // Karplus-Strong plucked strings for the melody (two octaves of the In scale on D)
    const base = 146.83; // D3
    for (let oct = 0; oct < 2; oct++) {
      for (const semi of IN_SCALE) this.plucks.push(this.makePluck(base * Math.pow(2, oct + semi / 12)));
    }
    this.plucks.push(this.makePluck(base * 4));

    const n = 1024;
    this.distCurve = new Float32Array(new ArrayBuffer(n * 4));
    for (let i = 0; i < n; i++) {
      const x = (i / (n - 1)) * 2 - 1;
      this.distCurve[i] = Math.tanh(x * 6);
    }
  }

  private makePluck(freq: number) {
    const ctx = this.ctx!;
    const sr = ctx.sampleRate;
    const dur = 1.6;
    const buf = ctx.createBuffer(1, Math.floor(sr * dur), sr);
    const out = buf.getChannelData(0);
    const N = Math.max(2, Math.round(sr / freq));
    const ring = new Float32Array(N);
    for (let i = 0; i < N; i++) ring[i] = Math.random() * 2 - 1;
    let idx = 0;
    for (let i = 0; i < out.length; i++) {
      const next = (idx + 1) % N;
      const v = 0.5 * (ring[idx] + ring[next]) * 0.994;
      out[i] = ring[idx];
      ring[idx] = v;
      idx = next;
    }
    // bright attack like a shamisen bachi strike
    for (let i = 0; i < Math.min(out.length, 300); i++) out[i] *= 1 + (1 - i / 300) * 0.8;
    return buf;
  }

  applyVolumes() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(this.muted ? 0 : this.volumes.master, t, 0.02);
    this.sfx.gain.setTargetAtTime(this.volumes.sfx, t, 0.02);
    this.music.gain.setTargetAtTime(this.volumes.music, t, 0.05);
    try {
      localStorage.setItem('monomachia.audio', JSON.stringify(this.volumes));
    } catch {
      /* ignore */
    }
  }

  // ------------------------------------------------------------------ building blocks

  private env(g: GainNode, t: number, peak: number, attack: number, decay: number) {
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  }

  private tone(freq: number, type: OscillatorType, peak: number, attack: number, decay: number, dest: AudioNode, t0 = 0, freqEnd?: number) {
    const ctx = this.ctx!;
    const t = ctx.currentTime + t0;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (freqEnd) o.frequency.exponentialRampToValueAtTime(freqEnd, t + attack + decay);
    const g = ctx.createGain();
    this.env(g, t, peak, attack, decay);
    o.connect(g).connect(dest);
    o.start(t);
    o.stop(t + attack + decay + 0.05);
  }

  private noiseBurst(
    peak: number,
    attack: number,
    decay: number,
    filter: BiquadFilterType,
    f0: number,
    dest: AudioNode,
    t0 = 0,
    f1?: number,
    q = 1,
  ) {
    const ctx = this.ctx!;
    const t = ctx.currentTime + t0;
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    src.playbackRate.value = 0.9 + Math.random() * 0.2;
    const bf = ctx.createBiquadFilter();
    bf.type = filter;
    bf.frequency.setValueAtTime(f0, t);
    if (f1) bf.frequency.exponentialRampToValueAtTime(f1, t + attack + decay);
    bf.Q.value = q;
    const g = ctx.createGain();
    this.env(g, t, peak, attack, decay);
    src.connect(bf).connect(g).connect(dest);
    const off = Math.random() * 1.5;
    src.start(t, off);
    src.stop(t + attack + decay + 0.05);
  }

  private metal(f0: number, partials: number[], peak: number, decay: number, dest: AudioNode, t0 = 0) {
    partials.forEach((p, i) => {
      this.tone(f0 * p * (0.99 + Math.random() * 0.02), i === 0 ? 'triangle' : 'sine', peak / (1 + i * 0.7), 0.002, decay * (1 - i * 0.12), dest, t0);
    });
  }

  // ------------------------------------------------------------------ sound effects

  clang(heavy: boolean) {
    if (!this.ctx) return;
    const f0 = (heavy ? 520 : 760) * (0.92 + Math.random() * 0.16);
    this.metal(f0, [1, 2.76, 5.4, 8.93], heavy ? 0.28 : 0.2, heavy ? 0.55 : 0.35, this.sfx);
    this.noiseBurst(heavy ? 0.5 : 0.35, 0.001, 0.06, 'highpass', 2500, this.sfx);
  }

  parryClang(kind: 'parry' | 'flash' | 'redirect') {
    if (!this.ctx) return;
    if (kind === 'redirect') {
      this.tone(160, 'sine', 0.6, 0.002, 0.18, this.sfx, 0, 70);
      this.noiseBurst(0.4, 0.002, 0.12, 'bandpass', 1800, this.sfx, 0, 600, 2);
      this.metal(900, [1, 2.4, 4.1], 0.15, 0.5, this.sfx);
      return;
    }
    const f0 = kind === 'flash' ? 1450 : 1180;
    this.metal(f0, [1, 2.32, 3.87, 5.71, 7.2], 0.32, 1.25, this.sfx);
    this.noiseBurst(0.35, 0.004, 0.35, 'bandpass', 3200, this.sfx, 0, 9000, 4);
    this.tone(95, 'sine', 0.55, 0.002, 0.16, this.sfx, 0, 55);
    if (kind === 'flash') this.metal(f0 * 1.5, [1, 2.1], 0.12, 0.9, this.sfx, 0.05);
  }

  slice(heavy: boolean, dagger: boolean) {
    if (!this.ctx) return;
    this.noiseBurst(heavy ? 0.7 : 0.5, 0.003, dagger ? 0.08 : 0.14, 'bandpass', dagger ? 4200 : 2800, this.sfx, 0, 600, 1.5);
    this.tone(heavy ? 110 : 140, 'sine', heavy ? 0.5 : 0.35, 0.002, 0.12, this.sfx, 0.01, 50);
    this.noiseBurst(0.25, 0.01, 0.12, 'lowpass', 900, this.sfx, 0.02);
  }

  crush() {
    if (!this.ctx) return;
    this.tone(75, 'sine', 0.9, 0.003, 0.4, this.sfx, 0, 32);
    this.noiseBurst(0.7, 0.003, 0.3, 'lowpass', 1100, this.sfx, 0, 200);
    for (let i = 0; i < 6; i++) this.noiseBurst(0.3, 0.001, 0.02, 'highpass', 1500 + Math.random() * 2000, this.sfx, 0.02 + Math.random() * 0.18);
  }

  punch(heavy: boolean) {
    if (!this.ctx) return;
    this.tone(heavy ? 120 : 160, 'sine', 0.8, 0.002, heavy ? 0.16 : 0.1, this.sfx, 0, 50);
    this.noiseBurst(0.5, 0.002, 0.06, 'lowpass', 1400, this.sfx);
  }

  whoosh(heavy: boolean, weapon: string) {
    if (!this.ctx) return;
    const colossal = weapon === 'greatsword';
    const small = weapon === 'daggers' || weapon === 'fists';
    const dur = colossal ? 0.36 : heavy ? 0.24 : small ? 0.1 : 0.16;
    const f0 = colossal ? 300 : small ? 900 : 500;
    this.noiseBurst(colossal ? 0.45 : 0.3, dur * 0.45, dur * 0.55, 'bandpass', f0, this.sfx, 0, f0 * 3.5, 1.2);
  }

  dodge() {
    if (!this.ctx) return;
    this.noiseBurst(0.22, 0.03, 0.14, 'bandpass', 700, this.sfx, 0, 1600, 0.8);
    this.noiseBurst(0.12, 0.01, 0.08, 'lowpass', 600, this.sfx, 0.02);
  }

  footstep() {
    if (!this.ctx) return;
    this.noiseBurst(0.08, 0.002, 0.05, 'lowpass', 500, this.sfx);
  }

  land() {
    if (!this.ctx) return;
    this.tone(90, 'sine', 0.3, 0.002, 0.1, this.sfx, 0, 45);
    this.noiseBurst(0.18, 0.002, 0.08, 'lowpass', 700, this.sfx);
  }

  taiko(accent = 1, t0 = 0, dest?: AudioNode) {
    if (!this.ctx) return;
    const d = dest ?? this.sfx;
    this.tone(95, 'sine', 0.9 * accent, 0.002, 0.45, d, t0, 48);
    this.tone(190, 'triangle', 0.15 * accent, 0.002, 0.12, d, t0, 90);
    this.noiseBurst(0.25 * accent, 0.001, 0.05, 'lowpass', 500, d, t0);
  }

  telegraph() {
    if (!this.ctx) return;
    this.taiko(0.9);
    this.metal(2400, [1, 2.7], 0.12, 0.35, this.sfx, 0.01);
  }

  gong(t0 = 0) {
    if (!this.ctx) return;
    const f0 = 98;
    [1, 1.52, 2.13, 2.74, 3.43, 4.6].forEach((p, i) =>
      this.tone(f0 * p, 'sine', 0.22 / (1 + i * 0.5), 0.01, 2.6 - i * 0.3, this.sfx, t0),
    );
    this.noiseBurst(0.15, 0.005, 0.3, 'lowpass', 800, this.sfx, t0);
  }

  disarm() {
    if (!this.ctx) return;
    this.parryClang('parry');
    this.metal(640, [1, 2.9, 5.1], 0.25, 0.8, this.sfx, 0.05);
    this.tone(55, 'sine', 0.7, 0.003, 0.5, this.sfx, 0, 30);
  }

  bounce(speed: number) {
    if (!this.ctx) return;
    const v = Math.min(1, speed / 8);
    this.metal(1300 + Math.random() * 500, [1, 2.9], 0.12 * v, 0.25, this.sfx);
  }

  ultStart() {
    if (!this.ctx) return;
    this.noiseBurst(0.35, 0.6, 0.3, 'bandpass', 300, this.sfx, 0, 4000, 1.5);
    [146.8, 220, 293.7].forEach((f) => this.tone(f, 'sawtooth', 0.05, 0.3, 0.7, this.sfx));
    this.taiko(1.1, 0.0);
  }

  boom() {
    if (!this.ctx) return;
    this.tone(55, 'sine', 1, 0.004, 0.9, this.sfx, 0, 25);
    this.noiseBurst(0.9, 0.004, 0.9, 'lowpass', 2400, this.sfx, 0, 120);
  }

  lightning() {
    if (!this.ctx) return;
    for (let i = 0; i < 8; i++) this.noiseBurst(0.35, 0.001, 0.03, 'highpass', 3000, this.sfx, i * 0.025);
    this.tone(1800, 'square', 0.05, 0.001, 0.2, this.sfx, 0, 300);
  }

  wave() {
    if (!this.ctx) return;
    this.noiseBurst(0.6, 0.01, 0.5, 'bandpass', 5000, this.sfx, 0, 800, 3);
    this.metal(1900, [1, 2.2], 0.15, 0.7, this.sfx);
  }

  uiMove() {
    if (!this.ctx) return;
    this.tone(880, 'sine', 0.08, 0.002, 0.05, this.sfx);
  }

  uiSelect() {
    if (!this.ctx) return;
    this.tone(660, 'triangle', 0.12, 0.002, 0.08, this.sfx);
    this.tone(990, 'triangle', 0.1, 0.002, 0.12, this.sfx, 0.06);
  }

  /** Map simulation events to sounds. */
  handle(events: SimEvent[], playerIndex = 0) {
    if (!this.ctx) return;
    for (const e of events) {
      switch (e.t) {
        case 'hit':
          if (e.sound === 'fist') this.punch(e.heavy);
          else if (e.sound === 'colossal') {
            this.crush();
            this.slice(true, false);
          } else this.slice(e.heavy, e.sound === 'dagger');
          break;
        case 'block':
          this.clang(e.heavy);
          break;
        case 'parry':
          this.parryClang(e.kind);
          break;
        case 'counter':
          if (e.kind === 'stomp') {
            this.crush();
            this.clang(true);
          } else if (e.kind === 'leap') this.punch(true);
          else this.dodge();
          this.taiko(0.7, 0.03);
          break;
        case 'swing':
          this.whoosh(e.heavy, e.weapon);
          break;
        case 'telegraph':
          if (e.kind !== 'ult') this.telegraph();
          break;
        case 'disarm':
          this.disarm();
          break;
        case 'weaponBounce':
          this.bounce(e.speed);
          break;
        case 'dodge':
          this.dodge();
          break;
        case 'step':
          if (e.f === playerIndex) this.footstep();
          break;
        case 'land':
          this.land();
          break;
        case 'ultStart':
        case 'ultChoice':
          this.ultStart();
          break;
        case 'ultWave':
          this.wave();
          break;
        case 'ultImpale':
          this.slice(true, false);
          this.crush();
          break;
        case 'ultBurst':
          this.boom();
          break;
        case 'ultLightning':
          this.lightning();
          break;
        case 'pickup':
        case 'recall':
          this.metal(1600, [1, 2.4], 0.12, 0.4, this.sfx);
          break;
        case 'roundStart':
          this.gong();
          break;
        case 'fight':
          this.taiko(1.2);
          this.taiko(1.0, 0.18);
          break;
        case 'ko':
          this.taiko(1.3);
          this.gong(0.1);
          this.boom();
          break;
        case 'stagger':
          this.metal(700, [1, 1.5], 0.1, 0.5, this.sfx);
          break;
      }
    }
  }

  // ------------------------------------------------------------------ music

  setMusic(mode: 'off' | 'menu' | 'fight') {
    if (!this.ctx) {
      this.musicMode = mode;
      return;
    }
    if (mode === this.musicMode && this.timer !== null) return;
    this.musicMode = mode;
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (mode === 'off') return;
    this.tempo = mode === 'fight' ? 138 : 84;
    this.nextNote = this.ctx.currentTime + 0.1;
    this.step = 0;
    this.timer = window.setInterval(() => this.schedule(), 25);
  }

  private schedule() {
    const ctx = this.ctx;
    if (!ctx || this.musicMode === 'off') return;
    const sixteenth = 60 / this.tempo / 4;
    while (this.nextNote < ctx.currentTime + 0.12) {
      this.playStep(this.step, this.nextNote - ctx.currentTime);
      this.nextNote += sixteenth;
      this.step = (this.step + 1) % 128;
    }
  }

  private playStep(s: number, t0: number) {
    const fight = this.musicMode === 'fight';
    const beat = s % 16;
    const bar = Math.floor(s / 16) % 8;
    const M = this.music;
    if (fight) {
      // taiko groove
      if (beat === 0 || beat === 10 || (beat === 6 && bar % 2 === 1)) this.taiko(beat === 0 ? 0.8 : 0.55, t0, M);
      if (beat === 4 || beat === 12) this.taiko(0.6, t0, M);
      if (beat % 2 === 1) this.noiseBurst(0.08, 0.001, 0.03, 'highpass', 5000, M, t0); // "ka" rim
      // palm-muted distorted chug on D
      if (bar >= 2 && (beat % 2 === 0 || (bar % 4 === 3 && beat > 11))) this.chug(t0, beat === 0 ? 0.26 : 0.16, bar % 4 === 3 && beat >= 8);
    } else {
      if (beat === 0 && bar % 2 === 0) this.taiko(0.45, t0, M);
      if (beat === 0 && bar % 4 === 0) this.drone(t0);
    }
    // plucked melody: a wandering line in the In scale
    const density = fight ? 0.42 : 0.22;
    const onGrid = fight ? beat % 2 === 0 : beat % 4 === 0;
    if (onGrid && Math.random() < density) {
      this.melodyIdx = Math.max(0, Math.min(this.plucks.length - 1, this.melodyIdx + Math.round((Math.random() - 0.5) * 4)));
      this.pluck(this.melodyIdx, t0, fight ? 0.32 : 0.26);
    }
  }

  private pluck(i: number, t0: number, vol: number) {
    const ctx = this.ctx!;
    const src = ctx.createBufferSource();
    src.buffer = this.plucks[i];
    const g = ctx.createGain();
    g.gain.value = vol;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 3200;
    src.connect(f).connect(g).connect(this.music);
    src.start(ctx.currentTime + t0);
  }

  private chug(t0: number, vol: number, high: boolean) {
    const ctx = this.ctx!;
    const t = ctx.currentTime + t0;
    const shaper = ctx.createWaveShaper();
    shaper.curve = this.distCurve;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 1100;
    const g = ctx.createGain();
    this.env(g, t, vol, 0.004, 0.11);
    const root = high ? 87.31 : 73.42; // F2 / D2
    for (const f of [root, root * 1.5]) {
      const o = ctx.createOscillator();
      o.type = 'sawtooth';
      o.frequency.value = f;
      o.connect(shaper);
      o.start(t);
      o.stop(t + 0.16);
    }
    shaper.connect(lp).connect(g).connect(this.music);
  }

  private drone(t0: number) {
    const ctx = this.ctx!;
    const t = ctx.currentTime + t0;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.06, t + 1.5);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 6.5);
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 500;
    for (const f of [73.42, 110, 146.83]) {
      const o = ctx.createOscillator();
      o.type = 'sawtooth';
      o.frequency.value = f * (1 + (Math.random() - 0.5) * 0.004);
      o.connect(lp);
      o.start(t);
      o.stop(t + 7);
    }
    lp.connect(g).connect(this.music);
  }
}
