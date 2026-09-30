// Keyboard, mouse and gamepad reading. Turns physical inputs into the
// simulation's RawInput using a profile's bindings. Supports several
// controllers so two people can play on one screen.

import { B, RawInput } from '../sim/input';
import { Action, BindingSet, KB_ARROWS, Profile } from './bindings';

export type MenuNav = 'up' | 'down' | 'left' | 'right' | 'ok' | 'back' | 'pause';
/** 'all' = keyboard, mouse and the first controller together (single player). */
export type DeviceId = 'all' | 'kbm' | 'pad0' | 'pad1' | 'kbArrows';

const GAME_KEYS = new Set([
  'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab', 'ShiftLeft', 'ShiftRight', 'Semicolon',
  'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyF', 'KeyQ', 'KeyE', 'KeyJ', 'KeyK', 'KeyL', 'KeyI', 'KeyU', 'KeyO',
]);

const ACTION_BUTTON: Partial<Record<Action, B>> = {
  light: B.Light,
  heavy: B.Heavy,
  block: B.Block,
  dodge: B.Dodge,
  jump: B.Jump,
  interact: B.Interact,
  ultimate: B.Ultimate,
  sprint: B.Sprint,
};

type PadStyle = 'ps' | 'xbox' | 'generic';

function styleOf(pad: Gamepad): PadStyle {
  const id = pad.id.toLowerCase();
  // Xbox first: "Xbox Wireless Controller" would otherwise match the PlayStation
  // pad's generic "Wireless Controller" name
  if (/xbox|xinput|045e/.test(id)) return 'xbox';
  if (/054c|dualsense|dualshock|wireless controller|playstation|ps4|ps5|qanba/.test(id)) return 'ps';
  return 'generic';
}

export class InputDevices {
  keys = new Set<string>();
  mouse = new Set<number>();
  /** connected controllers in order */
  pads: Gamepad[] = [];
  padBlocked = false;
  lastDevice: 'kb' | 'pad' = 'kb';
  menuQueue: MenuNav[] = [];
  /** when false, keyboard events go to menus only */
  gameActive = false;

  private hatRest = new Map<string, boolean>();
  private prevButtons = new Map<number, boolean[]>();
  private prevNav = new Map<number, { up: boolean; down: boolean; left: boolean; right: boolean }>();
  private navRepeatAt = new Map<number, number>();
  private capture: { kind: 'kb' | 'pad'; cb: (t: string | null) => void; armed: boolean; rest: Map<number, number[]> } | null = null;
  private pausePrev = new Map<string, boolean>();

  constructor(private surface: HTMLElement) {
    window.addEventListener('keydown', (e) => this.onKey(e, true));
    window.addEventListener('keyup', (e) => this.onKey(e, false));
    surface.addEventListener('mousedown', (e) => {
      if (this.capture?.kind === 'kb') {
        e.preventDefault();
        this.finishCapture('m:' + e.button);
        return;
      }
      if (!this.gameActive) return;
      this.mouse.add(e.button);
      this.lastDevice = 'kb';
      e.preventDefault();
    });
    window.addEventListener('mouseup', (e) => this.mouse.delete(e.button));
    surface.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('blur', () => {
      this.keys.clear();
      this.mouse.clear();
    });
    window.addEventListener('gamepadconnected', () => this.poll());
  }

  /** The first controller (menus, button labels). */
  get pad(): Gamepad | null {
    return this.pads[0] ?? null;
  }

  get padStyle(): PadStyle {
    return this.pad ? styleOf(this.pad) : 'generic';
  }

  padStyleFor(device: DeviceId): PadStyle {
    const p = this.padAt(device === 'pad1' ? 1 : 0);
    return p ? styleOf(p) : 'generic';
  }

  // Controller seats. During a two-player match each seat is tied to one
  // physical controller (by the browser's controller number), so unplugging
  // controller 1 can never hand player 2's controller to player 1.
  private seats: (number | null)[] = [null, null];
  private seated = false;

  /** Tie seat 1 and seat 2 to the controllers connected right now. */
  bindSeats() {
    this.seated = true;
    this.seats = [this.pads[0]?.index ?? null, this.pads[1]?.index ?? null];
  }

  /** Back to "first controller / second controller" in connection order. */
  unbindSeats() {
    this.seated = false;
    this.seats = [null, null];
  }

  padAt(seat: 0 | 1): Gamepad | undefined {
    if (!this.seated) return this.pads[seat];
    let idx = this.seats[seat];
    if (idx == null) {
      // a controller plugged in after the match began takes the empty seat
      const taken = this.seats[1 - seat];
      const free = this.pads.find((p) => p.index !== taken);
      if (!free) return undefined;
      this.seats[seat] = idx = free.index;
    }
    return this.pads.find((p) => p.index === idx);
  }

  private isTyping(e: KeyboardEvent) {
    const t = e.target as HTMLElement | null;
    return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
  }

