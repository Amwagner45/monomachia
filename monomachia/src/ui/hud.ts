// Fighting-game HUD: health and posture bars, round pips, ultimate badge,
// big announcements, small feedback toasts, context prompts and the dropped
// weapon marker.

import * as THREE from 'three';
import { HP_MAX, POSTURE_MAX } from '../sim/constants';
import type { SimEvent } from '../sim/events';
import type { Match } from '../sim/match';
import type { World } from '../sim/world';
import type { View } from '../render/view';
import { h } from './dom';

export type LabelFn = (action: string) => string;

interface SideEls {
  root: HTMLElement;
  name: HTMLElement;
  weapon: HTMLElement;
  tag: HTMLElement;
  hp: HTMLElement;
  hpFill: HTMLElement;
  hpLag: HTMLElement;
  posture: HTMLElement;
  postureFill: HTMLElement;
  pips: HTMLElement[];
  ult: HTMLElement;
  lag: number;
  lagHold: number;
}

const ROUND_KANJI = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

export class Hud {
  root: HTMLElement;
  private sides: SideEls[] = [];
  private roundK: HTMLElement;
  private roundE: HTMLElement;
  private announceEl: HTMLElement;
  private toastEl: HTMLElement;
  private promptEls: HTMLElement[];
  private markerEls: HTMLElement[];
  trainPanel: HTMLElement;
  private announceTimer: number | null = null;
  private lastPrompt = ['', ''];
  playerIndex = 0;
  training = false;
  watch = false;
  versus = false;
  showHints = true;
  private lateWatch: { frame: number; window: number } | null = null;
  labelFn: LabelFn = (a) => a;

  constructor(parent: HTMLElement) {
    this.announceEl = h('div', { id: 'announce' });
    this.toastEl = h('div', { id: 'toast' });
    this.promptEls = [h('div', { id: 'prompt' }), h('div', { id: 'prompt2', class: 'prompt2', hidden: true })];
    this.markerEls = [h('div', { class: 'marker', hidden: true }, 'Your weapon'), h('div', { class: 'marker', hidden: true }, 'Your weapon')];
    this.roundK = h('div', { class: 'kanji' }, '一');
    this.roundE = h('div', { class: 'en' }, 'Round 1');
    this.trainPanel = h('div', { class: 'train-panel', hidden: true });
    const top = h('div', { class: 'hud-top' });
    const left = this.makeSide('left');
    const right = this.makeSide('right');
    top.append(left.root, h('div', { class: 'round-label' }, this.roundK, this.roundE), right.root);
    this.sides = [left, right];
    this.root = h('div', { id: 'hud', hidden: true }, top, this.announceEl, this.toastEl, ...this.promptEls, ...this.markerEls, this.trainPanel);
    parent.appendChild(this.root);
  }

  private makeSide(side: 'left' | 'right'): SideEls {
    const name = h('span', { class: 'name' }, 'Fighter');
    const weapon = h('span', { class: 'weapon' }, '');
    const tag = h('span', { class: 'tag', hidden: true }, 'Disarmed');
    const seal = h('span', { class: 'seal' }, side === 'left' ? '赤' : '青');
    const hpLag = h('div', { class: 'lag' });
    const hpFill = h('div', { class: 'fill' });
    const hp = h('div', { class: 'bar', role: 'meter', 'aria-label': 'Health' }, hpLag, hpFill);
    const postureFill = h('div', { class: 'fill' });
    const posture = h('div', { class: 'posture', role: 'meter', 'aria-label': 'Posture' }, postureFill, h('span', { class: 'label' }, 'Posture'));
    const pips = [0, 1, 2].map(() => h('span', { class: 'pip' }));
    const ult = h('span', { class: 'ult', title: 'Ultimate' }, '奥義');
    const root = h(
      'div',
      { class: `side ${side}` },
      h('div', { class: 'plate' }, seal, name, weapon, tag),
      hp,
      posture,
      h('div', { class: 'meta' }, h('div', { class: 'pips' }, pips), ult),
    );
    return { root, name, weapon, tag, hp, hpFill, hpLag, posture, postureFill, pips, ult, lag: 1, lagHold: 0 };
  }

  show(on: boolean) {
    this.root.hidden = !on;
  }

  setup(names: [string, string], weapons: [string, string]) {
    this.sides.forEach((s, i) => {
      s.name.textContent = names[i];
      s.weapon.textContent = weapons[i];
      s.lag = 1;
      s.lagHold = 0;
    });
    this.toastEl.textContent = '';
    for (const p of this.promptEls) p.textContent = '';
    this.lastPrompt = ['', ''];
    this.announceEl.className = '';
    this.promptEls[0].classList.toggle('left', this.versus);
    this.promptEls[1].hidden = !this.versus;
  }

