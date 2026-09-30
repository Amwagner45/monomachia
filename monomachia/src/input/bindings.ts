// Control bindings and player profiles (saved in this browser).

export type Action =
  | 'up'
  | 'down'
  | 'left'
  | 'right'
  | 'light'
  | 'heavy'
  | 'block'
  | 'dodge'
  | 'jump'
  | 'interact'
  | 'ultimate'
  | 'sprint'
  | 'pause';

export const ACTIONS: { id: Action; label: string; hint?: string }[] = [
  { id: 'up', label: 'Move toward opponent' },
  { id: 'down', label: 'Move away' },
  { id: 'left', label: 'Circle left' },
  { id: 'right', label: 'Circle right' },
  { id: 'light', label: 'Light attack' },
  { id: 'heavy', label: 'Heavy attack', hint: 'hold to charge' },
  { id: 'block', label: 'Block / Parry', hint: 'hold / tap on impact' },
  { id: 'dodge', label: 'Dodge / Backstep' },
  { id: 'jump', label: 'Jump' },
  { id: 'interact', label: 'Pick up weapon' },
  { id: 'ultimate', label: 'Ultimate', hint: 'or light + heavy together' },
  { id: 'sprint', label: 'Sprint (hold)', hint: 'or double-tap a direction' },
  { id: 'pause', label: 'Pause' },
];

export type BindingSet = Record<Action, string[]>;

export interface Profile {
  name: string;
  kb: BindingSet;
  pad: BindingSet;
}

export const DEFAULT_KB: BindingSet = {
  up: ['k:KeyW', 'k:ArrowUp'],
  down: ['k:KeyS', 'k:ArrowDown'],
  left: ['k:KeyA', 'k:ArrowLeft'],
  right: ['k:KeyD', 'k:ArrowRight'],
  light: ['m:0', 'k:KeyJ'],
  heavy: ['m:2', 'k:KeyK'],
  block: ['k:ShiftLeft', 'k:KeyL'],
  dodge: ['k:Space'],
  jump: ['k:KeyF', 'k:KeyI'],
  interact: ['k:KeyE'],
  ultimate: ['k:KeyQ', 'k:KeyU'],
  sprint: [],
  pause: ['k:Escape', 'k:KeyP'],
};

export const DEFAULT_PAD: BindingSet = {
  up: ['b:12', 'a:1-'],
  down: ['b:13', 'a:1+'],
  left: ['b:14', 'a:0-'],
  right: ['b:15', 'a:0+'],
  light: ['b:5'],
  heavy: ['b:7'],
  block: ['b:4'],
  dodge: ['b:1'],
  jump: ['b:0'],
  interact: ['b:2'],
  ultimate: ['b:3'],
  sprint: ['b:10'],
  pause: ['b:9'],
};

/** 8-button fight-stick layout: top row □ △ R1 L1, bottom row ✕ ○ R2 L2. */
export const FIGHTSTICK_PAD: BindingSet = {
  up: ['b:12', 'a:1-'],
  down: ['b:13', 'a:1+'],
  left: ['b:14', 'a:0-'],
  right: ['b:15', 'a:0+'],
  light: ['b:2'],
  heavy: ['b:3'],
  block: ['b:5'],
  dodge: ['b:1'],
  jump: ['b:0'],
  interact: ['b:7'],
  ultimate: ['b:4'],
  sprint: ['b:6'],
  pause: ['b:9'],
};

/** Right-hand keyboard layout for a second player sharing the keyboard. */
export const KB_ARROWS: BindingSet = {
  up: ['k:ArrowUp'],
  down: ['k:ArrowDown'],
  left: ['k:ArrowLeft'],
  right: ['k:ArrowRight'],
  light: ['k:KeyJ', 'k:Numpad4'],
  heavy: ['k:KeyK', 'k:Numpad5'],
  block: ['k:KeyL', 'k:Numpad6'],
  dodge: ['k:Semicolon', 'k:Numpad0'],
  jump: ['k:KeyI', 'k:Numpad8'],
  interact: ['k:KeyO', 'k:Numpad9'],
  ultimate: ['k:KeyU', 'k:Numpad7'],
  sprint: [],
  pause: ['k:Backspace', 'k:NumpadEnter'],
};