  private onKey(e: KeyboardEvent, down: boolean) {
    if (this.isTyping(e)) return;
    if (this.capture?.kind === 'kb' && down) {
      e.preventDefault();
      if (e.code === 'Escape') this.finishCapture(null);
      else this.finishCapture('k:' + e.code);
      return;
    }
    if (this.capture?.kind === 'pad' && down && e.code === 'Escape') {
      e.preventDefault();
      this.finishCapture(null);
      return;
    }
    if (down) {
      this.lastDevice = 'kb';
      if (!e.repeat) this.keys.add(e.code);
      if (!this.gameActive || e.code === 'Escape') {
        const nav: Record<string, MenuNav> = {
          ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left',
          ArrowRight: 'right', KeyD: 'right', Enter: 'ok', Space: 'ok', Escape: 'back', Backspace: 'back',
        };
        const n = nav[e.code];
        if (n) this.menuQueue.push(n);
      }
      if (GAME_KEYS.has(e.code) || (this.gameActive && (e.code.startsWith('Key') || e.code.startsWith('Numpad')))) e.preventDefault();
    } else {
      this.keys.delete(e.code);
    }
  }

  // ------------------------------------------------------------------ gamepads

  poll(now = performance.now()) {
    let raw: (Gamepad | null)[] = [];
    try {
      raw = navigator.getGamepads ? Array.from(navigator.getGamepads()) : [];
      this.padBlocked = false;
    } catch {
      this.padBlocked = true;
    }
    this.pads = raw.filter((p): p is Gamepad => !!p && p.connected).sort((a, b) => a.index - b.index);

    for (const pad of this.pads) {
      const prev = this.prevButtons.get(pad.index) ?? [];
      const pressed = pad.buttons.map((b) => b.pressed || b.value > 0.5);
      const fresh = (i: number) => pressed[i] && !prev[i];
      if (pressed.some((p, i) => p && !prev[i]) || pad.axes.some((a, i) => !this.isHat(pad, i) && Math.abs(a) > 0.6)) this.lastDevice = 'pad';

      // rebinding capture from any controller
      if (this.capture?.kind === 'pad') {
        const c = this.capture;
        if (!c.armed) {
          if (!pressed.some(Boolean)) {
            c.armed = true;
            c.rest.set(pad.index, [...pad.axes]);
          }
        } else {
          const rest = c.rest.get(pad.index) ?? pad.axes.map(() => 0);
          const bi = pressed.findIndex((p, i) => p && !prev[i]);
          if (bi >= 0) this.finishCapture('b:' + bi);
          else {
            for (let i = 0; i < pad.axes.length; i++) {
              if (this.isHat(pad, i)) continue;
              const d = pad.axes[i] - (rest[i] ?? 0);
              if (Math.abs(d) > 0.6) {
                this.finishCapture(`a:${i}${d < 0 ? '-' : '+'}`);
                break;
              }
            }
          }
        }
      }

      if (!this.capture) {
        const dir = this.padDirs(pad);
        const pn = this.prevNav.get(pad.index) ?? { up: false, down: false, left: false, right: false };
        const rep = this.navRepeatAt.get(pad.index) ?? 0;
        for (const k of ['up', 'down', 'left', 'right'] as const) {
          if (dir[k] && (!pn[k] || now > rep)) {
            if (!this.gameActive) this.menuQueue.push(k);
            this.navRepeatAt.set(pad.index, now + (pn[k] ? 120 : 380));
          }
        }
        this.prevNav.set(pad.index, dir);
        if (!this.gameActive) {
          if (fresh(0)) this.menuQueue.push('ok');
          if (fresh(1)) this.menuQueue.push('back');
        }
        if (fresh(9)) this.menuQueue.push('pause');
      }
      this.prevButtons.set(pad.index, pressed);
    }
  }

  private isHat(pad: Gamepad, i: number) {
    if (pad.mapping === 'standard') return false;
    const key = `${pad.index}:${i}`;
    if (this.hatRest.get(key)) return true;
    if (Math.abs(pad.axes[i]) > 1.05) {
      this.hatRest.set(key, true);
      return true;
    }
    return false;
  }

  /** Digital directions from D-pad buttons, the left stick and hat switches. */
  private padDirs(pad: Gamepad) {
    const b = (i: number) => !!pad.buttons[i] && (pad.buttons[i].pressed || pad.buttons[i].value > 0.5);
    let up = b(12);
    let down = b(13);
    let left = b(14);
    let right = b(15);
    const ax = pad.axes[0] ?? 0;
    const ay = pad.axes[1] ?? 0;
    if (!this.isHat(pad, 0) && !this.isHat(pad, 1)) {
      up ||= ay < -0.55;
      down ||= ay > 0.55;
      left ||= ax < -0.55;
      right ||= ax > 0.55;
    }
    for (let i = 0; i < pad.axes.length; i++) {
      if (!this.isHat(pad, i)) continue;
      const v = pad.axes[i];
      if (v < -1.05 || v > 1.05) continue;
      // hat values step by 2/7 clockwise from up (-1)
      const idx = Math.round((v + 1) / (2 / 7));
      const dirs = [
        [1, 0, 0, 0], [1, 0, 0, 1], [0, 0, 0, 1], [0, 1, 0, 1],
        [0, 1, 0, 0], [0, 1, 1, 0], [0, 0, 1, 0], [1, 0, 1, 0],
      ][((idx % 8) + 8) % 8];
      up ||= !!dirs[0];
      down ||= !!dirs[1];
      left ||= !!dirs[2];
      right ||= !!dirs[3];
    }
    return { up, down, left, right };
  }