  private nameOf(i: number) {
    return this.sides[i].name.textContent ?? '';
  }

  // ------------------------------------------------------------------ announcements

  announce(kanji: string, english: string, sub = '', hold = false, ms = 1300) {
    const a = this.announceEl;
    a.innerHTML = '';
    a.append(h('div', { class: 'k' }, kanji), h('div', { class: 'e' }, english));
    if (sub) a.append(h('div', { class: 's' }, sub));
    a.className = '';
    void a.offsetWidth; // restart the animation
    a.className = hold ? 'hold' : 'show';
    if (this.announceTimer) window.clearTimeout(this.announceTimer);
    if (!hold) this.announceTimer = window.setTimeout(() => (a.className = ''), ms);
  }

  clearAnnounce() {
    this.announceEl.className = '';
  }

  toast(text: string, cls = 'gold', sub = '') {
    const t = h('div', { class: `toast ${cls}` }, text, sub ? h('small', null, sub) : null);
    this.toastEl.appendChild(t);
    while (this.toastEl.children.length > 3) this.toastEl.firstChild!.remove();
    window.setTimeout(() => t.remove(), 1150);
  }

  // ------------------------------------------------------------------ events

  handleEvents(events: SimEvent[], world: World, match: Match) {
    const me = this.playerIndex;
    const W = world;
    if (this.versus) return this.handleVersusEvents(events, world, match);
    for (const e of events) {
      switch (e.t) {
        case 'roundStart':
          this.roundK.textContent = ROUND_KANJI[(e.round - 1) % 9];
          this.roundE.textContent = `Round ${e.round}`;
          if (!this.training) this.announce(`第${ROUND_KANJI[(e.round - 1) % 9]}戦`, `Round ${e.round}`, match.wins[0] === 2 && match.wins[1] === 2 ? 'Final round' : '');
          break;
        case 'fight':
          if (!this.training) this.announce('始め', 'Fight', '', false, 900);
          break;
        case 'parry': {
          const mine = e.parrier === me || this.watch;
          const label = e.kind === 'flash' ? 'Flash' : e.kind === 'redirect' ? 'Redirect' : 'Parry';
          if (e.parrier === me || this.watch || e.attacker === me) {
            const sub = this.training && e.parrier === me ? `${e.timing} frame${e.timing === 1 ? '' : 's'} before impact · window ${e.window}` : e.attacker === me && !this.watch ? 'Your attack was deflected' : '';
            this.toast(label, mine ? (e.kind === 'parry' ? 'gold' : 'jade') : 'red', sub);
          }
          break;
        }
        case 'counter': {
          const names = { stomp: 'Stomp counter', leap: 'Leap counter', evade: 'Evade counter' };
          const mine = e.by === me;
          const sub = e.kind === 'evade' && mine ? `Press ${this.labelFn('light')} now to lunge` : mine ? 'They are stunned: attack' : this.watch ? '' : 'You were countered';
          this.toast(names[e.kind], mine || this.watch ? 'jade' : 'red', sub);
          break;
        }
        case 'disarm':
          this.announce('武器喪失', 'Disarmed', e.victim === me && !this.watch ? 'Retrieve your weapon or fight bare-handed' : e.victim === 1 - me && !this.watch ? 'Stand between them and their blade' : '', false, 1500);
          break;
        case 'ko': {
          if (this.training) break;
          if (e.winner < 0) this.announce('相打ち', 'Double K.O.', '', false, 2200);
          else this.announce('一本', 'K.O.', '', false, 2000);
          break;
        }
        case 'roundOver': {
          if (this.training) break;
          const sub = e.winner < 0 ? 'The round will be replayed' : e.perfect ? 'Perfect' : '';
          const who = e.winner < 0 ? '' : this.watch ? `${this.sides[e.winner].name.textContent} wins the round` : e.winner === me ? 'You win the round' : 'You lose the round';
          window.setTimeout(() => this.announce(e.winner === me || this.watch ? '勝' : '敗', who || 'Draw', sub, false, 1600), 1300);
          break;
        }
        case 'ultReady':
          if (e.f === me && !this.watch) this.toast('Ultimate ready', 'gold', 'Light + Heavy together');
          break;
        case 'ultStart':
          if (e.f !== me || this.watch) this.toast('Ultimate', 'red', this.watch ? '' : 'Get ready to evade');
          break;
        case 'backstabReady':
          if (e.f === me) this.toast('Behind them', 'jade', 'Light attack to backstab');
          break;
        case 'hit':
          if (e.backstab) this.toast('Backstab', 'jade');
          if (this.training && e.target === me) this.checkEarly(W, e.attacker);
          if (e.target === me) this.lateWatch = { frame: W.frame, window: W.fighters[me].moveset.parryWindow };
          break;
        case 'block':
          if (this.training && e.target === me) this.checkEarly(W, e.attacker);
          if (e.target === me) this.lateWatch = { frame: W.frame, window: W.fighters[me].moveset.parryWindow };
          break;
        case 'stagger':
          if (e.f === me) this.toast('Dazed', 'red', 'Posture broken');
          break;
        case 'evade':
          if (e.f === me && this.training) this.toast('Evaded', 'dim');
          break;
      }
    }
  }