export function tokensOf(set: BindingSet): Set<string> {
  return new Set(Object.values(set).flat());
}

const clone = (b: BindingSet): BindingSet => JSON.parse(JSON.stringify(b));

export function defaultProfile(name = 'Player 1'): Profile {
  return { name, kb: clone(DEFAULT_KB), pad: clone(DEFAULT_PAD) };
}

const KEY = 'monomachia.profiles.v1';

export interface ProfileStore {
  active: number;
  profiles: Profile[];
}

export function loadProfiles(): ProfileStore {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const s = JSON.parse(raw) as ProfileStore;
      if (Array.isArray(s.profiles) && s.profiles.length) {
        // fill in any actions added since the profile was saved
        for (const p of s.profiles) {
          for (const a of ACTIONS) {
            p.kb[a.id] ??= [...DEFAULT_KB[a.id]];
            p.pad[a.id] ??= [...DEFAULT_PAD[a.id]];
          }
        }
        s.active = Math.min(Math.max(0, s.active | 0), s.profiles.length - 1);
        return s;
      }
    }
  } catch {
    /* storage unavailable or corrupt */
  }
  return { active: 0, profiles: [defaultProfile()] };
}

export function saveProfiles(s: ProfileStore) {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* ignore: private mode etc. */
  }
}

// ------------------------------------------------------------------ labels

const PS_BUTTONS = ['✕', '○', '□', '△', 'L1', 'R1', 'L2', 'R2', 'Create', 'Options', 'L3', 'R3', 'D-pad ↑', 'D-pad ↓', 'D-pad ←', 'D-pad →', 'PS', 'Touchpad'];
const XB_BUTTONS = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', 'View', 'Menu', 'LS', 'RS', 'D-pad ↑', 'D-pad ↓', 'D-pad ←', 'D-pad →', 'Guide'];

const KEY_NAMES: Record<string, string> = {
  ShiftLeft: 'L-Shift',
  ShiftRight: 'R-Shift',
  ControlLeft: 'L-Ctrl',
  ControlRight: 'R-Ctrl',
  AltLeft: 'L-Alt',
  AltRight: 'R-Alt',
  Space: 'Space',
  Escape: 'Esc',
  Enter: 'Enter',
  Tab: 'Tab',
  Backspace: 'Backspace',
  ArrowUp: '↑',
  ArrowDown: '↓',
  ArrowLeft: '←',
  ArrowRight: '→',
  CapsLock: 'Caps',
  Semicolon: ';',
  Quote: "'",
  Comma: ',',
  Period: '.',
  Slash: '/',
  BracketLeft: '[',
  BracketRight: ']',
  Backslash: '\\',
  Minus: '-',
  Equal: '=',
  Backquote: '`',
};

export function bindingLabel(token: string, style: 'ps' | 'xbox' | 'generic' = 'generic'): string {
  const [kind, rest] = [token.slice(0, 1), token.slice(2)];
  if (kind === 'k') {
    if (KEY_NAMES[rest]) return KEY_NAMES[rest];
    if (rest.startsWith('Key')) return rest.slice(3);
    if (rest.startsWith('Digit')) return rest.slice(5);
    if (rest.startsWith('Numpad')) return 'Num ' + rest.slice(6);
    return rest;
  }
  if (kind === 'm') return ['Left Click', 'Middle Click', 'Right Click', 'Mouse 4', 'Mouse 5'][Number(rest)] ?? `Mouse ${rest}`;
  if (kind === 'b') {
    const i = Number(rest);
    if (style === 'ps') return PS_BUTTONS[i] ?? `Button ${i}`;
    if (style === 'xbox') return XB_BUTTONS[i] ?? `Button ${i}`;
    return `Button ${i}`;
  }
  if (kind === 'a') {
    const axis = rest.slice(0, -1);
    const dir = rest.slice(-1);
    if (axis === '0') return dir === '-' ? 'Stick ←' : 'Stick →';
    if (axis === '1') return dir === '-' ? 'Stick ↑' : 'Stick ↓';
    return `Axis ${axis}${dir}`;
  }
  return token;
}