  // ------------------------------------------------------------------ sampling

  private kbValue(tok: string): number {
    if (tok.startsWith('k:')) return this.keys.has(tok.slice(2)) ? 1 : 0;
    if (tok.startsWith('m:')) return this.mouse.has(Number(tok.slice(2))) ? 1 : 0;
    return 0;
  }

  private padValue(tok: string, pad: Gamepad | undefined): number {
    if (!pad) return 0;
    if (tok.startsWith('b:')) {
      const b = pad.buttons[Number(tok.slice(2))];
      if (!b) return 0;
      return b.pressed || b.value > 0.4 ? 1 : 0;
    }
    if (tok.startsWith('a:')) {
      const body = tok.slice(2);
      const i = Number(body.slice(0, -1));
      const sign = body.endsWith('-') ? -1 : 1;
      if (this.isHat(pad, i)) return 0;
      const v = (pad.axes[i] ?? 0) * sign;
      return v > 0.25 ? Math.min(1, (v - 0.25) / 0.6 + 0.35) : 0;
    }
    return 0;
  }

  /** Which binding sets and controller a device reads. */
  private sources(profile: Profile, device: DeviceId): { kb: BindingSet | null; pad: Gamepad | undefined; padSet: BindingSet | null } {
    switch (device) {
      case 'kbm':
        return { kb: profile.kb, pad: undefined, padSet: null };
      case 'kbArrows':
        return { kb: KB_ARROWS, pad: undefined, padSet: null };
      case 'pad0':
        return { kb: null, pad: this.padAt(0), padSet: profile.pad };
      case 'pad1':
        return { kb: null, pad: this.padAt(1), padSet: profile.pad };
      default:
        return { kb: profile.kb, pad: this.pads[0], padSet: profile.pad };
    }
  }

  actionValue(profile: Profile, a: Action, device: DeviceId = 'all', exclude?: Set<string>): number {
    const src = this.sources(profile, device);
    let v = 0;
    if (src.kb) for (const t of src.kb[a] ?? []) if (!exclude?.has(t)) v = Math.max(v, this.kbValue(t));
    if (src.pad && src.padSet) for (const t of src.padSet[a] ?? []) v = Math.max(v, this.padValue(t, src.pad));
    return v;
  }

  sample(profile: Profile, device: DeviceId = 'all', exclude?: Set<string>): RawInput {
    const val = (a: Action) => this.actionValue(profile, a, device, exclude);
    let up = val('up');
    let down = val('down');
    let left = val('left');
    let right = val('right');
    const pad = this.sources(profile, device).pad;
    if (pad && pad.mapping !== 'standard') {
      const h = this.padDirs(pad);
      up = Math.max(up, h.up ? 1 : 0);
      down = Math.max(down, h.down ? 1 : 0);
      left = Math.max(left, h.left ? 1 : 0);
      right = Math.max(right, h.right ? 1 : 0);
    }
    let mx = right - left;
    let my = up - down;
    const m = Math.hypot(mx, my);
    if (m > 1) {
      mx /= m;
      my /= m;
    }
    let buttons = 0;
    for (const [a, b] of Object.entries(ACTION_BUTTON) as [Action, B][]) {
      if (val(a) > 0.5) buttons |= 1 << b;
    }
    return { mx, my, buttons };
  }

  /** Edge-detected pause press for in-game use. */
  pausePressed(profile: Profile, device: DeviceId = 'all', exclude?: Set<string>): boolean {
    const v = this.actionValue(profile, 'pause', device, exclude) > 0.5;
    const edge = v && !this.pausePrev.get(device);
    this.pausePrev.set(device, v);
    return edge;
  }

  // ------------------------------------------------------------------ rebinding

  startCapture(kind: 'kb' | 'pad', cb: (token: string | null) => void) {
    this.capture = { kind, cb, armed: false, rest: new Map() };
    this.keys.clear();
    this.mouse.clear();
  }

  cancelCapture() {
    this.capture = null;
  }

  get capturing() {
    return !!this.capture;
  }

  private finishCapture(tok: string | null) {
    const c = this.capture;
    this.capture = null;
    this.keys.clear();
    this.mouse.clear();
    if (c) c.cb(tok);
  }

  drainMenu(): MenuNav[] {
    const q = this.menuQueue;
    this.menuQueue = [];
    return q;
  }
}