  /** Two players on one screen: neutral announcements that name who did what. */
  private handleVersusEvents(events: SimEvent[], world: World, match: Match) {
    for (const e of events) {
      switch (e.t) {
        case 'roundStart':
          this.roundK.textContent = ROUND_KANJI[(e.round - 1) % 9];
          this.roundE.textContent = `Round ${e.round}`;
          this.announce(`第${ROUND_KANJI[(e.round - 1) % 9]}戦`, `Round ${e.round}`, match.wins[0] === 2 && match.wins[1] === 2 ? 'Final round' : '');
          break;
        case 'fight':
          this.announce('始め', 'Fight', '', false, 900);
          break;
        case 'parry':
          this.toast(`${this.nameOf(e.parrier)}: ${e.kind === 'flash' ? 'Flash' : e.kind === 'redirect' ? 'Redirect' : 'Parry'}`, e.parrier === 0 ? 'red' : 'jade');
          break;
        case 'counter': {
          const names = { stomp: 'Stomp counter', leap: 'Leap counter', evade: 'Evade counter' };
          this.toast(`${this.nameOf(e.by)}: ${names[e.kind]}`, e.by === 0 ? 'red' : 'jade');
          break;
        }
        case 'disarm':
          this.announce('武器喪失', 'Disarmed', `${this.nameOf(e.victim)} lost their weapon`, false, 1500);
          break;
        case 'ultStart':
          this.toast(`${this.nameOf(e.f)}: Ultimate`, 'gold');
          break;
        case 'ko':
          if (e.winner < 0) this.announce('相打ち', 'Double K.O.', '', false, 2200);
          else this.announce('一本', 'K.O.', '', false, 2000);
          break;
        case 'roundOver': {
          const who = e.winner < 0 ? 'Draw' : `${this.nameOf(e.winner)} wins the round`;
          window.setTimeout(() => this.announce('勝', who, e.perfect ? 'Perfect' : '', false, 1600), 1300);
          break;
        }
        case 'backstabReady':
          this.toast(`${this.nameOf(e.f)}: behind them`, 'dim');
          break;
      }
    }
    void world;
  }

  /** Training feedback: was the block pressed a little too early? */
  private checkEarly(W: World, attacker: number) {
    const p = W.fighters[this.playerIndex];
    const d = W.frame - p.blockPressFrame;
    const win = p.parryWindowAtPress || p.moveset.parryWindow;
    if (d > win && d <= win + 20) this.toast('Too early', 'dim', `Parry pressed ${d - win} frame${d - win === 1 ? '' : 's'} too early`);
    void attacker;
  }

  /** Training feedback: block pressed just after being hit. */
  checkLate(W: World) {
    if (!this.training || !this.lateWatch) return;
    const p = W.fighters[this.playerIndex];
    const since = W.frame - this.lateWatch.frame;
    if (since > 14) {
      this.lateWatch = null;
      return;
    }
    if (p.blockPressFrame > this.lateWatch.frame) {
      const late = p.blockPressFrame - this.lateWatch.frame;
      this.toast('Too late', 'dim', `Parry pressed ${late} frame${late === 1 ? '' : 's'} after impact`);
      this.lateWatch = null;
    }
  }

  // ------------------------------------------------------------------ per frame

  update(world: World, match: Match, view: View, label: LabelFn | ((a: string, player: number) => string), dt: number) {
    world.fighters.forEach((f, i) => {
      const s = this.sides[i];
      const hp = Math.max(0, f.hp / HP_MAX);
      s.hpFill.style.width = `${hp * 100}%`;
      if (hp < s.lag) {
        s.lagHold += dt;
        if (s.lagHold > 0.45) s.lag = Math.max(hp, s.lag - dt * 0.6);
      } else {
        s.lag = hp;
        s.lagHold = 0;
      }
      s.hpLag.style.width = `${s.lag * 100}%`;
      s.hp.classList.toggle('low', hp <= 0.25 && hp > 0);
      const p = f.posture / POSTURE_MAX;
      s.postureFill.style.width = `${p * 100}%`;
      s.posture.classList.toggle('hot', p >= 0.7 && p < 1);
      s.posture.classList.toggle('full', p >= 0.999);
      s.pips.forEach((pip, k) => pip.classList.toggle('on', match.wins[i] > k));
      s.ult.classList.toggle('ready', f.canUlt());
      s.ult.classList.toggle('used', f.ultUsed && f.hp <= 25);
      s.tag.hidden = f.armed;
    });
    this.checkLate(world);
    const players = this.watch ? [] : this.versus ? [0, 1] : [this.playerIndex];
    for (let slot = 0; slot < 2; slot++) {
      const p = players[slot];
      if (p === undefined) {
        this.markerEls[slot].hidden = true;
        if (this.lastPrompt[slot]) {
          this.promptEls[slot].innerHTML = '';
          this.lastPrompt[slot] = '';
        }
        continue;
      }
      this.updatePrompts(world, (a) => (label as (a: string, p: number) => string)(a, p), p, slot);
      this.updateMarker(world, view, p, slot);
    }
  }

  private updatePrompts(world: World, label: LabelFn, player: number, slot: number) {
    if (!this.showHints) {
      if (this.lastPrompt[slot]) {
        this.promptEls[slot].innerHTML = '';
        this.lastPrompt[slot] = '';
      }
      return;
    }
    const me = world.fighters[player];
    const k = (a: string) => `<kbd>${label(a)}</kbd>`;
    const hints: { html: string; urgent?: boolean }[] = [];
    if (me.state === 'ultChoice') hints.push({ html: `${k('light')} Recall your weapon &nbsp;·&nbsp; ${k('heavy')} Breaker Palm`, urgent: true });
    else if (me.state === 'ult' && me.ult?.kind === 'moonsplitter' && me.ult.phase === 'windup')
      hints.push({ html: `Tilt ${k('up')}/${k('down')} vertical slash &nbsp;·&nbsp; ${k('left')}/${k('right')} horizontal`, urgent: true });
    else if (me.state === 'ult' && me.ult?.kind === 'impaler' && me.ult.phase === 'impale') hints.push({ html: `Press ${k('heavy')} to detonate`, urgent: true });
    if (world.frame <= me.counterLungeUntil) hints.push({ html: `Counter lunge: ${k('light')}`, urgent: true });
    if (!me.armed) {
      const w = world.weaponOf(me.id);
      if (w && w.grounded && Math.hypot(w.pos.x - me.pos.x, w.pos.z - me.pos.z) < 2.2) hints.push({ html: `Pick up your weapon ${k('interact')}`, urgent: true });
    }
    if (me.canUlt() && me.state !== 'ult' && me.state !== 'ultChoice') {
      hints.push({ html: `Ultimate ready: ${k('light')} + ${k('heavy')}${label('ultimate') ? ` or ${k('ultimate')}` : ''}` });
    }
    const html = hints
      .slice(0, 2)
      .map((x) => `<div class="hint${x.urgent ? ' urgent' : ''}">${x.html}</div>`)
      .join('');
    if (html !== this.lastPrompt[slot]) {
      this.promptEls[slot].innerHTML = html;
      this.lastPrompt[slot] = html;
    }
  }

  private updateMarker(world: World, view: View, player: number, slot: number) {
    const me = world.fighters[player];
    const w = !me.armed ? world.weaponOf(me.id) : null;
    const m = this.markerEls[slot];
    if (!w) {
      m.hidden = true;
      return;
    }
    const pr = view.project(new THREE.Vector3(w.pos.x, 0.6, w.pos.z), player);
    const x0 = pr.x0;
    const W = pr.w;
    const H = window.innerHeight;
    const pad = 40;
    let x = pr.x;
    let y = pr.y;
    let edge = false;
    if (pr.behind || x < x0 + pad || x > x0 + W - pad || y < pad || y > H - pad) {
      edge = true;
      if (pr.behind) {
        x = x0 + W - (x - x0);
        y = H - pad;
      }
      x = Math.min(x0 + W - pad, Math.max(x0 + pad, x));
      y = Math.min(H - pad, Math.max(pad + 60, y));
    }
    const label = this.versus ? `${this.nameOf(player)}'s weapon` : 'Your weapon';
    m.hidden = false;
    m.classList.toggle('edge', edge);
    m.textContent = edge ? (x < x0 + W / 2 ? `◀ ${label}` : `${label} ▶`) : label;
    m.style.left = `${x}px`;
    m.style.top = `${y}px`;
  }
}
